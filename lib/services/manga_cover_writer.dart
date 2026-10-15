// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../utils/cover_image.dart';
import 'cache_service.dart';

/// Resize a page to the manga cover thumb and replace the local file.
///
/// [thumbSize] controls output:
/// - null or positive → resize + center-crop to that edge (defaults to [coverThumbSize])
/// - 0 ([mangaCoverThumbSizeKeepOriginal]) → store original bytes without resizing
///
/// Returns false when [bytes] are empty or (non-zero size) cannot be decoded.
Future<bool> writeMangaCoverThumb({
  required CacheService cache,
  required String mangaId,
  required Uint8List bytes,
  int? thumbSize,
}) async {
  if (bytes.isEmpty) return false;
  final effectiveSize = thumbSize ?? coverThumbSize;
  if (effectiveSize == mangaCoverThumbSizeKeepOriginal) {
    // Keep original: store bytes as-is, skip resize.
    return replaceMangaCoverBytes(cache: cache, mangaId: mangaId, bytes: bytes);
  }
  final thumb = resizeCoverToThumb(bytes, size: effectiveSize);
  if (thumb == null || thumb.isEmpty) return false;
  return replaceMangaCoverBytes(cache: cache, mangaId: mangaId, bytes: thumb);
}

/// Replace the stored cover bytes as-is.
///
/// Sync already carries a thumb, so adopting a newer row must not resize again.
Future<bool> replaceMangaCoverBytes({
  required CacheService cache,
  required String mangaId,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) return false;
  final file = cache.mangaCoverFile(mangaId);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  try {
    await FileImage(file).evict();
  } catch (_) {}
  await cache.registerMangaCoverWritten(mangaId);
  return true;
}
