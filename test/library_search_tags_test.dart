import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/services/library_service.dart';

LibraryTrack _t({
  required String path,
  String? title,
  String? artist,
  String? album,
  String? genre,
}) {
  return LibraryTrack(
    sourceName: 'a',
    remotePath: path,
    fileName: path.split('/').last,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
  );
}

void main() {
  test('search matches title artist album', () {
    final svc = LibraryService();
    svc.debugSetTracksForTest([
      _t(path: '/1.mp3', title: 'Blue Moon', artist: 'Jazz Band', album: 'Night'),
      _t(path: '/2.mp3', title: 'Red Sun', artist: 'Rockers', album: 'Day'),
    ]);
    expect(svc.search('moon').map((t) => t.title), ['Blue Moon']);
    expect(svc.search('rock').map((t) => t.title), ['Red Sun']);
    expect(svc.search('night').map((t) => t.title), ['Blue Moon']);
  });

  test('genre grouping and filter', () {
    final svc = LibraryService();
    svc.debugSetTracksForTest([
      _t(path: '/1.mp3', title: 'A', genre: 'Jazz'),
      _t(path: '/2.mp3', title: 'B', genre: 'jazz'),
      _t(path: '/3.mp3', title: 'C'),
      _t(path: '/4.mp3', title: 'D', genre: 'Rock'),
    ]);
    final genres = svc.allGenres();
    expect(genres.length, 2);
    expect(genres.map((g) => g.toLowerCase()).toSet(), {'jazz', 'rock'});
    expect(svc.tracksWithGenre('Jazz').length, 2);
    final grouped = svc.groupedByGenre();
    expect(grouped.containsKey('未分类'), isTrue);
    expect(grouped['未分类']!.single.title, 'C');
  });
}
