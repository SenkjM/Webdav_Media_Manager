import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Default square edge for new cover thumbs (overridable via Settings).
const int coverThumbSize = 100;

/// Alternate preset offered in Settings.
const int coverThumbSizeLarge = 300;

/// Clamp user-chosen square edge length for thumbs.
const int minCoverThumbSize = 32;
const int maxCoverThumbSize = 1024;

int clampCoverThumbSize(int size) {
  if (size < minCoverThumbSize) return minCoverThumbSize;
  if (size > maxCoverThumbSize) return maxCoverThumbSize;
  return size;
}

/// Decode [bytes], resize to square [size]×[size], encode JPEG.
/// Returns null if decoding fails.
Uint8List? resizeCoverToThumb(Uint8List bytes, {int size = coverThumbSize}) {
  final edge = clampCoverThumbSize(size);
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(
      decoded,
      width: edge,
      height: edge,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  } catch (_) {
    return null;
  }
}

/// True when [width] and [height] match [expected] (default policy size).
bool isCoverThumbSize(int width, int height, {int expected = coverThumbSize}) =>
    width == expected && height == expected;

/// Prefer full-resolution cover when the audio file is on disk; else thumb.
///
/// When [audioIsLocal] is true but [fullCoverPath] is missing, returns null so
/// the caller can load original bytes from tags (Image.memory) instead of the
/// compressed thumb. When not local, returns [thumbPath] as the offline placeholder.
String? resolveLibraryCoverPath({
  required bool audioIsLocal,
  String? fullCoverPath,
  String? thumbPath,
}) {
  if (audioIsLocal) {
    if (fullCoverPath != null && fullCoverPath.isNotEmpty) {
      return fullCoverPath;
    }
    return null;
  }
  if (thumbPath != null && thumbPath.isNotEmpty) return thumbPath;
  return null;
}

/// Missing local audio should trigger download unless already queued/active.
bool shouldEnqueueMissingAudio({
  required bool audioIsLocal,
  required bool alreadyQueuedOrDownloading,
}) {
  if (audioIsLocal) return false;
  if (alreadyQueuedOrDownloading) return false;
  return true;
}
