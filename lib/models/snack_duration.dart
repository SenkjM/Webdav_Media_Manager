/// How long in-app messages (SnackBars) stay on screen.
///
/// They are always single-slot — a new message replaces the current one and
/// identical repeats within a few seconds are ignored — so this only controls how
/// long a message lingers.
enum SnackDuration {
  /// 1.5s — for people who find the messages noisy.
  short,

  /// 3s — default.
  normal,

  /// 5s — easier to read while doing something else.
  long,

  /// Stays until tapped or swiped away.
  untilDismissed,

  /// Never show in-app messages at all.
  off,
}

extension SnackDurationX on SnackDuration {
  String get storageKey => switch (this) {
    SnackDuration.short => 'short',
    SnackDuration.normal => 'normal',
    SnackDuration.long => 'long',
    SnackDuration.untilDismissed => 'until_dismissed',
    SnackDuration.off => 'off',
  };

  String get labelZh => switch (this) {
    SnackDuration.short => '很短',
    SnackDuration.normal => '默认',
    SnackDuration.long => '较长',
    SnackDuration.untilDismissed => '点击才消失',
    SnackDuration.off => '关闭',
  };

  /// Whether messages are shown at all.
  bool get visible => this != SnackDuration.off;

  Duration get duration => switch (this) {
    SnackDuration.short => const Duration(milliseconds: 1500),
    SnackDuration.normal => const Duration(seconds: 3),
    SnackDuration.long => const Duration(seconds: 5),
    // Effectively "forever"; cleared by tapping the message or a new one.
    SnackDuration.untilDismissed => const Duration(minutes: 30),
    // Never shown; the value is irrelevant.
    SnackDuration.off => Duration.zero,
  };

  static SnackDuration fromStorageKey(String? key) => switch (key) {
    'short' => SnackDuration.short,
    'long' => SnackDuration.long,
    'until_dismissed' => SnackDuration.untilDismissed,
    'off' => SnackDuration.off,
    _ => SnackDuration.normal,
  };
}
