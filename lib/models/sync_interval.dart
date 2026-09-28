import '../l10n/generated/app_localizations.dart';

/// How often the background scan runs (credentials + playlists + library push).
///
/// A single knob instead of a hidden 30-minute timer: a user who syncs rarely
/// can leave it off, one who moves between two devices daily can shorten it.
///
/// The default is [SyncInterval.off]: nothing runs in the background until the
/// user explicitly asks for it.
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

  String label(AppLocalizations l10n) => switch (this) {
    SyncInterval.off => l10n.syncOff,
    SyncInterval.every15m => l10n.syncEvery15m,
    SyncInterval.every30m => l10n.syncEvery30m,
    SyncInterval.hourly => l10n.syncHourly,
    SyncInterval.every6h => l10n.syncEvery6h,
    SyncInterval.daily => l10n.syncDaily,
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

  /// What a fresh install (or an unreadable value) starts from.
  static const SyncInterval fallback = SyncInterval.off;

  static SyncInterval fromStorageKey(String? key) => switch (key) {
    'off' => SyncInterval.off,
    '15m' => SyncInterval.every15m,
    '30m' => SyncInterval.every30m,
    '1h' => SyncInterval.hourly,
    '6h' => SyncInterval.every6h,
    '24h' => SyncInterval.daily,
    _ => fallback,
  };
}
