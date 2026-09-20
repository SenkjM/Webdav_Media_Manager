import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../services/download_queue_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  /// Collapse CUE cache-group members into one queue row.
  static List<_QueueRow> _rowsFor(List<DownloadTask> tasksNewestFirst) {
    final seenGroups = <String>{};
    final rows = <_QueueRow>[];
    for (final t in tasksNewestFirst) {
      final gid = t.cacheGroupId;
      if (gid != null && gid.startsWith('cue')) {
        if (seenGroups.contains(gid)) continue;
        seenGroups.add(gid);
        final members = tasksNewestFirst
            .where((x) => x.cacheGroupId == gid)
            .toList();
        rows.add(_QueueRow.cueGroup(gid, members));
      } else {
        rows.add(_QueueRow.single(t));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<DownloadQueueService>();
    final tasks = queue.tasks.reversed.toList();
    final rows = _rowsFor(tasks);

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
                  return _CueGroupTile(members: row.members);
                }
                return _TaskTile(task: row.members.first);
              },
            ),
    );
  }
}

class _QueueRow {
  _QueueRow._(this.members, {required this.isCueGroup});
  factory _QueueRow.single(DownloadTask t) =>
      _QueueRow._([t], isCueGroup: false);
  factory _QueueRow.cueGroup(String id, List<DownloadTask> members) =>
      _QueueRow._(members, isCueGroup: true);

  final List<DownloadTask> members;
  final bool isCueGroup;
}

class _CueGroupTile extends StatelessWidget {
  const _CueGroupTile({required this.members});

  final List<DownloadTask> members;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<DownloadQueueService>();
    final cue = members.cast<DownloadTask?>().firstWhere(
          (t) => t!.remotePath.toLowerCase().endsWith('.cue'),
          orElse: () => null,
        );
    final title = cue?.fileName ?? members.first.fileName;
    final done =
        members.where((t) => t.status == DownloadStatus.completed).length;
    final failed = members.any((t) => t.status == DownloadStatus.failed);
    final active = members.any((t) => t.status == DownloadStatus.active);
    final pending = members.any((t) => t.status == DownloadStatus.pending);
    final (label, color) = failed
        ? ('失败', AppColors.error)
        : active
            ? ('下载中 $done/${members.length}', AppColors.accent)
            : pending
                ? ('等待中', AppColors.mutedText)
                : done == members.length
                    ? ('已完成', const Color(0xFF66BB6A))
                    : ('进行中 $done/${members.length}', AppColors.mutedText);
    final progress = members.isEmpty
        ? 0.0
        : members.map((t) => t.progress).reduce((a, b) => a + b) /
            members.length;

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
                    'CUE · $title',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Text(label, style: TextStyle(color: color, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${members.length} 个文件（.cue + 音频）合并为一条',
              style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
            ),
            if (active) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.elevatedHigh,
                  color: AppColors.accent,
                ),
              ),
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
                Expanded(
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Text(label, style: TextStyle(color: color, fontSize: 12)),
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
                style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
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
