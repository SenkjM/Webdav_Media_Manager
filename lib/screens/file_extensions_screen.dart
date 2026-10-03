import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
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
  late final TextEditingController _imageController;
  late final TextEditingController _cueController;

  @override
  void initState() {
    super.initState();
    _musicController = TextEditingController();
    _videoController = TextEditingController();
    _imageController = TextEditingController();
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
    _imageController.text = FileTypeConfig.displayList(
      settings.fileTypes.imageExtensions,
    );
    _cueController.text = FileTypeConfig.displayList(
      settings.fileTypes.cueExtensions,
    );
  }

  @override
  void dispose() {
    _musicController.dispose();
    _videoController.dispose();
    _imageController.dispose();
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
    final image = category == FileCategory.image
        ? FileTypeConfig.parseInput(_imageController.text)
        : current.imageExtensions;
    final cue = category == FileCategory.cue
        ? FileTypeConfig.parseInput(_cueController.text)
        : current.cueExtensions;
    await settings.setFileTypes(
      FileTypeConfig(
        musicExtensions: music,
        videoExtensions: video,
        imageExtensions: image,
        cueExtensions: cue,
      ),
    );
    // Re-point the download queue's classifier: it must never keep using the
    // previous extension list after the user edits it here.
    if (mounted) context.read<AppState>().refreshFileTypeClassifiers();
    if (!mounted) return;
    AppSnack.show(context, AppLocalizations.of(context)!.fileExtSaved);
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
      case FileCategory.image:
        _imageController.text = FileTypeConfig.displayList(def.imageExtensions);
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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(l10n.fileExtensionSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.fileExtIntro,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.fileCatMusic,
            subtitle: l10n.fileExtDefaultAction(actions.music.label(l10n)),
            controller: _musicController,
            onApply: () => _apply(FileCategory.music),
            onRestore: () => _restoreDefault(FileCategory.music),
            actionDropdown: _buildActionDropdown(settings, FileCategory.music),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.fileCatVideo,
            subtitle: l10n.fileExtDefaultAction(actions.video.label(l10n)),
            controller: _videoController,
            onApply: () => _apply(FileCategory.video),
            onRestore: () => _restoreDefault(FileCategory.video),
            actionDropdown: _buildActionDropdown(settings, FileCategory.video),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.fileCatImage,
            subtitle: l10n.fileExtDefaultAction(actions.image.label(l10n)),
            controller: _imageController,
            onApply: () => _apply(FileCategory.image),
            onRestore: () => _restoreDefault(FileCategory.image),
            actionDropdown: _buildActionDropdown(settings, FileCategory.image),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.fileCatCue,
            subtitle: l10n.fileExtCueNote(actions.cue.label(l10n)),
            controller: _cueController,
            onApply: () => _apply(FileCategory.cue),
            onRestore: () => _restoreDefault(FileCategory.cue),
            actionDropdown: _buildActionDropdown(settings, FileCategory.cue),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.fileCatOther,
            subtitle: l10n.fileExtOtherNote(actions.other.label(l10n)),
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
    final l10n = AppLocalizations.of(context)!;
    final actions = settings.fileActions;
    final choices = actions.choicesFor(category);
    final value = actions.forCategory(category);
    return DropdownButtonFormField<FileAction>(
      borderRadius: BorderRadius.circular(10),
      initialValue: choices.contains(value) ? value : choices.first,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context)!.fileExtTapBehavior,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final a in choices)
          DropdownMenuItem(value: a, child: Text(a.label(l10n))),
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
    final l10n = AppLocalizations.of(context)!;
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
                    label: Text(l10n.restoreDefault),
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
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.fileExtHintExample,
                  labelText: l10n.fileExtListLabel,
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
                  child: Text(l10n.apply),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
