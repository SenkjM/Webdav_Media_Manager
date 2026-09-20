import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/cover_image.dart';
import '../utils/track_identity.dart';

/// Stores 100×100 album art thumbs under app documents `covers/`.
/// Never keeps full-size original art for persistence.
class CoverService {
  Directory? _coversDir;

  Future<Directory> get coversDir async {
    if (_coversDir != null) return _coversDir!;
    final root = await getApplicationDocumentsDirectory();
    _coversDir = Directory(p.join(root.path, 'covers'));
    if (!await _coversDir!.exists()) {
      await _coversDir!.create(recursive: true);
    }
    return _coversDir!;
  }

  String coverFileName(String accountId, String remotePath) {
    return '${identityHashStem(accountId, remotePath)}.jpg';
  }

  Future<File> coverFile(String accountId, String remotePath) async {
    final dir = await coversDir;
    return File(p.join(dir.path, coverFileName(accountId, remotePath)));
  }

  /// Transcode/resize [bytes] to 100×100 JPEG and write under covers/.
  /// Returns local path, or null if [bytes] could not be decoded.
  Future<String?> saveThumb({
    required String accountId,
    required String remotePath,
    required Uint8List bytes,
  }) async {
    final thumb = resizeCoverToThumb(bytes);
    if (thumb == null) return null;
    final file = await coverFile(accountId, remotePath);
    await file.writeAsBytes(thumb, flush: true);
    return file.path;
  }

  Future<void> deleteThumb(String accountId, String remotePath) async {
    final file = await coverFile(accountId, remotePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
