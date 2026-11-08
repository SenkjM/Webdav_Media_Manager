import 'package:flutter/foundation.dart';

/// Lightweight startup phase tracer (debug builds only).
///
/// Call [BootTrace.mark] at the start of each init phase to get a timestamped
/// log of the startup sequence. All output is suppressed in release builds.
///
/// Example:
/// ```dart
/// BootTrace.mark('core-init');
/// // ... do the work ...
/// BootTrace.mark('settings');
/// ```
abstract final class BootTrace {
  static final _start = DateTime.now();

  /// Emit a debug-only timestamped marker for [phase].
  ///
  /// The elapsed time shown is wall-clock ms since the first [mark] call.
  static void mark(String phase) {
    if (!kDebugMode) return;
    final elapsed = DateTime.now().difference(_start).inMilliseconds;
    debugPrint('[BootTrace] +${elapsed}ms $phase');
  }
}
