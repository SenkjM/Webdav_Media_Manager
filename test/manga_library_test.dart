import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/manga.dart';
import 'package:webdav_media_manager/models/page_turn_direction.dart';
import 'package:webdav_media_manager/models/manga_page.dart';
import 'package:webdav_media_manager/models/manga_series.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/services/manga_library_service.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/manga_file_types.dart';
import 'package:webdav_media_manager/utils/manga_identity.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

class _MemMangaDb extends LibraryDatabase {
  final series = <MangaSeries>[];
  final mangas = <Manga>[];
  final pages = <MangaPage>[];
  final progress = <String, int>{};

  @override
  Future<List<MangaSeries>> loadMangaSeries() async => List.of(series);

  @override
  Future<void> upsertMangaSeries(MangaSeries s) async {
    series.removeWhere((e) => e.id == s.id);
    series.add(s);
  }

  @override
  Future<List<Manga>> loadMangas({String? seriesId, String? author}) async {
    var list = List.of(mangas);
    if (seriesId != null) {
      list = [for (final m in list) if (m.seriesId == seriesId) m];
    }
    if (author != null) {
      list = [for (final m in list) if (m.author == author) m];
    }
    return list;
  }

  @override
  Future<Manga> upsertManga(Manga manga, {bool keepRev = false}) async {
    mangas.removeWhere(
      (m) =>
          m.id == manga.id ||
          (m.sourceName == manga.sourceName &&
              m.remotePath == manga.remotePath),
    );
    mangas.add(manga);
    return manga;
  }

  @override
  Future<void> replaceMangaPages(String mangaId, List<MangaPage> list) async {
    pages.removeWhere((p) => p.mangaId == mangaId);
    pages.addAll(list);
  }

  @override
  Future<List<MangaPage>> loadMangaPages(String mangaId) async =>
      [for (final p in pages) if (p.mangaId == mangaId) p]
        ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

  @override
  Future<List<String>> loadMangaAuthors() async {
    final set = <String>{};
    for (final m in mangas) {
      final a = m.author?.trim();
      if (a != null && a.isNotEmpty) set.add(a);
    }
    return set.toList()..sort();
  }

  @override
  Future<Manga?> loadMangaById(String id) async {
    for (final m in mangas) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<Manga?> loadMangaByPath({
    required String sourceName,
    required String remotePath,
  }) async {
    final norm = normalizeRemotePath(remotePath);
    for (final m in mangas) {
      if (m.sourceName == sourceName && m.remotePath == norm) return m;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mangaId is path-index stable and unique per source', () {
    final a = mangaIdForRemote('disk', '/manga/vol1');
    final b = mangaIdForRemote('disk', 'manga/vol1');
    final c = mangaIdForRemote('other', '/manga/vol1');
    expect(a, b);
    expect(a, isNot(equals(c)));
    expect(a, isNot(contains('book')));
  });

  test('page sort key orders numeric names', () {
    final names = ['10.png', '2.png', '1.png'];
    names.sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
    expect(names, ['1.png', '2.png', '10.png']);
  });

  test('upsertFromDraft freezes page order and identity uniqueness', () async {
    final db = _MemMangaDb();
    final svc = MangaLibraryService(db: db);
    await svc.init();

    final draft = MangaLibraryService.draftForImageDir(
      sourceName: 'nas',
      folderPath: '/comics/OneShot',
      folderName: 'OneShot',
      imageNames: ['03.jpg', '01.jpg', '02.jpg'],
    );
    draft.author = 'Alice';
    draft.seriesTitle = 'Demo Series';

    final manga = await svc.upsertFromDraft(draft);
    expect(manga.id, mangaIdForRemote('nas', '/comics/OneShot'));
    expect(manga.format, MangaFormat.images);
    expect(manga.pageCount, 3);
    expect(manga.coverRelpath, '01.jpg');
    expect(svc.series.length, 1);
    expect(svc.series.first.title, 'Demo Series');

    final pages = await svc.pagesFor(manga.id);
    expect(pages.map((p) => p.relPath).toList(), ['01.jpg', '02.jpg', '03.jpg']);
    expect(pages.map((p) => p.pageIndex).toList(), [0, 1, 2]);

    // Re-ingest same path replaces, does not duplicate.
    draft.title = 'OneShot Renamed';
    await svc.upsertFromDraft(draft);
    expect(svc.mangas.length, 1);
    expect(svc.mangas.first.title, 'OneShot Renamed');
  });

  test('home_tab_v025 shifts indices >= 3 by one', () async {
    SharedPreferences.setMockInitialValues({
      'home_tab_index': 3, // was network library before manga insert
      'home_tab_v024_folders_inserted': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs: prefs);
    await settings.init();
    expect(settings.homeTab, 4); // network moved to 4
    expect(prefs.getBool('home_tab_v025_manga_inserted'), isTrue);

    // Second init does not shift again.
    final again = SettingsService(prefs: prefs);
    await again.init();
    expect(again.homeTab, 4);
  });

  test('home_tab below 3 stays put', () async {
    SharedPreferences.setMockInitialValues({
      'home_tab_index': 2, // playlists
      'home_tab_v024_folders_inserted': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs: prefs);
    await settings.init();
    expect(settings.homeTab, 2);
  });

  test('ref kind constants use manga not book', () {
    expect(isComicContainerFileName('a.cbz'), isTrue);
    expect(isComicContainerFileName('a.pdf'), isTrue);
    expect(isMangaImageFileName('x.png'), isTrue);
    expect(mangaFormatForFileName('x.CBZ'), MangaFormat.cbz);
  });

  test('assignSeriesToMangas sets shared series', () async {
    final db = _MemMangaDb();
    final svc = MangaLibraryService(db: db);
    await svc.init();
    final a = await svc.upsertFromDraft(
      MangaLibraryService.draftForImageDir(
        sourceName: 'nas',
        folderPath: '/a',
        folderName: 'A',
        imageNames: ['1.jpg'],
      ),
    );
    final b = await svc.upsertFromDraft(
      MangaLibraryService.draftForImageDir(
        sourceName: 'nas',
        folderPath: '/b',
        folderName: 'B',
        imageNames: ['2.jpg'],
      ),
    );
    final n = await svc.assignSeriesToMangas(
      mangaIds: [a.id, b.id],
      seriesTitle: 'Shared',
    );
    expect(n, 2);
    expect(svc.series.single.title, 'Shared');
    expect(svc.mangas.every((m) => m.seriesId == svc.series.single.id), isTrue);
  });

  test('manga walk prefs default and clamp', () async {
    SharedPreferences.setMockInitialValues({
      'home_tab_v024_folders_inserted': true,
      'home_tab_v025_manga_inserted': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();
    expect(s.mangaScanSubdirs, isTrue);
    expect(s.mangaCreateSubdirs, isTrue);
    expect(s.mangaScanMaxDepth, 5);
    expect(s.mangaCreateMaxDepth, 5);
    await s.setMangaScanMaxDepth(99);
    expect(s.mangaScanMaxDepth, lessThanOrEqualTo(20));
    await s.setMangaCreateSubdirs(false);
    expect(s.mangaCreateWalkOptions.includeSubdirs, isFalse);
  });

  test('image prefetch clamps to 1–20', () async {
    SharedPreferences.setMockInitialValues({
      'home_tab_v024_folders_inserted': true,
      'home_tab_v025_manga_inserted': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();
    expect(SettingsService.maxImagePrefetchCount, 20);
    await s.setImagePrefetchCount(20);
    expect(s.imagePrefetchCount, 20);
    await s.setImagePrefetchCount(99);
    expect(s.imagePrefetchCount, 20);
    await s.setImagePrefetchCount(0);
    expect(s.imagePrefetchCount, 1);
  });

  test('Manga pageTurn map round-trip and clear', () {
    final m = Manga(
      id: 'm1',
      sourceName: 's',
      remotePath: '/a.cbz',
      title: 'T',
      pageCount: 1,
      format: MangaFormat.cbz,
      pageTurn: PageTurnDirection.rtl,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    expect(Manga.fromMap(m.toMap()).pageTurn, PageTurnDirection.rtl);
    expect(m.copyWith(clearPageTurn: true).pageTurn, isNull);
  });

  test('setPageTurn persists per-manga and does not require global', () async {
    final db = _MemMangaDb();
    final svc = MangaLibraryService(db: db);
    await svc.init();
    final draft = MangaLibraryService.draftForComicFile(
      sourceName: 'nas',
      remotePath: '/comics/rtl.cbz',
      fileName: 'rtl.cbz',
    );
    final manga = await svc.upsertFromDraft(draft);
    expect(db.mangas.single.pageTurn, isNull);

    await svc.setPageTurn(manga.id, PageTurnDirection.rtl);
    expect(db.mangas.single.pageTurn, PageTurnDirection.rtl);

    await svc.setPageTurn(manga.id, null);
    expect(db.mangas.single.pageTurn, isNull);
  });

  test('SettingsService image_page_turn persists', () async {
    SharedPreferences.setMockInitialValues({
      'home_tab_v024_folders_inserted': true,
      'home_tab_v025_manga_inserted': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();
    expect(s.imagePageTurn, PageTurnDirection.ltr);
    await s.setImagePageTurn(PageTurnDirection.rtl);
    expect(s.imagePageTurn, PageTurnDirection.rtl);
    final again = SettingsService(prefs: prefs);
    await again.init();
    expect(again.imagePageTurn, PageTurnDirection.rtl);
  });

}
