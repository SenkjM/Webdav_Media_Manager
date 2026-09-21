import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../utils/cue_sheet.dart';
import '../services/download_queue_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import 'home_shell.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  /// Collapse CUE cache-group members into one queue row.
  static List<_QueueRow> _rowsFor(
    List<DownloadTask> tasksNewestFirst,
    DownloadQueueService queue,
  ) {
    final seenGroups = <String>{};
    final rows = <_QueueRow>[];
    for (final t in tasksNewestFirst) {
      final gid = t.cacheGroupId;
      if (gid != null && gid.startsWith('cue')) {
        if (seenGroups.contains(gid)) continue;
        seenGroups.add(gid);
        // Prefer live generation so cancelled leftovers never inflate the row.
        var members = tasksNewestFirst
            .where(
              (x) =>
                  x.cacheGroupId == gid &&
                  x.status != DownloadStatus.cancelled &&
                  x.status != DownloadStatus.failed,
            )
            .toList();
        if (members.isEmpty) {
          members = tasksNewestFirst
              .where((x) => x.cacheGroupId == gid)
              .toList();
        }
        // Dedupe by remotePath (keep newest).
        final byPath = <String, DownloadTask>{};
        for (final m in members) {
          final prev = byPath[m.remotePath];
          if (prev == null || m.createdAt.isAfter(prev.createdAt)) {
            byPath[m.remotePath] = m;
          }
        }
        rows.add(_QueueRow.cueGroup(gid, byPath.values.toList(), queue));
      } else {
        rows.add(_QueueRow.single(t));
      }
    }
    return rows;
  }

  /// Clear every queue entry. Always asks first: unlike clearing completed rows,
  /// this also drops pending/failed entries and cancels running transfers.
  Future<void> _confirmClearAll(
    BuildContext context,
    DownloadQueueService queue,
    List<DownloadTask> tasks,
  ) async {
    final running = tasks
        .where(
          (t) =>
              t.status == DownloadStatus.active ||
              t.status == DownloadStatus.pending,
        )
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('清除所有队列？'),
        content: Text(
          '将移除 ${tasks.length} 条队列记录${running > 0 ? '，并取消 $running 个进行中的下载' : ''}；已下载的文件保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await queue.clearAll();
    if (!context.mounted) return;
    AppSnack.show(context, '下载队列已清空');
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<DownloadQueueService>();
    final tasks = queue.tasks.reversed.toList();
    final rows = _rowsFor(tasks, queue);

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('下载队列'),
        actions: [
          TextButton(
            onPressed: tasks.any((t) => t.status == DownloadStatus.completed)
                ? () => queue.clearCompleted()
                : null,
            child: const Text('清除已完成'),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              if (v == 'clear_all') _confirmClearAll(context, queue, tasks);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear_all',
                enabled: tasks.isNotEmpty,
                child: const Text(
                  '清除所有队列',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: rows.isEmpty
          ? const Center(
              child: Text(
                '暂无下载任务',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row.isCueGroup) {
                  return _CueGroupTile(
                    members: row.members,
                    groupId: row.groupId!,
                    songCount: row.songCount,
                  );
                }
                return _TaskTile(task: row.members.first);
              },
            ),
    );
  }
}

class _QueueRow {
  _QueueRow._(
    this.members, {
    required this.isCueGroup,
    this.groupId,
    this.songCount,
  });
  factory _QueueRow.single(DownloadTask t) =>
      _QueueRow._([t], isCueGroup: false);
  factory _QueueRow.cueGroup(
    String id,
    List<DownloadTask> members,
    DownloadQueueService queue,
  ) => _QueueRow._(
    members,
    isCueGroup: true,
    groupId: id,
    songCount: queue.cueSongCountForGroup(id),
  );

  final List<DownloadTask> members;
  final bool isCueGroup;
  final String? groupId;
  final int? songCount;
}

class _CueGroupTile extends StatelessWidget {
  const _CueGroupTile({
    required this.members,
    required this.groupId,
    this.songCount,
  });

  final List<DownloadTask> members;
  final String groupId;
  final int? songCount;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<DownloadQueueService>();
    final cue = members.cast<DownloadTask?>().firstWhere(
      (t) => t!.remotePath.toLowerCase().endsWith('.cue'),
      orElse: () => null,
    );
    final title = cue?.fileName ?? members.first.fileName;
    var songs = songCount ?? queue.cueSongCountForGroup(groupId);
    if (songs == null) {
      final cueFile = cue?.localPath;
      if (cueFile != null && File(cueFile).existsSync()) {
        try {
          final sheet = CueSheetParser.tryParse(
            decodeCueText(File(cueFile).readAsBytesSync()),
          );
          if (sheet != null) {
            songs = sheet.tracks.length;
            queue.rememberCueSongCount(groupId, songs);
          }
        } catch (_) {}
      }
    }
    final failed = members.any((t) => t.status == DownloadStatus.failed);
    final active = members.any((t) => t.status == DownloadStatus.active);
    final pending = members.any((t) => t.status == DownloadStatus.pending);
    final allDone =
        members.isNotEmpty &&
        members.every((t) => t.status == DownloadStatus.completed);
    final (label, color) = failed
        ? ('失败', AppColors.error)
        : active
        ? ('下载中', AppColors.accent)
        : pending
        ? ('等待中', AppColors.mutedText)
        : allDone
        ? ('已完成', const Color(0xFF66BB6A))
        : ('进行中', AppColors.mutedText);
    final progress = members.isEmpty
        ? 0.0
        : members.map((t) => t.progress).reduce((a, b) => a + b) /
              members.length;
    final songLabel = songs != null && songs > 0 ? '$songs 首歌' : 'CUE 专辑';

    return Card(
      color: AppColors.elevated,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.album, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              songLabel,
              style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
            ),
            if (active || pending) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: active ? progress.clamp(0.0, 1.0) : null,
                  minHeight: 4,
                  backgroundColor: AppColors.elevatedHigh,
                  color: AppColors.accent,
                ),
              ),
              if (active) ...[
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (pending || active)
                  TextButton(
                    onPressed: () {
                      for (final t in members) {
                        if (t.status == DownloadStatus.pending ||
                            t.status == DownloadStatus.active) {
                          queue.cancel(t.id);
                        }
                      }
                    },
                    child: const Text('取消'),
                  ),
                if (failed)
                  TextButton(
                    onPressed: () {
                      for (final t in members) {
                        if (t.status == DownloadStatus.failed ||
                            t.status == DownloadStatus.cancelled) {
                          queue.retry(t.id);
                        }
                      }
                    },
                    child: const Text('重试'),
                  ),
                TextButton(
                  onPressed: () {
                    for (final t in members) {
                      queue.remove(t.id);
                    }
                  },
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<DownloadQueueService>();
    final (label, color) = switch (task.status) {
      DownloadStatus.pending => ('等待中', AppColors.mutedText),
      DownloadStatus.active => ('下载中', AppColors.accent),
      DownloadStatus.completed => ('已完成', const Color(0xFF66BB6A)),
      DownloadStatus.failed => ('失败', AppColors.error),
      DownloadStatus.cancelled => ('已取消', AppColors.mutedText),
    };
    final savedToGallery =
        task.isGallery && task.status == DownloadStatus.completed;
    final savedToDownloads =
        task.target == DownloadTarget.downloads &&
        task.status == DownloadStatus.completed;

    return Card(
      color: AppColors.elevated,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    task.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.isGallery)
                  _DestinationChip(
                    icon: Icons.photo_library_outlined,
                    label: savedToGallery ? '已存入系统相册' : '目标：系统相册',
                    color: AppColors.accent,
                  ),
                if (task.target == DownloadTarget.downloads)
                  _DestinationChip(
                    icon: Icons.folder_outlined,
                    label: savedToDownloads ? '已存入下载目录' : '目标：下载目录',
                    color: AppColors.accent,
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (task.status == DownloadStatus.active) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.elevatedHigh,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(task.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                ),
              ),
            ],
            if (task.target != DownloadTarget.cache &&
                task.status == DownloadStatus.completed) ...[
              const SizedBox(height: 4),
              Text(
                '${task.target.labelZh}：${task.localPath ?? ''}',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (task.errorMessage != null &&
                task.status == DownloadStatus.failed) ...[
              const SizedBox(height: 4),
              Text(
                task.errorMessage!,
                style: const TextStyle(color: AppColors.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.status == DownloadStatus.pending ||
                    task.status == DownloadStatus.active)
                  TextButton(
                    onPressed: () => queue.cancel(task.id),
                    child: const Text('取消'),
                  ),
                if (task.status == DownloadStatus.failed ||
                    task.status == DownloadStatus.cancelled)
                  TextButton(
                    onPressed: () => queue.retry(task.id),
                    child: const Text('重试'),
                  ),
                TextButton(
                  onPressed: () => queue.remove(task.id),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill marking the destination of a download (e.g. 系统相册).
class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
