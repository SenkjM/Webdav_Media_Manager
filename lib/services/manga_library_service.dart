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
  final List<MangaSeries> _series = [];
  final List<String> _authors = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Manga> get mangas => List.unmodifiable(_mangas);
  List<MangaSeries> get series => List.unmodifiable(_series);
  List<String> get authors => List.unmodifiable(_authors);
  int get count => _mangas.length;

  Future<void> init() async {
    await reload();
  }

  Future<void> reload() async {
    _series
      ..clear()
      ..addAll(await _db.loadMangaSeries());
    _mangas
      ..clear()
      ..addAll(await _db.loadMangas());
    _authors
      ..clear()
      ..addAll(await _db.loadMangaAuthors());
    _loaded = true;
    notifyListeners();
  }

  List<Manga> mangasForSeries(String seriesId) => [
    for (final m in _mangas)
      if (m.seriesId == seriesId) m,
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

  Future<MangaSeries> ensureSeries({
    required String title,
    String? author,
  }) async {
    final trimmed = title.trim();
    for (final s in _series) {
      if (s.title == trimmed) return s;
    }
    final series = MangaSeries(
      id: mangaSeriesIdForTitle(trimmed),
      title: trimmed,
      author: author,
      sortTitle: trimmed,
      createdAt: DateTime.now(),
    );
    await _db.upsertMangaSeries(series);
    _series.add(series);
    notifyListeners();
    return series;
  }

  /// Commit a confirmed ingest draft (image-dir or container).
  Future<Manga> upsertFromDraft(MangaIngestDraft draft) async {
    final remotePath = normalizeRemotePath(draft.remotePath);
    final id = mangaIdForRemote(draft.sourceName, remotePath);
    String? seriesId;
    final seriesTitle = draft.seriesTitle?.trim();
    if (seriesTitle != null && seriesTitle.isNotEmpty) {
      seriesId = (await ensureSeries(
        title: seriesTitle,
        author: draft.author,
      )).id;
    }
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
      seriesId: seriesId,
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
    await _db.replaceMangaPages(mangaId, pages);
    final existing = await _db.loadMangaById(mangaId);
    if (existing != null) {
      await _db.upsertManga(
        existing.copyWith(
          pageCount: pages.length,
          coverRelpath:
              coverRelpath ??
              existing.coverRelpath ??
              (pages.isEmpty ? null : pages.first.relPath),
          updatedAt: DateTime.now(),
        ),
      );
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

  /// Assign [mangaIds] to one series (create by title if needed). Empty title clears.
  Future<int> assignSeriesToMangas({
    required List<String> mangaIds,
    required String seriesTitle,
  }) async {
    if (mangaIds.isEmpty) return 0;
    final trimmed = seriesTitle.trim();
    String? seriesId;
    if (trimmed.isNotEmpty && trimmed != unspecifiedSeriesLabel) {
      seriesId = (await ensureSeries(title: trimmed)).id;
    }
    var n = 0;
    for (final id in mangaIds) {
      final existing = await _db.loadMangaById(id);
      if (existing == null) continue;
      await _db.upsertManga(
        existing.copyWith(
          seriesId: seriesId,
          clearSeriesId: seriesId == null,
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

  bool isUnspecifiedSeries(Manga m) {
    if (m.seriesId == null || m.seriesId!.isEmpty) return true;
    for (final s in _series) {
      if (s.id == m.seriesId) {
        final title = s.title.trim();
        return title.isEmpty || title == unspecifiedSeriesLabel;
      }
    }
    return true;
  }

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
    for (final s in _series) {
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
    String? seriesId = existing.seriesId;
    var clearSeries = false;
    if (updateSeries) {
      final trimmed = seriesTitle?.trim() ?? '';
      if (trimmed.isEmpty || trimmed == unspecifiedSeriesLabel) {
        seriesId = null;
        clearSeries = true;
      } else {
        seriesId = (await ensureSeries(title: trimmed, author: author)).id;
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
        seriesId: seriesId,
        clearSeriesId: clearSeries,
        updatedAt: DateTime.now(),
      ),
    );
    await reload();
  }

  /// Rename series title / author. Empty title → treat as 未指定 (unbind mangas).
  Future<void> updateSeriesMetadata(
    String seriesId, {
    String? title,
    String? author,
  }) async {
    MangaSeries? existing;
    for (final s in _series) {
      if (s.id == seriesId) {
        existing = s;
        break;
      }
    }
    if (existing == null) return;
    final trimmed = title?.trim();
    if (trimmed != null &&
        (trimmed.isEmpty || trimmed == unspecifiedSeriesLabel)) {
      // Unbind all mangas in this series and drop the row.
      for (final m in mangasForSeries(seriesId)) {
        await _db.upsertManga(
          m.copyWith(clearSeriesId: true, updatedAt: DateTime.now()),
        );
      }
      // No dedicated deleteSeries API — leave orphan series; reload filters empty.
      await reload();
      return;
    }
    final next = MangaSeries(
      id: existing.id,
      title: trimmed ?? existing.title,
      author: author == null
          ? existing.author
          : (author.trim().isEmpty ? null : author.trim()),
      sortTitle: trimmed ?? existing.sortTitle,
      createdAt: existing.createdAt,
    );
    await _db.upsertMangaSeries(next);
    await reload();
  }

  /// Rename author across all mangas (and series rows with that author).
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
    for (final s in List.of(_series)) {
      if ((s.author ?? '').trim() != src) continue;
      await _db.upsertMangaSeries(
        MangaSeries(
          id: s.id,
          title: s.title,
          author: nextAuthor,
          sortTitle: s.sortTitle,
          createdAt: s.createdAt,
        ),
      );
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

  /// Every local row with its series and frozen page order, as sync ships it.
  Future<List<MangaSyncRow>> syncRows() async {
    final mangas = await _db.loadMangas();
    final series = {for (final s in await _db.loadMangaSeries()) s.id: s};
    final pages = await _db.allMangaPagesById();
    return [
      for (final m in mangas)
        MangaSyncRow(
          manga: m,
          series: m.seriesId == null ? null : series[m.seriesId],
          pages: pages[m.id] ?? const [],
        ),
    ];
  }

  /// Adopt rows pulled from the cloud verbatim (rev kept, pages replaced).
  Future<void> adoptCloudRows(List<MangaSyncRow> rows) async {
    for (final r in rows) {
      final s = r.series;
      if (s != null) await _db.upsertMangaSeries(s);
      await _db.upsertManga(r.manga, keepRev: true);
      await _db.replaceMangaPages(r.manga.id, [
        for (var i = 0; i < r.pages.length; i++)
          MangaPage(mangaId: r.manga.id, pageIndex: i, relPath: r.pages[i]),
      ], bumpRev: false);
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
