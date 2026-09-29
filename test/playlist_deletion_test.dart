import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/models/playlist_deletion.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/playlist_codec.dart';
import 'package:webdav_media_manager/services/playlist_deletion_codec.dart';
import 'package:webdav_media_manager/services/playlist_deletion_log.dart';
import 'package:webdav_media_manager/services/playlist_service.dart';
import 'package:webdav_media_manager/services/playlist_store.dart';
import 'package:webdav_media_manager/services/playlist_sync_plan.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';
import 'package:sqflite/sqflite.dart';

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

class _MemDav extends WebDavService {
  final Map<String, Uint8List> files = {};
  final List<String> writes = [];

  @override
  bool hasAccount(String accountId) => true;

  @override
  Future<void> ensureDirectory(String accountId, String path) async {}

  @override
  Future<List<WebDavItem>> listDirectory(
    String accountId,
    String path, {
    FileTypeConfig? fileTypes,
  }) async {
    return [
      for (final entry in files.entries)
        WebDavItem(
          name: entry.key.split('/').last,
          path: entry.key,
          isDirectory: false,
          size: entry.value.length,
        ),
    ];
  }

  @override
  Future<Uint8List> readAsBytes(String accountId, String remotePath) async {
    final bytes = files[remotePath];
    if (bytes == null) throw Exception('404 $remotePath');
    return bytes;
  }

  @override
  Future<void> writeBytes(
    String accountId,
    String remotePath,
    Uint8List data,
  ) async {
    writes.add('PUT $remotePath');
    files[remotePath] = data;
  }

  @override
  Future<void> deletePath(String accountId, String path) async {
    writes.add('DEL $path');
    files.remove(path);
  }
}

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

  group('删除记录包（WDMMPD01）', () {
    test('包内用种类和段区分，不只靠文件名', () {
      final bytes = PlaylistDeletionCodec.encode('pl-1', [
        PlaylistDeletion(
          playlistId: 'pl-1',
          entryIdentity: 'music-a',
          deletedAt: t1,
        ),
        PlaylistDeletion(playlistId: 'pl-1', deletedAt: t2),
      ]);

      expect(WmpContainer.kindOf(bytes), WmpFileKind.playlistDeletion);
      expect(WmpContainer.kindOf(bytes), isNot(WmpFileKind.tomb));
      expect(WmpContainer.kindOf(bytes), isNot(WmpFileKind.playlist));
      final container = WmpContainer.fromBytes(bytes);
      expect(container.has(WmpSections.playlistDeletions), isTrue);
      expect(container.has(WmpSections.tombs), isFalse);
      expect(container.has(WmpSections.entries), isFalse);

      final decoded = PlaylistDeletionCodec.decode(bytes);
      expect(decoded.playlistId, 'pl-1');
      // 整单删除压过同包里的单曲记录：解码仍保留两条，合并时再折叠。
      expect(decoded.records, hasLength(2));

      expect(
        () => PlaylistCodec.decode(bytes),
        throwsA(isA<WmpFormatException>()),
      );

      // 文件名可以不同，身份在包内。
      expect(PlaylistDeletionCodec.fileNameFor('pl-1'), 'pdel_pl-1.wdmp');
      expect(
        PlaylistDeletionCodec.looksLikePackName('not-a-pack.wdmp'),
        isFalse,
      );
      final renamed = PlaylistDeletionCodec.decode(bytes);
      expect(renamed.playlistId, 'pl-1');
    });
  });

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

  group('拉取不会复活', () {
    late _MemoryPlaylistStore store;
    late MemoryPlaylistDeletionLog log;
    late _MemDav dav;
    late PlaylistService service;

    setUp(() {
      store = _MemoryPlaylistStore();
      log = MemoryPlaylistDeletionLog();
      dav = _MemDav();
      service = PlaylistService(store: store, deletions: log, webDav: dav);
      service.configureSync(
        remotePath: '/Playlists/',
        enabled: true,
        accountId: 'acc',
      );
    });

    test('文件名不像删除包时，仍按包内种类认删整单', () async {
      final local = _playlist(
        id: 'pl-9',
        updatedAt: t3,
        entries: [_entry('/a.mp3'), _entry('/b.mp3')],
        remoteFileName: 'loved.wdmp',
      );
      await service.mergeFromPlaylists([local]);
      dav.files['/Playlists/loved.wdmp'] = PlaylistCodec.encode(local);
      dav.files['/Playlists/weird.wdmp'] = PlaylistDeletionCodec.encode(
        'pl-9',
        [PlaylistDeletion(playlistId: 'pl-9', deletedAt: t1)],
      );

      final ok = await service.pullAndMergeFromWebDav();

      expect(ok, isTrue);
      expect(service.playlists, isEmpty);
      expect(dav.writes.where((w) => w.startsWith('PUT ')).toList(), [
        'PUT /Playlists/${PlaylistDeletionCodec.fileNameFor('pl-9')}',
      ]);
      expect(dav.files.containsKey('/Playlists/loved.wdmp'), isFalse);
      expect(dav.files.containsKey('/Playlists/weird.wdmp'), isFalse);
      expect(
        dav.files.containsKey(
          '/Playlists/${PlaylistDeletionCodec.fileNameFor('pl-9')}',
        ),
        isTrue,
      );
    });

    test('远端文档更新时不会把本地旧歌单传回去', () async {
      final local = _playlist(
        id: 'pl',
        updatedAt: t0,
        entries: [_entry('/a.mp3'), _entry('/b.mp3')],
      );
      final remote = _playlist(
        id: 'pl',
        updatedAt: t2,
        entries: [_entry('/a.mp3')],
      );
      await service.mergeFromPlaylists([local]);
      dav.files['/Playlists/list.wdmp'] = PlaylistCodec.encode(remote);

      await service.pullAndMergeFromWebDav();

      expect(service.playlists.single.entries, hasLength(1));
      expect(dav.writes, isEmpty);
    });

    test('清理删除记录会删包，且不留下复活用的墓碑', () async {
      final local = _playlist(
        id: 'pl',
        updatedAt: t0,
        entries: [_entry('/a.mp3')],
        remoteFileName: 'list.wdmp',
      );
      await service.mergeFromPlaylists([local]);
      dav.files['/Playlists/list.wdmp'] = PlaylistCodec.encode(local);
      dav.files['/Playlists/${PlaylistDeletionCodec.fileNameFor('pl')}'] =
          PlaylistDeletionCodec.encode('pl', [
            PlaylistDeletion(playlistId: 'pl', deletedAt: t2),
          ]);

      await service.compactDeletionQueue();

      expect(service.playlists, isEmpty);
      expect(await log.loadAll(), isEmpty);
      expect(dav.files.keys.where((k) => k.endsWith('.wdmp')), isEmpty);
    });
  });
}
