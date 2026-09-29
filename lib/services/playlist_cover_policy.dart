import 'dart:io';
import 'dart:typed_data';

import '../models/playlist.dart';
import '../utils/cover_image.dart';
import '../utils/track_identity.dart';
import 'cover_service.dart';

/// Cover source tier for playlist documents.
enum PlaylistCoverTier {
  /// Downscaled thumbnail from `covers/` — same tier the library shards carry.
  thumb,

  /// Original bytes from `covers_full/`, no resize.
  full,
}

/// Playlist-side cover policy (docs/10 §4.2, COVERS section).
///
/// **Deliberately separate from [CoverService.thumbSize]** even though the
/// default value is routed from it: playlists may later want a different edge
/// length than the library (a playlist strip is not an album grid), and that
/// decision must not require touching the library path. Today the override is
/// not exposed in Settings — it exists so the change is a value edit, not a
/// refactor. `edgeSize == null` means "follow the library setting".
class PlaylistCoverPolicy {
  PlaylistCoverPolicy({CoverService? covers}) : _covers = covers;

  final CoverService? _covers;

  /// Explicit override; null = route to [CoverService.thumbSize].
  int? edgeSize;

  /// Which on-disk tier to read.
  PlaylistCoverTier tier = PlaylistCoverTier.thumb;

  /// When false, playlist documents are written without a COVERS section —
  /// the escape hatch if a server or quota makes embedded art a bad idea.
  bool embedCovers = true;

  /// Effective edge length in pixels.
  int effectiveEdgeSize(int fallback) => edgeSize ?? _covers?.thumbSize ?? fallback;

  /// Read the cover bytes for one playlist entry, or null when there is none.
  ///
  /// Missing / unreadable covers are **not** an error: the entry is still
  /// written, just without a `coverIndex`. A playlist that cannot embed one
  /// album's art must not fail to sync.
  Future<Uint8List?> readFor(
    PlaylistEntry entry, {
    required int fallbackEdgeSize,
  }) async {
    if (!embedCovers) return null;
    if (tier == PlaylistCoverTier.full) {
      return _readFull(entry);
    }
    return _readThumb(entry, fallbackEdgeSize);
  }

  Future<Uint8List?> _readThumb(PlaylistEntry entry, int fallbackEdgeSize) async {
    final covers = _covers;
    if (covers == null) return null;
    // CUE slices share the backing audio's art; ask the audio path so both
    // halves of one album resolve to the same file.
    final remotePath =
        parseCueVirtualRemotePath(entry.remotePath)?.audioRemotePath ??
        entry.remotePath;
    try {
      final file = await covers.coverFile(entry.sourceName, remotePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      // Stored thumbs are already at the library edge length. Only re-encode
      // when this policy asks for a different one, so the common path is a
      // plain file read with no decode cost.
      final edge = effectiveEdgeSize(fallbackEdgeSize);
      final libraryEdge = covers.thumbSize;
      if (edge == libraryEdge) return bytes;
      return resizeToEdge(bytes, edge) ?? bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readFull(PlaylistEntry entry) async {
    final covers = _covers;
    if (covers == null) return null;
    final remotePath =
        parseCueVirtualRemotePath(entry.remotePath)?.audioRemotePath ??
        entry.remotePath;
    try {
      final path = await covers.fullCoverPath(entry.sourceName, remotePath);
      if (path == null) return null;
      final bytes = await File(path).readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }
}

/// Resize [bytes] to a square [edge]-px JPEG, or null when the bytes cannot be
/// decoded.
///
/// Shares the library helper: a playlist cover is the same kind of object as a
/// library thumb, so there is no reason to carry a second image pipeline.
Uint8List? resizeToEdge(Uint8List bytes, int edge) =>
    resizeCoverToThumb(bytes, size: edge);

/// Convenience: read covers for a whole playlist, parallel to its entries.
///
/// Entry `i` gets `list[i]`; nulls are preserved so the codec's index mapping
/// stays aligned with `playlist.entries`.
Future<List<Uint8List?>> readCoversForPlaylist(
  Playlist playlist, {
  required PlaylistCoverPolicy policy,
  required int fallbackEdgeSize,
}) async {
  final out = <Uint8List?>[];
  for (final entry in playlist.entries) {
    out.add(
      await policy.readFor(entry, fallbackEdgeSize: fallbackEdgeSize),
    );
  }
  return out;
}
