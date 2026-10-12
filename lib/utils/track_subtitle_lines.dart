import '../l10n/generated/app_localizations.dart';
import '../models/library_track.dart';

/// Shared subtitle layout for folder track rows and music-library title tiles.
///
/// - Line 1: album + disc + track number (one line)
/// - Line 2: prefer artist; else album artist; omit if neither
class TrackSubtitleLines {
  const TrackSubtitleLines({required this.line1, this.line2});

  final String line1;
  final String? line2;

  static TrackSubtitleLines of(LibraryTrack track, AppLocalizations l10n) {
    final parts = <String>[
      track.displayAlbumFor(l10n),
      if (track.discNumber != null) l10n.folderDiscNumber(track.discNumber!),
      track.trackNumber != null
          ? l10n.folderTrackNumber(track.trackNumber!)
          : l10n.folderTrackNumberUnknown,
    ];
    return TrackSubtitleLines(
      line1: parts.join(' · '),
      line2: _artistLine(track),
    );
  }

  /// Raw artist, else album artist; null when both empty (no "unknown" fallback).
  static String? _artistLine(LibraryTrack track) {
    final artist = track.artist?.trim();
    if (artist != null && artist.isNotEmpty) return artist;
    final albumArtist = track.albumArtist?.trim();
    if (albumArtist != null && albumArtist.isNotEmpty) return albumArtist;
    return null;
  }
}
