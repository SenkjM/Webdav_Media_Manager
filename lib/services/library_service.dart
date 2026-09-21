import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;

import '../models/library_track.dart';
import '../utils/cue_sheet.dart';
import '../utils/track_identity.dart';
import 'cover_service.dart';
import 'library_database.dart';
import 'tag_service.dart';

/// Local music library: indexes tracks that have been cached at least once.
/// Metadata + cover thumbs persist across audio-cache deletion.
class LibraryService extends ChangeNotifier {
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


  List<LibraryTrack> tracksForAccount(String accountId) =>
      _tracks.where((t) => t.accountId == accountId).toList();

  /// Upsert tracks from a sync/backup payload; only touches listed rows.
  Future<void> upsertTracks(Iterable<LibraryTrack> tracks) async {
    for (final track in tracks) {
      await _db.upsertTrack(track);
      final idx = _tracks.indexWhere(
        (t) =>
            t.musicId == track.musicId ||
            (t.accountId == track.accountId && t.remotePath == track.remotePath),
      );
      if (idx >= 0) {
        _tracks[idx] = track;
      } else {
        _tracks.add(track);
      }
    }
    notifyListeners();
  }

  /// Replace all local tracks for [accountId] with [tracks] (other accounts untouched).
  Future<void> replaceTracksForAccount(
    String accountId,
    List<LibraryTrack> tracks,
  ) async {
    await _db.deleteTracksForAccount(accountId);
    _tracks.removeWhere((t) => t.accountId == accountId);
    for (final track in tracks) {
      await _db.upsertTrack(track);
      _tracks.add(track);
    }
    notifyListeners();
  }

  LibraryTrack? find(String accountId, String remotePath) {
    try {
      return _tracks.firstWhere(
        (t) => t.accountId == accountId && t.remotePath == remotePath,
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
    required String accountId,
    required String remotePath,
    required String fileName,
    required String localPath,
  }) async {
    final now = DateTime.now();
    final read = await _tags.readFromFile(localPath);
    String? coverPath;
    if (read.coverBytes != null && read.coverBytes!.isNotEmpty) {
      coverPath = await _covers.saveThumb(
        accountId: accountId,
        remotePath: remotePath,
        bytes: read.coverBytes!,
      );
      // Best-effort full-res cache for library UI when file is local.
      await _covers.saveFull(
        accountId: accountId,
        remotePath: remotePath,
        bytes: read.coverBytes!,
      );
    } else {
      // Keep previous thumb if re-download has no art.
      final existing = await _db.getTrack(accountId, remotePath);
      coverPath = existing?.coverPath;
      if (coverPath != null && !File(coverPath).existsSync()) {
        coverPath = null;
      }
    }

    final track = LibraryTrack(
      accountId: accountId,
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
      (t) => t.accountId == accountId && t.remotePath == remotePath,
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
    required String accountId,
    required String cueRemotePath,
    required CueSheet sheet,
    required String cacheGroupId,
    required String Function(String remotePath) localPathFor,
  }) async {
    final now = DateTime.now();
    // Replace the whole CUE group so clear-cache + re-download cannot leave
    // orphan virtual rows or a leftover standalone audio row (+1 drift).
    await _db.deleteTracksForCue(accountId, cueRemotePath);
    _tracks.removeWhere(
      (t) => t.accountId == accountId && t.cueRemotePath == cueRemotePath,
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
        coverPath = await _covers.saveThumb(accountId: accountId, remotePath: virtualPath, bytes: bytes);
        await _covers.saveFull(accountId: accountId, remotePath: resolved, bytes: bytes);
      }
      final audioMid = musicIdForRemote(accountId, resolved);
      final sliceMid = musicIdForCueSlice(accountId, cueRemotePath, ct.number);
      final track = LibraryTrack(
        musicId: sliceMid,
        accountId: accountId,
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
        cueId: cueIdFor(accountId, cueRemotePath),
        cueRemotePath: cueRemotePath,
        cueTrackIndex: ct.number,
        audioMusicId: audioMid,
        audioRemotePath: resolved,
        clipStartMs: range.start.inMilliseconds,
        clipEndMs: range.end?.inMilliseconds,
        cacheGroupId: cacheGroupId,
        lastDownloadedAt: now,
        lastTagReadAt: now,
      );
      await _db.upsertTrack(track);
      final idx = _tracks.indexWhere((x) => x.accountId == accountId && x.remotePath == virtualPath);
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
      await _db.deleteTrack(accountId, path);
      _tracks.removeWhere((t) => t.accountId == accountId && t.remotePath == path);
    }
    // Also drop any row whose audioRemotePath is one of this album's files but
    // is not one of the virtual paths we just wrote (stale / wrong keys).
    final keepVirtual = created.map((t) => t.remotePath).toSet();
    final stale = _tracks
        .where(
          (t) =>
              t.accountId == accountId &&
              !keepVirtual.contains(t.remotePath) &&
              (t.cueRemotePath == cueRemotePath ||
                  (t.audioRemotePath != null &&
                      audioRemotes.contains(t.audioRemotePath)) ||
                  audioRemotes.contains(t.remotePath)),
        )
        .toList();
    for (final t in stale) {
      await _db.deleteTrack(t.accountId, t.remotePath);
      _tracks.removeWhere(
        (x) => x.accountId == t.accountId && x.remotePath == t.remotePath,
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

  /// Destroy tracks: drop their library rows **and** their cover thumbnails.
  ///
  /// Distinct from [removeTrack] (rows only) and from cache deletion (audio
  /// files only, metadata kept). CUE slices are grouped so the whole album's
  /// virtual rows disappear together.
  Future<void> destroyTracks(Iterable<LibraryTrack> tracks) async {
    final list = tracks.toList();
    if (list.isEmpty) return;
    final removedIds = <String>{};
    final cuePaths = <String>{};
    for (final t in list) {
      removedIds.add(t.musicId);
      if (t.isCueVirtual && t.cueRemotePath != null) {
        cuePaths.add('${t.accountId}\u0000${t.cueRemotePath}');
      }
    }
    // Cover thumbs + full-res covers live per identity; collect them before
    // deleting rows.
    for (final t in list) {
      await _covers.deleteThumb(t.accountId, t.remotePath);
      await _covers.deleteFull(t.accountId, t.remotePath);
    }
    for (final t in list) {
      if (t.isCueVirtual && t.cueRemotePath != null) {
        await _db.deleteTracksForCue(t.accountId, t.cueRemotePath!);
      } else {
        await _db.deleteTrack(t.accountId, t.remotePath);
      }
    }
    _tracks.removeWhere(
      (t) =>
          removedIds.contains(t.musicId) ||
          (t.isCueVirtual &&
              t.cueRemotePath != null &&
              cuePaths.contains('${t.accountId}\u0000${t.cueRemotePath}')),
    );
    notifyListeners();
  }

  Future<void> removeTrack(String accountId, String remotePath) async {
    await _db.deleteTrack(accountId, remotePath);
    _tracks.removeWhere((t) => t.accountId == accountId && t.remotePath == remotePath);
    notifyListeners();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}
