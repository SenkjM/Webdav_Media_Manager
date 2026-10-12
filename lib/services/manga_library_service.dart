// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/manga.dart';
import '../models/manga_page.dart';
import '../models/manga_progress.dart';
import '../models/manga_series.dart';
import '../utils/manga_file_types.dart';
import '../utils/manga_identity.dart';
import '../utils/track_identity.dart';
import 'library_database.dart';

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
  final _uuid = const Uuid();

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

  List<Manga> mangasForSeries(String seriesId) =>
      [for (final m in _mangas) if (m.seriesId == seriesId) m];

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
      id: _uuid.v4(),
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
        MangaPage(
          mangaId: id,
          pageIndex: i,
          relPath: draft.pageRelPaths[i],
        ),
      );
    }
    final cover = draft.coverRelpath ??
        (draft.pageRelPaths.isEmpty ? null : draft.pageRelPaths.first);
    final manga = Manga(
      id: id,
      sourceName: draft.sourceName,
      remotePath: remotePath,
      title: draft.title.trim().isEmpty
          ? remotePath.split('/').where((s) => s.isNotEmpty).last
          : draft.title.trim(),
      author: draft.author?.trim().isEmpty == true ? null : draft.author?.trim(),
      seriesId: seriesId,
      volume: draft.volume?.trim().isEmpty == true ? null : draft.volume?.trim(),
      chapterNumber: draft.chapterNumber?.trim().isEmpty == true
          ? null
          : draft.chapterNumber?.trim(),
      pageCount: pages.length,
      coverRelpath: cover,
      format: draft.format,
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
        Manga(
          id: existing.id,
          sourceName: existing.sourceName,
          remotePath: existing.remotePath,
          title: existing.title,
          author: existing.author,
          seriesId: existing.seriesId,
          volume: existing.volume,
          chapterNumber: existing.chapterNumber,
          pageCount: pages.length,
          coverRelpath: coverRelpath ??
              existing.coverRelpath ??
              (pages.isEmpty ? null : pages.first.relPath),
          format: existing.format,
          remoteMissing: existing.remoteMissing,
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


  /// Assign [mangaIds] to one series (create by title if needed). Empty title clears.
  Future<int> assignSeriesToMangas({
    required List<String> mangaIds,
    required String seriesTitle,
  }) async {
    if (mangaIds.isEmpty) return 0;
    final trimmed = seriesTitle.trim();
    String? seriesId;
    if (trimmed.isNotEmpty) {
      seriesId = (await ensureSeries(title: trimmed)).id;
    }
    var n = 0;
    for (final id in mangaIds) {
      final existing = await _db.loadMangaById(id);
      if (existing == null) continue;
      await _db.upsertManga(
        Manga(
          id: existing.id,
          sourceName: existing.sourceName,
          remotePath: existing.remotePath,
          title: existing.title,
          author: existing.author,
          seriesId: seriesId,
          volume: existing.volume,
          chapterNumber: existing.chapterNumber,
          pageCount: existing.pageCount,
          coverRelpath: existing.coverRelpath,
          format: existing.format,
          remoteMissing: existing.remoteMissing,
          updatedAt: DateTime.now(),
        ),
      );
      n++;
    }
    await reload();
    return n;
  }

  Future<void> deleteManga(String id) async {
    await _db.deleteManga(id);
    await reload();
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
