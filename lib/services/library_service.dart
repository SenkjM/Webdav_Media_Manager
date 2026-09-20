import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/library_track.dart';
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

  Future<void> init() async {
    await _db.database;
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

  LibraryTrack? find(String accountId, String remotePath) {
    try {
      return _tracks.firstWhere(
        (t) => t.accountId == accountId && t.remotePath == remotePath,
      );
    } catch (_) {
      return null;
    }
  }

  /// After a file finishes downloading: read tags, save 100×100 cover, upsert.
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
      album: read.album,
      durationMs: read.durationMs,
      trackNumber: read.trackNumber,
      discNumber: read.discNumber,
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

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}
