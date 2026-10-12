// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/foundation.dart';

import '../models/manga.dart';
import '../models/page_turn_direction.dart';
import '../models/manga_page.dart';
import '../models/manga_progress.dart';
import '../models/manga_series.dart';
import '../utils/manga_file_types.dart';
import '../utils/manga_identity.dart';
import '../utils/track_identity.dart';
import 'library_database.dart';
import 'manga_sync_store.dart';

/// Draft metadata shown in the confirm sheet before commit.
class MangaIngestDraft {
  MangaIngestDraft({
    required this.sourceName,
    required this.remotePath,
    required this.title,
    this.author,
    this.seriesTitle,
    this.volume,
    this.chapterNumber,
    required this.format,
    required this.pageRelPaths,
    this.coverRelpath,
  });

  final String sourceName;
  final String remotePath;
  String title;
  String? author;
  String? seriesTitle;
  String? volume;
  String? chapterNumber;
  final String format;
  final List<String> pageRelPaths;
  String? coverRelpath;
}

/// Thin manga library façade (99 §19): list / upsert from scan / progress.
class MangaLibraryService extends ChangeNotifier {
  MangaLibraryService({required LibraryDatabase db}) : _db = db;

  final LibraryDatabase _db;

  final List<Manga> _mangas = [];
  final List<String> _authors = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Manga> get mangas => List.unmodifiable(_mangas);

  /// Series in display order, **derived from the books that carry them**.
  ///
  /// Nothing is stored per series, so a title always has at least one book and
  /// deleting the last book removes the series with it — the album rule.
  List<MangaSeries> get series {
    final titles = <String>{};
    for (final m in _mangas) {
      final t = seriesTitleOf(m);
      if (t != null) titles.add(t);
    }
    final sorted = titles.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List.unmodifiable([for (final t in sorted) MangaSeries(title: t)]);
  }

  List<String> get authors => List.unmodifiable(_authors);
  int get count => _mangas.length;

  Future<void> init() async {
    await reload();
  }

  Future<void> reload() async {
    _mangas
      ..clear()
      ..addAll(await _db.loadMangas());
    _authors
      ..clear()
      ..addAll(await _db.loadMangaAuthors());
    _loaded = true;
    notifyListeners();
  }

  /// The stored series tag of [m], or null when unset / the 未指定 sentinel.
  String? seriesTitleOf(Manga m) {
    final t = normalizeMangaSeriesTag(m.series);
    if (t == null || t == unspecifiedSeriesLabel) return null;
    return t;
  }

  /// Deterministic id of [m]'s series (`sha1` of the tag); null when unset.
  ///
  /// `mangaSeries` folder soft refs address a series through this id, which is
  /// why the id survives as long as the title does.
  String? seriesIdOf(Manga m) {
    final t = seriesTitleOf(m);
    return t == null ? null : mangaSeriesIdForTitle(t);
  }

  /// The derived series [m] belongs to, or null.
  MangaSeries? seriesOf(Manga m) {
    final t = seriesTitleOf(m);
    return t == null ? null : MangaSeries(title: t);
  }

  List<Manga> mangasForSeries(String seriesId) => [
    for (final m in _mangas)
      if (seriesIdOf(m) == seriesId) m,
  ];

  List<Manga> mangasForAuthor(String author) => [
    for (final m in _mangas)
      if ((m.author ?? '').trim() == author) m,
  ];

  List<Manga> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return mangas;
    return [
      for (final m in _mangas)
        if (m.title.toLowerCase().contains(q) ||
            (m.author ?? '').toLowerCase().contains(q) ||
            m.remotePath.toLowerCase().contains(q))
          m,
    ];
  }

  /// Commit a confirmed ingest draft (image-dir or container).
  Future<Manga> upsertFromDraft(MangaIngestDraft draft) async {
    final remotePath = normalizeRemotePath(draft.remotePath);
    final id = mangaIdForRemote(draft.sourceName, remotePath);
    final series = normalizeMangaSeriesTag(draft.seriesTitle);
    final pages = <MangaPage>[];
    for (var i = 0; i < draft.pageRelPaths.length; i++) {
      pages.add(
        MangaPage(mangaId: id, pageIndex: i, relPath: draft.pageRelPaths[i]),
      );
    }
    final cover =
        draft.coverRelpath ??
        (draft.pageRelPaths.isEmpty ? null : draft.pageRelPaths.first);
    final existing = await _db.loadMangaById(id);
    final manga = Manga(
      id: id,
      sourceName: draft.sourceName,
      remotePath: remotePath,
      title: draft.title.trim().isEmpty
          ? remotePath.split('/').where((s) => s.isNotEmpty).last
          : draft.title.trim(),
      author: draft.author?.trim().isEmpty == true
          ? null
          : draft.author?.trim(),
      series: series,
      volume: draft.volume?.trim().isEmpty == true
          ? null
          : draft.volume?.trim(),
      chapterNumber: draft.chapterNumber?.trim().isEmpty == true
          ? null
          : draft.chapterNumber?.trim(),
      pageCount: pages.length,
      coverRelpath: cover,
      format: draft.format,
      pageTurn: existing?.pageTurn,
      remoteMissing: existing?.remoteMissing ?? false,
      updatedAt: DateTime.now(),
    );
    await _db.upsertManga(manga);
    await _db.replaceMangaPages(id, pages);
    await reload();
    return manga;
  }

  Future<List<MangaPage>> pagesFor(String mangaId) =>
      _db.loadMangaPages(mangaId);

  /// Freeze page list and update page_count / cover without touching series.
  Future<void> replacePages(
    String mangaId, {
    required List<MangaPage> pages,
    String? coverRelpath,
  }) async {
    final existing = await _db.loadMangaById(mangaId);
    // Loose-image pages are membership (synced → bump rev); CBZ / container
    // page order is a local cache and never bumps.
    await _db.replaceMangaPages(
      mangaId,
      pages,
      bumpRev: existing?.format == MangaFormat.images,
    );
    if (existing != null) {
      final cover =
          coverRelpath ??
          existing.coverRelpath ??
          (pages.isEmpty ? null : pages.first.relPath);
      // Only a change to page_count / cover rewrites the row, so a device
      // rebuilding its CBZ page cache for a pulled row does not re-upload it.
      if (existing.pageCount != pages.length ||
          existing.coverRelpath != cover) {
        await _db.upsertManga(
          existing.copyWith(
            pageCount: pages.length,
            coverRelpath: cover,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
    await reload();
  }

  Future<MangaProgress?> progressFor(String mangaId) =>
      _db.loadMangaProgress(mangaId);

  Future<void> setProgress(String mangaId, int pageIndex) async {
    await _db.upsertMangaProgress(
      MangaProgress(
        mangaId: mangaId,
        pageIndex: pageIndex,
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// Set per-manga page-turn (`ltr` / `rtl`) or clear (null = follow global).
  Future<void> setPageTurn(String mangaId, String? direction) async {
    final existing = await _db.loadMangaById(mangaId);
    if (existing == null) return;
    final next = direction == null || direction.trim().isEmpty
        ? existing.copyWith(clearPageTurn: true, updatedAt: DateTime.now())
        : existing.copyWith(
            pageTurn: PageTurnDirection.normalize(direction),
            updatedAt: DateTime.now(),
          );
    await _db.upsertManga(next);
    await reload();
  }

  /// Assign [mangaIds] to one series by tag. Empty title clears it.
  ///
  /// Assigning a title that already exists simply joins that series — there is
  /// no separate series object that could end up with two spellings.
  Future<int> assignSeriesToMangas({
    required List<String> mangaIds,
    required String seriesTitle,
  }) async {
    if (mangaIds.isEmpty) return 0;
    final tag = normalizeMangaSeriesTag(seriesTitle);
    final next = tag == unspecifiedSeriesLabel ? null : tag;
    var n = 0;
    for (final id in mangaIds) {
      final existing = await _db.loadMangaById(id);
      if (existing == null) continue;
      await _db.upsertManga(
        existing.copyWith(
          series: next,
          clearSeries: next == null,
          updatedAt: DateTime.now(),
        ),
      );
      n++;
    }
    await reload();
    return n;
  }

  /// Display label for unset series (UI sentinel; empty series name = 未指定).
  static const unspecifiedSeriesLabel = '未指定';

  bool isUnspecifiedSeries(Manga m) => seriesTitleOf(m) == null;

  /// Mangas with no series / empty / 「未指定」 series name.
  List<Manga> mangasUnspecifiedSeries() => [
    for (final m in _mangas)
      if (isUnspecifiedSeries(m)) m,
  ];

  /// Mangas that belong to a real named series.
  List<Manga> mangasWithSeries() => [
    for (final m in _mangas)
      if (!isUnspecifiedSeries(m)) m,
  ];

  MangaSeries? seriesById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final s in series) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Edit manga title / author / series. Empty series title clears (未指定).
  Future<void> updateMangaMetadata(
    String mangaId, {
    String? title,
    String? author,
    String? seriesTitle,
    bool updateSeries = false,
  }) async {
    final existing = await _db.loadMangaById(mangaId);
    if (existing == null) return;
    var nextSeries = existing.series;
    var clearSeries = false;
    if (updateSeries) {
      final tag = normalizeMangaSeriesTag(seriesTitle);
      if (tag == null || tag == unspecifiedSeriesLabel) {
        nextSeries = null;
        clearSeries = true;
      } else {
        nextSeries = tag;
      }
    }
    final clearAuthor = author != null && author.trim().isEmpty;
    final nextAuthor = author == null
        ? null
        : (clearAuthor ? null : author.trim());
    await _db.upsertManga(
      existing.copyWith(
        title: title?.trim().isEmpty == true
            ? existing.title
            : (title ?? existing.title),
        author: nextAuthor,
        clearAuthor: clearAuthor,
        series: nextSeries,
        clearSeries: clearSeries,
        updatedAt: DateTime.now(),
      ),
    );
    await reload();
  }

  /// Rename a series by rewriting the tag on every book that carries it.
  ///
  /// A series has no row of its own, so a rename is just a re-tag; renaming
  /// onto an existing title merges the two, and an empty title unbinds the
  /// books (the series then stops existing).
  Future<void> updateSeriesMetadata(String seriesId, {String? title}) async {
    final members = mangasForSeries(seriesId);
    if (members.isEmpty) return;
    final tag = normalizeMangaSeriesTag(title);
    final next = tag == unspecifiedSeriesLabel ? null : tag;
    if (next == seriesTitleOf(members.first)) return;
    for (final m in members) {
      await _db.upsertManga(
        m.copyWith(
          series: next,
          clearSeries: next == null,
          updatedAt: DateTime.now(),
        ),
      );
    }
    await reload();
  }

  /// Rename author across all mangas that carry it.
  Future<int> renameAuthor({required String from, required String to}) async {
    final src = from.trim();
    final dst = to.trim();
    if (src.isEmpty) return 0;
    final nextAuthor = dst.isEmpty ? null : dst;
    var n = 0;
    for (final m in List.of(_mangas)) {
      if ((m.author ?? '').trim() != src) continue;
      await _db.upsertManga(
        m.copyWith(
          author: nextAuthor,
          clearAuthor: nextAuthor == null,
          updatedAt: DateTime.now(),
        ),
      );
      n++;
    }
    await reload();
    return n;
  }

  /// Delete one manga. Leaves a tombstone so the deletion reaches the cloud.
  Future<void> deleteManga(String id) async {
    await _db.deleteManga(id);
    await reload();
  }

  // --- Cloud sync helpers (docs/08) ---

  Manga? find(String sourceName, String remotePath) {
    final path = normalizeRemotePath(remotePath);
    for (final m in _mangas) {
      if (m.sourceName == sourceName && m.remotePath == path) return m;
    }
    return null;
  }

  /// Every local row as sync ships it. The series tag rides on the row itself,
  /// so nothing extra has to be looked up. Loose-image rows carry their page
  /// list (membership); CBZ rows never do.
  Future<List<MangaSyncRow>> syncRows() async {
    final mangas = await _db.loadMangas();
    final pages = await _db.imageMangaPagesById();
    return [
      for (final m in mangas)
        MangaSyncRow(manga: m, pages: pages[m.id] ?? const []),
    ];
  }

  /// Adopt rows pulled from the cloud verbatim (rev kept, no bump). A
  /// loose-image row replaces its local page list (membership); a CBZ row
  /// leaves local page order alone (rebuilt on first open / scrape).
  Future<void> adoptCloudRows(List<MangaSyncRow> rows) async {
    for (final r in rows) {
      await _db.upsertManga(r.manga, keepRev: true);
      if (r.manga.format == MangaFormat.images) {
        await _db.replaceMangaPages(r.manga.id, [
          for (var i = 0; i < r.pages.length; i++)
            MangaPage(mangaId: r.manga.id, pageIndex: i, relPath: r.pages[i]),
        ]);
      }
    }
    await reload();
  }

  Future<List<MangaProgress>> allProgress() => _db.allMangaProgress();

  /// Write cloud-newer progress rows (no rev, no tombstone involved).
  Future<void> applyProgress(List<MangaProgress> rows) async {
    for (final p in rows) {
      await _db.upsertMangaProgress(p);
    }
    if (rows.isNotEmpty) notifyListeners();
  }

  /// Build a draft for a loose image directory (list only; no download).
  static MangaIngestDraft draftForImageDir({
    required String sourceName,
    required String folderPath,
    required String folderName,
    required List<String> imageNames,
  }) {
    final sorted = [...imageNames]
      ..sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
    return MangaIngestDraft(
      sourceName: sourceName,
      remotePath: normalizeRemotePath(folderPath),
      title: folderName,
      format: MangaFormat.images,
      pageRelPaths: sorted,
      coverRelpath: sorted.isEmpty ? null : sorted.first,
    );
  }

  /// Merge-mode draft: [pageRelPaths] already relative to [folderPath].
  static MangaIngestDraft draftForMergedImages({
    required String sourceName,
    required String folderPath,
    required String folderName,
    required List<String> pageRelPaths,
  }) {
    final sorted = [...pageRelPaths]
      ..sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
    return MangaIngestDraft(
      sourceName: sourceName,
      remotePath: normalizeRemotePath(folderPath),
      title: folderName,
      format: MangaFormat.images,
      pageRelPaths: sorted,
      coverRelpath: sorted.isEmpty ? null : sorted.first,
    );
  }

  /// Build a draft for a comic container file (pages may be empty this slice).
  static MangaIngestDraft draftForComicFile({
    required String sourceName,
    required String remotePath,
    required String fileName,
  }) {
    final stem = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    return MangaIngestDraft(
      sourceName: sourceName,
      remotePath: normalizeRemotePath(remotePath),
      title: stem,
      format: mangaFormatForFileName(fileName),
      pageRelPaths: const [],
    );
  }
}
