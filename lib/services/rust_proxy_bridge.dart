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
/// ## R12 cutover status
/// - [kRustProxyEnabled] is `true` (device smoke passed in Round 10/11).
/// - [LocalStreamBridge] is **deleted** (R12): MustProxy (crypt) streaming and
///   DLNA LAN cast now route through [RustProxyStreamBridge], which drives the
///   `wdmm_proxy_register_stream` / `wdmm_proxy_stream_set_result` FFI added in
///   this round. Dart supplies Range bytes to the proxy via a
///   `NativeCallable.listener` async reply channel; no Dart HTTP server.
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
  /// Returns the bound port as an integer on success, or null on failure /
  /// when [kRustProxyEnabled] is false.
  ///
  /// Idempotent — if the proxy is already running, returns its current port.
  static int? start({required String bindMode, int port = 0}) {
    if (!kRustProxyEnabled) return null;
    final result = RustCoreService.proxyStart(bindMode: bindMode, port: port);
    if (result == null || result.startsWith('error:')) {
      debugPrint('[RustProxyBridge] start failed: $result');
      return null;
    }
    final p = int.tryParse(result);
    debugPrint('[RustProxyBridge] started on port $p (bind: $bindMode)');
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
/// **R12: `true`** — LocalStreamBridge deleted. MustProxy + DLNA cast route
/// through [RustProxyStreamBridge] via [wdmm_proxy_register_stream] FFI.
///
/// Serial invariant: the proxy is a process-global singleton — never create
/// more than one instance per process.
// ignore: constant_identifier_names
const bool kRustProxyEnabled = true;
