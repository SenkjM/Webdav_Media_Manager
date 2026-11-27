// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 11 — Rust local HTTP proxy bridge.
///
/// Thin wrappers for the `wdmm_proxy_*` FFI exports.
///
/// ## Purpose
/// The Rust proxy (`wdmm-proxy`) serves local files over HTTP so that DLNA
/// renderers, the system media player, and other HTTP clients can reach cached
/// media without direct filesystem access.
///
/// ## R12 cutover status
/// - [LocalStreamBridge] is **deleted** (R12): MustProxy (crypt) streaming is
///   registered through `wdmm_proxy_register_account`, so the Rust proxy builds
///   the driver from the database and streams content in 1 MiB
///   `get_content_range` chunks. No Dart byte callbacks, no Dart HTTP server.
/// - Settings → Developer / Rust Proxy panel drives start/stop/register for the
///   Rust proxy path (Settings section still present).
///
/// ## Serial invariant
/// The proxy is a process-global singleton — never create more than one instance.
class RustProxyBridge {
  RustProxyBridge._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start the local HTTP proxy with the given bind mode and port.
  ///
  /// [bindMode] specifies where the proxy listens:
  /// - `"loopback"` — 127.0.0.1 (localhost only; DLNA devices cannot reach)
  /// - `"lan_any"` — 0.0.0.0 (all interfaces; OS routes to appropriate one)
  /// - `"lan_if:<ip>"` — specific interface (e.g., `"lan_if:192.168.1.100"`)
  /// - `"explicit:<addr>"` — exact SocketAddr (e.g., `"explicit:192.168.1.100:8080"`)
  ///
  /// [port] — port number; use 0 to let OS assign (ignored for `explicit:<addr>`).
  ///
  /// Returns the bound port as an integer on success, or null on failure.
  ///
  /// Idempotent — if the proxy is already running, returns its current port.
  static int? start({required String bindMode, int port = 0}) {
    final result = RustCoreService.proxyStart(bindMode: bindMode, port: port);
    if (result == null || result.startsWith('error:')) {
      debugPrint('[RustProxyBridge] start failed: $result');
      return null;
    }
    final p = int.tryParse(result);
    debugPrint('[RustProxyBridge] started on port $p (bind: $bindMode)');
    return p;
  }

  /// Stop the local HTTP proxy. No-op if not running.
  static void stop() {
    RustCoreService.proxyStop();
    debugPrint('[RustProxyBridge] stopped');
  }

  /// Returns the bound proxy port, or -1 if not running.
  static int port() {
    return RustCoreService.proxyPort();
  }

  /// Unregister [token] from the proxy.
  static void unregister(String token) {
    RustCoreService.proxyUnregister(token);
  }
}
