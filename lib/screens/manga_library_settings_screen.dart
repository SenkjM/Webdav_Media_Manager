import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/cache_policy.dart';
import '../models/manga_read_mode.dart';
import '../providers/app_state.dart';
import '../utils/directory_walk.dart';
import '../widgets/library_cache_settings.dart';

/// 漫画库设置子页：扫描 / 建立的子目录与深度，以及漫画缓存。
///
/// 与「音乐库」子页同级，同挂在「媒体库」分区下。
class MangaLibrarySettingsScreen extends StatelessWidget {
  const MangaLibrarySettingsScreen({super.key});

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
          const LibraryCacheSettings(kind: CacheKind.manga),
        ],
      ),
    );
  }
}
