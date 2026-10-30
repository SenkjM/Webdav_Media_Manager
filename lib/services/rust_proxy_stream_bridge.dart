// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';
import 'rust_proxy_bridge.dart';

// ── NativeCallable typedef (void return) ─────────────────────────────────────
//
// Dart 3.13.4 (and earlier 3.x) requires the Dart callback passed to
// [NativeCallable.listener] to be void-returning. The native thunk synthesised
// for a *void* listener does not explicitly set the return register; on
// ARM64 / x86_64 the register contains the return value of the last internal
// call (`dart_post_message` → 0 or 1 on success). Rust reads this as an
// `int32_t` — both 0 and 1 are non-negative, so Rust takes the async path
// (result ≥ 0 && *out_buf == null → park handler, wait for set_result). The
// function pointer is cast to [WdmmProxyRangeCallbackNative] (Int32 return)
// before being registered with Rust.
//
// This is the only viable approach: listener + non-void callback fails with
// `must_return_void`; a synchronous isolateLocal callable would deadlock
// Tokio; adding a C wrapper would require native build changes.
typedef _WdmmProxyRangeCallbackVoidNative = ffi.Void Function(
  ffi.Pointer<ffi.Void>, // user_data  (ignored; state captured in closure)
  ffi.Int64,             // start
  ffi.Int64,             // end
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>, // out_buf  (async path: leave null)
  ffi.Pointer<ffi.Size>,               // out_len  (async path: ignore)
  ffi.Uint64,            // request_id (pass to set_result)
);

/// Active stream registration kept alive while the Rust proxy serves requests.
class _StreamReg {
  _StreamReg({required this.token, required this.callable});

  final String token;

  /// The [NativeCallable.listener] is invocable from any thread (Rust Tokio).
  /// Held so we can call [ffi.NativeCallable.close] on [unregister].
  final ffi.NativeCallable<_WdmmProxyRangeCallbackVoidNative> callable;
}

/// Routes Dart-driver Range reads through the Rust local HTTP proxy.
///
/// Each [expose] call registers a stream with `wdmm_proxy_register_stream` and
/// returns a `http://{host}:{port}{path}` URI, where `host` and `port` come
/// from the Core FFI JSON response — the actual address the proxy is bound on.
///
/// For each Range request Rust invokes the registered callback from a Tokio
/// worker thread. The callable is created with [NativeCallable.listener]:
/// the native thunk returns immediately (async-path signal — return register is
/// 0 or 1 from dart_post_message, always non-negative, so Rust parks the
/// handler). The Dart callback is then dispatched on this isolate's event queue,
/// calls [readRange], allocates a Rust-heap buffer via
/// `wdmm_proxy_stream_alloc_buf`, copies bytes, and wakes the handler with
/// `wdmm_proxy_stream_set_result`. Rust waits up to 30 s
/// (`PROXY_STREAM_TIMEOUT_SECS`).
///
/// ## Bind modes
/// Pass [expose.bindMode] = `'lan_if:<ip>'` for DLNA cast so the proxy binds
/// on a LAN interface reachable by the renderer. The returned URI host is the
/// address Core actually bound on — Dart never assembles a URL host itself.
/// Default `'loopback'` is for on-device playback only.
class RustProxyStreamBridge {
  RustProxyStreamBridge._();

  /// token → live registration.
  static final Map<String, _StreamReg> _regs = {};

  /// Register a MustProxy / LocalStream with the Rust proxy and return its URL.
  ///
  /// - [size]      — known content length in bytes; `0` if unknown.
  /// - [name]      — filename hint for Content-Type (e.g. `"movie.mp4"`).
  /// - [accountId] / [remotePath] — used for debug logging only.
  /// - [readRange] — called with `(start, end)` for each Range request.
  ///   `end` is inclusive; `-1` means read to EOF. Returns the raw bytes.
  /// - [bindMode]  — Rust proxy bind mode string. `'loopback'` (default) for
  ///   on-device playback; `'lan_if:<ip>'` binds a LAN interface for DLNA cast.
  ///   The returned URI host is read from the Core JSON response.
  ///
  /// Returns `({Uri uri, String token})`. Pass [token] to [unregister] when
  /// playback ends to release the Rust-side slot.
  ///
  /// Throws [StateError] if the proxy cannot be started or stream registration
  /// fails.
  static Future<({Uri uri, String token})> expose({
    required int size,
    required String name,
    required String accountId,
    required String remotePath,
    required FutureOr<List<int>> Function(int start, int end) readRange,
    String bindMode = 'loopback',
  }) async {
    // Ensure the proxy singleton is running with the requested bind mode.
    final proxyPort = RustProxyBridge.start(bindMode: bindMode);
    if (proxyPort == null) {
      throw StateError(
        '[RustProxyStreamBridge] proxy could not be started '
        '',
      );
    }

    // Create a NativeCallable with a void-returning native typedef, then cast
    // its function pointer to the int32-returning type Rust expects. See the
    // _WdmmProxyRangeCallbackVoidNative comment for the full ABI rationale.
    final callable =
        ffi.NativeCallable<_WdmmProxyRangeCallbackVoidNative>.listener(
      (ffi.Pointer<ffi.Void> userData, int start, int end,
          ffi.Pointer<ffi.Pointer<ffi.Uint8>> outBuf,
          ffi.Pointer<ffi.Size> outLen, int requestId) {
        // Runs async on the Dart isolate event loop — must not block.
        unawaited(_deliverRange(readRange, start, end, requestId));
      },
    );

    // Cast to the int32-returning type before passing to Rust.
    final cbPtr = callable.nativeFunction
        .cast<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>();

    final result = RustCoreService.proxyRegisterStream(
      size: size,
      name: name,
      cb: cbPtr,
      userData: ffi.nullptr,
    );

    if (result == null || result.startsWith('error:')) {
      callable.close();
      throw StateError(
        '[RustProxyStreamBridge] wdmm_proxy_register_stream failed '
        'for "$remotePath": $result',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(result) as Map<String, dynamic>;
    } catch (e) {
      callable.close();
      throw StateError(
        '[RustProxyStreamBridge] register_stream returned bad JSON: $result ($e)',
      );
    }
    final token = json['token'] as String?;
    final pathTemplate = json['path_template'] as String?;
    // host is the IP Core is actually bound on — never assembled in Dart.
    final host = (json['host'] as String?) ?? '127.0.0.1';
    final port = json['port'] as int?;
    if (token == null || pathTemplate == null || port == null) {
      callable.close();
      throw StateError(
        '[RustProxyStreamBridge] register_stream missing fields: $result',
      );
    }

    _regs[token] = _StreamReg(token: token, callable: callable);
    debugPrint(
      '[RustProxyStreamBridge] registered $token ($remotePath) '
      'size=$size host=$host port=$port',
    );

    final uri = Uri.parse('http://$host:$port$pathTemplate');
    return (uri: uri, token: token);
  }

  /// Replace the range callback for [token] (e.g. after a credential refresh).
  ///
  /// No-op if [token] is not registered.
  static void renewCallback(
    String token,
    FutureOr<List<int>> Function(int start, int end) newReadRange,
  ) {
    final reg = _regs[token];
    if (reg == null) return;

    final newCallable =
        ffi.NativeCallable<_WdmmProxyRangeCallbackVoidNative>.listener(
      (ffi.Pointer<ffi.Void> userData, int start, int end,
          ffi.Pointer<ffi.Pointer<ffi.Uint8>> outBuf,
          ffi.Pointer<ffi.Size> outLen, int requestId) {
        unawaited(_deliverRange(newReadRange, start, end, requestId));
      },
    );

    final cbPtr = newCallable.nativeFunction
        .cast<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>();

    final result = RustCoreService.proxyRenewStreamCallback(
      token,
      cbPtr,
      ffi.nullptr,
    );
    if (result == null || result.startsWith('error:')) {
      newCallable.close();
      debugPrint(
        '[RustProxyStreamBridge] renewCallback failed for $token: $result',
      );
      return;
    }

    // Close the old callable only after Rust has swapped to the new one.
    reg.callable.close();
    _regs[token] = _StreamReg(token: token, callable: newCallable);
    debugPrint('[RustProxyStreamBridge] callback renewed for $token');
  }

  /// Unregister [token] and close its [ffi.NativeCallable].
  ///
  /// No-op if [token] is unknown. Safe to call from any thread.
  static void unregister(String token) {
    final reg = _regs.remove(token);
    if (reg == null) return;
    RustCoreService.proxyUnregister(token);
    reg.callable.close();
    debugPrint('[RustProxyStreamBridge] unregistered $token');
  }

  /// Unregister and close all active stream registrations.
  ///
  /// Prefer [unregister] during normal operation; use [disposeAll] only when
  /// the owning service is being torn down.
  static void disposeAll() {
    for (final reg in _regs.values) {
      RustCoreService.proxyUnregister(reg.token);
      reg.callable.close();
    }
    _regs.clear();
    debugPrint('[RustProxyStreamBridge] all stream registrations disposed');
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Async Range delivery for each incoming Rust proxy request.
  ///
  /// On success, buf ownership transfers to Rust via [proxyStreamSetResult];
  /// do NOT free it. On any error, signal negative status with a null buffer.
  static Future<void> _deliverRange(
    FutureOr<List<int>> Function(int, int) readRange,
    int start,
    int end,
    int requestId,
  ) async {
    try {
      final data = Uint8List.fromList(await readRange(start, end));
      if (data.isEmpty) {
        // Empty range / EOF — signal success with zero bytes.
        RustCoreService.proxyStreamSetResult(requestId, ffi.nullptr, 0, 0);
        return;
      }
      final buf = RustCoreService.proxyStreamAllocBuf(data.length);
      if (buf == ffi.nullptr) {
        debugPrint(
          '[RustProxyStreamBridge] alloc_buf(${data.length}) returned null',
        );
        RustCoreService.proxyStreamSetResult(requestId, ffi.nullptr, 0, -1);
        return;
      }
      // Copy Dart bytes into the Rust-heap buffer, then transfer ownership.
      buf.asTypedList(data.length).setAll(0, data);
      RustCoreService.proxyStreamSetResult(requestId, buf, data.length, 0);
    } catch (e, st) {
      debugPrint('[RustProxyStreamBridge] _deliverRange error: $e\n$st');
      RustCoreService.proxyStreamSetResult(requestId, ffi.nullptr, 0, -1);
    }
  }
}
