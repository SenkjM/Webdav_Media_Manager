// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'rust_core_service.dart';

/// Round 6/v9b — dual-read probe for the library DB cutover (101 §A/§B).
///
/// This is a **read-only diagnostic**. It compares row counts between the
/// legacy Dart sqflite library DB and the new Rust rusqlite library DB on
/// app startup, so we can surface row-count drift *before* the cutover
/// flip. It does **not** dual-write and does **not** delete the Dart DB.
///
/// Three surfaces are probed:
///   * `tracks`        — rows in the `tracks` table (sqflite vs rusqlite)
///   * `deleted_tracks`— tombstone rows (sqflite vs rusqlite)
///   * `sync_state`    — cursor rows (sqflite vs rusqlite; rusqlite via the
///                        CompareReport when an [oldDbPath] is supplied, as
///                        there is no `list_sync_states` FFI)
///
/// Usage: call [RustLibraryProbe.runOnStartup] once at app start (debug
/// builds only — see [RustCoreService.debugLogVersion]). Pass a callback
/// that returns the Dart-side track count (and optionally the Dart-side
/// tombstone/sync counts); the Rust side is queried via FFI.  Results are
/// emitted via [debugPrint].
///
/// The probe never throws — any failure is swallowed with a debug log so
/// it can never block app startup.
class RustLibraryProbe {
  RustLibraryProbe._();

  /// Run the dual-read count probe once at startup.
  ///
  /// [dartTrackCount] returns the number of tracks in the Dart sqflite DB
  /// (or null if the Dart DB is not reachable).  The Rust track count is
  /// obtained via [RustCoreService.trackList] and decoded as a JSON array.
  ///
  /// Optional callbacks surface the v6 tombstone / sync_state surfaces:
  ///   * [dartDeletedTrackCount] — sqflite `deleted_tracks` row count.
  ///   * [dartSyncStateCount]    — sqflite `sync_state` row count.
  ///
  /// When [oldDbPath] is a non-empty path, the CompareReport produced by
  /// [RustCoreService.libraryCompareWithSqflite] is used to source the
  /// `deleted_tracks` / `sync_state` counts (left = sqflite, right =
  /// rusqlite), since there is no `list_sync_states` FFI.
  ///
  /// Emits one log line per surface, e.g.:
  ///   `[RustLibraryProbe] tracks — sqflite: 142, rusqlite: 142 (match)`
  ///   `[RustLibraryProbe] deleted_tracks — sqflite: 5, rusqlite: 5 (match)`
  ///   `[RustLibraryProbe] sync_state — sqflite: 2, rusqlite: n/a (DRIFT: 3)`
  ///
  /// No-op when [RustCoreService] is unavailable (non-Android, or native lib
  /// not yet built) — the Dart path stays the source of truth.
  static void runOnStartup({
    required Future<int?> Function() dartTrackCount,
    Future<int?> Function()? dartDeletedTrackCount,
    Future<int?> Function()? dartSyncStateCount,
    String? oldDbPath,
  }) {
    // Fire-and-forget; never block startup.
    Future(() async {
      await _probeCounts(
        dartTrackCount: dartTrackCount,
        dartDeletedTrackCount: dartDeletedTrackCount,
        dartSyncStateCount: dartSyncStateCount,
        oldDbPath: oldDbPath,
      );
    });
  }

  static Future<void> _probeCounts({
    required Future<int?> Function() dartTrackCount,
    Future<int?> Function()? dartDeletedTrackCount,
    Future<int?> Function()? dartSyncStateCount,
    String? oldDbPath,
  }) async {
    // ── tracks ────────────────────────────────────────────────────────────
    var sqfliteTracks = await _safeCount(dartTrackCount, 'sqflite track count');
    var rusqliteTracks = _arrayLength(RustCoreService.trackList());

    // ── deleted_tracks ────────────────────────────────────────────────────
    var sqfliteDeleted = await _safeCount(
      dartDeletedTrackCount,
      'sqflite deleted_tracks count',
    );
    var rusqliteDeleted = _arrayLength(RustCoreService.deletedTracksList());

    // ── sync_state ────────────────────────────────────────────────────────
    // No `list_sync_states` FFI: sqflite from the callback, rusqlite n/a
    // unless a CompareReport supplies it below.
    var sqfliteSync = await _safeCount(
      dartSyncStateCount,
      'sqflite sync_state count',
    );
    int? rusqliteSync;

    if (oldDbPath != null && oldDbPath.isNotEmpty) {
      // Prefer the CompareReport: left = sqflite, right = rusqlite.  This is
      // the only source for the rusqlite sync_state count.  Any surface the
      // report omits keeps the callback / list-derived value.
      final report = RustCoreService.libraryCompareWithSqflite(oldDbPath);
      final tracksPair = countPairFromCompare(report, 'tracks');
      final deletedPair = countPairFromCompare(report, 'deleted_tracks');
      final syncPair = countPairFromCompare(report, 'sync_state');
      sqfliteTracks = tracksPair?.sqflite ?? sqfliteTracks;
      rusqliteTracks = tracksPair?.rusqlite ?? rusqliteTracks;
      sqfliteDeleted = deletedPair?.sqflite ?? sqfliteDeleted;
      rusqliteDeleted = deletedPair?.rusqlite ?? rusqliteDeleted;
      sqfliteSync = syncPair?.sqflite ?? sqfliteSync;
      rusqliteSync = syncPair?.rusqlite ?? rusqliteSync;
    }

    _emitCountLine('tracks', sqfliteTracks, rusqliteTracks);
    _emitCountLine('deleted_tracks', sqfliteDeleted, rusqliteDeleted);
    _emitCountLine('sync_state', sqfliteSync, rusqliteSync);

    // ── Phase C: artist/album counts (log only) ────────────────────────────
    // When dual-write is enabled, compare distinct artist/album counts from
    // Core aggregates vs sqflite in-memory distinct lists. Log only; no fail.
    final rustArtists = _arrayLength(RustCoreService.artistList());
    final rustAlbums = _arrayLength(RustCoreService.albumList());
    if (rustArtists != null || rustAlbums != null) {
      debugPrint(
        '[RustLibraryProbe] Core aggregates — artists: ${_fmt(rustArtists ?? -1)}, '
        'albums: ${_fmt(rustAlbums ?? -1)} (compare vs sqflite distinctArtists/distinctAlbums when available)',
      );
    }
  }

  /// Await [cb] guarded so a throwing/failing callback can never break the
  /// probe; returns null when [cb] is null or fails.
  static Future<int?> _safeCount(
    Future<int?> Function()? cb,
    String label,
  ) async {
    if (cb == null) return null;
    try {
      return await cb();
    } catch (e) {
      debugPrint('[RustLibraryProbe] $label failed (non-fatal): $e');
      return null;
    }
  }

  /// Decode a Rust JSON-array string and return its length, tolerating a
  /// null / `error:` / non-array / undecodable payload (→ null).
  static int? _arrayLength(String? rustJson) {
    if (rustJson == null || rustJson.startsWith('error:')) return null;
    try {
      final decoded = jsonDecode(rustJson);
      if (decoded is List) return decoded.length;
    } catch (e) {
      debugPrint('[RustLibraryProbe] rusqlite decode failed (non-fatal): $e');
    }
    return null;
  }

  static void _emitCountLine(String label, int? sqflite, int? rusqlite) {
    if (sqflite == null && rusqlite == null) {
      // Neither DB reachable for this surface — nothing to compare (expected
      // on desktop/debug host where the native lib isn't shipped).
      return;
    }
    final sq = sqflite ?? -1;
    final ru = rusqlite ?? -1;
    final match = sq == ru;
    final tag = match ? 'match' : 'DRIFT: ${sq > ru ? sq - ru : ru - sq}';
    debugPrint(
      '[RustLibraryProbe] $label — sqflite: ${_fmt(sq)}, '
      'rusqlite: ${_fmt(ru)} ($tag)',
    );
  }

  /// Parse a [CompareReport] JSON string and pull the `left_count` /
  /// `right_count` pair for [surface] (`tracks`, `deleted_tracks`, or
  /// `sync_state`).  Left is sqflite, right is rusqlite.
  ///
  /// Pure and total: tolerates null / `error:` / malformed JSON / a missing
  /// surface key by returning null.  Exposed for unit testing without FFI.
  static ({int? sqflite, int? rusqlite})? countPairFromCompare(
    String? reportJson,
    String surface,
  ) {
    if (reportJson == null || reportJson.startsWith('error:')) return null;
    try {
      final decoded = jsonDecode(reportJson);
      if (decoded is! Map) return null;
      final surfaceMap = decoded[surface];
      if (surfaceMap is! Map) return null;
      final left = surfaceMap['left_count'];
      final right = surfaceMap['right_count'];
      return (
        sqflite: left is int ? left : null,
        rusqlite: right is int ? right : null,
      );
    } catch (e) {
      debugPrint(
        '[RustLibraryProbe] compare decode failed for $surface '
        '(non-fatal): $e',
      );
      return null;
    }
  }

  /// Format an operator log line for a decoded [ImportSummary] JSON string,
  /// or null when the payload is not a decodable JSON object (null /
  /// `error:` / malformed).
  ///
  /// Pure and total — exposed for unit testing without FFI.
  static String? formatImportSummary(String? result) {
    if (result == null || result.startsWith('error:')) return null;
    Map<dynamic, dynamic> decoded;
    try {
      final parsed = jsonDecode(result);
      if (parsed is! Map) return null;
      decoded = parsed;
    } catch (e) {
      return null;
    }
    final parts = <String>[];
    for (final key in const [
      'already_done',
      'tracks',
      'playlists',
      'entries',
      'deleted_tracks',
      'sync_state',
    ]) {
      if (decoded.containsKey(key)) {
        parts.add('$key: ${decoded[key]}');
      }
    }
    return '[RustLibraryProbe] import — ${parts.join(', ')}';
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
  ///
  /// On a successful JSON result the summary is logged as one operator line
  /// (see [formatImportSummary]) so first-run callers surface the v6
  /// `deleted_tracks` / `sync_state` import counts.  The raw JSON is returned
  /// unchanged.
  static String? maybeImportFromSqflite(String oldDbPath) {
    String? result;
    try {
      result = RustCoreService.libraryImportFromSqflite(oldDbPath);
    } catch (e) {
      debugPrint('[RustLibraryProbe] import failed (non-fatal): $e');
      return null;
    }
    final line = formatImportSummary(result);
    if (line != null) {
      debugPrint(line);
    } else if (result != null) {
      debugPrint('[RustLibraryProbe] import non-JSON result (non-fatal): '
          '$result');
    }
    return result;
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
