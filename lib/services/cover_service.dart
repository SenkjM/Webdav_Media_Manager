import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/cover_image.dart';
import '../utils/track_identity.dart';

/// Stores square album art thumbs under `covers/` and optional full-resolution
/// originals under `covers_full/` for faster display when the audio file is local.
/// Thumb edge length defaults to [coverThumbSize]; override via [thumbSize]
/// (Settings) for newly written thumbs. Existing files keep their old size until
/// re-ingest or library destroy + re-download.
class CoverService {
  Directory? _coversDir;
  Directory? _coversFullDir;

  /// Square edge (px) used by [saveThumb] when no explicit size is passed.
  int thumbSize = coverThumbSize;

  Future<Directory> get coversDir async {
    if (_coversDir != null) return _coversDir!;
    final root = await getApplicationDocumentsDirectory();
    _coversDir = Directory(p.join(root.path, 'covers'));
    if (!await _coversDir!.exists()) {
      await _coversDir!.create(recursive: true);
    }
    return _coversDir!;
  }

  Future<Directory> get coversFullDir async {
    if (_coversFullDir != null) return _coversFullDir!;
    final root = await getApplicationDocumentsDirectory();
    _coversFullDir = Directory(p.join(root.path, 'covers_full'));
    if (!await _coversFullDir!.exists()) {
      await _coversFullDir!.create(recursive: true);
    }
    return _coversFullDir!;
  }

  String coverFileName(String accountId, String remotePath) {
    return '${identityHashStem(accountId, remotePath)}.jpg';
  }

  Future<File> coverFile(String accountId, String remotePath) async {
    final dir = await coversDir;
    return File(p.join(dir.path, coverFileName(accountId, remotePath)));
  }

  /// Transcode/resize [bytes] to square JPEG and write under covers/.
  /// Uses [size] or [thumbSize] (Settings). Returns local path, or null if
  /// [bytes] could not be decoded.
  Future<String?> saveThumb({
    required String accountId,
    required String remotePath,
    required Uint8List bytes,
    int? size,
  }) async {
    final thumb = resizeCoverToThumb(bytes, size: size ?? thumbSize);
    if (thumb == null) return null;
    final file = await coverFile(accountId, remotePath);
    await file.writeAsBytes(thumb, flush: true);
    return file.path;
  }

  static String _extensionForBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return 'jpg';
  }

  /// Persist original cover bytes under covers_full/ (not resized).
  Future<String?> saveFull({
    required String accountId,
    required String remotePath,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return null;
    final dir = await coversFullDir;
    final stem = identityHashStem(accountId, remotePath);
    final ext = _extensionForBytes(bytes);
    // Remove prior variants so only one full cover remains.
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('$stem.')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
    final file = File(p.join(dir.path, '$stem.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Sync lookup of a previously saved full-res cover (null if missing / not ready).
  String? fullCoverPathSync(String accountId, String remotePath) {
    final dir = _coversFullDir;
    if (dir == null) return null;
    final stem = identityHashStem(accountId, remotePath);
    for (final ext in const ['jpg', 'jpeg', 'png', 'webp']) {
      final f = File(p.join(dir.path, '$stem.$ext'));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Future<String?> fullCoverPath(
    String accountId,
    String remotePath,
  ) async {
    final dir = await coversFullDir;
    final stem = identityHashStem(accountId, remotePath);
    for (final ext in const ['jpg', 'jpeg', 'png', 'webp']) {
      final f = File(p.join(dir.path, '$stem.$ext'));
      if (await f.exists()) return f.path;
    }
    return null;
  }

  Future<void> deleteThumb(String accountId, String remotePath) async {
    final file = await coverFile(accountId, remotePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> deleteFull(String accountId, String remotePath) async {
    final dir = await coversFullDir;
    final stem = identityHashStem(accountId, remotePath);
    await for (final entity in dir.list()) {
      if (entity is File && p.basename(entity.path).startsWith('$stem.')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  /// Wipe all compressed thumbs and full-res covers (library destroy).
  Future<void> deleteAllCovers() async {
    for (final getter in [coversDir, coversFullDir]) {
      final dir = await getter;
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  }

  /// Ensure covers_full dir is created so [fullCoverPathSync] can work after init.
  Future<void> init() async {
    await coversDir;
    await coversFullDir;
  }
}
