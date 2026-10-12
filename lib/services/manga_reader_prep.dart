// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/image_viewer_page.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import '../utils/cbz_range_zip.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'manga_library_service.dart';
import 'webdav_service.dart';

class MangaReaderPrepareResult {
  const MangaReaderPrepareResult({
    required this.pages,
    required this.initialIndex,
    required this.manga,
  });

  final List<ImageViewerPage> pages;
  final int initialIndex;
  final Manga manga;
}

enum MangaReaderPrepareError {
  unbound,
  unsupported,
  empty,
  failed,

  /// Remote ignored Range — UI should offer full-cache then retry.
  rangeUnsupported,
}

class MangaReaderPrepareException implements Exception {
  MangaReaderPrepareException(this.kind, [this.detail]);
  final MangaReaderPrepareError kind;
  final String? detail;
}

/// Build viewer pages for a manga: image-dir remotes or CBZ (Range or cache).
class MangaReaderPrep {
  MangaReaderPrep._();

  static Future<MangaReaderPrepareResult> prepare({
    required Manga manga,
    required String accountId,
    required WebDavService webDav,
    required MangaLibraryService mangaLib,
    CacheService? cache,

    /// When true, download whole CBZ into manga_cache (after Range refused).
    bool forceFullCache = false,
  }) async {
    switch (manga.format) {
      case MangaFormat.images:
        return _prepareImages(manga: manga, mangaLib: mangaLib);
      case MangaFormat.cbz:
        return _prepareCbz(
          manga: manga,
          accountId: accountId,
          webDav: webDav,
          mangaLib: mangaLib,
          cache: cache,
          forceFullCache: forceFullCache,
        );
      case MangaFormat.cbr:
      case MangaFormat.pdf:
      case MangaFormat.epub:
      default:
        throw MangaReaderPrepareException(MangaReaderPrepareError.unsupported);
    }
  }

  static Future<MangaReaderPrepareResult> _prepareImages({
    required Manga manga,
    required MangaLibraryService mangaLib,
  }) async {
    final pages = await mangaLib.pagesFor(manga.id);
    if (pages.isEmpty) {
      throw MangaReaderPrepareException(MangaReaderPrepareError.empty);
    }
    final root = normalizeRemotePath(manga.remotePath);
    final rootPrefix = root.endsWith('/') ? root : '$root/';
    final viewerPages = <ImageViewerPage>[
      for (final page in pages)
        ImageViewerPage(
          id: '${manga.id}:${page.pageIndex}',
          name: page.relPath.split('/').where((s) => s.isNotEmpty).last,
          remotePath: page.relPath.startsWith('/')
              ? normalizeRemotePath(page.relPath)
              : normalizeRemotePath('$rootPrefix${page.relPath}'),
        ),
    ];
    final prog = await mangaLib.progressFor(manga.id);
    final initial = (prog?.pageIndex ?? 0).clamp(0, viewerPages.length - 1);
    return MangaReaderPrepareResult(
      pages: viewerPages,
      initialIndex: initial,
      manga: manga,
    );
  }

  static Future<MangaReaderPrepareResult> _prepareCbz({
    required Manga manga,
    required String accountId,
    required WebDavService webDav,
    required MangaLibraryService mangaLib,
    CacheService? cache,
    required bool forceFullCache,
  }) async {
    // Prefer full local cache when present.
    final cached = cache?.mangaFileForRemote(
      manga.remotePath,
      sourceName: manga.sourceName,
    );
    if (cached != null && cached.existsSync() && cached.lengthSync() > 0) {
      return _prepareCbzFromLocalFile(
        manga: manga,
        archiveFile: cached,
        mangaLib: mangaLib,
      );
    }

    if (forceFullCache) {
      if (cache == null) {
        throw MangaReaderPrepareException(MangaReaderPrepareError.failed);
      }
      final archiveFile = await _downloadFullCbz(
        manga: manga,
        accountId: accountId,
        webDav: webDav,
        cache: cache,
      );
      return _prepareCbzFromLocalFile(
        manga: manga,
        archiveFile: archiveFile,
        mangaLib: mangaLib,
      );
    }

    // Stream via HTTP Range.
    try {
      final source = await webDav.resolveStreamSource(
        accountId: accountId,
        remotePath: manga.remotePath,
        name: p.basename(manga.remotePath),
      );
      if (source == null) {
        throw MangaReaderPrepareException(MangaReaderPrepareError.failed);
      }
      final zip = CbzRangeZip(source: source);
      await zip.open();
      return await _prepareCbzWithZip(
        manga: manga,
        mangaLib: mangaLib,
        zip: zip,
      );
    } on CbzRangeUnsupportedException catch (e) {
      throw MangaReaderPrepareException(
        MangaReaderPrepareError.rangeUnsupported,
        e.detail,
      );
    }
  }

  /// Shared body of both CBZ paths. Only the EOCD and the central directory are
  /// read up front; the page payloads come out lazily, one prefetch window at a
  /// time, through the [ImageViewerPage.localLoader] each page carries. The page
  /// the reader is about to show is fetched eagerly so the first frame is not
  /// blank — a 180-page CBZ used to cost the whole archive before showing it.
  /// [zip] may be backed by HTTP Range or by a local archive.
  static Future<MangaReaderPrepareResult> _prepareCbzWithZip({
    required Manga manga,
    required MangaLibraryService mangaLib,
    required CbzRangeZip zip,
  }) async {
    final imageEntries = zip.imageEntries;
    if (imageEntries.isEmpty) {
      throw MangaReaderPrepareException(MangaReaderPrepareError.empty);
    }

    final total = imageEntries.length;

    // Resolve the reading position *before* touching a single page: the page
    // the reader opens on is the only one worth blocking for.
    final prog = await mangaLib.progressFor(manga.id);
    final initial = (prog?.pageIndex ?? 0).clamp(0, total - 1);

    final dbPages = await mangaLib.pagesFor(manga.id);
    if (dbPages.isEmpty) {
      await mangaLib.replacePages(
        manga.id,
        pages: [
          for (var i = 0; i < total; i++)
            MangaPage(
              mangaId: manga.id,
              pageIndex: i,
              relPath: imageEntries[i].name.replaceAll('\\', '/'),
            ),
        ],
        coverRelpath: imageEntries.first.name.replaceAll('\\', '/'),
      );
    }

    final outDir = await _mangaPageDir(manga.id);
    final viewerPages = <ImageViewerPage>[];
    for (var i = 0; i < total; i++) {
      final entry = imageEntries[i];
      final rel = entry.name.replaceAll('\\', '/');
      final base = p.basename(rel);
      final dest = File(
        p.join(outDir.path, '${i.toString().padLeft(5, '0')}_$base'),
      );
      viewerPages.add(
        ImageViewerPage(
          id: '${manga.id}:$i',
          name: base,
          localPath: dest.path,
          localLoader: (target) => _extractEntryTo(zip, entry, target),
        ),
      );
    }

    // Only the page the reader opens on is fetched here. Everything else waits
    // for the viewer's prefetch window to call each page's localLoader.
    try {
      await _extractEntryTo(
        zip,
        imageEntries[initial],
        File(viewerPages[initial].localPath!),
      );
    } on MangaReaderPrepareException {
      rethrow;
    } catch (_) {
      // Transient failure: the viewer retries this page through localLoader.
    }
    final latest = mangaLib.mangas.cast<Manga?>().firstWhere(
      (m) => m?.id == manga.id,
      orElse: () => manga,
    )!;
    return MangaReaderPrepareResult(
      pages: viewerPages,
      initialIndex: initial,
      manga: latest,
    );
  }

  /// Materialises one archive entry at [dest], skipping the round trip when it
  /// is already there. Both the eager seed above and the viewer's lazy
  /// [ImagePageLoader] go through here.
  static Future<void> _extractEntryTo(
    CbzRangeZip zip,
    CbzZipEntry entry,
    File dest,
  ) async {
    if (dest.existsSync() && dest.lengthSync() > 0) return;
    final raw = await zip.extractEntry(entry);
    if (raw.isEmpty) {
      throw MangaReaderPrepareException(
        MangaReaderPrepareError.failed,
        'empty page ${entry.name}',
      );
    }
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(raw, flush: true);
  }

  /// Same walk as the Range path, but reading straight out of the local
  /// archive: only the EOCD, the central directory and the page payloads are
  /// touched, so a large CBZ no longer costs its own size in memory.
  static Future<MangaReaderPrepareResult> _prepareCbzFromLocalFile({
    required Manga manga,
    required File archiveFile,
    required MangaLibraryService mangaLib,
  }) async {
    final zip = CbzRangeZip(file: archiveFile);
    await zip.open();
    return _prepareCbzWithZip(manga: manga, mangaLib: mangaLib, zip: zip);
  }

  static Future<File> _downloadFullCbz({
    required Manga manga,
    required String accountId,
    required WebDavService webDav,
    required CacheService cache,
  }) async {
    final dest = cache.mangaFileForRemote(
      manga.remotePath,
      sourceName: manga.sourceName,
    );
    if (dest.existsSync() && dest.lengthSync() > 0) return dest;
    final part = File('${dest.path}.part');
    if (part.existsSync()) part.deleteSync();
    await dest.parent.create(recursive: true);
    await webDav.downloadToFile(accountId, manga.remotePath, part);
    if (!part.existsSync() || part.lengthSync() <= 0) {
      throw MangaReaderPrepareException(MangaReaderPrepareError.failed);
    }
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
    return dest;
  }

  static Future<Directory> _mangaPageDir(String mangaId) async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory(
      p.join(cache.path, 'prefetch_cache', 'manga_pages', mangaId),
    );
    await dir.create(recursive: true);
    return dir;
  }
}
