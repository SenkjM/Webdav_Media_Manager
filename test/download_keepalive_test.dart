import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/download_keepalive.dart';

class _FakeBridge implements DownloadKeepAliveBridge {
  int starts = 0;
  int stops = 0;
  bool failStart = false;
  void Function()? onTimeout;
  void Function(String error)? onStartFailed;

  @override
  void bind({
    required void Function() onTimeout,
    required void Function(String error) onStartFailed,
  }) {
    this.onTimeout = onTimeout;
    this.onStartFailed = onStartFailed;
  }

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
    title: '正在下载',
    notificationId: 2001,
    channelId: 'com.senkjm.media_manager.downloads.v1',
    isForeground: () => true,
  );
}

void main() {
  test('前台 ensureRunning 只启动一次，release 再停', () async {
    final bridge = _FakeBridge();
    final keepAlive = DownloadKeepAlive(bridge: bridge);
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

  test('启动失败不调用 stop，release 回到 idle', () async {
    final bridge = _FakeBridge()..failStart = true;
    final keepAlive = DownloadKeepAlive(bridge: bridge);
    await _start(bridge, keepAlive);
    expect(keepAlive.phase, DownloadKeepAlivePhase.failedToStart);
    expect(keepAlive.lastStartError, 'blocked');
    await keepAlive.release();
    expect(bridge.stops, 0);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
  });

  test('不在前台或配额冷却中不启动', () async {
    final bridge = _FakeBridge();
    final keepAlive = DownloadKeepAlive(bridge: bridge);
    await keepAlive.ensureRunning(
      title: '正在下载',
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
    final keepAlive = DownloadKeepAlive(bridge: bridge);
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

  test('先启动再 release 串行，最终是 idle', () async {
    final bridge = _FakeBridge();
    final keepAlive = DownloadKeepAlive(bridge: bridge);
    await Future.wait([_start(bridge, keepAlive), keepAlive.release()]);
    expect(bridge.starts, 1);
    expect(bridge.stops, 1);
    expect(keepAlive.phase, DownloadKeepAlivePhase.idle);
  });
}
