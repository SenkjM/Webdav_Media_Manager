/// Download queue task statuses.
enum DownloadStatus {
  pending,
  active,
  completed,
  failed,
  cancelled,
}

/// Where a downloaded file is written.
enum DownloadTarget {
  /// App-internal audio cache (`music_cache/`). Required for music playback —
  /// music is never streamed, so its only usable destination is the cache.
  cache,

  /// System gallery / media library via MediaStore (Android `Movies/…`).
  /// Video downloads go here instead of the app-private cache.
  gallery,
}

extension DownloadTargetX on DownloadTarget {
  String get storageKey => switch (this) {
        DownloadTarget.cache => 'cache',
        DownloadTarget.gallery => 'gallery',
      };

  /// Short badge shown in the download queue and library lists.
  String get labelZh => switch (this) {
        DownloadTarget.cache => '应用缓存',
        DownloadTarget.gallery => '系统相册',
      };

  static DownloadTarget fromStorageKey(String? key) =>
      key == 'gallery' ? DownloadTarget.gallery : DownloadTarget.cache;
}

/// A single download queue item persisted across restarts.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.accountId,
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
  });

  final String id;
  final String accountId;
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

  /// True when the file went to the system gallery rather than app storage.
  bool get isGallery => target == DownloadTarget.gallery;

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  Map<String, dynamic> toMap() => {
        'id': id,
        'account_id': accountId,
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
      };

  factory DownloadTask.fromMap(Map<String, dynamic> map) => DownloadTask(
        id: map['id'] as String,
        accountId: (map['account_id'] as String?) ?? 'legacy',
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
      accountId: accountId,
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
