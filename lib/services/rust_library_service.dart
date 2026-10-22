// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/library_track.dart';
import 'rust_core_service.dart';

/// Round 8 — Rust library read service.
///
/// Gates list / search / get calls behind [kRustLibraryReadEnabled].  When the
/// flag is `true`, read ops (list all tracks, search, get by id) are served
/// from the Rust rusqlite DB via FFI; write paths remain on the Dart sqflite
/// shim and carry `// TODO(cutover)` markers.
///
/// ## Schema gap notes
/// The Rust `LibraryTrack` JSON uses snake_case field names (`account_id`,
/// `remote_path`, …) that differ slightly from the Dart sqflite map keys
/// (`source_name`, `file_name`, …).  The [_rustJsonToTrack] helper bridges
/// the gap by accepting both naming conventions; `source_name` wins over
/// `account_id` when both are present.
///
/// Fields that do not exist in the Rust schema (album_artist, cover_path,
/// bitrate, sample_rate, cue_*, cache_group_id, remote_missing) are filled
/// with safe defaults so the resulting LibraryTrack works correctly in the
/// Dart UI.
///
/// ## Cutover path (Round 9)
/// 1. Validate row-count parity on device (RustLibraryProbe still runs at
///    startup in debug builds).
/// 2. Flip [kRustLibraryReadEnabled] = `true` in this file.
/// 3. Rebuild + smoke-test on a real device.
/// 4. After device green: flip write paths and delete
///    `music_library_database_impl.dart`.
class RustLibraryService {
  RustLibraryService._();

  // ── Read ops ────────────────────────────────────────────────────────────────

  /// List all tracks from the Rust rusqlite DB.
  ///
  /// Returns `null` when [kRustLibraryReadEnabled] is `false` or when the
  /// native library is unavailable — callers must fall back to Dart sqflite.
  ///
  /// Never throws.
  static List<LibraryTrack>? listAll() {
    if (!kRustLibraryReadEnabled) return null;
    final json = RustCoreService.trackList();
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] listAll failed: $json');
      return null;
    }
    return _decodeArray(json);
  }

  /// Search tracks by title/artist substring.
  ///
  /// Returns `null` when [kRustLibraryReadEnabled] is `false` or the library
  /// is unavailable.  Returns an empty list on a genuine zero-hit search.
  ///
  /// Never throws.
  static List<LibraryTrack>? search(String query) {
    if (!kRustLibraryReadEnabled) return null;
    if (query.trim().isEmpty) return listAll();
    final json = RustCoreService.trackSearch(query.trim());
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] search("$query") failed: $json');
      return null;
    }
    return _decodeArray(json);
  }

  /// Get a single track by its rusqlite `id` (SHA-1 hex).
  ///
  /// Returns `null` when [kRustLibraryReadEnabled] is `false`, the track is
  /// not found, or the library is unavailable.
  ///
  /// Never throws.
  static LibraryTrack? getById(String id) {
    if (!kRustLibraryReadEnabled) return null;
    final json = RustCoreService.trackGet(id);
    if (json == null || json == 'null' || json.startsWith('error:')) {
      return null;
    }
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return _rustJsonToTrack(map);
    } catch (e) {
      debugPrint('[RustLibraryService] getById("$id") decode error: $e');
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Decode a JSON array of track objects into LibraryTrack instances.
  static List<LibraryTrack>? _decodeArray(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return null;
      final out = <LibraryTrack>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final t = _rustJsonToTrack(item);
          if (t != null) out.add(t);
        }
      }
      return out;
    } catch (e) {
      debugPrint('[RustLibraryService] _decodeArray error: $e');
      return null;
    }
  }

  /// Convert a Rust LibraryTrack JSON map → Dart LibraryTrack.
  ///
  /// The Rust schema uses `account_id` for what Dart calls `source_name`.
  /// `remote_path` and `title` are shared.  Missing Dart-only fields (CUE
  /// columns, cover_path, bitrate, …) are filled with null / defaults.
  static LibraryTrack? _rustJsonToTrack(Map<String, dynamic> map) {
    try {
      // `source_name` takes precedence over `account_id` in case a row was
      // imported from sqflite with the Dart key name preserved.
      final sourceName =
          (map['source_name'] as String?) ??
          (map['account_id'] as String?) ??
          '';
      final remotePath = (map['remote_path'] as String?) ?? '';
      if (sourceName.isEmpty || remotePath.isEmpty) return null;

      final id = (map['id'] as String?);
      final fileName =
          remotePath.contains('/')
              ? remotePath.split('/').last
              : remotePath;

      return LibraryTrack(
        musicId: (id != null && id.isNotEmpty) ? id : null,
        sourceName: sourceName,
        remotePath: remotePath,
        fileName: fileName,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        // albumArtist not in Rust schema; leave null
        album: null,
        durationMs: _asInt(map['duration_ms']),
        trackNumber: _asInt(map['track_number']),
        discNumber: _asInt(map['disc_number']),
        year: _asInt(map['year']),
        genre: map['genre'] as String?,
        // Fields with no Rust equivalent — safe defaults:
        bitrate: null,
        sampleRate: null,
        coverPath: null,
        cueId: null,
        cueRemotePath: null,
        cueTrackIndex: null,
        audioMusicId: null,
        audioRemotePath: null,
        clipStartMs: null,
        clipEndMs: null,
        cacheGroupId: null,
        remoteMissing: false,
      );
    } catch (e) {
      debugPrint('[RustLibraryService] _rustJsonToTrack error: $e');
      return null;
    }
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

// ── Feature flag ──────────────────────────────────────────────────────────────

/// Gate for the Rust library read path.
///
/// **Default: `false`** — Dart sqflite ([LibraryDatabase]) remains the source
/// of truth for list / search / get ops.
///
/// When `true`, [RustLibraryService.listAll], [RustLibraryService.search], and
/// [RustLibraryService.getById] return data from the Rust rusqlite DB via FFI.
///
/// ## Enable instructions
/// 1. Verify row-count parity in logcat: `[RustLibraryProbe] tracks … (match)`.
/// 2. Change `kRustLibraryReadEnabled = false` → `kRustLibraryReadEnabled = true`.
/// 3. Rebuild and run on a real Android device.
/// 4. Confirm the library screen loads correctly with the same tracks.
/// 5. Round 9: flip write paths and delete `music_library_database_impl.dart`.
///
/// Serial invariant: list / search / get are read-only — no concurrency risk.
// ignore: constant_identifier_names
const bool kRustLibraryReadEnabled = false;
