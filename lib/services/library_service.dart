import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;

import '../models/library_track.dart';
import '../utils/audio_extensions.dart';
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
        (t) => t.accountId == track.accountId && t.remotePath == track.remotePath,
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

  /// After a file finishes downloading: read tags, save thumb + full cover, upsert.
  Future<LibraryTrack> ingestDownloaded({
    required String accountId,
    required String remotePath,
    required String fileName,
    required String localPath,
  }) async {
    final now = DateTime.now();
    if (!isAudioFileName(fileName) && !isAudioFileName(remotePath)) {
      throw StateError('非音频文件不会加入音乐库: $fileName');
    }
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
      final track = LibraryTrack(
        accountId: accountId, remotePath: virtualPath,
        fileName: merged.title ?? ct.title ?? '${ct.number}',
        title: merged.title, artist: merged.artist, albumArtist: merged.albumArtist, album: merged.album,
        durationMs: durationMs, trackNumber: merged.trackNumber, trackTotal: sheet.tracks.length,
        year: merged.year, genre: merged.genre, bitrate: fileTag.bitrate, sampleRate: fileTag.sampleRate,
        coverPath: coverPath, cueRemotePath: cueRemotePath, cueTrackIndex: ct.number,
        audioRemotePath: resolved, clipStartMs: range.start.inMilliseconds, clipEndMs: range.end?.inMilliseconds,
        cacheGroupId: cacheGroupId, lastDownloadedAt: now, lastTagReadAt: now,
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
    // Drop any accidental standalone rows for the .cue itself or raw audio
    // files — library should only keep virtual tracks for this album.
    final removePaths = <String>{cueRemotePath, ...sheet.audioRemotePaths(cueRemotePath)};
    for (final path in removePaths) {
      await _db.deleteTrack(accountId, path);
      _tracks.removeWhere((t) => t.accountId == accountId && t.remotePath == path);
    }

    notifyListeners();
    return created;
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
