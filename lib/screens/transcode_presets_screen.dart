import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/transcode_preset.dart';
import '../services/rust_core_service.dart';
import '../utils/app_snack.dart';

/// 转码预设管理页面。
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
      // 按 sort_order 排序
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
                            'ID: ${preset.id}  |  容器: ${preset.container}  |  '
                            '视频: ${preset.videoCodec ?? "仅音频"}  |  '
                            '音频: ${preset.audioCodec} ${preset.audioBitrate ~/ 1000}kbps',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: preset.isBuiltin
                              ? Chip(
                                  label: const Text('内置'),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surfaceContainerHighest,
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _editPreset(preset),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () => _deletePreset(preset),
                                    ),
                                  ],
                                ),
                          onTap: preset.isBuiltin ? null : () => _editPreset(preset),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editPreset(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 转码预设编辑页面。
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

  String _container = 'mpegts';
  String? _videoCodec = 'h264';
  bool _videoHwPreferred = true;
  String _audioCodec = 'aac';
  int _audioChannels = 2;
  bool _remuxFirst = false;
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
      _container = p.container;
      _videoCodec = p.videoCodec;
      _videoHwPreferred = p.videoHwPreferred;
      _audioCodec = p.audioCodec;
      _audioChannels = p.audioChannels;
      _remuxFirst = p.remuxFirst;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final preset = TranscodePreset(
      id: _idController.text.trim(),
      label: _labelController.text.trim(),
      container: _container,
      videoCodec: _videoCodec,
      videoHwPreferred: _videoHwPreferred,
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
      remuxFirst: _remuxFirst,
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.preset != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑预设' : '新建预设'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _container,
              decoration: const InputDecoration(labelText: '容器格式'),
              items: const [
                DropdownMenuItem(value: 'mpegts', child: Text('MPEG-TS')),
                DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                DropdownMenuItem(value: 'original', child: Text('原始')),
              ],
              onChanged: (v) => setState(() => _container = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _videoCodec,
              decoration: const InputDecoration(labelText: '视频编码'),
              items: const [
                DropdownMenuItem(value: 'h264', child: Text('H.264')),
                DropdownMenuItem(value: null, child: Text('仅音频')),
              ],
              onChanged: (v) => setState(() => _videoCodec = v),
            ),
            if (_videoCodec != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('优先硬件编码器'),
                value: _videoHwPreferred,
                onChanged: (v) => setState(() => _videoHwPreferred = v),
              ),
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
                  labelText: '最大比特率 (bps)',
                  hintText: '留空 = 不限制',
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
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _audioCodec,
              decoration: const InputDecoration(labelText: '音频编码'),
              items: const [
                DropdownMenuItem(value: 'aac', child: Text('AAC')),
                DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                DropdownMenuItem(value: 'copy', child: Text('复制（不转码）')),
              ],
              onChanged: (v) => setState(() => _audioCodec = v!),
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
              onChanged: (v) => setState(() => _audioChannels = v!),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _hlsSegmentSecsController,
              decoration: const InputDecoration(
                labelText: 'HLS 分段时长 (秒) *',
                hintText: '4',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'HLS 分段时长不能为空';
                if (int.tryParse(v.trim()) == null) return '必须是数字';
                return null;
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('先尝试 remux（复制流）'),
              subtitle: const Text('转码前先尝试不转码直接封装'),
              value: _remuxFirst,
              onChanged: (v) => setState(() => _remuxFirst = v),
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
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
