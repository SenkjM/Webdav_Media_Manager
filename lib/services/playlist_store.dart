import 'dart:convert';

import '../models/playlist.dart';
import 'rust_core_service.dart';

/// Local playlist persistence.
///
/// The Rust core owns both halves: the playlist spine (id / name / timestamps)
/// and the ordered entry rows, including `cueTrackIndex` / `remoteMissing`. The
/// cloud sync engine reads those very tables, so nothing is mirrored into the
/// KV store any more — a second copy would only go stale after a native pull.
class PlaylistStore {
  /// On-disk name kept for [LocalDatabaseRecoveryService] / backups that still
  /// reference it; the file is no longer opened by this store.
  static const fileName = 'playlists.db';

  Future<List<Playlist>> loadAll() async {
    final raw = RustCoreService.playlistList();
    if (raw == null || raw.startsWith('error:')) {
      // FFI unavailable (non-Android / library not loaded). Return empty so the
      // UI degrades gracefully; a later sync pull repopulates from the cloud.
      return [];
    }
    final list = jsonDecode(raw) as List<dynamic>;
    final playlists = <Playlist>[];
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = m['id'] as String? ?? '';
      if (id.isEmpty) continue;
      playlists.add(_load(id, m));
    }
    return playlists;
  }

  Future<void> upsert(Playlist playlist) async {
    // The spine carries `updated_at` because Core's sync merge is
    // last-write-wins on it; an edit means "now".
    final spine = jsonEncode({
      'id': playlist.id,
      'name': playlist.name,
      'updated_at': playlist.updatedAt.toUtc().toIso8601String(),
    });
    final res = RustCoreService.playlistCreate(spine);
    if (res == null || res.startsWith('error:')) {
      // FFI unavailable: in-memory only. The caller still holds the object.
      return;
    }
    final arr = <Map<String, dynamic>>[
      for (final e in playlist.entries)
        {
          'music_id': e.musicId ?? '',
          'source_name': e.sourceName,
          'remote_path': e.remotePath,
          'title': e.title ?? '',
          'duration_ms': e.durationMs ?? 0,
          'cue_track_index': e.cueTrackIndex,
          'remote_missing': e.remoteMissing,
        },
    ];
    // A removed entry becomes an entry tombstone here (Core diffs the rows).
    RustCoreService.playlistSetEntries(playlist.id, jsonEncode(arr));
  }

  Future<void> delete(String id) async {
    // Core records the whole-playlist tombstone inside `wdmm_playlist_delete`.
    RustCoreService.playlistDelete(id);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Playlist _load(String id, Map<String, dynamic> spine) {
    final entriesRaw = RustCoreService.playlistListEntries(id) ?? '[]';
    return Playlist(
      id: id,
      name: spine['name'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(spine['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      entries: _parseFfiEntries(entriesRaw),
    );
  }

  List<PlaylistEntry> _parseFfiEntries(String raw) {
    if (raw.isEmpty || raw == 'null' || raw.startsWith('error:')) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final e in list) _entry(Map<String, dynamic>.from(e as Map)),
    ];
  }

  PlaylistEntry _entry(Map<String, dynamic> m) {
    final musicId = m['music_id'] as String? ?? '';
    final title = m['title'] as String? ?? '';
    return PlaylistEntry(
      sourceName: m['source_name'] as String? ?? '',
      remotePath: m['remote_path'] as String? ?? '',
      musicId: musicId.isEmpty ? null : musicId,
      title: title.isEmpty ? null : title,
      durationMs: (m['duration_ms'] as num?)?.toInt(),
      cueTrackIndex: (m['cue_track_index'] as num?)?.toInt(),
      remoteMissing: m['remote_missing'] == true,
    );
  }

  /// Absolute path of the legacy DB file (kept for backup compatibility; the
  /// file is no longer opened by this store).
  Future<String> databasePath() async => fileName;

  Future<void> close() async {}
}
