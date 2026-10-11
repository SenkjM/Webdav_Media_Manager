import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_track.dart';
import '../models/playlist.dart';
import '../models/playlist_sentinels.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import '../services/stream_cover_reader.dart';
import '../services/task_queue_service.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import '../utils/task_error.dart';
import '../widgets/library_cover_art.dart';
import '../widgets/meta_text.dart';
import '../widgets/track_status_chip.dart';
import 'webdav_folder_picker_screen.dart';

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistService>();
    final library = context.watch<LibraryService>();
    final pl = service.findById(playlistId);
    if (pl == null) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.playlistsTitle)),
        body: Center(child: Text(l10n.playlistNotFound)),
      );
    }

    // Keep entry order. Resolve by musicId (single source of truth for
    // remote_missing / cache / streamable); missing → 「库中暂无」, not a red dot.
    final resolved = <LibraryTrack?>[];
    final playableTracks = <LibraryTrack>[];
    for (final e in pl.entries) {
      final t =
          library.findByMusicId(e.identityKey) ??
          library.find(e.sourceName, e.remotePath);
      resolved.add(t);
      if (t != null) playableTracks.add(t);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          isUnnamedPlaylistName(pl.name)
              ? AppLocalizations.of(context)!.unnamedPlaylist
              : pl.name,
        ),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.playlistAddFromLibrary,
            icon: const Icon(Icons.library_add_outlined),
            onPressed: () => _pickFromLibrary(context, pl),
          ),
        ],
      ),
      body: pl.entries.isEmpty
          ? Center(
              child: Text(
                AppLocalizations.of(context)!.playlistEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              itemCount: pl.entries.length,
              itemBuilder: (context, i) {
                final entry = pl.entries[i];
                final track = resolved[i];
                if (track == null) {
                  return _MissingPlaylistTile(
                    entry: entry,
                    onRemove: () => service.removeTrack(pl.id, entry),
                  );
                }
                return _PlaylistTrackTile(
                  playlistId: pl.id,
                  entry: entry,
                  track: track,
                  playlistTracks: playableTracks,
                  onRemove: () => service.removeTrack(
                    pl.id,
                    PlaylistEntry(
                      sourceName: track.sourceName,
                      remotePath: track.remotePath,
                      musicId: track.musicId,
                      cueTrackIndex: track.cueTrackIndex,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _pickFromLibrary(BuildContext context, Playlist pl) async {
    final l10n = AppLocalizations.of(context)!;
    final library = context.read<LibraryService>();
    final all = library.tracks.toList();
    final selected = await showDialog<LibraryTrack>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.playlistAddFromLibrary),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: all.isEmpty
              ? Center(child: Text(l10n.libraryEmpty))
              : ListView.builder(
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final t = all[i];
                    return ListTile(
                      title: Text(t.displayTitle),
                      subtitle: Text(t.displayArtistFor(l10n)),
                      onTap: () => Navigator.pop(ctx, t),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    await context.read<PlaylistService>().addTrack(
      pl.id,
      PlaylistEntry(
        sourceName: selected.sourceName,
        remotePath: selected.remotePath,
        musicId: selected.musicId,
        title: selected.displayTitle,
        durationMs: selected.durationMs,
        cueTrackIndex: selected.cueTrackIndex,
      ),
    );
  }
}

/// Entry whose musicId is not in the library — parallel to library, not a
/// remote-missing red dot.
class _MissingPlaylistTile extends StatelessWidget {
  const _MissingPlaylistTile({required this.entry, required this.onRemove});

  final PlaylistEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: Icon(
        Icons.music_off_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(entry.title ?? entry.remotePath.split('/').last),
      subtitle: MetaText(l10n.playlistMissingInLibrary(entry.sourceName)),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: onRemove,
      ),
      onLongPress: onRemove,
    );
  }
}

class _PlaylistTrackTile extends StatelessWidget {
  const _PlaylistTrackTile({
    required this.playlistId,
    required this.entry,
    required this.track,
    required this.playlistTracks,
    required this.onRemove,
  });

  final String playlistId;
  final PlaylistEntry entry;
  final LibraryTrack track;
  final List<LibraryTrack> playlistTracks;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    final downloads = context.watch<TaskQueueService>();
    final isLocal = libraryTrackIsLocal(cache, track);
    final task = downloads.taskForRemote(
      track.sourceName,
      track.effectiveAudioRemotePath,
    );
    // read: avoid rebuild every position tick (same as library list).
    final audio = context.read<AudioPlayerService>();
    final sourceBound = context.read<AccountsService>().isSourceBound(
      track.sourceName,
    );
    final state = libraryRowUiState(
      downloads: downloads,
      track: track,
      playingRemotePath: audio.currentRemotePath,
      playingSourceName: audio.currentSourceName,
    );
    final showChip =
        state == TrackUiState.remoteMissing ||
        state == TrackUiState.queued ||
        state == TrackUiState.downloading ||
        state == TrackUiState.error ||
        state == TrackUiState.playing;
    final isDownloading = state == TrackUiState.downloading;

    return ListTile(
      leading: LibraryCoverArt.forTrack(
        track: track,
        size: 48,
        borderRadius: 4,
        enqueueIfMissing: false,
      ),
      title: Text(
        track.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isLocal
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        [
          if (track.isCueVirtual)
            AppLocalizations.of(context)!.cueMultiSliceLabel,
          if (!sourceBound) AppLocalizations.of(context)!.sourceUnbound,
          if (isDownloading && task != null && task.progress > 0)
            AppLocalizations.of(context)!
                .downloadingPercent((task.progress * 100).toStringAsFixed(0)),
          track.displayArtistFor(AppLocalizations.of(context)!),
          if (isLocal) track.displayAlbumFor(AppLocalizations.of(context)!),
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
          if (showChip)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TrackStatusChip(
                state: state,
                progress: isDownloading ? task?.progress : null,
              ),
            ),
          Tooltip(
            message: track.remoteMissing
                ? AppLocalizations.of(context)!.trackStateRemoteMissing
                : isLocal
                    ? AppLocalizations.of(context)!.downloaded
                    : AppLocalizations.of(context)!.trackStateStreamable,
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: track.remoteMissing
                    ? AppColors.error
                    : isLocal
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.primary,
                border: Border.all(
                  color: (track.remoteMissing
                          ? AppColors.error
                          : isLocal
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onRemove,
          ),
        ],
      ),
      onTap: () {
        if (track.remoteMissing && !isLocal) {
          unawaited(_onRemoteMissingTap(context));
          return;
        }
        unawaited(_onTap(context, isLocal: isLocal));
      },
      onLongPress: onRemove,
    );
  }

  Future<void> _onTap(BuildContext context, {required bool isLocal}) async {
    final accountsService = context.read<AccountsService>();
    if (!accountsService.isSourceBound(track.sourceName)) {
      AppSnack.error(
        context,
        unboundSourceMessage(AppLocalizations.of(context)!, track.sourceName),
      );
      return;
    }
    final accountId = accountsService.idForSource(track.sourceName) ?? '';
    final player = context.read<AudioPlayerService>();
    final cache = context.read<CacheService>();
    final playlistInfos = <TrackInfo>[];
    for (final t in playlistTracks) {
      if (t.isCueVirtual && t != track) {
        final path = await cache.localPathIfCached(
          t.effectiveAudioRemotePath,
          sourceName: t.sourceName,
        );
        if (path == null) continue;
        playlistInfos.add(
          libraryTrackToTrackInfo(
            t,
            path,
            accountsService.idForSource(t.sourceName) ?? '',
          ),
        );
        continue;
      }
      final path = await cache.localPathIfCached(
        t.effectiveAudioRemotePath,
        sourceName: t.sourceName,
      );
      playlistInfos.add(
        libraryTrackToTrackInfo(
          t,
          path,
          accountsService.idForSource(t.sourceName) ?? accountId,
        ),
      );
    }
    final local = await cache.localPathIfCached(
      track.effectiveAudioRemotePath,
      sourceName: track.sourceName,
    );
    final info = libraryTrackToTrackInfo(track, local, accountId);
    if (playlistInfos.isEmpty) playlistInfos.add(info);
    if (!context.mounted) return;
    await player.playTrack(info, playlist: playlistInfos);
    if (player.error != null && context.mounted) {
      final err = TaskError.classify(StateError(player.error!));
      AppSnack.error(
        context,
        err.code == 'err.cloud.notFound'
            ? AppLocalizations.of(context)!.trackStateRemoteMissing
            : player.error!,
      );
    }
  }

  Future<void> _onRemoteMissingTap(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final accounts = context.read<AccountsService>();
    final accountId = accounts.idForSource(track.sourceName);
    if (accountId == null) {
      AppSnack.error(context, unboundSourceMessage(l10n, track.sourceName));
      return;
    }
    AppSnack.show(context, l10n.remoteMissingRetrying);
    try {
      final source = await context.read<WebDavService>().resolveStreamSource(
        accountId: accountId,
        remotePath: track.effectiveAudioRemotePath,
        name: track.fileName,
        kind: StreamKind.music,
      );
      if (!context.mounted) return;
      if (source == null || source.uri.isEmpty) {
        throw StateError('err.cloud.notFound|missing');
      }
      await context.read<LibraryService>().clearRemoteMissing(
        sourceName: track.sourceName,
        remotePath: track.remotePath,
      );
      if (!context.mounted) return;
      await _onTap(context, isLocal: false);
    } catch (e) {
      if (!context.mounted) return;
      final code = TaskError.classify(e).code;
      if (code != 'err.cloud.notFound') {
        AppSnack.error(context, TaskError.classify(e).detail);
        return;
      }
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.remoteMissingTitle),
          content: Text(l10n.remoteMissingBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text(l10n.delete),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'redirect'),
              child: Text(l10n.remoteMissingRedirect),
            ),
          ],
        ),
      );
      if (!context.mounted || action == null || action == 'cancel') return;
      if (action == 'delete') {
        // Playlist parallel: remove the entry, do not destroy the library row.
        onRemove();
        return;
      }
      if (action == 'redirect') {
        final picked = await pickWebDavFile(
          context,
          accountId: accountId,
          musicOnly: true,
        );
        if (!context.mounted || picked == null) return;
        final library = context.read<LibraryService>();
        final playlists = context.read<PlaylistService>();
        final next = await library.retargetTrack(
          track: track,
          newRemotePath: picked.path,
          newFileName: picked.name,
        );
        await playlists.replaceTrack(
          playlistId,
          entry,
          PlaylistEntry(
            sourceName: next.sourceName,
            remotePath: next.remotePath,
            musicId: next.musicId,
            title: next.title ?? next.displayTitle,
            durationMs: next.durationMs,
            cueTrackIndex: next.cueTrackIndex,
          ),
        );
        try {
          final source = await context.read<WebDavService>().resolveStreamSource(
            accountId: accountId,
            remotePath: next.remotePath,
            name: next.fileName,
            kind: StreamKind.music,
          );
          if (source != null && source.uri.isNotEmpty && context.mounted) {
            final tags = await StreamCoverReader().extractTags(source);
            if (tags != null && context.mounted) {
              await library.ingestFromTags(
                sourceName: next.sourceName,
                remotePath: next.remotePath,
                fileName: next.fileName,
                tags: tags,
              );
            }
          }
        } catch (_) {
          // Redirect succeeded even if tag re-read fails.
        }
      }
    }
  }
}
