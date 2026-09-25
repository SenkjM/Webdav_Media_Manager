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
///
/// **Tab 归属**：shell 用 IndexedStack 保活所有 tab，后台 tab 的 State 依然活着。
/// 处理器注册时声明自己属于哪个 tab（[register] 的 `tab`），shell 维护
/// [activeTabIndex]；分发时只考虑活跃 tab 的（或未声明归属的）处理器——
/// 否则后台 tab 会吃掉别的 tab 的返回键（真机反馈：下载页按返回被网络库
/// 消费，一路退完目录栈才回到设定主页）。
class BackHandlerRegistry {
  BackHandlerRegistry._();

  /// Active handlers in registration order. Each returns true when it consumed
  /// the back gesture.
  static final List<_Entry> _handlers = [];

  /// 当前活跃 tab 的索引（由 [HomeShell] 维护；shell 销毁时置回 null）。
  static int? activeTabIndex;

  static void register(bool Function() handler, {int? tab}) {
    if (!_handlers.any((e) => e.handler == handler)) {
      _handlers.add(_Entry(handler, tab));
    }
  }

  static void unregister(bool Function() handler) {
    _handlers.removeWhere((e) => e.handler == handler);
  }

  /// Returns true when a handler was invoked and reported that it handled the
  /// back gesture.
  static bool tryHandleBack() {
    // Copy first: a handler may unregister itself while running.
    for (final entry in List<_Entry>.from(_handlers)) {
      // 别的 tab 的处理器不参与分发（见类注释）。
      if (entry.tab != null && entry.tab != activeTabIndex) continue;
      try {
        if (entry.handler()) return true;
      } catch (e) {
        debugPrint('BackHandlerRegistry handler failed: $e');
      }
    }
    return false;
  }

  @visibleForTesting
  static void resetForTest() => _handlers.clear();
}

class _Entry {
  const _Entry(this.handler, this.tab);

  final bool Function() handler;

  /// 处理器归属的 tab；null = 与 tab 无关，任何上下文都参与分发。
  final int? tab;
}
