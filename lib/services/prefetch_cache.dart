import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/audio_extensions.dart';

/// Process-lifetime bytes for image and audio prefetch.
///
/// The directory lives under the application cache. It is wiped once at
/// startup, before playback, and is not deleted when a file slides out of
/// the current window or when a page is disposed.
class PrefetchCache {
  PrefetchCache._();

  static const String folderName = 'prefetch_cache';

  static Future<Directory> root() async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory(p.join(cache.path, folderName));
    await dir.create(recursive: true);
    return dir;
  }

  /// Delete the prefetch cache. Call once at startup, before any player.
  static Future<void> wipe() async {
    try {
      final cache = await getApplicationCacheDirectory();
      final dir = Directory(p.join(cache.path, folderName));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<File> file({
    required String bucket,
    required String accountId,
    required String remotePath,
    required String name,
  }) async {
    final dir = Directory(p.join((await root()).path, bucket));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _fileName(accountId, remotePath, name)));
  }

  static bool isComplete(File file) {
    try {
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<File> writeBytes({
    required String bucket,
    required String accountId,
    required String remotePath,
    required String name,
    required List<int> bytes,
  }) async {
    final dest = await file(
      bucket: bucket,
      accountId: accountId,
      remotePath: remotePath,
      name: name,
    );
    final part = File('${dest.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
    return dest;
  }

  static String _fileName(String accountId, String remotePath, String name) {
    final digest = sha1
        .convert(utf8.encode('$accountId\n$remotePath'))
        .toString()
        .substring(0, 20);
    var base = sanitizeFileName(name);
    if (base.isEmpty) base = 'file';
    if (base.length > 80) base = base.substring(base.length - 80);
    return '${digest}_$base';
  }
}
