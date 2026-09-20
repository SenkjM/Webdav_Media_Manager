import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../services/download_queue_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<DownloadQueueService>();
    final tasks = queue.tasks.reversed.toList();

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
      body: tasks.isEmpty
          ? const Center(
              child: Text(
                '暂无下载任务',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: tasks.length,
              itemBuilder: (context, i) {
                final t = tasks[i];
                return _TaskTile(task: t);
              },
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
                  child: Text(label, style: TextStyle(color: color, fontSize: 12)),
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
