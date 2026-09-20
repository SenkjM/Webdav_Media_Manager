import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/download_queue_service.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/track_identity.dart';
import 'package:path/path.dart' as p;
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';
import '../models/playlist.dart';
import 'home_shell.dart';
import 'playlists_screen.dart';

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
    final cache = context.watch<CacheService>();
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
        final coverTrack = pickCoverTrack(tracks, cache);
        return _CoverTile(
          coverTrack: coverTrack,
          title: artist,
          subtitle: '${tracks.length} 首',
          placeholderIcon: Icons.person_outline,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(
                  title: artist,
                  tracks: tracks,
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
    final cache = context.watch<CacheService>();
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
        final coverTrack = pickCoverTrack(tracks, cache);
        return _CoverTile(
          coverTrack: coverTrack,
          title: album,
          subtitle: '${tracks.length} 首 · ${tracks.first.displayArtist}',
          placeholderIcon: Icons.album,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(
                  title: album,
                  tracks: tracks,
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
    required this.coverTrack,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.placeholderIcon,
  });

  final LibraryTrack? coverTrack;
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
                    final t = coverTrack;
                    if (t == null) {
                      return Center(
                        child: CoverArt(
                          size: side,
                          borderRadius: 6,
                          icon: placeholderIcon,
                        ),
                      );
                    }
                    return Center(
                      child: LibraryCoverArt.forTrack(
                        track: t,
                        size: side,
                        borderRadius: 6,
                        icon: placeholderIcon,
                        // Grid tiles: show art; download on open album / tap play.
                        enqueueIfMissing: false,
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enqueueMissing());
  }

  void _enqueueMissing() {
    if (!mounted) return;
    final downloads = context.read<DownloadQueueService>();
    // Batch-enqueue missing files when opening album/artist detail (non-blocking).
    unawaited(
      downloads.ensureQueuedMany(
        widget.tracks.map(
          (t) => (
            accountId: t.accountId,
            remotePath: t.remotePath,
            fileName: t.fileName,
          ),
        ),
      ),
    );
  }

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
      leading: LibraryCoverArt.forTrack(
        track: track,
        size: 52,
        borderRadius: 4,
        // List rows: enqueue when the row is shown / tapped — prefer tap play;
        // also enqueue if missing while rendering so cover upgrades soon.
        enqueueIfMissing: true,
      ),
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
      onLongPress: () => _showTrackMenu(context),
    );
  }

  Future<void> _showTrackMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(track.displayTitle), subtitle: Text(track.isCueVirtual ? 'CUE 虚拟曲目' : track.fileName)),
        ListTile(leading: const Icon(Icons.playlist_add), title: const Text('添加到歌单'), onTap: () {
          Navigator.pop(ctx);
          showAddToPlaylistDialog(context, PlaylistEntry(accountId: track.accountId, remotePath: track.remotePath, title: track.displayTitle, durationMs: track.durationMs));
        }),
        ListTile(leading: const Icon(Icons.delete_outline, color: AppColors.error), title: const Text('删除本地音频缓存'), subtitle: const Text('保留元数据与封面'), onTap: () { Navigator.pop(ctx); _deleteLocalCache(context); }),
      ])),
    );
  }

  Future<void> _deleteLocalCache(BuildContext context) async {
    final cache = context.read<CacheService>();
    final groupId = track.cacheGroupId ?? (track.cueRemotePath != null ? cueCacheGroupId(track.accountId, track.cueRemotePath!) : null);
    if (track.isCueVirtual && groupId != null) {
      var names = cache.groupMemberFileNames(groupId);
      if (names.isEmpty) names = [if (track.cueRemotePath != null) p.basename(track.cueRemotePath!), if (track.audioRemotePath != null) p.basename(track.audioRemotePath!)];
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('删除整个 CUE 缓存组？'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('将删除整组（CUE + 关联音频）：'), const SizedBox(height: 8),
          for (final n in names) Text('• $n'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除整组'))],
      ));
      if (ok != true || !context.mounted) return;
      final n = await cache.deleteCacheGroup(groupId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 CUE 缓存组（$n 个文件）')));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除本地音频缓存？'),
      content: Text('将删除「${p.basename(track.effectiveAudioRemotePath)}」。元数据与封面保留。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true || !context.mounted) return;
    final removed = await cache.deleteLocalFile(accountId: track.accountId, remotePath: track.effectiveAudioRemotePath);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(removed ? '已删除本地音频缓存' : '本地无缓存文件')));
  }

  Future<void> _play(BuildContext context) async {
    final player = context.read<AudioPlayerService>();
    final cache = context.read<CacheService>();
    final downloads = context.read<DownloadQueueService>();
    final local = await cache.localPathIfCached(
      track.effectiveAudioRemotePath,
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
    final info = TrackInfo(
      accountId: track.accountId,
      remotePath: track.remotePath,
      fileName: track.fileName,
      localPath: local,
      title: track.title,
      artist: track.artist,
      albumArtist: track.albumArtist,
      album: track.album,
      duration:
          track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      discNumber: track.discNumber,
      discTotal: track.discTotal,
      year: track.year,
      genre: track.genre,
      bitrate: track.bitrate,
      sampleRate: track.sampleRate,
      coverPath: track.coverPath,
      cueRemotePath: track.cueRemotePath,
      cueTrackIndex: track.cueTrackIndex,
      audioRemotePath: track.audioRemotePath,
      clipStart: track.clipStartMs != null ? Duration(milliseconds: track.clipStartMs!) : null,
      clipEnd: track.clipEndMs != null ? Duration(milliseconds: track.clipEndMs!) : null,
      cacheGroupId: track.cacheGroupId,
    );
    final list = playlist
        .map(
          (t) => TrackInfo(
            accountId: t.accountId,
            remotePath: t.remotePath,
            fileName: t.fileName,
            title: t.title,
            artist: t.artist,
            albumArtist: t.albumArtist,
            album: t.album,
            coverPath: t.coverPath,
            trackNumber: t.trackNumber,
            trackTotal: t.trackTotal,
            discNumber: t.discNumber,
            discTotal: t.discTotal,
            year: t.year,
            genre: t.genre,
            bitrate: t.bitrate,
            sampleRate: t.sampleRate,
            duration: t.durationMs != null
                ? Duration(milliseconds: t.durationMs!)
                : null,
            cueRemotePath: t.cueRemotePath,
            cueTrackIndex: t.cueTrackIndex,
            audioRemotePath: t.audioRemotePath,
            clipStart: t.clipStartMs != null ? Duration(milliseconds: t.clipStartMs!) : null,
            clipEnd: t.clipEndMs != null ? Duration(milliseconds: t.clipEndMs!) : null,
            cacheGroupId: t.cacheGroupId,
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
