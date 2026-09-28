import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/cue_sheet.dart';
import '../services/cloud_driver.dart';
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
    final l10n = AppLocalizations.of(context)!;
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
        title: Text(l10n.clearQueueConfirm),
        content: Text(
          l10n.clearQueueDetails(
            tasks.length,
            running > 0 ? l10n.runningDownloads(running) : '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await queue.clearAll();
    if (!context.mounted) return;
    AppSnack.show(context, l10n.queueCleared);
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<DownloadQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final tasks = queue.tasks.reversed.toList();
    final rows = _rowsFor(tasks, queue);

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(l10n.downloadQueue),
        actions: [
          IconButton(
            tooltip: l10n.downloadAll,
            onPressed: tasks.any((t) => t.status != DownloadStatus.completed)
                ? () => queue.downloadAll()
                : null,
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
          IconButton(
            tooltip: l10n.wakeWaiting,
            onPressed: tasks.any((t) => t.status == DownloadStatus.pending)
                ? () => queue.downloadWaiting()
                : null,
            icon: const Icon(Icons.playlist_play),
          ),
          IconButton(
            tooltip: l10n.cancelAll,
            onPressed:
                tasks.any(
                  (t) =>
                      t.status == DownloadStatus.active ||
                      t.status == DownloadStatus.pending,
                )
                ? () => queue.cancelAll()
                : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          TextButton(
            onPressed: tasks.any((t) => t.status == DownloadStatus.completed)
                ? () => queue.clearCompleted()
                : null,
            child: Text(l10n.clearCompleted),
          ),
          PopupMenuButton<String>(
            tooltip: l10n.more,
            onSelected: (v) {
              if (v == 'clear_all') _confirmClearAll(context, queue, tasks);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear_all',
                enabled: tasks.isNotEmpty,
                child: Text(
                  l10n.clearAllQueue,
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: rows.isEmpty
          ? Center(
              child: Text(
                l10n.noDownloadTasks,
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
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = failed
        ? (l10n.downloadFailed, AppColors.error)
        : active
        ? (l10n.downloadActive, AppColors.accent)
        : pending
        ? (l10n.downloadPending, AppColors.mutedText)
        : allDone
        ? (l10n.downloadCompleted, const Color(0xFF66BB6A))
        : (l10n.inProgress, AppColors.mutedText);
    final progress = members.isEmpty
        ? 0.0
        : members.map((t) => t.progress).reduce((a, b) => a + b) /
              members.length;
    final songLabel = songs != null && songs > 0
        ? l10n.songCount(songs)
        : l10n.cueAlbum;

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
                    child: Text(l10n.cancel),
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
                    child: Text(l10n.retry),
                  ),
                TextButton(
                  onPressed: () {
                    for (final t in members) {
                      queue.remove(t.id);
                    }
                  },
                  child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
    final retryWaiting =
        task.status == DownloadStatus.pending && task.nextRetryAt != null;
    final label = retryWaiting
        ? '${l10n.downloadActive} (${task.attempts}/${DownloadQueueService.maxAutoRetries})'
        : task.status.label(l10n);
    final color = switch (task.status) {
      DownloadStatus.pending =>
        retryWaiting ? AppColors.accent : AppColors.mutedText,
      DownloadStatus.active => AppColors.accent,
      DownloadStatus.completed => const Color(0xFF66BB6A),
      DownloadStatus.failed => AppColors.error,
      DownloadStatus.cancelled => AppColors.mutedText,
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
                if (task.downloadMode == CloudDownloadMode.cryptSequential)
                  _DestinationChip(
                    icon: Icons.stream_outlined,
                    label: l10n.dlCryptSequential,
                    color: AppColors.accent,
                  ),
                if (task.isGallery)
                  _DestinationChip(
                    icon: Icons.photo_library_outlined,
                    label: savedToGallery
                        ? l10n.dlSavedToGallery
                        : l10n.dlTargetGallery,
                    color: AppColors.accent,
                  ),
                if (task.target == DownloadTarget.downloads)
                  _DestinationChip(
                    icon: Icons.folder_outlined,
                    label: savedToDownloads
                        ? l10n.dlSavedToDownloads
                        : l10n.dlTargetDownloads,
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
            // 落盘位置的原始 URI（content://…）对用户没有意义，已按要求不再
            // 显示（真机反馈：既读不懂也反映不了实际位置）；目标信息由上方
            // 的「已存入系统相册」标签承担。
            if (task.errorMessage != null &&
                (task.status == DownloadStatus.failed || retryWaiting)) ...[
              const SizedBox(height: 4),
              Text(
                DownloadQueueService.describeError(task.errorMessage!, l10n),
                style: TextStyle(
                  color: task.status == DownloadStatus.failed
                      ? AppColors.error
                      : AppColors.mutedText,
                ),
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
                    child: Text(l10n.cancel),
                  ),
                if (task.status == DownloadStatus.failed ||
                    task.status == DownloadStatus.cancelled)
                  TextButton(
                    onPressed: () => queue.retry(task.id),
                    child: Text(l10n.retry),
                  ),
                TextButton(
                  onPressed: () => queue.remove(task.id),
                  child: Text(l10n.delete),
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
