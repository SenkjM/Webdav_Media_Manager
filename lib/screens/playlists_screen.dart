import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/playlist.dart';
import '../models/playlist_sentinels.dart';
import '../services/audio_player_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/meta_text.dart';
import 'home_shell.dart';
import 'playlist_detail_screen.dart';
import '../utils/app_snack.dart';

String _playlistDisplayName(BuildContext context, String name) {
  final l10n = AppLocalizations.of(context)!;
  return isUnnamedPlaylistName(name) ? l10n.unnamedPlaylist : name;
}

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _createFromQueue(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final player = context.read<AudioPlayerService>();
    final queue = player.queue;
    if (queue.isEmpty) {
      AppSnack.show(context, l10n.playlistQueueEmpty);
      return;
    }
    final controller = TextEditingController(
      text: l10n.playlistQueueDefaultName(
        DateTime.now().month,
        DateTime.now().day,
      ),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.playlistCreateFromQueue),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.playlistCreateFromQueueBody(queue.length),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.playlistNameLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final entries = queue
        .map(
          (t) => PlaylistEntry(
            sourceName: t.sourceName,
            remotePath: t.remotePath,
            musicId: t.musicId,
            title: t.displayTitle,
            durationMs: t.duration?.inMilliseconds,
            cueTrackIndex: t.cueTrackIndex,
          ),
        )
        .toList();
    final pl = await context.read<PlaylistService>().createFromQueue(
      name: name,
      queueEntries: entries,
    );
    if (!context.mounted) return;
    AppSnack.show(
      context,
      l10n.playlistCreated(_playlistDisplayName(context, pl.name)),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: pl.id),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.playlistNew),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.nameLabel),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final pl = await context.read<PlaylistService>().create(name: name);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: pl.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(l10n.playlistsTitle),
        actions: [
          IconButton(
            tooltip: l10n.playlistSyncTooltip,
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () async {
              await service.pullAndMergeFromWebDav();
              if (!context.mounted) return;
              AppSnack.show(
                context,
                service.lastSyncError == null
                    ? l10n.playlistSynced
                    : l10n.playlistSyncFailed(service.lastSyncError!),
              );
            },
          ),
          IconButton(
            tooltip: l10n.playlistCreateFromQueue,
            icon: const Icon(Icons.playlist_add_check),
            onPressed: () => _createFromQueue(context),
          ),
          IconButton(
            tooltip: l10n.playlistNew,
            icon: const Icon(Icons.add),
            onPressed: () => _create(context),
          ),
        ],
      ),
      body: service.playlists.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.playlistsEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ),
            )
          : ListView.builder(
              itemCount: service.playlists.length,
              itemBuilder: (context, i) {
                final pl = service.playlists[i];
                return ListTile(
                  leading: Icon(
                    Icons.queue_music,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(_playlistDisplayName(context, pl.name)),
                  subtitle: MetaText(l10n.playlistTrackCount(pl.length)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'rename') {
                        final c = TextEditingController(
                          text: _playlistDisplayName(context, pl.name),
                        );
                        final name = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              AppLocalizations.of(context)!.playlistRename,
                            ),
                            content: TextField(controller: c, autofocus: true),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(
                                  AppLocalizations.of(context)!.cancel,
                                ),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, c.text),
                                child: Text(AppLocalizations.of(context)!.save),
                              ),
                            ],
                          ),
                        );
                        if (name != null && context.mounted) {
                          await service.rename(pl.id, name);
                        }
                      } else if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              AppLocalizations.of(context)!.playlistDelete,
                            ),
                            content: Text(
                              AppLocalizations.of(context)!
                                  .playlistDeleteConfirm(pl.name),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(
                                  AppLocalizations.of(context)!.cancel,
                                ),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(
                                  AppLocalizations.of(context)!.delete,
                                ),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await service.deletePlaylist(pl.id);
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(AppLocalizations.of(context)!.rename),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(AppLocalizations.of(context)!.delete),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(playlistId: pl.id),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'from_queue',
            onPressed: () => _createFromQueue(context),
            icon: const Icon(Icons.playlist_add_check),
            label: Text(l10n.playlistCreateFromQueue),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new_playlist',
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.playlistNew),
          ),
        ],
      ),
    );
  }
}

/// Dialog to pick a playlist (or create) and add [entry].
Future<void> showAddToPlaylistDialog(
  BuildContext context,
  PlaylistEntry entry,
) async {
  final service = context.read<PlaylistService>();
  final l10n = AppLocalizations.of(context)!;
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final list = service.playlists;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.playlistAddTo)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pl in list)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(_playlistDisplayName(context, pl.name)),
                      onTap: () => Navigator.pop(ctx, pl.id),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(l10n.playlistNewEllipsis),
                    onTap: () => Navigator.pop(ctx, '__new__'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == '__new__') {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.playlistNew),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final pl = await service.create(name: name);
    await service.addTrack(pl.id, entry);
  } else {
    await service.addTrack(choice, entry);
  }
  if (!context.mounted) return;
  AppSnack.show(context, l10n.playlistAdded);
}

/// Add multiple entries to one playlist (or create).
Future<void> showAddManyToPlaylistDialog(
  BuildContext context,
  List<PlaylistEntry> entries,
) async {
  if (entries.isEmpty) return;
  final service = context.read<PlaylistService>();
  final l10n = AppLocalizations.of(context)!;
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final list = service.playlists;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.playlistAddMany(entries.length))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pl in list)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(_playlistDisplayName(context, pl.name)),
                      onTap: () => Navigator.pop(ctx, pl.id),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(l10n.playlistNewEllipsis),
                    onTap: () => Navigator.pop(ctx, '__new__'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  String playlistId = choice;
  if (choice == '__new__') {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.playlistNew),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final pl = await service.create(name: name);
    playlistId = pl.id;
  }
  for (final e in entries) {
    await service.addTrack(playlistId, e);
  }
  if (!context.mounted) return;
  AppSnack.show(context, l10n.playlistAddedMany(entries.length));
}
