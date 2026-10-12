import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_sentinels.dart';
import '../models/library_tag_dimension.dart';
import '../models/library_track.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/user_folder_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final folders = context.watch<UserFolderService>();
    final children = folders.childrenOf(_currentId);
    final items =
        _currentId == null ? const [] : folders.itemsIn(_currentId!);
    final path = folders.pathDisplay(_currentId);

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: MetaText(path),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.parentFolder,
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _stack.length <= 1
                        ? null
                        : () => setState(() => _stack.removeLast()),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'mkdir':
                          await _createFolder();
                        case 'album':
                          await _addRefs(
                            UserFolderRefKind.album,
                            l10n.folderAddAlbums,
                          );
                        case 'artist':
                          await _addRefs(
                            UserFolderRefKind.artist,
                            l10n.folderAddArtists,
                          );
                        case 'track':
                          await _addRefs(
                            UserFolderRefKind.track,
                            l10n.folderAddTracks,
                          );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'mkdir',
                        child: Text(l10n.newFolder),
                      ),
                      PopupMenuItem(
                        value: 'album',
                        child: Text(l10n.folderAddAlbums),
                      ),
                      PopupMenuItem(
                        value: 'artist',
                        child: Text(l10n.folderAddArtists),
                      ),
                      PopupMenuItem(
                        value: 'track',
                        child: Text(l10n.folderAddTracks),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
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
                  : ListView(
                      children: [
                        for (final f in children)
                          ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(f.name),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'rename') {
                                  await _renameFolder(f.id, f.name);
                                } else if (v == 'delete') {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(l10n.delete),
                                      content: Text(
                                        l10n.folderDeleteConfirm(f.name),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(l10n.cancel),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: Text(l10n.delete),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true && mounted) {
                                    await context
                                        .read<UserFolderService>()
                                        .deleteFolder(f.id);
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(l10n.rename),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l10n.delete),
                                ),
                              ],
                            ),
                            onTap: () => setState(() => _stack.add(f.id)),
                          ),
                        for (final item in items)
                          _FolderItemTile(
                            refKind: item.refKind,
                            refKey: item.refKey,
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

class _FolderItemTile extends StatelessWidget {
  const _FolderItemTile({
    required this.refKind,
    required this.refKey,
    required this.onOpen,
    required this.onRemove,
  });

  final String refKind;
  final String refKey;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final library = context.watch<LibraryService>();
    late final IconData icon;
    late final String title;
    String? subtitle;
    switch (refKind) {
      case UserFolderRefKind.album:
        icon = Icons.album;
        title = localizedLibraryGroupName(l10n, refKey);
        subtitle = l10n.playlistTrackCount(
          library.tracks.where((t) => t.displayAlbum == refKey).length,
        );
      case UserFolderRefKind.artist:
        icon = Icons.person_outline;
        title = localizedLibraryGroupName(l10n, refKey);
        subtitle = l10n.playlistTrackCount(
          library.tracks.where((t) => t.displayArtist == refKey).length,
        );
      case UserFolderRefKind.track:
        icon = Icons.music_note;
        LibraryTrack? found;
        for (final t in library.tracks) {
          if (t.musicId == refKey) {
            found = t;
            break;
          }
        }
        title = found?.displayTitle ?? refKey;
        subtitle = found == null
            ? l10n.folderRefMissing
            : '${found.displayArtistFor(l10n)} · ${found.displayAlbumFor(l10n)}';
      default:
        icon = Icons.label_outline;
        title = refKey;
    }
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : MetaText(subtitle),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        tooltip: l10n.delete,
        onPressed: onRemove,
      ),
      onTap: onOpen,
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
          return ListTile(
            title: Text(t.displayTitle),
            subtitle: MetaText(
              '${t.displayArtistFor(l10n)} · ${t.displayAlbumFor(l10n)}',
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
