import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/services/library_service.dart';

LibraryTrack _t({
  required String file,
  String? title,
  String? album,
  String? artist,
  int? track,
  int? disc,
}) {
  return LibraryTrack(
    sourceName: 'a',
    remotePath: '/$file',
    fileName: file,
    title: title,
    album: album,
    artist: artist,
    trackNumber: track,
    discNumber: disc,
  );
}

void main() {
  group('compareTracksByName', () {
    test('sorts by display title case-insensitively', () {
      final a = _t(file: 'z.mp3', title: 'Banana');
      final b = _t(file: 'a.mp3', title: 'apple');
      final c = _t(file: 'm.mp3', title: 'Cherry');
      final list = [a, c, b]..sort(compareTracksByName);
      expect(list.map((t) => t.displayTitle).toList(),
          ['apple', 'Banana', 'Cherry']);
    });

    test('falls back to fileName when title missing', () {
      final a = _t(file: 'beta.mp3');
      final b = _t(file: 'alpha.mp3');
      final list = [a, b]..sort(compareTracksByName);
      expect(list.first.fileName, 'alpha.mp3');
    });
  });

  group('compareTracksByAlbumOrder', () {
    test('orders by disc then track', () {
      final t1 = _t(file: '1.mp3', title: 'One', track: 1, disc: 1);
      final t2 = _t(file: '2.mp3', title: 'Two', track: 2, disc: 1);
      final t3 = _t(file: '3.mp3', title: 'Disc2', track: 1, disc: 2);
      final list = [t3, t2, t1]..sort(compareTracksByAlbumOrder);
      expect(list.map((t) => t.title).toList(), ['One', 'Two', 'Disc2']);
    });

    test('missing track number sorts after numbered tracks', () {
      final numbered = _t(file: '1.mp3', title: 'A', track: 1);
      final missing = _t(file: 'x.mp3', title: 'Z');
      final list = [missing, numbered]..sort(compareTracksByAlbumOrder);
      expect(list.first.title, 'A');
      expect(list.last.title, 'Z');
    });

    test('missing disc defaults to 1', () {
      final d1 = _t(file: 'a.mp3', title: 'A', track: 2); // disc null => 1
      final d2 = _t(file: 'b.mp3', title: 'B', track: 1, disc: 2);
      final list = [d2, d1]..sort(compareTracksByAlbumOrder);
      expect(list.first.title, 'A');
    });
  });

  group('LibraryTrack map roundtrip includes track/disc', () {
    test('persists trackNumber and discNumber', () {
      final t = _t(file: 's.mp3', title: 'Song', track: 7, disc: 2);
      final map = t.toMap();
      expect(map['track_number'], 7);
      expect(map['disc_number'], 2);
      final back = LibraryTrack.fromMap(map);
      expect(back.trackNumber, 7);
      expect(back.discNumber, 2);
    });
  });

  group('LibraryService grouping album order', () {
    test('groupedByAlbum sorts tracks by album order', () {
      final svc = LibraryService();
      // Inject via private path: use byTitle-like approach — call sortedCopy.
      final tracks = [
        _t(file: 'b.mp3', title: 'B', album: 'X', track: 2),
        _t(file: 'a.mp3', title: 'A', album: 'X', track: 1),
      ];
      final sorted =
          svc.sortedCopy(tracks, sort: LibrarySortMode.byAlbumTrack);
      expect(sorted.map((t) => t.title).toList(), ['A', 'B']);
    });
  });

  group('LibrarySortMode storage', () {
    test('roundtrips keys', () {
      expect(LibrarySortMode.byName.storageKey, 'name');
      expect(LibrarySortMode.byAlbumTrack.storageKey, 'album_track');
      expect(LibrarySortModeX.fromStorageKey('album_track'),
          LibrarySortMode.byAlbumTrack);
      expect(LibrarySortModeX.fromStorageKey(null), LibrarySortMode.byName);
    });
  });
}
