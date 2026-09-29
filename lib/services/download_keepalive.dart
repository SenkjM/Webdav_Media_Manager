import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Method channel shared with `DownloadKeepAliveService`.
const String kDownloadKeepAliveChannel =
    'com.senkjm.media_manager/download_keepalive';

/// idle → starting → running → stopping, plus a failed start.
enum DownloadKeepAlivePhase { idle, starting, running, stopping, failedToStart }

class KeepAliveStartResult {
  const KeepAliveStartResult({required this.ok, this.error});

  final bool ok;
  final String? error;

  static const KeepAliveStartResult unsupported = KeepAliveStartResult(
    ok: false,
    error: 'unsupported',
  );
}

/// Native side of the download dataSync foreground service.
///
/// The service posts one minimal notification and does not own progress
/// updates. A native-owned 2001 fallback is not part of this bridge.
abstract class DownloadKeepAliveBridge {
  Future<KeepAliveStartResult> start({
    required String title,
    required int notificationId,
    required String channelId,
  });

  Future<void> stop();

  Future<Map<String, Object?>> diagnostics();

  void bind({
    required void Function() onTimeout,
    required void Function(String error) onStartFailed,
  });
}

/// Keeps the download process in a dataSync foreground service while the
/// queue has work. Callers start it only from the foreground; [release] is
/// the ordered stop (stopForeground REMOVE, then stopSelf).
class DownloadKeepAlive {
  DownloadKeepAlive({DownloadKeepAliveBridge? bridge}) : _injected = bridge;

  /// After Android 15+ `onTimeout`, don't immediately start the FGS again.
  /// This is not a quota reset — it only avoids a tight restart loop.
  static const Duration timeoutCooldown = Duration(minutes: 30);

  final DownloadKeepAliveBridge? _injected;
  DownloadKeepAliveBridge? _resolved;

  DownloadKeepAlivePhase phase = DownloadKeepAlivePhase.idle;
  String? lastStartError;
  DateTime? _suppressUntil;
  Future<void>? _tail;

  /// Fired after the native service has already stopped itself.
  void Function()? onTimeout;

  bool get isRunning => phase == DownloadKeepAlivePhase.running;

  /// True while a startForeground call is in flight or the FGS is up.
  bool get holdsOrStarting =>
      phase == DownloadKeepAlivePhase.starting ||
      phase == DownloadKeepAlivePhase.running ||
      phase == DownloadKeepAlivePhase.stopping;

  void suppressStartUntil(DateTime until) {
    final current = _suppressUntil;
    if (current == null || until.isAfter(current)) _suppressUntil = until;
  }

  bool get _suppressed {
    final until = _suppressUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  DownloadKeepAliveBridge get _client {
    final existing = _resolved;
    if (existing != null) return existing;
    final created = _injected ?? MethodChannelDownloadKeepAliveBridge();
    created.bind(onTimeout: _handleTimeout, onStartFailed: _handleStartFailed);
    _resolved = created;
    return created;
  }

  /// Paused / hidden / detached count as background. `inactive` stays
  /// foreground so a transient system UI doesn't tighten the retry cap.
  static bool lifecycleIsBackground() {
    try {
      switch (WidgetsBinding.instance.lifecycleState) {
        case AppLifecycleState.paused:
        case AppLifecycleState.hidden:
        case AppLifecycleState.detached:
          return true;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureRunning({
    required String title,
    required int notificationId,
    required String channelId,
    bool Function()? isForeground,
  }) {
    return _enqueue(
      () => _ensure(
        title: title,
        notificationId: notificationId,
        channelId: channelId,
        isForeground: isForeground,
      ),
    );
  }

  Future<void> release() => _enqueue(_release);

  Future<Map<String, Object?>> diagnostics() async {
    try {
      final native = await _client.diagnostics();
      return {
        ...native,
        'phase': phase.name,
        'lastStartError': lastStartError,
        'suppressedUntil': _suppressUntil?.toIso8601String(),
      };
    } catch (e) {
      return {
        'phase': phase.name,
        'lastStartError': lastStartError,
        'error': e.toString(),
      };
    }
  }

  Future<void> _ensure({
    required String title,
    required int notificationId,
    required String channelId,
    bool Function()? isForeground,
  }) async {
    if (phase == DownloadKeepAlivePhase.running ||
        phase == DownloadKeepAlivePhase.starting) {
      return;
    }
    if (_suppressed) return;
    final foreground = isForeground?.call() ?? !lifecycleIsBackground();
    if (!foreground) return;
    phase = DownloadKeepAlivePhase.starting;
    try {
      final result = await _client.start(
        title: title,
        notificationId: notificationId,
        channelId: channelId,
      );
      if (phase != DownloadKeepAlivePhase.starting) return;
      if (result.ok) {
        phase = DownloadKeepAlivePhase.running;
        lastStartError = null;
      } else {
        phase = DownloadKeepAlivePhase.failedToStart;
        lastStartError = result.error;
        debugPrint('DownloadKeepAlive start failed: ${result.error}');
      }
    } catch (e) {
      if (phase == DownloadKeepAlivePhase.starting) {
        phase = DownloadKeepAlivePhase.failedToStart;
      }
      lastStartError = e.toString();
      debugPrint('DownloadKeepAlive start failed: $e');
    }
  }

  Future<void> _release() async {
    if (phase == DownloadKeepAlivePhase.idle ||
        phase == DownloadKeepAlivePhase.failedToStart) {
      phase = DownloadKeepAlivePhase.idle;
      return;
    }
    phase = DownloadKeepAlivePhase.stopping;
    try {
      await _client.stop();
    } catch (e) {
      debugPrint('DownloadKeepAlive stop failed: $e');
    } finally {
      if (phase == DownloadKeepAlivePhase.stopping) {
        phase = DownloadKeepAlivePhase.idle;
      }
    }
  }

  void _handleTimeout() {
    phase = DownloadKeepAlivePhase.idle;
    final until = DateTime.now().add(timeoutCooldown);
    suppressStartUntil(until);
    debugPrint('DownloadKeepAlive onTimeout; suppress until $until');
    onTimeout?.call();
  }

  void _handleStartFailed(String error) {
    lastStartError = error;
    if (phase == DownloadKeepAlivePhase.starting ||
        phase == DownloadKeepAlivePhase.running) {
      phase = DownloadKeepAlivePhase.failedToStart;
    }
    debugPrint('DownloadKeepAlive onStartFailed: $error');
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final previous = _tail ?? Future<void>.value();
    final gate = Completer<void>();
    _tail = gate.future;
    final result = previous.catchError((Object _) {}).then((_) => action());
    result.whenComplete(gate.complete);
    return result;
  }
}

class MethodChannelDownloadKeepAliveBridge implements DownloadKeepAliveBridge {
  MethodChannelDownloadKeepAliveBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kDownloadKeepAliveChannel);

  final MethodChannel _channel;
  void Function()? _onTimeout;
  void Function(String error)? _onStartFailed;
  bool _handlerInstalled = false;

  void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTimeout':
          _onTimeout?.call();
        case 'onStartFailed':
          final args = call.arguments;
          final error = args is Map ? '${args['error']}' : '$args';
          _onStartFailed?.call(error);
        default:
          break;
      }
    });
  }

  @override
  void bind({
    required void Function() onTimeout,
    required void Function(String error) onStartFailed,
  }) {
    _onTimeout = onTimeout;
    _onStartFailed = onStartFailed;
    _installHandler();
  }

  @override
  Future<KeepAliveStartResult> start({
    required String title,
    required int notificationId,
    required String channelId,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return KeepAliveStartResult.unsupported;
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('start', {
        'title': title,
        'notificationId': notificationId,
        'channelId': channelId,
      });
      if (raw is Map && raw['ok'] == false) {
        return KeepAliveStartResult(ok: false, error: '${raw['error']}');
      }
      return const KeepAliveStartResult(ok: true);
    } on MissingPluginException catch (e) {
      return KeepAliveStartResult(ok: false, error: e.message);
    } on PlatformException catch (e) {
      return KeepAliveStartResult(ok: false, error: e.message ?? e.code);
    }
  }

  @override
  Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Hot reload / tests without the native plugin.
    } on PlatformException catch (e) {
      debugPrint('DownloadKeepAlive stop: $e');
    }
  }

  @override
  Future<Map<String, Object?>> diagnostics() async {
    if (kIsWeb || !Platform.isAndroid) return const {};
    try {
      final raw = await _channel.invokeMethod<dynamic>('diagnostics');
      if (raw is Map) {
        final out = <String, Object?>{};
        raw.forEach((key, value) => out['$key'] = value);
        return out;
      }
    } on MissingPluginException {
      return const {};
    } on PlatformException catch (e) {
      return {'error': e.message ?? e.code};
    }
    return const {};
  }
}
