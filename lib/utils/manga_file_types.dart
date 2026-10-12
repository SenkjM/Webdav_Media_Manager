// SPDX-License-Identifier: AGPL-3.0-or-later
import '../models/manga.dart';
import 'audio_extensions.dart';

/// Default comic-container extensions (no leading dot).
const List<String> kDefaultComicExtensions = [
  'cbz',
  'cbr',
  'pdf',
  'epub',
];

/// Extra image suffixes accepted for loose image-dir scans (beyond FileTypeConfig).
const List<String> kMangaImageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'avif',
];

bool isComicContainerFileName(String name) {
  final ext = extensionOf(name);
  return kDefaultComicExtensions.contains(ext);
}

bool isMangaImageFileName(String name, {List<String>? imageExtensions}) {
  final exts = imageExtensions ?? kMangaImageExtensions;
  return isImageFileNameWith(name, exts);
}

String mangaFormatForFileName(String name) {
  final ext = extensionOf(name);
  return switch (ext) {
    'cbz' => MangaFormat.cbz,
    'cbr' => MangaFormat.cbr,
    'pdf' => MangaFormat.pdf,
    'epub' => MangaFormat.epub,
    _ => MangaFormat.unknown,
  };
}

String extensionOf(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0 || i == name.length - 1) return '';
  return name.substring(i + 1).toLowerCase();
}

/// Natural-ish sort key for page file names (zero-pad trailing numbers lightly).
String mangaPageSortKey(String name) {
  return name.toLowerCase().replaceAllMapped(
    RegExp(r'(\d+)'),
    (m) => m.group(1)!.padLeft(8, '0'),
  );
}
