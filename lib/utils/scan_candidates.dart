import 'package:dio/dio.dart';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../services/webdav_service.dart';
import 'directory_walk.dart';

/// One music/CUE file path from a lightweight directory walk.
class ScanPathEntry {
  const ScanPathEntry({
    required this.path,
    required this.name,
    required this.isCue,
  });

  final String path;
  final String name;
  final bool isCue;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'cue': isCue,
      };

  factory ScanPathEntry.fromJson(Map<String, dynamic> json) {
    return ScanPathEntry(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isCue: json['cue'] == true,
    );
  }

  WebDavItem toItem() => WebDavItem(
        name: name,
        path: path,
        isDirectory: false,
        category: isCue ? FileCategory.cue : FileCategory.music,
      );
}

/// Lightweight walk: listDirectory only → music + CUE paths (CUE first).
///
/// No library lookups, no CUE parse, no tags. Yields after each directory.
Future<List<ScanPathEntry>> listScanPaths({
  required WebDavService webDav,
  required String accountId,
  required String rootPath,
  required bool rootIsFile,
  required WalkOptions walk,
  required bool Function(String name) isMusic,
  required bool Function(String name) isCue,
  CancelToken? cancel,
}) async {
  if (rootIsFile) {
    final name = rootPath.split('/').where((s) => s.isNotEmpty).last;
    if (isCue(name)) {
      return [ScanPathEntry(path: rootPath, name: name, isCue: true)];
    }
    if (isMusic(name) || isMusic(rootPath)) {
      return [ScanPathEntry(path: rootPath, name: name, isCue: false)];
    }
    return const [];
  }

  final walker = DirectoryWalker(rootPath: rootPath, options: walk);
  final cues = <ScanPathEntry>[];
  final music = <ScanPathEntry>[];
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
        cues.add(ScanPathEntry(path: item.path, name: item.name, isCue: true));
        continue;
      }
      if (isMusic(item.name)) {
        music.add(
          ScanPathEntry(path: item.path, name: item.name, isCue: false),
        );
      }
    }
    walker.acceptChildren(dir, childDirs);
    await Future<void>.delayed(Duration.zero);
  }
  return [...cues, ...music];
}

/// Fallback walk when a scan task has no prelisted payload (old tasks / resume).
///
/// Applies incremental library filters. CUE first. No CUE parse / tags.
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
  required bool Function(String cueRemotePath) cueAlbumInLibrary,
  required bool Function(String audioRemotePath) audioCoveredByCue,
  CancelToken? cancel,
}) async {
  final listed = await listScanPaths(
    webDav: webDav,
    accountId: accountId,
    rootPath: rootPath,
    rootIsFile: rootIsFile,
    walk: walk,
    isMusic: isMusic,
    isCue: isCue,
    cancel: cancel,
  );
  final out = <WebDavItem>[];
  for (final e in listed) {
    if (e.isCue) {
      if (!cueAlbumInLibrary(e.path)) out.add(e.toItem());
    } else {
      if (alreadyInLibrary(e.path) || audioCoveredByCue(e.path)) continue;
      out.add(e.toItem());
    }
  }
  return out;
}
