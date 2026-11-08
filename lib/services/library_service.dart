import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/library_sentinels.dart';
import '../models/library_track.dart';
import 'cover_service.dart';
import 'rust_core_service.dart';
import 'rust_library_service.dart';
import 'tag_service.dart';

/// Local music library: indexes tracks that have been cached at least once.
/// Metadata + cover thumbs persist across audio-cache deletion.
class LibraryService extends ChangeNotifier {
  /// Next revision for a locally-created or locally-changed row.
  ///
  /// Rust owns the single sync clock (library_rev_watermark); a Dart-side
  /// monotonic clock would let a local edit look older than a peer's write and
  /// lose the last-write-wins comparison. Falls back to the wall clock only when
  /// the native library is unavailable.
  int _nextRev() =>
      RustLibraryService.nextRev() ?? DateTime.now().millisecondsSinceEpoch;

  /// Record a tombstone so a destroyed song is not pulled back by sync.
  ///
  /// Only *destruction* / removal writes one: dropping just the audio cache keeps
  /// the metadata and the song stays in the library.
  Future<void> recordTombstone(String sourceName, String remotePath) async {
    final rev = _nextRev();
    final json = jsonEncode({
      'source_name': sourceName,
      'remote_path': remotePath,
      'rev': rev,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'pushed': 0,
    });
    final result = RustLibraryService.deletedTrackUpsert(json);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust deleted_track upsert failed: $result');
    }
  }

  LibraryService({TagService? tags, CoverService? covers})
    : _tags = tags ?? TagService(),
      _covers = covers ?? CoverService();

  final TagService _tags;
  final CoverService _covers;

  final List<LibraryTrack> _tracks = [];
  bool _loaded = false;

  UnmodifiableListView<LibraryTrack> get tracks =>
      UnmodifiableListView(_tracks);

  /// Test-only: seed in-memory tracks without opening SQLite.
  @visibleForTesting
  void debugSetTracksForTest(List<LibraryTrack> tracks) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _loaded = true;
  }

  bool get loaded => _loaded;
  int get count => _tracks.length;

  CoverService get covers => _covers;
  TagService get tags => _tags;

  Future<void> init() async {
    await _covers.init();
    await refresh();
  }

  Future<void> refresh() async {
    final rustTracks = RustLibraryService.listAll();
    if (rustTracks == null) {
      throw StateError(
        'Rust library read failed; Dart sqflite fallback removed',
      );
    }
    _tracks
      ..clear()
      ..addAll(rustTracks);
    _loaded = true;
    notifyListeners();
  }

  List<LibraryTrack> tracksForSource(String sourceName) =>
      _tracks.where((t) => t.sourceName == sourceName).toList();

  /// Upsert tracks from a sync/backup payload; only touches listed rows.
  Future<void> upsertTracks(Iterable<LibraryTrack> tracks) async {
    for (final track in tracks) {
      // Rust-only write: sqflite dual-path removed per Round 11 cutover.
      final result = RustLibraryService.upsertTrack(track);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
      final idx = _tracks.indexWhere(
        (t) =>
            t.musicId == track.musicId ||
            (t.sourceName == track.sourceName &&
                t.remotePath == track.remotePath),
      );
      if (idx >= 0) {
        _tracks[idx] = track;
      } else {
        _tracks.add(track);
      }
    }
    notifyListeners();
  }

  /// Replace all local tracks for [sourceName] with [tracks] (other accounts untouched).
  Future<void> replaceTracksForAccount(
    String sourceName,
    List<LibraryTrack> tracks,
  ) async {
    // Rust: delete all tracks for this account in one call
    final result = RustLibraryService.deleteTracksBySource(sourceName);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library delete-by-source failed; sqflite fallback removed: $result');
    }
    _tracks.removeWhere((t) => t.sourceName == sourceName);
    for (final track in tracks) {
      final upsertResult = RustLibraryService.upsertTrack(track);
      if (upsertResult != null && upsertResult.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $upsertResult');
      }
      _tracks.add(track);
    }
    notifyListeners();
  }

  LibraryTrack? find(String sourceName, String remotePath) {
    try {
      return _tracks.firstWhere(
        (t) => t.sourceName == sourceName && t.remotePath == remotePath,
      );
    } catch (_) {
      return null;
    }
  }

  LibraryTrack? findByMusicId(String musicId) {
    try {
      return _tracks.firstWhere((t) => t.musicId == musicId);
    } catch (_) {
      return null;
    }
  }

  /// Bidirectional CUE: slice → cue album + audio music_id.
  Future<Map<String, dynamic>?> cueRelationForSlice(LibraryTrack track) async {
    if (!track.isCueVirtual) return null;
    final coreAlbum = RustLibraryService.cueAlbumForSlice(track.musicId);
    if (coreAlbum == null) {
      throw StateError(
        'Rust CUE album lookup failed; sqflite fallback removed (musicId=${track.musicId})',
      );
    }
    final cueId = coreAlbum['cue_id'] as String;
    final coreSlices = RustLibraryService.slicesForCue(cueId);
    if (coreSlices == null) {
      throw StateError(
        'Rust CUE slices lookup failed; sqflite fallback removed (cueId=$cueId)',
      );
    }
    return {
      'cueId': cueId,
      'cueRemotePath': coreAlbum['cue_remote_path'],
      'audioMusicId': track.audioMusicId ?? track.cacheMusicId,
      'audioRemotePath': track.audioRemotePath,
      'sliceMusicIds': coreSlices.map((s) => s.musicId).toList(),
    };
  }

  /// Bidirectional CUE: cue → original audio + slice music_ids.
  Future<Map<String, dynamic>?> cueRelationForCueId(String cueId) async {
    final coreSlices = RustLibraryService.slicesForCue(cueId);
    if (coreSlices == null) {
      throw StateError(
        'Rust CUE slices lookup failed; sqflite fallback removed (cueId=$cueId)',
      );
    }
    if (coreSlices.isEmpty) return null;
    final first = coreSlices.first;
    return {
      'cueId': cueId,
      'cueRemotePath': first.cueRemotePath,
      'audioMusicId': first.audioMusicId ?? first.cacheMusicId,
      'audioRemotePath': first.audioRemotePath,
      'sliceMusicIds': coreSlices.map((s) => s.musicId).toList(),
      'slices': coreSlices,
    };
  }

  Future<void> markRemoteMissing({
    required String sourceName,
    required String remotePath,
    bool hasLocalCache = false,
  }) async {
    if (hasLocalCache) return;
    final existing = find(sourceName, remotePath);
    if (existing == null) return;
    if (existing.remoteMissing) return;
    existing.remoteMissing = true;
    existing.rev = _nextRev();
    final result = RustLibraryService.upsertTrack(existing);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
    }
    notifyListeners();
  }

  Future<void> clearRemoteMissing({
    required String sourceName,
    required String remotePath,
  }) async {
    final existing = find(sourceName, remotePath);
    if (existing == null || !existing.remoteMissing) return;
    existing.remoteMissing = false;
    existing.rev = _nextRev();
    final result = RustLibraryService.upsertTrack(existing);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
    }
    notifyListeners();
  }

  /// Point a library row at a new remote path (redirect after missing).

  /// Persist a new [CoverState] value for a track.
  ///
  /// Rev is bumped **only** when the value changes — rewriting the thumb bytes
  /// at the same `present` state does not bump rev.
  Future<void> setCoverState({
    required String sourceName,
    required String remotePath,
    required int state,
  }) async {
    final existing = find(sourceName, remotePath);
    if (existing == null) return;
    if (existing.coverState == state) return;
    existing.coverState = state;
    existing.rev = _nextRev();
    final result = RustLibraryService.upsertTrack(existing);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
    }
    notifyListeners();
  }

  Future<LibraryTrack> retargetTrack({
    required LibraryTrack track,
    required String newRemotePath,
    String? newFileName,
  }) async {
    final name = newFileName ?? newRemotePath.split('/').where((s) => s.isNotEmpty).last;
    final deleteResult = RustLibraryService.deleteTrack(track.musicId);
    if (deleteResult != null && deleteResult.startsWith('error:')) {
      throw StateError('Rust library delete failed; sqflite fallback removed: $deleteResult');
    }
    _tracks.removeWhere(
      (t) => t.sourceName == track.sourceName && t.remotePath == track.remotePath,
    );
    final next = LibraryTrack(
      sourceName: track.sourceName,
      remotePath: newRemotePath,
      fileName: name.isEmpty ? track.fileName : name,
      title: track.title,
      artist: track.artist,
      albumArtist: track.albumArtist,
      album: track.album,
      durationMs: track.durationMs,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      discNumber: track.discNumber,
      discTotal: track.discTotal,
      year: track.year,
      genre: track.genre,
      bitrate: track.bitrate,
      sampleRate: track.sampleRate,
      coverState: track.coverState,
      cacheGroupId: track.cacheGroupId,
      rev: _nextRev(),
      lastDownloadedAt: track.lastDownloadedAt,
      lastTagReadAt: track.lastTagReadAt,
      remoteMissing: false,
    );
    final upsertResult = RustLibraryService.upsertTrack(next);
    if (upsertResult != null && upsertResult.startsWith('error:')) {
      throw StateError('Rust library upsert failed; sqflite fallback removed: $upsertResult');
    }
    _tracks.add(next);
    notifyListeners();
    return next;
  }

  /// Upsert tags (and optional cover) without requiring a local audio file.
  ///
  /// Used after HTTP Range / stream tag reads. Does **not** bump
  /// [LibraryTrack.lastDownloadedAt] — a later [ingestDownloaded] still
  /// overwrites tags and records the download time.

  /// Ingest one remote file through the Rust executor.
  ///
  /// Tags, CUE sheets, sidecar covers and identity hashing all live in
  /// `wdmm_library_ingest`; Dart keeps only the in-memory projection, so a scan
  /// item and a manual re-read write exactly the same row.
  Future<LibraryTrack?> ingestRemoteFile({
    required String accountId,
    required String sourceName,
    required String remotePath,
    required String fileName,
  }) => _ingestThroughCore(
    accountId: accountId,
    sourceName: sourceName,
    remotePath: remotePath,
    fileName: fileName,
  );

  /// Re-read the tags of an already cached file through the Rust executor.
  Future<LibraryTrack?> ingestCachedFile({
    required String accountId,
    required String sourceName,
    required String remotePath,
    required String fileName,
    required String localPath,
  }) => _ingestThroughCore(
    accountId: accountId,
    sourceName: sourceName,
    remotePath: remotePath,
    fileName: fileName,
    localPath: localPath,
  );

  Future<LibraryTrack?> _ingestThroughCore({
    required String accountId,
    required String sourceName,
    required String remotePath,
    required String fileName,
    String? localPath,
  }) async {
    final reply = await RustCoreService.libraryIngestAsync(
      jsonEncode({
        'account_id': accountId,
        'source_name': sourceName,
        'remote_path': remotePath,
        'file_name': fileName,
        'local_path': ?localPath,
      }),
    );
    if (reply == null) {
      throw StateError('Core FFI unavailable — cannot ingest $remotePath');
    }
    if (reply.startsWith('error:')) {
      throw StateError('Core ingest failed: $reply');
    }
    await refresh();
    return find(sourceName, remotePath);
  }
  /// Case-insensitive search over title / artist / album / file name.
  List<LibraryTrack> search(
    String query, {
    LibrarySortMode sort = LibrarySortMode.byName,
  }) {
    final rustResult = RustLibraryService.search(query);
    if (rustResult == null) {
      throw StateError(
        'Rust library search failed; Dart fallback removed',
      );
    }
    rustResult.sort(
      sort == LibrarySortMode.byAlbumTrack
          ? compareTracksByAlbumOrder
          : compareTracksByName,
    );
    return rustResult;
  }

  /// Distinct non-empty genre values, sorted (case-insensitive unique).
  List<String> allGenres() {
    final byLower = <String, String>{};
    for (final t in _tracks) {
      final g = t.genre?.trim();
      if (g == null || g.isEmpty) continue;
      byLower.putIfAbsent(g.toLowerCase(), () => g);
    }
    final list = byLower.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Tracks matching a genre tag (exact, case-insensitive).
  List<LibraryTrack> tracksWithGenre(
    String genre, {
    LibrarySortMode sort = LibrarySortMode.byName,
  }) {
    final g = genre.trim().toLowerCase();
    final list = isUncategorizedGenre(genre)
        ? _tracks.where((t) => (t.genre ?? '').trim().isEmpty).toList()
        : _tracks
              .where((t) => (t.genre ?? '').trim().toLowerCase() == g)
              .toList();
    list.sort(
      sort == LibrarySortMode.byAlbumTrack
          ? compareTracksByAlbumOrder
          : compareTracksByName,
    );
    return list;
  }

  /// Group tracks by genre for the tags browser (empty genre → sentinel).
  Map<String, List<LibraryTrack>> groupedByGenre() {
    final map = <String, List<LibraryTrack>>{};
    final keyByLower = <String, String>{};
    for (final t in _tracks) {
      final g = t.genre?.trim();
      final String key;
      if (g == null || g.isEmpty) {
        key = kUncategorizedGenre;
      } else {
        key = keyByLower.putIfAbsent(g.toLowerCase(), () => g);
      }
      map.putIfAbsent(key, () => []).add(t);
    }
    for (final e in map.entries) {
      e.value.sort(compareTracksByName);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (isUncategorizedGenre(a)) return 1;
        if (isUncategorizedGenre(b)) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return LinkedHashMap.fromEntries(keys.map((k) => MapEntry(k, map[k]!)));
  }

  List<LibraryTrack> byTitle({LibrarySortMode sort = LibrarySortMode.byName}) {
    final list = List<LibraryTrack>.from(_tracks);
    list.sort(
      sort == LibrarySortMode.byAlbumTrack
          ? compareTracksByAlbumOrder
          : compareTracksByName,
    );
    return list;
  }

  List<LibraryTrack> sortedCopy(
    List<LibraryTrack> source, {
    required LibrarySortMode sort,
  }) {
    final list = List<LibraryTrack>.from(source);
    list.sort(
      sort == LibrarySortMode.byAlbumTrack
          ? compareTracksByAlbumOrder
          : compareTracksByName,
    );
    return list;
  }

  Map<String, List<LibraryTrack>> groupedByArtist() {
    final map = <String, List<LibraryTrack>>{};
    for (final t in _tracks) {
      map.putIfAbsent(t.displayArtist, () => []).add(t);
    }
    for (final e in map.entries) {
      e.value.sort(compareTracksByName);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return LinkedHashMap.fromEntries(keys.map((k) => MapEntry(k, map[k]!)));
  }

  Map<String, List<LibraryTrack>> groupedByAlbum() {
    final map = <String, List<LibraryTrack>>{};
    for (final t in _tracks) {
      map.putIfAbsent(t.displayAlbum, () => []).add(t);
    }
    // Album detail defaults to disc/track order.
    for (final e in map.entries) {
      e.value.sort(compareTracksByAlbumOrder);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return LinkedHashMap.fromEntries(keys.map((k) => MapEntry(k, map[k]!)));
  }

  /// Destroy the entire local music library: DB track/cue rows, cover thumbs
  /// (and full covers), and in-memory index. Does not touch WebDAV accounts.
  /// Caller should also delete local audio files and clean playlists.
  Future<void> destroyAll() async {
    final result = RustLibraryService.clearLibraryAll();
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library clear-all failed: $result');
    }
    await _covers.deleteAllCovers();
    _tracks.clear();
    notifyListeners();
  }

  /// Hand the index over to the cloud: drop every index row (tracks, CUE,
  /// tombstones, sync cursor) and forget the in-memory list, keeping the runtime
  /// cache tables and the covers.
  ///
  /// The next incremental sync then finds an empty local index and no cursor, so
  /// it re-reads the cloud and adopts the whole library — and because cached
  /// state is derived from disk (v9), rows that have a file on disk come back as
  /// local instead of triggering a second full download.
  Future<void> prepareCloudOverwrite() async {
    final result = RustLibraryService.clearLibraryIndex();
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library clear-index failed: $result');
    }
    _tracks.clear();
    notifyListeners();
  }

  /// Destroy **one** song: its tombstone, its cover art and its library row.
  ///
  /// One song is the atomic unit of destruction — callers loop over songs and
  /// stop *between* them, never inside one. CUE slices share a backing file, so
  /// 每一次调用只删自己那一片，兄弟片各自留各自的墓碑——整组一次性
  /// 清空会让后面几片拿不到墓碑，它们会在下一次从云端拉取时被旧 base 带回来。
  ///
  /// Distinct from [removeTrack] (rows only) and from cache deletion (audio files
  /// only, metadata kept). The audio file itself is the caller's business:
  /// `AppState.destroyLibraryTrack` owns the disk file.
  Future<void> destroyTrack(LibraryTrack track) async {
    // Tombstone first, so a sync that runs while we delete still learns about the
    // removal (and cannot pull the song back).
    await recordTombstone(track.sourceName, track.remotePath);
    await _covers.deleteThumb(track.sourceName, track.remotePath);
    if (track.isCueVirtual && track.cueRemotePath != null) {
      // 逐条：只删这一片。整组一次性清空的话，兄弟片就再也拿不到墓碑，
      // 它们会在下一次从云端拉取时被旧 base 带回来。
      final cuePath = track.cueRemotePath!;
      final result = RustLibraryService.deleteCueSlice(track.musicId);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust CUE slice delete failed: $result');
      }
      _tracks.removeWhere((t) => t.musicId == track.musicId);
      // 整组最后一片走完，专辑行也就没有存在的理由了。
      final slicesJson = RustLibraryService.listCueRemainingSlices(
        track.sourceName,
        cuePath,
      );
      if (slicesJson == null || slicesJson.startsWith('error:')) {
        throw StateError(
          'Rust CUE remaining-slices read failed: ${slicesJson ?? "null"}',
        );
      }
      // Core returns a decimal count string (e.g. "5"), not a JSON array
      final remaining = int.tryParse(slicesJson.trim()) ?? 0;
      if (remaining == 0) {
        final albumResult = RustLibraryService.deleteCueAlbum(
          track.sourceName,
          cuePath,
        );
        if (albumResult != null && albumResult.startsWith('error:')) {
          throw StateError('Rust CUE album delete failed: $albumResult');
        }
      }
    } else {
      final result = RustLibraryService.deleteTrack(track.musicId);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library delete failed; sqflite fallback removed: $result');
      }
      _tracks.removeWhere(
        (t) =>
            t.sourceName == track.sourceName &&
            t.remotePath == track.remotePath,
      );
    }
    notifyListeners();
  }

  /// Loop over [tracks], one atomic [destroyTrack] at a time. Kept for callers
  /// with no progress UI; the screens go through `AppState` so they can report
  /// progress and stop between songs.
  Future<void> destroyTracks(Iterable<LibraryTrack> tracks) async {
    for (final t in tracks) {
      await destroyTrack(t);
    }
  }

  Future<void> removeTrack(String sourceName, String remotePath) async {
    await recordTombstone(sourceName, remotePath);
    // Resolve the musicId from the in-memory index before the row is gone.
    final id = find(sourceName, remotePath)?.musicId;
    final result = RustLibraryService.deleteTrack(id);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust library delete failed; sqflite fallback removed: $result');
    }
    _tracks.removeWhere(
      (t) => t.sourceName == sourceName && t.remotePath == remotePath,
    );
    notifyListeners();
  }

  /// Decode Rust deleted_tracks JSON array to sqflite-compatible maps.
  ///
  /// Returns null on decode failure.
  static List<Map<String, dynamic>>? decodeDeletedTracks(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return null;
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          final row = <String, dynamic>{};
          row['source_name'] = item['source_name'] as String? ?? '';
          row['remote_path'] = item['remote_path'] as String? ?? '';
          row['rev'] = (item['rev'] as num?)?.toInt() ?? 0;
          row['deleted_at'] = item['deleted_at'] as String? ?? '';
          row['pushed'] = (item['pushed'] as num?)?.toInt() ?? 0;
          out.add(row);
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}
