import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/transcode_preset.dart';
import '../services/rust_core_service.dart';
import '../utils/app_snack.dart';

/// 转码预设管理页面。
///
/// 预设现在是一个三层方案（契约 `preset-encoder-tiers` §1/§7.2）：
/// 流复制 → 硬件编码器 → 软件编码器。内置只有 `h264` / `hevc` 两个，
/// 可编辑、不可删除，并提供「恢复默认」。
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

  /// 把内置预设恢复为出厂参数（契约 §4，FFI `wdmm_transcode_preset_reset`）。
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
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
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

/// 转码预设编辑页面：固定六段式布局（契约 §7.2）。
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
  late TextEditingController _idController;
  late TextEditingController _labelController;
  late TextEditingController _videoMaxWController;
  late TextEditingController _videoMaxHController;
  late TextEditingController _videoMaxBitrateController;
  late TextEditingController _videoFpsCapController;
  late TextEditingController _audioBitrateController;
  late TextEditingController _audioSampleRateController;
  late TextEditingController _hlsSegmentSecsController;
  late TextEditingController _sortOrderController;

  bool _videoCopy = false;
  bool _audioCopy = false;
  String _hwVideoEncoder = '';
  String _hwVideoTier = 'balanced';
  String _swVideoEncoder = '';
  String _swVideoTier = 'balanced';
  String _audioCodec = 'aac';
  int _audioChannels = 2;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _idController = TextEditingController(text: p?.id ?? '');
    _labelController = TextEditingController(text: p?.label ?? '');
    _videoMaxWController =
        TextEditingController(text: p?.videoMaxW?.toString() ?? '');
    _videoMaxHController =
        TextEditingController(text: p?.videoMaxH?.toString() ?? '');
    _videoMaxBitrateController =
        TextEditingController(text: p?.videoMaxBitrate?.toString() ?? '');
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
      _hwVideoTier = p.hwVideoTier;
      _swVideoEncoder = p.swVideoEncoder;
      _swVideoTier = p.swVideoTier;
      _audioCodec = p.audioCodec;
      _audioChannels = p.audioChannels;
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _labelController.dispose();
    _videoMaxWController.dispose();
    _videoMaxHController.dispose();
    _videoMaxBitrateController.dispose();
    _videoFpsCapController.dispose();
    _audioBitrateController.dispose();
    _audioSampleRateController.dispose();
    _hlsSegmentSecsController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

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
      hwVideoTier: _hwVideoTier,
      swVideoEncoder: _swVideoEncoder,
      swVideoTier: _swVideoTier,
      videoMaxW: _videoMaxWController.text.trim().isEmpty
          ? null
          : int.tryParse(_videoMaxWController.text.trim()),
      videoMaxH: _videoMaxHController.text.trim().isEmpty
          ? null
          : int.tryParse(_videoMaxHController.text.trim()),
      videoMaxBitrate: _videoMaxBitrateController.text.trim().isEmpty
          ? null
          : int.tryParse(_videoMaxBitrateController.text.trim()),
      videoFpsCap: _videoFpsCapController.text.trim().isEmpty
          ? null
          : int.tryParse(_videoFpsCapController.text.trim()),
      audioCodec: _audioCodec,
      audioBitrate: int.parse(_audioBitrateController.text.trim()),
      audioChannels: _audioChannels,
      audioSampleRate: _audioSampleRateController.text.trim().isEmpty
          ? null
          : int.tryParse(_audioSampleRateController.text.trim()),
      hlsSegmentSecs: int.parse(_hlsSegmentSecsController.text.trim()),
      sortOrder: int.parse(_sortOrderController.text.trim()),
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

  Widget _tierDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: 'fast', child: Text('快速')),
          DropdownMenuItem(value: 'balanced', child: Text('均衡')),
          DropdownMenuItem(value: 'quality', child: Text('高质量')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.preset != null;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑预设' : '新建预设'),
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

            // ① 流复制
            _sectionTitle(context, '流复制', '可复制时优先复制，不重新编码'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('视频复制'),
              subtitle: const Text('MPEG-TS 兼容时直接复制视频流，画质无损且最快'),
              value: _videoCopy,
              onChanged: (v) => setState(() => _videoCopy = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('音频复制'),
              subtitle: const Text('编码兼容时直接复制音频流'),
              value: _audioCopy,
              onChanged: (v) => setState(() => _audioCopy = v),
            ),

            // ② 硬件编码器
            _sectionTitle(context, '硬件编码器', '设备支持时使用，速度最快'),
            DropdownButtonFormField<String>(
              initialValue: _hwVideoEncoder,
              decoration: const InputDecoration(labelText: '硬件编码器'),
              items: const [
                DropdownMenuItem(value: '', child: Text('禁用')),
                DropdownMenuItem(
                    value: 'h264_mediacodec', child: Text('H.264 硬编')),
                DropdownMenuItem(
                    value: 'hevc_mediacodec', child: Text('H.265 硬编')),
                DropdownMenuItem(
                    value: 'mpeg4_mediacodec', child: Text('MPEG-4 硬编')),
              ],
              onChanged: (v) =>
                  setState(() => _hwVideoEncoder = v ?? ''),
            ),
            const SizedBox(height: 8),
            _tierDropdown(
              label: '硬件编码挡位',
              value: _hwVideoTier,
              onChanged: (v) => setState(() => _hwVideoTier = v),
            ),

            // ③ 软件编码器
            _sectionTitle(context, '软件编码器', '硬件不可用时的兜底'),
            DropdownButtonFormField<String>(
              initialValue: _swVideoEncoder,
              decoration: const InputDecoration(labelText: '软件编码器'),
              items: const [
                DropdownMenuItem(value: '', child: Text('禁用')),
                DropdownMenuItem(value: 'libx264', child: Text('x264')),
                DropdownMenuItem(value: 'mpeg2video', child: Text('MPEG-2')),
                DropdownMenuItem(value: 'mpeg4', child: Text('MPEG-4')),
              ],
              onChanged: (v) =>
                  setState(() => _swVideoEncoder = v ?? ''),
            ),
            const SizedBox(height: 8),
            _tierDropdown(
              label: '软件编码挡位',
              value: _swVideoTier,
              onChanged: (v) => setState(() => _swVideoTier = v),
            ),

            // ④ 输出包络
            _sectionTitle(context, '输出包络', '留空 = 不限制'),
            TextFormField(
              controller: _videoMaxWController,
              decoration: const InputDecoration(
                labelText: '最大宽度 (px)',
                hintText: '留空 = 不限制',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _videoMaxHController,
              decoration: const InputDecoration(
                labelText: '最大高度 (px)',
                hintText: '留空 = 不限制',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _videoMaxBitrateController,
              decoration: const InputDecoration(
                labelText: '最大码率 (bps)',
                hintText: '留空 = 按分辨率自动',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _videoFpsCapController,
              decoration: const InputDecoration(
                labelText: '帧率上限',
                hintText: '留空 = 不限制',
              ),
              keyboardType: TextInputType.number,
            ),

            // ⑤ 音频
            _sectionTitle(context, '音频', '视频复制时音频也按此编码（除非开启音频复制）'),
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
                if (int.tryParse(v.trim()) == null) return '必须是数字';
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
                if (int.tryParse(v.trim()) == null) return '必须是数字';
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving || !_hasVideoPath ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
