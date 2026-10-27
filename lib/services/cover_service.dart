import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/cover_image.dart';
import '../utils/track_identity.dart';

/// Stores square album-art thumbs under `covers/`.
///
/// The original embedded art is **not** cached anymore: when the audio file is
/// local it is read from that file's tags on demand. Thumbs stay on disk so a
/// track keeps its cover after the audio cache is cleaned up (and they are what
/// list/notification surfaces use). Thumb edge defaults to [coverThumbSize];
/// override via [thumbSize] for newly written thumbs. Existing files keep their
/// old size until re-ingest.
class CoverService {
  Directory? _coversDir;

  /// Cached path for sync access after [init]. `null` until init completes.
  String? _coversDirPath;

  bool _legacyFullPurged = false;

  /// Square edge (px) used by [saveThumb] when no explicit size is passed.
  int thumbSize = coverThumbSize;

  Future<Directory> get coversDir async {
    if (_coversDir != null) return _coversDir!;
    final root = await getApplicationDocumentsDirectory();
    _coversDir = Directory(p.join(root.path, 'covers'));
    if (!await _coversDir!.exists()) {
      await _coversDir!.create(recursive: true);
    }
    _coversDirPath = _coversDir!.path;
    return _coversDir!;
  }

  String coverFileName(String sourceName, String remotePath) {
    return '${identityHashStem(sourceName, remotePath)}.jpg';
  }

  /// Synchronous thumb path — returns `null` if [init] has not completed yet.
  ///
  /// The path is *deterministic* (derived from identity) so callers may display
  /// it as a [FileImage] immediately, gated on [File.existsSync].
  String? thumbPath(String sourceName, String remotePath) {
    final dir = _coversDirPath;
    if (dir == null) return null;
    return p.join(dir, coverFileName(sourceName, remotePath));
  }

  Future<File> coverFile(String sourceName, String remotePath) async {
    final dir = await coversDir;
    return File(p.join(dir.path, coverFileName(sourceName, remotePath)));
  }

  /// Transcode/resize [bytes] to square JPEG and write under covers/.
  /// Uses [size] or [thumbSize] (Settings). Returns local path, or null if
  /// [bytes] could not be decoded.
  Future<String?> saveThumb({
    required String sourceName,
    required String remotePath,
    required Uint8List bytes,
    int? size,
  }) async {
    final thumb = resizeCoverToThumb(bytes, size: size ?? thumbSize);
    if (thumb == null) return null;
    final file = await coverFile(sourceName, remotePath);
    await file.writeAsBytes(thumb, flush: true);
    // The path is stable per track, so Flutter's decoded-image cache would keep
    // serving the old art after a re-scrape; evict it explicitly.
    try {
      await FileImage(file).evict();
    } catch (_) {}
    return file.path;
  }

  /// Thin ensure helper: write thumb bytes only if the deterministic file is
  /// absent. Returns the thumb path on success, `null` if bytes are not
  /// available or decode fails.
  ///
  /// Does **not** write to the database; callers update [CoverState] after
  /// this returns a non-null path.
  ///
  /// [fetchBytes] is called at most once, only when the file is missing.
  Future<String?> ensureMusicCoverFile({
    required String sourceName,
    required String remotePath,
    required Future<Uint8List?> Function() fetchBytes,
    int? size,
  }) async {
    final file = await coverFile(sourceName, remotePath);
    if (await file.exists()) return file.path;
    final bytes = await fetchBytes();
    if (bytes == null || bytes.isEmpty) return null;
    return saveThumb(
      sourceName: sourceName,
      remotePath: remotePath,
      bytes: bytes,
      size: size,
    );
  }

  Future<void> deleteThumb(String sourceName, String remotePath) async {
    final file = await coverFile(sourceName, remotePath);
    if (await file.exists()) {
      try {
        await FileImage(file).evict();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Remove the legacy `covers_full/` directory (original-art cache).
  ///
  /// Originals are no longer maintained: local audio art is read from the
  /// audio file's tags when needed, remote rows only keep a thumb. Runs once per
  /// process from [init]; best-effort.
  Future<void> purgeFullCovers() async {
    if (_legacyFullPurged) return;
    _legacyFullPurged = true;
    try {
      final root = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(root.path, 'covers_full'));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Wipe all compressed thumbs (library destroy) and any legacy full covers.
  Future<void> deleteAllCovers() async {
    final dir = await coversDir;
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
    try {
      final root = await getApplicationDocumentsDirectory();
      final full = Directory(p.join(root.path, 'covers_full'));
      if (await full.exists()) await full.delete(recursive: true);
    } catch (_) {}
  }

  /// Ensure the covers dir exists and drop the legacy original-art cache.
  Future<void> init() async {
    await coversDir;
    await purgeFullCovers();
  }
}
