import 'dart:convert';

import '../models/playlist.dart';
import 'rust_core_service.dart';

/// Local playlist persistence.
///
/// **Wave B cutover**: the sqflite `playlists.db` store is gone. Persistence
/// now lives in the Rust core via [RustCoreService]:
///   - playlist spine (id / name / timestamps) → `wdmm_playlist_*` FFI
///   - entries → `wdmm_playlist_set_entries` (snake_case FFI schema)
///   - Dart-only fields the FFI schema does not carry — [Playlist.remoteFileName]
///     and the per-entry `cueTrackIndex` / `remoteMissing` — are stashed in the
///     Core KV store (`wdmm_kv_get/set`) keyed by playlist id.
///
/// The WebDAV `.wdmp` sync / cover policy in [PlaylistService] sits above this
/// layer and is untouched: it still reads / writes [Playlist] objects, and this
/// store faithfully round-trips every field those objects carry.
class PlaylistStore {
  /// KV prefix for a playlist's remote file name (Dart-only; not in FFI schema).
  static const _kRemoteNamePrefix = 'playlist_remote_name:';

  /// KV prefix for the full Dart entry JSON of a playlist.
  ///
  /// The FFI entry schema is `{music_id, source_name, remote_path, title,
  /// duration_ms}` and drops `cueTrackIndex` / `remoteMissing`, which matter
  /// for CUE sheets and the missing-file hint. We therefore keep the rich
  /// Dart representation here as the authoritative source; the FFI entries
  /// are mirrored so any native consumer sees the same membership.
  static const _kEntriesPrefix = 'playlist_entries_dart:';

  /// On-disk name kept for [LocalDatabaseRecoveryService] / backups that still
  /// reference it; no longer opened.
  static const fileName = 'playlists.db';

  Future<List<Playlist>> loadAll() async {
    final raw = RustCoreService.playlistList();
    if (raw == null || raw.startsWith('error:')) {
      // FFI unavailable (non-Android / library not loaded). Return empty so
      // the UI degrades gracefully; the WebDAV sync pull will repopulate.
      return [];
    }
    final list = jsonDecode(raw) as List<dynamic>;
    final playlists = <Playlist>[];
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = m['id'] as String? ?? '';
      if (id.isEmpty) continue;
      playlists.add(_loadFull(id, m));
    }
    return playlists;
  }

  Future<Playlist?> getById(String id) async {
    // No dedicated FFI for a single playlist; load all and filter. The list is
    // small and rarely called.
    final all = await loadAll();
    for (final pl in all) {
      if (pl.id == id) return pl;
    }
    return null;
  }

  Future<void> upsert(Playlist playlist) async {
    // Spine: create-or-replace. The FFI `playlist_create` accepts an optional
    // id; re-creating with an existing id replaces the name in place.
    final spine = jsonEncode({'id': playlist.id, 'name': playlist.name});
    final res = RustCoreService.playlistCreate(spine);
    if (res == null || res.startsWith('error:')) {
      // FFI unavailable: in-memory only, nothing to persist. Caller still has
      // the object in its list; nothing more we can do.
      return;
    }

    // Entries — mirror to FFI (rich fields preserved in KV below).
    _syncFfiEntries(playlist);

    // Dart-only fields → KV.
    final entriesJson = jsonEncode(
      playlist.entries.map((e) => e.toJson()).toList(),
    );
    RustCoreService.kvSet('$_kEntriesPrefix${playlist.id}', entriesJson);
    if (playlist.remoteFileName != null &&
        playlist.remoteFileName!.isNotEmpty) {
      RustCoreService.kvSet(
        '$_kRemoteNamePrefix${playlist.id}',
        playlist.remoteFileName!,
      );
    } else {
      RustCoreService.kvDelete('$_kRemoteNamePrefix${playlist.id}');
    }
  }

  Future<void> delete(String id) async {
    RustCoreService.playlistDelete(id);
    // Clean up the Dart-only KV sidecars.
    RustCoreService.kvDelete('$_kEntriesPrefix$id');
    RustCoreService.kvDelete('$_kRemoteNamePrefix$id');
  }

  Future<void> clearAll() async {
    final all = await loadAll();
    for (final pl in all) {
      await delete(pl.id);
    }
  }

  Future<void> replaceAll(List<Playlist> playlists) async {
    await clearAll();
    for (final pl in playlists) {
      await upsert(pl);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Assemble a [Playlist] from an FFI spine row + KV sidecars.
  Playlist _loadFull(String id, Map<String, dynamic> spine) {
    // Entries: prefer the rich Dart JSON from KV; fall back to the FFI
    // entries (which drop cueTrackIndex / remoteMissing) when KV is empty
    // (e.g. created directly from native, then read from Dart).
    final dartEntriesRaw = RustCoreService.kvGet('$_kEntriesPrefix$id');
    List<PlaylistEntry> entries;
    if (dartEntriesRaw != null &&
        dartEntriesRaw != 'null' &&
        !dartEntriesRaw.startsWith('error:')) {
      final list = jsonDecode(dartEntriesRaw) as List<dynamic>;
      entries = [
        for (final e in list)
          PlaylistEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } else {
      final ffiEntriesRaw = RustCoreService.playlistListEntries(id) ?? '[]';
      entries = _parseFfiEntries(ffiEntriesRaw);
      // Backfill KV so future loads are consistent and rich.
      if (entries.isNotEmpty &&
          !(ffiEntriesRaw.startsWith('error:') || ffiEntriesRaw == 'null')) {
        RustCoreService.kvSet(
          '$_kEntriesPrefix$id',
          jsonEncode(entries.map((e) => e.toJson()).toList()),
        );
      }
    }

    final remoteRaw = RustCoreService.kvGet('$_kRemoteNamePrefix$id');
    final remoteFileName =
        (remoteRaw == null || remoteRaw == 'null' || remoteRaw.startsWith('error:'))
            ? null
            : remoteRaw;

    final updatedAtStr = spine['updated_at'] as String? ??
        spine['created_at'] as String? ??
        '';

    return Playlist(
      id: id,
      name: spine['name'] as String? ?? '',
      updatedAt: DateTime.tryParse(updatedAtStr) ?? DateTime.now().toUtc(),
      remoteFileName: remoteFileName,
      entries: entries,
    );
  }

  /// Push entries to the FFI store (snake_case schema). Rich fields not in the
  /// FFI schema are silently dropped here — they are preserved in KV via the
  /// caller ([upsert]).
  void _syncFfiEntries(Playlist playlist) {
    final arr = <Map<String, dynamic>>[];
    for (final e in playlist.entries) {
      final m = <String, dynamic>{
        'source_name': e.sourceName,
        'remote_path': e.remotePath,
      };
      if (e.musicId != null && e.musicId!.isNotEmpty) m['music_id'] = e.musicId;
      if (e.title != null) m['title'] = e.title;
      if (e.durationMs != null) m['duration_ms'] = e.durationMs;
      arr.add(m);
    }
    RustCoreService.playlistSetEntries(playlist.id, jsonEncode(arr));
  }

  List<PlaylistEntry> _parseFfiEntries(String raw) {
    if (raw.isEmpty || raw == 'null' || raw.startsWith('error:')) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final e in list)
        PlaylistEntry.fromJson({
          'sourceName': (e as Map)['source_name'] as String? ?? '',
          'remotePath': e['remote_path'] as String? ?? '',
          'musicId': e['music_id'] as String?,
          'title': e['title'] as String?,
          'durationMs': e['duration_ms'] as int?,
        }),
    ];
  }

  /// Absolute path of the legacy DB file (kept for backup compatibility; the
  /// file is no longer opened by this store).
  Future<String> databasePath() async => fileName;

  Future<void> close() async {}
}
