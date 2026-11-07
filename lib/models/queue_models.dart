import '../l10n/generated/app_localizations.dart';

/// Wire name of a queue task kind (Rust `TaskKind`).
enum QueueTaskKind {
  downloadCache('download_cache'),
  downloadPublic('download_public'),
  scan('scan'),
  retagCloud('retag_cloud'),
  coverRefresh('cover_refresh'),
  matchRemote('match_remote'),
  mangaScrape('manga_scrape'),
  mangaCache('manga_cache'),
  mangaBuild('manga_build'),
  mangaPack('manga_pack'),
  upload('upload');

  const QueueTaskKind(this.wireName);

  final String wireName;

  static QueueTaskKind? tryParse(Object? value) {
    if (value is! String) return null;
    for (final kind in QueueTaskKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }

  bool get isDownload =>
      this == QueueTaskKind.downloadCache || this == QueueTaskKind.downloadPublic;

  String label(AppLocalizations l10n) {
    switch (this) {
      case QueueTaskKind.downloadCache:
      case QueueTaskKind.downloadPublic:
        return l10n.taskKindDownload;
      case QueueTaskKind.scan:
        return l10n.taskKindScan;
      case QueueTaskKind.retagCloud:
        return l10n.taskKindRetagCloud;
      case QueueTaskKind.coverRefresh:
        return l10n.taskKindCoverRefresh;
      case QueueTaskKind.matchRemote:
        return l10n.taskKindMatchRemote;
      case QueueTaskKind.mangaScrape:
        return l10n.taskKindMangaScrape;
      case QueueTaskKind.mangaCache:
        return l10n.taskKindMangaCache;
      case QueueTaskKind.mangaBuild:
        return l10n.taskKindMangaBuild;
      case QueueTaskKind.mangaPack:
        return l10n.taskKindMangaPack;
      case QueueTaskKind.upload:
        return l10n.taskKindUpload;
    }
  }
}

/// Wire name of a queue task status (Rust `TaskStatus`).
enum QueueTaskStatus {
  pending('pending'),
  active('active'),
  awaitingPlatform('awaiting_platform'),
  completed('completed'),
  partial('partial'),
  failed('failed'),
  cancelled('cancelled');

  const QueueTaskStatus(this.wireName);

  final String wireName;

  static QueueTaskStatus? tryParse(Object? value) {
    if (value is! String) return null;
    for (final status in QueueTaskStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }

  bool get isTerminal =>
      this != QueueTaskStatus.pending &&
      this != QueueTaskStatus.active &&
      this != QueueTaskStatus.awaitingPlatform;

  bool get isRunning =>
      this == QueueTaskStatus.pending || this == QueueTaskStatus.active;

  String label(AppLocalizations l10n) {
    switch (this) {
      case QueueTaskStatus.pending:
        return l10n.downloadPending;
      case QueueTaskStatus.active:
        return l10n.downloadActive;
      case QueueTaskStatus.awaitingPlatform:
        return l10n.taskAwaitingPlatform;
      case QueueTaskStatus.completed:
        return l10n.downloadCompleted;
      case QueueTaskStatus.partial:
        return l10n.taskPartialFailed;
      case QueueTaskStatus.failed:
        return l10n.downloadFailed;
      case QueueTaskStatus.cancelled:
        return l10n.downloadCancelled;
    }
  }
}

/// Wire name of a task progress mode (Rust `ProgressMode`).
enum QueueProgressMode {
  bytes('bytes'),
  units('units');

  const QueueProgressMode(this.wireName);

  final String wireName;

  static QueueProgressMode tryParse(Object? value) {
    if (value == 'units') return QueueProgressMode.units;
    return QueueProgressMode.bytes;
  }
}

/// Where a finished download goes (Rust `TaskTarget`).
enum QueueTarget {
  cache('cache'),
  public('public');

  const QueueTarget(this.wireName);

  final String wireName;

  static QueueTarget tryParse(Object? value) {
    return value == 'public' ? QueueTarget.public : QueueTarget.cache;
  }
}

/// Wire name of a folded row kind (Rust `BatchKind`).
enum QueueBatchKind {
  scan('scan'),
  download('download'),
  upload('upload'),
  manga('manga'),
  sync('sync');

  const QueueBatchKind(this.wireName);

  final String wireName;

  static QueueBatchKind tryParse(Object? value) {
    if (value is! String) return QueueBatchKind.scan;
    for (final kind in QueueBatchKind.values) {
      if (kind.wireName == value) return kind;
    }
    return QueueBatchKind.scan;
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case QueueBatchKind.scan:
        return l10n.taskKindScan;
      case QueueBatchKind.download:
        return l10n.taskKindDownload;
      case QueueBatchKind.upload:
        return l10n.taskKindUpload;
      case QueueBatchKind.manga:
        return l10n.taskKindMangaBuild;
      case QueueBatchKind.sync:
        return l10n.taskKindRetagCloud;
    }
  }
}

/// Who created a batch (Rust `BatchOrigin`).
enum QueueBatchOrigin {
  user('user'),
  autoBackfill('auto_backfill'),
  system('system');

  const QueueBatchOrigin(this.wireName);

  final String wireName;

  static QueueBatchOrigin tryParse(Object? value) {
    if (value is! String) return QueueBatchOrigin.user;
    for (final origin in QueueBatchOrigin.values) {
      if (origin.wireName == value) return origin;
    }
    return QueueBatchOrigin.user;
  }
}

DateTime? _msToDate(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int _int(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _intOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _double(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String _string(Object? value, [String fallback = '']) {
  if (value is String) return value;
  return value?.toString() ?? fallback;
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return value.toString();
}

/// Gallery-eligible extensions, mirroring the Rust download job's choice of
/// `save_to_gallery` vs `save_to_downloads`. Display only.
const Set<String> _galleryExtensions = {
  'mp4', 'm4v', 'mkv', 'webm', 'avi', 'mov', 'flv', 'ts', 'wmv', '3gp', //
  'mpg', 'mpeg',
  'jpg', 'jpeg', 'png', 'webp', 'gif',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// One queue task as Rust serializes it (`wdmm-queue` `QueueTask`).
class QueueTask {
  const QueueTask({
    required this.id,
    required this.kind,
    required this.status,
    required this.sourceName,
    required this.accountId,
    required this.remotePath,
    required this.fileName,
    required this.createdAt,
    required this.updatedAt,
    required this.progress,
    required this.progressMode,
    required this.bytesDone,
    required this.unitsDone,
    required this.attempts,
    required this.batchId,
    required this.target,
    required this.priority,
    required this.queuedWhileForeground,
    this.localPath,
    this.localUri,
    this.errorMessage,
    this.cacheGroupId,
    this.payloadPath,
    this.resultJson,
    this.bytesTotal,
    this.unitsTotal,
    this.attemptsCap,
    this.nextRetryAt,
    this.remoteSize,
    this.remoteModified,
  });

  factory QueueTask.fromJson(Map<String, dynamic> json) {
    return QueueTask(
      id: _string(json['id']),
      kind: QueueTaskKind.tryParse(json['kind']) ?? QueueTaskKind.downloadCache,
      status:
          QueueTaskStatus.tryParse(json['status']) ?? QueueTaskStatus.pending,
      sourceName: _string(json['source_name']),
      accountId: _string(json['account_id']),
      remotePath: _string(json['remote_path']),
      fileName: _string(json['file_name']),
      createdAt: _msToDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _msToDate(json['updated_at']) ?? DateTime.now(),
      progress: _double(json['progress']),
      progressMode: QueueProgressMode.tryParse(json['progress_mode']),
      bytesDone: _int(json['bytes_done']),
      unitsDone: _int(json['units_done']),
      attempts: _int(json['attempts']),
      batchId: _string(json['batch_id']),
      target: QueueTarget.tryParse(json['target']),
      priority: _int(json['priority']),
      queuedWhileForeground: json['queued_while_foreground'] == true,
      localPath: _stringOrNull(json['local_path']),
      localUri: _stringOrNull(json['local_uri']),
      errorMessage: _stringOrNull(json['error_message']),
      cacheGroupId: _stringOrNull(json['cache_group_id']),
      payloadPath: _stringOrNull(json['payload_path']),
      resultJson: _stringOrNull(json['result_json']),
      bytesTotal: _intOrNull(json['bytes_total']),
      unitsTotal: _intOrNull(json['units_total']),
      attemptsCap: _intOrNull(json['attempts_cap']),
      nextRetryAt: _msToDate(json['next_retry_at']),
      remoteSize: _intOrNull(json['remote_size']),
      remoteModified: _msToDate(json['remote_modified']),
    );
  }

  final String id;
  final QueueTaskKind kind;
  final QueueTaskStatus status;
  final String sourceName;
  final String accountId;
  final String remotePath;
  final String fileName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? localPath;
  final String? localUri;
  final String? errorMessage;
  final double progress;
  final QueueProgressMode progressMode;
  final int? bytesTotal;
  final int bytesDone;
  final int? unitsTotal;
  final int unitsDone;
  final int attempts;
  final int? attemptsCap;
  final DateTime? nextRetryAt;
  final String batchId;
  final String? cacheGroupId;
  final QueueTarget target;
  final int priority;
  final String? payloadPath;
  final String? resultJson;
  final int? remoteSize;
  final DateTime? remoteModified;
  final bool queuedWhileForeground;

  bool get isTerminal => status.isTerminal;

  bool get isPublic => target == QueueTarget.public;

  /// Whether this public download lands in the system gallery. Mirrors the
  /// Rust job's extension-based platform action.
  bool get isGallery => isPublic && _galleryExtensions.contains(_extensionOf(fileName));

  /// 0..1 progress for progress bars, derived from the reported unit.
  double get displayProgress {
    if (progressMode == QueueProgressMode.units) {
      final total = unitsTotal;
      if (total == null || total <= 0) return 0;
      return (unitsDone / total).clamp(0.0, 1.0);
    }
    final total = bytesTotal;
    if (total == null || total <= 0) return progress.clamp(0.0, 1.0);
    return (bytesDone / total).clamp(0.0, 1.0);
  }

  /// Apply a `task_progress` event (deltas only, never re-orders tasks).
  QueueTask withProgress({
    QueueTaskStatus? status,
    double? progress,
    QueueProgressMode? progressMode,
    int? bytesDone,
    int? bytesTotal,
    int? unitsDone,
    int? unitsTotal,
  }) {
    return QueueTask(
      id: id,
      kind: kind,
      status: status ?? this.status,
      sourceName: sourceName,
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      progress: progress ?? this.progress,
      progressMode: progressMode ?? this.progressMode,
      bytesDone: bytesDone ?? this.bytesDone,
      unitsDone: unitsDone ?? this.unitsDone,
      attempts: attempts,
      batchId: batchId,
      target: target,
      priority: priority,
      queuedWhileForeground: queuedWhileForeground,
      localPath: localPath,
      localUri: localUri,
      errorMessage: errorMessage,
      cacheGroupId: cacheGroupId,
      payloadPath: payloadPath,
      resultJson: resultJson,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      unitsTotal: unitsTotal ?? this.unitsTotal,
      attemptsCap: attemptsCap,
      nextRetryAt: nextRetryAt,
      remoteSize: remoteSize,
      remoteModified: remoteModified,
    );
  }

  /// Apply a `task_terminal` event: the terminal event carries the authoritative
  /// result fields, so absent values clear the previous ones.
  QueueTask withTerminal({
    required QueueTaskStatus status,
    String? errorMessage,
    String? localPath,
    String? localUri,
    String? resultJson,
    double? progress,
  }) {
    return QueueTask(
      id: id,
      kind: kind,
      status: status,
      sourceName: sourceName,
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      progress: progress ?? this.progress,
      progressMode: progressMode,
      bytesDone: bytesDone,
      unitsDone: unitsDone,
      attempts: attempts,
      batchId: batchId,
      target: target,
      priority: priority,
      queuedWhileForeground: queuedWhileForeground,
      localPath: localPath,
      localUri: localUri,
      errorMessage: errorMessage,
      cacheGroupId: cacheGroupId,
      payloadPath: payloadPath,
      resultJson: resultJson,
      bytesTotal: bytesTotal,
      unitsTotal: unitsTotal,
      attemptsCap: attemptsCap,
      nextRetryAt: nextRetryAt,
      remoteSize: remoteSize,
      remoteModified: remoteModified,
    );
  }
}

/// Per-status counters on a folded row (Rust `RowCounts`).
class QueueRowCounts {
  const QueueRowCounts({
    this.completed = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.pending = 0,
    this.active = 0,
  });

  factory QueueRowCounts.fromJson(Map<String, dynamic> json) {
    return QueueRowCounts(
      completed: _int(json['completed']),
      failed: _int(json['failed']),
      cancelled: _int(json['cancelled']),
      pending: _int(json['pending']),
      active: _int(json['active']),
    );
  }

  final int completed;
  final int failed;
  final int cancelled;
  final int pending;
  final int active;

  int get total => completed + failed + cancelled + pending + active;

  int get done => completed + failed + cancelled;
}

/// One batch folded by Rust for the tasks screen (`wdmm-queue` `QueueRow`).
class QueueRow {
  const QueueRow({
    required this.groupId,
    required this.batchId,
    required this.kind,
    required this.origin,
    required this.silent,
    required this.headTaskId,
    required this.status,
    required this.progress,
    required this.progressMode,
    required this.unitsDone,
    required this.counts,
    required this.taskIds,
    required this.earliestCreatedAt,
    this.label,
    this.unitsTotal,
  });

  factory QueueRow.fromJson(Map<String, dynamic> json) {
    return QueueRow(
      groupId: _string(json['group_id']),
      batchId: _string(json['batch_id']),
      kind: QueueBatchKind.tryParse(json['kind']),
      label: _stringOrNull(json['label']),
      origin: QueueBatchOrigin.tryParse(json['origin']),
      silent: json['silent'] == true,
      headTaskId: _string(json['head_task_id']),
      status: QueueTaskStatus.tryParse(json['status']) ?? QueueTaskStatus.pending,
      progress: _double(json['progress']),
      progressMode: QueueProgressMode.tryParse(json['progress_mode']),
      unitsDone: _int(json['units_done']),
      unitsTotal: _intOrNull(json['units_total']),
      counts: json['counts'] is Map
          ? QueueRowCounts.fromJson(
              Map<String, dynamic>.from(json['counts'] as Map),
            )
          : const QueueRowCounts(),
      taskIds: json['task_ids'] is List
          ? [for (final id in json['task_ids'] as List) _string(id)]
          : const <String>[],
      earliestCreatedAt:
          _msToDate(json['earliest_created_at']) ?? DateTime.now(),
    );
  }

  final String groupId;
  final String batchId;
  final QueueBatchKind kind;
  final String? label;
  final QueueBatchOrigin origin;
  final bool silent;
  final String headTaskId;
  final QueueTaskStatus status;
  final double progress;
  final QueueProgressMode progressMode;
  final int unitsDone;
  final int? unitsTotal;
  final QueueRowCounts counts;
  final List<String> taskIds;
  final DateTime earliestCreatedAt;

  int get taskCount => counts.total;
}

/// A queue batch as Rust serializes it (`wdmm-queue` `QueueBatch`).
class QueueBatch {
  const QueueBatch({
    required this.id,
    required this.kind,
    required this.origin,
    required this.silent,
    required this.createdAt,
    this.expectedTotal,
    this.closedAt,
    this.label,
  });

  factory QueueBatch.fromJson(Map<String, dynamic> json) {
    return QueueBatch(
      id: _string(json['id']),
      kind: QueueBatchKind.tryParse(json['kind']),
      origin: QueueBatchOrigin.tryParse(json['origin']),
      silent: json['silent'] == true,
      createdAt: _msToDate(json['created_at']) ?? DateTime.now(),
      expectedTotal: _intOrNull(json['expected_total']),
      closedAt: _msToDate(json['closed_at']),
      label: _stringOrNull(json['label']),
    );
  }

  final String id;
  final QueueBatchKind kind;
  final QueueBatchOrigin origin;
  final bool silent;
  final DateTime createdAt;
  final int? expectedTotal;
  final DateTime? closedAt;
  final String? label;

  bool get isOpen => closedAt == null;
}

/// Keep-alive phase reported by Rust (`idle`, `start`, `release`, ...).
class QueueKeepalive {
  const QueueKeepalive({required this.phase, this.lastError});

  factory QueueKeepalive.fromJson(Map<String, dynamic>? json) {
    return QueueKeepalive(
      phase: _string(json?['phase'], 'idle'),
      lastError: _stringOrNull(json?['last_error']),
    );
  }

  final String phase;
  final String? lastError;
}

/// Session summary attached to every command/query response.
class QueueSession {
  const QueueSession({
    required this.drained,
    required this.scrapeOnly,
    required this.background,
    required this.keepalive,
    required this.notifications,
  });

  factory QueueSession.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return QueueSession(
      drained: map['drained'] == true,
      scrapeOnly: map['scrape_only'] == true,
      background: map['background'] == true,
      keepalive: QueueKeepalive.fromJson(
        map['keepalive'] is Map
            ? Map<String, dynamic>.from(map['keepalive'] as Map)
            : null,
      ),
      notifications: map['notifications'] == true,
    );
  }

  const QueueSession.initial()
    : drained = true,
      scrapeOnly = false,
      background = false,
      keepalive = const QueueKeepalive(phase: 'idle'),
      notifications = false;

  final bool drained;
  final bool scrapeOnly;
  final bool background;
  final QueueKeepalive keepalive;
  final bool notifications;
}

/// Counters for the queue badge (`wdmm-queue` `QueueStats`).
class QueueStats {
  const QueueStats({
    this.pending = 0,
    this.active = 0,
    this.awaitingPlatform = 0,
    this.completed = 0,
    this.partial = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.total = 0,
  });

  factory QueueStats.fromJson(Map<String, dynamic> json) {
    return QueueStats(
      pending: _int(json['pending']),
      active: _int(json['active']),
      awaitingPlatform: _int(json['awaiting_platform']),
      completed: _int(json['completed']),
      partial: _int(json['partial']),
      failed: _int(json['failed']),
      cancelled: _int(json['cancelled']),
      total: _int(json['total']),
    );
  }

  final int pending;
  final int active;
  final int awaitingPlatform;
  final int completed;
  final int partial;
  final int failed;
  final int cancelled;
  final int total;

  bool get hasRunning => pending + active + awaitingPlatform > 0;
}
