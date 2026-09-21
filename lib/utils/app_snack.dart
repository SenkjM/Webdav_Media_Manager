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
/// * **one slot** — showing a message dismisses whatever is on screen, so the
///   newest message always wins and nothing queues up;
/// * **same text within a few seconds is ignored** — tapping download five times
///   produces one message, not five;
/// * **tapping the message itself dismisses it** (swipe and the `知道了` button
///   work too);
/// * duration comes from Settings (short / normal / long / until dismissed / off).
class AppSnack {
  AppSnack._();

  static SettingsService? _settings;
  static String? _lastText;
  static DateTime? _lastAt;

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
    final now = DateTime.now();
    // Collapse identical rapid-fire taps into a single message.
    if (_lastText == text &&
        _lastAt != null &&
        now.difference(_lastAt!) < repeatWindow) {
      return;
    }
    _lastText = text;
    _lastAt = now;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    void dismiss() => messenger.hideCurrentSnackBar();

    // Replace, never queue.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: GestureDetector(
          // The bar itself is only hit-testable where it has content, so make the
          // whole text area opaque and dismiss on tap. Previously only the
          // `知道了` button reacted, which read as "tapping does nothing".
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

  /// Resets the dedupe window (tests).
  @visibleForTesting
  static void resetForTest() {
    _lastText = null;
    _lastAt = null;
  }
}
