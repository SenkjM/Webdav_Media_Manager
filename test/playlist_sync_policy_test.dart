import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  group('playlist identity', () {
    test('entry identity is the library music_id (docs/10 §4.4)', () {
      const e = PlaylistEntry(sourceName: 'acc-1', remotePath: '/Music/a.mp3');
      // 权威身份是 music_id（归一化后的 sha1），不是裸的 "网盘名\0路径" 串。
      expect(e.identityKey, musicIdForRemote('acc-1', '/Music/a.mp3'));
      expect(
        e.identityKey,
        isNot(trackIdentityKey('acc-1', '/Music/a.mp3')),
      );
      // 归一化：斜杠变体、首尾空格不改变身份。
      expect(
        e.identityKey,
        const PlaylistEntry(
          sourceName: ' acc-1 ',
          remotePath: 'Music//a.mp3',
        ).identityKey,
      );
      expect(
        e,
        const PlaylistEntry(sourceName: 'acc-1', remotePath: '/Music/a.mp3'),
      );
      expect(
        e ==
            const PlaylistEntry(
              sourceName: 'acc-2',
              remotePath: '/Music/a.mp3',
            ),
        isFalse,
      );
      // CUE 切片：显式 musicId 优先，没有时退回 backing audio 的整轨身份。
      const slice = PlaylistEntry(
        sourceName: 'acc-1',
        remotePath: '/Music/disc.flac#cue:2',
        musicId: 'slice-2',
        cueTrackIndex: 2,
      );
      expect(slice.identityKey, 'slice-2');
      expect(
        const PlaylistEntry(
          sourceName: 'acc-1',
          remotePath: '/Music/disc.flac#cue:2',
        ).identityKey,
        musicIdForRemote('acc-1', '/Music/disc.flac'),
      );
    });
  });

  group('last-write-wins merge', () {
    test('newer remote wins', () {
      final local = Playlist(
        id: 'p1',
        name: 'local',
        updatedAt: DateTime.utc(2026, 1, 1),
        entries: const [PlaylistEntry(sourceName: 'a', remotePath: '/x.mp3')],
      );
      final remote = Playlist(
        id: 'p1',
        name: 'remote',
        updatedAt: DateTime.utc(2026, 2, 1),
        entries: const [PlaylistEntry(sourceName: 'a', remotePath: '/y.mp3')],
      );
      final merged = mergePlaylistsLastWriteWins(local, remote);
      expect(merged.name, 'remote');
      expect(merged.entries.single.remotePath, '/y.mp3');
    });

    test('equal timestamp keeps local', () {
      final t = DateTime.utc(2026, 3, 1);
      final local = Playlist(id: 'p1', name: 'local', updatedAt: t);
      final remote = Playlist(id: 'p1', name: 'remote', updatedAt: t);
      expect(mergePlaylistsLastWriteWins(local, remote).name, 'local');
    });

    test('newer local wins', () {
      final local = Playlist(
        id: 'p1',
        name: 'local',
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final remote = Playlist(
        id: 'p1',
        name: 'remote',
        updatedAt: DateTime.utc(2026, 4, 1),
      );
      expect(mergePlaylistsLastWriteWins(local, remote).name, 'local');
    });
  });
}
