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
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';
import '../widgets/meta_text.dart';
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

  String? get _currentId => _stack.last;

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
            onSelected: (mode) =>
                context.read<SettingsService>().setFolderViewMode(mode),
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
    final items =
        _currentId == null ? const <UserFolderItem>[] : folders.itemsIn(_currentId!);
    final path = folders.pathDisplay(_currentId);
    final viewMode = settings.folderViewMode;

    return PopScope(
      canPop: !widget.embedded || _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_stack.length > 1) setState(() => _stack.removeLast());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: widget.embedded ? null : AppBar(title: Text(l10n.myFolders)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pathChrome(path: path, viewMode: viewMode, l10n: l10n),
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
                          onOpenFolder: (f) =>
                              setState(() => _stack.add(f.id)),
                          onRenameFolder: (f) => _renameFolder(f.id, f.name),
                          onDeleteFolder: _deleteFolder,
                          onOpenItem: (item) =>
                              _openGroup(item.refKind, item.refKey),
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
                                onOpen: () =>
                                    setState(() => _stack.add(f.id)),
                                onRename: () => _renameFolder(f.id, f.name),
                                onDelete: () => _deleteFolder(f),
                              ),
                            for (final item in items)
                              _FolderItemTile(
                                refKind: item.refKind,
                                refKey: item.refKey,
                                library: library,
                                cache: cache,
                                onOpen: () =>
                                    _openGroup(item.refKind, item.refKey),
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
  });

  final UserFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: CoverArt(
        size: 48,
        borderRadius: 6,
        icon: Icons.folder_outlined,
      ),
      title: Text(folder.name),
      trailing: PopupMenuButton<String>(
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
    );
  }
}

class _FolderItemTile extends StatelessWidget {
  const _FolderItemTile({
    required this.refKind,
    required this.refKey,
    required this.library,
    required this.cache,
    required this.onOpen,
    required this.onRemove,
  });

  final String refKind;
  final String refKey;
  final LibraryService library;
  final CacheService cache;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final resolved = _resolveItem(l10n);
    return ListTile(
      // Keep density close to a single-subtitle tile: two MetaText lines share
      // the subtitle slot without extra outer padding.
      isThreeLine: resolved.subtitleLine2 != null,
      leading: resolved.cover,
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
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        tooltip: l10n.delete,
        onPressed: onRemove,
      ),
      onTap: onOpen,
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
        final album = found.displayAlbumFor(l10n);
        final trackNo = found.trackNumber != null
            ? l10n.folderTrackNumber(found.trackNumber!)
            : l10n.folderTrackNumberUnknown;
        return _ResolvedFolderItem(
          title: found.displayTitle,
          subtitleLine1: album,
          subtitleLine2: trackNo,
          cover: LibraryCoverArt.forTrack(
            track: found,
            size: 48,
            borderRadius: 4,
            enqueueIfMissing: false,
          ),
        );
      default:
        // Future dimensions (genre, …): album-cover fallback + custom override hook.
        final tracks = <LibraryTrack>[];
        return _ResolvedFolderItem(
          title: localizedLibraryGroupName(l10n, refKey),
          subtitleLine1: null,
          cover: buildLibraryGroupCover(
            dimensionId: refKind,
            groupKey: refKey,
            groupTracks: tracks,
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
  final void Function(UserFolder) onOpenFolder;
  final void Function(UserFolder) onRenameFolder;
  final void Function(UserFolder) onDeleteFolder;
  final void Function(UserFolderItem) onOpenItem;
  final void Function(UserFolderItem) onRemoveItem;

  @override
  Widget build(BuildContext context) {
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
          return _FolderGridCell(
            title: e.folder!.name,
            columns: columns,
            coverBuilder: (size) => CoverArt(
              size: size,
              borderRadius: 6,
              icon: Icons.folder_outlined,
            ),
            onTap: () => onOpenFolder(e.folder!),
            menuItems: [
              (value: 'rename', label: AppLocalizations.of(context)!.rename),
              (value: 'delete', label: AppLocalizations.of(context)!.delete),
            ],
            onMenu: (v) {
              if (v == 'rename') onRenameFolder(e.folder!);
              if (v == 'delete') onDeleteFolder(e.folder!);
            },
          );
        }
        final item = e.item!;
        final resolved = _resolveGridItem(context, item);
        return _FolderGridCell(
          title: resolved.title,
          subtitle: resolved.subtitle,
          columns: columns,
          coverBuilder: resolved.coverBuilder,
          onTap: () => onOpenItem(item),
          menuItems: [
            (value: 'remove', label: AppLocalizations.of(context)!.delete),
          ],
          onMenu: (v) {
            if (v == 'remove') onRemoveItem(item);
          },
        );
      },
    );
  }

  ({String title, String? subtitle, Widget Function(double size) coverBuilder})
      _resolveGridItem(
    BuildContext context,
    UserFolderItem item,
  ) {
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
            coverBuilder: (size) => CoverArt(size: size, icon: Icons.music_note),
          );
        }
        final track = found;
        return (
          title: track.displayTitle,
          subtitle: track.displayAlbumFor(l10n),
          coverBuilder: (size) => LibraryCoverArt.forTrack(
            track: track,
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
  });

  final String title;
  final String? subtitle;
  final int columns;
  final Widget Function(double size) coverBuilder;
  final VoidCallback onTap;
  final List<({String value, String label})> menuItems;
  final void Function(String) onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(columns >= 4 ? 6 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide;
                    // Scale 「更多」 with cell size so dense grids stay clean.
                    final moreSize =
                        (side * 0.22).clamp(14.0, columns >= 4 ? 22.0 : 28.0);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(child: coverBuilder(side)),
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
                MetaText(subtitle!),
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
          final album = t.displayAlbumFor(l10n);
          final trackNo = t.trackNumber != null
              ? l10n.folderTrackNumber(t.trackNumber!)
              : l10n.folderTrackNumberUnknown;
          return ListTile(
            isThreeLine: true,
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
                MetaText(album),
                MetaText(trackNo),
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
