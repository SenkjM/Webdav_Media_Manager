import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;

import '../models/library_track.dart';
import '../utils/cue_sheet.dart';
import '../utils/rev_clock.dart';
import '../utils/track_identity.dart';
import 'cover_service.dart';
import 'library_database.dart';
import 'tag_service.dart';

/// Local music library: indexes tracks that have been cached at least once.
/// Metadata + cover thumbs persist across audio-cache deletion.
class LibraryService extends ChangeNotifier {
  /// Monotonic version source; every locally-created or locally-changed row is
  /// stamped with it so sync has a single comparable field.
  RevClock? _revClock;

  /// Wire the clock (AppState.init) — falls back to the wall clock when absent.
  void attachRevClock(RevClock clock) => _revClock = clock;

  /// Sync cursor for one remote: how far we have consumed, plus the parts we
  /// already read (so a pull only fetches what is new).
  Future<({int lastSeq, int baseUpTo, Map<String, int> parts})> loadSyncCursor(
    String remoteKey,
  ) async {
    final row = await _db.loadSyncState(remoteKey);
    if (row == null) return (lastSeq: 0, baseUpTo: 0, parts: <String, int>{});
    final parts = <String, int>{};
    try {
      final decoded = jsonDecode(row['parts'] as String? ?? '{}');
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String) parts[k] = (v as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // A corrupt cursor only costs one full re-read.
    }
    return (
      lastSeq: (row['last_seq'] as num?)?.toInt() ?? 0,
      baseUpTo: (row['base_up_to'] as num?)?.toInt() ?? 0,
      parts: parts,
    );
  }

  Future<void> saveSyncCursor({
    required String remoteKey,
    required int lastSeq,
    required int baseUpTo,
    required Map<String, int> parts,
  }) => _db.saveSyncState(
    remoteKey: remoteKey,
    lastSeq: lastSeq,
    baseUpTo: baseUpTo,
    parts: jsonEncode(parts),
  );

  Future<void> clearSyncCursor() => _db.clearSyncState();

  /// Adopt an externally observed rev (a row pulled from the cloud) so the next
  /// local write cannot go backwards relative to it.
  void observeRev(int rev) => _revClock?.observe(rev);

  /// Deletions made here that the cloud has not been told about yet.
  Future<List<Map<String, dynamic>>> pendingTombstones() =>
      _db.unpushedTombstones();

  /// Mark the given tombstone revs as published.
  Future<void> markTombstonesPushed(Set<int> revs) =>
      _db.markTombstonesPushed(revs);

  /// Drop tombstones that a rebuild has materialised (`rev <= upTo`).
  Future<int> purgeTombstonesUpTo(int upTo) => _db.purgeTombstonesUpTo(upTo);

  /// Forget tombstones for rows that were re-downloaded (they are alive again).
  Future<void> clearTombstones(Set<int> revs) async {
    if (revs.isEmpty) return;
    final rows = await _db.allTombstones();
    for (final row in rows) {
      final rev = (row['rev'] as num?)?.toInt() ?? 0;
      if (!revs.contains(rev)) continue;
      await _db.clearTombstone(
        row['source_name'] as String? ?? '',
        row['remote_path'] as String? ?? '',
      );
    }
  }

  int _nextRev() =>
      _revClock?.next() ?? DateTime.now().millisecondsSinceEpoch;

  /// Record a tombstone so a destroyed song is not pulled back by sync.
  ///
  /// Only *destruction* / removal writes one: dropping just the audio cache keeps
  /// the metadata and the song stays in the library.
  Future<void> recordTombstone(String sourceName, String remotePath) async {
    await _db.upsertTombstone(
      sourceName: sourceName,
      remotePath: remotePath,
      rev: _nextRev(),
    );
  }
  LibraryService({
    LibraryDatabase? db,
    TagService? tags,
    CoverService? covers,
  })  : _db = db ?? LibraryDatabase(),
        _tags = tags ?? TagService(),
        _covers = covers ?? CoverService();

  final LibraryDatabase _db;
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

  LibraryDatabase get database => _db;
  CoverService get covers => _covers;
  TagService get tags => _tags;

  Future<void> init() async {
    await _db.database;
    await _covers.init();
    await refresh();
  }

  Future<void> refresh() async {
    final all = await _db.allTracks();
    _tracks
      ..clear()
      ..addAll(all);
    _loaded = true;
    notifyListeners();
  }


  List<LibraryTrack> tracksForSource(String sourceName) =>
      _tracks.where((t) => t.sourceName == sourceName).toList();

  /// Upsert tracks from a sync/backup payload; only touches listed rows.
  Future<void> upsertTracks(Iterable<LibraryTrack> tracks) async {
    for (final track in tracks) {
      await _db.upsertTrack(track);
      final idx = _tracks.indexWhere(
        (t) =>
            t.musicId == track.musicId ||
            (t.sourceName == track.sourceName && t.remotePath == track.remotePath),
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
    await _db.deleteTracksForSource(sourceName);
    _tracks.removeWhere((t) => t.sourceName == sourceName);
    for (final track in tracks) {
      await _db.upsertTrack(track);
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
    final album = await _db.cueAlbumForSlice(track.musicId);
    if (album == null) return null;
    final cueId = album['cue_id'] as String;
    final slices = await _db.sliceMusicIdsForCue(cueId);
    return {
      'cueId': cueId,
      'cueRemotePath': album['cue_remote_path'],
      'audioMusicId': track.audioMusicId ?? track.cacheMusicId,
      'audioRemotePath': track.audioRemotePath,
      'sliceMusicIds': slices,
    };
  }

  /// Bidirectional CUE: cue → original audio + slice music_ids.
  Future<Map<String, dynamic>?> cueRelationForCueId(String cueId) async {
    final slices = await _db.slicesForCue(cueId);
    if (slices.isEmpty) return null;
    final first = slices.first;
    return {
      'cueId': cueId,
      'cueRemotePath': first.cueRemotePath,
      'audioMusicId': first.audioMusicId ?? first.cacheMusicId,
      'audioRemotePath': first.audioRemotePath,
      'sliceMusicIds': slices.map((s) => s.musicId).toList(),
      'slices': slices,
    };
  }

  /// After a file finishes downloading: read tags, save thumb + full cover, upsert.
  ///
  /// The caller has already decided this file belongs in the library (it uses
  /// the user's configured music extensions); this does not re-check against a
  /// hard-coded list, which used to reject configured formats like `.m4a`.
  Future<LibraryTrack> ingestDownloaded({
    required String sourceName,
    required String remotePath,
    required String fileName,
    required String localPath,
  }) async {
    final now = DateTime.now();
    final read = await _tags.readFromFile(localPath);
    String? coverPath;
    if (read.coverBytes != null && read.coverBytes!.isNotEmpty) {
      coverPath = await _covers.saveThumb(
        sourceName: sourceName,
        remotePath: remotePath,
        bytes: read.coverBytes!,
      );
      // Best-effort full-res cache for library UI when file is local.
      await _covers.saveFull(
        sourceName: sourceName,
        remotePath: remotePath,
        bytes: read.coverBytes!,
      );
    } else {
      // Keep previous thumb if re-download has no art.
      final existing = await _db.getTrack(sourceName, remotePath);
      coverPath = existing?.coverPath;
      if (coverPath != null && !File(coverPath).existsSync()) {
        coverPath = null;
      }
    }

    final track = LibraryTrack(
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      title: read.title,
      artist: read.artist,
      albumArtist: read.albumArtist,
      album: read.album,
      durationMs: read.durationMs,
      trackNumber: read.trackNumber,
      trackTotal: read.trackTotal,
      discNumber: read.discNumber,
      discTotal: read.discTotal,
      year: read.year,
      genre: read.genre,
      bitrate: read.bitrate,
      sampleRate: read.sampleRate,
      coverPath: coverPath,
      lastDownloadedAt: now,
      lastTagReadAt: now,
    );
    await _db.upsertTrack(track);
    final idx = _tracks.indexWhere(
      (t) => t.sourceName == sourceName && t.remotePath == remotePath,
    );
    if (idx >= 0) {
      _tracks[idx] = track;
    } else {
      _tracks.add(track);
    }
    notifyListeners();
    return track;
  }


  Future<List<LibraryTrack>> ingestCueAlbum({
    required String sourceName,
    required String cueRemotePath,
    required CueSheet sheet,
    required String cacheGroupId,
    required String Function(String remotePath) localPathFor,
  }) async {
    final now = DateTime.now();
    // Replace the whole CUE group so clear-cache + re-download cannot leave
    // orphan virtual rows or a leftover standalone audio row (+1 drift).
    await _db.deleteTracksForCue(sourceName, cueRemotePath);
    _tracks.removeWhere(
      (t) => t.sourceName == sourceName && t.cueRemotePath == cueRemotePath,
    );
    final audioRemotes = sheet.audioRemotePaths(cueRemotePath);
    final fileTags = <String, ReadTags>{};
    final fileDurations = <String, Duration?>{};
    for (final audioRemote in audioRemotes) {
      final tags = await _tags.readFromFile(localPathFor(audioRemote));
      fileTags[audioRemote] = tags;
      final base = p.basename(audioRemote);
      if (tags.durationMs != null) {
        final d = Duration(milliseconds: tags.durationMs!);
        fileDurations[base] = d;
        for (final f in sheet.files) {
          if (p.basename(f.replaceAll('\\', '/')) == base) fileDurations[f] = d;
        }
      }
    }
    final ranges = cueClipRanges(sheet.tracks, fileDurations: fileDurations);
    final created = <LibraryTrack>[];
    ReadTags? coverSource;
    for (final a in audioRemotes) {
      final tags = fileTags[a];
      if (tags?.coverBytes != null && tags!.coverBytes!.isNotEmpty) { coverSource = tags; break; }
    }
    for (var i = 0; i < sheet.tracks.length; i++) {
      final ct = sheet.tracks[i];
      final range = ranges[i];
      final base = p.basename(ct.fileName.replaceAll('\\', '/'));
      final resolved = audioRemotes.firstWhere((r) => p.basename(r) == base, orElse: () => audioRemotes.isNotEmpty ? audioRemotes.first : ct.fileName);
      final fileTag = fileTags[resolved] ?? const ReadTags();
      final merged = mergeCueOverFileTags(sheet: sheet, cueTrack: ct, fileTitle: fileTag.title, fileArtist: fileTag.artist, fileAlbumArtist: fileTag.albumArtist, fileAlbum: fileTag.album, fileYear: fileTag.year, fileGenre: fileTag.genre);
      final virtualPath = cueVirtualRemotePath(resolved, ct.number);
      int? durationMs;
      if (range.end != null) {
        final ms = (range.end! - range.start).inMilliseconds;
        durationMs = ms >= 0 ? ms : null;
      } else if (fileTag.durationMs != null) {
        final ms = fileTag.durationMs! - range.start.inMilliseconds;
        durationMs = ms >= 0 ? ms : null;
      }
      String? coverPath;
      final bytes = coverSource?.coverBytes ?? fileTag.coverBytes;
      if (bytes != null && bytes.isNotEmpty) {
        coverPath = await _covers.saveThumb(sourceName: sourceName, remotePath: virtualPath, bytes: bytes);
        await _covers.saveFull(sourceName: sourceName, remotePath: resolved, bytes: bytes);
      }
      final audioMid = musicIdForRemote(sourceName, resolved);
      final sliceMid = musicIdForCueSlice(sourceName, cueRemotePath, ct.number);
      final track = LibraryTrack(
        musicId: sliceMid,
        sourceName: sourceName,
        remotePath: virtualPath,
        fileName: merged.title ?? ct.title ?? '${ct.number}',
        title: merged.title,
        artist: merged.artist,
        albumArtist: merged.albumArtist,
        album: merged.album,
        durationMs: durationMs,
        trackNumber: merged.trackNumber,
        trackTotal: sheet.tracks.length,
        year: merged.year,
        genre: merged.genre,
        bitrate: fileTag.bitrate,
        sampleRate: fileTag.sampleRate,
        coverPath: coverPath,
        cueId: cueIdFor(sourceName, cueRemotePath),
        cueRemotePath: cueRemotePath,
        cueTrackIndex: ct.number,
        audioMusicId: audioMid,
        audioRemotePath: resolved,
        clipStartMs: range.start.inMilliseconds,
        clipEndMs: range.end?.inMilliseconds,
        cacheGroupId: cacheGroupId,
        lastDownloadedAt: now,
        lastTagReadAt: now,
        rev: _nextRev(),
      );
      await _db.upsertTrack(track);
      final idx = _tracks.indexWhere((x) => x.sourceName == sourceName && x.remotePath == virtualPath);
      if (idx >= 0) {
        _tracks[idx] = track;
      } else {
        _tracks.add(track);
      }
      created.add(track);
    }
    // Drop accidental standalone rows for the .cue itself or raw audio files
    // (e.g. ensureQueued ingested audio without a cue group id).
    final removePaths = <String>{cueRemotePath, ...audioRemotes};
    for (final path in removePaths) {
      await _db.deleteTrack(sourceName, path);
      _tracks.removeWhere((t) => t.sourceName == sourceName && t.remotePath == path);
    }
    // Also drop any row whose audioRemotePath is one of this album's files but
    // is not one of the virtual paths we just wrote (stale / wrong keys).
    final keepVirtual = created.map((t) => t.remotePath).toSet();
    final stale = _tracks
        .where(
          (t) =>
              t.sourceName == sourceName &&
              !keepVirtual.contains(t.remotePath) &&
              (t.cueRemotePath == cueRemotePath ||
                  (t.audioRemotePath != null &&
                      audioRemotes.contains(t.audioRemotePath)) ||
                  audioRemotes.contains(t.remotePath)),
        )
        .toList();
    for (final t in stale) {
      await _db.deleteTrack(t.sourceName, t.remotePath);
      _tracks.removeWhere(
        (x) => x.sourceName == t.sourceName && x.remotePath == t.remotePath,
      );
    }

    notifyListeners();
    return created;
  }

  /// Case-insensitive search over title / artist / album / file name.
  List<LibraryTrack> search(
    String query, {
    LibrarySortMode sort = LibrarySortMode.byName,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return byTitle(sort: sort);
    final matched = _tracks.where((t) {
      bool has(String? s) => (s ?? '').toLowerCase().contains(q);
      return has(t.title) ||
          has(t.artist) ||
          has(t.albumArtist) ||
          has(t.album) ||
          has(t.fileName) ||
          has(t.genre) ||
          t.displayTitle.toLowerCase().contains(q) ||
          t.displayArtist.toLowerCase().contains(q) ||
          t.displayAlbum.toLowerCase().contains(q);
    }).toList();
    matched.sort(sort == LibrarySortMode.byAlbumTrack
        ? compareTracksByAlbumOrder
        : compareTracksByName);
    return matched;
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
    final list = _tracks
        .where((t) => (t.genre ?? '').trim().toLowerCase() == g)
        .toList();
    list.sort(sort == LibrarySortMode.byAlbumTrack
        ? compareTracksByAlbumOrder
        : compareTracksByName);
    return list;
  }

  /// Group tracks by genre for the tags browser (empty genre → 未分类).
  Map<String, List<LibraryTrack>> groupedByGenre() {
    final map = <String, List<LibraryTrack>>{};
    final keyByLower = <String, String>{};
    for (final t in _tracks) {
      final g = t.genre?.trim();
      final String key;
      if (g == null || g.isEmpty) {
        key = '未分类';
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
        if (a == '未分类') return 1;
        if (b == '未分类') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return LinkedHashMap.fromEntries(keys.map((k) => MapEntry(k, map[k]!)));
  }

    List<LibraryTrack> byTitle({LibrarySortMode sort = LibrarySortMode.byName}) {
    final list = List<LibraryTrack>.from(_tracks);
    list.sort(sort == LibrarySortMode.byAlbumTrack
        ? compareTracksByAlbumOrder
        : compareTracksByName);
    return list;
  }

  List<LibraryTrack> sortedCopy(
    List<LibraryTrack> source, {
    required LibrarySortMode sort,
  }) {
    final list = List<LibraryTrack>.from(source);
    list.sort(sort == LibrarySortMode.byAlbumTrack
        ? compareTracksByAlbumOrder
        : compareTracksByName);
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
  /// Caller should also delete local audio files / annex and clean playlists.
  Future<void> destroyAll() async {
    await _db.clearAllLibraryData();
    await _covers.deleteAllCovers();
    _tracks.clear();
    notifyListeners();
  }

  /// Hand the index over to the cloud: drop every index row (tracks, CUE,
  /// tombstones, sync cursor) and forget the in-memory list, keeping the cache
  /// annex and the covers.
  ///
  /// The next incremental sync then finds an empty local index and no cursor, so
  /// it re-reads the cloud and adopts the whole library — and because the annex
  /// survived, rows that have a file on disk come back as local instead of
  /// triggering a second full download.
  Future<void> prepareCloudOverwrite() async {
    await _db.clearLibraryIndex();
    _tracks.clear();
    notifyListeners();
  }

  /// Destroy **one** song: its tombstone, its cover art and its library row.
  ///
  /// One song is the atomic unit of destruction — callers loop over songs and
  /// stop *between* them, never inside one. CUE slices share a backing file, so
  /// destroying any slice takes the whole album's virtual rows with it; the
  /// siblings are then already gone, and a later call on one of them finds nothing
  /// to do.
  ///
  /// Distinct from [removeTrack] (rows only) and from cache deletion (audio files
  /// only, metadata kept). The audio file itself is the caller's business:
  /// `AppState.destroyLibraryTrack` owns both the annex and the disk.
  Future<void> destroyTrack(LibraryTrack track) async {
    // Tombstone first, so a sync that runs while we delete still learns about the
    // removal (and cannot pull the song back).
    await recordTombstone(track.sourceName, track.remotePath);
    await _covers.deleteThumb(track.sourceName, track.remotePath);
    await _covers.deleteFull(track.sourceName, track.remotePath);
    if (track.isCueVirtual && track.cueRemotePath != null) {
      await _db.deleteTracksForCue(track.sourceName, track.cueRemotePath!);
      _tracks.removeWhere(
        (t) =>
            t.sourceName == track.sourceName &&
            t.isCueVirtual &&
            t.cueRemotePath == track.cueRemotePath,
      );
    } else {
      await _db.deleteTrack(track.sourceName, track.remotePath);
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
    await _db.deleteTrack(sourceName, remotePath);
    _tracks.removeWhere((t) => t.sourceName == sourceName && t.remotePath == remotePath);
    notifyListeners();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}
