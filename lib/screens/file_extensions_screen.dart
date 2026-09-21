import '../utils/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/file_type_config.dart';
import '../models/video_settings.dart';
import '../providers/app_state.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Manage which file extensions are treated as music / video / CUE, plus the
/// default tap action for music & video files in the network library.
class FileExtensionsScreen extends StatefulWidget {
  const FileExtensionsScreen({super.key});

  @override
  State<FileExtensionsScreen> createState() => _FileExtensionsScreenState();
}

class _FileExtensionsScreenState extends State<FileExtensionsScreen> {
  late final TextEditingController _musicController;
  late final TextEditingController _videoController;
  late final TextEditingController _cueController;

  @override
  void initState() {
    super.initState();
    _musicController = TextEditingController();
    _videoController = TextEditingController();
    _cueController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromSettings());
  }

  void _syncFromSettings() {
    final settings = context.read<SettingsService>();
    _musicController.text = FileTypeConfig.displayList(
      settings.fileTypes.musicExtensions,
    );
    _videoController.text = FileTypeConfig.displayList(
      settings.fileTypes.videoExtensions,
    );
    _cueController.text = FileTypeConfig.displayList(
      settings.fileTypes.cueExtensions,
    );
  }

  @override
  void dispose() {
    _musicController.dispose();
    _videoController.dispose();
    _cueController.dispose();
    super.dispose();
  }

  Future<void> _apply(FileCategory category) async {
    final settings = context.read<SettingsService>();
    final current = settings.fileTypes;
    final music = category == FileCategory.music
        ? FileTypeConfig.parseInput(_musicController.text)
        : current.musicExtensions;
    final video = category == FileCategory.video
        ? FileTypeConfig.parseInput(_videoController.text)
        : current.videoExtensions;
    final cue = category == FileCategory.cue
        ? FileTypeConfig.parseInput(_cueController.text)
        : current.cueExtensions;
    await settings.setFileTypes(
      FileTypeConfig(
        musicExtensions: music,
        videoExtensions: video,
        cueExtensions: cue,
      ),
    );
    // Re-point the download queue's classifier: it must never keep using the
    // previous extension list after the user edits it here.
    if (mounted) context.read<AppState>().refreshFileTypeClassifiers();
    if (!mounted) return;
    AppSnack.show(context, '后缀配置已保存');
  }

  void _restoreDefault(FileCategory category) {
    final def = FileTypeConfig();
    switch (category) {
      case FileCategory.music:
        _musicController.text = FileTypeConfig.displayList(def.musicExtensions);
        break;
      case FileCategory.video:
        _videoController.text = FileTypeConfig.displayList(def.videoExtensions);
        break;
      case FileCategory.cue:
        _cueController.text = FileTypeConfig.displayList(def.cueExtensions);
        break;
      case FileCategory.other:
        break;
    }
    _apply(category);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('文件后缀管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '网络库按后缀识别文件类型。可自由增删；多个后缀用空格或逗号分隔。'
            '修改后返回网络库重新刷新即生效。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '音乐文件',
            subtitle: '默认操作：${settings.musicTapAction.labelZh}',
            controller: _musicController,
            onApply: () => _apply(FileCategory.music),
            onRestore: () => _restoreDefault(FileCategory.music),
            actionDropdown: DropdownButtonFormField<MusicTapAction>(
              initialValue: settings.musicTapAction,
              items: [
                for (final a in MusicTapAction.values)
                  DropdownMenuItem(value: a, child: Text(a.labelZh)),
              ],
              onChanged: (v) {
                if (v != null) {
                  context.read<SettingsService>().setMusicTapAction(v);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '视频文件',
            subtitle: '默认操作：${settings.videoTapAction.labelZh}',
            controller: _videoController,
            onApply: () => _apply(FileCategory.video),
            onRestore: () => _restoreDefault(FileCategory.video),
            actionDropdown: DropdownButtonFormField<VideoTapAction>(
              initialValue: settings.videoTapAction,
              items: [
                for (final a in VideoTapAction.values)
                  DropdownMenuItem(value: a, child: Text(a.labelZh)),
              ],
              onChanged: (v) {
                if (v != null) {
                  context.read<SettingsService>().setVideoTapAction(v);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'CUE 文件',
            subtitle: '点击 CUE 会解析并预览分片',
            controller: _cueController,
            onApply: () => _apply(FileCategory.cue),
            onRestore: () => _restoreDefault(FileCategory.cue),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required VoidCallback onApply,
    required VoidCallback onRestore,
    Widget? actionDropdown,
  }) {
    return Card(
      color: AppColors.elevated,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '例如：mp3 flac m4a',
                labelText: '后缀列表',
              ),
              onEditingComplete: onApply,
            ),
            if (actionDropdown != null) ...[
              const SizedBox(height: 12),
              actionDropdown,
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: onApply,
                child: const Text('应用'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
