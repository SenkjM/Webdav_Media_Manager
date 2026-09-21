import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/playlist.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_actions.dart';
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
      final t = library.find(e.sourceName, e.remotePath);
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
                '歌单为空，可从音乐库添加。',
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
                        sourceName: tracks[i].sourceName,
                        remotePath: tracks[i].remotePath,
                      ),
                    ),
                  ),
                for (final e in missing)
                  ListTile(
                    leading: const Icon(Icons.music_off_outlined),
                    title: Text(e.title ?? e.remotePath.split('/').last),
                    subtitle: Text('库中暂无 · ${e.sourceName}'),
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
            sourceName: selected.sourceName,
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
    final cache = context.watch<CacheService>();
    final isLocal = libraryTrackIsLocal(cache, track);
    return ListTile(
      leading: LibraryCoverArt.forTrack(
        track: track,
        size: 48,
        borderRadius: 4,
        enqueueIfMissing: false,
      ),
      title: Text(
        track.displayTitle,
        style: TextStyle(
          color: isLocal ? AppColors.onDark : AppColors.secondaryText,
        ),
      ),
      subtitle: Text(
        [
          if (track.isCueVirtual) LibraryTrack.cueMultiSliceLabel,
          if (!isLocal) '未下载',
          track.displayArtist,
          if (isLocal) track.displayAlbum,
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: isLocal ? '已下载' : '点按加入下载',
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLocal ? AppColors.localReady : AppColors.remotePlaceholder,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onRemove,
          ),
        ],
      ),
      onTap: () => _onTap(context, isLocal: isLocal),
      onLongPress: onRemove,
    );
  }

  Future<void> _onTap(BuildContext context, {required bool isLocal}) async {
    if (!isLocal) {
      await enqueueLibraryTrackDownload(context, track);
      return;
    }
    final player = context.read<AudioPlayerService>();
    final cache = context.read<CacheService>();
    final local = await cache.localPathIfCached(
      track.effectiveAudioRemotePath,
      sourceName: track.sourceName,
    );
    if (local == null) {
      if (context.mounted) await enqueueLibraryTrackDownload(context, track);
      return;
    }
    final list = <TrackInfo>[];
    for (final t in playlistTracks) {
      final path = await cache.localPathIfCached(
        t.effectiveAudioRemotePath,
        sourceName: t.sourceName,
      );
      if (path == null) continue;
      list.add(
        TrackInfo(
          sourceName: t.sourceName,
          remotePath: t.remotePath,
          fileName: t.fileName,
          localPath: path,
          title: t.title,
          artist: t.artist,
          album: t.album,
          duration: t.durationMs != null
              ? Duration(milliseconds: t.durationMs!)
              : null,
          coverPath: t.coverPath,
          cueRemotePath: t.cueRemotePath,
          cueTrackIndex: t.cueTrackIndex,
          audioRemotePath: t.audioRemotePath,
          clipStart: t.clipStartMs != null
              ? Duration(milliseconds: t.clipStartMs!)
              : null,
          clipEnd: t.clipEndMs != null
              ? Duration(milliseconds: t.clipEndMs!)
              : null,
          cacheGroupId: t.cacheGroupId,
        ),
      );
    }
    final info = TrackInfo(
      sourceName: track.sourceName,
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
      cueRemotePath: track.cueRemotePath,
      cueTrackIndex: track.cueTrackIndex,
      audioRemotePath: track.audioRemotePath,
      clipStart: track.clipStartMs != null
          ? Duration(milliseconds: track.clipStartMs!)
          : null,
      clipEnd: track.clipEndMs != null
          ? Duration(milliseconds: track.clipEndMs!)
          : null,
      cacheGroupId: track.cacheGroupId,
    );
    if (list.isEmpty) list.add(info);
    if (!context.mounted) return;
    await player.playTrack(info, playlist: list);
  }
}
