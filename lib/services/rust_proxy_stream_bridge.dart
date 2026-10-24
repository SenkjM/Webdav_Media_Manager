// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';

import '../models/webdav_stream.dart';
import 'rust_core_service.dart';
import 'rust_proxy_bridge.dart';

/// P0.5 — Registers a Dart Range reader with the Rust local HTTP proxy via
/// `wdmm_proxy_register_stream`, returning a loopback [WebDavStreamSource].
///
/// Replaces the deleted Dart `LocalStreamBridge` (HttpServer) for the
/// MustProxy / crypt-wrapper playback path. **Not** a Dart HttpServer — the
/// proxy itself is the Rust `wdmm-proxy` singleton.
///
/// ## C ABI contract (core e236ece)
///
/// `wdmm_proxy_register_stream` stores a C function pointer + opaque
/// `user_data`. On each HTTP Range request, Rust's request handler
/// (`invoke_c_callback` in `wdmm-ffi/src/lib.rs`) calls the callback
/// **synchronously on a Tokio worker thread** and immediately consumes
/// `*out_buf` / `*out_len`:
///
/// ```c
/// int32_t cb(user_data, start, end, &out_buf, &out_len)  // runs on Tokio worker
/// // Rust reads out_buf the instant cb returns.
/// ```
///
/// ## The sync-vs-async gap (documented leftover)
///
/// Dart content decryption (`CryptDriver.openContentRange`) is **async**
/// (`Future`/`Stream`). Dart's `NativeCallable` has two modes:
///
/// - `.listener` — posts the call onto the Dart isolate's event loop and
///   returns to native immediately (fire-and-forget). The Dart handler runs
///   later, so `*out_buf` is still null when Rust reads it → IO error.
/// - `.isolateLocal` — runs the Dart function synchronously on the calling
///   thread, but only when that thread *is* the owning Dart isolate. A Tokio
///   worker is not the Dart isolate, so invoking it there is undefined.
///
/// Neither can satisfy "synchronous C callback on a foreign thread that needs
/// async Dart work" without a native blocking primitive (semaphore / condvar)
/// the C side waits on until the Dart isolate signals completion. The current
/// Rust ABI does not export such a primitive, so a **fully-working** sync
/// delivery path is a follow-up (see Leftovers below).
///
/// ## What this bridge delivers in P0.5
///
/// - Full FFI wiring: proxy start, symbol resolution, `wdmm_proxy_register_stream`
///   registration, JSON `{token,path_template,port}` parse, loopback URL
///   composition, and lifecycle (`unregister` / `unregisterAll`).
/// - Registration is real: a `NativeCallable.listener` is created and passed
///   to the Rust proxy; the token map is maintained; the loopback URL is
///   returned to the player exactly like `registerFile`.
/// - The range dispatch is structured via a [ReceivePort] so that, once a
///   Rust-side reply/blocking primitive lands (or a native semaphore is
///   added), only the dispatch body changes — the registration + URL path
///   stays.
///
/// Until that primitive lands, byte delivery on a Range request will surface
/// as a proxy IO error rather than a hang; the player falls back to its own
/// error handling. This is the "minimal working bridge" the brief permits,
/// with the async-sync gap recorded as a leftover.
///
/// ## Leftovers
///
/// - **Sync delivery** — needs either a Rust-side blocking/reply FFI (e.g.
///   `wdmm_proxy_stream_set_result` + a semaphore the C callback waits on)
///   or a small native (C) shim that blocks the Tokio worker until the Dart
///   isolate signals. Until then the listener handler can't fill `*out_buf`
///   before Rust consumes it.
/// - **Renew callback** — `proxyRenewStreamCallback` is wired in
///   `RustCoreService` but not yet called from here (crypt key rotation is
///   still Dart-only); wire when Rust crypt lands.
///
/// Do **NOT** revive `LocalStreamBridge.dart` / `stream_bridge.dart`.
class RustProxyStreamBridge {
  RustProxyStreamBridge._();

  /// token → active registration.
  static final Map<String, _StreamRegistration> _regs = {};

  /// Indicates whether the register_stream FFI symbols are present in the
  /// loaded `libwdmm_ffi.so`. Checked before registration so callers get a
  /// diagnostic error instead of a silent null.
  static bool streamSymbolsAvailable() {
    // Probe via a 1-byte alloc. proxyStreamAllocBuf returns nullptr both when
    // the symbols are absent (function pointer null) and when len == 0 — so
    // probe with len == 1 and free immediately.
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
  /// the requested plaintext bytes. It may call `CryptDriver.openContentRange`
  /// internally.
  ///
  /// Returns null if the proxy cannot be started or `register_stream` returns
  /// an error. Throws a [StateError] naming the missing FFI + expected core
  /// SHA (e236ece) if the stream symbols are absent from the loaded .so.
  ///
  /// See the class doc for the sync-delivery limitation (P0.5 leftover).
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

    // 2. Verify the register_stream FFI symbols are present.
    if (!streamSymbolsAvailable()) {
      throw StateError(
        'wdmm_proxy_register_stream FFI symbols missing. '
        'Ensure libwdmm_ffi.so is built from core SHA e236ece '
        '(feat/proxy-hls-ffmpeg P0.5), not 4a37aa4.',
      );
    }

    // 3. Build the NativeCallable. Use the void-returning listener typedef so
    //    that NativeCallable.listener type-checks. We then cast the native
    //    function pointer to the Int32-returning ABI before passing to
    //    proxyRegisterStream (the Rust side reads the return value, but for
    //    the listener path it always gets -1 / the trampoline default).
    final callable =
        ffi.NativeCallable<WdmmProxyRangeCallbackListenerNative>.listener(
      _nativeRangeCallbackVoid,
    );
    final callbackPtr = callable.nativeFunction
        .cast<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>();

    // 4. Register with the Rust proxy.
    final result = RustCoreService.proxyRegisterStream(
      size: size,
      name: name,
      callback: callbackPtr,
      userData: ffi.nullptr, // we key registrations by token, not by user_data
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
      debugPrint('[RustProxyStreamBridge] register JSON decode error: $e / $result');
      return null;
    }

    final token = json['token'] as String? ?? '';
    final pathTemplate = json['path_template'] as String? ?? '';
    final port = json['port'] as int? ?? proxyPort;
    final uri = 'http://127.0.0.1:$port$pathTemplate';

    // 6. Keep the registration alive + callable for the proxy lifetime.
    _regs[token] = _StreamRegistration(
      rangeReader: rangeReader,
      callable: callable,
      token: token,
    );

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

  // ── Native Range callback (dispatched by NativeCallable.listener) ─────────
  //
  // Runs on the Dart isolate event loop when the Rust proxy receives a Range
  // request. We look up the active registration and run rangeReader.
  //
  // IMPORTANT (leftover): the Rust ABI reads *out_buf synchronously right after
  // the C callback returns (see invoke_c_callback in wdmm-ffi/src/lib.rs).
  // NativeCallable.listener returns to native immediately and schedules this
  // Dart handler later, so *out_buf is still null when Rust consumes it.
  //
  // The handler below therefore cannot satisfy the current sync contract; it
  // runs the rangeReader and discards the result. A working delivery path
  // requires a Rust-side reply/blocking primitive (see class Doc / Leftovers).
  //
  // We use the global "most recent in-flight token" to locate the registration
  // because user_data is nullptr (Dart object pointers must not cross FFI).
  // Rust serialises Range calls per token, so there is at most one in-flight
  // request per stream at a time.

  static void _nativeRangeCallbackVoid(
    ffi.Pointer<ffi.Void> userData,
    int start,
    int end,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>> outBuf,
    ffi.Pointer<ffi.Size> outLen,
  ) {
    final reg = _currentInFlight;
    if (reg == null) return;
    // Fire async work — bytes cannot be delivered synchronously from a
    // .listener handler (see class doc / P0.5 leftover).
    _runRangeAsync(reg, start, end).catchError((Object e) {
      debugPrint('[RustProxyStreamBridge] rangeReader error: $e');
    });
  }

  static Future<void> _runRangeAsync(
    _StreamRegistration reg,
    int start,
    int end,
  ) async {
    final bytes = await reg.rangeReader(start, end);
    // We successfully fetched the bytes, but the C callback already returned
    // (listener is async). A future Rust reply primitive would take this
    // `bytes` and a token, allocate a Rust-heap buffer, and signal the
    // blocked Tokio worker. For now we drop them — documented leftover.
    if (kDebugMode) {
      debugPrint(
        '[RustProxyStreamBridge] fetched ${bytes.length}B for '
        '[$start,$end] (dropped — sync delivery is a P0.5 leftover)',
      );
    }
  }

  /// The registration whose Range request is currently being served. Set when
  /// a player opens a stream; cleared on unregister. Single-slot because Rust
  /// serialises Range calls per token and the typical playback session has one
  /// active stream at a time. (If multiple concurrent streams are needed later,
  /// this becomes a token→slot map keyed by a user_data id passed from Rust.)
  static _StreamRegistration? _currentInFlight;

  /// Mark [token] as the in-flight registration for callback dispatch.
  /// Called by the player layer when it begins playback of a proxy URL.
  static void setInFlight(String token) {
    _currentInFlight = _regs[token];
  }

  /// Clear the in-flight registration (e.g. on stop).
  static void clearInFlight() {
    _currentInFlight = null;
  }
}

/// One active stream registration: the Dart range reader + its NativeCallable.
class _StreamRegistration {
  _StreamRegistration({
    required this.rangeReader,
    required this.callable,
    required this.token,
  });

  final Future<List<int>> Function(int start, int end) rangeReader;
  final ffi.NativeCallable<WdmmProxyRangeCallbackListenerNative> callable;
  final String token;
}
