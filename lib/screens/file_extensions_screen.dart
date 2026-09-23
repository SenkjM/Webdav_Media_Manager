import '../utils/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/file_actions.dart';
import '../models/file_type_config.dart';
import '../providers/app_state.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 管理「哪些后缀算音乐 / 视频 / CUE」以及**每一类文件的单击行为**。
///
/// 单击行为来自统一的[文件动作模型](file_actions.dart)：每个类别维护一个
/// 默认动作，网络库的单击、多选工具栏、更多菜单都从这里取。不在允许列表里
/// 的动作不会出现在下拉框里——「拦截不合法行为」的第一道闸就在这。
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
    final actions = settings.fileActions;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('文件后缀管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '按后缀识别文件类型；多个后缀用空格或逗号分隔。返回网络库刷新后生效。'
            '下面每一类的「单击行为」就是网络库点按该文件时的动作，'
            '多选工具栏与「更多」菜单遵循同一套判定。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '音乐文件',
            subtitle: '点按默认动作：${actions.music.labelZh}',
            controller: _musicController,
            onApply: () => _apply(FileCategory.music),
            onRestore: () => _restoreDefault(FileCategory.music),
            actionDropdown: _buildActionDropdown(settings, FileCategory.music),
            footer: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: actions.experimentalMusicStreaming,
              onChanged: (v) => context
                  .read<SettingsService>()
                  .setExperimentalMusicStreaming(v),
              title: const Text(
                '允许音乐流式传输（实验性）',
                style: TextStyle(color: AppColors.primaryText),
              ),
              subtitle: const Text(
                '打开后音乐可以像视频一样远端播放，不下载、不进音乐库。'
                '差别与限制见开发中文档的可行性分析。',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '视频文件',
            subtitle: '点按默认动作：${actions.video.labelZh}',
            controller: _videoController,
            onApply: () => _apply(FileCategory.video),
            onRestore: () => _restoreDefault(FileCategory.video),
            actionDropdown: _buildActionDropdown(settings, FileCategory.video),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'CUE 文件',
            subtitle: '点按默认动作：${actions.cue.labelZh}'
                '（CUE 读取会解析分片并整组下载）',
            controller: _cueController,
            onApply: () => _apply(FileCategory.cue),
            onRestore: () => _restoreDefault(FileCategory.cue),
            actionDropdown: _buildActionDropdown(settings, FileCategory.cue),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '普通文件',
            subtitle: '点按默认动作：${actions.other.labelZh}'
                '（不在上面三张列表里的后缀，下载到系统下载目录）',
            controller: null,
            onApply: null,
            onRestore: null,
            actionDropdown: _buildActionDropdown(settings, FileCategory.other),
          ),
        ],
      ),
    );
  }

  Widget _buildActionDropdown(SettingsService settings, FileCategory category) {
    final actions = settings.fileActions;
    final choices = actions.choicesFor(category);
    final value = actions.forCategory(category);
    return DropdownButtonFormField<FileAction>(
      initialValue: choices.contains(value) ? value : choices.first,
      decoration: const InputDecoration(
        labelText: '点按行为',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final a in choices)
          DropdownMenuItem(value: a, child: Text(a.labelZh)),
      ],
      onChanged: (v) {
        if (v != null) {
          context.read<SettingsService>().setFileAction(category, v);
        }
      },
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required TextEditingController? controller,
    required VoidCallback? onApply,
    required VoidCallback? onRestore,
    Widget? actionDropdown,
    Widget? footer,
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
                if (onRestore != null)
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
            if (controller != null) ...[
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
            ],
            if (actionDropdown != null) ...[
              const SizedBox(height: 12),
              actionDropdown,
            ],
            if (footer != null) ...[const SizedBox(height: 8), footer],
            if (onApply != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onApply,
                  child: const Text('应用'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
