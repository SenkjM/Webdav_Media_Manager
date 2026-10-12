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

  /// Tag-like dimensions available to folder “add …” pickers in v1.
  static final List<LibraryTagDimension> v1TagDimensions = [album, artist];

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
  static const track = 'track';

  static const v1 = [album, artist, track];

  static bool isKnown(String kind) => v1.contains(kind);
}
