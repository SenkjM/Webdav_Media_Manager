// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/services/backup_service.dart';
import 'package:webdav_media_manager/services/cache_service.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';

/// Manga thumbnails ride in the archive the way track covers do: raw bytes in
/// their own section, an index on the row, and **no path** — the file name is
/// derived from the manga id, so a restored archive can never point at a
/// stranger's cache directory.
///
/// Both halves of that pairing are static and cache-explicit so they can be
/// exercised here without a database or a service graph (the full restore path
/// goes through sqflite; the readable-JSON export has no cover bytes at all).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;
  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp('wdmm-manga-cover-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getApplicationSupportPath' ||
            'getApplicationSupportDirectory' => support.path,
            _ => null,
          };
        });
    cache = CacheService();
    await cache.init();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await support.exists()) await support.delete(recursive: true);
  });

  Uint8List thumb(int seed) =>
      Uint8List.fromList(List<int>.generate(64, (i) => (i * 7 + seed) & 0xFF));

  /// Ids are long enough to be truncated to a 16-character stem, like the real
  /// ones (`sha1`-derived).
  String idOf(String suffix) => 'manga-$suffix-0123456789abcdef';

  Future<void> put(String mangaId, Uint8List bytes) async {
    final file = cache.mangaCoverFile(mangaId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Uint8List section(Uint8List a, [Uint8List? b]) => buildCoverSection([
    for (final blob in [a, ?b]) (bytes: blob, kind: WmpImageKind.detect(blob)),
  ]);

  group('导出侧：collectMangaCovers', () {
    test('给真有缩略图的行编号，缺文件的行丢掉旧下标', () async {
      final a = idOf('a');
      final b = idOf('b');
      final c = idOf('c');
      await put(a, thumb(1));
      await put(c, thumb(3));

      final snapshot = <String, dynamic>{
        'mangas': [
          {'id': a, 'title': 'A'},
          // 本机没有 B 的缩略图：即使行上留着下标也要丢掉，
          // 否则归档会指向一段它并不携带的字节。
          {'id': b, 'title': 'B', 'cover_index': 9},
          {'id': c, 'title': 'C'},
          {'title': '没有 id 的行'},
        ],
      };

      final blobs = await BackupService.collectMangaCovers(
        snapshot: snapshot,
        cache: cache,
      );

      expect(blobs, hasLength(2));
      expect(blobs[0], thumb(1));
      expect(blobs[1], thumb(3));
      final rows = snapshot['mangas'] as List;
      expect(rows[0]['cover_index'], 0);
      expect(rows[1].containsKey('cover_index'), isFalse);
      expect(rows[1]['title'], 'B');
      expect(rows[2]['cover_index'], 1);
      expect(rows[3].containsKey('cover_index'), isFalse);
    });

    test('缓存不可用时返回空，且不留下任何下标', () async {
      final snapshot = <String, dynamic>{
        'mangas': [
          {'id': idOf('a'), 'cover_index': 0},
        ],
      };
      final blobs = await BackupService.collectMangaCovers(
        snapshot: snapshot,
        cache: null,
      );
      expect(blobs, isEmpty);
      expect(
        (snapshot['mangas'] as List).single.containsKey('cover_index'),
        isFalse,
      );
    });
  });

  group('恢复侧：restoreMangaThumbnails', () {
    test('写回由 id 派生的路径，并抹掉归档内部用的下标', () async {
      final a = idOf('a');
      final b = idOf('b');
      final blobA = thumb(1);
      final blobB = thumb(2);
      final snapshot = <String, dynamic>{
        'mangas': [
          {'id': a, 'cover_index': 0},
          {'id': b, 'cover_index': 1, 'title': 'B'},
        ],
        'pages': [
          {'manga_id': a, 'rel_path': '001.jpg'},
        ],
      };

      // 全新设备：缓存里什么都没有。
      expect(await cache.mangaCoverFile(a).exists(), isFalse);

      final out = await BackupService.restoreMangaThumbnails(
        snapshot: snapshot,
        coversSection: section(blobA, blobB),
        cache: cache,
      );

      expect(await cache.mangaCoverFile(a).readAsBytes(), blobA);
      expect(await cache.mangaCoverFile(b).readAsBytes(), blobB);
      for (final row in out['mangas'] as List) {
        expect(row.containsKey('cover_index'), isFalse);
      }
      // 行本身别的字段原样留着。
      expect((out['mangas'] as List)[1]['title'], 'B');
      expect(out['pages'], isNotNull);
    });

    test('越界下标 / 缺 id / 没有该段：只影响那一张，其余照旧', () async {
      final a = idOf('a');
      final b = idOf('b');
      final blobA = thumb(1);
      final snapshot = <String, dynamic>{
        'mangas': [
          {'id': a, 'cover_index': 0},
          {'id': b, 'cover_index': 7}, // 越界
          {'cover_index': 0}, // 没有 id
        ],
      };

      final out = await BackupService.restoreMangaThumbnails(
        snapshot: snapshot,
        coversSection: section(blobA),
        cache: cache,
      );

      expect(await cache.mangaCoverFile(a).readAsBytes(), blobA);
      expect(await cache.mangaCoverFile(b).exists(), isFalse);
      expect((out['mangas'] as List), hasLength(3));

      // 段整个不在（旧归档）：下标仍然被抹掉，一个文件也不写。
      final b2 = idOf('b2');
      final legacy = <String, dynamic>{
        'mangas': [
          {'id': b2, 'cover_index': 0},
        ],
      };
      final legacyOut = await BackupService.restoreMangaThumbnails(
        snapshot: legacy,
        coversSection: null,
        cache: cache,
      );
      expect(await cache.mangaCoverFile(b2).exists(), isFalse);
      expect(
        (legacyOut['mangas'] as List).single.containsKey('cover_index'),
        isFalse,
      );
    });
  });

  group('段格式', () {
    test('MANGA_COVERS 是一个新的独立段号，字节原样往返', () {
      // 段号写死在这里：改号是格式变更，得同时改 docs/08 §5。
      expect(WmpSections.mangaCovers, 15);
      // 不复用 tracks 段号，也不与已用段撞车。
      expect(<int>{
        WmpSections.meta,
        WmpSections.tracks,
        WmpSections.covers,
        WmpSections.tombs,
        WmpSections.credentials,
        WmpSections.playlists,
        WmpSections.settings,
        WmpSections.cueAlbums,
        WmpSections.entries,
        WmpSections.playlistDeletions,
        WmpSections.mangas,
        WmpSections.mangaLibrary,
        WmpSections.userFolders,
      }, isNot(contains(WmpSections.mangaCovers)));

      final a = thumb(1);
      final b = thumb(2);
      final raw = section(a, b);
      final parsed = parseCoverSection(raw);
      expect(parsed, hasLength(2));
      expect(parsed[0].bytesIn(raw), a);
      expect(parsed[1].bytesIn(raw), b);
    });
  });
}
