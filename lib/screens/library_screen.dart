import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import 'home_shell.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final settings = context.watch<SettingsService>();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.nearBlack,
        appBar: AppBar(
          leading: const DrawerMenuButton(),
          title: const Text('音乐库'),
          actions: [
            PopupMenuButton<LibrarySortMode>(
              tooltip: '排序',
              initialValue: settings.librarySort,
              onSelected: (mode) =>
                  context.read<SettingsService>().setLibrarySort(mode),
              itemBuilder: (context) => [
                for (final mode in LibrarySortMode.values)
                  PopupMenuItem(
                    value: mode,
                    child: Row(
                      children: [
                        Icon(
                          settings.librarySort == mode
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(mode.labelZh),
                      ],
                    ),
                  ),
              ],
              icon: const Icon(Icons.sort),
            ),
          ],
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
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ),
              )
            : TabBarView(
                children: [
                  _AlbumTab(library: library),
                  _ArtistTab(library: library),
                  _TitleTab(
                    library: library,
                    sort: settings.librarySort,
                  ),
                ],
              ),
      ),
    );
  }
}

class _TitleTab extends StatelessWidget {
  const _TitleTab({required this.library, required this.sort});
  final LibraryService library;
  final LibrarySortMode sort;

  @override
  Widget build(BuildContext context) {
    final tracks = library.byTitle(sort: sort);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tracks.length,
      itemBuilder: (context, i) =>
          _TrackTile(track: tracks[i], playlist: tracks),
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
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final artist = artists[i];
        final tracks = groups[artist]!;
        String? cover;
        for (final t in tracks) {
          final path = t.coverPath;
          if (path != null && File(path).existsSync()) {
            cover = path;
            break;
          }
        }
        return _CoverTile(
          coverPath: cover,
          title: artist,
          subtitle: '${tracks.length} 首',
          placeholderIcon: Icons.person_outline,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(
                  title: artist,
                  tracks: tracks,
                  // Artist lists stay name-ordered unless user opens album.
                  defaultSort: LibrarySortMode.byName,
                ),
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
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
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
        return _CoverTile(
          coverPath: cover,
          title: album,
          subtitle: '${tracks.length} 首 · ${tracks.first.displayArtist}',
          placeholderIcon: Icons.album,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(
                  title: album,
                  tracks: tracks,
                  // Album detail defaults to disc/track order.
                  defaultSort: LibrarySortMode.byAlbumTrack,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.coverPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.placeholderIcon,
  });

  final String? coverPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? placeholderIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.elevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide;
                    return Center(
                      child: CoverArt(
                        path: coverPath,
                        size: side,
                        borderRadius: 6,
                        icon: placeholderIcon,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.onDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackListPage extends StatefulWidget {
  const _TrackListPage({
    required this.title,
    required this.tracks,
    required this.defaultSort,
  });
  final String title;
  final List<LibraryTrack> tracks;
  final LibrarySortMode defaultSort;

  @override
  State<_TrackListPage> createState() => _TrackListPageState();
}

class _TrackListPageState extends State<_TrackListPage> {
  late LibrarySortMode _sort = widget.defaultSort;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();
    final tracks = library.sortedCopy(widget.tracks, sort: _sort);
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<LibrarySortMode>(
            tooltip: '排序',
            initialValue: _sort,
            onSelected: (mode) => setState(() => _sort = mode),
            itemBuilder: (context) => [
              for (final mode in LibrarySortMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Text(mode.labelZh),
                ),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
    final trackLabel = track.trackNumber != null
        ? '${track.trackNumber}. '
        : '';
    return ListTile(
      leading: CoverArt(path: track.coverPath, size: 52, borderRadius: 4),
      title: Text(
        '$trackLabel${track.displayTitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.onDark,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        '${track.displayArtist} · ${track.displayAlbum}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
      ),
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
