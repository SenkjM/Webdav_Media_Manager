import '../l10n/generated/app_localizations.dart';
import '../services/wdmm_vfs.dart';

String? _asString(Object? value) => value?.toString();

DateTime? _asDate(Object? value) =>
    value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');

/// What the queue entry does. Download is the only executor wired today;
/// scan / retag kinds are reserved for later steps.
enum TaskKind {
  download,
  scan,
  retagCloud,
  retagLocal,

  /// Optional full-library remote existence probe (writes remote_missing).
  matchRemote,

  /// CBZ / container metadata + cover scrape (separate from music [scan]).
  mangaScrape,

  /// Download one whole manga archive into the manga cache.
  mangaCache,

  /// Stream one local file up to its account. The only write-side kind: it
  /// covers a SAF import copy and a packed archive alike. Cloud-drive accounts
  /// have no upload primitive and fail fast.
  upload,

  /// Build loose-image books from a folder (merged, or one per directory).
  mangaBuild,

  /// Pack one loose-image manga into a CBZ on disk and hand it to an [upload]
  /// task. Two rows by design: the user sees packing and uploading separately.
  mangaPack,
}

extension TaskKindX on TaskKind {
  String get storageKey => switch (this) {
    TaskKind.download => 'download',
    TaskKind.scan => 'scan',
    TaskKind.retagCloud => 'retag_cloud',
    TaskKind.retagLocal => 'retag_local',
    TaskKind.matchRemote => 'match_remote',
    TaskKind.mangaScrape => 'manga_scrape',
    TaskKind.mangaCache => 'manga_cache',
    TaskKind.upload => 'upload',
    TaskKind.mangaBuild => 'manga_build',
    TaskKind.mangaPack => 'manga_pack',
  };

  String label(AppLocalizations l10n) => switch (this) {
    TaskKind.download => l10n.taskKindDownload,
    TaskKind.scan => l10n.taskKindScan,
    TaskKind.retagCloud => l10n.taskKindRetagCloud,
    TaskKind.retagLocal => l10n.taskKindRetagLocal,
    TaskKind.matchRemote => l10n.taskKindMatchRemote,
    TaskKind.mangaScrape => l10n.taskKindMangaScrape,
    TaskKind.mangaCache => l10n.taskKindMangaCache,
    TaskKind.upload => l10n.taskKindUpload,
    TaskKind.mangaBuild => l10n.taskKindMangaBuild,
    TaskKind.mangaPack => l10n.taskKindMangaPack,
  };

  static TaskKind fromStorageKey(String? key) => switch (key) {
    'scan' => TaskKind.scan,
    'retag_cloud' => TaskKind.retagCloud,
    'retag_local' => TaskKind.retagLocal,
    'match_remote' => TaskKind.matchRemote,
    'manga_scrape' => TaskKind.mangaScrape,
    'manga_cache' => TaskKind.mangaCache,
    'upload' => TaskKind.upload,
    'manga_build' => TaskKind.mangaBuild,
    'manga_pack' => TaskKind.mangaPack,
    _ => TaskKind.download,
  };
}

/// Queue entry lifecycle.
/// [partial]: batch finished, some items failed after internal retries.
enum TaskStatus { pending, active, completed, failed, cancelled, partial }

extension TaskStatusX on TaskStatus {
  String label(AppLocalizations l10n) => switch (this) {
    TaskStatus.pending => l10n.downloadPending,
    TaskStatus.active => l10n.downloadActive,
    TaskStatus.completed => l10n.downloadCompleted,
    TaskStatus.failed => l10n.downloadFailed,
    TaskStatus.cancelled => l10n.downloadCancelled,
    TaskStatus.partial => l10n.taskPartialFailed,
  };
}

/// Where a **download** kind writes its file.
enum DownloadTarget {
  /// App-internal audio cache (`music_cache/`).
  cache,

  /// System gallery / media library via MediaStore (Android `Movies/…`).
  gallery,

  /// Public Downloads folder via MediaStore (`Download/…`).
  downloads,
}

extension DownloadTargetX on DownloadTarget {
  String get storageKey => switch (this) {
    DownloadTarget.cache => 'cache',
    DownloadTarget.gallery => 'gallery',
    DownloadTarget.downloads => 'downloads',
  };

  String label(AppLocalizations l10n) => switch (this) {
    DownloadTarget.cache => l10n.targetCache,
    DownloadTarget.gallery => l10n.targetGallery,
    DownloadTarget.downloads => l10n.targetDownloads,
  };

  static DownloadTarget fromStorageKey(String? key) => switch (key) {
    'gallery' => DownloadTarget.gallery,
    'downloads' => DownloadTarget.downloads,
    _ => DownloadTarget.cache,
  };
}

/// How [QueueTask.progress] / UI should interpret counters.
enum TaskProgressMode {
  /// [bytesReceived] / [bytesTotal] (downloads).
  bytes,

  /// [unitsDone] / [unitsTotal] (scan / retag item counts).
  units,
}

/// A single task-queue item persisted across restarts.
class QueueTask {
  QueueTask({
    required this.id,
    required this.sourceName,
    required this.remotePath,
    required this.fileName,
    required this.createdAt,
    this.kind = TaskKind.download,
    this.status = TaskStatus.pending,
    this.localPath,
    this.localUri,
    this.errorMessage,
    this.progress = 0.0,
    this.progressMode = TaskProgressMode.bytes,
    this.completedAt,
    this.bytesTotal,
    this.bytesReceived = 0,
    this.unitsTotal,
    this.unitsDone = 0,
    this.cacheGroupId,
    this.isEnumerator = false,
    this.target = DownloadTarget.cache,
    this.attempts = 0,
    this.nextRetryAt,
    this.downloadMode,
    this.remoteSize,
    this.remoteModified,
    this.priority = 0,
  });

  final String id;

  /// Disk name — binding point for account resolution at run time.
  final String sourceName;
  final String remotePath;

  /// Display title (file name for download; path / label for scan).
  final String fileName;
  final DateTime createdAt;
  TaskKind kind;
  TaskStatus status;
  String? localPath;

  /// Android SAF content URI. When non-null, [_runUpload] calls
  /// [PlatformExportService.readUriToCache] to materialise the file
  /// just-in-time. Cleared after the resolved cache path is written
  /// back to [localPath] for retries.
  String? localUri;

  String? errorMessage;

  /// Unified 0–1 progress for bars. Prefer [displayProgress] when reading.
  double progress;
  TaskProgressMode progressMode;
  DateTime? completedAt;
  int? bytesTotal;
  int bytesReceived;

  /// Count progress (scan / retag). Null [unitsTotal] = unknown denominator.
  int? unitsTotal;
  int unitsDone;
  String? cacheGroupId;

  /// True when this entry only *discovers* work: it walks its own [remotePath]
  /// and fans the result out into one unit task per item. It is kept out of the
  /// batch counters so a finished root does not report as a completed item, and
  /// so the notification total does not jump when its children appear.
  final bool isEnumerator;

  /// Destination for [TaskKind.download] only.
  DownloadTarget target;
  CloudDownloadMode? downloadMode;
  int? remoteSize;
  DateTime? remoteModified;

  int attempts;
  DateTime? nextRetryAt;

  /// In-memory scheduling priority (higher runs first). Not persisted: a
  /// restarted queue falls back to creation order, which is fine because the
  /// only reason to prioritise is "the user is waiting right now".
  int priority;

  bool get isPublic => target != DownloadTarget.cache;
  bool get isGallery => target == DownloadTarget.gallery;

  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.partial ||
      status == TaskStatus.cancelled;

  bool get isDownload => kind == TaskKind.download;

  /// 0–1 for UI; falls back to [progress] when totals are unknown.
  double get displayProgress {
    switch (progressMode) {
      case TaskProgressMode.units:
        final total = unitsTotal;
        if (total != null && total > 0) {
          return (unitsDone / total).clamp(0.0, 1.0);
        }
        return progress.clamp(0.0, 1.0);
      case TaskProgressMode.bytes:
        final total = bytesTotal;
        if (total != null && total > 0) {
          return (bytesReceived / total).clamp(0.0, 1.0);
        }
        return progress.clamp(0.0, 1.0);
    }
  }

  /// Sync [progress] from the active counter mode.
  void syncProgressFromCounters() {
    progress = displayProgress;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'source_name': sourceName,
    'remote_path': remotePath,
    'file_name': fileName,
    'created_at': createdAt.toIso8601String(),
    'kind': kind.storageKey,
    'status': status.name,
    'local_path': localPath,
    'local_uri': localUri,
    'error_message': errorMessage,
    'progress': progress,
    'progress_mode': progressMode.name,
    'completed_at': completedAt?.toIso8601String(),
    'bytes_total': bytesTotal,
    'bytes_received': bytesReceived,
    'units_total': unitsTotal,
    'units_done': unitsDone,
    'cache_group_id': cacheGroupId,
    'is_enumerator': isEnumerator ? 1 : 0,
    'target': target.storageKey,
    'download_mode': downloadMode?.name,
    'remote_size': remoteSize,
    'remote_modified': remoteModified?.toIso8601String(),
    'attempts': attempts,
    'next_retry_at': nextRetryAt?.toIso8601String(),
  };

  factory QueueTask.fromMap(Map<String, dynamic> map) => QueueTask(
    id: _asString(map['id']) ?? '',
    sourceName:
        _asString(map['source_name']) ??
        _asString(map['account_id']) ??
        'legacy',
    remotePath: _asString(map['remote_path']) ?? '',
    fileName: _asString(map['file_name']) ?? '',
    createdAt: _asDate(map['created_at']) ?? DateTime.now(),
    kind: TaskKindX.fromStorageKey(_asString(map['kind'])),
    status: TaskStatus.values.firstWhere(
      (e) => e.name == _asString(map['status']),
      orElse: () => TaskStatus.pending,
    ),
    localPath: _asString(map['local_path']),
    localUri: _asString(map['local_uri']),
    errorMessage: _asString(map['error_message']),
    progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
    progressMode: TaskProgressMode.values.firstWhere(
      (e) => e.name == _asString(map['progress_mode']),
      orElse: () => TaskProgressMode.bytes,
    ),
    completedAt: map['completed_at'] != null
        ? _asDate(map['completed_at'])
        : null,
    bytesTotal: map['bytes_total'] as int?,
    bytesReceived: (map['bytes_received'] as int?) ?? 0,
    unitsTotal: map['units_total'] as int?,
    unitsDone: (map['units_done'] as int?) ?? 0,
    cacheGroupId: _asString(map['cache_group_id']),
    isEnumerator: map['is_enumerator'] == 1,
    target: DownloadTargetX.fromStorageKey(_asString(map['target'])),
    downloadMode: CloudDownloadMode.values.firstWhere(
      (e) => e.name == _asString(map['download_mode']),
      orElse: () => CloudDownloadMode.cryptRange,
    ),
    remoteSize: map['remote_size'] as int?,
    remoteModified: map['remote_modified'] != null
        ? _asDate(map['remote_modified'])
        : null,
    attempts: (map['attempts'] as int?) ?? 0,
    nextRetryAt: map['next_retry_at'] != null
        ? _asDate(map['next_retry_at'])
        : null,
  );

  QueueTask copyWith({
    TaskKind? kind,
    TaskStatus? status,
    String? localPath,
    String? errorMessage,
    double? progress,
    TaskProgressMode? progressMode,
    DateTime? completedAt,
    int? bytesTotal,
    int? bytesReceived,
    int? unitsTotal,
    int? unitsDone,
    String? cacheGroupId,
    DownloadTarget? target,
    CloudDownloadMode? downloadMode,
    int? remoteSize,
    DateTime? remoteModified,
  }) {
    return QueueTask(
      id: id,
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      createdAt: createdAt,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      localPath: localPath ?? this.localPath,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      progressMode: progressMode ?? this.progressMode,
      completedAt: completedAt ?? this.completedAt,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      unitsTotal: unitsTotal ?? this.unitsTotal,
      unitsDone: unitsDone ?? this.unitsDone,
      cacheGroupId: cacheGroupId ?? this.cacheGroupId,
      isEnumerator: isEnumerator,
      target: target ?? this.target,
      downloadMode: downloadMode ?? this.downloadMode,
      remoteSize: remoteSize ?? this.remoteSize,
      remoteModified: remoteModified ?? this.remoteModified,
      attempts: attempts,
      nextRetryAt: nextRetryAt,
    );
  }
}
