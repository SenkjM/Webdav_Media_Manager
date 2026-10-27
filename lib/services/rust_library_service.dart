// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/library_track.dart';
import '../utils/track_identity.dart';
import 'rust_core_service.dart';

/// Core FFI library service — always-on Rust rusqlite backend.
///
/// All read and write ops go directly to the Rust rusqlite DB via FFI.
/// Dart sqflite is no longer involved in any music/CUE path.
///
/// ## Schema gap notes
/// The Rust `LibraryTrack` JSON uses snake_case field names (`account_id`,
/// `remote_path`, …) that differ slightly from the Dart sqflite map keys
/// (`source_name`, `file_name`, …).  The [_rustJsonToTrack] helper bridges
/// the gap by accepting both naming conventions; `source_name` wins over
/// `account_id` when both are present.
///
/// Fields that do not exist in the Rust schema (cover_path, bitrate,
/// sample_rate, cue_*, cache_group_id, remote_missing) are filled with safe
/// defaults so the resulting LibraryTrack works correctly in the Dart UI.
class RustLibraryService {
  RustLibraryService._();

  // ── Read ops ────────────────────────────────────────────────────────────────

  /// List all tracks from the Rust rusqlite DB.
  ///
  /// Returns `null` when the native library is unavailable — throws
  /// [StateError] (no Dart fallback).
  ///
  /// Never throws.
  static List<LibraryTrack>? listAll() {
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
  /// Returns an empty list on a genuine zero-hit search.
  ///
  /// Never throws.
  static List<LibraryTrack>? search(String query) {
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
  /// Returns `null` when the track is not found or the library is unavailable.
  ///
  /// Never throws.
  static LibraryTrack? getById(String id) {
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
  /// Returns the result string from FFI (`'ok'` on success, `'error:…'` on
  /// failure), or `null` when the native library is unavailable.
  ///
  /// CUE slice tracks are routed to [upsertCueSlice] when [track.isCueVirtual]
  /// is true.  Regular tracks use the track table.
  ///
  /// Never throws.
  static String? upsertTrack(LibraryTrack track) {

    // Route CUE virtuals to the CUE upsert path
    if (track.isCueVirtual) {
      final sliceJson = cueSliceJson(track);
      if (sliceJson == null) {
        debugPrint('[RustLibraryService] upsertTrack: CUE slice missing required fields');
        return null;
      }
      return upsertCueSlice(jsonEncode(sliceJson));
    }

    // Regular track path
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
  /// No-op when [musicId] is null/empty or the library is unavailable.
  ///
  /// Never throws.
  static String? deleteTrack(String? musicId) {
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
  /// No-op when [accountId] is null/empty or the library is unavailable.
  ///
  /// Never throws.
  static String? deleteTracksBySource(String? accountId) {
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
  /// No-op when the library is unavailable.
  ///
  /// Never throws.
  static String? clearLibraryAll() {
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
  /// No-op when the library is unavailable.
  ///
  /// Never throws.
  static String? clearLibraryIndex() {
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
  /// No-op when [musicId] is null/empty or the library is unavailable.
  ///
  /// Never throws.
  static String? deleteCueSlice(String? musicId) {
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
  /// No-op when parameters are null/empty.
  ///
  /// Never throws.
  static String? deleteCueAlbum(String? sourceName, String? cueRemotePath) {
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
  /// the library is unavailable.
  ///
  /// Never throws.
  static String? listCueRemainingSlices(String? sourceName, String? cueRemotePath) {
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

  /// Get a track (or CUE slice) by source name and remote path.
  ///
  /// The FFI export tries `tracks` first; on miss it tries `cue_slices`.
  /// Returns a [LibraryTrack] on hit, `null` on miss or error.
  ///
  /// CUE slice JSON (discriminant: has `music_id` + `cue_id`) is decoded via
  /// [LibraryTrack.fromMap] which populates all CUE fields.  Track JSON is
  /// decoded via [_rustJsonToTrack].
  ///
  /// Never throws.
  static LibraryTrack? getBySourcePath(String sourceName, String remotePath) {
    final json = RustCoreService.trackGetBySourcePath(sourceName, remotePath);
    if (json == null || json == 'null' || json.startsWith('error:')) {
      if (json != null && json != 'null') {
        debugPrint('[RustLibraryService] getBySourcePath("$sourceName", "$remotePath") error: $json');
      }
      return null;
    }
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      // Discriminate: CueSlice has `music_id`+`cue_id`; LibraryTrack has `id`+`account_id`.
      if (map.containsKey('music_id') && map.containsKey('cue_id')) {
        final track = LibraryTrack.fromMap(map);
        // CueSlice JSON omits cue_remote_path; fill from parent album.
        if (track.cueRemotePath == null || track.cueRemotePath!.isEmpty) {
          final album = cueAlbumForSlice(track.musicId);
          final cueRemote = album?['cue_remote_path'] as String?;
          if (cueRemote != null && cueRemote.isNotEmpty) {
            track.cueRemotePath = cueRemote;
            track.cacheGroupId ??= album?['cache_group_id'] as String?;
          }
        }
        return track;
      }
      return _rustJsonToTrack(map);
    } catch (e) {
      debugPrint('[RustLibraryService] getBySourcePath decode error: $e');
      return null;
    }
  }

  /// Get the CUE album that owns the slice with [musicId].
  ///
  /// Returns the raw album map on hit, `null` on miss or error.
  ///
  /// Never throws.
  static Map<String, dynamic>? cueAlbumForSlice(String musicId) {
    final json = RustCoreService.cueAlbumForSlice(musicId);
    if (json == null || json == 'null' || json.startsWith('error:')) {
      if (json != null && json != 'null') {
        debugPrint('[RustLibraryService] cueAlbumForSlice("$musicId") error: $json');
      }
      return null;
    }
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[RustLibraryService] cueAlbumForSlice decode error: $e');
      return null;
    }
  }

  /// List all CUE slices for [cueId], ordered by track_index ASC.
  ///
  /// Returns a list of [LibraryTrack] on success (may be empty), `null` on
  /// error.
  ///
  /// Never throws.
  static List<LibraryTrack>? slicesForCue(String cueId) {
    final json = RustCoreService.cueSlicesForCue(cueId);
    if (json == null || json.startsWith('error:')) {
      if (json != null) {
        debugPrint('[RustLibraryService] slicesForCue("$cueId") error: $json');
      }
      return null;
    }
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return null;
      final slices = raw
          .whereType<Map<String, dynamic>>()
          .map(LibraryTrack.fromMap)
          .toList();
      // Core CueSlice JSON has no cue_remote_path (lives on cue_albums).
      // Hydrate once from album so isCueVirtual / cueRelation match sqflite.
      if (slices.isNotEmpty &&
          (slices.first.cueRemotePath == null ||
              slices.first.cueRemotePath!.isEmpty)) {
        final album = cueAlbumForSlice(slices.first.musicId);
        final cueRemote = album?['cue_remote_path'] as String?;
        if (cueRemote != null && cueRemote.isNotEmpty) {
          for (final s in slices) {
            s.cueRemotePath ??= cueRemote;
            s.cacheGroupId ??= album?['cache_group_id'] as String?;
          }
        }
      }
      return slices;
    } catch (e) {
      debugPrint('[RustLibraryService] slicesForCue decode error: $e');
      return null;
    }
  }

  /// Upsert a CUE slice into the Rust rusqlite DB.
  ///
  /// No-op when [sliceJson] is null/empty.
  ///
  /// Never throws.
  static String? upsertCueSlice(String? sliceJson) {
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
  /// No-op when [albumJson] is null/empty.
  ///
  /// Never throws.
  static String? upsertCueAlbum(String? albumJson) {
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

  /// List all CUE albums from the Rust rusqlite DB.
  ///
  /// Returns the raw Core JSON maps (snake_case CueAlbum shape: `cue_id`,
  /// `source_name`, `cue_remote_path`, `title`, `performer`,
  /// `cache_group_id`, `created_at`).
  ///
  /// Throws [StateError] when Core FFI is unavailable or returns an error —
  /// same hard-fail policy as [listAll] (backup export must not silently fall
  /// back to an empty library). Never throws otherwise.
  static List<Map<String, dynamic>> listCueAlbums() {
    final json = RustCoreService.listCueAlbums();
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] listCueAlbums failed: $json');
      throw StateError('RustLibraryService.listCueAlbums failed: $json');
    }
    try {
      final raw = jsonDecode(json);
      if (raw is! List) {
        throw StateError('RustLibraryService.listCueAlbums: expected array');
      }
      return [
        for (final e in raw)
          Map<String, dynamic>.from(e as Map),
      ];
    } catch (e) {
      debugPrint('[RustLibraryService] listCueAlbums decode error: $e');
      throw StateError('RustLibraryService.listCueAlbums decode: $e');
    }
  }

  // ── Schema v6 — deleted_tracks + sync_state write ops ──────────────────────

  /// Upsert a deleted track tombstone.
  ///
  /// No-op when [json] is null/empty.
  /// Never throws.
  static String? deletedTrackUpsert(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final result = RustCoreService.deletedTrackUpsert(json);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deletedTrackUpsert failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deletedTrackUpsert exception: $e');
      return null;
    }
  }

  /// Clear a deleted track tombstone by source and remote path.
  ///
  /// No-op when parameters are null/empty. Never throws.
  static String? deletedTrackClear(String? sourceName, String? remotePath) {
    if (sourceName == null || sourceName.isEmpty) return null;
    if (remotePath == null || remotePath.isEmpty) return null;
    try {
      final result = RustCoreService.deletedTrackClear(sourceName, remotePath);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deletedTrackClear("$sourceName", "$remotePath") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deletedTrackClear exception: $e');
      return null;
    }
  }

  /// List all deleted tracks from the Rust DB.
  ///
  /// Returns `null` when the library is unavailable (throws). Never throws.
  static String? deletedTracksList() {
    try {
      final result = RustCoreService.deletedTracksList();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deletedTracksList failed: $result');
        throw StateError('RustLibraryService.deletedTracksList failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deletedTracksList exception: $e');
      rethrow;
    }
  }

  /// List unpushed deleted tracks (pushed=0).
  ///
  /// Returns `null` when the library is unavailable (throws). Never throws.
  static String? deletedTracksUnpushed() {
    try {
      final result = RustCoreService.deletedTracksUnpushed();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deletedTracksUnpushed failed: $result');
        throw StateError('RustLibraryService.deletedTracksUnpushed failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deletedTracksUnpushed exception: $e');
      rethrow;
    }
  }

  /// Mark deleted tracks as pushed by revision numbers.
  ///
  /// No-op when [revsJson] is null/empty. Never throws.
  static String? deletedTracksMarkPushed(String? revsJson) {
    if (revsJson == null || revsJson.isEmpty) return null;
    try {
      final result = RustCoreService.deletedTracksMarkPushed(revsJson);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deletedTracksMarkPushed failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deletedTracksMarkPushed exception: $e');
      return null;
    }
  }

  /// Purge pushed deleted tracks up to and including the given revision.
  ///
  /// Never throws.
  static String? deletedTracksPurgeUpTo(int upTo) {
    try {
      final result = RustCoreService.deletedTracksPurgeUpTo(upTo);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] deletedTracksPurgeUpTo($upTo) failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] deletedTracksPurgeUpTo exception: $e');
      return null;
    }
  }

  /// Get tombstoned remote paths for a source.
  ///
  /// Returns `null` when the library is unavailable (throws). Never throws.
  static String? tombstonedRemotePaths(String? sourceName) {
    if (sourceName == null || sourceName.isEmpty) return null;
    try {
      final result = RustCoreService.tombstonedRemotePaths(sourceName);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] tombstonedRemotePaths("$sourceName") failed: $result');
        throw StateError('RustLibraryService.tombstonedRemotePaths failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] tombstonedRemotePaths exception: $e');
      rethrow;
    }
  }

  /// Get sync state by remote key.
  ///
  /// Returns `null` when the library is unavailable (throws). Never throws.
  static String? syncStateGet(String? remoteKey) {
    if (remoteKey == null || remoteKey.isEmpty) return null;
    try {
      final result = RustCoreService.syncStateGet(remoteKey);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] syncStateGet("$remoteKey") failed: $result');
        throw StateError('RustLibraryService.syncStateGet failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] syncStateGet exception: $e');
      rethrow;
    }
  }

  /// Save sync state from JSON.
  ///
  /// No-op when [json] is null/empty.
  /// Never throws.
  static String? syncStateSave(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final result = RustCoreService.syncStateSave(json);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] syncStateSave failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] syncStateSave exception: $e');
      return null;
    }
  }

  /// Clear sync state by optional prefix.
  ///
  /// Never throws.
  static String? syncStateClear([String? prefix]) {
    try {
      final result = RustCoreService.syncStateClear(prefix);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] syncStateClear("$prefix") failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] syncStateClear exception: $e');
      return null;
    }
  }

  // ── Schema v7+v8 — Aggregates + FTS5 ───────────────────────────────────────

  /// List all artists.
  ///
  /// Returns a JSON array of artist objects, or null on error. Never throws.
  static String? listArtists() {
    try {
      final result = RustCoreService.artistList();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] listArtists failed: $result');
        throw StateError('RustLibraryService.listArtists failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] listArtists exception: $e');
      rethrow;
    }
  }

  /// Get one artist by name.
  ///
  /// Returns a JSON object, "null" if absent, or throws on error. Never throws.
  static String? getArtist(String name) {
    try {
      final result = RustCoreService.artistGet(name);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] getArtist("$name") failed: $result');
        throw StateError('RustLibraryService.getArtist failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] getArtist exception: $e');
      rethrow;
    }
  }

  /// List all albums.
  ///
  /// Returns a JSON array of album objects, or null on error. Never throws.
  static String? listAlbums() {
    try {
      final result = RustCoreService.albumList();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] listAlbums failed: $result');
        throw StateError('RustLibraryService.listAlbums failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] listAlbums exception: $e');
      rethrow;
    }
  }

  /// Get one album by title.
  ///
  /// Returns a JSON object, "null" if absent, or throws on error. Never throws.
  static String? getAlbum(String title) {
    try {
      final result = RustCoreService.albumGet(title);
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] getAlbum("$title") failed: $result');
        throw StateError('RustLibraryService.getAlbum failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] getAlbum exception: $e');
      rethrow;
    }
  }

  /// List tracks by artist name.
  ///
  /// Returns a list of [LibraryTrack], or throws on error.
  static List<LibraryTrack>? tracksByArtist(String name) {
    final json = RustCoreService.tracksByArtist(name);
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] tracksByArtist("$name") failed: $json');
      throw StateError('RustLibraryService.tracksByArtist failed: $json');
    }
    return _decodeArray(json);
  }

  /// List tracks by album title.
  ///
  /// Returns a list of [LibraryTrack], or throws on error.
  static List<LibraryTrack>? tracksByAlbum(String title) {
    final json = RustCoreService.tracksByAlbum(title);
    if (json == null || json.startsWith('error:')) {
      debugPrint('[RustLibraryService] tracksByAlbum("$title") failed: $json');
      throw StateError('RustLibraryService.tracksByAlbum failed: $json');
    }
    return _decodeArray(json);
  }

  /// Rebuild artist and album aggregates.
  ///
  /// Never throws.
  static String? rebuildAggregates() {
    try {
      final result = RustCoreService.libraryRebuildAggregates();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] rebuildAggregates failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] rebuildAggregates exception: $e');
      return null;
    }
  }

  /// Rebuild FTS5 search index.
  ///
  /// Never throws.
  static String? rebuildFts() {
    try {
      final result = RustCoreService.libraryRebuildFts();
      if (result != null && result.startsWith('error:')) {
        debugPrint('[RustLibraryService] rebuildFts failed: $result');
      }
      return result;
    } catch (e) {
      debugPrint('[RustLibraryService] rebuildFts exception: $e');
      return null;
    }
  }

  // ── CUE helpers ─────────────────────────────────────────────────────────────

  /// Build a Core-shaped CueAlbum JSON object from a CUE slice track.
  ///
  /// Returns `null` when required fields are missing.
  static Map<String, dynamic>? cueAlbumJson({
    required String cueId,
    required String sourceName,
    required String cueRemotePath,
    String? title,
    String? performer,
    String? cacheGroupId,
    required DateTime createdAt,
  }) {
    if (cueId.isEmpty || sourceName.isEmpty || cueRemotePath.isEmpty) {
      return null;
    }
    return {
      'cue_id': cueId,
      'source_name': sourceName,
      'cue_remote_path': cueRemotePath,
      'title': title,
      'performer': performer,
      'cache_group_id': cacheGroupId,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  /// Build a Core-shaped CueSlice JSON object from a LibraryTrack.
  ///
  /// Returns `null` when the track is not a CUE virtual or required fields are
  /// missing.
  static Map<String, dynamic>? cueSliceJson(LibraryTrack track) {
    if (!track.isCueVirtual) return null;
    if (track.cueId == null || track.cueId!.isEmpty) return null;
    if (track.audioMusicId == null || track.audioMusicId!.isEmpty) {
      // Derive audio_music_id like sqflite _upsertCueSlice does
      if (track.audioRemotePath == null || track.audioRemotePath!.isEmpty) {
        return null;
      }
    }
    final audioMid = track.audioMusicId ??
        musicIdForRemote(track.sourceName, track.audioRemotePath!);
    return {
      'music_id': track.musicId,
      'cue_id': track.cueId,
      'audio_music_id': audioMid,
      'source_name': track.sourceName,
      'remote_path': track.remotePath,
      'file_name': track.fileName,
      'track_index': track.cueTrackIndex ?? 0,
      'title': track.title,
      'artist': track.artist,
      'album_artist': track.albumArtist,
      'album': track.album,
      'duration_ms': track.durationMs,
      'track_number': track.trackNumber,
      'track_total': track.trackTotal,
      'disc_number': track.discNumber,
      'disc_total': track.discTotal,
      'year': track.year,
      'genre': track.genre,
      'bitrate': track.bitrate,
      'sample_rate': track.sampleRate,
      'cover_state': track.coverState,
      'audio_remote_path': track.audioRemotePath,
      'clip_start_ms': track.clipStartMs,
      'clip_end_ms': track.clipEndMs,
      'cache_group_id': track.cacheGroupId,
      'rev': track.rev ?? 0,
      'last_downloaded_at': track.lastDownloadedAt.toUtc().toIso8601String(),
      'last_tag_read_at': track.lastTagReadAt.toUtc().toIso8601String(),
      'remote_missing': track.remoteMissing ? 1 : 0,
    };
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
  /// columns, cover_state, bitrate, …) are filled with 0 / defaults.
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
        albumArtist: map['album_artist'] as String?,
        album: map['album'] as String?,
        durationMs: _asInt(map['duration_ms']),
        trackNumber: _asInt(map['track_number']),
        discNumber: _asInt(map['disc_number']),
        year: _asInt(map['year']),
        genre: map['genre'] as String?,
        // Fields with no Rust equivalent — safe defaults:
        bitrate: null,
        sampleRate: null,
        coverState: 0,
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
    if (id.isEmpty) return null;
    return {
      'id': id,
      // Rust schema requires a non-empty title; fall back to the file name.
      'title': (track.title?.isNotEmpty ?? false) ? track.title! : track.fileName,
      'artist': track.artist,
      'album': track.album,
      'album_artist': track.albumArtist,
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
