/// Download queue task statuses.
enum DownloadStatus { pending, active, completed, failed, cancelled }

/// Where a downloaded file is written.
enum DownloadTarget {
  /// App-internal audio cache (`music_cache/`). Required for music playback —
  /// music is never streamed, so its only usable destination is the cache.
  cache,

  /// System gallery / media library via MediaStore (Android `Movies/…`).
  /// Video downloads go here instead of the app-private cache.
  gallery,

  /// Public Downloads folder via MediaStore (`Download/…`).
  ///
  /// Used for files whose extension is not in the configured music/video/CUE
  /// lists: they are still downloadable, they just have no playback path.
  downloads,
}

extension DownloadTargetX on DownloadTarget {
  String get storageKey => switch (this) {
    DownloadTarget.cache => 'cache',
    DownloadTarget.gallery => 'gallery',
    DownloadTarget.downloads => 'downloads',
  };

  /// Short badge shown in the download queue and library lists.
  String get labelZh => switch (this) {
    DownloadTarget.cache => '应用缓存',
    DownloadTarget.gallery => '系统相册',
    DownloadTarget.downloads => '系统下载目录',
  };

  static DownloadTarget fromStorageKey(String? key) => switch (key) {
    'gallery' => DownloadTarget.gallery,
    'downloads' => DownloadTarget.downloads,
    _ => DownloadTarget.cache,
  };
}

/// A single download queue item persisted across restarts.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.sourceName,
    required this.remotePath,
    required this.fileName,
    required this.createdAt,
    this.status = DownloadStatus.pending,
    this.localPath,
    this.errorMessage,
    this.progress = 0.0,
    this.completedAt,
    this.bytesTotal,
    this.bytesReceived = 0,
    this.cacheGroupId,
    this.target = DownloadTarget.cache,
    this.attempts = 0,
    this.nextRetryAt,
  });

  final String id;

  /// 网盘名 —— the binding point. The local WebDAV account (URL/username/
  /// password) is resolved from this name when the transfer actually runs, so a
  /// renamed or re-added disk can never leave a stale pointer in the queue.
  final String sourceName;
  final String remotePath;
  final String fileName;
  final DateTime createdAt;
  DownloadStatus status;
  String? localPath;
  String? errorMessage;
  double progress;
  DateTime? completedAt;
  int? bytesTotal;
  int bytesReceived;
  String? cacheGroupId;

  /// Destination the file was (or will be) written to.
  DownloadTarget target;

  /// 自动重试已经用掉几次（见 download_queue_service 的退避策略）。
  /// 手动点「重试」会清零。
  int attempts;

  /// 下一次允许尝试的时间；null = 立即可跑。无网时不消耗 [attempts]，
  /// 只把这个时间推远，等网络事件把队列唤醒。
  DateTime? nextRetryAt;

  /// True when the file went to a **public** collection (system gallery or the
  /// Downloads folder) rather than the app-private audio cache.
  bool get isPublic => target != DownloadTarget.cache;

  /// True when the file went to the system gallery specifically.
  bool get isGallery => target == DownloadTarget.gallery;

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  Map<String, dynamic> toMap() => {
    'id': id,
    'source_name': sourceName,
    'remote_path': remotePath,
    'file_name': fileName,
    'created_at': createdAt.toIso8601String(),
    'status': status.name,
    'local_path': localPath,
    'error_message': errorMessage,
    'progress': progress,
    'completed_at': completedAt?.toIso8601String(),
    'bytes_total': bytesTotal,
    'bytes_received': bytesReceived,
    'cache_group_id': cacheGroupId,
    'target': target.storageKey,
    'attempts': attempts,
    'next_retry_at': nextRetryAt?.toIso8601String(),
  };

  factory DownloadTask.fromMap(Map<String, dynamic> map) => DownloadTask(
    id: map['id'] as String,
    sourceName:
        (map['source_name'] as String?) ??
        (map['account_id'] as String?) ??
        'legacy',
    remotePath: map['remote_path'] as String,
    fileName: map['file_name'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    status: DownloadStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => DownloadStatus.pending,
    ),
    localPath: map['local_path'] as String?,
    errorMessage: map['error_message'] as String?,
    progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
    completedAt: map['completed_at'] != null
        ? DateTime.parse(map['completed_at'] as String)
        : null,
    bytesTotal: map['bytes_total'] as int?,
    bytesReceived: (map['bytes_received'] as int?) ?? 0,
    cacheGroupId: map['cache_group_id'] as String?,
    target: DownloadTargetX.fromStorageKey(map['target'] as String?),
    attempts: (map['attempts'] as int?) ?? 0,
    nextRetryAt: map['next_retry_at'] != null
        ? DateTime.parse(map['next_retry_at'] as String)
        : null,
  );

  DownloadTask copyWith({
    DownloadStatus? status,
    String? localPath,
    String? errorMessage,
    double? progress,
    DateTime? completedAt,
    int? bytesTotal,
    int? bytesReceived,
    String? cacheGroupId,
    DownloadTarget? target,
  }) {
    return DownloadTask(
      id: id,
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      createdAt: createdAt,
      status: status ?? this.status,
      localPath: localPath ?? this.localPath,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      completedAt: completedAt ?? this.completedAt,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      cacheGroupId: cacheGroupId ?? this.cacheGroupId,
      target: target ?? this.target,
    );
  }
}
