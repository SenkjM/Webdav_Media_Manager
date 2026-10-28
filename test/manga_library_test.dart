import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/manga.dart';
import 'package:webdav_media_manager/models/page_turn_direction.dart';
import 'package:webdav_media_manager/services/manga_library_service.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/manga_file_types.dart';
import 'package:webdav_media_manager/utils/manga_identity.dart';

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
    final svc = MangaLibraryService();
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
    // Cover path is deterministic from id; only cover_state is persisted.
    expect(manga.coverState, 0); // unknown until a cover file is saved
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
    expect(kept.coverState, 0);
    expect(svc.mangas.length, 2);
  });

  test('setCoverState updates cover availability and keeps the book', () async {
    final svc = MangaLibraryService();
    await svc.init();
    final draft = MangaLibraryService.draftForImageDir(
      sourceName: 'nas',
      folderPath: '/comics/OneShot',
      folderName: 'OneShot',
      imageNames: ['01.jpg', '02.jpg'],
    );
    final manga = await svc.upsertFromDraft(draft);
    final ok = await svc.setCoverState(manga.id, 2);
    expect(ok, isTrue);
    expect(svc.mangaById(manga.id)!.coverState, 2);
    expect(svc.mangaById(manga.id)!.id, manga.id);
    expect(await svc.setCoverState('missing', 2), isFalse);
    // Same state is a no-op success.
    expect(await svc.setCoverState(manga.id, 2), isTrue);
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
    final svc = MangaLibraryService();
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
    final svc = MangaLibraryService();
    await svc.init();
    final draft = MangaLibraryService.draftForComicFile(
      sourceName: 'nas',
      remotePath: '/comics/rtl.cbz',
      fileName: 'rtl.cbz',
    );
    final manga = await svc.upsertFromDraft(draft);
    expect(svc.mangaById(manga.id)!.pageTurn, isNull);

    await svc.setPageTurn(manga.id, PageTurnDirection.rtl);
    expect(svc.mangaById(manga.id)!.pageTurn, PageTurnDirection.rtl);

    await svc.setPageTurn(manga.id, null);
    expect(svc.mangaById(manga.id)!.pageTurn, isNull);
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
