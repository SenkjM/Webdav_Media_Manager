import 'package:dio/dio.dart';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../services/webdav_service.dart';
import 'directory_walk.dart';

/// Walk [rootPath] with [walk] and return music files not yet in the library.
Future<List<WebDavItem>> collectScanCandidates({
  required WebDavService webDav,
  required String accountId,
  required String sourceName,
  required String rootPath,
  required bool rootIsFile,
  required WalkOptions walk,
  required bool Function(String name) isMusic,
  required bool Function(String remotePath) alreadyInLibrary,
  CancelToken? cancel,
}) async {
  if (rootIsFile) {
    if (!isMusic(rootPath) && !isMusic(rootPath.split('/').last)) {
      return const [];
    }
    final name = rootPath.split('/').where((s) => s.isNotEmpty).last;
    if (alreadyInLibrary(rootPath)) return const [];
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
  final out = <WebDavItem>[];
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
      if (!isMusic(item.name)) continue;
      if (alreadyInLibrary(item.path)) continue;
      out.add(item);
    }
    walker.acceptChildren(dir, childDirs);
  }
  return out;
}
