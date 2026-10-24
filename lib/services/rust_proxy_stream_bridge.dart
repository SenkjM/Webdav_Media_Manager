// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';

import '../models/webdav_stream.dart';
import 'rust_core_service.dart';
import 'rust_proxy_bridge.dart';

/// P0.5+ — Registers a Dart Range reader with the Rust local HTTP proxy via
/// `wdmm_proxy_register_stream`, delivering real bytes via the async reply
/// channel (`wdmm_proxy_stream_set_result`).
///
/// Replaces the deleted Dart `LocalStreamBridge` (HttpServer) for the
/// MustProxy / crypt-wrapper playback path. **Not** a Dart HttpServer — the
/// proxy itself is the Rust `wdmm-proxy` singleton.
///
/// ## How it works (core b08a5ef)
///
/// Each registration creates its own `NativeCallable.listener` whose closure
/// captures the specific [rangeReader]. When the Rust proxy receives an HTTP
/// Range request it fires the listener on the Dart event loop:
///
/// ```
/// Rust proxy (Tokio worker)
///   → calls WdmmProxyRangeCallback(user_data, start, end, &out_buf, &out_len, request_id)
///   → cb returns 0 + out_buf=null  (async intent)
///   → parks the worker thread (up to 30 s)
///
/// Dart event loop (later)
///   → listener fires: _dispatchAsync(rangeReader, start, end, requestId)
///   → await rangeReader(start, end)
///   → proxyStreamAllocBuf(len) + copy bytes
///   → proxyStreamSetResult(requestId, buf, len, 0)   // unparks worker
///   → on error: proxyStreamSetResult(requestId, nullptr, 0, -1)
/// ```
///
/// The Tokio worker returns the bytes as an HTTP response chunk. No bytes are
/// dropped.
///
/// ## Concurrent streams
///
/// Multiple concurrent registrations are supported. Each registration has its
/// own `NativeCallable` closure, so `rangeReader` dispatch is unambiguous.
/// The `request_id` parameter uniquely identifies each Range invocation across
/// all registrations, so concurrent Range requests cannot interfere.
///
/// ## Do NOT revive
/// - `LocalStreamBridge.dart` / `stream_bridge.dart`
/// - Any Dart HttpServer bridge
class RustProxyStreamBridge {
  RustProxyStreamBridge._();

  /// token → active registration.
  static final Map<String, _StreamRegistration> _regs = {};

  /// Returns true if the stream FFI symbols (register, alloc, set_result) are
  /// all present in the loaded `libwdmm_ffi.so`.
  static bool streamSymbolsAvailable() {
    // Probe via a 1-byte alloc; proxyStreamAllocBuf returns nullptr when the
    // symbol is absent or when len == 0.
    final buf = RustCoreService.proxyStreamAllocBuf(1);
    if (buf == ffi.nullptr) return false;
    RustCoreService.proxyStreamFreeBuf(buf, 1);
    return true;
  }

  /// Register [rangeReader] with the Rust proxy and return a loopback
  /// [WebDavStreamSource] whose `uri` is `http://127.0.0.1:{port}{path_template}`.
  ///
  /// [size] is the plaintext file size in bytes (0 if unknown).
  /// [name] is optional, used for Content-Type guessing (e.g. `"movie.mkv"`).
  /// [rangeReader] receives inclusive `(start, end)` byte offsets and returns
  /// the requested plaintext bytes. It may call `CryptDriver.openContentRange`.
  ///
  /// Returns null if the proxy cannot be started or `register_stream` returns
  /// an error. Throws a [StateError] if the stream FFI symbols are absent.
  static Future<WebDavStreamSource?> register({
    required int size,
    String? name,
    required Future<List<int>> Function(int start, int end) rangeReader,
    String remotePath = '',
    String accountId = '',
    StreamKind kind = StreamKind.video,
  }) async {
    // 1. Ensure the process-global proxy is started (idempotent).
    final proxyPort = RustProxyBridge.start();
    if (proxyPort == null) {
      debugPrint('[RustProxyStreamBridge] proxy start failed');
      return null;
    }

    // 2. Verify the stream FFI symbols are present.
    if (!streamSymbolsAvailable()) {
      throw StateError(
        'wdmm_proxy_register_stream / wdmm_proxy_stream_set_result FFI '
        'symbols missing. Ensure libwdmm_ffi.so is built from core b08a5ef '
        '(sync-reply commit on feat/proxy-hls-ffmpeg).',
      );
    }

    // 3. Build a per-registration NativeCallable whose closure captures
    //    [rangeReader]. The listener callback returns to native immediately and
    //    schedules the async work (rangeReader → set_result).
    final callable =
        ffi.NativeCallable<WdmmProxyRangeCallbackListenerNative>.listener(
      (
        ffi.Pointer<ffi.Void> userData,
        int start,
        int end,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> outBuf,
        ffi.Pointer<ffi.Size> outLen,
        int requestId,
      ) {
        _dispatchAsync(rangeReader, start, end, requestId);
      },
    );
    final callbackPtr = callable.nativeFunction
        .cast<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>();

    // 4. Register with the Rust proxy.
    final result = RustCoreService.proxyRegisterStream(
      size: size,
      name: name,
      callback: callbackPtr,
      userData: ffi.nullptr,
    );

    if (result == null || result.startsWith('error:')) {
      callable.close();
      debugPrint('[RustProxyStreamBridge] register_stream failed: $result');
      return null;
    }

    // 5. Parse {token, path_template, port} and compose the loopback URL.
    late Map<String, dynamic> json;
    try {
      json = jsonDecode(result) as Map<String, dynamic>;
    } catch (e) {
      callable.close();
      debugPrint('[RustProxyStreamBridge] JSON decode error: $e / $result');
      return null;
    }

    final token = json['token'] as String? ?? '';
    final pathTemplate = json['path_template'] as String? ?? '';
    final port = json['port'] as int? ?? proxyPort;
    final uri = 'http://127.0.0.1:$port$pathTemplate';

    _regs[token] = _StreamRegistration(callable: callable, token: token);

    debugPrint('[RustProxyStreamBridge] registered token=$token uri=$uri');
    return WebDavStreamSource(
      uri: uri,
      headers: const {},
      name: name ?? '',
      remotePath: remotePath,
      accountId: accountId,
      kind: kind,
    );
  }

  // ── Range dispatch ─────────────────────────────────────────────────────────

  /// Fire-and-forget: schedule the async range read + set_result reply.
  static void _dispatchAsync(
    Future<List<int>> Function(int, int) rangeReader,
    int start,
    int end,
    int requestId,
  ) {
    _runRange(rangeReader, start, end, requestId).catchError((Object e) {
      debugPrint('[RustProxyStreamBridge] _dispatchAsync error (req=$requestId): $e');
    });
  }

  static Future<void> _runRange(
    Future<List<int>> Function(int, int) rangeReader,
    int start,
    int end,
    int requestId,
  ) async {
    try {
      final bytes = await rangeReader(start, end);
      if (bytes.isEmpty) {
        debugPrint(
          '[RustProxyStreamBridge] rangeReader returned empty for '
          'req=$requestId [$start,$end] — signalling error',
        );
        RustCoreService.proxyStreamSetResult(
            requestId, ffi.nullptr.cast(), 0, -1);
        return;
      }

      // Allocate a Rust-heap buffer and copy bytes into it.
      final buf = RustCoreService.proxyStreamAllocBuf(bytes.length);
      if (buf == ffi.nullptr) {
        debugPrint(
          '[RustProxyStreamBridge] alloc_buf returned null for '
          '${bytes.length}B req=$requestId',
        );
        RustCoreService.proxyStreamSetResult(
            requestId, ffi.nullptr.cast(), 0, -1);
        return;
      }

      // Zero-copy if bytes is already a Uint8List; one copy otherwise.
      final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      buf.cast<ffi.Uint8>().asTypedList(bytes.length).setAll(0, u8);

      RustCoreService.proxyStreamSetResult(requestId, buf, bytes.length, 0);
      if (kDebugMode) {
        debugPrint(
          '[RustProxyStreamBridge] set_result ${bytes.length}B '
          'req=$requestId [$start,$end]',
        );
      }
    } catch (e, st) {
      debugPrint(
        '[RustProxyStreamBridge] rangeReader error req=$requestId: $e\n$st',
      );
      RustCoreService.proxyStreamSetResult(
          requestId, ffi.nullptr.cast(), 0, -1);
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Unregister a single stream token and close its NativeCallable.
  static void unregister(String token) {
    final reg = _regs.remove(token);
    if (reg == null) return;
    reg.callable.close();
    RustCoreService.proxyUnregister(token);
    debugPrint('[RustProxyStreamBridge] unregistered token=$token');
  }

  /// Unregister every active stream registration. Call on player stop / dispose.
  static void unregisterAll() {
    for (final reg in _regs.values) {
      reg.callable.close();
      RustCoreService.proxyUnregister(reg.token);
    }
    _regs.clear();
    debugPrint('[RustProxyStreamBridge] unregistered all');
  }
}

/// One active stream registration: the per-registration NativeCallable + token.
class _StreamRegistration {
  _StreamRegistration({required this.callable, required this.token});

  final ffi.NativeCallable<WdmmProxyRangeCallbackListenerNative> callable;
  final String token;
}
