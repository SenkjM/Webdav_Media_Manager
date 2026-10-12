import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/folder_view_mode.dart';
import '../models/library_sentinels.dart';
import '../models/library_tag_dimension.dart';
import '../models/library_track.dart';
import '../models/user_folder.dart';
import '../models/user_folder_item.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../services/user_folder_service.dart';
import '../utils/library_group_cover.dart';
import '../utils/selection_controller.dart';
import '../utils/track_subtitle_lines.dart';
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';
import '../widgets/meta_text.dart';
import '../widgets/selection_toolbar.dart';
import 'library_folder_picker_screen.dart';
import 'library_tag_picker_screen.dart';

/// Network-library-style browser for the local user folder tree (99 §18).
class LibraryFolderBrowserScreen extends StatefulWidget {
  const LibraryFolderBrowserScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<LibraryFolderBrowserScreen> createState() =>
      _LibraryFolderBrowserScreenState();
}

class _LibraryFolderBrowserScreenState
    extends State<LibraryFolderBrowserScreen> {
  final List<String?> _stack = [null];
  SelectionController _selection = const SelectionController();

  String? get _currentId => _stack.last;
  bool get _selecting => _selection.active;

  String _folderKey(UserFolder f) => 'f:${f.id}';
  String _itemKey(UserFolderItem i) =>
      'i:${i.folderId}|${i.refKind}|${i.refKey}';

  List<String> _allKeys(
    List<UserFolder> children,
    List<UserFolderItem> items,
  ) =>
      [
        for (final f in children) _folderKey(f),
        for (final i in items) _itemKey(i),
      ];

  String _typeLabel(AppLocalizations l10n, String refKind) => switch (refKind) {
        UserFolderRefKind.album => l10n.folderTypeAlbum,
        UserFolderRefKind.artist => l10n.folderTypeArtist,
        UserFolderRefKind.track => l10n.folderTypeTrack,
        'genre' => l10n.folderTypeGenre,
        _ => refKind,
      };

  Future<String?> _askName({
    required String title,
    required String initial,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askName(
      title: l10n.newFolder,
      initial: l10n.newFolderDefaultName,
    );
    if (name == null || !mounted) return;
    await context.read<UserFolderService>().createFolder(
          parentId: _currentId,
          name: name.isEmpty ? l10n.newFolderDefaultName : name,
        );
  }

  Future<void> _renameFolder(String id, String current) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askName(title: l10n.rename, initial: current);
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<UserFolderService>().renameFolder(id, name);
  }

  Future<void> _deleteFolder(UserFolder f) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.folderDeleteConfirm(f.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<UserFolderService>().deleteFolder(f.id);
    }
  }

  Future<void> _deleteSelected(
    List<UserFolder> children,
    List<UserFolderItem> items,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final folders = [
      for (final f in children)
        if (_selection.contains(_folderKey(f))) f,
    ];
    final refs = [
      for (final i in items)
        if (_selection.contains(_itemKey(i))) i,
    ];
    if (folders.isEmpty && refs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.folderDeleteSelected),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = context.read<UserFolderService>();
    for (final f in folders) {
      await svc.deleteFolder(f.id);
    }
    for (final i in refs) {
      await svc.removeRef(
        folderId: i.folderId,
        refKind: i.refKind,
        refKey: i.refKey,
      );
    }
    if (!mounted) return;
    setState(() => _selection = _selection.exit());
  }

  Future<void> _addRefs(String refKind, String title) async {
    var folderId = _currentId;
    if (folderId == null) {
      folderId = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => LibraryFolderPickerScreen(purpose: title),
        ),
      );
      if (folderId == null || !mounted) return;
    }
    final keys = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) =>
            LibraryTagPickerScreen(refKind: refKind, title: title),
      ),
    );
    if (keys == null || keys.isEmpty || !mounted) return;
    final n = await context.read<UserFolderService>().addRefs(
          folderId: folderId,
          refKind: refKind,
          refKeys: keys,
        );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.folderItemsAdded(n))),
    );
  }

  LibraryTrack? _trackById(LibraryService library, String musicId) {
    for (final t in library.tracks) {
      if (t.musicId == musicId) return t;
    }
    return null;
  }

  Future<void> _openGroup(String refKind, String refKey) async {
    final library = context.read<LibraryService>();
    final l10n = AppLocalizations.of(context)!;
    if (refKind == UserFolderRefKind.track) {
      final t = _trackById(library, refKey);
      if (t == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.folderRefMissing)),
        );
        return;
      }
      await _play(tracks: [t], start: t);
      return;
    }
    final dim = LibraryTagDimension.byId(refKind);
    if (dim == null) return;
    final tracks = [
      for (final t in library.tracks)
        if (dim.groupKey(t) == refKey) t,
    ];
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.folderRefMissing)),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FolderTrackListPage(
          title: dim.displayName(l10n, refKey),
          tracks: tracks,
        ),
      ),
    );
  }

  Future<void> _play({
    required List<LibraryTrack> tracks,
    required LibraryTrack start,
  }) async {
    final player = context.read<AudioPlayerService>();
    final accounts = context.read<AccountsService>();
    final infos = [
      for (final t in tracks)
        libraryTrackToTrackInfo(
          t,
          null,
          accounts.idForSource(t.sourceName) ?? '',
        ),
    ];
    final idx = tracks.indexWhere((t) => t.musicId == start.musicId);
    if (idx < 0) return;
    await player.playTrack(infos[idx], playlist: infos);
  }

  Future<void> _onAddMenu(String v) async {
    final l10n = AppLocalizations.of(context)!;
    switch (v) {
      case 'mkdir':
        await _createFolder();
      case 'album':
        await _addRefs(UserFolderRefKind.album, l10n.folderAddAlbums);
      case 'artist':
        await _addRefs(UserFolderRefKind.artist, l10n.folderAddArtists);
      case 'track':
        await _addRefs(UserFolderRefKind.track, l10n.folderAddTracks);
    }
  }

  List<PopupMenuEntry<String>> _addMenuItems(AppLocalizations l10n) => [
        PopupMenuItem(value: 'mkdir', child: Text(l10n.newFolder)),
        PopupMenuItem(value: 'album', child: Text(l10n.folderAddAlbums)),
        PopupMenuItem(value: 'artist', child: Text(l10n.folderAddArtists)),
        PopupMenuItem(value: 'track', child: Text(l10n.folderAddTracks)),
      ];

  Widget _pathChrome({
    required String path,
    required FolderViewMode viewMode,
    required AppLocalizations l10n,
    required String? folderId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                    child: Text(path),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.parentFolder,
            icon: const Icon(Icons.arrow_upward, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: _stack.length <= 1
                ? null
                : () => setState(() => _stack.removeLast()),
          ),
          PopupMenuButton<FolderViewMode>(
            tooltip: l10n.folderViewMode,
            icon: Icon(
              viewMode.isGrid ? Icons.grid_view : Icons.view_list,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            onSelected: (mode) => context
                .read<SettingsService>()
                .setFolderViewMode(mode, folderId: folderId),
            itemBuilder: (context) => [
              for (final mode in FolderViewMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Row(
                    children: [
                      Icon(
                        viewMode == mode
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
          ),
          if (!_selecting)
            PopupMenuButton<String>(
              tooltip: l10n.folderAddMenu,
              icon: const Icon(Icons.add, size: 22),
              padding: EdgeInsets.zero,
              onSelected: _onAddMenu,
              itemBuilder: (context) => _addMenuItems(l10n),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final folders = context.watch<UserFolderService>();
    final settings = context.watch<SettingsService>();
    final library = context.watch<LibraryService>();
    final cache = context.watch<CacheService>();
    final children = folders.childrenOf(_currentId);
    final items = _currentId == null
        ? const <UserFolderItem>[]
        : folders.itemsIn(_currentId!);
    final path = folders.pathDisplay(_currentId);
    final viewMode = settings.folderViewModeFor(_currentId);
    final keys = _allKeys(children, items);
    final synced = _selection.sync(total: keys.length, validKeys: keys);
    if (synced.count != _selection.count || synced.total != _selection.total) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selection = synced);
      });
    }

    return PopScope(
      canPop: (!_selecting) && (!widget.embedded || _stack.length <= 1),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          setState(() => _selection = _selection.exit());
          return;
        }
        if (_stack.length > 1) setState(() => _stack.removeLast());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: widget.embedded ? null : AppBar(title: Text(l10n.myFolders)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selecting)
              SelectionToolbar(
                children: [
                  if (_selection.showsDeselect)
                    IconButton(
                      tooltip: l10n.cancelSelection,
                      icon: const Icon(Icons.deselect),
                      onPressed: () => setState(
                        () => _selection = _selection.toggleSelectAll(keys),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: l10n.selectAll,
                      icon: const Icon(Icons.select_all),
                      onPressed: keys.isEmpty
                          ? null
                          : () => setState(
                                () => _selection =
                                    _selection.toggleSelectAll(keys),
                              ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${_selection.count}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: l10n.moreActions,
                    enabled: _selection.count > 0,
                    onSelected: (v) {
                      if (v == 'delete') {
                        unawaited(_deleteSelected(children, items));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.folderDeleteSelected),
                      ),
                    ],
                  ),
                ],
              )
            else
              _pathChrome(
                path: path,
                viewMode: viewMode,
                l10n: l10n,
                folderId: _currentId,
              ),
            Expanded(
              child: children.isEmpty && items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.folderEmptyHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : viewMode.isGrid
                      ? _FolderGridBody(
                          columns: viewMode.crossAxisCount!,
                          children: children,
                          items: items,
                          library: library,
                          cache: cache,
                          selecting: _selecting,
                          selection: _selection,
                          folderKeyOf: _folderKey,
                          itemKeyOf: _itemKey,
                          typeLabelOf: _typeLabel,
                          onEnterSelect: (key) => setState(() {
                            _selection = _selection
                                .enter(key, selectOnly: keys)
                                .sync(total: keys.length, validKeys: keys);
                          }),
                          onOpenFolder: (f) {
                            if (_selecting) {
                              setState(
                                () => _selection =
                                    _selection.toggle(_folderKey(f)),
                              );
                              return;
                            }
                            setState(() => _stack.add(f.id));
                          },
                          onRenameFolder: (f) => _renameFolder(f.id, f.name),
                          onDeleteFolder: _deleteFolder,
                          onOpenItem: (item) {
                            if (_selecting) {
                              setState(
                                () => _selection =
                                    _selection.toggle(_itemKey(item)),
                              );
                              return;
                            }
                            _openGroup(item.refKind, item.refKey);
                          },
                          onRemoveItem: (item) async {
                            await context.read<UserFolderService>().removeRef(
                                  folderId: item.folderId,
                                  refKind: item.refKind,
                                  refKey: item.refKey,
                                );
                          },
                        )
                      : ListView(
                          children: [
                            for (final f in children)
                              _FolderListTile(
                                folder: f,
                                selecting: _selecting,
                                selected:
                                    _selection.contains(_folderKey(f)),
                                onOpen: () {
                                  if (_selecting) {
                                    setState(
                                      () => _selection =
                                          _selection.toggle(_folderKey(f)),
                                    );
                                    return;
                                  }
                                  setState(() => _stack.add(f.id));
                                },
                                onLongPress: () => setState(() {
                                  _selection = _selection
                                      .enter(
                                        _folderKey(f),
                                        selectOnly: keys,
                                      )
                                      .sync(
                                        total: keys.length,
                                        validKeys: keys,
                                      );
                                }),
                                onRename: () =>
                                    _renameFolder(f.id, f.name),
                                onDelete: () => _deleteFolder(f),
                              ),
                            for (final item in items)
                              _FolderItemTile(
                                refKind: item.refKind,
                                refKey: item.refKey,
                                library: library,
                                cache: cache,
                                typeLabel:
                                    _typeLabel(l10n, item.refKind),
                                selecting: _selecting,
                                selected:
                                    _selection.contains(_itemKey(item)),
                                onOpen: () {
                                  if (_selecting) {
                                    setState(
                                      () => _selection = _selection
                                          .toggle(_itemKey(item)),
                                    );
                                    return;
                                  }
                                  _openGroup(item.refKind, item.refKey);
                                },
                                onLongPress: () => setState(() {
                                  _selection = _selection
                                      .enter(
                                        _itemKey(item),
                                        selectOnly: keys,
                                      )
                                      .sync(
                                        total: keys.length,
                                        validKeys: keys,
                                      );
                                }),
                                onRemove: () async {
                                  await context
                                      .read<UserFolderService>()
                                      .removeRef(
                                        folderId: item.folderId,
                                        refKind: item.refKind,
                                        refKey: item.refKey,
                                      );
                                },
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderListTile extends StatelessWidget {
  const _FolderListTile({
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final UserFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      leading: selecting
          ? Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.outline,
            )
          : CoverArt(
              size: 48,
              borderRadius: 6,
              icon: Icons.folder_outlined,
            ),
      title: Text(folder.name),
      // Folder nodes: no type chip on the right.
      trailing: selecting
          ? null
          : PopupMenuButton<String>(
              tooltip: l10n.moreActions,
              onSelected: (v) {
                if (v == 'rename') onRename();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
              ],
            ),
      onTap: onOpen,
      onLongPress: onLongPress,
    );
  }
}

class _FolderItemTile extends StatelessWidget {
  const _FolderItemTile({
    required this.refKind,
    required this.refKey,
    required this.library,
    required this.cache,
    required this.typeLabel,
    required this.onOpen,
    required this.onRemove,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final String refKind;
  final String refKey;
  final LibraryService library;
  final CacheService cache;
  final String typeLabel;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final resolved = _resolveItem(l10n);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      isThreeLine: resolved.subtitleLine2 != null,
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      leading: selecting
          ? Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.outline,
            )
          : resolved.cover,
      title: Text(
        resolved.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: resolved.subtitleLine2 == null
          ? (resolved.subtitleLine1 == null
              ? null
              : MetaText(resolved.subtitleLine1!))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (resolved.subtitleLine1 != null)
                  MetaText(resolved.subtitleLine1!),
                MetaText(resolved.subtitleLine2!),
              ],
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              typeLabel,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          if (!selecting)
            PopupMenuButton<String>(
              tooltip: l10n.moreActions,
              onSelected: (v) {
                if (v == 'remove') onRemove();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'remove', child: Text(l10n.delete)),
              ],
            ),
        ],
      ),
      onTap: onOpen,
      onLongPress: onLongPress,
    );
  }

  _ResolvedFolderItem _resolveItem(AppLocalizations l10n) {
    switch (refKind) {
      case UserFolderRefKind.album:
      case UserFolderRefKind.artist:
        final dim = LibraryTagDimension.byId(refKind)!;
        final tracks = [
          for (final t in library.tracks)
            if (dim.groupKey(t) == refKey) t,
        ];
        final icon = refKind == UserFolderRefKind.album
            ? Icons.album
            : Icons.person_outline;
        return _ResolvedFolderItem(
          title: dim.displayName(l10n, refKey),
          subtitleLine1: l10n.playlistTrackCount(tracks.length),
          cover: buildLibraryGroupCover(
            dimensionId: refKind,
            groupKey: refKey,
            groupTracks: tracks,
            cache: cache,
            size: 48,
            placeholderIcon: icon,
          ),
        );
      case UserFolderRefKind.track:
        LibraryTrack? found;
        for (final t in library.tracks) {
          if (t.musicId == refKey) {
            found = t;
            break;
          }
        }
        if (found == null) {
          return _ResolvedFolderItem(
            title: refKey,
            subtitleLine1: l10n.folderRefMissing,
            cover: CoverArt(size: 48, icon: Icons.music_note),
          );
        }
        final subs = TrackSubtitleLines.of(found, l10n);
        return _ResolvedFolderItem(
          title: found.displayTitle,
          subtitleLine1: subs.line1,
          subtitleLine2: subs.line2,
          cover: LibraryCoverArt.forTrack(
            track: found,
            size: 48,
            borderRadius: 4,
            enqueueIfMissing: false,
          ),
        );
      default:
        return _ResolvedFolderItem(
          title: localizedLibraryGroupName(l10n, refKey),
          subtitleLine1: null,
          cover: buildLibraryGroupCover(
            dimensionId: refKind,
            groupKey: refKey,
            groupTracks: const [],
            cache: cache,
            size: 48,
            placeholderIcon: Icons.label_outline,
          ),
        );
    }
  }
}

class _ResolvedFolderItem {
  const _ResolvedFolderItem({
    required this.title,
    required this.cover,
    this.subtitleLine1,
    this.subtitleLine2,
  });

  final String title;
  final String? subtitleLine1;
  final String? subtitleLine2;
  final Widget cover;
}

class _FolderGridBody extends StatelessWidget {
  const _FolderGridBody({
    required this.columns,
    required this.children,
    required this.items,
    required this.library,
    required this.cache,
    required this.selecting,
    required this.selection,
    required this.folderKeyOf,
    required this.itemKeyOf,
    required this.typeLabelOf,
    required this.onEnterSelect,
    required this.onOpenFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenItem,
    required this.onRemoveItem,
  });

  final int columns;
  final List<UserFolder> children;
  final List<UserFolderItem> items;
  final LibraryService library;
  final CacheService cache;
  final bool selecting;
  final SelectionController selection;
  final String Function(UserFolder) folderKeyOf;
  final String Function(UserFolderItem) itemKeyOf;
  final String Function(AppLocalizations, String) typeLabelOf;
  final void Function(String key) onEnterSelect;
  final void Function(UserFolder) onOpenFolder;
  final void Function(UserFolder) onRenameFolder;
  final void Function(UserFolder) onDeleteFolder;
  final void Function(UserFolderItem) onOpenItem;
  final void Function(UserFolderItem) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = <_GridEntry>[
      for (final f in children) _GridEntry.folder(f),
      for (final i in items) _GridEntry.item(i),
    ];
    final aspect = columns >= 4 ? 0.70 : (columns == 3 ? 0.75 : 0.82);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: aspect,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        if (e.folder != null) {
          final f = e.folder!;
          final key = folderKeyOf(f);
          return _FolderGridCell(
            title: f.name,
            columns: columns,
            selected: selecting && selection.contains(key),
            selecting: selecting,
            coverBuilder: (size) => CoverArt(
              size: size,
              borderRadius: 6,
              icon: Icons.folder_outlined,
            ),
            onTap: () => onOpenFolder(f),
            onLongPress: () => onEnterSelect(key),
            typeLabel: null,
            menuItems: selecting
                ? const []
                : [
                    (value: 'rename', label: l10n.rename),
                    (value: 'delete', label: l10n.delete),
                  ],
            onMenu: (v) {
              if (v == 'rename') onRenameFolder(f);
              if (v == 'delete') onDeleteFolder(f);
            },
          );
        }
        final item = e.item!;
        final key = itemKeyOf(item);
        final resolved = _resolveGridItem(context, item);
        return _FolderGridCell(
          title: resolved.title,
          subtitle: resolved.subtitle,
          columns: columns,
          selected: selecting && selection.contains(key),
          selecting: selecting,
          coverBuilder: resolved.coverBuilder,
          onTap: () => onOpenItem(item),
          onLongPress: () => onEnterSelect(key),
          typeLabel: typeLabelOf(l10n, item.refKind),
          menuItems: selecting
              ? const []
              : [
                  (value: 'remove', label: l10n.delete),
                ],
          onMenu: (v) {
            if (v == 'remove') onRemoveItem(item);
          },
        );
      },
    );
  }

  ({String title, String? subtitle, Widget Function(double size) coverBuilder})
      _resolveGridItem(BuildContext context, UserFolderItem item) {
    final l10n = AppLocalizations.of(context)!;
    switch (item.refKind) {
      case UserFolderRefKind.album:
      case UserFolderRefKind.artist:
        final dim = LibraryTagDimension.byId(item.refKind)!;
        final tracks = [
          for (final t in library.tracks)
            if (dim.groupKey(t) == item.refKey) t,
        ];
        final icon = item.refKind == UserFolderRefKind.album
            ? Icons.album
            : Icons.person_outline;
        return (
          title: dim.displayName(l10n, item.refKey),
          subtitle: l10n.playlistTrackCount(tracks.length),
          coverBuilder: (size) => buildLibraryGroupCover(
            dimensionId: item.refKind,
            groupKey: item.refKey,
            groupTracks: tracks,
            cache: cache,
            size: size,
            placeholderIcon: icon,
          ),
        );
      case UserFolderRefKind.track:
        LibraryTrack? found;
        for (final t in library.tracks) {
          if (t.musicId == item.refKey) {
            found = t;
            break;
          }
        }
        if (found == null) {
          return (
            title: item.refKey,
            subtitle: l10n.folderRefMissing,
            coverBuilder: (size) =>
                CoverArt(size: size, icon: Icons.music_note),
          );
        }
        final subs = TrackSubtitleLines.of(found, l10n);
        return (
          title: found.displayTitle,
          subtitle: subs.line2 == null
              ? subs.line1
              : '${subs.line1}\n${subs.line2}',
          coverBuilder: (size) => LibraryCoverArt.forTrack(
            track: found!,
            size: size,
            borderRadius: 6,
            enqueueIfMissing: false,
          ),
        );
      default:
        return (
          title: localizedLibraryGroupName(l10n, item.refKey),
          subtitle: null,
          coverBuilder: (size) => buildLibraryGroupCover(
            dimensionId: item.refKind,
            groupKey: item.refKey,
            groupTracks: const [],
            cache: cache,
            size: size,
            placeholderIcon: Icons.label_outline,
          ),
        );
    }
  }
}

class _GridEntry {
  const _GridEntry.folder(this.folder) : item = null;
  const _GridEntry.item(this.item) : folder = null;
  final UserFolder? folder;
  final UserFolderItem? item;
}

class _FolderGridCell extends StatelessWidget {
  const _FolderGridCell({
    required this.title,
    required this.columns,
    required this.coverBuilder,
    required this.onTap,
    required this.menuItems,
    required this.onMenu,
    this.subtitle,
    this.typeLabel,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final String? typeLabel;
  final int columns;
  final Widget Function(double size) coverBuilder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<({String value, String label})> menuItems;
  final void Function(String) onMenu;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.all(columns >= 4 ? 6 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide;
                    final moreSize =
                        (side * 0.22).clamp(14.0, columns >= 4 ? 22.0 : 28.0);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(child: coverBuilder(side)),
                        if (selecting)
                          Positioned(
                            top: -2,
                            left: -2,
                            child: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: moreSize,
                              color:
                                  selected ? scheme.primary : scheme.outline,
                            ),
                          ),
                        if (!selecting && menuItems.isNotEmpty)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Material(
                              color: scheme.surface.withValues(alpha: 0.72),
                              shape: const CircleBorder(),
                              child: SizedBox(
                                width: moreSize,
                                height: moreSize,
                                child: PopupMenuButton<String>(
                                  tooltip: l10n.moreActions,
                                  padding: EdgeInsets.zero,
                                  iconSize: moreSize * 0.65,
                                  icon: Icon(
                                    Icons.more_vert,
                                    size: moreSize * 0.65,
                                  ),
                                  onSelected: onMenu,
                                  itemBuilder: (context) => [
                                    for (final m in menuItems)
                                      PopupMenuItem(
                                        value: m.value,
                                        child: Text(m.label),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (typeLabel != null)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    scheme.surface.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                typeLabel!,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: columns >= 4 ? 9 : 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(height: columns >= 4 ? 4 : 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: columns >= 4 ? 11 : 13,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                MetaText(subtitle!, maxLines: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTrackListPage extends StatelessWidget {
  const _FolderTrackListPage({required this.title, required this.tracks});

  final String title;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final t = tracks[i];
          final subs = TrackSubtitleLines.of(t, l10n);
          return ListTile(
            dense: true,
            isThreeLine: subs.line2 != null,
            leading: LibraryCoverArt.forTrack(
              track: t,
              size: 48,
              borderRadius: 4,
              enqueueIfMissing: false,
            ),
            title: Text(
              t.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MetaText(subs.line1),
                if (subs.line2 != null) MetaText(subs.line2!),
              ],
            ),
            onTap: () async {
              final player = context.read<AudioPlayerService>();
              final accounts = context.read<AccountsService>();
              final infos = [
                for (final x in tracks)
                  libraryTrackToTrackInfo(
                    x,
                    null,
                    accounts.idForSource(x.sourceName) ?? '',
                  ),
              ];
              await player.playTrack(infos[i], playlist: infos);
            },
          );
        },
      ),
    );
  }
}
