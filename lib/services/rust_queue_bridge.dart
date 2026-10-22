// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 6 — SerialPump wiring sketch (101 §D).
///
/// This file documents and stubs the Dart-side hook that will eventually
/// delegate downloads to the Rust `SerialPump` (wdmm-queue) via FFI.
///
/// **Coexistence contract (Round 6)**:
/// - [TaskQueueService] remains the live download engine; do NOT remove it.
/// - [RustQueueBridge] is a thin shim that shows the intended wire-up without
///   actually replacing any Dart logic.  It is safe to call — all its methods
///   are no-ops until [kRustQueueEnabled] is flipped to `true`.
///
/// **Future cutover (Round 7+)**:
/// 1. [TaskQueueService.enqueueDownload] calls [RustQueueBridge.enqueue].
/// 2. [RustQueueBridge.enqueue] serialises the task to JSON and calls
///    `wdmm_queue_enqueue` FFI (to be added in Round 7).
/// 3. Progress events come back via `wdmm_queue_status_json` polling or a
///    future subscription FFI.
/// 4. Once cutover is validated, [TaskQueueService]'s download path is
///    removed and the Dart `_pump` loop is replaced by the Rust SerialPump.
///
/// Serial invariant: SerialPump (Rust) enforces concurrency = 1 (same as
/// Dart `_pump`). Do NOT introduce a concurrency knob on either side.
class RustQueueBridge {
  RustQueueBridge._();

  /// Enqueue a download task in the Rust SerialPump.
  ///
  /// No-op when [kRustQueueEnabled] is false (Round 6 default).
  ///
  /// [taskJson] is a JSON object describing the task:
  /// ```json
  /// {
  ///   "id":          "uuid-...",
  ///   "kind":        "download",
  ///   "remote_path": "/Music/foo.mp3",
  ///   "account_id":  "acc-uuid",
  ///   "dest_path":   "/data/user/0/.../cache/foo.mp3"
  /// }
  /// ```
  ///
  /// Returns the result string from FFI ('ok' on success, 'error:...' on
  /// failure), or null if the bridge is disabled / library unavailable.
  static String? enqueue(String taskJson) {
    if (!kRustQueueEnabled) return null;
    // TODO(Round 7): call wdmm_queue_enqueue(taskJson) via FFI.
    // For now this is a no-op stub.  The FFI export does not exist yet.
    debugPrint('[RustQueueBridge] enqueue stub (queue disabled): $taskJson');
    return null;
  }

  /// Poll the Rust SerialPump for progress on all active/pending tasks.
  ///
  /// Returns the JSON array from [RustCoreService.getQueueStatusJson].
  /// Used during the coexistence phase to display Rust-side queue state
  /// alongside the Dart queue in the Tasks screen.
  ///
  /// Returns '[]' when the bridge is disabled or the library is unavailable.
  static String pollStatus() {
    if (!kRustQueueEnabled) return '[]';
    return RustCoreService.getQueueStatusJson();
  }

  /// Cancel a Rust-side task by id.
  ///
  /// No-op when [kRustQueueEnabled] is false.
  ///
  /// Returns 'ok', 'not_found', 'error:...', or null if disabled/unavailable.
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
    // Quick check: any `"status":"Active"` in the payload.
    return json.contains('"Active"');
  }
}

// ── Feature flag ──────────────────────────────────────────────────────────────

/// Gate for the Rust queue bridge.  Flip to `true` to enable Round 7+
/// Rust SerialPump wiring.  Defaults to `false` — Dart [TaskQueueService]
/// remains the source of truth in Round 6.
// ignore: constant_identifier_names
const bool kRustQueueEnabled = false;
