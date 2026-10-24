// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 11 — Rust local HTTP proxy bridge (kRustProxyEnabled = true).
///
/// Thin wrappers for the `wdmm_proxy_*` FFI exports. Gated by [kRustProxyEnabled].
///
/// ## Purpose
/// The Rust proxy (`wdmm-proxy`) serves local files over HTTP so that DLNA
/// renderers, the system media player, and other HTTP clients can reach cached
/// media without direct filesystem access.
///
/// ## Round 12.1 cutover status (updated P0.5 — core e236ece)
/// - [kRustProxyEnabled] is `true` (device smoke passed in Round 10/11).
/// - DLNA cast path cut over to Rust FFI in Round 12: `RustDlnaCastService`
///   uses `wdmm_proxy_register_hls`.
/// - `LocalStreamBridge` (Dart HTTP proxy for MustProxy/crypt) **deleted** in
///   R12.1. P0.5 restores MustProxy playback via `wdmm_proxy_register_stream`
///   (core SHA e236ece): `cloud_drive_service.resolveStreamSource` now routes
///   `ContentDeliveryKind.localStream` items through
///   [RustProxyStreamBridge] (see `rust_proxy_stream_bridge.dart`).
///   TODO(proxy-cutover): sync byte delivery is a leftover — the Rust callback
///   is synchronous on a Tokio worker; `NativeCallable.listener` posts to the
///   Dart isolate and returns before bytes are ready. A Rust-side reply/block
///   primitive (or a native semaphore shim) is needed for working playback.
/// - Settings → Developer / Rust Proxy panel drives start/stop/register for the
///   Rust proxy path (Settings section still present).
///
/// ## Serial invariant
/// The proxy is a process-global singleton — never create more than one instance.
class RustProxyBridge {
  RustProxyBridge._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start the local HTTP proxy on `127.0.0.1` at [port] (0 = OS-assigned).
  ///
  /// Returns the bound port as an integer on success, or null on failure /
  /// when [kRustProxyEnabled] is false.
  ///
  /// Idempotent — if the proxy is already running, returns its current port.
  static int? start({int port = 0}) {
    if (!kRustProxyEnabled) return null;
    final result = RustCoreService.proxyStart(port: port);
    if (result == null || result.startsWith('error:')) {
      debugPrint('[RustProxyBridge] start failed: $result');
      return null;
    }
    final p = int.tryParse(result);
    debugPrint('[RustProxyBridge] started on port $p');
    return p;
  }

  /// Stop the local HTTP proxy. No-op if not running or flag is off.
  static void stop() {
    if (!kRustProxyEnabled) return;
    RustCoreService.proxyStop();
    debugPrint('[RustProxyBridge] stopped');
  }

  /// Returns the bound proxy port, or -1 if not running / flag is off.
  static int port() {
    if (!kRustProxyEnabled) return -1;
    return RustCoreService.proxyPort();
  }

  /// Register [filePath] with the proxy.
  ///
  /// Returns a map with:
  /// - `token`         — opaque string to pass to [unregister].
  /// - `pathTemplate`  — e.g. `"/s/<token>"`.
  /// - `port`          — the proxy port.
  /// - `url`           — full URL: `http://127.0.0.1:{port}{pathTemplate}`.
  ///
  /// Returns null on failure or when [kRustProxyEnabled] is false.
  ///
  /// [name] is optional; used for Content-Type guessing (e.g. `"track.mp3"`).
  static Map<String, dynamic>? registerFile(String filePath, {String? name}) {
    if (!kRustProxyEnabled) return null;
    final result = RustCoreService.proxyRegisterFile(filePath, name: name);
    if (result == null || result.startsWith('error:')) {
      debugPrint('[RustProxyBridge] registerFile failed: $result');
      return null;
    }
    try {
      final map = jsonDecode(result) as Map<String, dynamic>;
      final p = map['port'] as int? ?? 0;
      final tmpl = map['path_template'] as String? ?? '';
      map['url'] = 'http://127.0.0.1:$p$tmpl';
      debugPrint('[RustProxyBridge] registered ${map['url']}');
      return map;
    } catch (e) {
      debugPrint('[RustProxyBridge] registerFile decode error: $e');
      return null;
    }
  }

  /// Unregister [token] from the proxy. No-op if [kRustProxyEnabled] is false.
  static void unregister(String token) {
    if (!kRustProxyEnabled) return;
    RustCoreService.proxyUnregister(token);
  }
}

// ── Feature flag ──────────────────────────────────────────────────────────────

/// Gate for the Rust local HTTP proxy.
///
/// **Round 11: `true`** — device smoke passed; RustProxyBridge is the primary
/// path for explicit file-serving (Settings → Developer / Rust Proxy panel).
///
/// `LocalStreamBridge` (the Dart HTTP proxy for MustProxy/crypt streams) was
/// **deleted** in R12.1. P0.5 (core SHA e236ece) restores MustProxy/crypt
/// playback via `wdmm_proxy_register_stream`; see `rust_proxy_stream_bridge.dart`
/// and `cloud_drive_service.resolveStreamSource`. The sync byte-delivery path
/// is a P0.5 leftover (NativeCallable.listener cannot fill *out_buf before the
/// Rust Tokio worker reads it; a native blocking primitive is needed).
/// The DLNA cast path was cut over to Rust FFI in Round 12
/// (`RustDlnaCastService` uses `wdmm_proxy_register_hls`).
///
/// Serial invariant: the proxy is a process-global singleton — never create
/// more than one instance per process.
// ignore: constant_identifier_names
const bool kRustProxyEnabled = true;
