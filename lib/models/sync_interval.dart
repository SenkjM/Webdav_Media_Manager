/// How often the background scan runs (credentials + playlists + library push).
///
/// A single knob instead of a hidden 30-minute timer: a user who syncs rarely
/// can turn it off, one who moves between two devices daily can shorten it.
enum SyncInterval {
  /// No background scan at all — sync only when the user asks.
  off,

  every15m,
  every30m,
  hourly,
  every6h,
  daily,
}

extension SyncIntervalX on SyncInterval {
  String get storageKey => switch (this) {
    SyncInterval.off => 'off',
    SyncInterval.every15m => '15m',
    SyncInterval.every30m => '30m',
    SyncInterval.hourly => '1h',
    SyncInterval.every6h => '6h',
    SyncInterval.daily => '24h',
  };

  String get labelZh => switch (this) {
    SyncInterval.off => '关闭（仅手动）',
    SyncInterval.every15m => '每 15 分钟',
    SyncInterval.every30m => '每 30 分钟',
    SyncInterval.hourly => '每 1 小时',
    SyncInterval.every6h => '每 6 小时',
    SyncInterval.daily => '每 24 小时',
  };

  /// Null when the scan is disabled.
  Duration? get duration => switch (this) {
    SyncInterval.off => null,
    SyncInterval.every15m => const Duration(minutes: 15),
    SyncInterval.every30m => const Duration(minutes: 30),
    SyncInterval.hourly => const Duration(hours: 1),
    SyncInterval.every6h => const Duration(hours: 6),
    SyncInterval.daily => const Duration(hours: 24),
  };

  static SyncInterval fromStorageKey(String? key) => switch (key) {
    'off' => SyncInterval.off,
    '15m' => SyncInterval.every15m,
    '1h' => SyncInterval.hourly,
    '6h' => SyncInterval.every6h,
    '24h' => SyncInterval.daily,
    _ => SyncInterval.every30m,
  };
}
