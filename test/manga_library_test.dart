import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/manga.dart';
import 'package:webdav_media_manager/models/page_turn_direction.dart';
import 'package:webdav_media_manager/models/manga_page.dart';
import 'package:webdav_media_manager/models/manga_progress.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/services/manga_library_service.dart';
import 'package:webdav_media_manager/services/manga_sync_store.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/manga_file_types.dart';
import 'package:webdav_media_manager/utils/manga_identity.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

/// In-memory stand-in for [LibraryDatabase]. A series has no rows of its own
/// any more, so there is nothing here to store for one: the service derives
/// series from the `mangas.series` tag.
class _MemMangaDb extends LibraryDatabase {
  final mangas = <Manga>[];
  final pages = <MangaPage>[];
  final progress = <String, int>{};

  /// Last `bumpRev` passed per manga id to [replaceMangaPages].
  final pageBumps = <String, bool>{};

  @override
  Future<Map<String, List<String>>> imageMangaPagesById() async {
    final images = {
      for (final m in mangas)
        if (m.format == MangaFormat.images) m.id,
    };
    final out = <String, List<String>>{};
    for (final p in [
      ...pages,
    ]..sort((a, b) => a.pageIndex.compareTo(b.pageIndex))) {
      if (images.contains(p.mangaId)) {
        (out[p.mangaId] ??= []).add(p.relPath);
      }
    }
    return out;
  }

  @override
  Future<List<Manga>> loadMangas({String? series, String? author}) async {
    var list = List.of(mangas);
    if (series != null) {
      list = [
        for (final m in list)
          if (m.series == series) m,
      ];
    }
    if (author != null) {
      list = [
        for (final m in list)
          if (m.author == author) m,
      ];
    }
    return list;
  }

  @override
  Future<Manga> upsertManga(Manga manga, {bool keepRev = false}) async {
    // Schema v18: only containers are unique per (网盘名, path) — the fake
    // mirrors `idx_mangas_container_key`. Loose-image books are surrogate-keyed
    // and may share a folder.
    mangas.removeWhere(
      (m) =>
          m.id == manga.id ||
          (manga.format != MangaFormat.images &&
              m.format != MangaFormat.images &&
              m.sourceName == manga.sourceName &&
              m.remotePath == manga.remotePath),
    );
    mangas.add(manga);
    return manga;
  }

  @override
  Future<void> replaceMangaPages(
    String mangaId,
    List<MangaPage> list, {
    bool bumpRev = false,
  }) async {
    pageBumps[mangaId] = bumpRev;
    pages.removeWhere((p) => p.mangaId == mangaId);
    pages.addAll(list);
  }

  @override
  Future<List<MangaPage>> loadMangaPages(String mangaId) async => [
    for (final p in pages)
      if (p.mangaId == mangaId) p,
  ]..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

  @override
  Future<MangaProgress?> loadMangaProgress(String mangaId) async {
    final page = progress[mangaId];
    if (page == null) return null;
    return MangaProgress(
      mangaId: mangaId,
      pageIndex: page,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> upsertMangaProgress(MangaProgress p) async {
    progress[p.mangaId] = p.pageIndex;
  }

  @override
  Future<List<MangaProgress>> allMangaProgress() async => [
    for (final e in progress.entries)
      MangaProgress(
        mangaId: e.key,
        pageIndex: e.value,
        updatedAt: DateTime.now(),
      ),
  ];

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

  test('upsertFromDraft mints a surrogate id and freezes page order', () async {
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
    // 丙: the folder is a one-off input, so the id is a fresh surrogate and
    // never the path hash.
    expect(manga.id, isNot(mangaIdForRemote('nas', '/comics/OneShot')));
    expect(manga.id, isNotEmpty);
    expect(manga.format, MangaFormat.images);
    expect(manga.pageCount, 3);
    // Page paths are relative to the source root: the list *is* the book.
    expect(manga.coverRelpath, '/comics/OneShot/01.jpg');
    expect(svc.series.length, 1);
    expect(svc.series.first.title, 'Demo Series');
    expect(manga.series, 'Demo Series');

    final pages = await svc.pagesFor(manga.id);
    expect(pages.map((p) => p.relPath).toList(), [
      '/comics/OneShot/01.jpg',
      '/comics/OneShot/02.jpg',
      '/comics/OneShot/03.jpg',
    ]);
    expect(pages.map((p) => p.pageIndex).toList(), [0, 1, 2]);

    // Building again from the same folder makes a *second* book instead of
    // silently replacing the first.
    final again = await svc.upsertFromDraft(draft);
    expect(again.id, isNot(manga.id));
    expect(svc.mangas.length, 2);

    // Re-scanning a book the user owns updates it in place, so its id and its
    // hand-edited metadata survive.
    final rescan = MangaLibraryService.draftForImageDir(
      sourceName: 'nas',
      folderPath: '/comics/OneShot',
      folderName: 'OneShot',
      imageNames: ['01.jpg', '02.jpg', '03.jpg', '04.jpg'],
    );
    await svc.rescanLoose(manga.id, draft: rescan);
    final kept = svc.mangaById(manga.id)!;
    expect(kept.pageCount, 4);
    expect(kept.series, 'Demo Series');
    expect(kept.coverRelpath, '/comics/OneShot/01.jpg');
    expect(svc.mangas.length, 2);
  });

  test('setCoverRelpath replaces the cover and keeps the book', () async {
    final db = _MemMangaDb();
    final svc = MangaLibraryService(db: db);
    await svc.init();
    final draft = MangaLibraryService.draftForImageDir(
      sourceName: 'nas',
      folderPath: '/comics/OneShot',
      folderName: 'OneShot',
      imageNames: ['01.jpg', '02.jpg'],
    );
    final manga = await svc.upsertFromDraft(draft);
    final ok = await svc.setCoverRelpath(manga.id, '/comics/OneShot/02.jpg');
    expect(ok, isTrue);
    expect(svc.mangaById(manga.id)!.coverRelpath, '/comics/OneShot/02.jpg');
    expect(svc.mangaById(manga.id)!.id, manga.id);
    expect(await svc.setCoverRelpath('missing', '/x'), isFalse);
    expect(await svc.setCoverRelpath(manga.id, '  '), isFalse);
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
    // 出厂只认 cbz；pdf/cbr/epub 要靠调用方传后缀表。
    expect(isComicContainerFileName('a.pdf'), isFalse);
    expect(
      isComicContainerFileName('a.pdf', extensions: const ['pdf']),
      isTrue,
    );
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
    expect(svc.mangas.every((m) => m.series == 'Shared'), isTrue);
    // The id is derived from the title, so it is the same on every device.
    expect(svc.series.single.id, mangaSeriesIdForTitle('Shared'));
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
    // 默认深度 1：漫画目录天然扁平，扫太深会把整棵盘扫进来。
    expect(s.mangaScanMaxDepth, 1);
    expect(s.mangaCreateMaxDepth, 1);
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

  group('page lists in sync: images = membership, CBZ = local cache', () {
    Manga m(String path, String format) => Manga(
      // Loose-image books are surrogate-keyed; only containers are
      // path-derived. A path-derived *images* row is a pre-v18 leftover, which
      // sync and restore deliberately drop.
      id: format == MangaFormat.images
          ? 'uuid-${path.replaceAll('/', '_')}'
          : mangaIdForRemote('nas', path),
      sourceName: 'nas',
      remotePath: path,
      title: path,
      format: format,
      updatedAt: DateTime.utc(2026, 1, 1),
      rev: 7,
    );
    MangaPage pg(String id, int i, String rel) =>
        MangaPage(mangaId: id, pageIndex: i, relPath: rel);

    test('syncRows ships pages for images rows only', () async {
      final db = _MemMangaDb();
      final img = m('/imgs', MangaFormat.images);
      final cbz = m('/a.cbz', MangaFormat.cbz);
      db.mangas.addAll([img, cbz]);
      db.pages.addAll([pg(img.id, 0, 'x/1.jpg'), pg(cbz.id, 0, '1.jpg')]);
      final svc = MangaLibraryService(db: db);
      await svc.init();
      final rows = {for (final r in await svc.syncRows()) r.manga.id: r};
      expect(rows[img.id]!.pages, ['x/1.jpg']);
      expect(rows[cbz.id]!.pages, isEmpty);
    });

    test('pull replaces images pages without bump; CBZ keeps local', () async {
      final db = _MemMangaDb();
      final img = m('/imgs', MangaFormat.images);
      final cbz = m('/a.cbz', MangaFormat.cbz);
      db.pages.addAll([pg(img.id, 0, 'old.jpg'), pg(cbz.id, 0, 'local.jpg')]);
      final svc = MangaLibraryService(db: db);
      await svc.init();
      await svc.adoptCloudRows([
        MangaSyncRow(manga: img, pages: ['a/1.jpg', 'b/1.jpg']),
        MangaSyncRow(manga: cbz, pages: ['ignored.jpg']),
      ]);
      expect((await svc.pagesFor(img.id)).map((p) => p.relPath), [
        'a/1.jpg',
        'b/1.jpg',
      ]);
      expect(db.pageBumps[img.id], isFalse);
      expect((await svc.pagesFor(cbz.id)).single.relPath, 'local.jpg');
      expect(db.pageBumps.containsKey(cbz.id), isFalse);
    });

    test('local page save bumps rev for images, never for CBZ', () async {
      final db = _MemMangaDb();
      final img = m('/imgs', MangaFormat.images);
      final cbz = m('/a.cbz', MangaFormat.cbz);
      db.mangas.addAll([img, cbz]);
      final svc = MangaLibraryService(db: db);
      await svc.init();
      await svc.replacePages(img.id, pages: [pg(img.id, 0, '1.jpg')]);
      await svc.replacePages(cbz.id, pages: [pg(cbz.id, 0, '1.jpg')]);
      expect(db.pageBumps[img.id], isTrue);
      expect(db.pageBumps[cbz.id], isFalse);
    });
  });
}
