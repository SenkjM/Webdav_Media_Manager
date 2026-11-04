import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/transcode_preset.dart';
import '../models/video_encoder_catalog.dart';
import '../services/codec_capability_service.dart';
import '../services/rust_core_service.dart';
import '../utils/app_snack.dart';

/// 转码预设管理页面。
///
/// 预设是三层方案（契约 `preset-editor-slimming` §4）：
/// 流复制 → 硬件编码器 → 软件编码器，编码层共享一套码率控制。
/// 内置只有 `h264` / `hevc` 两个，可编辑、不可删除，并提供「恢复默认」。
class TranscodePresetsScreen extends StatefulWidget {
  const TranscodePresetsScreen({super.key});

  @override
  State<TranscodePresetsScreen> createState() => _TranscodePresetsScreenState();
}

class _TranscodePresetsScreenState extends State<TranscodePresetsScreen> {
  List<TranscodePreset>? _presets;
  String? _error;
  bool _loading = true;
  late VideoEncoderCatalog _catalog;

  @override
  void initState() {
    super.initState();
    _catalog =
        VideoEncoderCatalog.parse(RustCoreService.videoEncoderCatalogJson());
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jsonStr = RustCoreService.transcodePresetsJson();
      if (jsonStr == null) {
        throw Exception('FFI not loaded');
      }
      if (jsonStr.startsWith('error:')) {
        throw Exception(jsonStr.substring(6));
      }
      final decoded = jsonDecode(jsonStr) as List<dynamic>;
      final presets = decoded
          .map((e) => TranscodePreset.fromJson(e as Map<String, dynamic>))
          .toList();
      presets.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      setState(() {
        _presets = presets;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deletePreset(TranscodePreset preset) async {
    if (preset.isBuiltin) {
      AppSnack.show(context, '内置预设不能删除');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除预设 "${preset.label}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final result = RustCoreService.transcodePresetDelete(preset.id);
    if (result == null) {
      if (mounted) AppSnack.show(context, 'FFI 未加载');
      return;
    }
    if (result.startsWith('error:')) {
      if (mounted) AppSnack.show(context, '删除失败: ${result.substring(6)}');
      return;
    }
    if (mounted) AppSnack.show(context, '已删除');
    await _loadPresets();
  }

  /// 把内置预设恢复为出厂参数（FFI `wdmm_transcode_preset_reset`）。
  Future<void> _resetBuiltin(TranscodePreset preset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认'),
        content: Text('将「${preset.label}」恢复为出厂参数？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final result = RustCoreService.transcodePresetReset(preset.id);
    if (result == null) {
      if (mounted) {
        AppSnack.show(context, '当前原生库不支持恢复默认', error: true);
      }
      return;
    }
    if (result.startsWith('error:')) {
      if (mounted) AppSnack.show(context, '恢复失败: ${result.substring(6)}');
      return;
    }
    if (mounted) AppSnack.show(context, '已恢复默认');
    await _loadPresets();
  }

  Future<void> _editPreset(TranscodePreset? preset) async {
    final result = await Navigator.push<TranscodePreset>(
      context,
      MaterialPageRoute(
        builder: (_) => _TranscodePresetEditScreen(
          preset: preset,
          catalog: _catalog,
        ),
      ),
    );
    if (result != null) {
      await _loadPresets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('转码预设'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPresets,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '加载失败: $_error',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                )
              : _presets == null || _presets!.isEmpty
                  ? const Center(child: Text('无预设'))
                  : ListView.builder(
                      itemCount: _presets!.length,
                      itemBuilder: (ctx, i) {
                        final preset = _presets![i];
                        return ListTile(
                          title: Text(preset.label),
                          subtitle: Text(
                            '${_videoSummary(preset)} · ${_audioSummary(preset)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (preset.isBuiltin)
                                Chip(
                                  label: const Text('内置'),
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                ),
                              _buildPresetMenu(preset),
                            ],
                          ),
                          onTap: () => _editPreset(preset),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editPreset(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 每行只留一个「更多」菜单：编辑 / 恢复默认 / 删除。
  Widget _buildPresetMenu(TranscodePreset preset) {
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      onSelected: (action) {
        if (action == 'edit') {
          unawaited(_editPreset(preset));
        } else if (action == 'reset') {
          unawaited(_resetBuiltin(preset));
        } else if (action == 'delete') {
          unawaited(_deletePreset(preset));
        }
      },
      itemBuilder: (ctx) => [
        _menuItem('edit', Icons.edit_outlined, '编辑'),
        if (preset.isBuiltin)
          _menuItem('reset', Icons.restore, '恢复默认'),
        if (!preset.isBuiltin) _menuItem('delete', Icons.delete_outline, '删除'),
      ],
    );
  }

  static PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  /// 列表副标题：视频命中层摘要（复制 / 硬编 / 软编 / 无）。
  String _videoSummary(TranscodePreset preset) {
    if (preset.videoCopy) return '视频: 复制';
    if (preset.hwVideoEncoder.isNotEmpty) {
      return '视频: 硬编 ${_catalog.labelOf(preset.hwVideoEncoder)}';
    }
    if (preset.swVideoEncoder.isNotEmpty) {
      return '视频: 软编 ${_catalog.labelOf(preset.swVideoEncoder)}';
    }
    return '视频: 无';
  }

  /// 列表副标题：音频命中层摘要（复制 / 编码）。
  static String _audioSummary(TranscodePreset preset) {
    if (preset.audioCopy) return '音频: 复制';
    return '音频: ${preset.audioCodec.toUpperCase()} '
        '${preset.audioBitrate ~/ 1000}kbps';
  }
}

/// 转码预设编辑页面。
///
/// 全部为可视化控件（契约 §4）：码率控制用 `Wrap` + `ChoiceChip`，恒定质量
/// 时隐藏目标码率；编码器列表来自 [VideoEncoderCatalog]（旧 `.so` 缺符号时
/// 用内置 6 条目录兜底），不提供任何命令行式 key=value 输入。
class _TranscodePresetEditScreen extends StatefulWidget {
  final TranscodePreset? preset;
  final VideoEncoderCatalog catalog;

  const _TranscodePresetEditScreen({this.preset, required this.catalog});

  @override
  State<_TranscodePresetEditScreen> createState() =>
      _TranscodePresetEditScreenState();
}

class _TranscodePresetEditScreenState
    extends State<_TranscodePresetEditScreen> {
  /// 编辑器只展示三档码率控制（契约 §4）；`auto` 是旧值，读入时归一为 VBR。
  static const List<String> _kRateControlOrder = ['cq', 'vbr', 'cbr'];

  static const Map<String, String> _kRateControlLabels = {
    'cq': '恒定质量',
    'vbr': '可变码率',
    'cbr': '恒定码率',
  };

  static const Map<String, String> _kRateControlHints = {
    'vbr': '按画面复杂度动态分配码率，兼容性最好',
    'cbr': '码率恒定，适合弱网/老设备，画质波动更大',
    'cq': '恒定质量，码率随画面变化，体积不可控',
  };

  /// x264 速度挡位（只暴露三档，不展示编码器底层 preset 名）。
  static const Map<String, String> _kSpeedPresetLabels = {
    'veryfast': '快速',
    'medium': '均衡',
    'slow': '高质量',
  };

  /// CQ 质量可选值（契约 §4）。
  static const List<int> _kQualityValues = [18, 20, 23, 26, 30];

  /// 目标码率快捷选项（Mbps；`null` = 自动推导）。
  static const List<int?> _kBitrateChoices = [null, 2, 4, 6, 8];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _idController;
  late final TextEditingController _labelController;
  late final TextEditingController _videoMaxWController;
  late final TextEditingController _videoMaxHController;
  late final TextEditingController _videoBitrateMbpsController;
  late final TextEditingController _videoFpsCapController;
  late final TextEditingController _audioBitrateController;
  late final TextEditingController _audioSampleRateController;
  late final TextEditingController _hlsSegmentSecsController;
  late final TextEditingController _sortOrderController;

  late final VideoEncoderCatalog _catalog;
  late final CodecCapabilityService _caps;

  bool _videoCopy = false;
  bool _audioCopy = false;
  String _hwVideoEncoder = '';
  String _swVideoEncoder = '';
  String _swVideoPreset = 'veryfast';
  String _videoRateControl = 'vbr';
  int _videoQuality = 23;
  String _audioCodec = 'aac';
  int _audioChannels = 2;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    // 机型编码能力：探测失败时 API 保守放行，不会挡住保存/投屏。
    _caps = CodecCapabilityService.shared;
    _caps.addListener(_onCapsChanged);
    unawaited(_caps.load());
    final p = widget.preset;
    _idController = TextEditingController(text: p?.id ?? '');
    _labelController = TextEditingController(text: p?.label ?? '');
    _videoMaxWController =
        TextEditingController(text: p?.videoMaxW?.toString() ?? '');
    _videoMaxHController =
        TextEditingController(text: p?.videoMaxH?.toString() ?? '');
    _videoBitrateMbpsController =
        TextEditingController(text: _formatMbps(p?.videoMaxBitrate));
    _videoFpsCapController =
        TextEditingController(text: p?.videoFpsCap?.toString() ?? '');
    _audioBitrateController =
        TextEditingController(text: (p?.audioBitrate ?? 128000).toString());
    _audioSampleRateController =
        TextEditingController(text: p?.audioSampleRate?.toString() ?? '');
    _hlsSegmentSecsController =
        TextEditingController(text: (p?.hlsSegmentSecs ?? 4).toString());
    _sortOrderController =
        TextEditingController(text: (p?.sortOrder ?? 100).toString());

    if (p != null) {
      _videoCopy = p.videoCopy;
      _audioCopy = p.audioCopy;
      _hwVideoEncoder = p.hwVideoEncoder;
      _swVideoEncoder = p.swVideoEncoder;
      _swVideoPreset = _nearestSpeedPreset(p.swVideoPreset);
      _videoRateControl = _kRateControlOrder.contains(p.videoRateControl)
          ? p.videoRateControl
          : 'vbr';
      _videoQuality = p.videoQuality ?? 23;
      _audioCodec = p.audioCodec;
      _audioChannels = p.audioChannels;
    }
  }

  /// 机型编码能力探测完成后刷新「置灰」，探测失败时保持全部可用。
  void _onCapsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _caps.removeListener(_onCapsChanged);
    _idController.dispose();
    _labelController.dispose();
    _videoMaxWController.dispose();
    _videoMaxHController.dispose();
    _videoBitrateMbpsController.dispose();
    _videoFpsCapController.dispose();
    _audioBitrateController.dispose();
    _audioSampleRateController.dispose();
    _hlsSegmentSecsController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  // ── 数值换算 ──────────────────────────────────────────────────────────────

  int? _intOrNull(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  /// 可留空的数值输入：留空合法，填了就必须是正整数（0 会写出无意义预设）。
  String? _positiveIntValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed <= 0) return '请输入正整数';
    return null;
  }

  /// 当前表单的推导码率（bps）。
  ///
  /// 与 Rust `default_video_bitrate` 同口径（crates/wdmm-ffmpeg/src/plan.rs）：
  /// `round(width × height × fps × 0.10)`，下限 800 kbps。编辑器不知道片源的真实
  /// 分辨率，未填上限时按 1920×1080@30 估算，与内置预设的默认包络一致。
  int get _derivedBitrate {
    final width = _intOrNull(_videoMaxWController) ?? 1920;
    final height = _intOrNull(_videoMaxHController) ?? 1080;
    final fps = _intOrNull(_videoFpsCapController) ?? 30;
    final derived = (width * height * fps * 0.10).round();
    return math.max(derived, 800000);
  }

  int? get _bitrateBps {
    final text = _videoBitrateMbpsController.text.trim();
    if (text.isEmpty) return null;
    final mbps = double.tryParse(text);
    if (mbps == null || mbps <= 0) return null;
    return (mbps * 1000000).round();
  }

  static String _formatMbps(int? bps) {
    if (bps == null || bps <= 0) return '';
    final mbps = bps / 1000000;
    var text = mbps.toStringAsFixed(6);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  /// 展示用的一两位小数版本（不参与回填，避免数值漂移）。
  static String _formatMbpsShort(int bps) =>
      (bps / 1000000).toStringAsFixed(1);

  /// 把任意历史 x264 preset 名归一到编辑器暴露的三档之一。
  static String _nearestSpeedPreset(String raw) {
    if (_kSpeedPresetLabels.containsKey(raw)) return raw;
    final index = TranscodePreset.x264Presets.indexOf(raw);
    if (index < 0) return 'medium';
    if (index <= 3) return 'veryfast';
    if (index <= 5) return 'medium';
    return 'slow';
  }

  // ── 码率控制 ──────────────────────────────────────────────────────────────

  /// 当前编码器组合是否支持某个码率控制模式。
  ///
  /// 需要同时满足：catalog 声明该编码器支持该模式，且机型探测没有明确否认
  /// （硬编）；探测不可用时 [CodecCapabilityService] 保守放行。只复制、没有
  /// 编码器时三档都可用（模式不会真正生效）。
  bool _rateModeEnabled(String mode) {
    final hw = _hwVideoEncoder;
    final sw = _swVideoEncoder;
    if (hw.isEmpty && sw.isEmpty) return true;
    final hwSupported = hw.isNotEmpty &&
        _caps.supportsHw(hw) &&
        _catalog.rateControlFor(hw).contains(mode) &&
        _caps.supportsRateControl(hw, mode);
    final swSupported =
        sw.isNotEmpty && _catalog.rateControlFor(sw).contains(mode);
    return hwSupported || swSupported;
  }

  String _rateModeTooltip(String mode) {
    if (_rateModeEnabled(mode)) return _kRateControlHints[mode] ?? '';
    final label = _kRateControlLabels[mode] ?? mode;
    if (_hwVideoEncoder.isNotEmpty && !_caps.supportsHw(_hwVideoEncoder)) {
      return '当前机型未报告 ${_catalog.labelOf(_hwVideoEncoder)} 硬件编码能力，该模式不可用';
    }
    return '当前编码器不支持「$label」，请先选择支持的编码器';
  }

  // ── 保存 ──────────────────────────────────────────────────────────────────

  /// 至少配置一条视频路（复制 / 硬编 / 软编），否则 Rust 会拒绝保存。
  bool get _hasVideoPath =>
      _videoCopy || _hwVideoEncoder.isNotEmpty || _swVideoEncoder.isNotEmpty;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasVideoPath) return;

    final preset = TranscodePreset(
      id: _idController.text.trim(),
      label: _labelController.text.trim(),
      videoCopy: _videoCopy,
      audioCopy: _audioCopy,
      hwVideoEncoder: _hwVideoEncoder,
      swVideoEncoder: _swVideoEncoder,
      swVideoPreset: _swVideoEncoder == 'libx264' && !_videoCopy
          ? _swVideoPreset
          : '',
      videoMaxW: _intOrNull(_videoMaxWController),
      videoMaxH: _intOrNull(_videoMaxHController),
      videoMaxBitrate: _videoRateControl == 'cq' ? null : _bitrateBps,
      videoFpsCap: _intOrNull(_videoFpsCapController),
      videoRateControl: _videoRateControl,
      videoQuality: _videoRateControl == 'cq' ? _videoQuality : null,
      audioCodec: _audioCodec,
      audioBitrate: int.tryParse(_audioBitrateController.text.trim()) ?? 128000,
      audioChannels: _audioChannels,
      audioSampleRate: _intOrNull(_audioSampleRateController),
      hlsSegmentSecs: int.tryParse(_hlsSegmentSecsController.text.trim()) ?? 4,
      sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 100,
      isBuiltin: widget.preset?.isBuiltin ?? false,
    );

    setState(() => _saving = true);
    final json = jsonEncode(preset.toJson());
    final result = RustCoreService.transcodePresetSave(json);
    setState(() => _saving = false);

    if (result == null) {
      if (mounted) AppSnack.show(context, 'FFI 未加载');
      return;
    }
    if (result.startsWith('error:')) {
      if (mounted) AppSnack.show(context, '保存失败: ${result.substring(6)}');
      return;
    }
    if (mounted) {
      AppSnack.show(context, '已保存');
      Navigator.pop(context, preset);
    }
  }

  // ── 布局辅助 ──────────────────────────────────────────────────────────────

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _encoderDropdown({
    required String label,
    required String value,
    required List<VideoEncoderInfo> codecs,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('禁用')),
        for (final codec in codecs)
          DropdownMenuItem(
            value: codec.id,
            enabled: codec.hardware ? _caps.supportsHw(codec.id) : true,
            child: Text(codec.label),
          ),
        // 预设里保存了当前 catalog 不认识的编码器时，保留它而不是悄悄清空。
        if (value.isNotEmpty && !codecs.any((codec) => codec.id == value))
          DropdownMenuItem(value: value, child: Text(_catalog.labelOf(value))),
      ],
      onChanged: (next) => onChanged(next ?? ''),
    );
  }

  Widget _rateControlPicker() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final mode in _kRateControlOrder)
              Tooltip(
                message: _rateModeTooltip(mode),
                child: ChoiceChip(
                  label: Text(_kRateControlLabels[mode] ?? mode),
                  selected: _videoRateControl == mode,
                  onSelected: _rateModeEnabled(mode)
                      ? (_) => setState(() => _videoRateControl = mode)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _kRateControlHints[_videoRateControl] ?? '',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!_rateModeEnabled(_videoRateControl))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '当前编码器组合不支持所选码率控制模式。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.error),
            ),
          ),
      ],
    );
  }

  /// 恒定质量：只出质量挡位，目标码率整块隐藏（契约 §4）。
  Widget _qualityPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('质量', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final quality in _kQualityValues)
              ChoiceChip(
                label: Text('$quality'),
                selected: _videoQuality == quality,
                onSelected: (_) => setState(() => _videoQuality = quality),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '数值越低画质越好、体积越大；默认 23。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// 可变/恒定码率：目标码率输入 + 自动/2M/4M/6M/8M 快捷挡位。
  Widget _bitratePicker() {
    final currentBps = _bitrateBps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        TextFormField(
          controller: _videoBitrateMbpsController,
          decoration: InputDecoration(
            labelText: '目标码率',
            suffixText: 'Mbps',
            hintText: '留空 = 自动推导',
            helperText:
                '自动推导约 ${_formatMbpsShort(_derivedBitrate)} Mbps（分辨率 × 帧率估算）',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            final text = v?.trim() ?? '';
            if (text.isEmpty) return null;
            final value = double.tryParse(text);
            if (value == null || value <= 0) return '请输入大于 0 的数字';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final choice in _kBitrateChoices)
              ChoiceChip(
                label: Text(choice == null ? '自动' : '$choice Mbps'),
                selected: choice == null
                    ? currentBps == null
                    : currentBps == choice * 1000000,
                onSelected: (_) => setState(() {
                  if (choice == null) {
                    _videoBitrateMbpsController.clear();
                  } else {
                    _videoBitrateMbpsController.text = '$choice';
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.preset != null;
    final colorScheme = Theme.of(context).colorScheme;
    final swIsX264 = _swVideoEncoder == 'libx264';
    final showSpeedPreset = swIsX264 && !_videoCopy;
    final isCq = _videoRateControl == 'cq';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑预设' : '新建预设'),
        // 保存固定右上角，滚动到哪一层都能直接保存。
        actions: [
          IconButton(
            tooltip: '保存',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _saving || !_hasVideoPath ? null : _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            TextFormField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'ID *',
                hintText: 'my-custom-preset',
              ),
              enabled: !isEdit,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'ID 不能为空' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '显示名称 *',
                hintText: '我的自定义预设',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '显示名称不能为空' : null,
            ),

            // ① 视频命中层
            _sectionTitle(context, '视频',
                '复制 → 硬件编码 → 软件编码，前一层不可用时自动落到下一层'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('视频复制'),
              subtitle: const Text('MPEG-TS 兼容时直接复制视频流，画质无损且最快'),
              value: _videoCopy,
              onChanged: (v) => setState(() => _videoCopy = v),
            ),
            _encoderDropdown(
              label: '硬件编码器',
              value: _hwVideoEncoder,
              codecs: _catalog.hardwareCodecs,
              onChanged: (value) => setState(() => _hwVideoEncoder = value),
            ),
            const SizedBox(height: 8),
            _encoderDropdown(
              label: '软件编码器',
              value: _swVideoEncoder,
              codecs: _catalog.softwareCodecs,
              onChanged: (value) => setState(() {
                _swVideoEncoder = value;
                if (value != 'libx264') {
                  // 只有 libx264 有速度挡位。
                  _swVideoPreset = 'veryfast';
                }
              }),
            ),
            if (showSpeedPreset) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _swVideoPreset,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '速度预设',
                  helperText: '越快越省 CPU，越慢同码率画质越好',
                ),
                items: [
                  for (final entry in _kSpeedPresetLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _swVideoPreset = value);
                },
              ),
            ],

            // ② 输出包络
            _sectionTitle(context, '输出包络', '留空 = 不限制；目标码率留空按分辨率自动推导'),
            TextFormField(
              controller: _videoMaxWController,
              decoration: const InputDecoration(
                labelText: '最大宽度 (px)',
                hintText: '留空 = 不限制',
              ),
              keyboardType: TextInputType.number,
              validator: _positiveIntValidator,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _videoMaxHController,
              decoration: const InputDecoration(
                labelText: '最大高度 (px)',
                hintText: '留空 = 不限制',
              ),
              keyboardType: TextInputType.number,
              validator: _positiveIntValidator,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _videoFpsCapController,
              decoration: const InputDecoration(
                labelText: '帧率上限',
                hintText: '留空 = 不限制',
              ),
              keyboardType: TextInputType.number,
              validator: _positiveIntValidator,
            ),

            // ③ 码率控制
            _sectionTitle(context, '码率控制', '只显示当前编码器支持的模式'),
            _rateControlPicker(),
            if (isCq) _qualityPicker() else _bitratePicker(),

            // ④ 音频
            _sectionTitle(context, '音频', '视频复制时音频也按此编码（除非开启音频复制）'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('音频复制'),
              subtitle: const Text('编码兼容时直接复制音频流'),
              value: _audioCopy,
              onChanged: (v) => setState(() => _audioCopy = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: _audioCodec,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '音频编码'),
              items: const [
                DropdownMenuItem(value: 'aac', child: Text('AAC')),
                DropdownMenuItem(value: 'ac3', child: Text('AC-3')),
                DropdownMenuItem(value: 'eac3', child: Text('E-AC-3')),
                DropdownMenuItem(value: 'mp2', child: Text('MP2')),
              ],
              onChanged: (v) => setState(() => _audioCodec = v ?? 'aac'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _audioBitrateController,
              decoration: const InputDecoration(
                labelText: '音频比特率 (bps) *',
                hintText: '128000',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '音频比特率不能为空';
                final parsed = int.tryParse(v.trim());
                if (parsed == null || parsed <= 0) return '请输入正整数';
                return null;
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _audioChannels,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '音频声道数'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('单声道 (1)')),
                DropdownMenuItem(value: 2, child: Text('立体声 (2)')),
              ],
              onChanged: (v) => setState(() => _audioChannels = v ?? 2),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _audioSampleRateController,
              decoration: const InputDecoration(
                labelText: '音频采样率 (Hz)',
                hintText: '留空 = 保持原始',
              ),
              keyboardType: TextInputType.number,
              validator: _positiveIntValidator,
            ),

            // ⑤ 分段
            _sectionTitle(context, '分段', 'HLS 分片时长'),
            TextFormField(
              controller: _hlsSegmentSecsController,
              decoration: const InputDecoration(
                labelText: '分段时长 (秒) *',
                hintText: '4',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '分段时长不能为空';
                final parsed = int.tryParse(v.trim());
                if (parsed == null || parsed <= 0) return '请输入正整数';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sortOrderController,
              decoration: const InputDecoration(
                labelText: '排序顺序 *',
                hintText: '100',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '排序顺序不能为空';
                if (int.tryParse(v.trim()) == null) return '必须是数字';
                return null;
              },
            ),

            if (!_hasVideoPath) ...[
              const SizedBox(height: 16),
              Text(
                '至少启用「视频复制」、硬件编码器或软件编码器之一。',
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
