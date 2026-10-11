import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  group('playlist ↔ library status alignment', () {
    test('PlaylistEntry JSON has no remoteMissing (join is single source)', () {
      final id = musicIdForRemote('disk', '/a.mp3');
      final e = PlaylistEntry(
        sourceName: 'disk',
        remotePath: '/a.mp3',
        musicId: id,
        title: 'A',
      );
      final json = e.toJson();
      expect(json.containsKey('remoteMissing'), isFalse);
      expect(json['musicId'], id);
      final back = PlaylistEntry.fromJson({
        ...json,
        'remoteMissing': true, // stray sync field must be ignored
      });
      expect(back.toJson().containsKey('remoteMissing'), isFalse);
      expect(back.identityKey, id);
    });

    test('identityKey prefers explicit musicId', () {
      final id = musicIdForRemote('disk', '/real.mp3');
      const e = PlaylistEntry(
        sourceName: 'disk',
        remotePath: '/stale.mp3',
        musicId: 'explicit-id',
      );
      expect(e.identityKey, 'explicit-id');
      expect(musicIdForRemote('disk', '/stale.mp3'), isNot(id));
    });

    test('LibraryTrack.remoteMissing persists; playlist stays a reference', () {
      final t = LibraryTrack(
        sourceName: 'disk',
        remotePath: '/a.mp3',
        fileName: 'a.mp3',
        remoteMissing: true,
      );
      expect(t.toTrackTableMap()['remote_missing'], 1);
      final entry = PlaylistEntry(
        sourceName: t.sourceName,
        remotePath: t.remotePath,
        musicId: t.musicId,
        title: t.displayTitle,
      );
      // Destroying the library row leaves the entry; UI shows 库中暂无, not red.
      expect(entry.toJson().containsKey('remoteMissing'), isFalse);
    });

    test('TrackUiState.remoteMissing distinct from not-in-library', () {
      expect(TrackUiState.values.contains(TrackUiState.remoteMissing), isTrue);
      expect(TrackUiState.values.contains(TrackUiState.streamable), isTrue);
      // 「库中暂无」 is not a TrackUiState — playlist missing branch only.
    });
  });
}
