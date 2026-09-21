import 'package:path/path.dart' as p;

import 'track_identity.dart';

bool isCueFileName(String name) => name.toLowerCase().endsWith('.cue');

bool isAudioFileName(String name) {
  final lower = name.toLowerCase();
  const exts = [
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
  ];
  return exts.any(lower.endsWith);
}

bool isVideoFileName(String name) {
  final lower = name.toLowerCase();
  const exts = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.flv',
    '.ts',
    '.m4v',
    '.wmv',
    '.3gp',
    '.mpg',
    '.mpeg',
  ];
  return exts.any(lower.endsWith);
}

/// Extension check against a caller-supplied list (without leading dots).
bool isCueFileNameWith(String name, List<String> extensions) =>
    extensions.any((e) => name.toLowerCase().endsWith('.$e'));

bool isAudioFileNameWith(String name, List<String> extensions) =>
    extensions.any((e) => name.toLowerCase().endsWith('.$e'));

bool isVideoFileNameWith(String name, List<String> extensions) =>
    extensions.any((e) => name.toLowerCase().endsWith('.$e'));

String sanitizeFileName(String name) {
  return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

/// Percent-encode a WebDAV path's segments while keeping `/` separators.
///
/// `webdav_client` stores decoded paths (spaces / non-ASCII as literal
/// characters), so a streaming URL handed to libmpv must re-encode them.
String encodeWebDavPath(String path) {
  return path
      .split('/')
      .map((seg) => Uri.encodeComponent(seg))
      .join('/');
}

/// Stable cache file name derived from account + remote path (avoids collisions).
String cacheFileNameForRemote(String remotePath, {String? accountId}) {
  final base = sanitizeFileName(p.basename(remotePath));
  if (accountId == null || accountId.isEmpty) {
    final hash = remotePath.hashCode.toRadixString(16);
    return '${hash}_$base';
  }
  final stem = identityHashStem(accountId, remotePath);
  return '${stem}_$base';
}

/// Current folder name for breadcrumb (never show full remote path).
String folderDisplayName(String path) {
  if (path.isEmpty || path == '/') return '根目录';
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final name = p.basename(trimmed);
  return name.isEmpty ? '根目录' : name;
}


String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
