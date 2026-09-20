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
