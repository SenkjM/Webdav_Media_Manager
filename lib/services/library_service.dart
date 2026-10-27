import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;

import '../models/library_sentinels.dart';
import '../models/library_track.dart';
import '../utils/cue_sheet.dart';
import '../utils/rev_clock.dart';
import '../utils/track_identity.dart';
import 'cover_service.dart';
import 'library_database.dart';
import 'rust_library_service.dart';
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
    final rustResult = RustLibraryService.syncStateGet(remoteKey);
    if (rustResult != null && !rustResult.startsWith('error:') && rustResult != 'null') {
      try {
        final decoded = jsonDecode(rustResult);
        if (decoded is Map) {
          final partsStr = decoded['parts'] as String? ?? '{}';
          final parts = <String, int>{};
          try {
            final partsDecoded = jsonDecode(partsStr);
            if (partsDecoded is Map) {
              partsDecoded.forEach((k, v) {
                if (k is String) parts[k] = (v as num?)?.toInt() ?? 0;
              });
            }
          } catch (_) {
            // A corrupt cursor only costs one full re-read.
          }
          return (
            lastSeq: (decoded['last_seq'] as num?)?.toInt() ?? 0,
            baseUpTo: (decoded['base_up_to'] as num?)?.toInt() ?? 0,
            parts: parts,
          );
        }
      } catch (_) {
        // Parse failure — start fresh
      }
    }
    // No cursor or error — start from zero
    return (lastSeq: 0, baseUpTo: 0, parts: <String, int>{});
  }

  Future<void> saveSyncCursor({
    required String remoteKey,
    required int lastSeq,
    required int baseUpTo,
    required Map<String, int> parts,
  }) async {
    final json = jsonEncode({
      'remote_key': remoteKey,
      'last_seq': lastSeq,
      'base_up_to': baseUpTo,
      'parts': jsonEncode(parts),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final result = RustLibraryService.syncStateSave(json);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust sync_state save failed: $result');
    }
  }

  Future<void> clearSyncCursor() async {
    final result = RustLibraryService.syncStateClear(LibraryDatabase.musicCursorPrefix);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust sync_state clear failed: $result');
    }
  }

  /// Adopt an externally observed rev (a row pulled from the cloud) so the next
  /// local write cannot go backwards relative to it.
  void observeRev(int rev) => _revClock?.observe(rev);

  /// Deletions made here that the cloud has not been told about yet.
  Future<List<Map<String, dynamic>>> pendingTombstones() async {
    final rustResult = RustLibraryService.deletedTracksUnpushed();
    if (rustResult != null && !rustResult.startsWith('error:') && rustResult != 'null') {
      try {
        final decoded = decodeDeletedTracksForTest(rustResult);
        if (decoded != null) return decoded;
      } catch (_) {
        // Parse failure — return empty
      }
    }
    return [];
  }

  /// Mark the given tombstone revs as published.
  Future<void> markTombstonesPushed(Set<int> revs) async {
    if (revs.isEmpty) return;
    final revsJson = jsonEncode(revs.toList());
    final result = RustLibraryService.deletedTracksMarkPushed(revsJson);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust deleted_tracks mark_pushed failed: $result');
    }
  }

  /// Drop tombstones that a rebuild has materialised (`rev <= upTo`).
  Future<int> purgeTombstonesUpTo(int upTo) async {
    final result = RustLibraryService.deletedTracksPurgeUpTo(upTo);
    if (result != null && result.startsWith('error:')) {
      throw StateError('Rust deleted_tracks purge failed: $result');
    }
    return 0; // Core tracks the count internally
  }

  /// Every tombstone, pushed or not (重建后的残留检查要看全量).
  Future<List<Map<String, dynamic>>> allTombstones() async {
    final rustResult = RustLibraryService.deletedTracksList();
    if (rustResult != null && !rustResult.startsWith('error:') && rustResult != 'null') {
      try {
        final decoded = decodeDeletedTracksForTest(rustResult);
        if (decoded != null) return decoded;
      } catch (_) {
        // Parse failure — return empty
      }
    }
    return [];
  }

  /// 清掉「行已经不在」的墓碑，返回清掉几条。
  ///
  /// 重建之后云端 base 就是本地全部行的快照，删除意图也一起被物化了，所以
  /// **本地不该再留着任何墓碑**。这里只清那些确实没有对应活行的——还留着活行
  /// 的墓碑属于「行 rev 高于墓碑」的复活场景，要不要清得让用户看见。
  Future<int> clearDeadTombstones() async {
    final rows = await allTombstones();
    var cleared = 0;
    for (final row in rows) {
      final source = row['source_name'] as String? ?? '';
      final path = row['remote_path'] as String? ?? '';
      if (source.isEmpty || path.isEmpty) continue;
      if (find(source, path) != null) continue;
      final result = RustLibraryService.deletedTrackClear(source, path);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust deleted_track clear failed: $result');
      }
      cleared++;
    }
    return cleared;
  }

  /// Forget tombstones for rows that were re-downloaded (they are alive again).
  Future<void> clearTombstones(Set<int> revs) async {
    if (revs.isEmpty) return;
    final rows = await allTombstones();
    for (final row in rows) {
      final rev = (row['rev'] as num?)?.toInt() ?? 0;
      if (!revs.contains(rev)) continue;
      final source = row['source_name'] as String? ?? '';
      final path = row['remote_path'] as String? ?? '';
      final result = RustLibraryService.deletedTrackClear(source, path);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust deleted_track clear failed: $result');
      }
    }
  }

  int _nextRev() => _revClock?.next() ?? DateTime.now().millisecondsSinceEpoch;

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

  LibraryService({LibraryDatabase? db, TagService? tags, CoverService? covers})
    : _db = db ?? LibraryDatabase(),
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
    // Forced Rust path when [kRustLibraryReadEnabled] — no sqflite fallback
    // (fallback hid missing libwdmm_ffi.so during device smoke).
    if (kRustLibraryReadEnabled) {
      final rustTracks = RustLibraryService.listAll();
      if (rustTracks == null) {
        throw StateError(
          'Rust library read failed; Dart sqflite fallback removed',
        );
      }
      _tracks
        ..clear()
        ..addAll(rustTracks);
    } else {
      final all = await _db.allTracks();
      _tracks
        ..clear()
        ..addAll(all);
    }
    _loaded = true;
    notifyListeners();
  }

  List<LibraryTrack> tracksForSource(String sourceName) =>
      _tracks.where((t) => t.sourceName == sourceName).toList();

  /// Upsert tracks from a sync/backup payload; only touches listed rows.
  Future<void> upsertTracks(Iterable<LibraryTrack> tracks) async {
    for (final track in tracks) {
      if (kRustLibraryWriteEnabled) {
        // Rust-only write: sqflite dual-path removed per Round 11 cutover.
        final result = RustLibraryService.upsertTrack(track);
        if (result != null && result.startsWith('error:')) {
          throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
        }
      } else {
        await _db.upsertTrack(track);
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
    if (kRustLibraryWriteEnabled) {
      // Rust: delete all tracks for this account in one call
      final result = RustLibraryService.deleteTracksBySource(sourceName);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library delete-by-source failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.deleteTracksForSource(sourceName);
    }
    _tracks.removeWhere((t) => t.sourceName == sourceName);
    for (final track in tracks) {
      if (kRustLibraryWriteEnabled) {
        final result = RustLibraryService.upsertTrack(track);
        if (result != null && result.startsWith('error:')) {
          throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
        }
      } else {
        await _db.upsertTrack(track);
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
    // Core-first: try Rust rusqlite; fall back to sqflite.
    final coreAlbum = RustLibraryService.cueAlbumForSlice(track.musicId);
    if (coreAlbum != null) {
      final cueId = coreAlbum['cue_id'] as String;
      final coreSlices = RustLibraryService.slicesForCue(cueId);
      if (coreSlices != null) {
        return {
          'cueId': cueId,
          'cueRemotePath': coreAlbum['cue_remote_path'],
          'audioMusicId': track.audioMusicId ?? track.cacheMusicId,
          'audioRemotePath': track.audioRemotePath,
          'sliceMusicIds': coreSlices.map((s) => s.musicId).toList(),
        };
      }
    }
    // sqflite fallback
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
    // Core-first: try Rust rusqlite; fall back to sqflite on null/empty.
    final coreSlices = RustLibraryService.slicesForCue(cueId);
    if (coreSlices != null && coreSlices.isNotEmpty) {
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
    // sqflite fallback
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
    bool updateDownloadTime = true,
  }) async {
    final now = DateTime.now();
    LibraryTrack? existing;
    if (kRustLibraryReadEnabled) {
      existing = RustLibraryService.getBySourcePath(sourceName, remotePath);
    }
    existing ??= await _db.getTrack(sourceName, remotePath);
    final read = await _tags.readFromFile(localPath);    String? coverPath;
    if (read.coverBytes != null && read.coverBytes!.isNotEmpty) {
      coverPath = await _covers.saveThumb(
        sourceName: sourceName,
        remotePath: remotePath,
        bytes: read.coverBytes!,
      );
    } else {
      // Keep previous thumb if re-download has no art.
      coverPath = existing?.coverPath;
      if (coverPath != null && !File(coverPath).existsSync()) {
        coverPath = null;
      }
    }

    final track = LibraryTrack(
      musicId: existing?.musicId,
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
      cacheGroupId: existing?.cacheGroupId,
      rev: _nextRev(),
      lastDownloadedAt: updateDownloadTime
          ? now
          : existing?.lastDownloadedAt ?? now,
      lastTagReadAt: now,
    );
    if (kRustLibraryWriteEnabled) {
      // Rust-only write: sqflite dual-path removed per Round 11 cutover.
      final result = RustLibraryService.upsertTrack(track);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.upsertTrack(track);
    }
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

  /// Persist confirmed cloud absence (list red-dot). Skip when [hasLocalCache].
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
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.upsertTrack(existing);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.upsertTrack(existing);
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
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.upsertTrack(existing);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.upsertTrack(existing);
    }
    notifyListeners();
  }

  /// Point a library row at a new remote path (redirect after missing).

  Future<void> updateCoverPath({
    required String sourceName,
    required String remotePath,
    required String coverPath,
  }) async {
    final existing = find(sourceName, remotePath);
    if (existing == null) return;
    existing.coverPath = coverPath;
    existing.rev = _nextRev();
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.upsertTrack(existing);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.upsertTrack(existing);
    }
    notifyListeners();
  }

  Future<LibraryTrack> retargetTrack({
    required LibraryTrack track,
    required String newRemotePath,
    String? newFileName,
  }) async {
    final name = newFileName ?? newRemotePath.split('/').where((s) => s.isNotEmpty).last;
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.deleteTrack(track.musicId);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library delete failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.deleteTrack(track.sourceName, track.remotePath);
    }
    // Rust delete: Round 11 cutover.
    RustLibraryService.deleteTrack(track.musicId);
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
      coverPath: track.coverPath,
      cacheGroupId: track.cacheGroupId,
      rev: _nextRev(),
      lastDownloadedAt: track.lastDownloadedAt,
      lastTagReadAt: track.lastTagReadAt,
      remoteMissing: false,
    );
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.upsertTrack(next);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.upsertTrack(next);
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
  Future<LibraryTrack> ingestFromTags({
    required String sourceName,
    required String remotePath,
    required String fileName,
    required ReadTags tags,
  }) async {
    final now = DateTime.now();
    LibraryTrack? existing;
    if (kRustLibraryReadEnabled) {
      existing = RustLibraryService.getBySourcePath(sourceName, remotePath);
    }
    existing ??= await _db.getTrack(sourceName, remotePath);
    String? coverPath = existing?.coverPath;
    if (tags.coverBytes != null && tags.coverBytes!.isNotEmpty) {
      coverPath = await _covers.saveThumb(
        sourceName: sourceName,
        remotePath: remotePath,
        bytes: tags.coverBytes!,
      );
    } else if (coverPath != null && !File(coverPath).existsSync()) {
      coverPath = null;
    }

    final track = LibraryTrack(
      musicId: existing?.musicId,
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      title: tags.title ?? existing?.title,
      artist: tags.artist ?? existing?.artist,
      albumArtist: tags.albumArtist ?? existing?.albumArtist,
      album: tags.album ?? existing?.album,
      durationMs: tags.durationMs ?? existing?.durationMs,
      trackNumber: tags.trackNumber ?? existing?.trackNumber,
      trackTotal: tags.trackTotal ?? existing?.trackTotal,
      discNumber: tags.discNumber ?? existing?.discNumber,
      discTotal: tags.discTotal ?? existing?.discTotal,
      year: tags.year ?? existing?.year,
      genre: tags.genre ?? existing?.genre,
      bitrate: tags.bitrate ?? existing?.bitrate,
      sampleRate: tags.sampleRate ?? existing?.sampleRate,
      coverPath: coverPath,
      cacheGroupId: existing?.cacheGroupId,
      rev: _nextRev(),
      lastDownloadedAt: existing?.lastDownloadedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastTagReadAt: now,
    );
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.upsertTrack(track);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library upsert failed; sqflite fallback removed: $result');
      }
    } else {
      await _db.upsertTrack(track);
    }
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

  /// Re-read tags from an already cached, non-CUE audio file and replace its
  /// library metadata. CUE slices must be refreshed as a whole album.
  Future<LibraryTrack> refreshTrackTagsFromFile({
    required LibraryTrack track,
    required String localPath,
  }) async {
    if (track.isCueVirtual) {
      throw ArgumentError('CUE tracks must be refreshed as an album');
    }
    return ingestDownloaded(
      sourceName: track.sourceName,
      remotePath: track.remotePath,
      fileName: track.fileName,
      localPath: localPath,
      updateDownloadTime: false,
    );
  }

  /// Scrape/Range path: build CUE slices from a parsed sheet **without**
  /// requiring local audio files. Clip ends stay open until a later cache ingest.
  Future<List<LibraryTrack>> ingestCueRemote({
    required String sourceName,
    required String cueRemotePath,
    required CueSheet sheet,
    Uint8List? coverBytes,
  }) async {
    final existing = _tracks
        .where(
          (tr) =>
              tr.sourceName == sourceName && tr.cueRemotePath == cueRemotePath,
        )
        .toList();
    if (existing.isNotEmpty) {
      // Re-scrape of an already ingested CUE album: rows exist, but they may
      // predate the "scrape also builds a thumb" rule (or the thumb file may be
      // gone). Fill/refresh covers without touching the clip rows.
      if (coverBytes != null && coverBytes.isNotEmpty) {
        await _refreshCueSliceCovers(existing, coverBytes);
      }
      return const [];
    }
    final now = DateTime.now();
    final audioRemotes = sheet.audioRemotePaths(cueRemotePath);
    final ranges = cueClipRanges(sheet.tracks);
    final groupId = cueCacheGroupId(sourceName, cueRemotePath);
    final created = <LibraryTrack>[];
    for (var i = 0; i < sheet.tracks.length; i++) {
      final ct = sheet.tracks[i];
      final range = ranges[i];
      final base = p.basename(ct.fileName.replaceAll('\\', '/'));
      final resolved = audioRemotes.firstWhere(
        (r) => p.basename(r) == base,
        orElse: () =>
            audioRemotes.isNotEmpty ? audioRemotes.first : ct.fileName,
      );
      final merged = mergeCueOverFileTags(
        sheet: sheet,
        cueTrack: ct,
        fileTitle: null,
        fileArtist: null,
        fileAlbumArtist: null,
        fileAlbum: null,
        fileYear: null,
        fileGenre: null,
      );
      final virtualPath = cueVirtualRemotePath(resolved, ct.number);
      String? coverPath;
      if (coverBytes != null && coverBytes.isNotEmpty) {
        coverPath = await _covers.saveThumb(
          sourceName: sourceName,
          remotePath: virtualPath,
          bytes: coverBytes,
        );
      }
      final audioMid = musicIdForRemote(sourceName, resolved);
      final sliceMid = musicIdForCueSlice(sourceName, cueRemotePath, ct.number);
      created.add(
        LibraryTrack(
          musicId: sliceMid,
          sourceName: sourceName,
          remotePath: virtualPath,
          fileName: merged.title ?? ct.title ?? '${ct.number}',
          title: merged.title,
          artist: merged.artist,
          albumArtist: merged.albumArtist,
          album: merged.album,
          durationMs: null,
          trackNumber: merged.trackNumber,
          trackTotal: sheet.tracks.length,
          year: merged.year,
          genre: merged.genre,
          cueId: cueIdFor(sourceName, cueRemotePath),
          cueRemotePath: cueRemotePath,
          cueTrackIndex: ct.number,
          audioMusicId: audioMid,
          audioRemotePath: resolved,
          clipStartMs: range.start.inMilliseconds,
          clipEndMs: range.end?.inMilliseconds,
          cacheGroupId: groupId,
          lastDownloadedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          lastTagReadAt: now,
          rev: _nextRev(),
          remoteMissing: false,
          coverPath: coverPath,
        ),
      );
    }
    if (created.isEmpty) return const [];

    // Dual-write: Rust first (when enabled), then sqflite
    if (kRustLibraryWriteEnabled) {
      // Delete-then-upsert mirrors replace semantics
      final deleteResult = RustLibraryService.deleteCueAlbum(
        sourceName,
        cueRemotePath,
      );
      // Ignore "not found" errors — the album may not exist yet
      if (deleteResult != null &&
          deleteResult.startsWith('error:') &&
          !deleteResult.contains('not found')) {
        throw StateError('Rust CUE album delete failed during replace: $deleteResult');
      }

      // Build and upsert the album record
      final albumJson = RustLibraryService.cueAlbumJson(
        cueId: created.first.cueId!,
        sourceName: sourceName,
        cueRemotePath: cueRemotePath,
        title: created.first.album,
        performer: created.first.albumArtist ?? created.first.artist,
        cacheGroupId: groupId,
        createdAt: now,
      );
      if (albumJson != null) {
        final albumResult = RustLibraryService.upsertCueAlbum(
          jsonEncode(albumJson),
        );
        if (albumResult != null && albumResult.startsWith('error:')) {
          throw StateError('Rust CUE album upsert failed: $albumResult');
        }
      }

      // Upsert each slice
      for (final track in created) {
        final sliceJson = RustLibraryService.cueSliceJson(track);
        if (sliceJson != null) {
          final sliceResult = RustLibraryService.upsertCueSlice(
            jsonEncode(sliceJson),
          );
          if (sliceResult != null && sliceResult.startsWith('error:')) {
            throw StateError('Rust CUE slice upsert failed: $sliceResult');
          }
        }
      }
    }

    _tracks.removeWhere(
      (t) =>
          t.sourceName == sourceName &&
          (t.cueRemotePath == cueRemotePath ||
              audioRemotes.contains(t.remotePath) ||
              audioRemotes.contains(t.audioRemotePath)),
    );
    _tracks.addAll(created);
    notifyListeners();
    return created;
  }

  /// Backfill/refresh the persistent thumbs of an already ingested CUE album.
  Future<void> _refreshCueSliceCovers(
    List<LibraryTrack> slices,
    Uint8List bytes,
  ) async {
    var changed = false;
    for (final row in slices) {
      final path = await _covers.saveThumb(
        sourceName: row.sourceName,
        remotePath: row.remotePath,
        bytes: bytes,
      );
      if (path == null) continue;
      row.coverPath = path;
      row.rev = _nextRev();

      // Dual-write: Rust first (when enabled), then sqflite
      if (kRustLibraryWriteEnabled) {
        final sliceJson = RustLibraryService.cueSliceJson(row);
        if (sliceJson != null) {
          final sliceResult = RustLibraryService.upsertCueSlice(
            jsonEncode(sliceJson),
          );
          if (sliceResult != null && sliceResult.startsWith('error:')) {
            throw StateError('Rust CUE slice upsert failed in cover refresh: $sliceResult');
          }
        }
      }

      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<List<LibraryTrack>> ingestCueAlbum({
    required String sourceName,
    required String cueRemotePath,
    required CueSheet sheet,
    required String cacheGroupId,
    required String Function(String remotePath) localPathFor,
  }) async {
    final now = DateTime.now();
    final audioRemotes = sheet.audioRemotePaths(cueRemotePath);
    final fileTags = <String, ReadTags>{};
    final fileDurations = <String, Duration?>{};
    for (final audioRemote in audioRemotes) {
      final localPath = localPathFor(audioRemote);
      if (!await File(localPath).exists()) {
        throw StateError('CUE audio disappeared from cache: $audioRemote');
      }
      final tags = await _tags.readFromFile(localPath);
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
      if (tags?.coverBytes != null && tags!.coverBytes!.isNotEmpty) {
        coverSource = tags;
        break;
      }
    }
    for (var i = 0; i < sheet.tracks.length; i++) {
      final ct = sheet.tracks[i];
      final range = ranges[i];
      final base = p.basename(ct.fileName.replaceAll('\\', '/'));
      final resolved = audioRemotes.firstWhere(
        (r) => p.basename(r) == base,
        orElse: () =>
            audioRemotes.isNotEmpty ? audioRemotes.first : ct.fileName,
      );
      final fileTag = fileTags[resolved] ?? const ReadTags();
      final merged = mergeCueOverFileTags(
        sheet: sheet,
        cueTrack: ct,
        fileTitle: fileTag.title,
        fileArtist: fileTag.artist,
        fileAlbumArtist: fileTag.albumArtist,
        fileAlbum: fileTag.album,
        fileYear: fileTag.year,
        fileGenre: fileTag.genre,
      );
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
        coverPath = await _covers.saveThumb(
          sourceName: sourceName,
          remotePath: virtualPath,
          bytes: bytes,
        );
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
      created.add(track);
    }

    // Read/build failures above leave the existing album untouched. Commit all
    // persisted rows together, then replace the in-memory projection at once.

    // Dual-write: Rust first (when enabled), then sqflite
    if (kRustLibraryWriteEnabled) {
      // Delete-then-upsert mirrors replace semantics
      final deleteResult = RustLibraryService.deleteCueAlbum(
        sourceName,
        cueRemotePath,
      );
      // Ignore "not found" errors — the album may not exist yet
      if (deleteResult != null &&
          deleteResult.startsWith('error:') &&
          !deleteResult.contains('not found')) {
        throw StateError('Rust CUE album delete failed during replace: $deleteResult');
      }

      // Build and upsert the album record
      final albumJson = RustLibraryService.cueAlbumJson(
        cueId: created.first.cueId!,
        sourceName: sourceName,
        cueRemotePath: cueRemotePath,
        title: created.first.album,
        performer: created.first.albumArtist ?? created.first.artist,
        cacheGroupId: cacheGroupId,
        createdAt: now,
      );
      if (albumJson != null) {
        final albumResult = RustLibraryService.upsertCueAlbum(
          jsonEncode(albumJson),
        );
        if (albumResult != null && albumResult.startsWith('error:')) {
          throw StateError('Rust CUE album upsert failed: $albumResult');
        }
      }

      // Upsert each slice
      for (final track in created) {
        final sliceJson = RustLibraryService.cueSliceJson(track);
        if (sliceJson != null) {
          final sliceResult = RustLibraryService.upsertCueSlice(
            jsonEncode(sliceJson),
          );
          if (sliceResult != null && sliceResult.startsWith('error:')) {
            throw StateError('Rust CUE slice upsert failed: $sliceResult');
          }
        }
      }
    }

    final removePaths = <String>{cueRemotePath, ...audioRemotes};
    _tracks.removeWhere(
      (t) =>
          t.sourceName == sourceName &&
          (t.cueRemotePath == cueRemotePath ||
              removePaths.contains(t.remotePath) ||
              audioRemotes.contains(t.audioRemotePath)),
    );
    _tracks.addAll(created);

    notifyListeners();
    return created;
  }

  /// Case-insensitive search over title / artist / album / file name.
  ///
  /// When [kRustLibraryReadEnabled] is true, search is Rust-only (throws if FFI fails).
  /// When the flag is off, searches the in-memory list from the last [refresh].
  List<LibraryTrack> search(
    String query, {
    LibrarySortMode sort = LibrarySortMode.byName,
  }) {
    // Forced Rust search when flag on — no in-memory/sqflite fallback.
    if (kRustLibraryReadEnabled) {
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

    // Flag off: in-memory search over last refresh().
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
          t.displayTitle.toLowerCase().contains(q);
    }).toList();
    matched.sort(
      sort == LibrarySortMode.byAlbumTrack
          ? compareTracksByAlbumOrder
          : compareTracksByName,
    );
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
      int remaining = 0;
      if (slicesJson != null && !slicesJson.startsWith('error:')) {
        try {
          // Core returns a decimal count string (e.g. "5"), not a JSON array
          remaining = int.tryParse(slicesJson.trim()) ?? 0;
        } catch (_) {
          remaining = 0;
        }
      }
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
    if (kRustLibraryWriteEnabled) {
      final result = RustLibraryService.deleteTrack(id);
      if (result != null && result.startsWith('error:')) {
        throw StateError('Rust library delete failed; sqflite fallback removed: $result');
      }
    } else {
      RustLibraryService.deleteTrack(id);
      await _db.deleteTrack(sourceName, remotePath);
    }
    _tracks.removeWhere(
      (t) => t.sourceName == sourceName && t.remotePath == remotePath,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  /// Decode Rust deleted_tracks JSON array to sqflite-compatible maps.
  ///
  /// Returns null on decode failure. Exposed for testing without FFI.
  @visibleForTesting
  static List<Map<String, dynamic>>? decodeDeletedTracksForTest(String json) {
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
