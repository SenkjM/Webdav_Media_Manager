// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// SerialPump wiring (101 §D).
///
/// Wires the Dart download enqueue path to the Rust `SerialPump`
/// (wdmm-queue) via the `wdmm_queue_enqueue` FFI export.
///
/// ## Serial invariant
/// SerialPump (Rust) enforces concurrency = 1 (same as Dart `_pump`). Do NOT
/// introduce a concurrency knob on either side.
class RustQueueBridge {
  RustQueueBridge._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Enqueue a download task in the Rust SerialPump.
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
  /// failure), or `null` if the library is unavailable.
  static String? enqueue(String taskJson) {
    final result = RustCoreService.queueEnqueue(taskJson);
    if (result != null) {
      debugPrint('[RustQueueBridge] enqueue → $result');
    }
    return result;
  }

  /// Poll the Rust SerialPump for progress on all active/pending tasks.
  ///
  /// Returns the JSON array from [RustCoreService.getQueueStatusJson].
  /// Returns `'[]'` when the library is unavailable.
  static String pollStatus() {
    return RustCoreService.getQueueStatusJson();
  }

  /// Cancel a Rust-side task by id.
  ///
  /// Returns `'ok'`, `'not_found'`, `'error:…'`, or null if unavailable.
  static String? cancel(String taskId) {
    return RustCoreService.cancelTask(taskId);
  }

  /// Returns true when the Rust queue has at least one Active task.
  static bool hasActiveTask() {
    final json = pollStatus();
    return json.contains('"Active"');
  }
}
