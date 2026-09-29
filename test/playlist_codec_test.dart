import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/playlist_codec.dart';
import 'package:webdav_media_manager/services/playlist_service.dart';
import 'package:webdav_media_manager/services/playlist_store.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';
import 'package:sqflite/sqflite.dart';

/// In-memory stand-in for the playlist sqlite table: these tests are about the
/// `WDMMPL01` bytes and the merge rule, never about sqflite.
class _MemoryPlaylistStore implements PlaylistStore {
  final Map<String, Playlist> rows = {};

  @override
  Future<Database> get database async => throw UnimplementedError();

  @override
  Future<List<Playlist>> loadAll() async => rows.values.toList();

  @override
  Future<Playlist?> getById(String id) async => rows[id];

  @override
  Future<void> upsert(Playlist playlist) async => rows[playlist.id] = playlist;

  @override
  Future<void> delete(String id) async => rows.remove(id);

  @override
  Future<void> clearAll() async => rows.clear();

  @override
  Future<void> replaceAll(List<Playlist> playlists) async {
    rows
      ..clear()
      ..addEntries(playlists.map((p) => MapEntry(p.id, p)));
  }

  @override
  Future<String> databasePath() async => 'memory:playlists.db';

  @override
  Future<void> close() async {}
}

class _FakeWebDav extends WebDavService {
  @override
  bool hasAccount(String accountId) => false;
}

Uint8List _blob(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i + seed) & 0xFF));

PlaylistEntry _plainEntry(String path) => PlaylistEntry(
  sourceName: '123pan',
  remotePath: path,
  musicId: musicIdForRemote('123pan', path),
  title: path.split('/').last,
  durationMs: 215000,
);

void main() {
  const cuePath = '/m/disc.cue';
  const cueAudio = '/m/disc.flac';

  group('歌单文档（WDMMPL01）', () {
    test('.wdmp 往返：名字、条目、时长与身份键都从文档里回来', () {
      final updatedAt = DateTime.utc(2026, 9, 20, 12, 30);
      final playlist = Playlist(
        id: 'pl-0001-abcd',
        name: '最爱',
        updatedAt: updatedAt,
        entries: [
          _plainEntry('/m/a.flac'),
          PlaylistEntry(
            sourceName: '123pan',
            remotePath: '$cueAudio#cue:2',
            musicId: musicIdForCueSlice('123pan', cuePath, 2),
            title: '第二首',
            durationMs: 180000,
            cueTrackIndex: 2,
          ),
        ],
      );

      final bytes = PlaylistCodec.encode(playlist, deviceId: 'dev-1');

      // 魔数：WDMM + PL + 01，与 META.kind 同源，不可能漂移。
      expect(WmpContainer.kindOf(bytes), WmpFileKind.playlist);
      expect(
        utf8.decode(bytes.sublist(0, 8)),
        'WDMM${WmpFileKind.playlist}${WmpContainer.layoutVersion}',
      );
      expect(PlaylistCodec.fileExtension, 'wdmp');

      final doc = PlaylistCodec.decode(bytes);
      expect(doc.entryCount, 2);
      expect(doc.deviceId, 'dev-1');
      expect(doc.playlist.id, 'pl-0001-abcd');
      expect(doc.playlist.name, '最爱');
      expect(doc.playlist.updatedAt, updatedAt);

      expect(doc.playlist.entries[0].sourceName, '123pan');
      expect(doc.playlist.entries[0].remotePath, '/m/a.flac');
      expect(doc.playlist.entries[0].title, 'a.flac');
      expect(doc.playlist.entries[0].durationMs, 215000);
      expect(doc.playlist.entries[0].cueTrackIndex, isNull);
      expect(
        doc.playlist.entries[0].identityKey,
        playlist.entries[0].identityKey,
      );

      expect(doc.playlist.entries[1].cueTrackIndex, 2);
      expect(doc.playlist.entries[1].musicId, musicIdForCueSlice('123pan', cuePath, 2));
      expect(
        doc.playlist.entries[1].identityKey,
        playlist.entries[1].identityKey,
      );
      // 身份键随文档走，不靠远端路径反推。
      expect(
        PlaylistCodec.decode(bytes).playlist.entries[1].identityKey,
        musicIdForCueSlice('123pan', cuePath, 2),
      );
    });

    test('musicId 与曲库同源：TrackInfo.musicId 正好命中歌单条目的身份键', () {
      final track = TrackInfo(
        sourceName: '123pan',
        accountId: 'acc-1',
        remotePath: '/m/a.flac',
        fileName: 'a.flac',
      );
      expect(track.musicId, musicIdForRemote('123pan', '/m/a.flac'));

      // 歌单侧写的就是同一个函数的结果 → 两边天然对齐。
      final entry = _plainEntry('/m/a.flac');
      expect(entry.identityKey, track.musicId);

      // CUE 虚拟切片：曲库行走 musicIdForLibraryRow 的切片分支。
      final slice = TrackInfo(
        sourceName: '123pan',
        accountId: 'acc-1',
        remotePath: '$cueAudio#cue:2',
        fileName: 'disc.flac',
        cueRemotePath: cuePath,
        cueTrackIndex: 2,
        audioRemotePath: cueAudio,
      );
      expect(slice.musicId, musicIdForCueSlice('123pan', cuePath, 2));

      final sliceEntry = PlaylistEntry(
        sourceName: '123pan',
        remotePath: '$cueAudio#cue:2',
        musicId: musicIdForCueSlice('123pan', cuePath, 2),
        cueTrackIndex: 2,
      );
      expect(sliceEntry.identityKey, slice.musicId);
    });

    test('CUE 切片区分：同一 .cue 的不同曲目各有身份，且都不等于整轨', () {
      final t1 = musicIdForCueSlice('123pan', cuePath, 1);
      final t2 = musicIdForCueSlice('123pan', cuePath, 2);
      final whole = musicIdForRemote('123pan', cueAudio);

      expect(t1, isNot(t2));
      expect(t1, isNot(whole));
      expect(t2, isNot(whole));
      // 换一张网盘就换身份。
      expect(musicIdForCueSlice('aliyun', cuePath, 1), isNot(t1));
      // 数字索引不按字符串拼接：1 与 10 不能撞。
      expect(musicIdForCueSlice('123pan', cuePath, 1), isNot(musicIdForCueSlice('123pan', cuePath, 10)));

      final a = PlaylistEntry(
        sourceName: '123pan',
        remotePath: '$cueAudio#cue:1',
        musicId: t1,
        cueTrackIndex: 1,
      );
      final b = PlaylistEntry(
        sourceName: '123pan',
        remotePath: '$cueAudio#cue:2',
        musicId: t2,
        cueTrackIndex: 2,
      );
      expect(a == b, isFalse);
      expect(a.hashCode, isNot(b.hashCode));

      // 文档往返后仍然互不相等（不是靠内存里的对象区分）。
      final doc = PlaylistCodec.decode(
        PlaylistCodec.encode(
          Playlist(id: 'pl-cue', name: 'CUE', entries: [a, b]),
        ),
      );
      expect(doc.playlist.entries[0].identityKey, isNot(doc.playlist.entries[1].identityKey));
      expect(doc.playlist.entries[0], isNot(doc.playlist.entries[1]));
    });

    test('缺显式 musicId 时，CUE 虚拟路径退回 backing audio 的整轨身份', () {
      // 这是文档里写明的兜底：虚拟路径反推不出 .cue 源路径，宁可解析到整轨。
      const legacy = PlaylistEntry(
        sourceName: '123pan',
        remotePath: '$cueAudio#cue:2',
        cueTrackIndex: 2,
      );
      expect(legacy.identityKey, musicIdForRemote('123pan', cueAudio));

      const plain = PlaylistEntry(
        sourceName: '123pan',
        remotePath: '/m/a.flac',
      );
      expect(plain.identityKey, musicIdForRemote('123pan', '/m/a.flac'));
    });

    test('封面：coverBlobs 与本条条目并行，索引指向自己那张图', () {
      final coverA = _blob(40, 1);
      final coverC = _blob(56, 3);
      final playlist = Playlist(
        id: 'pl-cover',
        name: '带封面',
        entries: [
          _plainEntry('/m/a.flac'),
          _plainEntry('/m/b.flac'),
          _plainEntry('/m/c.flac'),
        ],
      );

      final bytes = PlaylistCodec.encode(
        playlist,
        coverBlobs: [coverA, null, coverC],
        coverKinds: [WmpImageKind.jpeg, WmpImageKind.none, WmpImageKind.png],
      );
      final doc = PlaylistCodec.decode(bytes);

      expect(doc.coverCount, 2);
      expect(doc.coverFor(0), coverA);
      expect(doc.coverFor(1), isNull);
      expect(doc.coverFor(2), coverC);
      expect(doc.coverKindFor(0), WmpImageKind.jpeg);
      expect(doc.coverKindFor(1), WmpImageKind.none);
      expect(doc.coverKindFor(2), WmpImageKind.png);

      // 封面段走 rawIds：存储字节里就是原图，没被再压一次。
      final container = WmpContainer.fromBytes(bytes);
      final stored = container.storedBytes(WmpSections.covers);
      expect(
        _indexOf(stored, coverA),
        greaterThanOrEqualTo(0),
        reason: '封面段应以 raw codec 原样存储（不二次 deflate）',
      );
      expect(_indexOf(stored, coverC), greaterThanOrEqualTo(0));
    });

    test('没有封面时不写 COVERS 段，条目也不带 coverIndex', () {
      final bytes = PlaylistCodec.encode(
        Playlist(id: 'pl-bare', name: '无封面', entries: [_plainEntry('/m/a.flac')]),
      );
      final container = WmpContainer.fromBytes(bytes);
      expect(container.has(WmpSections.covers), isFalse);

      final doc = PlaylistCodec.decode(bytes);
      expect(doc.coverCount, 0);
      expect(doc.coverFor(0), isNull);
      expect(doc.coverKindFor(0), WmpImageKind.none);
      expect(doc.entryCount, 1);
    });

    test('safeFileName：清掉路径非法字符并把短 id 缀在后面', () {
      expect(
        PlaylistCodec.safeFileName('最爱/歌单:2026', 'abcdef123456'),
        '最爱_歌单_2026_abcdef12.wdmp',
      );
      expect(PlaylistCodec.safeFileName('  ', 'short'), 'playlist_short.wdmp');
      expect(
        PlaylistCodec.safeFileName('a b', 'abcdefghij'),
        'a_b_abcdefgh.wdmp',
      );
    });

    test('decode 拒绝 magic 与 META.kind 不一致的文档', () {
      // 伪造：PL 魔数，但 META.kind 写成 vault。
      final bogus = WmpContainer.encode(
        {
          WmpSections.meta: encodeRecords([
            {WmpMeta.kind: WmpKind.vault, WmpPlaylistMeta.playlistId: 'pl-x'},
          ]),
        },
        kind: WmpFileKind.playlist,
      );
      expect(
        () => PlaylistCodec.decode(bogus),
        throwsA(
          isA<WmpFormatException>().having(
            (e) => e.message,
            'message',
            contains('err.playlistKindMismatch'),
          ),
        ),
      );
    });

    test('decode 拒绝没有 playlistId 的文档（不静默造一个空歌单）', () {
      final bogus = WmpContainer.encode(
        {
          WmpSections.meta: encodeRecords([
            {WmpMeta.kind: WmpKind.playlist, WmpMeta.count: 0},
          ]),
        },
        kind: WmpFileKind.playlist,
      );
      expect(
        () => PlaylistCodec.decode(bogus),
        throwsA(
          isA<WmpFormatException>().having(
            (e) => e.message,
            'message',
            'err.playlistMissingId',
          ),
        ),
      );
    });
  });

  group('歌单与曲库相互独立', () {
    test('合并远端歌单时，曲库里没有对应行也不丢条目', () async {
      final store = _MemoryPlaylistStore();
      final service = PlaylistService(store: store, webDav: _FakeWebDav());

      // 远端来的歌单：条目引用的是本机曲库里根本不存在的行。
      final remote = Playlist(
        id: 'pl-remote',
        name: '远端歌单',
        updatedAt: DateTime.utc(2026, 9, 20),
        entries: [
          _plainEntry('/m/gone.flac'),
          PlaylistEntry(
            sourceName: '123pan',
            remotePath: '$cueAudio#cue:3',
            musicId: musicIdForCueSlice('123pan', cuePath, 3),
            cueTrackIndex: 3,
          ),
        ],
      );

      await service.mergeFromPlaylists([remote]);

      expect(service.playlists, hasLength(1));
      final stored = service.playlists.single;
      expect(stored.id, 'pl-remote');
      expect(stored.entries, hasLength(2));
      expect(stored.entries[0].remotePath, '/m/gone.flac');
      // 身份键照样算得出来——歌单不查曲库。
      expect(stored.entries[1].identityKey, musicIdForCueSlice('123pan', cuePath, 3));
      expect(store.rows['pl-remote'], isNotNull);

      // 再走一次二进制往返：条目仍然完整。
      final back = PlaylistCodec.decode(
        PlaylistCodec.encode(stored),
      ).playlist;
      expect(back.entries, hasLength(2));
      expect(back.entries[0].identityKey, stored.entries[0].identityKey);
      expect(back.entries[1].identityKey, stored.entries[1].identityKey);
    });

    test('合并采用 last-write-wins：更新的远端版本覆盖本地', () async {
      final store = _MemoryPlaylistStore();
      final service = PlaylistService(store: store, webDav: _FakeWebDav());

      final older = Playlist(
        id: 'pl-1',
        name: '旧',
        updatedAt: DateTime.utc(2026, 9, 1),
        entries: [_plainEntry('/m/a.flac')],
      );
      await service.mergeFromPlaylists([older]);

      final newer = Playlist(
        id: 'pl-1',
        name: '新',
        updatedAt: DateTime.utc(2026, 9, 2),
        entries: [_plainEntry('/m/a.flac'), _plainEntry('/m/b.flac')],
      );
      await service.mergeFromPlaylists([newer]);
      expect(service.playlists.single.name, '新');
      expect(service.playlists.single.entries, hasLength(2));

      // 时间戳更旧的远端版本不能把本地写回旧状态。
      await service.mergeFromPlaylists([older]);
      expect(service.playlists.single.name, '新');
      expect(service.playlists.single.entries, hasLength(2));
    });

    test('合并不会删掉远端没提到的本地歌单', () async {
      final store = _MemoryPlaylistStore();
      final service = PlaylistService(store: store, webDav: _FakeWebDav());
      await service.mergeFromPlaylists([
        Playlist(id: 'pl-keep', name: '本地留着', entries: []),
      ]);
      await service.mergeFromPlaylists([
        Playlist(id: 'pl-other', name: '远端新增', entries: []),
      ]);
      expect(
        service.playlists.map((p) => p.id),
        containsAll(<String>['pl-keep', 'pl-other']),
      );
    });
  });
}

/// First index of [needle] inside [haystack], or -1.
int _indexOf(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty || needle.length > haystack.length) return -1;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return i;
  }
  return -1;
}
