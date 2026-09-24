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
/// * messages sat at the bottom, where AlertDialogs, the keyboard and the bottom
///   navigation bar covered them — they are now a top banner instead.
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

  /// The banner currently on screen (single slot: a new message replaces it).
  static OverlayEntry? _entry;

  /// Auto-dismiss timer for [_entry].
  static Timer? _timer;

  /// Lets a service without a `BuildContext` (the download queue) post a message.
  /// Wired to `MaterialApp.scaffoldMessengerKey`.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Set once from `AppState.init`.
  static void attach(SettingsService settings) => _settings = settings;

  /// Fallback when no SettingsService is attached (tests / early boot).
  static const Duration defaultDuration = Duration(seconds: 3);

  /// Ignore an identical message repeating within this window.
  static const Duration repeatWindow = Duration(seconds: 3);

  /// Same contract as [show], for callers that only have the global key.
  static void showGlobal(String text, {bool error = false}) {
    final context = messengerKey.currentContext;
    if (context == null) return;
    _present(context, text, error: error);
  }

  static void show(BuildContext context, String text, {bool error = false}) {
    if (!context.mounted) return;
    _present(context, text, error: error);
  }
  static void _present(
    BuildContext context,
    String text, {
    required bool error,
  }) {
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

    // 顶部横幅挂在根 Overlay 上：ScaffoldMessenger 的 SnackBar 只能贴底，会被
    // AlertDialog / 键盘 / 底部导航挡住（真机上往往只露出一条边）。
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    void dismiss() {
      _dismissedText = text;
      // 立即移除，不留退场动画，也不排队——与旧 SnackBar 契约一致。
      _removeEntry();
    }

    // Replace, never queue.
    _removeEntry();
    final entry = OverlayEntry(
      builder: (_) => _TopBanner(
        text: text,
        error: error,
        onDismiss: dismiss,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(
      _settings?.snackMode.duration ?? defaultDuration,
      _removeEntry,
    );
  }

  /// Removes the banner if one is on screen. Safe to call twice.
  static void _removeEntry() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    try {
      if (entry.mounted) entry.remove();
    } catch (_) {
      // 树已销毁（测试切换 / 应用退出）时 Overlay 会先清理 entry。
    }
  }
  static void error(BuildContext context, String text) =>
      show(context, text, error: true);

  /// Resets the dedupe/dismissal state (tests).
  @visibleForTesting
  static void resetForTest() {
    _removeEntry();
    _lastText = null;
    _lastAt = null;
    _dismissedText = null;
  }
}

/// 应用内消息的顶部横幅：圆角卡片挂在根 Overlay 顶部安全区下方，整块可点、
/// 右侧「知道了」立即移除。错误消息用错误色，其余用反色面。
class _TopBanner extends StatelessWidget {
  const _TopBanner({
    required this.text,
    required this.error,
    required this.onDismiss,
  });

  final String text;
  final bool error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        error ? const Color(0xFFB3261E) : theme.colorScheme.inverseSurface;
    final foreground =
        error ? Colors.white : theme.colorScheme.onInverseSurface;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
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
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: foreground),
                      ),
                    ),
                    TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
