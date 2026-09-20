import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/playlist.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/download_queue_service.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/library_cover_art.dart';

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistService>();
    final library = context.watch<LibraryService>();
    final pl = service.findById(playlistId);
    if (pl == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('歌单')),
        body: const Center(child: Text('歌单不存在')),
      );
    }

    final tracks = <LibraryTrack>[];
    final missing = <PlaylistEntry>[];
    for (final e in pl.entries) {
      final t = library.find(e.accountId, e.remotePath);
      if (t != null) {
        tracks.add(t);
      } else {
        missing.add(e);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        title: Text(pl.name),
        actions: [
          IconButton(
            tooltip: '从音乐库添加',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: () => _pickFromLibrary(context, pl),
          ),
        ],
      ),
      body: pl.entries.isEmpty
          ? const Center(
              child: Text(
                '歌单为空。可在音乐库长按曲目添加，或点右上角从库中选择。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          : ListView(
              children: [
                for (var i = 0; i < tracks.length; i++)
                  _PlaylistTrackTile(
                    track: tracks[i],
                    playlistTracks: tracks,
                    onRemove: () => service.removeTrack(
                      pl.id,
                      PlaylistEntry(
                        accountId: tracks[i].accountId,
                        remotePath: tracks[i].remotePath,
                      ),
                    ),
                  ),
                for (final e in missing)
                  ListTile(
                    leading: const Icon(Icons.music_off_outlined),
                    title: Text(e.title ?? e.remotePath.split('/').last),
                    subtitle: Text('库中暂无 · ${e.accountId}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => service.removeTrack(pl.id, e),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _pickFromLibrary(BuildContext context, Playlist pl) async {
    final library = context.read<LibraryService>();
    final all = library.tracks.toList();
    final selected = await showDialog<LibraryTrack>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从音乐库添加'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: all.isEmpty
              ? const Center(child: Text('音乐库为空'))
              : ListView.builder(
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final t = all[i];
                    return ListTile(
                      title: Text(t.displayTitle),
                      subtitle: Text(t.displayArtist),
                      onTap: () => Navigator.pop(ctx, t),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    await context.read<PlaylistService>().addTrack(
          pl.id,
          PlaylistEntry(
            accountId: selected.accountId,
            remotePath: selected.remotePath,
            title: selected.displayTitle,
            durationMs: selected.durationMs,
          ),
        );
  }
}

class _PlaylistTrackTile extends StatelessWidget {
  const _PlaylistTrackTile({
    required this.track,
    required this.playlistTracks,
    required this.onRemove,
  });

  final LibraryTrack track;
  final List<LibraryTrack> playlistTracks;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: LibraryCoverArt.forTrack(track: track, size: 48, borderRadius: 4),
      title: Text(track.displayTitle),
      subtitle: Text('${track.displayArtist} · ${track.displayAlbum}'),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: onRemove,
      ),
      onTap: () => _play(context),
      onLongPress: onRemove,
    );
  }

  Future<void> _play(BuildContext context) async {
    final player = context.read<AudioPlayerService>();
    final cache = context.read<CacheService>();
    final downloads = context.read<DownloadQueueService>();
    final local = await cache.localPathIfCached(
      track.remotePath,
      accountId: track.accountId,
    );
    if (local == null) {
      unawaited(
        downloads.ensureQueued(
          track.accountId,
          track.remotePath,
          fileName: track.fileName,
        ),
      );
    }
    final list = playlistTracks
        .map(
          (t) => TrackInfo(
            accountId: t.accountId,
            remotePath: t.remotePath,
            fileName: t.fileName,
            localPath: null,
            title: t.title,
            artist: t.artist,
            album: t.album,
            duration: t.durationMs != null
                ? Duration(milliseconds: t.durationMs!)
                : null,
            coverPath: t.coverPath,
          ),
        )
        .toList();
    // Refresh local paths best-effort for current.
    final info = TrackInfo(
      accountId: track.accountId,
      remotePath: track.remotePath,
      fileName: track.fileName,
      localPath: local,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.durationMs != null
          ? Duration(milliseconds: track.durationMs!)
          : null,
      coverPath: track.coverPath,
    );
    final idx = playlistTracks.indexWhere(
      (t) =>
          t.accountId == track.accountId && t.remotePath == track.remotePath,
    );
    if (idx >= 0) list[idx] = info;
    await player.playTrack(info, playlist: list);
  }
}
