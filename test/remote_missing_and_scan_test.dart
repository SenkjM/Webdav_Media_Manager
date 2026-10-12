import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/utils/directory_walk.dart';

void main() {
  test('LibraryTrack remoteMissing round-trips in map', () {
    final t = LibraryTrack(
      sourceName: 'disk',
      remotePath: '/a.mp3',
      fileName: 'a.mp3',
      remoteMissing: true,
    );
    final map = t.toTrackTableMap();
    expect(map['remote_missing'], 1);
    final back = LibraryTrack.fromMap(map);
    expect(back.remoteMissing, isTrue);
  });

  test('TrackUiState has remoteMissing', () {
    expect(TrackUiState.values.contains(TrackUiState.remoteMissing), isTrue);
  });

  test('WalkOptions media scrape defaults', () {
    const w = WalkOptions(includeSubdirs: true, maxDepth: 1);
    expect(w.effectiveMaxDepth, 1);
    expect(w.includeSubdirs, isTrue);
  });
}
