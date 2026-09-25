// 网络库失败重试的「有上限 + 防重入 + 网络恢复重置」语义测试。
//
// 真机反馈：crypt 源被删除后应用被拖慢。根因是 build 里的账号切换守卫在
// 加载失败（_browsedAccountId 不更新）时每帧又调度一次 _ensureAndLoad，
// 并发堆叠全量账号重建。修复：① _ensureInFlight 防重入；② 连续失败达到上限
// 后停止自动重试、停在错误界面等用户手动重试；③ 网络恢复事件重置上限。
// 这里用与生产代码相同的计数/守卫逻辑做纯 Dart 等价验证。

import 'package:flutter_test/flutter_test.dart';

class _RetryPolicy {
  static const int maxFailures = 3;

  int failures = 0;
  bool inFlight = false;
  int autoAttempts = 0;

  /// 复刻 build 守卫：只在未超限、未加载中才自动调度。
  bool shouldAutoRetry({required bool accountChanged, required bool loading}) {
    return accountChanged && !loading && failures < maxFailures;
  }

  /// 复刻 _ensureAndLoad 的防重入包装。
  bool enter() {
    if (inFlight) return false;
    inFlight = true;
    return true;
  }

  void leave() => inFlight = false;

  /// 复刻 _load：成功清零，失败累加并给出是否已放弃。
  bool load({required bool ok}) {
    if (!ok) {
      failures++;
      return failures >= maxFailures;
    }
    failures = 0;
    return false;
  }

  /// 手动重试 = 用户意志，重置上限。
  void manualRetry() => failures = 0;

  /// 网络恢复事件重置。
  void networkRecovered() => failures = 0;
}

void main() {
  test('连续失败达到上限后不再自动重试（停在错误界面）', () {
    final p = _RetryPolicy();
    expect(p.shouldAutoRetry(accountChanged: true, loading: false), isTrue);
    for (var i = 0; i < _RetryPolicy.maxFailures; i++) {
      p.enter();
      expect(p.load(ok: false), i + 1 == _RetryPolicy.maxFailures,
          reason: '第 ${_RetryPolicy.maxFailures} 次失败即应放弃自动重试');
      p.leave();
    }
    expect(p.shouldAutoRetry(accountChanged: true, loading: false), isFalse,
        reason: '超限后除手动/网络恢复外不得再自动调度');
  });

  test('防重入：await 期间重复进入被拒（真机拖慢的根因）', () {
    final p = _RetryPolicy();
    expect(p.enter(), isTrue, reason: '首次进入允许');
    expect(p.enter(), isFalse, reason: '进行中再进一律拒绝，避免并发多份全量重建');
    p.leave();
    expect(p.enter(), isTrue, reason: '完成后再进放行');
  });

  test('手动重试与网络恢复都会重置上限', () {
    final p = _RetryPolicy();
    for (var i = 0; i < _RetryPolicy.maxFailures; i++) { p.load(ok: false); }
    expect(p.failures, _RetryPolicy.maxFailures);
    p.manualRetry();
    expect(p.failures, 0);
    expect(p.shouldAutoRetry(accountChanged: true, loading: false), isTrue);
    for (var i = 0; i < _RetryPolicy.maxFailures; i++) { p.load(ok: false); }
    p.networkRecovered();
    expect(p.shouldAutoRetry(accountChanged: true, loading: false), isTrue,
        reason: '网络变化 = 新的一轮');
  });

  test('中间一次成功即清零：瞬时故障不会累积', () {
    final p = _RetryPolicy();
    p.load(ok: false);
    p.load(ok: false);
    expect(p.failures, 2);
    p.load(ok: true);
    expect(p.failures, 0, reason: '成功加载清零，重启计数窗口');
    expect(p.shouldAutoRetry(accountChanged: true, loading: false), isTrue);
  });
}