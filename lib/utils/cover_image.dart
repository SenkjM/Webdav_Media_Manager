import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Default square edge for new cover thumbs (overridable via Settings).
const int coverThumbSize = 300;

/// Alternate preset offered in Settings.
const int coverThumbSizeLarge = 600;

/// Presets offered as the pill (SegmentedButton) in Settings.
///
/// The default [coverThumbSize] must be a member; labels are generated from
/// these values so they can never drift apart again.
const List<int> coverThumbPresets = [coverThumbSize, coverThumbSizeLarge];

/// Settings pill key for [edge] (`'300'`, `'600'`) or `'custom'`.
String coverThumbPresetKey(int edge) =>
    coverThumbPresets.contains(edge) ? '$edge' : 'custom';

/// Pass this as [size] to [resizeCoverToThumb] to skip resizing and store original bytes.
const int mangaCoverThumbSizeKeepOriginal = 0;

/// Clamp user-chosen square edge length for thumbs.
const int minCoverThumbSize = 32;
const int maxCoverThumbSize = 1024;

int clampCoverThumbSize(int size) {
  if (size < minCoverThumbSize) return minCoverThumbSize;
  if (size > maxCoverThumbSize) return maxCoverThumbSize;
  return size;
}

/// Decode [bytes], resize + center-crop to square [size]×[size], encode JPEG.
///
/// Uses [img.copyResizeCropSquare] so the image is scaled uniformly to the
/// shorter side first, then center-cropped — never stretched.
/// Returns null if decoding fails.
Uint8List? resizeCoverToThumb(Uint8List bytes, {int size = coverThumbSize}) {
  final edge = clampCoverThumbSize(size);
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final square = img.copyResizeCropSquare(
      decoded,
      size: edge,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(square, quality: 85));
  } catch (_) {
    return null;
  }
}

/// True when [width] and [height] match [expected] (default policy size).
bool isCoverThumbSize(int width, int height, {int expected = coverThumbSize}) =>
    width == expected && height == expected;

