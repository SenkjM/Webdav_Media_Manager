import 'dart:async';
import 'dart:convert';

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

  /// 列表副标题：视频摘要（remux / 硬编 / 软编 / 无）。
  String _videoSummary(TranscodePreset preset) {
    if (preset.videoRemux != 'off') return '视频 remux';
    if (preset.hwVideoEncoder.isNotEmpty) {
      return '视频硬编 ${_catalog.labelOf(preset.hwVideoEncoder)}';
    }
    if (preset.swVideoEncoder.isNotEmpty) {
      return '视频软编 ${_catalog.labelOf(preset.swVideoEncoder)}';
    }
    return '视频无';
  }

  /// 列表副标题：音频摘要（remux / 编码）。
  static String _audioSummary(TranscodePreset preset) {
    if (preset.audioRemux != 'off') return '音频 remux';
    return '音频编码 ${preset.audioCodec.toUpperCase()} '
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

  /// 三档 remux（契约 `remux-modes` §6）。
  static const Map<String, String> _kRemuxLabels = {
    'off': '禁用',
    'strict': '严格',
    'on': '开启',
  };

  /// x264 速度挡位：五档 UI 投影（契约 `remux-modes` 追加要求）。
  static const Map<String, String> _kSpeedPresetLabels = {
    'superfast': '极速',
    'veryfast': '快速',
    'medium': '均衡',
    'slow': '高质量',
    'veryslow': '极致',
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

  String _videoRemux = 'on';
  String _audioRemux = 'on';
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
      _videoRemux = p.videoRemux;
      _audioRemux = p.audioRemux;
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

  /// 把任意历史 x264 preset 名归一到编辑器暴露的五档之一。
  static String _nearestSpeedPreset(String raw) =>
      TranscodePreset.normalizeSpeedPreset(raw);

  // ── 码率控制 ──────────────────────────────────────────────────────────────

  /// 当前编码器组合是否支持某个码率控制模式。
  ///
  /// 需要同时满足：catalog 声明该编码器支持该模式，且机型探测没有明确否认
  /// （硬编）；探测不可用时 [CodecCapabilityService] 保守放行。只 remux、没有
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

  // ── 保存 ──────────────────────────────────────────────────────────────────

  /// 至少配置一条视频路（remux / 硬编 / 软编），否则 Rust 会拒绝保存。
  bool get _hasVideoPath =>
      _videoRemux != 'off' ||
      _hwVideoEncoder.isNotEmpty ||
      _swVideoEncoder.isNotEmpty;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasVideoPath) return;

    final preset = TranscodePreset(
      id: _idController.text.trim(),
      label: _labelController.text.trim(),
      videoRemux: _videoRemux,
      audioRemux: _audioRemux,
      hwVideoEncoder: _hwVideoEncoder,
      swVideoEncoder: _swVideoEncoder,
      // 速度预设属于预设模板，与本次是否 remux 无关。
      swVideoPreset: _swVideoEncoder == 'libx264' ? _swVideoPreset : '',
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

  Widget _sectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 三档 remux 下拉：禁用 / 严格 / 开启（契约 `remux-modes` §6）。
  Widget _remuxDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final mode in TranscodePreset.remuxModes)
          DropdownMenuItem(
            value: mode,
            child: Text(_kRemuxLabels[mode] ?? mode),
          ),
      ],
      onChanged: (next) => onChanged(next ?? 'on'),
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
                message: _rateModeEnabled(mode) ? null : '当前编码器不支持',
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
    final showSpeedPreset = swIsX264;
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
            _sectionTitle(context, '视频'),
            _remuxDropdown(
              label: '视频 remux',
              value: _videoRemux,
              onChanged: (v) => setState(() => _videoRemux = v),
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
                decoration: const InputDecoration(labelText: '速度预设'),
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
            _sectionTitle(context, '输出包络'),
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
            _sectionTitle(context, '码率控制'),
            _rateControlPicker(),
            if (isCq) _qualityPicker() else _bitratePicker(),

            // ④ 音频
            _sectionTitle(context, '音频'),
            _remuxDropdown(
              label: '音频 remux',
              value: _audioRemux,
              onChanged: (v) => setState(() => _audioRemux = v),
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
            _sectionTitle(context, '分段'),
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
                '至少启用「视频 remux」、硬件编码器或软件编码器之一。',
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
