import 'package:flutter/material.dart';

import '../models/snack_duration.dart';
import '../services/settings_service.dart';

/// App-wide, single-slot message presenter.
///
/// Problems this solves (all visible in normal use):
/// * repeated taps queued a backlog of identical bars that then played one after
///   another long after the action;
/// * a later message could not be seen until the earlier one finished;
/// * there was no way to dismiss a message early.
///
/// Rules:
/// * **one slot** — showing a message removes whatever is on screen, so the
///   newest message always wins and nothing queues up;
/// * **every message carries 知道了** and tapping either the button or the text
///   removes it **immediately** (no exit animation to outrun);
/// * once you dismiss a message, that exact text is *not* shown again until a
///   different message appears — otherwise a background ticker re-showing the
///   same line looks like "知道了 不管用";
/// * duration comes from Settings (short / normal / long / until dismissed /
///   off), so 设置 → 提示与通知 governs every in-app message.
class AppSnack {
  AppSnack._();

  static SettingsService? _settings;
  static String? _lastText;
  static DateTime? _lastAt;

  /// Text the user explicitly closed; suppressed until the text changes.
  static String? _dismissedText;

  /// Set once from `AppState.init`.
  static void attach(SettingsService settings) => _settings = settings;

  /// Fallback when no SettingsService is attached (tests / early boot).
  static const Duration defaultDuration = Duration(seconds: 3);

  /// Ignore an identical message repeating within this window.
  static const Duration repeatWindow = Duration(seconds: 3);

  static void show(BuildContext context, String text, {bool error = false}) {
    if (!context.mounted) return;
    // Settings → 提示与通知 → 应用内消息 = 关闭.
    if (_settings?.snackMode.visible == false) return;
    // The user already closed exactly this message and nothing else has been
    // shown since: do not resurrect it.
    if (_dismissedText == text) return;

    final now = DateTime.now();
    // Collapse identical rapid-fire taps into a single message.
    if (_lastText == text &&
        _lastAt != null &&
        now.difference(_lastAt!) < repeatWindow) {
      return;
    }
    _lastText = text;
    _lastAt = now;
    // A different message ends the suppression of the previous one.
    _dismissedText = null;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    void dismiss() {
      _dismissedText = text;
      // `remove`, not `hide`: removal is immediate and leaves no exit animation
      // or queued bar behind, which is what made the button feel dead.
      messenger.removeCurrentSnackBar();
      messenger.clearSnackBars();
    }

    // Replace, never queue.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: GestureDetector(
          // The bar is only hit-testable where it has content, so make the whole
          // text area opaque and dismiss on tap.
          behavior: HitTestBehavior.opaque,
          onTap: dismiss,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(text),
          ),
        ),
        duration: _settings?.snackMode.duration ?? defaultDuration,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.horizontal,
        backgroundColor: error ? const Color(0xFFB3261E) : null,
        action: SnackBarAction(
          label: '知道了',
          textColor: error ? Colors.white : null,
          onPressed: dismiss,
        ),
      ),
    );
  }

  static void error(BuildContext context, String text) =>
      show(context, text, error: true);

  /// Resets the dedupe/dismissal state (tests).
  @visibleForTesting
  static void resetForTest() {
    _lastText = null;
    _lastAt = null;
    _dismissedText = null;
  }
}
