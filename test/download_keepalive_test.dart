import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/download_keepalive.dart';

/// In-memory stand-in for the SharedPreferences store, so tests never touch
/// the platform channel.
class _MemorySuppression implements DownloadKeepAliveSuppressionStore {
  DateTime? until;

  @override
  Future<DateTime?> read() async => until;

  @override
  Future<void> write(DateTime? value) async {
    until = value;
  }
}

DownloadKeepAlive _make(
  _FakeBridge bridge, [
  DownloadKeepAliveSuppressionStore? suppression,
]) => DownloadKeepAlive(
  bridge: bridge,
  suppression: suppression ?? _MemorySuppression(),
);

class _FakeBridge implements DownloadKeepAliveBridge {
  int starts = 0;
  int stops = 0;
  bool failStart = false;

  /// What the native side reports from `isRunning` — set false to simulate a
  /// service that was reclaimed behind Dart's back.
  bool nativelyRunning = true;
  void Function()? onTimeout;
  void Function(String error)? onStartFailed;
  void Function()? onStopped;

  @override
  void bind({
    required void Function() onTimeout,
    required void Function(String error) onStartFailed,
    required void Function() onStopped,
  }) {
    this.onTimeout = onTimeout;
    this.onStartFailed = onStartFailed;
    this.onStopped = onStopped;
  }

  @override
  Future<bool> isRunning() async => nativelyRunning;

  @override
  Future<KeepAliveStartResult> start({
    required String title,
    required int notificationId,
    required String channelId,
  }) async {
    starts++;
    if (failStart) {
      return const KeepAliveStartResult(ok: false, error: 'blocked');
    }
    return const KeepAliveStartResult(ok: true);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<Map<String, Object?>> diagnostics() async => {'fgsRunning': true};
}

Future<void> _start(_FakeBridge bridge, DownloadKeepAlive keepAlive) {
  return keepAlive.ensureRunning(
    title: '正在同步',
    notificationId: 2001,
    channelId: 'com.senkjm.media_manager.downloads.v1',
    isForeground: () => true,
  );
}

void main() {
  test('前台 ensureRunning 只启动一次，release 再停', () async {
    final bridge = _FakeBridge();
    final keepAlive = _make(bridge);
    await _start(bridge, keepAlive);
    await _start(bridge, keepAlive);
    expect(bridge.starts, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.running);
    expect(keepAlive.isRunning, isTrue);
    await keepAlive.release();
    expect(bridge.stops, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
    await keepAlive.release();
    expect(bridge.stops, 1);
  });

  test('启动失败后 release 仍请求原生停止（原生可能已自行 stopSelf）', () async {
    final bridge = _FakeBridge()..failStart = true;
    final keepAlive = _make(bridge);
    await _start(bridge, keepAlive);
    expect(keepAlive.phase, DownloadKeepAlivePhase.failedToStart);
    expect(keepAlive.lastStartError, 'blocked');
    await keepAlive.release();
    expect(bridge.stops, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
  });

  test('原生服务在背后死掉时，下一次 ensureRunning 会重新启动', () async {
    final bridge = _FakeBridge();
    final keepAlive = _make(bridge);
    await _start(bridge, keepAlive);
    expect(bridge.starts, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.running);

    // System reclaim / OEM killer: Dart is never told, only the probe sees it.
    bridge.nativelyRunning = false;
    await _start(bridge, keepAlive);
    expect(bridge.starts, 2);
    expect(keepAlive.phase, DownloadKeepAlivePhase.running);
  });

  test('onStopped 回调把 running 复位成 idle', () async {
    final bridge = _FakeBridge();
    final keepAlive = _make(bridge);
    var hits = 0;
    keepAlive.onStopped = () => hits++;
    await _start(bridge, keepAlive);
    bridge.onStopped?.call();
    expect(hits, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
    expect(keepAlive.holdsOrStarting, isFalse);
  });

  test('不在前台或配额冷却中不启动', () async {
    final bridge = _FakeBridge();
    final keepAlive = _make(bridge);
    await keepAlive.ensureRunning(
      title: '正在同步',
      notificationId: 2001,
      channelId: 'c',
      isForeground: () => false,
    );
    expect(bridge.starts, 0);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
    keepAlive.suppressStartUntil(
      DateTime.now().add(const Duration(minutes: 5)),
    );
    await _start(bridge, keepAlive);
    expect(bridge.starts, 0);
  });

  test('onTimeout 停在 idle 并通知调用方，之后 release 不再 stop', () async {
    final bridge = _FakeBridge();
    final keepAlive = _make(bridge);
    await _start(bridge, keepAlive);
    var hits = 0;
    keepAlive.onTimeout = () => hits++;
    bridge.onTimeout?.call();
    expect(hits, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
    expect(keepAlive.holdsOrStarting, isFalse);
    await keepAlive.release();
    expect(bridge.stops, 0);
  });

  test('超时冷却会写进注入的存储，重启后仍被恢复', () async {
    final store = _MemorySuppression();
    final first = _FakeBridge();
    final keepAlive = _make(first, store);
    await _start(first, keepAlive);
    keepAlive.suppressStartUntil(
      DateTime.now().add(const Duration(minutes: 5)),
    );
    await pumpEventQueue();
    expect(store.until, isNotNull);

    // A fresh instance inside the window must not start the FGS again.
    final bridge = _FakeBridge();
    final restarted = _make(bridge, store);
    await pumpEventQueue();
    await _start(bridge, restarted);
    expect(bridge.starts, 0);
  });

  test('先启动再 release 串行，最终是 idle', () async {
    final bridge = _FakeBridge();
    final keepAlive = _make(bridge);
    await Future.wait([_start(bridge, keepAlive), keepAlive.release()]);
    expect(bridge.starts, 1);
    expect(bridge.stops, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
  });
}
