import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../services/audio_player_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import 'playlist_detail_screen.dart';
import '../utils/app_snack.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _createFromQueue(BuildContext context) async {
    final player = context.read<AudioPlayerService>();
    final queue = player.queue;
    if (queue.isEmpty) {
      AppSnack.show(context, '当前播放列表为空');
      return;
    }
    final controller = TextEditingController(
      text: '播放列表 ${DateTime.now().month}/${DateTime.now().day}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从当前播放列表创建'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '复制当前队列 ${queue.length} 首到新歌单。',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: '歌单名称'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
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
            title: t.displayTitle,
            durationMs: t.duration?.inMilliseconds,
          ),
        )
        .toList();
    final pl = await context.read<PlaylistService>().createFromQueue(
      name: name,
      queueEntries: entries,
    );
    if (!context.mounted) return;
    AppSnack.show(context, '已创建歌单「${pl.name}」');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: pl.id),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
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
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('歌单'),
        actions: [
          IconButton(
            tooltip: '从 WebDAV 同步',
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () async {
              await service.pullAndMergeFromWebDav();
              if (!context.mounted) return;
              AppSnack.show(
                context,
                service.lastSyncError == null
                    ? '已同步歌单'
                    : '同步失败：${service.lastSyncError}',
              );
            },
          ),
          IconButton(
            tooltip: '从当前播放列表创建',
            icon: const Icon(Icons.playlist_add_check),
            onPressed: () => _createFromQueue(context),
          ),
          IconButton(
            tooltip: '新建歌单',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context),
          ),
        ],
      ),
      body: service.playlists.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '暂无歌单：右上角「+」新建，或在音乐库长按曲目添加。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              ),
            )
          : ListView.builder(
              itemCount: service.playlists.length,
              itemBuilder: (context, i) {
                final pl = service.playlists[i];
                return ListTile(
                  leading: const Icon(
                    Icons.queue_music,
                    color: AppColors.accent,
                  ),
                  title: Text(pl.name),
                  subtitle: Text('${pl.length} 首'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'rename') {
                        final c = TextEditingController(text: pl.name);
                        final name = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('重命名歌单'),
                            content: TextField(controller: c, autofocus: true),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, c.text),
                                child: const Text('保存'),
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
                            title: const Text('删除歌单'),
                            content: Text(
                              '确定删除「${pl.name}」？本地与 WebDAV 上的对应文件都会删除。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await service.deletePlaylist(pl.id);
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
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
            label: const Text('从当前播放列表创建'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new_playlist',
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('新建歌单'),
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
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final list = service.playlists;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('添加到歌单')),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pl in list)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(pl.name),
                      onTap: () => Navigator.pop(ctx, pl.id),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建歌单…'),
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
        title: const Text('新建歌单'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('创建'),
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
  AppSnack.show(context, '已添加到歌单');
}

/// Add multiple entries to one playlist (or create).
Future<void> showAddManyToPlaylistDialog(
  BuildContext context,
  List<PlaylistEntry> entries,
) async {
  if (entries.isEmpty) return;
  final service = context.read<PlaylistService>();
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final list = service.playlists;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('添加 ${entries.length} 首到歌单')),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pl in list)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(pl.name),
                      onTap: () => Navigator.pop(ctx, pl.id),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建歌单…'),
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
        title: const Text('新建歌单'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('创建'),
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
  AppSnack.show(context, '已添加 ${entries.length} 首到歌单');
}
