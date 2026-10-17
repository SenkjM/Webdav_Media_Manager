import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_sentinels.dart';
import '../models/folder_view_mode.dart';
import '../models/library_track.dart';
import '../services/accounts_service.dart';
import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/task_queue_service.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/stream_cover_reader.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/meta_text.dart';
import '../utils/app_snack.dart';
import '../utils/back_handler_registry.dart';
import '../utils/selection_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';
import '../utils/library_group_cover.dart';
import '../widgets/selection_toolbar.dart';
import '../widgets/track_status_chip.dart';
import '../widgets/track_status_dot.dart';
import '../widgets/app_bottom_sheet.dart';
import '../services/playlist_service.dart';
import 'home_shell.dart';
import 'webdav_folder_picker_screen.dart';
import '../services/webdav_service.dart';
import '../models/webdav_stream.dart';
import '../utils/task_error.dart';
import '../utils/track_subtitle_lines.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: const DrawerMenuButton(),
          title: _searchOpen
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.searchPlaceholder,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                )
              : Text(l10n.library),
          actions: [
            IconButton(
              tooltip: _searchOpen ? l10n.closeSearch : l10n.searchAction,
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
            Builder(
              builder: (ctx) {
                final tab = DefaultTabController.of(ctx).index;
                const keys = ['albums', 'artists', 'titles', 'genres'];
                final key = keys[tab.clamp(0, 3)];
                final mode = settings.musicViewModeFor(key);
                return PopupMenuButton<FolderViewMode>(
                  tooltip: l10n.musicViewMode,
                  icon: Icon(mode.isGrid ? Icons.grid_view : Icons.view_list),
                  onSelected: (m) => settings.setMusicViewMode(key, m),
                  itemBuilder: (context) => [
                    for (final m in FolderViewMode.values)
                      PopupMenuItem(
                        value: m,
                        child: Row(
                          children: [
                            Icon(
                              mode == m
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(m.label(l10n)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            PopupMenuButton<LibrarySortMode>(
              tooltip: l10n.sortTooltip,
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
                        Text(mode.label(l10n)),
                      ],
                    ),
                  ),
              ],
              icon: const Icon(Icons.sort),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.tabAlbums),
              Tab(text: l10n.tabArtists),
              Tab(text: l10n.tabTitles),
              Tab(text: l10n.tabGenres),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            library.count == 0
                ? _LibraryEmpty()
                : _AlbumTab(
                    library: library,
                    query: _query,
                    viewMode: settings.musicViewModeFor('albums'),
                  ),
            library.count == 0
                ? _LibraryEmpty()
                : _ArtistTab(
                    library: library,
                    query: _query,
                    viewMode: settings.musicViewModeFor('artists'),
                  ),
            library.count == 0
                ? _LibraryEmpty()
                : _TitleTab(
                    library: library,
                    sort: settings.librarySort,
                    query: _query,
                    viewMode: settings.musicViewModeFor('titles'),
                  ),
            library.count == 0
                ? _LibraryEmpty()
                : _TagsTab(
                    library: library,
                    query: _query,
                    viewMode: settings.musicViewModeFor('genres'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _LibraryEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context)!.libraryEmptyGuide,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
    required this.viewMode,
  });
  final LibraryService library;
  final LibrarySortMode sort;
  final String query;
  final FolderViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final tracks = query.trim().isEmpty
        ? library.byTitle(sort: sort)
        : library.search(query, sort: sort);
    return _SelectableTrackList(
      tracks: tracks,
      emptyHint: AppLocalizations.of(context)!.libraryNoMatch,
    );
  }
}

class _ArtistTab extends StatelessWidget {
  const _ArtistTab({
    required this.library,
    required this.query,
    required this.viewMode,
  });
  final LibraryService library;
  final String query;
  final FolderViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    var groups = library.groupedByArtist();
    final q = query.trim().toLowerCase();
    final l10n = AppLocalizations.of(context)!;
    if (q.isNotEmpty) {
      groups = Map.fromEntries(
        groups.entries.where((e) {
          if (localizedLibraryGroupName(
            l10n,
            e.key,
          ).toLowerCase().contains(q)) {
            return true;
          }
          return e.value.any(
            (t) =>
                t.displayTitle.toLowerCase().contains(q) ||
                t.displayAlbumFor(l10n).toLowerCase().contains(q),
          );
        }),
      );
    }
    final artists = groups.keys.toList();
    return _SelectableGroupGrid(
      keys: artists,
      groups: groups,
      cache: cache,
      viewMode: viewMode,
      placeholderIcon: Icons.person_outline,
      subtitleOf: (tracks) =>
          AppLocalizations.of(context)!.playlistTrackCount(tracks.length),
      detailSort: LibrarySortMode.byName,
      dimensionId: 'artist',
    );
  }
}

class _AlbumTab extends StatelessWidget {
  const _AlbumTab({
    required this.library,
    required this.query,
    required this.viewMode,
  });
  final LibraryService library;
  final String query;
  final FolderViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    var groups = library.groupedByAlbum();
    final q = query.trim().toLowerCase();
    final l10n = AppLocalizations.of(context)!;
    if (q.isNotEmpty) {
      groups = Map.fromEntries(
        groups.entries.where((e) {
          if (localizedLibraryGroupName(
            l10n,
            e.key,
          ).toLowerCase().contains(q)) {
            return true;
          }
          return e.value.any(
            (t) =>
                t.displayTitle.toLowerCase().contains(q) ||
                t.displayArtistFor(l10n).toLowerCase().contains(q),
          );
        }),
      );
    }
    final albums = groups.keys.toList();
    return _SelectableGroupGrid(
      keys: albums,
      groups: groups,
      cache: cache,
      viewMode: viewMode,
      placeholderIcon: Icons.album,
      subtitleOf: (tracks) =>
          '${AppLocalizations.of(context)!.playlistTrackCount(tracks.length)} · ${tracks.first.displayArtistFor(AppLocalizations.of(context)!)}',
      detailSort: LibrarySortMode.byAlbumTrack,
      dimensionId: 'album',
    );
  }
}

class _TagsTab extends StatelessWidget {
  const _TagsTab({
    required this.library,
    required this.query,
    required this.viewMode,
  });
  final LibraryService library;
  final String query;
  final FolderViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    var groups = library.groupedByGenre();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      groups = Map.fromEntries(
        groups.entries.where(
          (e) =>
              e.key.toLowerCase().contains(q) ||
              e.value.any(
                (t) =>
                    t.displayTitle.toLowerCase().contains(q) ||
                    t.displayArtistFor(l10n).toLowerCase().contains(q) ||
                    t.displayAlbumFor(l10n).toLowerCase().contains(q),
              ),
        ),
      );
    }
    if (groups.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.genreEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final tags = groups.keys.toList();
    final cache = context.watch<CacheService>();
    return _SelectableGroupGrid(
      keys: tags,
      groups: groups,
      cache: cache,
      viewMode: viewMode,
      placeholderIcon: Icons.label_outline,
      subtitleOf: (tracks) =>
          AppLocalizations.of(context)!.playlistTrackCount(tracks.length),
      detailSort: LibrarySortMode.byName,
      dimensionId: 'genre',
    );
  }
}

class _SelectableGroupGrid extends StatefulWidget {
  const _SelectableGroupGrid({
    required this.keys,
    required this.groups,
    required this.cache,
    required this.viewMode,
    required this.placeholderIcon,
    required this.subtitleOf,
    required this.detailSort,
    this.dimensionId,
  });

  final List<String> keys;
  final Map<String, List<LibraryTrack>> groups;
  final CacheService cache;
  final FolderViewMode viewMode;
  final IconData placeholderIcon;
  final String Function(List<LibraryTrack>) subtitleOf;
  final LibrarySortMode detailSort;

  /// Tag dimension id for [LibraryGroupCoverOverrides] (e.g. album / artist).
  final String? dimensionId;

  @override
  State<_SelectableGroupGrid> createState() => _SelectableGroupGridState();
}

class _SelectableGroupGridState extends State<_SelectableGroupGrid> {
  /// 多选状态：全选判定按**计数对比**，见 [SelectionController]。
  SelectionController _selection = const SelectionController();

  bool get _selecting => _selection.active;
  Set<String> get _selected => _selection.selected;

  List<LibraryTrack> get _selectedTracks {
    final out = <LibraryTrack>[];
    final seen = <String>{};
    for (final k in _selected) {
      for (final t in widget.groups[k] ?? const <LibraryTrack>[]) {
        final id = '${t.sourceName}\u0000${t.remotePath}';
        if (seen.add(id)) out.add(t);
      }
    }
    return out;
  }

  void _exitSelect() => setState(() => _selection = _selection.exit());

  @override
  void initState() {
    super.initState();
    BackHandlerRegistry.register(_handleSystemBack, tab: 0);
  }

  @override
  void dispose() {
    BackHandlerRegistry.unregister(_handleSystemBack);
    super.dispose();
  }

  /// 多选时先吃掉返回键：退出多选，而不是退出这一页或回主页。
  ///
  /// 只在**当前路由**上生效：流派 / 专辑的子界面会把自己压在库页面之上，
  /// 那时预建在这里的实例不该越权处理子界面的返回键。子界面自己用
  /// `PopScope` 处理，不靠这里。
  bool _handleSystemBack() {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (_selection.active) {
      _exitSelect();
      return true;
    }
    return false;
  }

  /// 全选 / 取消全选。取消全选**不会**退出多选界面。
  void _toggleSelectAll() =>
      setState(() => _selection = _selection.toggleSelectAll(widget.keys));

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noMatchResult,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_selecting)
          _SelectionBar(
            count: _selection.count,
            allSelected: _selection.isAllSelected,
            hasCachedSelection: _selectedTracks.any(
              (t) => libraryTrackIsLocal(context.read<CacheService>(), t),
            ),
            onSelectAll: _toggleSelectAll,
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
            onUpdateTags: () async {
              final result = await refreshLibraryTrackTags(
                context,
                _selectedTracks,
              );
              if (context.mounted) {
                final status = result.cancelled
                    ? AppLocalizations.of(context)!.updateCancelled
                    : AppLocalizations.of(context)!.updateDone;
                AppSnack.show(
                  context,
                  AppLocalizations.of(context)!.updateSummary(
                    status,
                    result.updated,
                    result.skipped,
                    result.failed,
                  ),
                );
              }
              if (mounted) _exitSelect();
            },
            onDownload: () async {
              await downloadUncachedLibraryTracks(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
            onDestroy: () async {
              await destroyLibraryTracks(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
          ),
        Expanded(
          child: widget.viewMode.isGrid
              ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.viewMode.crossAxisCount!,
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
                    final title = localizedLibraryGroupName(
                      AppLocalizations.of(context)!,
                      key,
                    );
                    final dimId = widget.dimensionId;
                    final overridePath = dimId == null
                        ? null
                        : LibraryGroupCoverOverrides.resolver?.call(
                            dimensionId: dimId,
                            groupKey: key,
                          );
                    return _CoverTile(
                      coverTrack: coverTrack,
                      title: title,
                      subtitle: widget.subtitleOf(tracks),
                      placeholderIcon: widget.placeholderIcon,
                      selected: _selecting && selected,
                      selecting: _selecting,
                      coverOverridePath: overridePath,
                      onTap: () {
                        if (_selecting) {
                          setState(() => _selection = _selection.toggle(key));
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TrackListPage(
                              title: title,
                              tracks: tracks,
                              defaultSort: widget.detailSort,
                              viewKey: 'musicDetail:${widget.dimensionId}',
                            ),
                          ),
                        );
                      },
                      onLongPress: () {
                        setState(
                          () => _selection = _selection.enter(
                            key,
                            selectOnly: widget.keys,
                          ),
                        );
                      },
                    );
                  },
                )
              : ListView.builder(
                  itemCount: widget.keys.length,
                  itemBuilder: (context, i) {
                    final key = widget.keys[i];
                    final tracks = widget.groups[key]!;
                    final coverTrack = pickCoverTrack(tracks, widget.cache);
                    final selected = _selected.contains(key);
                    final title = localizedLibraryGroupName(
                      AppLocalizations.of(context)!,
                      key,
                    );
                    final dimId = widget.dimensionId;
                    final overridePath = dimId == null
                        ? null
                        : LibraryGroupCoverOverrides.resolver?.call(
                            dimensionId: dimId,
                            groupKey: key,
                          );
                    return ListTile(
                      selected: _selecting && selected,
                      leading: _selecting
                          ? Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            )
                          : (overridePath != null
                                ? CoverArt(
                                    size: 48,
                                    path: overridePath,
                                    icon: widget.placeholderIcon,
                                  )
                                : (coverTrack == null
                                      ? CoverArt(
                                          size: 48,
                                          icon: widget.placeholderIcon,
                                        )
                                      : LibraryCoverArt.forTrack(
                                          track: coverTrack,
                                          size: 48,
                                          borderRadius: 4,
                                          enqueueIfMissing: false,
                                        ))),
                      title: Text(title),
                      subtitle: MetaText(widget.subtitleOf(tracks)),
                      onTap: () {
                        if (_selecting) {
                          setState(() => _selection = _selection.toggle(key));
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TrackListPage(
                              title: title,
                              tracks: tracks,
                              defaultSort: widget.detailSort,
                              viewKey: 'musicDetail:${widget.dimensionId}',
                            ),
                          ),
                        );
                      },
                      onLongPress: () {
                        setState(
                          () => _selection = _selection.enter(
                            key,
                            selectOnly: widget.keys,
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Action bar shown in multi-select mode.
///
/// The 删除 button only appears when at least one selected track has a local
/// audio cache (there is nothing to delete otherwise); 销毁 is always available
/// and additionally removes library metadata + cached covers.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.hasCachedSelection,
    required this.onAdd,
    required this.onShare,
    required this.onDelete,
    required this.onUpdateTags,
    required this.onDownload,
    required this.onDestroy,
    required this.allSelected,
    required this.onSelectAll,
  });

  final int count;
  final bool hasCachedSelection;
  final VoidCallback onAdd;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onUpdateTags;
  final VoidCallback onDownload;
  final VoidCallback onDestroy;

  /// 选中数已经等于可选总数（**计数对比**，不看按钮按过没有）：
  /// 此时那个按钮是叉号，作用是取消全选，而不是退出多选。
  final bool allSelected;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    // 与网络库共用同一个外壳：宽度、滚动与底色不会再各写一套。
    return SelectionToolbar(
      children: [
        // 一进入多选这里只是「全选」；只有选中数打满时才变成叉号。
        // 退不出多选是故意的：返回键负责退出，那个按钮不该兼职关闭。
        if (allSelected)
          IconButton(
            tooltip: AppLocalizations.of(context)!.cancelSelection,
            onPressed: onSelectAll,
            icon: const Icon(Icons.deselect),
          )
        else
          IconButton(
            tooltip: AppLocalizations.of(context)!.selectAll,
            onPressed: count == 0 ? null : onSelectAll,
            icon: const Icon(Icons.select_all),
          ),
        // 不要用 Expanded：外壳里是横向滚动层，宽度无限，Expanded 会把整条
        // 工具栏搞炸。文字自然宽度即可。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            AppLocalizations.of(context)!.netSelectedCount(count),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context)!.playlistAddTo,
          onPressed: count == 0 ? null : onAdd,
          icon: const Icon(Icons.playlist_add),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context)!.shareAction,
          onPressed: count == 0 ? null : onShare,
          icon: const Icon(Icons.share_outlined),
        ),
        // No cached file in the selection → nothing to delete.
        if (hasCachedSelection)
          IconButton(
            tooltip: AppLocalizations.of(context)!.deleteCacheKeepMeta,
            onPressed: count == 0 ? null : onDelete,
            icon: const Icon(
              Icons.cleaning_services_outlined,
              color: AppColors.error,
            ),
          ),
        PopupMenuButton<String>(
          tooltip: AppLocalizations.of(context)!.moreActions,
          enabled: count > 0,
          onSelected: (action) {
            switch (action) {
              case 'tags':
                onUpdateTags();
                break;
              case 'download':
                onDownload();
                break;
              case 'destroy':
                onDestroy();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'tags',
              child: ListTile(
                leading: Icon(Icons.sell_outlined),
                title: Text(AppLocalizations.of(context)!.updateTags),
              ),
            ),
            PopupMenuItem(
              value: 'download',
              child: ListTile(
                leading: Icon(Icons.download_outlined),
                title: Text(
                  AppLocalizations.of(context)!.downloadUncachedTracks,
                ),
              ),
            ),
            PopupMenuItem(
              value: 'destroy',
              child: ListTile(
                leading: Icon(Icons.delete_forever, color: AppColors.error),
                title: Text(AppLocalizations.of(context)!.destroyLibraryAction),
              ),
            ),
          ],
        ),
      ],
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
    this.coverOverridePath,
  });

  final LibraryTrack? coverTrack;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? placeholderIcon;
  final bool selected;
  final bool selecting;

  /// Custom cover path from [LibraryGroupCoverOverrides]; null = album-cover fallback.
  final String? coverOverridePath;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.14)
          : Theme.of(context).colorScheme.surfaceContainer,
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
                    final override = coverOverridePath;
                    if (override != null && override.isNotEmpty) {
                      art = Center(
                        child: CoverArt(
                          path: override,
                          size: side,
                          borderRadius: 6,
                          icon: placeholderIcon,
                        ),
                      );
                    } else if (t == null) {
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
                                : Theme.of(context).colorScheme.outline,
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              MetaText(subtitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectableTrackList extends StatefulWidget {
  const _SelectableTrackList({
    super.key,
    required this.tracks,
    this.emptyHint,
    this.startInSelection = false,
    this.onSelectingChanged,
    this.viewMode = FolderViewMode.list,
  });

  final List<LibraryTrack> tracks;
  final String? emptyHint;

  /// Grid reuses this list's own selection state, so flipping the view never
  /// drops a selection.
  final FolderViewMode viewMode;
  final bool startInSelection;

  /// 多选开 / 关时通知父级。子界面靠它在自己的 `PopScope` 里决定返回键
  /// 归谁——不依赖任何「当前路由是谁」的猜测。
  final ValueChanged<bool>? onSelectingChanged;

  @override
  State<_SelectableTrackList> createState() => _SelectableTrackListState();
}

class _SelectableTrackListState extends State<_SelectableTrackList> {
  /// 多选状态：全选判定按**计数对比**，见 [SelectionController]。
  SelectionController _selection = const SelectionController();

  bool get _selecting => _selection.active;
  Set<String> get _selected => _selection.selected;

  List<String> get _allIds => widget.tracks.map(_id).toList();

  @override
  void initState() {
    super.initState();
    BackHandlerRegistry.register(_handleSystemBack, tab: 0);
    if (widget.startInSelection) {
      // 整组进来时选中全部：计数打满 → 工具栏那个按钮一开始就是叉号。
      _selection = _selection.enter(
        '',
        entry: SelectionEntry.selectAll,
        selectOnly: _allIds,
      );
      // 父级的 PopScope 要知道「进来就是多选」，否则第一次返回会被直接 pop。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSelectingChanged?.call(_selection.active);
      });
    }
  }

  @override
  void dispose() {
    BackHandlerRegistry.unregister(_handleSystemBack);
    super.dispose();
  }

  /// 多选时先吃掉返回键。
  ///
  /// 只在**当前路由**上生效。子界面（`_TrackListPage`）不靠这里：它自己的
  /// `PopScope` 拿 `canPop` 直接接管，那是最可靠的一层。
  bool _handleSystemBack() {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (_selection.active) {
      _exitSelect();
      return true;
    }
    return false;
  }

  /// 多选状态发生变化时同步给父级与全局返回处理器。
  void _setSelection(SelectionController next) {
    setState(() => _selection = next);
    widget.onSelectingChanged?.call(next.active);
  }

  bool get selecting => _selection.active;

  /// 供子界面的 `PopScope` 调用：多选中就退出多选并返回 true。
  bool handleSystemBack() {
    if (!mounted || !_selection.active) return false;
    _setSelection(_selection.exit());
    return true;
  }

  String _id(LibraryTrack t) => '${t.sourceName}\u0000${t.remotePath}';

  List<LibraryTrack> get _selectedTracks =>
      widget.tracks.where((t) => _selected.contains(_id(t))).toList();

  void _exitSelect() => _setSelection(_selection.exit());

  /// 全选 / 取消全选。取消全选**不会**退出多选界面。
  void _toggleSelectAll() => _setSelection(_selection.toggleSelectAll(_allIds));

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) {
      return Center(
        child: Text(
          widget.emptyHint ?? AppLocalizations.of(context)!.libraryTracksEmpty,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_selecting)
          _SelectionBar(
            count: _selection.count,
            allSelected: _selection.isAllSelected,
            hasCachedSelection: _selectedTracks.any(
              (t) => libraryTrackIsLocal(context.read<CacheService>(), t),
            ),
            onSelectAll: _toggleSelectAll,
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
            onUpdateTags: () async {
              final result = await refreshLibraryTrackTags(
                context,
                _selectedTracks,
              );
              if (context.mounted) {
                final status = result.cancelled
                    ? AppLocalizations.of(context)!.updateCancelled
                    : AppLocalizations.of(context)!.updateDone;
                AppSnack.show(
                  context,
                  AppLocalizations.of(context)!.updateSummary(
                    status,
                    result.updated,
                    result.skipped,
                    result.failed,
                  ),
                );
              }
              if (mounted) _exitSelect();
            },
            onDownload: () async {
              await downloadUncachedLibraryTracks(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
            onDestroy: () async {
              await destroyLibraryTracks(context, _selectedTracks);
              if (mounted) _exitSelect();
            },
          ),
        Expanded(
          child: widget.viewMode.isGrid
              ? GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.viewMode.crossAxisCount!,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: widget.tracks.length,
                  itemBuilder: (context, i) {
                    final track = widget.tracks[i];
                    return _TrackGridTile(
                      track: track,
                      playlist: widget.tracks,
                      selecting: _selecting,
                      selected: _selected.contains(_id(track)),
                      onToggleSelect: () =>
                          _setSelection(_selection.toggle(_id(track))),
                      onEnterSelect: () => _setSelection(
                        _selection.enter(_id(track), selectOnly: _allIds),
                      ),
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.tracks.length,
                  itemBuilder: (context, i) {
                    final track = widget.tracks[i];
                    return _TrackTile(
                      track: track,
                      playlist: widget.tracks,
                      selecting: _selecting,
                      selected: _selected.contains(_id(track)),
                      onToggleSelect: () =>
                          _setSelection(_selection.toggle(_id(track))),
                      onEnterSelect: () => _setSelection(
                        _selection.enter(_id(track), selectOnly: _allIds),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class TrackListPage extends StatefulWidget {
  const TrackListPage({
    super.key,
    required this.title,
    required this.tracks,
    required this.defaultSort,
    this.viewKey = 'trackList',
  });
  final String title;
  final List<LibraryTrack> tracks;
  final LibrarySortMode defaultSort;
  final bool startInSelection = false;

  /// View-mode slot. One key per page family, so the folder leaf and the music
  /// library's own drill-downs remember the same choice.
  final String viewKey;

  @override
  State<TrackListPage> createState() => _TrackListPageState();
}

class _TrackListPageState extends State<TrackListPage> {
  late LibrarySortMode _sort = widget.defaultSort;
  final _listKey = GlobalKey<_SelectableTrackListState>();

  /// 列表里是否正在多选。多选时 `canPop` 转 false，返回键改成「退出多选」。
  bool _selecting = false;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    final viewMode = settings.musicViewModeFor(widget.viewKey);
    final tracks = library.sortedCopy(widget.tracks, sort: _sort);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<FolderViewMode>(
            tooltip: l10n.folderViewMode,
            initialValue: viewMode,
            onSelected: (mode) =>
                unawaited(settings.setMusicViewMode(widget.viewKey, mode)),
            itemBuilder: (context) => [
              for (final mode in FolderViewMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Text(mode.label(AppLocalizations.of(context)!)),
                ),
            ],
            icon: Icon(viewMode.isGrid ? Icons.grid_view : Icons.view_list),
          ),
          PopupMenuButton<LibrarySortMode>(
            tooltip: AppLocalizations.of(context)!.sortTooltip,
            initialValue: _sort,
            onSelected: (mode) => setState(() => _sort = mode),
            itemBuilder: (context) => [
              for (final mode in LibrarySortMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Text(mode.label(AppLocalizations.of(context)!)),
                ),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: PopScope(
        // 多选中就把 pop 拦下来：这一层是子界面自己的，跟全局返回处理器、
        // 跟「谁在栈顶」的推断都无关。
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _listKey.currentState?.handleSystemBack();
        },
        child: _SelectableTrackList(
          key: _listKey,
          tracks: tracks,
          viewMode: viewMode,
          startInSelection: widget.startInSelection,
          onSelectingChanged: (selecting) {
            if (!mounted || selecting == _selecting) return;
            setState(() => _selecting = selecting);
          },
        ),
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
    final downloads = context.watch<TaskQueueService>();
    final isLocal = libraryTrackIsLocal(cache, track);
    // A library row can be re-queued after its cache was deleted, so surface the
    // queue state here too (network library already does).
    final task = downloads.taskForRemote(
      track.sourceName,
      track.effectiveAudioRemotePath,
    );
    // `read` (not `watch`): AudioPlayerService notifies on every position tick,
    // so watching it here would rebuild the whole list several times a second.
    final audio = context.read<AudioPlayerService>();
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
    final l10n = AppLocalizations.of(context)!;
    final subs = TrackSubtitleLines.of(track, l10n);
    return ListTile(
      dense: true,
      isThreeLine: subs.line2 != null,
      selected: selected,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
      leading: selecting
          ? Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected
                  ? AppColors.accent
                  : Theme.of(context).colorScheme.outline,
            )
          : LibraryCoverArt.forTrack(
              track: track,
              size: 52,
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MetaText(subs.line1),
          if (subs.line2 != null) MetaText(subs.line2!),
        ],
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
          TrackStatusDot(remoteMissing: track.remoteMissing, isLocal: isLocal),
          if (!selecting)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: AppLocalizations.of(context)!.moreActions,
              onPressed: () => unawaited(
                trackShowMoreMenu(context, track, playlist, isLocal: isLocal),
              ),
            ),
        ],
      ),
      onTap: () {
        if (selecting) {
          onToggleSelect?.call();
          return;
        }
        if (track.remoteMissing && !isLocal) {
          unawaited(trackOnRemoteMissingTap(context, track, playlist));
          return;
        }
        trackOnTap(context, track, playlist, isLocal: isLocal);
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

  /// Shared with [_TrackGridTile] so both views run the same code path.
  static Future<void> trackOnTap(
    BuildContext context,
    LibraryTrack track,
    List<LibraryTrack> playlist, {
    required bool isLocal,
    bool forceStream = false,
  }) async {
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
    for (final t in playlist) {
      // CUE slices join even without a local file: the unified player clips the
      // backing audio stream with start/end and falls back to cache-then-play
      // when the remote stream cannot seek.
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
    final effectiveLocal = forceStream ? null : local;
    final info = libraryTrackToTrackInfo(track, effectiveLocal, accountId);
    if (forceStream) {
      // One-shot stream: drop local paths so resolvePlayable uses URL.
      for (var i = 0; i < playlistInfos.length; i++) {
        final row = playlistInfos[i];
        playlistInfos[i] = TrackInfo(
          sourceName: row.sourceName,
          accountId: row.accountId,
          remotePath: row.remotePath,
          fileName: row.fileName,
          title: row.title,
          artist: row.artist,
          albumArtist: row.albumArtist,
          album: row.album,
          duration: row.duration,
          trackNumber: row.trackNumber,
          trackTotal: row.trackTotal,
          discNumber: row.discNumber,
          discTotal: row.discTotal,
          year: row.year,
          genre: row.genre,
          bitrate: row.bitrate,
          sampleRate: row.sampleRate,
          coverPath: row.coverPath,
          cueRemotePath: row.cueRemotePath,
          cueTrackIndex: row.cueTrackIndex,
          audioRemotePath: row.audioRemotePath,
          clipStart: row.clipStart,
          clipEnd: row.clipEnd,
          cacheGroupId: row.cacheGroupId,
        );
      }
    }
    if (playlistInfos.isEmpty) playlistInfos.add(info);
    if (!context.mounted) return;
    await player.playTrack(
      info,
      playlist: playlistInfos,
      forceStream: forceStream,
    );
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

  static Future<void> trackOnRemoteMissingTap(
    BuildContext context,
    LibraryTrack track,
    List<LibraryTrack> playlist,
  ) async {
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
      await context.read<PlaylistService>().setRemoteMissingForIdentities(
        identityKeys: [track.musicId],
        missing: false,
      );
      if (!context.mounted) return;
      await trackOnTap(context, track, playlist, isLocal: false);
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
        await destroyLibraryTracks(context, [track]);
        return;
      }
      if (action == 'redirect') {
        await _redirectTrack(context, track);
      }
    }
  }

  static Future<void> trackShowMoreMenu(
    BuildContext context,
    LibraryTrack track,
    List<LibraryTrack> playlist, {
    required bool isLocal,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      isScrollControlled: true,
      shape: AppBottomSheet.shape,
      builder: (ctx) {
        return AppBottomSheet(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              ListTile(
                leading: const Icon(Icons.stream),
                title: Text(l10n.libMenuStream),
                onTap: () => Navigator.pop(ctx, 'stream'),
              ),
              if (!isLocal)
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: Text(l10n.libMenuCache),
                  onTap: () => Navigator.pop(ctx, 'cache'),
                ),
              if (isLocal)
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(l10n.libMenuClear),
                  onTap: () => Navigator.pop(ctx, 'clear'),
                ),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: Text(l10n.updateTagsFromCache),
                onTap: () => Navigator.pop(ctx, 'tags_cache'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(l10n.updateTagsFromCloud),
                onTap: () => Navigator.pop(ctx, 'tags_cloud'),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.remoteMissingRedirect),
                onTap: () => Navigator.pop(ctx, 'redirect'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: Text(l10n.destroyAction),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'stream':
        await trackOnTap(
          context,
          track,
          playlist,
          isLocal: false,
          forceStream: true,
        );
        break;
      case 'cache':
        await enqueueLibraryTrackDownload(context, track);
        break;
      case 'clear':
        await deleteTracksLocalCache(context, [track]);
        break;
      case 'tags_cache':
        final updated = await refreshOneLibraryTrackTags(context, track);
        if (!context.mounted) return;
        AppSnack.show(
          context,
          updated
              ? AppLocalizations.of(context)!.tagsUpdatedFromLocal
              : AppLocalizations.of(context)!.tagsNeedDownloadFirst,
        );
        break;
      case 'tags_cloud':
        if (track.isCueVirtual) {
          AppSnack.show(
            context,
            AppLocalizations.of(context)!.tagsNeedDownloadFirst,
          );
          return;
        }
        await context.read<TaskQueueService>().enqueueRetagCloud(
          sourceName: track.sourceName,
          remotePath: track.remotePath,
          fileName: track.fileName,
        );
        if (context.mounted) {
          AppSnack.show(
            context,
            AppLocalizations.of(context)!.mediaScanQueued(1),
          );
        }
        break;
      case 'redirect':
        await _redirectTrack(context, track);
        break;
      case 'delete':
        await destroyLibraryTracks(context, [track]);
        break;
    }
  }

  static Future<void> _redirectTrack(
    BuildContext context,
    LibraryTrack track,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final accounts = context.read<AccountsService>();
    final accountId = accounts.idForSource(track.sourceName);
    if (accountId == null) {
      AppSnack.error(context, unboundSourceMessage(l10n, track.sourceName));
      return;
    }
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
    await playlists.setRemoteMissingForIdentities(
      identityKeys: [next.musicId, track.musicId],
      missing: false,
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

/// Grid cell counterpart of [_TrackTile]. Same tap / long-press / selection
/// semantics, same actions — only the layout differs.
class _TrackGridTile extends StatelessWidget {
  const _TrackGridTile({
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
    final downloads = context.watch<TaskQueueService>();
    final isLocal = libraryTrackIsLocal(cache, track);
    final task = downloads.taskForRemote(
      track.sourceName,
      track.effectiveAudioRemotePath,
    );
    // `read` (not `watch`): AudioPlayerService ticks on every position update.
    final audio = context.read<AudioPlayerService>();
    final state = libraryRowUiState(
      downloads: downloads,
      track: track,
      playingRemotePath: audio.currentRemotePath,
      playingSourceName: audio.currentSourceName,
    );
    final isDownloading = state == TrackUiState.downloading;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.14)
          : Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (selecting) {
            onToggleSelect?.call();
            return;
          }
          if (track.remoteMissing && !isLocal) {
            unawaited(
              _TrackTile.trackOnRemoteMissingTap(context, track, playlist),
            );
            return;
          }
          unawaited(
            _TrackTile.trackOnTap(context, track, playlist, isLocal: isLocal),
          );
        },
        onLongPress: () {
          if (selecting) {
            onToggleSelect?.call();
            return;
          }
          onEnterSelect?.call();
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide;
                    final art = Center(
                      child: LibraryCoverArt.forTrack(
                        track: track,
                        size: side,
                        borderRadius: 6,
                        enqueueIfMissing: false,
                      ),
                    );
                    if (!selecting && !isDownloading) return art;
                    return Stack(
                      children: [
                        art,
                        if (selecting)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: selected
                                  ? AppColors.accent
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        if (isDownloading)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                value: task?.progress,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isLocal
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              MetaText(TrackSubtitleLines.of(track, l10n).line1),
            ],
          ),
        ),
      ),
    );
  }
}
