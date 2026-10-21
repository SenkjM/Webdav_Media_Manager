import '../l10n/generated/app_localizations.dart';
import 'library_sentinels.dart';
import 'library_track.dart';

/// One flat “tag dimension” used to group library rows for folder pickers.
///
/// v1 ships [album] and [artist]. Future dimensions (genre, year, remote parent
/// path, composer / lyricist, album-artist) register the same way — do not add
/// a third picker shell.
class LibraryTagDimension {
  const LibraryTagDimension({
    required this.id,
    required this.groupKey,
    required this.displayName,
  });

  /// Stable kind id stored on [UserFolderItem.refKind] for tag-like refs.
  final String id;

  /// Grouping key for one track (storage / membership key).
  final String Function(LibraryTrack track) groupKey;

  /// Locale-aware label for a grouping key.
  final String Function(AppLocalizations l10n, String key) displayName;

  static final album = LibraryTagDimension(
    id: UserFolderRefKind.album,
    groupKey: (t) => t.displayAlbum,
    displayName: localizedLibraryGroupName,
  );

  static final artist = LibraryTagDimension(
    id: UserFolderRefKind.artist,
    groupKey: (t) => t.displayArtist,
    displayName: localizedLibraryGroupName,
  );

  /// Genres are grouped case-sensitively here so the stored ref key keeps the
  /// user's original spelling (the genre tab still merges case-insensitively).
  static final genre = LibraryTagDimension(
    id: UserFolderRefKind.genre,
    groupKey: (t) {
      final g = t.genre?.trim();
      return (g == null || g.isEmpty) ? kUncategorizedGenre : g;
    },
    displayName: localizedLibraryGroupName,
  );

  /// Tag-like dimensions available to folder “add …” pickers.
  static final List<LibraryTagDimension> v1TagDimensions = [
    album,
    artist,
    genre,
  ];

  static LibraryTagDimension? byId(String id) {
    for (final d in v1TagDimensions) {
      if (d.id == id) return d;
    }
    return null;
  }
}

/// Ref kinds stored in `user_folder_items.ref_kind`.
///
/// Tag-like kinds share [LibraryTagDimension]. [track] is per-row (`music_id`).
abstract final class UserFolderRefKind {
  static const album = 'album';
  static const artist = 'artist';
  static const genre = 'genre';
  static const track = 'track';
  /// Soft-ref kinds for manga library (99 §19); picker UX may come later.
  static const manga = 'manga';
  static const mangaSeries = 'mangaSeries';

  static const v1 = [album, artist, genre, track];
  static const mangaKinds = [manga, mangaSeries];

  static bool isKnown(String kind) =>
      v1.contains(kind) || mangaKinds.contains(kind);
}
