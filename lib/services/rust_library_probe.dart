// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 6 — dual-read probe for the library DB cutover (101 §A/§B).
///
/// This is a **read-only diagnostic**. It compares row counts between the
/// legacy Dart sqflite library DB and the new Rust rusqlite library DB on
/// app startup, so we can surface row-count drift *before* the cutover
/// flip. It does **not** dual-write and does **not** delete the Dart DB.
///
/// Usage: call [RustLibraryProbe.runOnStartup] once at app start (debug
/// builds only — see [RustCoreService.debugLogVersion]). Pass a callback
/// that returns the Dart-side track count; the Rust side is queried via
/// FFI.  Results are emitted via [debugPrint].
///
/// The probe never throws — any failure is swallowed with a debug log so
/// it can never block app startup.
class RustLibraryProbe {
  RustLibraryProbe._();

  /// Run the dual-read count probe once at startup.
  ///
  /// [dartTrackCount] returns the number of tracks in the Dart sqflite DB
  /// (or null if the Dart DB is not reachable).  The Rust count is obtained
  /// via [RustCoreService.trackList] and decoded as a JSON array.
  ///
  /// Emits a single log line like:
  ///   `[RustLibraryProbe] tracks — sqflite: 142, rusqlite: 142 (match)`
  /// or
  ///   `[RustLibraryProbe] tracks — sqflite: 142, rusqlite: 138 (DRIFT: 4)`
  ///
  /// No-op when [RustCoreService] is unavailable (non-Android, or native lib
  /// not yet built) — the Dart path stays the source of truth.
  static void runOnStartup({
    required Future<int?> Function() dartTrackCount,
  }) {
    // Fire-and-forget; never block startup.
    Future(() async {
      await _probeCounts(dartTrackCount: dartTrackCount);
    });
  }

  static Future<void> _probeCounts({
    required Future<int?> Function() dartTrackCount,
  }) async {
    int? sqfliteCount;
    try {
      sqfliteCount = await dartTrackCount();
    } catch (e) {
      debugPrint('[RustLibraryProbe] sqflite count failed (non-fatal): $e');
    }

    int? rusqliteCount;
    final rustJson = RustCoreService.trackList();
    if (rustJson != null && !rustJson.startsWith('error:')) {
      try {
        final decoded = jsonDecode(rustJson);
        if (decoded is List) {
          rusqliteCount = decoded.length;
        }
      } catch (e) {
        debugPrint('[RustLibraryProbe] rusqlite decode failed (non-fatal): $e');
      }
    }

    if (sqfliteCount == null && rusqliteCount == null) {
      // Neither DB reachable — nothing to compare (expected on desktop/debug
      // host where the native lib isn't shipped).
      return;
    }

    final sq = sqfliteCount ?? -1;
    final ru = rusqliteCount ?? -1;
    final match = sq == ru;
    final tag = match ? 'match' : 'DRIFT: ${sq > ru ? sq - ru : ru - sq}';
    debugPrint(
      '[RustLibraryProbe] tracks — sqflite: ${_fmt(sq)}, '
      'rusqlite: ${_fmt(ru)} ($tag)',
    );
  }

  static String _fmt(int n) => n < 0 ? 'n/a' : n.toString();

  /// A no-op first-run import helper (101 §A).  Safe to call at startup: the
  /// Rust side sets a KV flag `sqflite_imported = 1` after the first
  /// successful import and skips subsequent calls, so this is cheap to
  /// invoke every launch.
  ///
  /// [oldDbPath] is the absolute path to the legacy `music_library.db`
  /// sqflite file on the device.
  ///
  /// Returns the JSON summary string from Rust, or null if the native lib is
  /// unavailable.  Never throws.
  static String? maybeImportFromSqflite(String oldDbPath) {
    try {
      return RustCoreService.libraryImportFromSqflite(oldDbPath);
    } catch (e) {
      debugPrint('[RustLibraryProbe] import failed (non-fatal): $e');
      return null;
    }
  }

  /// A debug-only comparison helper: compares the Rust library against the
  /// legacy sqflite DB at [oldDbPath] and returns the JSON `CompareReport`
  /// (tracks / deleted_tracks / sync_state diffs).  Neither DB is mutated.
  ///
  /// Returns the JSON report string from Rust, or null if the native lib is
  /// unavailable.  Never throws.
  static String? maybeCompareWithSqflite(String oldDbPath) {
    try {
      return RustCoreService.libraryCompareWithSqflite(oldDbPath);
    } catch (e) {
      debugPrint('[RustLibraryProbe] compare failed (non-fatal): $e');
      return null;
    }
  }
}

// ── Feature flags (Round 6 — coexistence phase) ────────────────────────────

/// When true, [RustLibraryProbe.runOnStartup] is invoked at app start.
/// Defaults to true in debug builds only; the Dart sqflite DB remains the
/// source of truth until the cutover flip in a later round.
// ignore: constant_identifier_names
const bool kRustLibraryProbeEnabled = true;
