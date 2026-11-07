import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/queue_models.dart';
import '../services/queue_service.dart';
import '../theme/app_theme.dart';
import '../widgets/meta_text.dart';
import '../utils/app_snack.dart';
import 'home_shell.dart';

/// Download-queue screen.
///
/// Rust owns the queue state machine: it folds tasks into `QueueRow`s, orders
/// them, decides retry/backoff and batch closing. This screen only renders the
/// rows it receives and issues thin commands (`cancel` / `retry` / `remove`).
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  Future<void> _confirmClearAll(
    BuildContext context,
    QueueService queue,
    List<QueueRow> rows,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final total = rows.fold<int>(0, (sum, row) => sum + row.counts.total);
    final running = rows.fold<int>(
      0,
      (sum, row) =>
          sum + row.counts.active + row.counts.pending,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearQueueConfirm),
        content: Text(
          l10n.clearQueueDetails(
            total,
            running > 0 ? l10n.runningDownloads(running) : '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await queue.clearAll();
    if (!context.mounted) return;
    AppSnack.show(context, l10n.queueCleared);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final queue = context.watch<QueueService>();
    final rows = queue.rows;
    final anyRetryable = rows.any(
      (row) =>
          row.status == QueueTaskStatus.failed ||
          row.status == QueueTaskStatus.partial ||
          row.status == QueueTaskStatus.cancelled,
    );
    final anyCompleted = rows.any(
      (row) => row.status == QueueTaskStatus.completed,
    );
    final anyActive = rows.any(
      (row) =>
          row.counts.active > 0 ||
          row.counts.pending > 0,
    );

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(l10n.taskQueue),
        actions: [
          IconButton(
            tooltip: l10n.downloadAll,
            onPressed: anyRetryable ? () => queue.retryAll() : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: l10n.clearCompleted,
            onPressed: anyCompleted ? () => queue.clearCompleted() : null,
            icon: const Icon(Icons.done_all),
          ),
          PopupMenuButton<String>(
            tooltip: l10n.more,
            onSelected: (value) {
              switch (value) {
                case 'cancel_all':
                  queue.cancelAll();
                case 'clear_all':
                  _confirmClearAll(context, queue, rows);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'cancel_all',
                enabled: anyActive,
                child: Text(l10n.cancelAll),
              ),
              PopupMenuItem(
                value: 'clear_all',
                enabled: rows.isNotEmpty,
                child: Text(
                  l10n.clearAllQueue,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: rows.isEmpty
          ? Center(
              child: Text(
                l10n.noTaskQueueItems,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _QueueRowTile(row: rows[index], queue: queue),
            ),
    );
  }
}

String _rowTitle(QueueRow row, AppLocalizations l10n) {
  final label = row.label;
  if (label != null && label.isNotEmpty) return label;
  return row.kind.label(l10n);
}

class _QueueRowTile extends StatelessWidget {
  const _QueueRowTile({required this.row, required this.queue});

  final QueueRow row;
  final QueueService queue;

  QueueTask? get _head => queue.taskById(row.headTaskId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final counts = row.counts;
    final done = counts.completed + counts.failed + counts.cancelled;
    final total = counts.total;
    final active = counts.active > 0 || counts.pending > 0;
    final head = _head;
    final error = row.status == QueueTaskStatus.failed
        ? head?.errorMessage
        : null;

    return InkWell(
      onTap: row.taskIds.length > 1
          ? () => _showMembers(context, row)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _kindIcon(row.kind),
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _rowTitle(row, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  l10n.taskGroupCount(total),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _RowActions(row: row, queue: queue),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                MetaText(row.status.label(l10n)),
                const SizedBox(width: 12),
                MetaText('$done / $total'),
                if (row.status == QueueTaskStatus.completed) ...[
                  const SizedBox(width: 12),
                  Text(
                    l10n.downloadCompleted,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            if (active) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: row.progress <= 0 ? null : row.progress.clamp(0.0, 1.0),
              ),
              const SizedBox(height: 4),
              Text(
                row.progressMode == QueueProgressMode.units
                    ? l10n.taskProgressUnits(
                        row.unitsDone,
                        row.unitsTotal ?? total,
                      )
                    : '${(row.progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _showErrorDetail(context, error),
                child: Text(
                  QueueService.describeError(error, l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMembers(BuildContext context, QueueRow row) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => Consumer<QueueService>(
          builder: (context, liveQueue, _) {
            QueueRow? current;
            for (final candidate in liveQueue.rows) {
              if (candidate.groupId == row.groupId) {
                current = candidate;
                break;
              }
            }
            final ids = current?.taskIds ?? const <String>[];
            final members = <QueueTask>[];
            for (final id in ids) {
              final task = liveQueue.taskById(id);
              if (task != null) members.add(task);
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_rowTitle(row, l10n)} · '
                          '${l10n.taskGroupCount(members.length)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.taskGroupDeleteAll,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        onPressed: members.isEmpty
                            ? null
                            : () async {
                                for (final id in ids) {
                                  await liveQueue.remove(id);
                                }
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final task = members[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          task.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          task.status == QueueTaskStatus.active ||
                                  task.status == QueueTaskStatus.awaitingPlatform
                              ? '${task.status.label(l10n)} · '
                                '${(task.displayProgress * 100).toStringAsFixed(0)}%'
                              : task.status.label(l10n),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showErrorDetail(BuildContext context, String raw) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.taskErrDetailTitle),
        content: SingleChildScrollView(
          child: SelectableText(QueueService.describeErrorDetail(raw)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  static IconData _kindIcon(QueueBatchKind kind) {
    switch (kind) {
      case QueueBatchKind.scan:
        return Icons.travel_explore;
      case QueueBatchKind.download:
        return Icons.download_outlined;
      case QueueBatchKind.upload:
        return Icons.upload_outlined;
      case QueueBatchKind.manga:
        return Icons.menu_book_outlined;
      case QueueBatchKind.sync:
        return Icons.sync_outlined;
    }
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.row, required this.queue});

  final QueueRow row;
  final QueueService queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = row.status;
    final cancellable =
        row.counts.active > 0 ||
        row.counts.pending > 0;
    final retryable =
        status == QueueTaskStatus.failed ||
        status == QueueTaskStatus.partial ||
        status == QueueTaskStatus.cancelled;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: l10n.more,
      onSelected: (value) async {
        for (final id in row.taskIds) {
          switch (value) {
            case 'cancel':
              await queue.cancel(id);
            case 'retry':
              await queue.retry(id);
            case 'delete':
              await queue.remove(id);
          }
        }
      },
      itemBuilder: (context) => [
        if (cancellable)
          PopupMenuItem(value: 'cancel', child: Text(l10n.cancel)),
        if (retryable)
          PopupMenuItem(value: 'retry', child: Text(l10n.retry)),
        PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
      ],
    );
  }
}

