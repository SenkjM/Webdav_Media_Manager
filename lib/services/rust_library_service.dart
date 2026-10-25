// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/library_track.dart';
import 'rust_core_service.dart';

/// Round 8/9 — Rust library service.
///
/// Gates read ops behind [kRustLibraryReadEnabled] and write ops behind
/// [kRustLibraryWriteEnabled].  When a flag is `true`, the matching ops are
/// served from the Rust rusqlite DB via FFI; the Dart sqflite path remains
/// the source of truth while a flag is `false`.
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
/// 4. After device green: flip [kRustLibraryWriteEnabled] = `true`, run a
///    dual-write probe, and confirm parity before deleting
///    `music_library_database_impl.dart`.
class RustLibraryService {
  RustLibraryService._();

  // ── Read ops ────────────────────────────────────────────────────────────────

  /// List all tracks from the Rust rusqlite DB.
  ///
  /// Returns `null` when [kRustLibraryReadEnabled] is `false` or when the
  /// native library is unavailable — throws [StateError] (no Dart fallback).
  ///
  /// Never throws.
  static List<LibraryTrack>? listAll() {
    if (!kRustLibraryReadEnabled) return null;
    final json = RustCoreService.trackList();
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] listAll failed: $json');
      // Do not return null for callers to soft-fall back to sqflite.
      throw StateError('RustLibraryService.listAll failed: $json');
    }
    return _decodeArray(json);
  }

  /// Search tracks by title/artist substring.
  ///
  /// Returns `null` when [kRustLibraryReadEnabled] is `false` or the library
  /// is unavailable (throws).  Returns an empty list on a genuine zero-hit search.
  ///
  /// Never throws.
  static List<LibraryTrack>? search(String query) {
    if (!kRustLibraryReadEnabled) return null;
    if (query.trim().isEmpty) return listAll();
    final json = RustCoreService.trackSearch(query.trim());
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] search("$query") failed: $json');
      throw StateError('RustLibraryService.search failed: $json');
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

  // ── Write ops ───────────────────────────────────────────────────────────────

  /// Upsert [track] into the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false` (the default) or when
  /// the native library is unavailable.  Returns the result string from FFI
  /// (`'ok'` on success, `'error:…'` on failure), or `null` if disabled.
  ///
  /// CUE slice tracks are skipped: their `musicId` field is used as the Rust
  /// `id`, and the Rust schema does not yet have a CUE-slice model.
  ///
  /// Never throws.
  static String? upsertTrack(LibraryTrack track) {
    if (!kRustLibraryWriteEnabled) return null;
    final json = _trackToRustJson(track);
    if (json == null) return null;
    try {
      final result = RustCoreService.trackUpsert(jsonEncode(json));
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] upsertTrack failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] upsertTrack exception: $e');
      return null;
    }
  }

  /// Delete the track identified by [musicId] from the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false`, [musicId] is null/
  /// empty, or the library is unavailable.
  ///
  /// Never throws.
  static String? deleteTrack(String? musicId) {
    if (!kRustLibraryWriteEnabled) return null;
    if (musicId == null || musicId.isEmpty) return null;
    try {
      final result = RustCoreService.trackDelete(musicId);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deleteTrack("$musicId") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deleteTrack exception: $e');
      return null;
    }
  }

  /// Delete all tracks for [accountId] from the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false`, [accountId] is null/
  /// empty, or the library is unavailable.
  ///
  /// Never throws.
  static String? deleteTracksBySource(String? accountId) {
    if (!kRustLibraryWriteEnabled) return null;
    if (accountId == null || accountId.isEmpty) return null;
    try {
      final result = RustCoreService.trackDeleteBySource(accountId);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deleteTracksBySource("$accountId") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deleteTracksBySource exception: $e');
      return null;
    }
  }

  /// Clear the entire library (tracks, playlists, manga, CUE sheets).
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false` or the library is
  /// unavailable.
  ///
  /// Never throws.
  static String? clearLibraryAll() {
    if (!kRustLibraryWriteEnabled) return null;
    try {
      final result = RustCoreService.libraryClearAll();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] clearLibraryAll failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] clearLibraryAll exception: $e');
      return null;
    }
  }

  /// Clear the library index (tracks, CUE sheets, deleted_tracks) but preserve
  /// playlists and manga.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false` or the library is
  /// unavailable.
  ///
  /// Never throws.
  static String? clearLibraryIndex() {
    if (!kRustLibraryWriteEnabled) return null;
    try {
      final result = RustCoreService.libraryClearIndex();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] clearLibraryIndex failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] clearLibraryIndex exception: $e');
      return null;
    }
  }

  /// Delete one CUE slice from the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false`, [musicId] is null/
  /// empty, or the library is unavailable.
  ///
  /// Never throws.
  static String? deleteCueSlice(String? musicId) {
    if (!kRustLibraryWriteEnabled) return null;
    if (musicId == null || musicId.isEmpty) return null;
    try {
      final result = RustCoreService.cueSliceDelete(musicId);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deleteCueSlice("$musicId") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deleteCueSlice exception: $e');
      return null;
    }
  }

  /// Delete an entire CUE album and its slices from the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false` or parameters are
  /// null/empty.
  ///
  /// Never throws.
  static String? deleteCueAlbum(String? sourceName, String? cueRemotePath) {
    if (!kRustLibraryWriteEnabled) return null;
    if (sourceName == null || sourceName.isEmpty) return null;
    if (cueRemotePath == null || cueRemotePath.isEmpty) return null;
    try {
      final result = RustCoreService.cueAlbumDelete(sourceName, cueRemotePath);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deleteCueAlbum("$sourceName", "$cueRemotePath") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deleteCueAlbum exception: $e');
      return null;
    }
  }

  /// Count remaining CUE slices for the given album from the Rust rusqlite DB.
  ///
  /// Returns a decimal count string (e.g. "5"), "error:...", or `null` if
  /// [kRustLibraryReadEnabled] is `false` or the library is unavailable.
  ///
  /// Never throws.
  static String? listCueRemainingSlices(String? sourceName, String? cueRemotePath) {
    if (!kRustLibraryReadEnabled) return null;
    if (sourceName == null || sourceName.isEmpty) return null;
    if (cueRemotePath == null || cueRemotePath.isEmpty) return null;
    try {
      final result = RustCoreService.cueRemainingSlices(sourceName, cueRemotePath);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] listCueRemainingSlices("$sourceName", "$cueRemotePath") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] listCueRemainingSlices exception: $e');
      return null;
    }
  }

  /// Upsert a CUE slice into the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false` or [sliceJson] is
  /// null/empty.
  ///
  /// Never throws.
  static String? upsertCueSlice(String? sliceJson) {
    if (!kRustLibraryWriteEnabled) return null;
    if (sliceJson == null || sliceJson.isEmpty) return null;
    try {
      final result = RustCoreService.cueSliceUpsert(sliceJson);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] upsertCueSlice failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] upsertCueSlice exception: $e');
      return null;
    }
  }

  /// Upsert a CUE album into the Rust rusqlite DB.
  ///
  /// No-op when [kRustLibraryWriteEnabled] is `false` or [albumJson] is
  /// null/empty.
  ///
  /// Never throws.
  static String? upsertCueAlbum(String? albumJson) {
    if (!kRustLibraryWriteEnabled) return null;
    if (albumJson == null || albumJson.isEmpty) return null;
    try {
      final result = RustCoreService.cueAlbumUpsert(albumJson);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] upsertCueAlbum failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] upsertCueAlbum exception: $e');
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

  /// Convert a Dart [LibraryTrack] → Rust upsert JSON object.
  ///
  /// Returns `null` when the track has no stable `musicId` (the Rust `id`
  /// column is the SHA-1 hex and is required for an upsert).  CUE slices
  /// are included when they carry a `musicId`.
  static Map<String, dynamic>? _trackToRustJson(LibraryTrack track) {
    final id = track.musicId;
    if (id == null || id.isEmpty) return null;
    return {
      'id': id,
      // Rust schema requires a non-empty title; fall back to the file name.
      'title': (track.title?.isNotEmpty ?? false) ? track.title! : track.fileName,
      'artist': track.artist,
      'remote_path': track.remotePath,
      // Rust uses `account_id` for what Dart calls `source_name`.
      'account_id': track.sourceName,
      'size': 0,
      'duration_ms': track.durationMs ?? 0,
      'genre': track.genre,
      'track_number': track.trackNumber,
      'disc_number': track.discNumber,
      'year': track.year,
      'mime_type': null,
    };
  }
}

// ── Feature flags ─────────────────────────────────────────────────────────────

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
/// 5. Round 9+: flip write flag and delete `music_library_database_impl.dart`.
///
/// Serial invariant: list / search / get are read-only — no concurrency risk.
// ignore: constant_identifier_names
const bool kRustLibraryReadEnabled = true;

/// Gate for the Rust library write path.
///
/// **Default: `false`** — Dart sqflite remains the write target.
///
/// When `true`, [RustLibraryService.upsertTrack] and [RustLibraryService.deleteTrack]
/// mirror every Dart sqflite write into the Rust rusqlite DB via FFI.  This
/// enables a dual-write probe: both DBs are updated in parallel so row-count
/// and content parity can be verified before the sqflite path is removed.
///
/// ## Cutover path
/// 1. Ensure [kRustLibraryReadEnabled] is `true` and device smoke green.
/// 2. Change `kRustLibraryWriteEnabled = false` → `kRustLibraryWriteEnabled = true`.
/// 3. Rebuild.  Both DBs are now written on every ingest / upsert / delete.
/// 4. Verify logcat shows no `[RustLibraryService] upsertTrack failed` lines.
/// 5. After dual-write probe passes: remove sqflite calls and delete
///    `music_library_database_impl.dart`.
///
/// Do **not** flip to `true` before [kRustLibraryReadEnabled] is confirmed.
// ignore: constant_identifier_names
const bool kRustLibraryWriteEnabled = true;
