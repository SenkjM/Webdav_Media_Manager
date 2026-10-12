import 'package:flutter/material.dart';

import '../models/library_track.dart';
import '../services/cache_service.dart';
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';

/// Optional custom cover for genre / artist / album / folder group items.
///
/// Return a **local filesystem path** for the cover image, or `null` to use
/// the default (album cover from [groupTracks] / placeholder). Assign
/// [LibraryGroupCoverOverrides.resolver] later to plug custom art without
/// redesigning list/grid cells.
typedef LibraryGroupCoverOverride = String? Function({
  required String dimensionId,
  required String groupKey,
});

/// Extension point for custom group covers (99 §18 folder polish).
abstract final class LibraryGroupCoverOverrides {
  /// Product hook — null means always fall back to album cover / placeholder.
  static LibraryGroupCoverOverride? resolver;
}

/// Resolve display art for a tag-like group (album / artist / genre / …).
///
/// Order: custom override path → [pickCoverTrack] local cache thumb → placeholder.
Widget buildLibraryGroupCover({
  required String dimensionId,
  required String groupKey,
  required List<LibraryTrack> groupTracks,
  required CacheService cache,
  required double size,
  double borderRadius = 6,
  IconData? placeholderIcon,
}) {
  final custom = LibraryGroupCoverOverrides.resolver?.call(
    dimensionId: dimensionId,
    groupKey: groupKey,
  );
  if (custom != null && custom.isNotEmpty) {
    return CoverArt(
      path: custom,
      size: size,
      borderRadius: borderRadius,
      icon: placeholderIcon,
    );
  }
  final coverTrack = pickCoverTrack(groupTracks, cache);
  if (coverTrack != null) {
    return LibraryCoverArt.forTrack(
      track: coverTrack,
      size: size,
      borderRadius: borderRadius,
      icon: placeholderIcon,
      enqueueIfMissing: false,
    );
  }
  return CoverArt(
    size: size,
    borderRadius: borderRadius,
    icon: placeholderIcon,
  );
}
