import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_tag_dimension.dart';
import '../models/library_track.dart';
import '../models/playlist.dart';
import '../models/webdav_item.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import '../widgets/cover_art.dart';
import 'library_tag_picker_screen.dart';
import 'playlists_screen.dart';

/// Editable now-playing queue: reorder / remove / add, plus clear.
///
/// Entries are library references (identity + fields resolved from the music
/// library), not a separate metadata store. Playback continues while editing
/// except for "play now" inserts, which switch the current track.
class NowPlayingQueueScreen extends StatelessWidget {
  const NowPlayingQueueScreen({super.key});

  Future<void> _addToExistingPlaylist(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final player = context.read<AudioPlayerService>();
    final queue = player.queue;
    if (queue.isEmpty) {
      AppSnack.show(context, l10n.playlistQueueEmpty);
      return;
    }
    final entries = [
      for (final t in queue)
        PlaylistEntry(
          sourceName: t.sourceName,
          remotePath: t.remotePath,
          musicId: t.musicId,
          title: t.displayTitle,
          durationMs: t.duration?.inMilliseconds,
          cueTrackIndex: t.cueTrackIndex,
        ),
    ];
    await showAddManyToPlaylistDialog(context, entries);
  }

  Future<void> _clear(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.playbackQueueClearConfirm),
        content: Text(l10n.playbackQueueClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.clearAll),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AudioPlayerService>().clearQueue();
    if (!context.mounted) return;
    AppSnack.show(context, l10n.playbackQueueCleared);
  }

  Future<void> _openAddSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    var append = false;
    String? kind;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  l10n.queueAdd,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: IconButton(
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(l10n.queueAddToEnd),
                value: append,
                onChanged: (v) => setSheetState(() => append = v),
              ),
              for (final entry in [
                (UserFolderRefKind.track, l10n.folderAddTracks),
                (UserFolderRefKind.album, l10n.folderAddAlbums),
                (UserFolderRefKind.artist, l10n.folderAddArtists),
                (UserFolderRefKind.genre, l10n.folderAddGenres),
              ])
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(entry.$2),
                  onTap: () {
                    kind = entry.$1;
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    await _pickAndQueue(context, kind!, append: append);
  }

  Future<void> _pickAndQueue(
    BuildContext context,
    String refKind, {
    required bool append,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final title = switch (refKind) {
      UserFolderRefKind.track => l10n.folderAddTracks,
      UserFolderRefKind.album => l10n.folderAddAlbums,
      UserFolderRefKind.artist => l10n.folderAddArtists,
      _ => l10n.folderAddGenres,
    };
    final keys = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => LibraryTagPickerScreen(refKind: refKind, title: title),
      ),
    );
    if (keys == null || keys.isEmpty || !context.mounted) return;
    final library = context.read<LibraryService>();
    final cache = context.read<CacheService>();
    final accounts = context.read<AccountsService>();
    final player = context.read<AudioPlayerService>();
    final tracks = <LibraryTrack>[];
    final seen = <String>{};
    for (final key in keys) {
      final resolved = _tracksForKey(library, refKind, key);
      for (final t in resolved) {
        if (seen.add(t.musicId)) tracks.add(t);
      }
    }
    if (tracks.isEmpty) {
      AppSnack.show(context, l10n.libraryTracksEmpty);
      return;
    }
    final batch = <TrackInfo>[];
    for (final t in tracks) {
      final path = await cache.localPathIfCached(
        t.effectiveAudioRemotePath,
        sourceName: t.sourceName,
      );
      batch.add(
        libraryTrackToTrackInfo(
          t,
          path,
          accounts.idForSource(t.sourceName) ?? '',
        ),
      );
    }
    if (!context.mounted) return;
    if (append) {
      await player.appendToQueue(batch);
    } else {
      await player.playNowBatch(batch);
    }
  }

  List<LibraryTrack> _tracksForKey(
    LibraryService library,
    String refKind,
    String key,
  ) {
    if (refKind == UserFolderRefKind.track) {
      final track = library.findByMusicId(key);
      return track == null ? const [] : [track];
    }
    final dim = LibraryTagDimension.byId(refKind);
    if (dim == null) return const [];
    final tracks = [
      for (final t in library.tracks)
        if (dim.groupKey(t) == key) t,
    ];
    return library.sortedCopy(
      tracks,
      sort: refKind == UserFolderRefKind.album
          ? LibrarySortMode.byAlbumTrack
          : LibrarySortMode.byName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final queue = player.queue;
    final currentIndex = player.index;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          queue.isEmpty
              ? l10n.nowPlayingQueueTitle
              : l10n.nowPlayingQueueCount(queue.length),
        ),
        actions: [
          IconButton(
            tooltip: l10n.queueAdd,
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(_openAddSheet(context)),
          ),
          if (queue.isNotEmpty)
            IconButton(
              tooltip: l10n.playlistAddQueueToExisting,
              icon: const Icon(Icons.playlist_add),
              onPressed: () => unawaited(_addToExistingPlaylist(context)),
            ),
          if (queue.isNotEmpty)
            IconButton(
              tooltip: l10n.clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => unawaited(_clear(context)),
            ),
        ],
      ),
      body: queue.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.nowPlayingQueueEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.builder(
              itemCount: queue.length,
              itemBuilder: (context, i) {
                final TrackInfo t = queue[i];
                final playing = i == currentIndex;
                return ListTile(
                  selected: playing,
                  selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
                  leading: CoverArt(
                    path: t.coverPath,
                    size: 44,
                    borderRadius: 4,
                    icon: playing ? Icons.equalizer : Icons.music_note,
                  ),
                  title: Text(
                    t.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
                      color: playing
                          ? AppColors.accent
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    [
                      t.displayArtistFor(l10n),
                      if (t.displayAlbum.isNotEmpty) t.displayAlbum,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (playing)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.graphic_eq,
                            color: AppColors.accent,
                          ),
                        )
                      else
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      PopupMenuButton<String>(
                        tooltip: l10n.moreActions,
                        onSelected: (v) {
                          if (v == 'up') {
                            unawaited(player.moveQueueEntry(i, i - 1));
                          } else if (v == 'down') {
                            unawaited(player.moveQueueEntry(i, i + 1));
                          } else if (v == 'remove') {
                            unawaited(player.removeQueueEntry(i));
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'up',
                            enabled: i > 0,
                            child: Text(l10n.moveUp),
                          ),
                          PopupMenuItem(
                            value: 'down',
                            enabled: i < queue.length - 1,
                            child: Text(l10n.moveDown),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(l10n.delete),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
