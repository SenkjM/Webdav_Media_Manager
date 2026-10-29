import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webdav_media_manager/services/rust_core_service.dart';

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

/// Persists the post-timeout start cooldown so it survives a process restart.
///
/// Android 12+ rejects a background `startForegroundService` for `dataSync`;
/// forgetting the window makes the service flap on the first task after a
/// restart, so the store is injected (and faked in tests).
abstract class DownloadKeepAliveSuppressionStore {
  Future<DateTime?> read();

  Future<void> write(DateTime? until);
}

/// Default store: one Rust KV entry.
class KvDownloadKeepAliveSuppressionStore
    implements DownloadKeepAliveSuppressionStore {
  static const String key = 'download_keepalive_suppress_until';

  @override
  Future<DateTime?> read() {
    final raw = RustCoreService.kvGet(key);
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      return Future.value(null);
    }
    final ms = int.tryParse(raw);
    if (ms == null) return Future.value(null);
    return Future.value(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  @override
  Future<void> write(DateTime? until) {
    if (until == null) {
      RustCoreService.kvDelete(key);
    } else {
      RustCoreService.kvSet(key, until.millisecondsSinceEpoch.toString());
    }
    return Future.value();
  }
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

  /// Cheap liveness probe for the native foreground service.
  ///
  /// A cached [DownloadKeepAlivePhase] goes stale whenever the service is torn
  /// down behind our back, so every start decision checks this first.
  Future<bool> isRunning();

  void bind({
    required void Function() onTimeout,
    required void Function(String error) onStartFailed,
    required void Function() onStopped,
  });
}

/// Keeps the download process in a dataSync foreground service while the
/// queue has work. Callers start it only from the foreground; [release] is
/// the ordered stop (stopForeground REMOVE, then stopSelf).
class DownloadKeepAlive {
  DownloadKeepAlive({
    DownloadKeepAliveBridge? bridge,
    DownloadKeepAliveSuppressionStore? suppression,
  }) : _injected = bridge,
       _suppression = suppression ?? KvDownloadKeepAliveSuppressionStore() {
    unawaited(_restoreSuppression());
  }

  /// After Android 15+ `onTimeout`, don't immediately start the FGS again.
  /// This is not a quota reset — it only avoids a tight restart loop.
  static const Duration timeoutCooldown = Duration(minutes: 30);

  final DownloadKeepAliveBridge? _injected;
  final DownloadKeepAliveSuppressionStore _suppression;
  DownloadKeepAliveBridge? _resolved;

  DownloadKeepAlivePhase phase = DownloadKeepAlivePhase.idle;
  String? lastStartError;
  DateTime? _suppressUntil;
  Future<void>? _tail;

  /// Fired after the native service stopped itself on the dataSync quota.
  void Function()? onTimeout;

  /// Fired whenever the native service goes away for any other reason, so the
  /// queue can re-decide whether it still needs an FGS.
  void Function()? onStopped;

  bool get isRunning => phase == DownloadKeepAlivePhase.running;

  /// True while a startForeground call is in flight or the FGS is up.
  bool get holdsOrStarting =>
      phase == DownloadKeepAlivePhase.starting ||
      phase == DownloadKeepAlivePhase.running ||
      phase == DownloadKeepAlivePhase.stopping;

  void suppressStartUntil(DateTime until) {
    final current = _suppressUntil;
    if (current != null && !until.isAfter(current)) return;
    _suppressUntil = until;
    unawaited(_persistSuppression(until));
  }

  Future<void> _restoreSuppression() async {
    try {
      final until = await _suppression.read();
      if (until == null) return;
      if (DateTime.now().isBefore(until)) {
        suppressStartUntil(until);
      } else {
        await _suppression.write(null);
      }
    } catch (e) {
      debugPrint('DownloadKeepAlive restore suppression failed: $e');
    }
  }

  Future<void> _persistSuppression(DateTime until) async {
    try {
      await _suppression.write(until);
    } catch (e) {
      debugPrint('DownloadKeepAlive persist suppression failed: $e');
    }
  }

  bool get _suppressed {
    final until = _suppressUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  DownloadKeepAliveBridge get _client {
    final existing = _resolved;
    if (existing != null) return existing;
    final created = _injected ?? MethodChannelDownloadKeepAliveBridge();
    created.bind(
      onTimeout: _handleTimeout,
      onStartFailed: _handleStartFailed,
      onStopped: _handleStopped,
    );
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
    if (phase == DownloadKeepAlivePhase.starting) return;
    if (phase == DownloadKeepAlivePhase.running) {
      // Never trust the cached phase alone: the service can be reclaimed
      // without us noticing, and a stale `running` turns every later
      // ensureRunning() into a no-op — downloads then run unprotected.
      if (await _client.isRunning()) return;
      phase = DownloadKeepAlivePhase.idle;
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
      if (result.ok) {
        // A concurrent native onTimeout may have written `idle` while this
        // call was in flight; the start result is still the truth about the
        // service that is now up.
        phase = DownloadKeepAlivePhase.running;
        lastStartError = null;
      } else if (phase == DownloadKeepAlivePhase.starting) {
        // A start reported as failed can still land after the FGS came up, in
        // which case a timeout already owns the phase — don't overwrite it.
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
    if (phase == DownloadKeepAlivePhase.idle) {
      phase = DownloadKeepAlivePhase.idle;
      return;
    }
    // `failedToStart` still asks the native side to stop: a start can be
    // reported as failed *after* the FGS came up, and leaving that one running
    // keeps a notification (and the dataSync quota) alive with nothing behind
    // it.
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

  /// Native side is gone. Only clear a phase that still claims liveness: a
  /// `stopping` phase belongs to an in-flight [release] and must not be
  /// clobbered, or `_release`'s `finally` would skip the idle reset.
  void _handleStopped() {
    if (phase == DownloadKeepAlivePhase.running ||
        phase == DownloadKeepAlivePhase.starting) {
      phase = DownloadKeepAlivePhase.idle;
    }
    debugPrint('DownloadKeepAlive onStopped; phase=${phase.name}');
    onStopped?.call();
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
    // whenComplete re-throws into the future it returns; leaving that one
    // unlistened turned a failed start into an unhandled async error. Swallow
    // the error on a derived future so the gate stays independent.
    unawaited(
      result
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(gate.complete),
    );
    return result;
  }
}

class MethodChannelDownloadKeepAliveBridge implements DownloadKeepAliveBridge {
  MethodChannelDownloadKeepAliveBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kDownloadKeepAliveChannel);

  final MethodChannel _channel;
  void Function()? _onTimeout;
  void Function(String error)? _onStartFailed;
  void Function()? _onStopped;
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
        case 'onStopped':
          _onStopped?.call();
        default:
          break;
      }
    });
  }

  @override
  void bind({
    required void Function() onTimeout,
    required void Function(String error) onStartFailed,
    required void Function() onStopped,
  }) {
    _onTimeout = onTimeout;
    _onStartFailed = onStartFailed;
    _onStopped = onStopped;
    _installHandler();
  }

  @override
  Future<bool> isRunning() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>('isRunning');
      if (raw is Map) return raw['running'] == true;
    } on MissingPluginException {
      // No native side (hot reload / tests): assume the cached phase is right
      // rather than restarting the service on every call.
      return true;
    } on PlatformException catch (e) {
      debugPrint('DownloadKeepAlive isRunning: $e');
      return true;
    }
    return true;
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
