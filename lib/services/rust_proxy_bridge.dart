// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 9 — Rust local HTTP proxy bridge.
///
/// Thin wrappers for the `wdmm_proxy_*` FFI exports added in the proxy-extract
/// round. Gated by [kRustProxyEnabled] (default `false`).
///
/// ## Purpose
/// The Rust proxy (`wdmm-proxy`) serves local files over HTTP so that DLNA
/// renderers, the system media player, and other HTTP clients can reach cached
/// media without direct filesystem access.
///
/// ## Coexistence contract (Round 9)
/// - [LocalStreamBridge] remains the **live** proxy when [kRustProxyEnabled]
///   is `false`. Do NOT delete it yet.
/// - When [kRustProxyEnabled] is `true` (debug only), all proxy calls route
///   through the Rust singleton. The Rust proxy auto-stops after inactivity
///   (idle TTL inside `ProxyHandle`); the next [registerFile] call restarts it.
///
/// ## Happy-path device smoke
/// 1. Change `kRustProxyEnabled = true` in this file and rebuild.
/// 2. Open Settings → Developer / Rust Proxy.
/// 3. Tap "Start proxy" — confirm the port is shown.
/// 4. Call [registerFile] with an existing cached mp3 file path.
/// 5. Confirm the returned URL serves the file via `curl` from a PC on the
///    same network, or by playing it directly in the system browser.
/// 6. Tap "Stop proxy" — confirm port returns to -1.
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
/// **Default: `false`** — [LocalStreamBridge] remains the live proxy engine.
///
/// When `true`, all proxy calls in [RustProxyBridge] route through the Rust
/// `wdmm-proxy` singleton via FFI. The proxy starts lazily on the first
/// [RustProxyBridge.start] call and stops after inactivity.
///
/// ## Prerequisites
/// - `kRustProxyEnabled` should only be `true` in debug builds until the Rust
///   proxy has been validated on a real device.
/// - Do NOT delete `LocalStreamBridge` until the Rust proxy is confirmed
///   feature-equivalent on device.
///
/// Serial invariant: the proxy is a process-global singleton — never create
/// more than one instance per process.
// ignore: constant_identifier_names
const bool kRustProxyEnabled = true;
