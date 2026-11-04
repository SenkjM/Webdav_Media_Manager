import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/encoder_options_schema.dart';
import '../models/transcode_preset.dart';
import '../services/codec_capability_service.dart';
import '../services/rust_core_service.dart';
import '../utils/app_snack.dart';

/// 转码预设管理页面。
///
/// 预设是三层方案（契约 `preset-rate-control-and-codec-probe` §13）：
/// 流复制 → 硬件编码器 → 软件编码器，编码层再叠加码率控制与高级 AVOptions。
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

  @override
  void initState() {
    super.initState();
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
        builder: (_) => _TranscodePresetEditScreen(preset: preset),
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
                              if (preset.isBuiltin)
                                IconButton(
                                  icon: const Icon(Icons.restore),
                                  tooltip: '恢复默认',
                                  onPressed: () => _resetBuiltin(preset),
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editPreset(preset),
                              ),
                              if (!preset.isBuiltin)
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _deletePreset(preset),
                                ),
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

  /// 列表副标题：视频命中层摘要（复制 / 硬编 / 软编 / 无）。
  static String _videoSummary(TranscodePreset preset) {
    if (preset.videoCopy) return '视频: 复制';
    if (preset.hwVideoEncoder.isNotEmpty) {
      return '视频: 硬编 ${_encoderLabel(preset.hwVideoEncoder)}';
    }
    if (preset.swVideoEncoder.isNotEmpty) {
      return '视频: 软编 ${_encoderLabel(preset.swVideoEncoder)}';
    }
    return '视频: 无';
  }

  /// 列表副标题：音频命中层摘要（复制 / 编码）。
  static String _audioSummary(TranscodePreset preset) {
    if (preset.audioCopy) return '音频: 复制';
    return '音频: ${preset.audioCodec.toUpperCase()} '
        '${preset.audioBitrate ~/ 1000}kbps';
  }

  static String _encoderLabel(String value) {
    switch (value) {
      case 'h264_mediacodec':
        return 'H.264 硬编';
      case 'hevc_mediacodec':
        return 'H.265 硬编';
      case 'mpeg4_mediacodec':
        return 'MPEG-4 硬编';
      case 'libx264':
        return 'x264';
      case 'mpeg2video':
        return 'MPEG-2';
      case 'mpeg4':
        return 'MPEG-4';
      default:
        return value;
    }
  }
}

/// 编辑器模板（契约 §13.3）：点一下填整张表单，之后仍可逐项修改。
class _TemplatePreset {
  const _TemplatePreset({
    required this.label,
    required this.swPreset,
    required this.rateControl,
    required this.bitrateFactor,
    this.quality,
  });

  final String label;
  final String swPreset;
  final String rateControl;

  /// 系数 × 推导码率。
  final double bitrateFactor;

  /// CQ 质量值（仅「好」模板使用）。
  final int? quality;

  int bitrateFor(int derivedBps) => (derivedBps * bitrateFactor).round();

  bool matches({
    required String swPreset,
    required String rateControl,
    required int? quality,
    required int? bitrateBps,
    required int derivedBps,
  }) {
    if (this.swPreset != swPreset || this.rateControl != rateControl) {
      return false;
    }
    if (this.quality != null && this.quality != quality) return false;
    return bitrateBps == bitrateFor(derivedBps);
  }
}

const List<_TemplatePreset> _kEditorTemplates = [
  _TemplatePreset(
    label: '快',
    swPreset: 'veryfast',
    rateControl: 'vbr',
    bitrateFactor: 0.5,
  ),
  _TemplatePreset(
    label: '均衡',
    swPreset: 'veryfast',
    rateControl: 'vbr',
    bitrateFactor: 1.0,
  ),
  _TemplatePreset(
    label: '好',
    swPreset: 'medium',
    rateControl: 'cq',
    bitrateFactor: 1.3,
    quality: 23,
  ),
];

/// 转码预设编辑页面。
///
/// 所有编码器/选项都从 Rust 的 `wdmm_encoder_options_schema_json()` 渲染
/// （契约 §13.4）；旧 `.so` 缺符号时降级为 [EncoderOptionsSchema.fallback]，
/// 界面仍可完整编辑基础字段，只是没有高级选项。
class _TranscodePresetEditScreen extends StatefulWidget {
  final TranscodePreset? preset;

  const _TranscodePresetEditScreen({this.preset});

  @override
  State<_TranscodePresetEditScreen> createState() =>
      _TranscodePresetEditScreenState();
}

class _TranscodePresetEditScreenState
    extends State<_TranscodePresetEditScreen> {
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

  late EncoderOptionsSchema _schema;

  bool _videoCopy = false;
  bool _audioCopy = false;
  String _hwVideoEncoder = '';
  String _swVideoEncoder = '';
  String _swVideoPreset = 'veryfast';
  String _videoRateControl = 'vbr';
  int _videoQuality = 23;
  final Map<String, String> _hwVideoOptions = {};
  final Map<String, String> _swVideoOptions = {};
  late final CodecCapabilityService _caps;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Schema 是可选 FFI：旧 .so 缺符号时 parse(null) 返回内置最小 schema。
    _schema =
        EncoderOptionsSchema.parse(RustCoreService.encoderOptionsSchemaJson());
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
      if (TranscodePreset.x264Presets.contains(p.swVideoPreset)) {
        _swVideoPreset = p.swVideoPreset;
      }
      if (TranscodePreset.rateControlModes.contains(p.videoRateControl)) {
        _videoRateControl = p.videoRateControl;
      }
      _videoQuality = p.videoQuality ?? 23;
      _hwVideoOptions.addAll(p.hwVideoOptions);
      _swVideoOptions.addAll(p.swVideoOptions);
      _audioCodec = p.audioCodec;
      _audioChannels = p.audioChannels;
    }
  }

  String _audioCodec = 'aac';
  int _audioChannels = 2;

  /// 机型编码能力探测完成后刷新「置灰/提示」，探测失败时保持全部可用。
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

  /// 展示用的一两位小数版本（不参与回填，避免模板比对漂移）。
  static String _formatMbpsShort(int bps) =>
      (bps / 1000000).toStringAsFixed(1);

  // ── 模板 ──────────────────────────────────────────────────────────────────

  int? get _activeTemplate {
    final bps = _bitrateBps;
    if (bps == null) return null;
    for (var i = 0; i < _kEditorTemplates.length; i++) {
      final template = _kEditorTemplates[i];
      if (template.matches(
        swPreset: _swVideoPreset,
        rateControl: _videoRateControl,
        quality: _videoRateControl == 'cq' ? _videoQuality : null,
        bitrateBps: bps,
        derivedBps: _derivedBitrate,
      )) {
        return i;
      }
    }
    return null;
  }

  void _applyTemplate(_TemplatePreset template) {
    setState(() {
      if (_swVideoEncoder.isEmpty) _swVideoEncoder = 'libx264';
      _swVideoPreset = template.swPreset;
      _videoRateControl = template.rateControl;
      if (template.quality != null) _videoQuality = template.quality!;
      final bitrate = template.bitrateFor(_derivedBitrate);
      _videoBitrateMbpsController.text = _formatMbps(bitrate);
    });
  }

  // ── 码率控制 ──────────────────────────────────────────────────────────────

  static const Map<String, String> _rateControlLabels = {
    'auto': '自动',
    'vbr': '可变码率',
    'cbr': '恒定码率',
    'cq': '恒定质量',
  };

  static const Map<String, String> _rateControlHints = {
    'auto': 'VBR / CBR / CQ · 不干预编码器默认',
    'vbr': '按画面复杂度动态分配码率，兼容性最好',
    'cbr': '码率恒定，适合弱网/老设备，画质波动更大',
    'cq': '恒定质量，码率随画面变化，体积不可控',
  };

  /// 当前编码器组合是否支持某个码率控制模式。
  ///
  /// 需要同时满足：schema 声明该编码器支持该模式，且机型探测没有明确否认
  /// （硬编）；探测不可用时 [CodecCapabilityService] 保守放行。
  bool _rateModeEnabled(String mode) {
    if (mode == 'auto') return true;
    final hwSupported = _hwVideoEncoder.isNotEmpty &&
        _caps.supportsHw(_hwVideoEncoder) &&
        _schema.rateControlFor(_hwVideoEncoder).contains(mode) &&
        _caps.supportsRateControl(_hwVideoEncoder, mode);
    final swSupported = _swVideoEncoder.isNotEmpty &&
        _schema.rateControlFor(_swVideoEncoder).contains(mode);
    return hwSupported || swSupported;
  }

  String _rateModeTooltip(String mode) {
    if (_rateModeEnabled(mode)) return _rateControlHints[mode] ?? '';
    if (_hwVideoEncoder.isNotEmpty && !_caps.supportsHw(_hwVideoEncoder)) {
      final label = _schema.codecById(_hwVideoEncoder)?.label ?? _hwVideoEncoder;
      return '当前机型未报告 $label 硬件编码能力，该模式不可用';
    }
    return '当前编码器不支持「${_rateControlLabels[mode] ?? mode}」，请先选择支持的编码器';
  }

  // ── 高级选项 ──────────────────────────────────────────────────────────────

  Map<String, String> _optionsMap(bool hardware) =>
      hardware ? _hwVideoOptions : _swVideoOptions;

  /// 编码器切换后，丢弃不再适用的高级选项，避免把无效键传给 Rust。
  void _pruneOptions(Map<String, String> options, String encoderId) {
    final allowed = _schema.optionKeysFor(encoderId);
    options.removeWhere((key, _) => !allowed.contains(key));
  }

  Widget _buildAdvancedOptions() {
    final hwOptions = _schema.advancedOptionsFor(_hwVideoEncoder);
    final swOptions = _schema.advancedOptionsFor(_swVideoEncoder);
    final children = <Widget>[
      if (_schema.isFallback)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '当前原生库未提供高级选项清单，无法配置编码器高级参数。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      if (!_schema.isFallback && hwOptions.isEmpty && swOptions.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _hwVideoEncoder.isEmpty && _swVideoEncoder.isEmpty
                ? '先选择硬件或软件编码器，再配置高级选项。'
                : '所选编码器没有可配置的高级选项。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      if (hwOptions.isNotEmpty) ...[
        _optionGroupTitle(
            '硬件编码器 · ${_schema.codecById(_hwVideoEncoder)?.label ?? _hwVideoEncoder}'),
        for (final option in hwOptions)
          _buildOption(option, _hwVideoOptions, hardware: true),
      ],
      if (swOptions.isNotEmpty) ...[
        _optionGroupTitle(
            '软件编码器 · ${_schema.codecById(_swVideoEncoder)?.label ?? _swVideoEncoder}'),
        for (final option in swOptions)
          _buildOption(option, _swVideoOptions, hardware: false),
      ],
    ];
    return ExpansionTile(
      title: const Text('高级编码器设置'),
      subtitle: Text(
        _schema.isFallback ? '原生库未提供清单' : '默认不覆盖；开启的选项才会传给底层编码器',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }

  Widget _optionGroupTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildOption(
    EncoderOptionSchema option,
    Map<String, String> target, {
    required bool hardware,
  }) {
    final current = target[option.key];
    final enabled = current != null;
    final theme = Theme.of(context);
    final control = enabled
        ? _buildOptionControl(option, current, hardware: hardware)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label, style: theme.textTheme.bodyMedium),
                    Text(
                      enabled ? option.key : '使用默认 · ${option.key}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      target[option.key] =
                          option.defaultValue ?? option.initialValue();
                    } else {
                      target.remove(option.key);
                    }
                  });
                },
              ),
            ],
          ),
          ?control,
        ],
      ),
    );
  }

  Widget _buildOptionControl(
    EncoderOptionSchema option,
    String current, {
    required bool hardware,
  }) {
    switch (option.type) {
      case EncoderOptionType.enumValue:
        final values = [
          if (option.values.isNotEmpty) ...option.values,
          if (!option.values.contains(current) && current.isNotEmpty) current,
        ];
        return DropdownButtonFormField<String>(
          initialValue: values.contains(current)
              ? current
              : (values.isEmpty ? null : values.first),
          decoration: InputDecoration(labelText: option.label),
          items: [
            for (final value in values)
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _setOptionValue(option, value, hardware: hardware));
          },
        );
      case EncoderOptionType.boolValue:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(option.label),
          value: current == 'true',
          onChanged: (value) {
            setState(() => _setOptionValue(option, value.toString(),
                hardware: hardware));
          },
        );
      case EncoderOptionType.intValue:
      case EncoderOptionType.floatValue:
        if (option.hasRange) {
          final min = option.min!.toDouble();
          final max = option.max!.toDouble();
          final parsed = double.tryParse(current) ?? min;
          final value = parsed.clamp(min, max).toDouble();
          final isInt = option.type == EncoderOptionType.intValue;
          return Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: isInt
                      ? ((max - min).round()).clamp(1, 1000)
                      : null,
                  label: isInt
                      ? value.round().toString()
                      : value.toStringAsFixed(1),
                  onChanged: (next) {
                    setState(() => _setOptionValue(
                          option,
                          isInt ? next.round().toString() : next.toString(),
                          hardware: hardware,
                        ));
                  },
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  isInt ? value.round().toString() : value.toStringAsFixed(1),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          );
        }
        return TextFormField(
          initialValue: current,
          decoration: InputDecoration(
            labelText: option.label,
            helperText: _rangeHelper(option),
          ),
          keyboardType: option.type == EncoderOptionType.intValue
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            final text = value.trim();
            setState(() {
              if (text.isEmpty) {
                _optionsMap(hardware).remove(option.key);
              } else {
                _setOptionValue(option, text, hardware: hardware);
              }
            });
          },
        );
    }
  }

  String? _rangeHelper(EncoderOptionSchema option) {
    if (option.min == null && option.max == null) return null;
    return '范围 ${option.min ?? '-'} ~ ${option.max ?? '-'}';
  }

  void _setOptionValue(
    EncoderOptionSchema option,
    String value, {
    required bool hardware,
  }) {
    _optionsMap(hardware)[option.key] = value;
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
      hwVideoOptions: Map.of(_hwVideoOptions),
      swVideoEncoder: _swVideoEncoder,
      swVideoPreset: _swVideoEncoder == 'libx264' ? _swVideoPreset : '',
      swVideoOptions: Map.of(_swVideoOptions),
      videoMaxW: _intOrNull(_videoMaxWController),
      videoMaxH: _intOrNull(_videoMaxHController),
      videoMaxBitrate: _bitrateBps,
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
    required List<EncoderCodecSchema> codecs,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('禁用')),
        for (final codec in codecs)
          DropdownMenuItem(
            value: codec.id,
            enabled: codec.isHardware ? _caps.supportsHw(codec.id) : true,
            child: Text(
              codec.isHardware && !_caps.supportsHw(codec.id)
                  ? '${codec.label}（机型未报告）'
                  : codec.label,
            ),
          ),
        // 预设里保存了当前 schema 不认识的编码器时，保留它而不是悄悄清空。
        if (value.isNotEmpty && !codecs.any((codec) => codec.id == value))
          DropdownMenuItem(value: value, child: Text(value)),
      ],
      onChanged: (next) => onChanged(next ?? ''),
    );
  }

  /// 选中的硬编在当前机型上不可用时，明确提示会回落到软编。
  Widget? _hardwareCapabilityHint() {
    final codec = _schema.codecById(_hwVideoEncoder);
    if (codec == null || !codec.isHardware) return null;
    if (_caps.supportsHw(codec.id)) {
      if (_caps.status == CodecCapabilityStatus.failed) {
        return _hintText('未能读取本机硬件编码能力，硬件选项按可用处理。', null);
      }
      return null;
    }
    return _hintText(
      '当前机型未报告 ${codec.label} 硬件编码能力，保存后编码时会自动回落到软件编码器。',
      Theme.of(context).colorScheme.error,
    );
  }

  Widget _hintText(String text, Color? color) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: color ?? Theme.of(context).hintColor),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.preset != null;
    final colorScheme = Theme.of(context).colorScheme;
    final activeTemplate = _activeTemplate;
    final swIsX264 = _swVideoEncoder == 'libx264';
    final hwInline = _schema.inlineOptionsFor(_hwVideoEncoder);
    final swInline = _schema.inlineOptionsFor(_swVideoEncoder);

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

            // 0. 模板 chips（契约 §13.3）
            _sectionTitle(context, '模板', '点一下填好整张表单，之后仍可逐项调整'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _kEditorTemplates.length; i++)
                  ChoiceChip(
                    label: Text(_kEditorTemplates[i].label),
                    selected: activeTemplate == i,
                    onSelected: (_) => _applyTemplate(_kEditorTemplates[i]),
                  ),
              ],
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
              codecs: _schema.hardwareCodecs,
              onChanged: (value) => setState(() {
                _hwVideoEncoder = value;
                _pruneOptions(_hwVideoOptions, value);
              }),
            ),
            ?_hardwareCapabilityHint(),
            for (final option in hwInline)
              _buildOption(option, _hwVideoOptions, hardware: true),
            const SizedBox(height: 8),
            _encoderDropdown(
              label: '软件编码器',
              value: _swVideoEncoder,
              codecs: _schema.softwareCodecs,
              onChanged: (value) => setState(() {
                _swVideoEncoder = value;
                if (value != 'libx264') {
                  // 只有 libx264 有 preset 阶梯。
                  _swVideoPreset = 'veryfast';
                }
                _pruneOptions(_swVideoOptions, value);
              }),
            ),
            if (swIsX264) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: TranscodePreset.x264Presets
                        .contains(_swVideoPreset)
                    ? _swVideoPreset
                    : 'veryfast',
                decoration: const InputDecoration(
                  labelText: 'x264 预设',
                  helperText: '越快越省 CPU，越慢同码率画质越好',
                ),
                items: [
                  for (final preset in TranscodePreset.x264Presets)
                    DropdownMenuItem(value: preset, child: Text(preset)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _swVideoPreset = value);
                },
              ),
            ],
            for (final option in swInline)
              _buildOption(option, _swVideoOptions, hardware: false),

            // ② 输出包络
            _sectionTitle(context, '输出包络', '留空 = 不限制；码率留空按分辨率自动推导'),
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
            const SizedBox(height: 8),
            TextFormField(
              controller: _videoBitrateMbpsController,
              decoration: InputDecoration(
                labelText: '码率上限',
                suffixText: 'Mbps',
                hintText: '留空 = 自动推导',
                helperText:
                    '自动推导约 ${_formatMbpsShort(_derivedBitrate)} Mbps（分辨率 × 帧率估算）',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
              children: [
                for (final mbps in const [2, 4, 6, 8])
                  ActionChip(
                    label: Text('$mbps Mbps'),
                    onPressed: () => setState(
                        () => _videoBitrateMbpsController.text = '$mbps'),
                  ),
              ],
            ),

            // ③ 码率控制
            _sectionTitle(context, '码率控制', '自动 = 不干预编码器默认'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: [
                  for (final mode in TranscodePreset.rateControlModes)
                    ButtonSegment<String>(
                      value: mode,
                      label: Text(_rateControlLabels[mode] ?? mode),
                      tooltip: _rateModeTooltip(mode),
                      enabled: _rateModeEnabled(mode),
                    ),
                ],
                selected: {_videoRateControl},
                onSelectionChanged: (selection) =>
                    setState(() => _videoRateControl = selection.first),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _rateControlHints[_videoRateControl] ?? '',
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
            if (_videoRateControl == 'cq') ...[
              const SizedBox(height: 8),
              Text('质量（CQ）: $_videoQuality',
                  style: Theme.of(context).textTheme.bodyMedium),
              Slider(
                value: _videoQuality.toDouble(),
                min: 0,
                max: 51,
                divisions: 51,
                label: '$_videoQuality',
                onChanged: (value) =>
                    setState(() => _videoQuality = value.round()),
              ),
              Text(
                _videoQuality < 18
                    ? '质量优先：数值越低画质越好，体积也明显更大。'
                    : '0–51，默认 23；数值越低画质越好、体积越大。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],

            // ④ 高级编码器设置
            _sectionTitle(context, '高级编码器设置', '默认不覆盖；开启的选项才会传给底层编码器'),
            _buildAdvancedOptions(),

            // ⑤ 音频
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

            // ⑥ 分段
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
