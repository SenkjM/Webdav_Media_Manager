import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
      MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: pl.id)),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    service.lastSyncError == null
                        ? '已同步歌单'
                        : '同步失败：${service.lastSyncError}',
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '新建',
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
                  '暂无歌单。点右上角「+」创建，或在音乐库长按曲目添加。\n'
                  '歌单保存在本地独立数据库，不会被音频缓存清理删除；'
                  '并可同步为 WebDAV 上的 M3U8 文件。',
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
                  leading: const Icon(Icons.queue_music, color: AppColors.accent),
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
                            content: Text('确定删除「${pl.name}」？本地与 WebDAV 上的对应文件都会删除。'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context),
        child: const Icon(Icons.add),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已添加到歌单')),
  );
}
