import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/account_sentinels.dart';
import '../models/music_library_backfill_root.dart';
import '../services/accounts_service.dart';
import '../services/library_actions.dart';
import '../services/library_backfill.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../services/task_queue_service.dart';
import '../utils/app_snack.dart';
import '../utils/directory_walk.dart';
import 'webdav_folder_picker_screen.dart';

/// 媒体库子页：曲库模式、默认打开、预载、刮削深度、标签更新。
class MediaLibrarySettingsScreen extends StatefulWidget {
  const MediaLibrarySettingsScreen({super.key});

  @override
  State<MediaLibrarySettingsScreen> createState() =>
      _MediaLibrarySettingsScreenState();
}

class _MediaLibrarySettingsScreenState
    extends State<MediaLibrarySettingsScreen> {
  final TextEditingController _names = TextEditingController();
  final TextEditingController _depth = TextEditingController();
  var _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final s = context.read<SettingsService>();
    _names.text = s.audioStreamSidecarNames;
    _depth.text = '${s.audioPlaylistMaxDepth}';
  }

  @override
  void dispose() {
    _names.dispose();
    _depth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final accounts = context.watch<AccountsService>();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final auto = settings.musicLibraryAutoBackfill;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mediaLibrarySettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.libraryManageMode,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.libraryManageModeHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.libraryModeManual),
            subtitle: Text(l10n.libraryModeManualHint),
            leading: Icon(
              auto ? Icons.radio_button_off : Icons.radio_button_checked,
            ),
            onTap: () => unawaited(settings.setMusicLibraryAutoBackfill(false)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.libraryModeAuto),
            subtitle: Text(l10n.libraryModeAutoHint),
            leading: Icon(
              auto ? Icons.radio_button_checked : Icons.radio_button_off,
            ),
            onTap: () => unawaited(settings.setMusicLibraryAutoBackfill(true)),
          ),
          if (auto) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.link),
              title: Text(l10n.libraryBackfillBindRoots),
              subtitle: Text(l10n.libraryBackfillBindRootsHint),
              value: settings.musicLibraryBackfillBindRoots,
              onChanged: (v) =>
                  unawaited(settings.setMusicLibraryBackfillBindRoots(v)),
            ),
            if (settings.musicLibraryBackfillBindRoots) ...[
              const SizedBox(height: 8),
              Text(
                l10n.libraryBackfillRoots,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.libraryBackfillRootsHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              for (final root in settings.musicLibraryBackfillRoots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(
                    backfillRootLabel(
                      root: root,
                      accounts: accounts,
                      localizeAccountName: (n) =>
                          localizedAccountName(l10n, n),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(
                      settings.removeMusicLibraryBackfillRoot(root),
                    ),
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_link),
                title: Text(l10n.libraryBackfillAddRoot),
                onTap: accounts.hasAccounts
                    ? () => unawaited(_addBackfillRoot(context))
                    : null,
                subtitle: accounts.hasAccounts
                    ? null
                    : Text(l10n.libraryBackfillNeedAccount),
              ),
            ],
          ],
          const Divider(height: 32),
          Text(
            l10n.musicDefaultOpen,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.musicDefaultOpenHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
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
            l10n.prefetchSection,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.prefetchSectionHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.image_outlined),
            title: Text(l10n.streamSidecarCover),
            subtitle: Text(l10n.streamSidecarCoverHint),
            value: settings.audioStreamSidecarCover,
            onChanged: (v) => unawaited(settings.setAudioStreamSidecarCover(v)),
          ),
          TextField(
            controller: _names,
            decoration: InputDecoration(
              labelText: l10n.streamSidecarNames,
              helperText: l10n.streamSidecarNamesHint,
              helperMaxLines: 4,
            ),
            onChanged: (value) =>
                unawaited(settings.setAudioStreamSidecarNames(value)),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.streamPrefetchHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.skip_previous),
            title: Text(l10n.streamPrefetchBackward),
            subtitle: Text('${settings.audioStreamPrefetchBackward}'),
          ),
          Slider(
            min: SettingsService.minStreamPrefetch.toDouble(),
            max: SettingsService.maxStreamPrefetch.toDouble(),
            divisions: SettingsService.maxStreamPrefetch -
                SettingsService.minStreamPrefetch,
            value: settings.audioStreamPrefetchBackward.toDouble(),
            label: '${settings.audioStreamPrefetchBackward}',
            onChanged: (v) => unawaited(
              settings.setAudioStreamPrefetchBackward(v.round()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.skip_next),
            title: Text(l10n.streamPrefetchForward),
            subtitle: Text('${settings.audioStreamPrefetchForward}'),
          ),
          Slider(
            min: SettingsService.minStreamPrefetch.toDouble(),
            max: SettingsService.maxStreamPrefetch.toDouble(),
            divisions: SettingsService.maxStreamPrefetch -
                SettingsService.minStreamPrefetch,
            value: settings.audioStreamPrefetchForward.toDouble(),
            label: '${settings.audioStreamPrefetchForward}',
            onChanged: (v) => unawaited(
              settings.setAudioStreamPrefetchForward(v.round()),
            ),
          ),
          const Divider(height: 32),
          Text(
            l10n.audioPlaylistSection,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.scanListHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            title: Text(l10n.scanSubdirectories),
            subtitle: Text(l10n.scanSubdirectoriesHint),
            value: settings.audioScanSubdirs,
            onChanged: (v) => unawaited(settings.setAudioScanSubdirs(v)),
          ),
          if (settings.audioScanSubdirs) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.layers_outlined),
              title: Text(l10n.playlistMaxDepth),
              subtitle: Text(l10n.playlistMaxDepthHint),
            ),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _depth,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.playlistMaxDepthInput,
                      border: const OutlineInputBorder(),
                    ),
                    onEditingComplete: () async {
                      final raw = int.tryParse(_depth.text.trim());
                      if (raw == null) return;
                      await settings.setAudioPlaylistMaxDepth(raw);
                      if (!context.mounted) return;
                      _depth.text = '${settings.audioPlaylistMaxDepth}';
                    },
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () async {
                    final raw = int.tryParse(_depth.text.trim());
                    if (raw == null) return;
                    await settings.setAudioPlaylistMaxDepth(raw);
                    if (!context.mounted) return;
                    _depth.text = '${settings.audioPlaylistMaxDepth}';
                  },
                  child: Text(l10n.apply),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '0–${WalkOptions.maxDepthClamp}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const Divider(height: 32),
          Text(
            l10n.mediaScanSection,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.mediaScanSectionHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
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

  Future<void> _addBackfillRoot(BuildContext context) async {
    final accounts = context.read<AccountsService>();
    final settings = context.read<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    final list = accounts.accounts.toList(growable: false);
    if (list.isEmpty) return;

    final accountId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.libraryBackfillPickAccount),
        children: [
          for (final a in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a.id),
              child: Text(localizedAccountName(l10n, a.name)),
            ),
        ],
      ),
    );
    if (accountId == null || !context.mounted) return;

    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WebDavFolderPickerScreen(
          accountId: accountId,
          purpose: l10n.libraryBackfillPickFolder,
        ),
      ),
    );
    if (path == null || !context.mounted) return;

    await settings.addMusicLibraryBackfillRoot(
      MusicLibraryBackfillRoot(accountId: accountId, path: path),
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
