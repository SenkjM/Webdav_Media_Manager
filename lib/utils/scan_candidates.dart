import 'package:dio/dio.dart';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../services/webdav_service.dart';
import 'directory_walk.dart';

/// Walk [rootPath] and return music + CUE file paths not yet in the library.
///
/// **Stats / scrape shared walker** — only lists paths (no CUE parse, no tags).
/// CUE entries are listed first so the scrape executor can ingest them before
/// plain audio. [audioCoveredByCue] skips raw audio already represented by an
/// existing CUE album (incremental). Stats count one unit per .cue path (not
/// per slice).
Future<List<WebDavItem>> collectScanCandidates({
  required WebDavService webDav,
  required String accountId,
  required String sourceName,
  required String rootPath,
  required bool rootIsFile,
  required WalkOptions walk,
  required bool Function(String name) isMusic,
  required bool Function(String name) isCue,
  required bool Function(String remotePath) alreadyInLibrary,
  /// True when any library slice already binds this `.cue` path.
  required bool Function(String cueRemotePath) cueAlbumInLibrary,
  /// True when a raw audio path is already the backing file of a CUE slice.
  required bool Function(String audioRemotePath) audioCoveredByCue,
  CancelToken? cancel,
}) async {
  if (rootIsFile) {
    final name = rootPath.split('/').where((s) => s.isNotEmpty).last;
    if (isCue(name)) {
      if (cueAlbumInLibrary(rootPath)) return const [];
      return [
        WebDavItem(
          name: name,
          path: rootPath,
          isDirectory: false,
          category: FileCategory.cue,
        ),
      ];
    }
    if (!isMusic(rootPath) && !isMusic(name)) return const [];
    if (alreadyInLibrary(rootPath) || audioCoveredByCue(rootPath)) {
      return const [];
    }
    return [
      WebDavItem(
        name: name,
        path: rootPath,
        isDirectory: false,
        category: FileCategory.music,
      ),
    ];
  }

  final walker = DirectoryWalker(rootPath: rootPath, options: walk);
  final cues = <WebDavItem>[];
  final music = <WebDavItem>[];
  while (true) {
    if (cancel?.isCancelled ?? false) break;
    final dir = walker.nextDirectory();
    if (dir == null) break;
    final items = await webDav.listDirectory(accountId, dir);
    final childDirs = <String>[];
    for (final item in items) {
      if (item.isDirectory) {
        childDirs.add(item.path);
        continue;
      }
      if (isCue(item.name)) {
        if (!cueAlbumInLibrary(item.path)) cues.add(item);
        continue;
      }
      if (!isMusic(item.name)) continue;
      if (alreadyInLibrary(item.path)) continue;
      if (audioCoveredByCue(item.path)) continue;
      music.add(item);
    }
    walker.acceptChildren(dir, childDirs);
  }
  // CUE first so scrape can mark covered audio before plain ingest.
  return [...cues, ...music];
}
