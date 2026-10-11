import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../services/task_queue_service.dart';
import '../utils/app_snack.dart';
import '../utils/directory_walk.dart';

/// 媒体库子页：默认打开、刮削深度、标签更新（本地 / 云端任务）。
class MediaLibrarySettingsScreen extends StatelessWidget {
  const MediaLibrarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mediaLibrarySettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.musicDefaultOpen,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.musicDefaultOpenHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.musicDefaultCache),
            leading: Icon(
              settings.musicDefaultStream
                  ? Icons.radio_button_off
                  : Icons.radio_button_checked,
            ),
            onTap: () => unawaited(settings.setMusicDefaultStream(false)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.musicDefaultStream),
            leading: Icon(
              settings.musicDefaultStream
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            onTap: () => unawaited(settings.setMusicDefaultStream(true)),
          ),
          const Divider(height: 32),
          Text(
            l10n.mediaScanSection,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.mediaScanSectionHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            title: Text(l10n.mediaScanRecursive),
            subtitle: Text(l10n.mediaScanRecursiveHint),
            value: settings.mediaScanRecursive,
            onChanged: (v) => unawaited(settings.setMediaScanRecursive(v)),
          ),
          if (settings.mediaScanRecursive)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.layers_outlined),
              title: Text(l10n.mediaScanMaxDepth),
              subtitle: Text(
                '${l10n.mediaScanMaxDepthHint}\n'
                '${settings.mediaScanMaxDepth} (0–${WalkOptions.maxDepthClamp})',
              ),
              trailing: SizedBox(
                width: 72,
                child: TextFormField(
                  key: ValueKey(
                    'media-scan-depth-${settings.mediaScanMaxDepth}',
                  ),
                  initialValue: '${settings.mediaScanMaxDepth}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null) {
                      unawaited(settings.setMediaScanMaxDepth(n));
                    }
                  },
                ),
              ),
            ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l10n.refreshTagsFromLocal),
            subtitle: Text(l10n.refreshTagsFromLocalHint),
            onTap: () => unawaited(_refreshLocal(context)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(l10n.refreshTagsFromCloud),
            subtitle: Text(l10n.refreshTagsFromCloudHint),
            onTap: () => unawaited(_refreshCloud(context)),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.travel_explore_outlined),
            title: Text(l10n.matchRemoteTitle),
            subtitle: Text(l10n.matchRemoteHint),
            onTap: () => unawaited(_matchRemote(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshLocal(BuildContext context) async {
    final library = context.read<LibraryService>();
    if (library.tracks.isEmpty) {
      AppSnack.show(context, AppLocalizations.of(context)!.libraryEmpty);
      return;
    }
    AppSnack.show(context, AppLocalizations.of(context)!.tagRefreshStarted);
    final result = await refreshLibraryTrackTags(
      context,
      library.tracks.toList(),
      showProgressDialog: false,
    );
    if (!context.mounted) return;
    AppSnack.show(
      context,
      AppLocalizations.of(context)!.tagRefreshCompleted(
        result.updated,
        result.skipped,
        result.failed,
      ),
      error: result.failed > 0 && result.updated == 0,
    );
  }

  Future<void> _refreshCloud(BuildContext context) async {
    final library = context.read<LibraryService>();
    final queue = context.read<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final tracks = library.tracks
        .where((t) => !t.isCueVirtual)
        .toList(growable: false);
    if (tracks.isEmpty) {
      AppSnack.show(context, l10n.libraryEmpty);
      return;
    }
    for (final t in tracks) {
      await queue.enqueueRetagCloud(
        sourceName: t.sourceName,
        remotePath: t.remotePath,
        fileName: t.fileName,
      );
    }
    if (context.mounted) {
      AppSnack.show(context, l10n.mediaScanQueued(tracks.length));
    }
  }
  Future<void> _matchRemote(BuildContext context) async {
    final library = context.read<LibraryService>();
    final queue = context.read<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    if (library.tracks.isEmpty) {
      AppSnack.show(context, l10n.libraryEmpty);
      return;
    }
    await queue.enqueueMatchRemote(
      sourceName: '*',
      unitsTotal: library.tracks.length,
    );
    if (context.mounted) {
      AppSnack.show(context, l10n.matchRemoteQueued);
    }
  }

}
