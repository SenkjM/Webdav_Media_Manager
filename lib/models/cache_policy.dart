/// Auto-cleanup retention for downloaded cache files.
enum CacheRetention {
  oneDay,
  oneWeek,
  custom,
  never,
}

extension CacheRetentionX on CacheRetention {
  String get labelZh => switch (this) {
        CacheRetention.oneDay => '1 天',
        CacheRetention.oneWeek => '1 周',
        CacheRetention.custom => '自定义',
        CacheRetention.never => '永不',
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
  const CacheExpiryPolicy({
    required this.retention,
    this.customDuration,
  });

  final CacheRetention retention;

  /// Used when [retention] is [CacheRetention.custom].
  /// Ignored for other modes. If null while custom, falls back to 7 days.
  final Duration? customDuration;

  /// Effective retention window, or `null` when auto-delete is disabled.
  Duration? get effectiveDuration => switch (retention) {
        CacheRetention.oneDay => const Duration(days: 1),
        CacheRetention.oneWeek => const Duration(days: 7),
        CacheRetention.never => null,
        CacheRetention.custom =>
          customDuration ?? const Duration(days: 7),
      };

  /// Returns true if [lastAccessed] is older than retention and the file
  /// is neither currently playing nor mid-download.
  ///
  /// [CacheRetention.never] never auto-deletes (manual clear still OK).
  bool shouldDelete({
    required DateTime lastAccessed,
    required DateTime now,
    required bool isCurrentlyPlaying,
    required bool isDownloading,
  }) {
    if (isCurrentlyPlaying || isDownloading) return false;
    final duration = effectiveDuration;
    if (duration == null) return false;
    return now.difference(lastAccessed) >= duration;
  }
}
