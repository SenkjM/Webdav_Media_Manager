import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/cache_policy.dart';
import '../models/file_actions.dart';
import '../models/manga_read_mode.dart';
import '../providers/app_state.dart';
import '../utils/cover_image.dart';
import '../utils/directory_walk.dart';
import '../services/settings_service.dart';
import '../widgets/library_cache_settings.dart';

/// 漫画库设置子页：扫描 / 建立的子目录与深度，以及漫画缓存。
///
/// 与「音乐库」子页同级，同挂在「媒体库」分区下。
class MangaLibrarySettingsScreen extends StatefulWidget {
  const MangaLibrarySettingsScreen({super.key});

  @override
  State<MangaLibrarySettingsScreen> createState() =>
      _MangaLibrarySettingsScreenState();
}

class _MangaLibrarySettingsScreenState extends State<MangaLibrarySettingsScreen> {
  late final TextEditingController _mangaCoverSizeController;
  String? _mangaCoverUiMode;

  @override
  void initState() {
    super.initState();
    _mangaCoverSizeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<AppState>().settings;
      final px = settings.mangaCoverThumbSizePx;
      if (px != 500 && px != mangaCoverThumbSizeKeepOriginal) {
        _mangaCoverSizeController.text = '$px';
      }
    });
  }

  @override
  void dispose() {
    _mangaCoverSizeController.dispose();
    super.dispose();
  }

  String _mangaCoverMode(SettingsService settings) {
    if (_mangaCoverUiMode != null) return _mangaCoverUiMode!;
    final px = settings.mangaCoverThumbSizePx;
    if (px == 500) return '500';
    if (px == mangaCoverThumbSizeKeepOriginal) return 'original';
    return 'custom';
  }

  Future<void> _applyCustomMangaCoverSize() async {
    final parsed = int.tryParse(_mangaCoverSizeController.text.trim());
    if (parsed == null) return;
    await context.read<AppState>().settings.setMangaCoverThumbSize(parsed);
    if (!mounted) return;
    setState(() => _mangaCoverUiMode = 'custom');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = context.watch<AppState>().settings;
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mangaLibrarySettingsSection)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(l10n.mangaLibrarySettingsHint, style: hintStyle),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.mangaScanSubdirs),
            subtitle: Text(l10n.mangaScanSubdirsHint),
            value: settings.mangaScanSubdirs,
            onChanged: (v) => unawaited(settings.setMangaScanSubdirs(v)),
          ),
          if (settings.mangaScanSubdirs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.layers_outlined),
              title: Text(l10n.mangaScanMaxDepth),
              subtitle: Text(
                '${l10n.mangaScanMaxDepthHint}\n'
                '${settings.mangaScanMaxDepth} (0–${WalkOptions.maxDepthClamp})',
              ),
              trailing: SizedBox(
                width: 72,
                child: TextFormField(
                  key: ValueKey(
                    'manga-scan-depth-${settings.mangaScanMaxDepth}',
                  ),
                  initialValue: '${settings.mangaScanMaxDepth}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null) {
                      unawaited(settings.setMangaScanMaxDepth(n));
                    }
                  },
                ),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.create_new_folder_outlined),
            title: Text(l10n.mangaCreateSubdirs),
            subtitle: Text(l10n.mangaCreateSubdirsHint),
            value: settings.mangaCreateSubdirs,
            onChanged: (v) => unawaited(settings.setMangaCreateSubdirs(v)),
          ),
          if (settings.mangaCreateSubdirs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.layers_outlined),
              title: Text(l10n.mangaCreateMaxDepth),
              subtitle: Text(
                '${l10n.mangaCreateMaxDepthHint}\n'
                '${settings.mangaCreateMaxDepth} (0–${WalkOptions.maxDepthClamp})',
              ),
              trailing: SizedBox(
                width: 72,
                child: TextFormField(
                  key: ValueKey(
                    'manga-create-depth-${settings.mangaCreateMaxDepth}',
                  ),
                  initialValue: '${settings.mangaCreateMaxDepth}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null) {
                      unawaited(settings.setMangaCreateMaxDepth(n));
                    }
                  },
                ),
              ),
            ),
          const Divider(height: 32),
          Text(
            l10n.mangaReadModeSection,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.mangaReadModeHint, style: hintStyle),
          const SizedBox(height: 12),
          SegmentedButton<MangaReadMode>(
            segments: [
              ButtonSegment(
                value: MangaReadMode.stream,
                icon: const Icon(Icons.cloud_outlined),
                label: Text(l10n.mangaReadModeStream),
              ),
              ButtonSegment(
                value: MangaReadMode.cache,
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.mangaReadModeCache),
              ),
            ],
            selected: {settings.mangaReadMode},
            onSelectionChanged: (sel) =>
                unawaited(settings.setMangaReadMode(sel.first)),
          ),
          const Divider(height: 32),
          Text(
            l10n.fileExtTapBehavior,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.mangaTapBehaviorHint, style: hintStyle),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.touch_app_outlined),
            title: Text(settings.fileActions.comic.label(l10n)),
            subtitle: Text(
              l10n.fileExtDefaultAction(settings.fileActions.comic.label(l10n)),
            ),
          ),
          const Divider(height: 32),
          Text(
            l10n.mangaCoverThumbSizeSection,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.mangaCoverThumbSizeHint, style: hintStyle),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: '500', label: Text(l10n.mangaCoverThumb500)),
              ButtonSegment(value: 'original', label: Text(l10n.mangaCoverThumbKeepOriginal)),
              ButtonSegment(value: 'custom', label: Text(l10n.mangaCoverThumbCustom)),
            ],
            selected: {_mangaCoverMode(settings)},
            onSelectionChanged: (sel) async {
              final v = sel.first;
              setState(() => _mangaCoverUiMode = v);
              if (v == '500') {
                await settings.setMangaCoverThumbSize(500);
              } else if (v == 'original') {
                await settings.setMangaCoverThumbSize(mangaCoverThumbSizeKeepOriginal);
              } else {
                if (_mangaCoverSizeController.text.trim().isEmpty) {
                  _mangaCoverSizeController.text = '${settings.mangaCoverThumbSizePx}';
                }
              }
            },
          ),
          if (_mangaCoverMode(settings) == 'custom') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _mangaCoverSizeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: '32–1024',
                    ),
                    onSubmitted: (_) => _applyCustomMangaCoverSize(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _applyCustomMangaCoverSize,
                  child: Text(l10n.apply),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.mangaCoverThumbSizeCurrent(settings.mangaCoverThumbSizePx),
              style: hintStyle,
            ),
          ],
          const LibraryCacheSettings(kind: CacheKind.manga),
        ],
      ),
    );
  }
}
