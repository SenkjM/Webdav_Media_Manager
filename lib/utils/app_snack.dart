import 'dart:async';

import 'package:flutter/material.dart';

import '../models/snack_duration.dart';
import '../services/settings_service.dart';

/// App-wide, single-slot message presenter.
///
/// Problems this solves (all visible in normal use):
/// * repeated taps queued a backlog of identical bars that then played one after
///   another long after the action;
/// * a later message could not be seen until the earlier one finished;
/// * there was no way to dismiss a message early;
/// * messages were covered by AlertDialogs, the keyboard and the bottom
///   navigation bar — the banner now renders **above the Navigator** (置于顶层),
///   so nothing can cover it, while staying at the bottom of the screen.
///
/// Rules:
/// * **one slot** — showing a message removes whatever is on screen, so the
///   newest message always wins and nothing queues up;
/// * **every message carries 知道了** and tapping either the button or the text
///   removes it **immediately** (no exit animation to outrun);
/// * once you dismiss a message, that exact text is *not* shown again until a
///   different message appears;
/// * duration comes from Settings (short / normal / long / until dismissed /
///   off), so 设置 → 提示与通知 governs every in-app message.
class AppSnack {
  AppSnack._();

  static SettingsService? _settings;
  static String? _lastText;
  static DateTime? _lastAt;

  /// Text the user explicitly closed; suppressed until the text changes.
  static String? _dismissedText;

  /// The message currently on screen (single slot).
  static final ValueNotifier<AppSnackMessage?> _current =
      ValueNotifier<AppSnackMessage?>(null);

  static Timer? _timer;
  static int _token = 0;

  /// Set once from `AppState.init`.
  static void attach(SettingsService settings) => _settings = settings;

  /// Fallback when no SettingsService is attached (tests / early boot).
  static const Duration defaultDuration = Duration(seconds: 3);

  /// Ignore an identical message repeating within this window.
  static const Duration repeatWindow = Duration(seconds: 3);

  /// Wire into `MaterialApp.builder`.
  ///
  /// The banner lives *above* the `Navigator`, so pages, dialogs and the
  /// keyboard can never cover it; it stays at the bottom of the screen where
  /// users expect an in-app message (置顶 = 置于顶层, not "moved to the top").
  static Widget hostBuilder(BuildContext context, Widget? child) {
    return Stack(
      children: <Widget>[
        ?child,
        const _BannerHost(),
      ],
    );
  }

  /// Same contract as [show], for callers without a `BuildContext` (the
  /// download queue reports from background work).
  static void showGlobal(String text, {bool error = false}) =>
      _present(text, error: error);

  static void show(BuildContext context, String text, {bool error = false}) {
    if (!context.mounted) return;
    _present(text, error: error);
  }

  static void _present(String text, {required bool error}) {
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

    // Replace, never queue.
    _remove();
    _current.value = AppSnackMessage(
      text: text,
      error: error,
      token: ++_token,
    );
    _timer = Timer(
      _settings?.snackMode.duration ?? defaultDuration,
      _remove,
    );
  }

  static void _remove() {
    _timer?.cancel();
    _timer = null;
    _current.value = null;
  }

  static void _dismiss(String text) {
    _dismissedText = text;
    // Immediate removal: no exit animation to outrun, nothing queued behind.
    _remove();
  }

  static void error(BuildContext context, String text) =>
      show(context, text, error: true);

  /// Resets the dedupe/dismissal state (tests).
  @visibleForTesting
  static void resetForTest() {
    _remove();
    _lastText = null;
    _lastAt = null;
    _dismissedText = null;
  }
}

/// One in-app message ([AppSnack] internal carrier).
class AppSnackMessage {
  const AppSnackMessage({
    required this.text,
    required this.error,
    required this.token,
  });

  final String text;
  final bool error;
  final int token;
}

/// Renders the current message at the bottom, inside the builder-level stack.
class _BannerHost extends StatelessWidget {
  const _BannerHost();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSnackMessage?>(
      valueListenable: AppSnack._current,
      builder: (context, message, _) {
        if (message == null) return const SizedBox.shrink();
        // 键盘弹出时抬到键盘之上，否则输入法会盖住消息。
        final inset = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + inset),
              child: _BannerCard(
                message: message,
                onDismiss: () => AppSnack._dismiss(message.text),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The card itself: rounded, tappable anywhere, with 知道了 on the right.
class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.message, required this.onDismiss});

  final AppSnackMessage message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = message.error
        ? const Color(0xFFB3261E)
        : theme.colorScheme.inverseSurface;
    final foreground =
        message.error ? Colors.white : theme.colorScheme.onInverseSurface;
    return Material(
      color: background,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onDismiss,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
