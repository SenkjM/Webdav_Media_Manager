// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/manga.dart';
import '../models/page_turn_direction.dart';
import '../models/manga_page.dart';
import '../models/manga_progress.dart';
import '../models/manga_series.dart';
import '../utils/manga_file_types.dart';
import '../utils/manga_identity.dart';
import '../utils/rev_clock.dart';
import '../utils/track_identity.dart';
import 'manga_sync_store.dart';
import 'rust_core_service.dart';

/// Draft metadata shown in the confirm sheet before commit.
///
/// [pageRelPaths] are **relative to the source root** for loose images (see
/// [MangaPage.relPath]) and archive entry names for containers.
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
    this.id,
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

  /// Set when the caller already owns the row (a re-scan, or a test). Null lets
  /// [MangaLibraryService.upsertFromDraft] mint one.
  final String? id;
}

/// Thin manga library façade (99 §19): list / upsert from scan / progress.
///
/// Wave D (fdb05df): manga index CRUD and reading progress route through the
/// Rust FFI ([RustCoreService.mangaList] / [RustCoreService.mangaUpsert] etc.)
/// instead of sqflite. Class B unload (2026-10-27): tombstones (`deleted_mangas`)
/// go through Core FFI ([RustCoreService.deletedMangaClear] / mangaDelete).
/// No LibraryDatabase dependency — accounts remain sqflite-primary elsewhere
/// (LibraryDatabase may still open on launch for accounts).
class MangaLibraryService extends ChangeNotifier {
  MangaLibraryService();

  RevClock? _revClock;

  /// Attach the shared rev clock (same instance as music) so manga revs stay
  /// on the same strictly-increasing scale and are comparable across domains.
  void attachRevClock(RevClock clock) => _revClock = clock;

  int _nextRev() =>
      _revClock?.next() ?? DateTime.now().millisecondsSinceEpoch;

  // ── In-memory state ───────────────────────────────────────────────────────

  final List<Manga> _mangas = [];
  final List<String> _authors = [];
  final Map<String, MangaProgress> _progress = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Manga> get mangas => List.unmodifiable(_mangas);

  /// Series in display order, **derived from the books that carry them**.
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

  // ── FFI decoders ──────────────────────────────────────────────────────────

  static List<Manga> _decodeMangaList(String? raw) {
    if (raw == null || raw.startsWith('error:')) {
      if (raw != null) debugPrint('[MangaLibrary] mangaList FFI: $raw');
      return [];
    }
    try {
      return [
        for (final m in jsonDecode(raw) as List<dynamic>)
          Manga.fromMap(Map<String, Object?>.from(m as Map)),
      ];
    } catch (e) {
      debugPrint('[MangaLibrary] _decodeMangaList: $e');
      return [];
    }
  }

  static Manga? _decodeManga(String? raw) {
    if (raw == null || raw == 'null') return null;
    if (raw.startsWith('error:')) {
      debugPrint('[MangaLibrary] mangaGet FFI: $raw');
      return null;
    }
    try {
      return Manga.fromMap(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('[MangaLibrary] _decodeManga: $e');
      return null;
    }
  }

  static List<MangaPage> _decodePageList(String? raw) {
    if (raw == null || raw.startsWith('error:')) {
      if (raw != null) debugPrint('[MangaLibrary] mangaListPages FFI: $raw');
      return [];
    }
    try {
      return [
        for (final p in jsonDecode(raw) as List<dynamic>)
          MangaPage.fromMap(Map<String, Object?>.from(p as Map)),
      ];
    } catch (e) {
      debugPrint('[MangaLibrary] _decodePageList: $e');
      return [];
    }
  }

  static MangaProgress? _decodeProgress(String? raw) {
    if (raw == null || raw == 'null') return null;
    if (raw.startsWith('error:')) {
      debugPrint('[MangaLibrary] mangaGetProgress FFI: $raw');
      return null;
    }
    try {
      return MangaProgress.fromMap(
          Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('[MangaLibrary] _decodeProgress: $e');
      return null;
    }
  }

  static List<MangaProgress> _decodeProgressList(String? raw) {
    if (raw == null || raw.startsWith('error:')) {
      if (raw != null) debugPrint('[MangaLibrary] mangaListProgress FFI: $raw');
      return [];
    }
    try {
      return [
        for (final p in jsonDecode(raw) as List<dynamic>)
          MangaProgress.fromMap(Map<String, Object?>.from(p as Map)),
      ];
    } catch (e) {
      debugPrint('[MangaLibrary] _decodeProgressList: $e');
      return [];
    }
  }

  // ── FFI wrappers ──────────────────────────────────────────────────────────

  Future<Manga?> _ffiGetManga(String id) async =>
      _decodeManga(RustCoreService.mangaGet(id));

  /// Upsert [manga] via FFI. When [keepRev] is false (default), assigns the
  /// next rev from the shared clock and clears any Core tombstone for this
  /// row's sync key — matching the semantics of [LibraryDatabase.upsertManga].
  Future<Manga> _ffiUpsertManga(Manga manga, {bool keepRev = false}) async {
    final stored = keepRev ? manga : manga.copyWith(rev: _nextRev());
    final r = RustCoreService.mangaUpsert(jsonEncode(stored.toMap()));
    if (r != null && r.startsWith('error:')) {
      debugPrint('[MangaLibrary] mangaUpsert FFI: $r');
    }
    if (!keepRev) {
      // A local write resurrects a deleted row — clear the tombstone so sync
      // does not push a deletion that was superseded by this write.
      final syncKey = mangaSyncKeyForManga(
        id: stored.id,
        format: stored.format,
        sourceName: stored.sourceName,
        remotePath: stored.remotePath,
      );
      final clearResult = RustCoreService.deletedMangaClear(syncKey);
      if (clearResult != null && clearResult.startsWith('error:')) {
        debugPrint('[MangaLibrary] deletedMangaClear FFI: $clearResult');
      }
    }
    return stored;
  }

  /// Atomically replace all pages for [mangaId] via FFI.
  void _ffiSetPages(String mangaId, List<MangaPage> pages) {
    final r = RustCoreService.mangaSetPages(
      mangaId,
      jsonEncode([for (final p in pages) p.toMap()]),
    );
    if (r != null && r.startsWith('error:')) {
      debugPrint('[MangaLibrary] mangaSetPages FFI: $r');
    }
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await reload();
  }

  Future<void> reload() async {
    _mangas
      ..clear()
      ..addAll(_decodeMangaList(RustCoreService.mangaList()));
    // Authors are derived in memory (the sqflite loadMangaAuthors query was a
    // DISTINCT author scan — identical to scanning the in-memory list).
    final authorSet = <String>{};
    for (final m in _mangas) {
      final a = (m.author ?? '').trim();
      if (a.isNotEmpty) authorSet.add(a);
    }
    _authors
      ..clear()
      ..addAll(authorSet.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    _progress
      ..clear()
      ..addAll({
        for (final p in _decodeProgressList(RustCoreService.mangaListProgress()))
          p.mangaId: p,
      });
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

  // ── Simple helpers (series/author) ────────────────────────────────────────

  /// Display label for unset series (UI sentinel; empty series name = 未指定).
  static const unspecifiedSeriesLabel = '未指定';

  bool isUnspecifiedSeries(Manga m) => seriesTitleOf(m) == null;

  List<Manga> mangasUnspecifiedSeries() => [
        for (final m in _mangas)
          if (isUnspecifiedSeries(m)) m,
      ];

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

  /// Single-row look-up from the in-memory cache.
  Manga? mangaById(String id) {
    for (final m in _mangas) {
      if (m.id == id) return m;
    }
    return null;
  }

  // ── Upsert / pages ────────────────────────────────────────────────────────

  /// Persist a draft, replacing any existing row with the same id.
  ///
  /// Existing [pageTurn] and [remoteMissing] flags are preserved; everything
  /// else comes from [draft]. Pages replace atomically via FFI.
  Future<Manga> upsertFromDraft(MangaIngestDraft draft) async {
    final remotePath = normalizeRemotePath(draft.remotePath);
    final id = draft.id ??
        (draft.format == MangaFormat.images
            ? newMangaId()
            : mangaIdForRemote(draft.sourceName, remotePath));
    final series = normalizeMangaSeriesTag(draft.seriesTitle);
    final pages = <MangaPage>[
      for (var i = 0; i < draft.pageRelPaths.length; i++)
        MangaPage(mangaId: id, pageIndex: i, relPath: draft.pageRelPaths[i]),
    ];
    final cover =
        draft.coverRelpath ?? (pages.isEmpty ? null : pages.first.relPath);
    final existing = await _ffiGetManga(id);
    final manga = Manga(
      id: id,
      sourceName: draft.sourceName,
      remotePath: remotePath,
      title: draft.title.trim().isEmpty
          ? remotePath.split('/').where((s) => s.isNotEmpty).last
          : draft.title.trim(),
      author: (draft.author ?? '').trim().isEmpty
          ? null
          : draft.author!.trim(),
      series: series,
      volume:
          (draft.volume ?? '').trim().isEmpty ? null : draft.volume?.trim(),
      chapterNumber: (draft.chapterNumber ?? '').trim().isEmpty
          ? null
          : draft.chapterNumber?.trim(),
      pageCount: pages.length,
      coverRelpath: cover,
      format: draft.format,
      remoteMissing: existing?.remoteMissing ?? false,
      pageTurn: existing?.pageTurn,
      updatedAt: DateTime.now(),
    );
    final stored = await _ffiUpsertManga(manga);
    _ffiSetPages(id, pages);
    await reload();
    return stored;
  }

  /// Load the page list for one manga from Rust.
  Future<List<MangaPage>> pagesFor(String mangaId) async =>
      _decodePageList(RustCoreService.mangaListPages(mangaId));

  /// Replace the page list for [mangaId]. Bumps rev when [format] is images
  /// (loose-image membership is synced) or when page count / cover changed.
  Future<void> replacePages(
    String mangaId, {
    required List<MangaPage> pages,
    String? coverRelpath,
  }) async {
    final existing = await _ffiGetManga(mangaId);
    if (existing != null) {
      final cover = coverRelpath ??
          existing.coverRelpath ??
          (pages.isEmpty ? null : pages.first.relPath);
      final bumpRev = existing.format == MangaFormat.images;
      final countChanged = existing.pageCount != pages.length;
      final coverChanged = existing.coverRelpath != cover;
      if (bumpRev || countChanged || coverChanged) {
        // _ffiUpsertManga(keepRev: false) mints a fresh rev and clears tombstone.
        await _ffiUpsertManga(existing.copyWith(
          pageCount: pages.length,
          coverRelpath: cover,
          updatedAt: DateTime.now(),
        ));
      }
    }
    _ffiSetPages(mangaId, pages);
    await reload();
  }

  // ── Progress ──────────────────────────────────────────────────────────────

  /// Cached progress for one manga (in-memory; refreshed by [reload]).
  MangaProgress? progressByManga(String mangaId) => _progress[mangaId];

  /// Cached progress for one manga, looked up by the row itself.
  MangaProgress? progressOf(Manga m) => _progress[m.id];

  /// Authoritative progress for one manga, read straight from Rust (not the
  /// in-memory cache) — used when the caller needs the freshest value.
  Future<MangaProgress?> progressFor(String mangaId) async =>
      _decodeProgress(RustCoreService.mangaGetProgress(mangaId));

  /// Set reading progress for [mangaId] to [pageIndex] (0-based).
  Future<void> setProgress(String mangaId, int pageIndex) async {
    final r = RustCoreService.mangaSetProgress(mangaId, pageIndex);
    if (r != null && r.startsWith('error:')) {
      debugPrint('[MangaLibrary] setProgress FFI: $r');
    }
    _progress[mangaId] = MangaProgress(
      mangaId: mangaId,
      pageIndex: pageIndex,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  // ── Per-book metadata edits ───────────────────────────────────────────────

  /// Set the page-turn direction for [mangaId]. Null / blank clears it.
  Future<void> setPageTurn(String mangaId, String? direction) async {
    final existing = await _ffiGetManga(mangaId);
    if (existing == null) return;
    final next = (direction == null || direction.trim().isEmpty)
        ? existing.copyWith(clearPageTurn: true, updatedAt: DateTime.now())
        : existing.copyWith(
            pageTurn: PageTurnDirection.normalize(direction),
            updatedAt: DateTime.now(),
          );
    await _ffiUpsertManga(next);
    await reload();
  }

  /// Set the cover page rel-path for [mangaId]. An unchanged path still bumps
  /// (the bytes may have been regenerated). Returns false when the book is
  /// missing or [relPath] is blank.
  Future<bool> setCoverRelpath(String mangaId, String relPath) async {
    final existing = await _ffiGetManga(mangaId);
    if (existing == null) return false;
    final next = relPath.trim();
    if (next.isEmpty) return false;
    await _ffiUpsertManga(
        existing.copyWith(coverRelpath: next, updatedAt: DateTime.now()));
    await reload();
    return true;
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
      final existing = await _ffiGetManga(id);
      if (existing == null) continue;
      await _ffiUpsertManga(
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

  /// Edit manga title / author / series. Empty series title clears (未指定).
  Future<void> updateMangaMetadata(
    String mangaId, {
    String? title,
    String? author,
    String? seriesTitle,
    bool updateSeries = false,
  }) async {
    final existing = await _ffiGetManga(mangaId);
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
    final nextAuthor = author == null ? null : (clearAuthor ? null : author.trim());
    await _ffiUpsertManga(
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
  Future<void> updateSeriesMetadata(String seriesId, {String? title}) async {
    final members = mangasForSeries(seriesId);
    if (members.isEmpty) return;
    final tag = normalizeMangaSeriesTag(title);
    final next = tag == unspecifiedSeriesLabel ? null : tag;
    if (next == seriesTitleOf(members.first)) return;
    for (final m in members) {
      await _ffiUpsertManga(
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
      await _ffiUpsertManga(
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

  /// Delete one manga. Core writes the tombstone via FFI; tombstone now managed
  /// entirely in Core (Class B unload complete).
  Future<void> deleteManga(String id) async {
    final r = RustCoreService.mangaDelete(id);
    if (r != null && r.startsWith('error:')) {
      debugPrint('[MangaLibrary] mangaDelete FFI: $r');
    }
    await reload();
  }

  // ── Cloud sync helpers ────────────────────────────────────────────────────

  Manga? find(String sourceName, String remotePath) {
    final path = normalizeRemotePath(remotePath);
    for (final m in _mangas) {
      if (m.sourceName == sourceName && m.remotePath == path) return m;
    }
    return null;
  }

  /// Every local row as sync ships it. Loose-image rows carry their page list
  /// (membership); CBZ rows never do. Uses fresh data from Rust rather than
  /// the in-memory cache so the snapshot is consistent even if reload() has
  /// not been called yet.
  Future<List<MangaSyncRow>> syncRows() async {
    final mangas = _decodeMangaList(RustCoreService.mangaList());
    final pagesById = <String, List<String>>{};
    for (final m in mangas) {
      if (m.format != MangaFormat.images) continue;
      final ps = _decodePageList(RustCoreService.mangaListPages(m.id));
      if (ps.isNotEmpty) pagesById[m.id] = [for (final p in ps) p.relPath];
    }
    return [
      for (final m in mangas)
        if (!isLegacyLooseManga(
          id: m.id,
          sourceName: m.sourceName,
          remotePath: m.remotePath,
          format: m.format,
        ))
          MangaSyncRow(manga: m, pages: pagesById[m.id] ?? const []),
    ];
  }

  /// Adopt rows pulled from the cloud verbatim (rev kept, tombstone NOT
  /// cleared). Loose-image rows replace local page lists; CBZ rows leave
  /// local page order alone (rebuilt on first open / scrape).
  Future<void> adoptCloudRows(List<MangaSyncRow> rows) async {
    for (final r in rows) {
      if (isLegacyLooseManga(
        id: r.manga.id,
        sourceName: r.manga.sourceName,
        remotePath: r.manga.remotePath,
        format: r.manga.format,
      )) {
        continue;
      }
      await _ffiUpsertManga(r.manga, keepRev: true);
      if (r.manga.format == MangaFormat.images) {
        _ffiSetPages(r.manga.id, [
          for (var i = 0; i < r.pages.length; i++)
            MangaPage(mangaId: r.manga.id, pageIndex: i, relPath: r.pages[i]),
        ]);
      }
    }
    if (rows.isNotEmpty) await reload();
  }

  /// All progress rows, read fresh from Rust.
  Future<List<MangaProgress>> allProgress() async =>
      _decodeProgressList(RustCoreService.mangaListProgress());

  /// Write cloud-newer progress rows (no rev, no tombstone involved).
  Future<void> applyProgress(List<MangaProgress> rows) async {
    for (final p in rows) {
      final r = RustCoreService.mangaSetProgress(p.mangaId, p.pageIndex);
      if (r != null && r.startsWith('error:')) {
        debugPrint('[MangaLibrary] applyProgress FFI: $r');
      }
    }
    if (rows.isNotEmpty) {
      _progress
        ..clear()
        ..addAll({
          for (final p in _decodeProgressList(RustCoreService.mangaListProgress()))
            p.mangaId: p,
        });
      notifyListeners();
    }
  }

  // ── Re-scan ───────────────────────────────────────────────────────────────

  /// Re-scan a loose-image book the user already owns.
  ///
  /// Keeps id, progress, and hand-edited metadata; replaces page list, cover,
  /// page count, and source folder. Bumps rev so peers see membership changes.
  Future<void> rescanLoose(
    String mangaId, {
    required MangaIngestDraft draft,
  }) async {
    final existing = await _ffiGetManga(mangaId);
    if (existing == null) return;
    final folder = normalizeRemotePath(draft.remotePath);
    final pages = <MangaPage>[
      for (var i = 0; i < draft.pageRelPaths.length; i++)
        MangaPage(
          mangaId: mangaId,
          pageIndex: i,
          relPath: draft.pageRelPaths[i],
        ),
    ];
    // _ffiUpsertManga(keepRev: false) bumps rev + clears tombstone.
    await _ffiUpsertManga(existing.copyWith(
      remotePath: folder,
      pageCount: pages.length,
      coverRelpath: pages.isEmpty ? null : pages.first.relPath,
      updatedAt: DateTime.now(),
    ));
    _ffiSetPages(mangaId, pages);
    await reload();
  }

  // ── Static factory helpers ────────────────────────────────────────────────

  /// Build a draft for a loose image directory (list only; no download).
  ///
  /// [imageNames] are bare names inside [folderPath]; the draft resolves them
  /// against the source root so the page list survives the folder moving.
  static MangaIngestDraft draftForImageDir({
    required String sourceName,
    required String folderPath,
    required String folderName,
    required List<String> imageNames,
  }) {
    final root = _sourceRoot(folderPath);
    final sorted = [...imageNames]
      ..sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
    return MangaIngestDraft(
      sourceName: sourceName,
      remotePath: normalizeRemotePath(folderPath),
      title: folderName,
      format: MangaFormat.images,
      pageRelPaths: [for (final n in sorted) _underSourceRoot(root, n)],
      coverRelpath:
          sorted.isEmpty ? null : _underSourceRoot(root, sorted.first),
    );
  }

  /// Merge-mode draft: [pageRelPaths] are relative to [folderPath].
  static MangaIngestDraft draftForMergedImages({
    required String sourceName,
    required String folderPath,
    required String folderName,
    required List<String> pageRelPaths,
  }) {
    final root = _sourceRoot(folderPath);
    final sorted = [...pageRelPaths]
      ..sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
    return MangaIngestDraft(
      sourceName: sourceName,
      remotePath: normalizeRemotePath(folderPath),
      title: folderName,
      format: MangaFormat.images,
      pageRelPaths: [for (final n in sorted) _underSourceRoot(root, n)],
      coverRelpath:
          sorted.isEmpty ? null : _underSourceRoot(root, sorted.first),
    );
  }

  /// `/a/b/` for the folder `/a/b`; `''` for the source root `/`.
  static String _sourceRoot(String folderPath) {
    final folder = normalizeRemotePath(folderPath);
    if (folder == '/') return '';
    return folder.endsWith('/') ? folder : '$folder/';
  }

  /// Join an entry name (or a path relative to the build folder) onto the
  /// source root. Already-absolute entries are kept as they are.
  static String _underSourceRoot(String root, String entry) {
    final name = entry.replaceAll('\\', '/');
    if (name.startsWith('/')) return normalizeRemotePath(name);
    return normalizeRemotePath('$root$name');
  }

  /// Build a draft for a comic container file.
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
