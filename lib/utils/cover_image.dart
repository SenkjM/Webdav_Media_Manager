import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Policy: persisted album art is always square [coverThumbSize]×[coverThumbSize].
const int coverThumbSize = 100;

/// Decode [bytes], resize to [coverThumbSize]×[coverThumbSize], encode JPEG.
/// Returns null if decoding fails.
Uint8List? resizeCoverToThumb(Uint8List bytes, {int size = coverThumbSize}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(
      decoded,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  } catch (_) {
    return null;
  }
}

/// True when [width] and [height] match the persistence policy.
bool isCoverThumbSize(int width, int height) =>
    width == coverThumbSize && height == coverThumbSize;

/// Prefer full-resolution cover when the audio file is on disk; else thumb.
///
/// When [audioIsLocal] is true but [fullCoverPath] is missing, returns null so
/// the caller can load original bytes from tags (Image.memory) instead of the
/// 100×100 thumb. When not local, returns [thumbPath] as the offline placeholder.
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
