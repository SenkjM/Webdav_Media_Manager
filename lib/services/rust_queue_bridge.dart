// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 7 — SerialPump wiring (101 §D).
///
/// This file wires the Dart download enqueue path to the Rust `SerialPump`
/// (wdmm-queue) via the `wdmm_queue_enqueue` FFI export added in Round 7.
///
/// ## Coexistence contract (Round 7)
/// - [TaskQueueService] remains the **live** download engine when
///   [kRustQueueEnabled] is `false` (the default). Do NOT remove it.
/// - Setting [kRustQueueEnabled] = `true` (Settings → Developer → "Use Rust
///   Queue") routes single-file download tasks through [RustQueueBridge.enqueue]
///   which calls `wdmm_queue_enqueue` FFI. Progress is polled via
///   [RustQueueBridge.pollStatus].
///
/// ## How to enable (happy path — single-file download)
/// 1. Open `lib/services/rust_queue_bridge.dart`.
/// 2. Change `kRustQueueEnabled = false` → `kRustQueueEnabled = true`.
/// 3. Rebuild and run on a real device.
/// 4. Enqueue one download from the network library.
/// 5. Watch `[RustQueueBridge] enqueue ok` in logcat; confirm progress via
///    `pollStatus()`.
///
/// ## Serial invariant
/// SerialPump (Rust) enforces concurrency = 1 (same as Dart `_pump`). Do NOT
/// introduce a concurrency knob on either side.
///
/// ## Round 8 cutover path
/// Once the happy path is validated on a real device:
/// 1. Remove the flag guard in [enqueue] (always call FFI).
/// 2. Remove the Dart `_pump` loop from [TaskQueueService].
/// 3. Wire [pollStatus] to the task UI for live Rust-side progress.
class RustQueueBridge {
  RustQueueBridge._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Enqueue a download task in the Rust SerialPump.
  ///
  /// No-op when [kRustQueueEnabled] is false (the default in Round 7).
  ///
  /// [taskJson] is a JSON object describing the task:
  /// ```json
  /// {
  ///   "id":          "uuid-...",
  ///   "kind":        "download_track",
  ///   "remote_path": "/Music/foo.mp3",
  ///   "local_path":  "/data/user/0/.../cache/foo.mp3",
  ///   "total_bytes": 5000000
  /// }
  /// ```
  ///
  /// Returns the result string from FFI (`'ok'` on success, `'error:…'` on
  /// failure), or `null` if the bridge is disabled or the library is
  /// unavailable.
  ///
  /// ## Enable Rust Queue
  /// Set `kRustQueueEnabled = true` in this file to activate.
  static String? enqueue(String taskJson) {
    if (!kRustQueueEnabled) {
      debugPrint('[RustQueueBridge] enqueue skipped (kRustQueueEnabled=false)');
      return null;
    }
    final result = RustCoreService.queueEnqueue(taskJson);
    if (result != null) {
      debugPrint('[RustQueueBridge] enqueue → $result');
    }
    return result;
  }

  /// Poll the Rust SerialPump for progress on all active/pending tasks.
  ///
  /// Returns the JSON array from [RustCoreService.getQueueStatusJson].
  /// Used during the coexistence phase to display Rust-side queue state
  /// alongside the Dart queue in the Tasks screen.
  ///
  /// Returns `'[]'` when the bridge is disabled or the library is unavailable.
  static String pollStatus() {
    if (!kRustQueueEnabled) return '[]';
    return RustCoreService.getQueueStatusJson();
  }

  /// Cancel a Rust-side task by id.
  ///
  /// No-op when [kRustQueueEnabled] is false.
  ///
  /// Returns `'ok'`, `'not_found'`, `'error:…'`, or null if disabled/unavailable.
  static String? cancel(String taskId) {
    if (!kRustQueueEnabled) return null;
    return RustCoreService.cancelTask(taskId);
  }

  /// Returns true when the Rust queue has at least one Active task.
  ///
  /// During the coexistence phase, the Dart queue is authoritative —
  /// this is for diagnostic display only.
  static bool hasActiveTask() {
    if (!kRustQueueEnabled) return false;
    final json = pollStatus();
    return json.contains('"Active"');
  }
}

// ── Feature flag ──────────────────────────────────────────────────────────────

/// Gate for the Rust queue bridge.
///
/// **Default: `false`** — Dart [TaskQueueService] remains the download engine.
///
/// Set to `true` to route single-file downloads through the Rust `SerialPump`
/// via `wdmm_queue_enqueue` FFI. See [RustQueueBridge] for enable instructions
/// and the full cutover path.
///
/// Serial invariant: SerialPump enforces concurrency = 1 — never introduce a
/// concurrency knob on either side.
// ignore: constant_identifier_names
const bool kRustQueueEnabled = false;
