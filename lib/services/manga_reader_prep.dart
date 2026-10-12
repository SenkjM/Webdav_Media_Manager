// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/image_viewer_page.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import '../utils/manga_file_types.dart';
import '../utils/track_identity.dart';
import 'manga_library_service.dart';
import 'prefetch_cache.dart';
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

enum MangaReaderPrepareError { unbound, unsupported, empty, failed }

class MangaReaderPrepareException implements Exception {
  MangaReaderPrepareException(this.kind, [this.detail]);
  final MangaReaderPrepareError kind;
  final String? detail;
}

/// Build viewer pages for a manga: image-dir remotes or CBZ extract.
class MangaReaderPrep {
  MangaReaderPrep._();

  static Future<MangaReaderPrepareResult> prepare({
    required Manga manga,
    required String accountId,
    required WebDavService webDav,
    required MangaLibraryService mangaLib,
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
  }) async {
    final archiveFile = await _ensureCbzLocal(
      manga: manga,
      accountId: accountId,
      webDav: webDav,
    );
    final bytes = await archiveFile.readAsBytes();
    final decoded = ZipDecoder().decodeBytes(bytes, verify: false);
    final imageEntries = <ArchiveFile>[
      for (final f in decoded)
        if (!f.isDirectory && isMangaImageFileName(p.basename(f.name))) f,
    ]..sort(
        (a, b) => mangaPageSortKey(a.name).compareTo(mangaPageSortKey(b.name)),
      );
    if (imageEntries.isEmpty) {
      throw MangaReaderPrepareException(MangaReaderPrepareError.empty);
    }

    var dbPages = await mangaLib.pagesFor(manga.id);
    if (dbPages.isEmpty) {
      dbPages = [
        for (var i = 0; i < imageEntries.length; i++)
          MangaPage(
            mangaId: manga.id,
            pageIndex: i,
            relPath: imageEntries[i].name.replaceAll('\\', '/'),
          ),
      ];
      await mangaLib.replacePages(
        manga.id,
        pages: dbPages,
        coverRelpath: dbPages.first.relPath,
      );
    }

    final outDir = await _mangaExtractDir(manga.id);
    final viewerPages = <ImageViewerPage>[];
    for (var i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final rel = entry.name.replaceAll('\\', '/');
      final base = p.basename(rel);
      final dest = File(
        p.join(outDir.path, '${i.toString().padLeft(5, '0')}_$base'),
      );
      if (!dest.existsSync() || dest.lengthSync() <= 0) {
        final raw = entry.readBytes();
        if (raw == null || raw.isEmpty) {
          throw MangaReaderPrepareException(
            MangaReaderPrepareError.failed,
            'empty page $rel',
          );
        }
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(raw, flush: true);
      }
      viewerPages.add(
        ImageViewerPage(
          id: '${manga.id}:$i',
          name: base,
          localPath: dest.path,
        ),
      );
    }

    final prog = await mangaLib.progressFor(manga.id);
    final initial = (prog?.pageIndex ?? 0).clamp(0, viewerPages.length - 1);
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

  static Future<File> _ensureCbzLocal({
    required Manga manga,
    required String accountId,
    required WebDavService webDav,
  }) async {
    await PrefetchCache.root();
    final dest = await PrefetchCache.file(
      bucket: 'manga_archives',
      accountId: accountId,
      remotePath: manga.remotePath,
      name: p.basename(manga.remotePath),
    );
    if (PrefetchCache.isComplete(dest)) return dest;
    final part = File('${dest.path}.part');
    if (part.existsSync()) part.deleteSync();
    await webDav.downloadToFile(accountId, manga.remotePath, part);
    if (!part.existsSync() || part.lengthSync() <= 0) {
      throw MangaReaderPrepareException(MangaReaderPrepareError.failed);
    }
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
    return dest;
  }

  static Future<Directory> _mangaExtractDir(String mangaId) async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory(
      p.join(cache.path, 'prefetch_cache', 'manga_pages', mangaId),
    );
    await dir.create(recursive: true);
    return dir;
  }
}
