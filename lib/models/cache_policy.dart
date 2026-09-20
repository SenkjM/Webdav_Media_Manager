/// Auto-cleanup retention for downloaded cache files.
enum CacheRetention {
  oneDay,
  oneWeek,
}

extension CacheRetentionX on CacheRetention {
  Duration get duration => switch (this) {
        CacheRetention.oneDay => const Duration(days: 1),
        CacheRetention.oneWeek => const Duration(days: 7),
      };

  String get labelZh => switch (this) {
        CacheRetention.oneDay => '1 天',
        CacheRetention.oneWeek => '1 周',
      };

  String get storageKey => name;

  static CacheRetention fromStorageKey(String? key) {
    return CacheRetention.values.firstWhere(
      (e) => e.name == key,
      orElse: () => CacheRetention.oneWeek,
    );
  }
}

/// Pure policy used by [CacheService] and unit tests.
class CacheExpiryPolicy {
  const CacheExpiryPolicy({required this.retention});

  final CacheRetention retention;

  /// Returns true if [lastAccessed] is older than retention and the file
  /// is neither currently playing nor mid-download.
  bool shouldDelete({
    required DateTime lastAccessed,
    required DateTime now,
    required bool isCurrentlyPlaying,
    required bool isDownloading,
  }) {
    if (isCurrentlyPlaying || isDownloading) return false;
    return now.difference(lastAccessed) >= retention.duration;
  }
}
