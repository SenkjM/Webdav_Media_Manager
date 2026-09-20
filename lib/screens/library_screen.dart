import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_service.dart';
import 'home_shell.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: const DrawerMenuButton(),
          title: const Text('音乐库'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '专辑'),
              Tab(text: '作者'),
              Tab(text: '音乐名'),
            ],
          ),
        ),
        body: library.count == 0
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '暂无已缓存曲目。\n请在「网络库」下载音乐后，曲目会出现在此。\n'
                    '元数据与封面缩略图会在缓存清理后保留。',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : TabBarView(
                children: [
                  _AlbumTab(library: library),
                  _ArtistTab(library: library),
                  _TitleTab(library: library),
                ],
              ),
      ),
    );
  }
}

class _TitleTab extends StatelessWidget {
  const _TitleTab({required this.library});
  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    final tracks = library.byTitle();
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) => _TrackTile(track: tracks[i], playlist: tracks),
    );
  }
}

class _ArtistTab extends StatelessWidget {
  const _ArtistTab({required this.library});
  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    final groups = library.groupedByArtist();
    final artists = groups.keys.toList();
    return ListView.builder(
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final artist = artists[i];
        final tracks = groups[artist]!;
        return ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(artist),
          subtitle: Text('${tracks.length} 首'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(title: artist, tracks: tracks),
              ),
            );
          },
        );
      },
    );
  }
}

class _AlbumTab extends StatelessWidget {
  const _AlbumTab({required this.library});
  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    final groups = library.groupedByAlbum();
    final albums = groups.keys.toList();
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final album = albums[i];
        final tracks = groups[album]!;
        String? cover;
        for (final t in tracks) {
          final path = t.coverPath;
          if (path != null && File(path).existsSync()) {
            cover = path;
            break;
          }
        }
        return ListTile(
          leading: _CoverThumb(path: cover, size: 48),
          title: Text(album),
          subtitle: Text('${tracks.length} 首 · ${tracks.first.displayArtist}'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(title: album, tracks: tracks),
              ),
            );
          },
        );
      },
    );
  }
}

class _TrackListPage extends StatelessWidget {
  const _TrackListPage({required this.title, required this.tracks});
  final String title;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, i) =>
            _TrackTile(track: tracks[i], playlist: tracks),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.playlist});
  final LibraryTrack track;
  final List<LibraryTrack> playlist;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _CoverThumb(path: track.coverPath, size: 48),
      title: Text(track.displayTitle),
      subtitle: Text('${track.displayArtist} · ${track.displayAlbum}'),
      onTap: () => _play(context),
    );
  }

  Future<void> _play(BuildContext context) async {
    final player = context.read<AudioPlayerService>();
    final cache = context.read<CacheService>();
    final local = await cache.localPathIfCached(
      track.remotePath,
      accountId: track.accountId,
    );
    final info = TrackInfo(
      accountId: track.accountId,
      remotePath: track.remotePath,
      fileName: track.fileName,
      localPath: local,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration:
          track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
      coverPath: track.coverPath,
    );
    final list = playlist
        .map(
          (t) => TrackInfo(
            accountId: t.accountId,
            remotePath: t.remotePath,
            fileName: t.fileName,
            title: t.title,
            artist: t.artist,
            album: t.album,
            coverPath: t.coverPath,
            duration: t.durationMs != null
                ? Duration(milliseconds: t.durationMs!)
                : null,
          ),
        )
        .toList();
    if (!context.mounted) return;
    if (local == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已过期，正在重新下载…')),
      );
    }
    await player.playTrack(info, playlist: list);
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.path, required this.size});
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (path != null && File(path!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (ctx, error, stackTrace) => _placeholder(ctx),
        ),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.album, size: size * 0.5),
    );
  }
}
