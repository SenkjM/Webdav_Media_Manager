import 'package:flutter/foundation.dart';

/// Lets a tab's root screen take over the system back key.
///
/// Why this exists: the app shell wraps every tab in a nested [Navigator] and
/// installs its own `PopScope`. For a tab root that navigates *internally*
/// (the network library walks a directory stack) the shell cannot tell that
/// anything is poppable — the nested navigator's `canPop()` is false because
/// the screen is its only route — so back was swallowed by the shell instead of
/// returning to the parent directory.
///
/// Delegating through `PopScope` alone proved unreliable in that nesting, so the
/// shell now asks registered handlers explicitly and only falls back to its own
/// behaviour when none of them consumed the event.
class BackHandlerRegistry {
  BackHandlerRegistry._();

  /// Active handlers in registration order. Each returns true when it consumed
  /// the back gesture.
  static final List<bool Function()> _handlers = [];

  static void register(bool Function() handler) {
    if (!_handlers.contains(handler)) _handlers.add(handler);
  }

  static void unregister(bool Function() handler) {
    _handlers.remove(handler);
  }

  /// Returns true when [handler] was invoked and reported that it handled the
  /// back gesture.
  static bool tryHandleBack() {
    // Copy first: a handler may unregister itself while running.
    for (final handler in List<bool Function()>.from(_handlers)) {
      try {
        if (handler()) return true;
      } catch (e) {
        debugPrint('BackHandlerRegistry handler failed: $e');
      }
    }
    return false;
  }

  @visibleForTesting
  static void resetForTest() => _handlers.clear();
}
