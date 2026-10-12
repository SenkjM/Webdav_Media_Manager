import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';
import 'package:webdav_media_manager/services/playlist_codec.dart';

void main() {
  group('playlist ↔ library status alignment', () {
    test('PlaylistEntry JSON mirrors remoteMissing independently', () {
      final id = musicIdForRemote('disk', '/a.mp3');
      final e = PlaylistEntry(
        sourceName: 'disk',
        remotePath: '/a.mp3',
        musicId: id,
        title: 'A',
        remoteMissing: true,
      );
      final json = e.toJson();
      expect(json['remoteMissing'], isTrue);
      expect(json['musicId'], id);
      final back = PlaylistEntry.fromJson(json);
      expect(back.remoteMissing, isTrue);
      expect(back.identityKey, id);
      final clear = back.copyWith(remoteMissing: false);
      expect(clear.toJson().containsKey('remoteMissing'), isFalse);
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

    test('LibraryTrack.remoteMissing and PlaylistEntry.remoteMissing are independent', () {
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
        remoteMissing: false,
      );
      // Destroying the library row leaves the entry; entry flag stays its own.
      expect(entry.remoteMissing, isFalse);
      expect(entry.copyWith(remoteMissing: true).remoteMissing, isTrue);
    });

    test('TrackUiState.remoteMissing distinct from not-in-library', () {
      expect(TrackUiState.values.contains(TrackUiState.remoteMissing), isTrue);
      expect(TrackUiState.values.contains(TrackUiState.streamable), isTrue);
    });

    test('wdmp ENTRIES round-trips remoteMissing', () {
      final pl = Playlist(
        id: 'p1',
        name: 'T',
        entries: [
          PlaylistEntry(
            sourceName: 'disk',
            remotePath: '/a.mp3',
            musicId: musicIdForRemote('disk', '/a.mp3'),
            title: 'A',
            remoteMissing: true,
          ),
        ],
      );
      final bytes = PlaylistCodec.encode(pl);
      final decoded = PlaylistCodec.decode(bytes);
      expect(decoded.playlist.entries.single.remoteMissing, isTrue);
      expect(WmpPlaylistEntry.remoteMissing, 8);
    });
  });
}
