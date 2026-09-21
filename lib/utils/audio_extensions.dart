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

/// Stable cache file name derived from the disk name + remote path (avoids
/// collisions). Renaming a disk therefore orphans its cached audio — that is the
/// documented "改名 = 换盘" semantics of the name-only binding.
String cacheFileNameForRemote(String remotePath, {String? sourceName}) {
  final base = sanitizeFileName(p.basename(remotePath));
  if (sourceName == null || sourceName.isEmpty) {
    final hash = remotePath.hashCode.toRadixString(16);
    return '${hash}_$base';
  }
  final stem = identityHashStem(sourceName, remotePath);
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

/// MIME type used when handing a file to MediaStore / the share sheet.
String galleryMimeFor(String fileName) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mkv':
      return 'video/x-matroska';
    case '.webm':
      return 'video/webm';
    case '.avi':
      return 'video/x-msvideo';
    case '.mov':
      return 'video/quicktime';
    case '.flv':
      return 'video/x-flv';
    case '.ts':
      return 'video/mp2t';
    case '.wmv':
      return 'video/x-ms-wmv';
    case '.3gp':
      return 'video/3gpp';
    case '.mpg':
    case '.mpeg':
      return 'video/mpeg';
    case '.mp3':
      return 'audio/mpeg';
    case '.flac':
      return 'audio/flac';
    case '.m4a':
    case '.aac':
      return 'audio/mp4';
    case '.ogg':
    case '.opus':
      return 'audio/ogg';
    case '.wav':
      return 'audio/wav';
    case '.wma':
      return 'audio/x-ms-wma';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.zip':
      return 'application/zip';
    case '.json':
      return 'application/json';
    case '.m3u8':
      return 'application/vnd.apple.mpegurl';
    default:
      return 'application/octet-stream';
  }
}

/// MIME type of an audio file for sharing (falls back to octet-stream).
String audioShareMimeFor(String path) {
  final mime = galleryMimeFor(path);
  return mime.startsWith('audio/') ? mime : 'application/octet-stream';
}
