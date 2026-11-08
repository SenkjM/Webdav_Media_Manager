// SPDX-License-Identifier: AGPL-3.0-or-later
import '../services/webdav_service.dart';
import 'directory_walk.dart';
import 'manga_file_types.dart';
import 'track_identity.dart';

/// One comic-container file found during a recursive folder scan.
class MangaComicHit {
  const MangaComicHit({required this.path, required this.name});
  final String path;
  final String name;
}

/// Images found under one directory (relative to that directory).
class MangaImageDirHit {
  const MangaImageDirHit({
    required this.folderPath,
    required this.folderName,
    required this.imageNames,
  });
  final String folderPath;
  final String folderName;
  final List<String> imageNames;
}

/// Recursive: collect comic containers under [rootPath] (no download).
///
/// [comicExtensions] 从设置来（见 [FileTypeConfig.comicExtensions]）；不传则用
/// 出厂默认。空列表表示「一个后缀都不认」。
Future<List<MangaComicHit>> listComicContainersRecursive({
  required WebDavService webDav,
  required String accountId,
  required String rootPath,
  List<String>? comicExtensions,
  WalkOptions walk = const WalkOptions(
    includeSubdirs: true,
    maxDepth: 20,
    maxEntries: 2000,
  ),
}) async {
  final result = await DirectoryWalker.scan(
    accountId: accountId,
    rootPath: rootPath,
    options: walk,
    extensions: comicExtensions ?? kDefaultComicExtensions,
  );
  final hits = [
    for (final entry in result.files)
      MangaComicHit(path: entry.path, name: entry.name),
  ];
  hits.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return hits;
}

/// Walk tree; group images by containing directory (for per-dir create).
Future<List<MangaImageDirHit>> listImageDirsRecursive({
  required WebDavService webDav,
  required String accountId,
  required String rootPath,
  required List<String> imageExtensions,
  WalkOptions walk = const WalkOptions(
    includeSubdirs: true,
    maxDepth: 20,
    maxEntries: 2000,
  ),
}) async {
  final result = await DirectoryWalker.scan(
    accountId: accountId,
    rootPath: rootPath,
    options: walk,
    extensions: imageExtensions,
  );
  final byDir = <String, List<String>>{};
  final names = <String, String>{};
  for (final entry in result.files) {
    final norm = normalizeRemotePath(entry.directory);
    (byDir[norm] ??= []).add(entry.name);
    names[norm] = _folderName(norm);
  }
  for (final images in byDir.values) {
    images.sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
  }
  final keys = byDir.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final k in keys)
      MangaImageDirHit(
        folderPath: k,
        folderName: names[k]!,
        imageNames: byDir[k]!,
      ),
  ];
}

/// Flatten all images under [rootPath] into relative paths from root (merge mode).
Future<List<String>> listMergedImageRelPaths({
  required WebDavService webDav,
  required String accountId,
  required String rootPath,
  required List<String> imageExtensions,
  WalkOptions walk = const WalkOptions(
    includeSubdirs: true,
    maxDepth: 20,
    maxEntries: 2000,
  ),
}) async {
  final root = normalizeRemotePath(rootPath);
  final rootPrefix = root.endsWith('/') ? root : '$root/';
  final result = await DirectoryWalker.scan(
    accountId: accountId,
    rootPath: rootPath,
    options: walk,
    extensions: imageExtensions,
  );
  final rels = <String>[];
  for (final entry in result.files) {
    final full = normalizeRemotePath(entry.path);
    String rel;
    if (normalizeRemotePath(entry.directory) == root || full == root) {
      rel = entry.name;
    } else if (full.startsWith(rootPrefix)) {
      rel = full.substring(rootPrefix.length);
    } else {
      rel = entry.name;
    }
    rels.add(rel);
  }
  rels.sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
  return rels;
}

String _folderName(String path) {
  final parts = normalizeRemotePath(path).split('/').where((s) => s.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}
