// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/manga.dart';
import 'package:webdav_media_manager/models/manga_progress.dart';
import 'package:webdav_media_manager/models/manga_series.dart';
import 'package:webdav_media_manager/services/backup_service.dart';
import 'package:webdav_media_manager/services/library_sync_store.dart';
import 'package:webdav_media_manager/services/manga_sync_store.dart';
import 'package:webdav_media_manager/services/user_folder_sync.dart';
import 'package:webdav_media_manager/utils/manga_identity.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';

MangaSyncRow _row(String path, int rev, {int pageCount = 0}) {
  final sid = mangaSeriesIdForTitle('系列');
  return MangaSyncRow(
    manga: Manga(
      id: mangaIdForRemote('盘', path),
      sourceName: '盘',
      remotePath: path,
      title: 'T$path',
      seriesId: sid,
      pageCount: pageCount,
      format: MangaFormat.unknown,
      updatedAt: DateTime.utc(2026, 1, 1),
      rev: rev,
    ),
    series: MangaSeries(
      id: sid,
      title: '系列',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

void main() {
  group('manga shard codec', () {
    test('round-trips rows, series and per-row covers (no page order)', () {
      final cover = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);
      final bytes = MangaShardCodec.encodeMangaShard(
        kind: WmpKind.seg,
        deviceId: 'dev',
        revFrom: 1,
        revTo: 2,
        rows: [_row('/a.cbz', 1, pageCount: 2), _row('/b', 2)],
        coverBlobs: [cover, null],
      );
      final d = MangaShardCodec.decode(bytes);
      expect(d.kind, WmpKind.seg);
      expect(d.rows, hasLength(2));
      expect(d.rows[0].manga.pageCount, 2);
      expect(d.rows[0].manga.rev, 1);
      expect(d.rows[0].series?.title, '系列');
      expect(d.rows[0].manga.id, mangaIdForRemote('盘', '/a.cbz'));
      expect(d.coverFor(0), cover);
      expect(d.coverFor(1), isNull);
    });

    test('page order never enters a shard record (tag 18 retired)', () {
      final rec = MangaShardCodec.rowToRecord(_row('/a.cbz', 1, pageCount: 3));
      expect(rec.containsKey(18), isFalse);
      expect(rec[WmpManga.pageCount], 3);
    });

    test('series id is deterministic across devices', () {
      expect(mangaSeriesIdForTitle(' X '), mangaSeriesIdForTitle('X'));
      expect(mangaSeriesIdForTitle('X'), isNot(mangaSeriesIdForTitle('Y')));
    });
  });

  group('manga merge', () {
    test('higher rev wins regardless of order', () {
      final m = mergeMangaCloudParts(
        dataParts: [
          [_row('/a', 5)],
          [_row('/a', 3)],
        ],
        tombstoneParts: const [],
      );
      expect(m.rows.single.rev, 5);
    });

    test('tombstone hides only rows at or below its rev', () {
      final m = mergeMangaCloudParts(
        dataParts: [
          [_row('/a', 5), _row('/b', 9)],
        ],
        tombstoneParts: [
          [
            {'source_name': '盘', 'remote_path': '/a', 'rev': 5},
            {'source_name': '盘', 'remote_path': '/b', 'rev': 6},
          ],
        ],
      );
      expect(m.rows.map((r) => r.manga.remotePath), ['/b']);
      expect(m.tombstonedKeys, hasLength(2));
    });

    test('rebuild chunks are sorted and sized', () {
      final chunks = chunkMangaRowsForRebuild([
        _row('/c', 1),
        _row('/a', 1),
        _row('/b', 1),
      ], perShard: 2);
      expect(chunks.map((c) => c.length), [2, 1]);
      expect(chunks.first.first.manga.remotePath, '/a');
    });
  });

  group('manga progress', () {
    MangaProgress p(String id, int page, int minute) => MangaProgress(
      mangaId: id,
      pageIndex: page,
      updatedAt: DateTime.utc(2026, 1, 1, 0, minute),
    );

    test('per entry, newer updatedAt wins', () {
      final r = mergeMangaProgress(
        local: [p('a', 3, 5), p('b', 1, 1)],
        cloud: [p('a', 9, 1), p('b', 7, 9), p('c', 2, 2)],
      );
      expect(r.merged['a']!.pageIndex, 3);
      expect(r.merged['b']!.pageIndex, 7);
      expect(r.merged['c']!.pageIndex, 2);
      expect(r.toApplyLocally.map((e) => e.mangaId).toSet(), {'b', 'c'});
      expect(r.cloudNeedsUpdate, isTrue);
    });

    test('identical sides need nothing', () {
      final r = mergeMangaProgress(
        local: [p('a', 1, 1)],
        cloud: [p('a', 1, 1)],
      );
      expect(r.toApplyLocally, isEmpty);
      expect(r.cloudNeedsUpdate, isFalse);
    });

    test('progress.json round-trips', () {
      final bytes = encodeMangaProgressDoc([p('a', 4, 3)], deviceId: 'd');
      final back = decodeMangaProgressDoc(bytes);
      expect(back.single.pageIndex, 4);
      expect(back.single.updatedAt.toUtc(), DateTime.utc(2026, 1, 1, 0, 3));
      expect(
        decodeMangaProgressDoc(Uint8List.fromList(utf8.encode('{}'))),
        isEmpty,
      );
    });
  });

  group('user folder sync', () {
    const t = '2026-01-01T00:00:10.000Z';
    final tMs = DateTime.parse(t).millisecondsSinceEpoch;

    test('no cloud file: push only if something exists', () {
      expect(
        planFolderSync(
          localChangedAtMs: 0,
          lastSyncAtMs: 0,
          cloudUpdatedAt: null,
          lastSeenCloudUpdatedAt: null,
          localEmpty: true,
        ),
        FolderSyncAction.none,
      );
      expect(
        planFolderSync(
          localChangedAtMs: 1,
          lastSyncAtMs: 0,
          cloudUpdatedAt: null,
          lastSeenCloudUpdatedAt: null,
          localEmpty: false,
        ),
        FolderSyncAction.push,
      );
    });

    test('one side changed', () {
      expect(
        planFolderSync(
          localChangedAtMs: 5,
          lastSyncAtMs: 10,
          cloudUpdatedAt: t,
          lastSeenCloudUpdatedAt: 'old',
          localEmpty: false,
        ),
        FolderSyncAction.pull,
      );
      expect(
        planFolderSync(
          localChangedAtMs: 20,
          lastSyncAtMs: 10,
          cloudUpdatedAt: t,
          lastSeenCloudUpdatedAt: t,
          localEmpty: false,
        ),
        FolderSyncAction.push,
      );
      expect(
        planFolderSync(
          localChangedAtMs: 5,
          lastSyncAtMs: 10,
          cloudUpdatedAt: t,
          lastSeenCloudUpdatedAt: t,
          localEmpty: false,
        ),
        FolderSyncAction.none,
      );
    });

    test('both changed: newer whole snapshot wins', () {
      FolderSyncAction plan(int localMs) => planFolderSync(
        localChangedAtMs: localMs,
        lastSyncAtMs: 1,
        cloudUpdatedAt: t,
        lastSeenCloudUpdatedAt: 'old',
        localEmpty: false,
      );
      expect(plan(tMs + 1), FolderSyncAction.push);
      expect(plan(tMs - 1), FolderSyncAction.pull);
    });

    test('folders.json round-trips', () {
      final bytes = encodeUserFoldersDoc(
        snapshot: {
          'folders': [
            {'id': 'f1', 'name': '收藏'},
          ],
          'items': [],
        },
        updatedAt: t,
        deviceId: 'd',
      );
      final doc = decodeUserFoldersDoc(bytes)!;
      expect(doc.updatedAt, t);
      expect((doc.snapshot['folders'] as List).single['name'], '收藏');
      expect(
        decodeUserFoldersDoc(Uint8List.fromList(utf8.encode('{}'))),
        isNull,
      );
    });
  });

  group('layout + backup', () {
    test('library kinds live under library/<kind>', () {
      expect(libraryDirFor('/root/'), '/root/library/music');
      expect(mangaLibraryDirFor('/root'), '/root/library/manga');
      expect(foldersLibraryDirFor('/root'), '/root/library/folders');
    });

    test('backup v7 carries manga + folder sections', () {
      expect(BackupService.formatVersion, 7);
      final ids = {
        WmpSections.mangas,
        WmpSections.mangaLibrary,
        WmpSections.userFolders,
      };
      expect(ids, hasLength(3));
      final payload = jsonEncode({
        'mangas': [
          {'id': 'm'},
        ],
      });
      final bytes = WmpContainer.encode({
        WmpSections.mangaLibrary: Uint8List.fromList(utf8.encode(payload)),
        WmpSections.userFolders: Uint8List.fromList(utf8.encode('{}')),
      }, kind: WmpFileKind.forMetaKind(WmpKind.base));
      final c = WmpContainer.fromBytes(bytes);
      expect(utf8.decode(c.readSection(WmpSections.mangaLibrary)!), payload);
      expect(c.readSection(WmpSections.userFolders), isNotNull);
    });
  });
}
