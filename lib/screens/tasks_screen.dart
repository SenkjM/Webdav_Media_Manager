import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/queue_task.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/cue_sheet.dart';
import '../services/wdmm_vfs.dart';
import '../services/rust_queue_bridge.dart';
import '../services/task_queue_service.dart';
import '../theme/app_theme.dart';
import '../widgets/meta_text.dart';
import '../utils/app_snack.dart';
import 'home_shell.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  /// Collapse CUE groups, then merge time-contiguous same-kind rows
  /// (split by [DownloadTarget] when kind is download). Display-only.
  static List<_QueueRow> _rowsFor(
    List<QueueTask> tasksNewestFirst,
    TaskQueueService queue,
  ) {
    final seenGroups = <String>{};
    final cueOrSingle = <_QueueRow>[];
    for (final t in tasksNewestFirst) {
      final gid = t.cacheGroupId;
      if (gid != null && gid.startsWith('cue')) {
        if (seenGroups.contains(gid)) continue;
        seenGroups.add(gid);
        var members = tasksNewestFirst
            .where(
              (x) =>
                  x.cacheGroupId == gid &&
                  x.status != TaskStatus.cancelled &&
                  x.status != TaskStatus.failed,
            )
            .toList();
        if (members.isEmpty) {
          members = tasksNewestFirst
              .where((x) => x.cacheGroupId == gid)
              .toList();
        }
        final byPath = <String, QueueTask>{};
        for (final m in members) {
          final prev = byPath[m.remotePath];
          if (prev == null || m.createdAt.isAfter(prev.createdAt)) {
            byPath[m.remotePath] = m;
          }
        }
        cueOrSingle.add(_QueueRow.cueGroup(gid, byPath.values.toList(), queue));
      } else {
        cueOrSingle.add(_QueueRow.single(t));
      }
    }
    return _mergeContiguousKind(cueOrSingle);
  }

  /// Merge adjacent non-CUE rows that share kind (+ download target).
  static List<_QueueRow> _mergeContiguousKind(List<_QueueRow> input) {
    if (input.isEmpty) return input;
    final out = <_QueueRow>[];
    var bucket = <QueueTask>[];
    TaskKind? kind;
    DownloadTarget? target;

    void flush() {
      if (bucket.isEmpty) return;
      if (bucket.length == 1) {
        out.add(_QueueRow.single(bucket.first));
      } else {
        out.add(_QueueRow.kindGroup(bucket));
      }
      bucket = [];
      kind = null;
      target = null;
    }

    for (final row in input) {
      if (row.isCueGroup) {
        flush();
        out.add(row);
        continue;
      }
      final t = row.members.first;
      final sameKind = kind == t.kind;
      final sameTarget = t.kind != TaskKind.download || target == t.target;
      if (bucket.isEmpty) {
        bucket.add(t);
        kind = t.kind;
        target = t.target;
        continue;
      }
      if (sameKind && sameTarget) {
        bucket.add(t);
      } else {
        flush();
        bucket.add(t);
        kind = t.kind;
        target = t.target;
      }
    }
    flush();
    return out;
  }

  /// Clear every queue entry. Always asks first: unlike clearing completed rows,
  /// this also drops pending/failed entries and cancels running transfers.
  Future<void> _confirmClearAll(
    BuildContext context,
    TaskQueueService queue,
    List<QueueTask> tasks,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final running = tasks
        .where(
          (t) =>
              t.status == TaskStatus.active || t.status == TaskStatus.pending,
        )
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
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
    final queue = context.watch<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final tasks = queue.tasks.reversed.toList();
    final rows = _rowsFor(tasks, queue);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(l10n.taskQueue),
        actions: [
          IconButton(
            tooltip: l10n.downloadAll,
            onPressed: tasks.any(
              (t) =>
                  t.status == TaskStatus.failed ||
                  t.status == TaskStatus.cancelled,
            )
                ? () => queue.downloadAll()
                : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: l10n.clearCompleted,
            onPressed: tasks.any((t) => t.status == TaskStatus.completed)
                ? () => queue.clearCompleted()
                : null,
            icon: const Icon(Icons.playlist_remove_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: l10n.more,
            onSelected: (v) {
              switch (v) {
                case 'cancel_all':
                  queue.cancelAll();
                case 'clear_all':
                  _confirmClearAll(context, queue, tasks);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'cancel_all',
                enabled: tasks.any(
                  (t) =>
                      t.status == TaskStatus.active ||
                      t.status == TaskStatus.pending,
                ),
                child: Text(l10n.cancelAll),
              ),
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
      body: Column(
        children: [
          // When the Rust queue is enabled, show a live Rust-side status panel
          // above the Dart task list so developers can verify both queues side
          // by side without opening Settings.  The panel auto-polls every 3 s.
          if (kRustQueueEnabled) const _RustQueuePanel(),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      l10n.noTaskQueueItems,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                      if (row.isKindGroup) {
                        return _KindGroupTile(members: row.members);
                      }
                      return _TaskTile(task: row.members.first);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow {
  _QueueRow._(
    this.members, {
    required this.isCueGroup,
    this.isKindGroup = false,
    this.groupId,
    this.songCount,
  });
  factory _QueueRow.single(QueueTask t) => _QueueRow._([t], isCueGroup: false);
  factory _QueueRow.kindGroup(List<QueueTask> members) =>
      _QueueRow._(members, isCueGroup: false, isKindGroup: true);
  factory _QueueRow.cueGroup(
    String id,
    List<QueueTask> members,
    TaskQueueService queue,
  ) => _QueueRow._(
    members,
    isCueGroup: true,
    groupId: id,
    songCount: queue.cueSongCountForGroup(id),
  );

  final List<QueueTask> members;
  final bool isCueGroup;
  final bool isKindGroup;
  final String? groupId;
  final int? songCount;
}

class _CueGroupTile extends StatelessWidget {
  const _CueGroupTile({
    required this.members,
    required this.groupId,
    this.songCount,
  });

  final List<QueueTask> members;
  final String groupId;
  final int? songCount;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<TaskQueueService>();
    final cue = members.cast<QueueTask?>().firstWhere(
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
    final failed = members.any((t) => t.status == TaskStatus.failed);
    final partial = members.any((t) => t.status == TaskStatus.partial);
    final active = members.any((t) => t.status == TaskStatus.active);
    final pending = members.any((t) => t.status == TaskStatus.pending);
    final allDone =
        members.isNotEmpty &&
        members.every((t) => t.status == TaskStatus.completed);
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = failed
        ? (l10n.downloadFailed, AppColors.error)
        : partial
        ? (l10n.taskPartialFailed, Colors.orange)
        : active
        ? (l10n.downloadActive, AppColors.accent)
        : pending
        ? (l10n.downloadPending, Theme.of(context).colorScheme.outline)
        : allDone
        ? (l10n.downloadCompleted, const Color(0xFF66BB6A))
        : (l10n.inProgress, Theme.of(context).colorScheme.outline);
    final progress = members.isEmpty
        ? 0.0
        : members.map((t) => t.progress).reduce((a, b) => a + b) /
              members.length;
    final songLabel = songs != null && songs > 0
        ? l10n.songCount(songs)
        : l10n.cueAlbum;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainer,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
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
            MetaText(songLabel),
            if (active || pending) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: active ? progress.clamp(0.0, 1.0) : null,
                  minHeight: 4,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                  color: AppColors.accent,
                ),
              ),
              if (active) ...[
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
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
                        if (t.status == TaskStatus.pending ||
                            t.status == TaskStatus.active) {
                          queue.cancel(t.id);
                        }
                      }
                    },
                    child: Text(l10n.cancel),
                  ),
                if (failed || partial)
                  TextButton(
                    onPressed: () {
                      for (final t in members) {
                        if (t.status == TaskStatus.failed ||
                            t.status == TaskStatus.partial ||
                            t.status == TaskStatus.cancelled) {
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

  final QueueTask task;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final retryWaiting =
        task.status == TaskStatus.pending && task.nextRetryAt != null;
    final label = retryWaiting
        ? '${l10n.downloadActive} (${task.attempts}/${TaskQueueService.maxAutoRetries})'
        : task.status.label(l10n);
    final color = switch (task.status) {
      TaskStatus.pending =>
        retryWaiting ? AppColors.accent : Theme.of(context).colorScheme.outline,
      TaskStatus.active => AppColors.accent,
      TaskStatus.completed => const Color(0xFF66BB6A),
      TaskStatus.failed => AppColors.error,
      TaskStatus.partial => Colors.orange,
      TaskStatus.cancelled => Theme.of(context).colorScheme.outline,
    };
    final savedToGallery =
        task.isGallery && task.status == TaskStatus.completed;
    final savedToDownloads =
        task.target == DownloadTarget.downloads &&
        task.status == TaskStatus.completed;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainer,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.kind != TaskKind.download)
                  _DestinationChip(
                    icon: Icons.task_alt_outlined,
                    label: task.kind.label(l10n),
                    color: AppColors.accent,
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
                        ? l10n.dlSavedGeneric
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
            if (task.status == TaskStatus.active) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.displayProgress,
                  minHeight: 4,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                task.progressMode == TaskProgressMode.units &&
                        task.unitsTotal != null
                    ? l10n.taskProgressUnits(task.unitsDone, task.unitsTotal!)
                    : '${(task.displayProgress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 12,
                ),
              ),
            ],
            // 落盘位置的原始 URI（content://…）对用户没有意义，已按要求不再
            // 显示（真机反馈：既读不懂也反映不了实际位置）；目标信息由上方
            // 的「已存入系统相册」标签承担。
            if (task.errorMessage != null &&
                (task.status == TaskStatus.failed || retryWaiting)) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onLongPress: () =>
                    _showTaskErrorDetail(context, task.errorMessage!),
                child: Text(
                  TaskQueueService.describeError(task.errorMessage!, l10n),
                  style: TextStyle(
                    color: task.status == TaskStatus.failed
                        ? AppColors.error
                        : Theme.of(context).colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.errorMessage != null &&
                    (task.status == TaskStatus.failed || retryWaiting))
                  TextButton(
                    onPressed: () =>
                        _showTaskErrorDetail(context, task.errorMessage!),
                    child: Text(l10n.taskErrViewDetail),
                  ),
                if (task.status == TaskStatus.pending ||
                    task.status == TaskStatus.active)
                  TextButton(
                    onPressed: () => queue.cancel(task.id),
                    child: Text(l10n.cancel),
                  ),
                if (task.status == TaskStatus.failed ||
                    task.status == TaskStatus.partial ||
                    task.status == TaskStatus.cancelled)
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

Future<void> _showTaskErrorDetail(BuildContext context, String raw) async {
  final l10n = AppLocalizations.of(context)!;
  final short = TaskQueueService.describeError(raw, l10n);
  final detail = TaskQueueService.describeErrorDetail(raw);
  final body = detail == short ? detail : '$short\n\n$detail';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      title: Text(l10n.taskErrDetailTitle),
      content: SingleChildScrollView(child: SelectableText(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

class _KindGroupTile extends StatelessWidget {
  const _KindGroupTile({required this.members});

  final List<QueueTask> members;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final head = members.first;
    final failed = members.any((t) => t.status == TaskStatus.failed);
    final partial = members.any((t) => t.status == TaskStatus.partial);
    final active = members.any((t) => t.status == TaskStatus.active);
    final pending = members.any((t) => t.status == TaskStatus.pending);
    final allDone =
        members.isNotEmpty &&
        members.every((t) => t.status == TaskStatus.completed);
    final (label, color) = failed
        ? (l10n.downloadFailed, AppColors.error)
        : partial
        ? (l10n.taskPartialFailed, Colors.orange)
        : active
        ? (l10n.downloadActive, AppColors.accent)
        : pending
        ? (l10n.downloadPending, Theme.of(context).colorScheme.outline)
        : allDone
        ? (l10n.downloadCompleted, const Color(0xFF66BB6A))
        : (l10n.inProgress, Theme.of(context).colorScheme.outline);
    final progress = members.isEmpty
        ? 0.0
        : members.map((t) => t.displayProgress).reduce((a, b) => a + b) /
              members.length;
    final title = head.kind == TaskKind.download
        ? (head.target.label(l10n))
        : head.kind.label(l10n);

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainer,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: () =>
            _showKindGroupMembers(context, members.map((t) => t.id).toSet()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    head.kind == TaskKind.scan
                        ? Icons.travel_explore_outlined
                        : Icons.playlist_add_check,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title · ${l10n.taskGroupCount(members.length)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
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
              if (active || pending) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: active ? progress.clamp(0.0, 1.0) : null,
                    minHeight: 4,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHigh,
                    color: AppColors.accent,
                  ),
                ),
                if (active) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
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
                        for (final task in members) {
                          if (task.status == TaskStatus.pending ||
                              task.status == TaskStatus.active) {
                            queue.cancel(task.id);
                          }
                        }
                      },
                      child: Text(l10n.cancel),
                    ),
                  if (failed || partial)
                    TextButton(
                      onPressed: () {
                        for (final task in members) {
                          if (task.status == TaskStatus.failed ||
                              task.status == TaskStatus.partial ||
                              task.status == TaskStatus.cancelled) {
                            queue.retry(task.id);
                          }
                        }
                      },
                      child: Text(l10n.retry),
                    ),
                  TextButton(
                    onPressed: () async {
                      for (final task in members) {
                        await queue.remove(task.id);
                      }
                    },
                    child: Text(l10n.taskGroupDeleteAll),
                  ),
                  TextButton(
                    onPressed: () => _showKindGroupMembers(
                      context,
                      members.map((t) => t.id).toSet(),
                    ),
                    child: Text(l10n.taskGroupMembers),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showKindGroupMembers(
  BuildContext context,
  Set<String> memberIds,
) async {
  final l10n = AppLocalizations.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, controller) {
          return Consumer<TaskQueueService>(
            builder: (context, queue, _) {
              final live = [
                for (final t in queue.tasks)
                  if (memberIds.contains(t.id)) t,
              ];
              live.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              if (live.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                });
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.taskGroupMembers,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: live.isEmpty
                              ? null
                              : () async {
                                  for (final t in List<QueueTask>.from(live)) {
                                    await queue.remove(t.id);
                                  }
                                },
                          child: Text(l10n.taskGroupDeleteAll),
                        ),
                        Text(l10n.taskGroupCount(live.length)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: live.isEmpty
                        ? Center(child: Text(l10n.noTaskQueueItems))
                        : ListView.builder(
                            controller: controller,
                            itemCount: live.length,
                            itemBuilder: (context, i) =>
                                _TaskTile(task: live[i]),
                          ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
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

// ── Rust queue live panel ─────────────────────────────────────────────────────
//
// Shown at the top of TasksScreen when kRustQueueEnabled=true.  Polls the Rust
// SerialPump every 3 seconds and displays a compact summary of its tasks.
// This replaces the debug-only poll in Settings as the live UI path.
//
// Serial invariant: SerialPump enforces concurrency=1 — do not add a
// concurrency knob on either side.

class _RustQueuePanel extends StatefulWidget {
  const _RustQueuePanel();

  @override
  State<_RustQueuePanel> createState() => _RustQueuePanelState();
}

class _RustQueuePanelState extends State<_RustQueuePanel> {
  List<Map<String, dynamic>> _tasks = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    final raw = RustQueueBridge.pollStatus();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        setState(() {
          _tasks = decoded.whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (_) {
      setState(() => _tasks = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_tasks.isEmpty) {
      return Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.memory, size: 14, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              'Rust queue: idle',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      );
    }
    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                'Rust queue — ${_tasks.length} task(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _poll,
                child: Icon(Icons.refresh, size: 14,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final t in _tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _RustTaskRow(task: t),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RustTaskRow extends StatelessWidget {
  const _RustTaskRow({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullId = task['id'] as String? ?? '';
    final id = fullId.substring(0, fullId.length < 8 ? fullId.length : 8);
    final status = task['status'] as String? ?? '?';
    final progress = (task['progress'] as num?)?.toDouble() ?? 0.0;
    final kind = task['kind'] as String? ?? '';
    final remotePath = task['remote_path'] as String? ?? '';
    final name = remotePath.isNotEmpty
        ? (remotePath.split('/').where((s) => s.isNotEmpty).lastOrNull ??
              remotePath)
        : kind;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.2),
            color: AppColors.accent,
            minHeight: 3,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '[$id…] $status',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
