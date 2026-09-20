import 'package:path/path.dart' as p;

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

String sanitizeFileName(String name) {
  return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

/// Stable cache file name derived from remote path (avoids collisions).
String cacheFileNameForRemote(String remotePath) {
  final base = p.basename(remotePath);
  final hash = remotePath.hashCode.toRadixString(16);
  return '${hash}_$base';
}
