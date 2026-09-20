import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';
import 'home_shell.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final settings = context.watch<SettingsService>();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.nearBlack,
        appBar: AppBar(
          leading: const DrawerMenuButton(),
          title: _searchOpen
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜索标题 / 艺术家 / 专辑',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                  style: const TextStyle(color: AppColors.onDark, fontSize: 16),
                  onChanged: (v) => setState(() => _query = v),
                )
              : const Text('音乐库'),
          actions: [
            IconButton(
              tooltip: _searchOpen ? '关闭搜索' : '搜索',
              icon: Icon(_searchOpen ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    _query = '';
                  }
                });
              },
            ),
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
            isScrollable: true,
            tabs: [
              Tab(text: '专辑'),
              Tab(text: '作者'),
              Tab(text: '音乐名'),
              Tab(text: '标签'),
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
                  _AlbumTab(library: library, query: _query),
                  _ArtistTab(library: library, query: _query),
                  _TitleTab(
                    library: library,
                    sort: settings.librarySort,
                    query: _query,
                  ),
                  _TagsTab(library: library, query: _query),
                ],
              ),
      ),
    );
  }
}

class _TitleTab extends StatelessWidget {
  const _TitleTab({
    required this.library,
    required this.sort,
    required this.query,
  });
  final LibraryService library;
  final LibrarySortMode sort;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tracks = query.trim().isEmpty
        ? library.byTitle(sort: sort)
        : library.search(query, sort: sort);
    return _SelectableTrackList(tracks: tracks, emptyHint: '无匹配曲目');
  }
}

class _ArtistTab extends StatelessWidget {
  const _ArtistTab({required this.library, required this.query});
  final LibraryService library;
  final String query;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    var groups = library.groupedByArtist();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      groups = Map.fromEntries(
        groups.entries.where((e) {
          if (e.key.toLowerCase().contains(q)) return true;
          return e.value.any((t) =>
              t.displayTitle.toLowerCase().contains(q) ||
              t.displayAlbum.toLowerCase().contains(q));
        }),
      );
    }
    final artists = groups.keys.toList();
    return _SelectableGroupGrid(
      keys: artists,
      groups: groups,
      cache: cache,
      placeholderIcon: Icons.person_outline,
      subtitleOf: (tracks) => '${tracks.length} 首',
      detailSort: LibrarySortMode.byName,
    );
  }
}

class _AlbumTab extends StatelessWidget {
  const _AlbumTab({required this.library, required this.query});
  final LibraryService library;
  final String query;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    var groups = library.groupedByAlbum();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      groups = Map.fromEntries(
        groups.entries.where((e) {
          if (e.key.toLowerCase().contains(q)) return true;
          return e.value.any((t) =>
              t.displayTitle.toLowerCase().contains(q) ||
              t.displayArtist.toLowerCase().contains(q));
        }),
      );
    }
    final albums = groups.keys.toList();
    return _SelectableGroupGrid(
      keys: albums,
      groups: groups,
      cache: cache,
      placeholderIcon: Icons.album,
      subtitleOf: (tracks) =>
          '${tracks.length} 首 · ${tracks.first.displayArtist}',
      detailSort: LibrarySortMode.byAlbumTrack,
    );
  }
}

class _TagsTab extends StatelessWidget {
  const _TagsTab({required this.library, required this.query});
  final LibraryService library;
  final String query;

  @override
  Widget build(BuildContext context) {
    var groups = library.groupedByGenre();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      groups = Map.fromEntries(
        groups.entries.where((e) =>
            e.key.toLowerCase().contains(q) ||
            e.value.any((t) =>
                t.displayTitle.toLowerCase().contains(q) ||
                t.displayArtist.toLowerCase().contains(q) ||
                t.displayAlbum.toLowerCase().contains(q))),
      );
    }
    if (groups.isEmpty) {
      return const Center(
        child: Text(
          '暂无标签。下载带有流派（genre）等元数据的曲目后会出现在此。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.secondaryText),
        ),
      );
    }
    final tags = groups.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tags.length,
      itemBuilder: (context, i) {
        final tag = tags[i];
        final tracks = groups[tag]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.elevatedHigh,
            child: Icon(
              tag == '未分类' ? Icons.label_off_outlined : Icons.label_outline,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          title: Text(tag, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${tracks.length} 首'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(
                  title: tag,
                  tracks: tracks,
                  defaultSort: LibrarySortMode.byName,
                ),
              ),
            );
          },
          onLongPress: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TrackListPage(
                  title: tag,
                  tracks: tracks,
                  defaultSort: LibrarySortMode.byName,
                  startInSelection: true,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SelectableGroupGrid extends StatefulWidget {
  const _SelectableGroupGrid({
    required this.keys,
    required this.groups,
    required this.cache,
    required this.placeholderIcon,
    required this.subtitleOf,
    required this.detailSort,
  });

  final List<String> keys;
  final Map<String, List<LibraryTrack>> groups;
  final CacheService cache;
  final IconData placeholderIcon;
  final String Function(List<LibraryTrack>) subtitleOf;
  final LibrarySortMode detailSort;

  @override
  State<_SelectableGroupGrid> createState() => _SelectableGroupGridState();
}

class _SelectableGroupGridState extends State<_SelectableGroupGrid> {
  bool _selecting = false;
  final Set<String> _selected = {};

  List<LibraryTrack> get _selectedTracks {
    final out = <LibraryTrack>[];
    final seen = <String>{};
    for (final k in _selected) {
      for (final t in widget.groups[k] ?? const <LibraryTrack>[]) {
        final id = '${t.accountId}\u0000${t.remotePath}';
        if (seen.add(id)) out.add(t);
      }
    }
    return out;
  }

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty) {
      return const Center(
        child: Text('无匹配结果', style: TextStyle(color: AppColors.secondaryText)),
      );
    }
    return Column(
      children: [
        if (_selecting) _SelectionBar(
          count: _selected.length,
          onCancel: _exitSelect,
          onAdd: () async {
            await addTracksToPlaylist(context, _selectedTracks);
            if (mounted) _exitSelect();
          },
          onShare: () async {
            await shareLibraryTracks(context, _selectedTracks);
            if (mounted) _exitSelect();
          },
          onDelete: () async {
            await deleteTracksLocalCache(context, _selectedTracks);
            if (mounted) _exitSelect();
          },
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: widget.keys.length,
            itemBuilder: (context, i) {
              final key = widget.keys[i];
              final tracks = widget.groups[key]!;
              final coverTrack = pickCoverTrack(tracks, widget.cache);
              final selected = _selected.contains(key);
              return _CoverTile(
                coverTrack: coverTrack,
                title: key,
                subtitle: widget.subtitleOf(tracks),
                placeholderIcon: widget.placeholderIcon,
                selected: _selecting && selected,
                selecting: _selecting,
                onTap: () {
                  if (_selecting) {
                    setState(() {
                      if (selected) {
                        _selected.remove(key);
                        if (_selected.isEmpty) _selecting = false;
                      } else {
                        _selected.add(key);
                      }
                    });
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _TrackListPage(
                        title: key,
                        tracks: tracks,
                        defaultSort: widget.detailSort,
                      ),
                    ),
                  );
                },
                onLongPress: () {
                  setState(() {
                    _selecting = true;
                    _selected.add(key);
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onAdd,
    required this.onShare,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onAdd;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.elevated,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '取消',
                onPressed: onCancel,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  '已选 $count 项',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '添加到歌单',
                onPressed: count == 0 ? null : onAdd,
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: '分享',
                onPressed: count == 0 ? null : onShare,
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: count == 0 ? null : onDelete,
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.coverTrack,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.placeholderIcon,
    this.selected = false,
    this.selecting = false,
  });

  final LibraryTrack? coverTrack;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? placeholderIcon;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.14) : AppColors.elevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
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
                    Widget art;
                    if (t == null) {
                      art = Center(
                        child: CoverArt(
                          size: side,
                          borderRadius: 6,
                          icon: placeholderIcon,
                        ),
                      );
                    } else {
                      art = Center(
                        child: LibraryCoverArt.forTrack(
                          track: t,
                          size: side,
                          borderRadius: 6,
                          icon: placeholderIcon,
                          enqueueIfMissing: false,
                        ),
                      );
                    }
                    if (!selecting) return art;
                    return Stack(
                      children: [
                        art,
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected
                                ? AppColors.accent
                                : AppColors.mutedText,
                          ),
                        ),
                      ],
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

class _SelectableTrackList extends StatefulWidget {
  const _SelectableTrackList({
    required this.tracks,
    this.emptyHint = '暂无曲目',
    this.startInSelection = false,
  });

  final List<LibraryTrack> tracks;
  final String emptyHint;
  final bool startInSelection;

  @override
  State<_SelectableTrackList> createState() => _SelectableTrackListState();
}

class _SelectableTrackListState extends State<_SelectableTrackList> {
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    if (widget.startInSelection) {
      _selecting = true;
      for (final t in widget.tracks) {
        _selected.add('${t.accountId}\u0000${t.remotePath}');
      }
    }
  }

  String _id(LibraryTrack t) => '${t.accountId}\u0000${t.remotePath}';

  List<LibraryTrack> get _selectedTracks =>
      widget.tracks.where((t) => _selected.contains(_id(t))).toList();

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) {
      return Center(
        child: Text(
          widget.emptyHint,
          style: const TextStyle(color: AppColors.secondaryText),
        ),
      );
    }
    return Column(
      children: [
        if (_selecting)
          _SelectionBar(
            count: _selected.length,
            onCancel: _exitSelect,
            onAdd: () async {
              await addTracksToPlaylist(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
            onShare: () async {
              await shareLibraryTracks(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
            onDelete: () async {
              await deleteTracksLocalCache(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.tracks.length,
            itemBuilder: (context, i) {
              final track = widget.tracks[i];
              return _TrackTile(
                track: track,
                playlist: widget.tracks,
                selecting: _selecting,
                selected: _selected.contains(_id(track)),
                onToggleSelect: () {
                  setState(() {
                    final id = _id(track);
                    if (_selected.contains(id)) {
                      _selected.remove(id);
                      if (_selected.isEmpty) _selecting = false;
                    } else {
                      _selected.add(id);
                    }
                  });
                },
                onEnterSelect: () {
                  setState(() {
                    _selecting = true;
                    _selected.add(_id(track));
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrackListPage extends StatefulWidget {
  const _TrackListPage({
    required this.title,
    required this.tracks,
    required this.defaultSort,
    this.startInSelection = false,
  });
  final String title;
  final List<LibraryTrack> tracks;
  final LibrarySortMode defaultSort;
  final bool startInSelection;

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
      body: _SelectableTrackList(
        tracks: tracks,
        startInSelection: widget.startInSelection,
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.playlist,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
    this.onEnterSelect,
  });
  final LibraryTrack track;
  final List<LibraryTrack> playlist;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onEnterSelect;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    final isLocal = libraryTrackIsLocal(cache, track);
    final trackLabel = track.trackNumber != null ? '${track.trackNumber}. ' : '';
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
      leading: selecting
          ? Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppColors.accent : AppColors.mutedText,
            )
          : LibraryCoverArt.forTrack(
              track: track,
              size: 52,
              borderRadius: 4,
              enqueueIfMissing: false,
            ),
      title: Text(
        '$trackLabel${track.displayTitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isLocal ? AppColors.onDark : AppColors.secondaryText,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        [
          if (track.isCueVirtual) LibraryTrack.cueMultiSliceLabel,
          if (!isLocal) '未下载',
          track.displayArtist,
          if (isLocal) track.displayAlbum,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
      ),
      trailing: Tooltip(
        message: isLocal ? '已下载到本地' : '未下载（点按加入下载）',
        child: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isLocal ? AppColors.localReady : AppColors.remotePlaceholder,
            border: Border.all(
              color: isLocal
                  ? AppColors.localReady.withValues(alpha: 0.4)
                  : AppColors.divider,
              width: 1,
            ),
          ),
        ),
      ),
      onTap: () {
        if (selecting) {
          onToggleSelect?.call();
          return;
        }
        _onTap(context, isLocal: isLocal);
      },
      onLongPress: () {
        if (selecting) {
          onToggleSelect?.call();
          return;
        }
        onEnterSelect?.call();
      },
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
      accountId: track.accountId,
    );
    if (local == null) {
      // Race: cache deleted between check and play — treat as download link.
      if (context.mounted) {
        await enqueueLibraryTrackDownload(context, track);
      }
      return;
    }
    // Only local tracks enter the play queue.
    final localPlaylist = <TrackInfo>[];
    for (final t in playlist) {
      final path = await cache.localPathIfCached(
        t.effectiveAudioRemotePath,
        accountId: t.accountId,
      );
      if (path == null) continue;
      localPlaylist.add(_toTrackInfo(t, path));
    }
    final info = _toTrackInfo(track, local);
    if (localPlaylist.isEmpty) {
      localPlaylist.add(info);
    }
    if (!context.mounted) return;
    await player.playTrack(info, playlist: localPlaylist);
  }

  static TrackInfo _toTrackInfo(LibraryTrack track, String? local) {
    return TrackInfo(
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
      clipStart: track.clipStartMs != null
          ? Duration(milliseconds: track.clipStartMs!)
          : null,
      clipEnd: track.clipEndMs != null
          ? Duration(milliseconds: track.clipEndMs!)
          : null,
      cacheGroupId: track.cacheGroupId,
    );
  }
}
