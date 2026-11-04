import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/models/playlist_deletion.dart';
import 'package:webdav_media_manager/services/playlist_sync_plan.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

PlaylistEntry _entry(String path) => PlaylistEntry(
  sourceName: '盘',
  remotePath: path,
  musicId: musicIdForRemote('盘', path),
  title: path,
);

Playlist _playlist({
  required String id,
  required DateTime updatedAt,
  required List<PlaylistEntry> entries,
  String name = '歌单',
  String? remoteFileName,
}) {
  return Playlist(
    id: id,
    name: name,
    updatedAt: updatedAt,
    remoteFileName: remoteFileName,
    entries: entries,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 2, 1);
  final t2 = DateTime.utc(2026, 3, 1);
  final t3 = DateTime.utc(2026, 4, 1);

  // The `WDMMPD01` pack codec and the "pull does not resurrect" service tests
  // moved to Rust: `wdmm_playlist_encode/decode` (`crates/wdmm-ffi/src/ext/
  // sync_codec.rs`) and the document tests in `crates/wdmm-sync/src/wmp.rs`
  // (`PlaylistDeletionDocument`), because `flutter test` cannot load
  // `libwdmm_ffi`. Only the pure merge plan stays here.
  group('合并计划', () {
    test('远端更新且内容已是胜者时，不回传本地副本', () {
      final local = _playlist(
        id: 'pl',
        updatedAt: t0,
        entries: [_entry('/a.mp3'), _entry('/b.mp3')],
      );
      final remote = _playlist(
        id: 'pl',
        updatedAt: t2,
        entries: [_entry('/a.mp3')],
        remoteFileName: '歌单_pl.wdmp',
      );
      final plan = planPlaylistSync(
        local: [local],
        remote: [remote],
        tombstones: const [],
        remotePacks: const {},
      );
      expect(plan.upload, isEmpty);
      expect(plan.playlists.single.entries, hasLength(1));
      expect(plan.playlists.single.remoteFileName, '歌单_pl.wdmp');
    });

    test('删掉的歌单不会因为本地还在而被上传', () {
      final local = _playlist(
        id: 'pl',
        updatedAt: t3,
        entries: [_entry('/a.mp3')],
        remoteFileName: '歌单_pl.wdmp',
      );
      final plan = planPlaylistSync(
        local: [local],
        remote: const [],
        tombstones: [PlaylistDeletion(playlistId: 'pl', deletedAt: t1)],
        remotePacks: {
          'pl': [PlaylistDeletion(playlistId: 'pl', deletedAt: t1)],
        },
      );
      expect(plan.playlists, isEmpty);
      expect(plan.upload, isEmpty);
      expect(plan.deleteRemoteNames, ['歌单_pl.wdmp']);
      expect(plan.uploadPackIds, isEmpty);
    });

    test('曲目墓碑从胜出的整份文档里滤掉，顺序不跟另一份混', () {
      final local = _playlist(
        id: 'pl',
        updatedAt: t0,
        entries: [_entry('/b.mp3'), _entry('/a.mp3')],
      );
      final remote = _playlist(
        id: 'pl',
        updatedAt: t2,
        name: '远端',
        entries: [_entry('/a.mp3'), _entry('/c.mp3'), _entry('/b.mp3')],
        remoteFileName: 'list.wdmp',
      );
      final dropped = _entry('/c.mp3').identityKey;
      final plan = planPlaylistSync(
        local: [local],
        remote: [remote],
        tombstones: [
          PlaylistDeletion(
            playlistId: 'pl',
            entryIdentity: dropped,
            deletedAt: t2,
          ),
        ],
        remotePacks: const {},
      );
      expect(plan.playlists.single.entries.map((e) => e.remotePath).toList(), [
        '/a.mp3',
        '/b.mp3',
      ]);
      expect(plan.playlists.single.name, '远端');
      expect(plan.upload, hasLength(1));
    });

    test('比墓碑更新的文档保留重新加入的曲目', () {
      final kept = _entry('/b.mp3');
      final local = _playlist(
        id: 'pl',
        updatedAt: t3,
        entries: [_entry('/a.mp3'), kept],
      );
      final plan = planPlaylistSync(
        local: [local],
        remote: [
          _playlist(
            id: 'pl',
            updatedAt: t0,
            entries: [_entry('/a.mp3')],
            remoteFileName: 'list.wdmp',
          ),
        ],
        tombstones: [
          PlaylistDeletion(
            playlistId: 'pl',
            entryIdentity: kept.identityKey,
            deletedAt: t1,
          ),
        ],
        remotePacks: const {},
      );
      expect(plan.playlists.single.entries, hasLength(2));
      expect(plan.upload, hasLength(1));
    });
  });
}
