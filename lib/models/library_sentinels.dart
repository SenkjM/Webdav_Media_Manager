import '../l10n/generated/app_localizations.dart';

/// Stable non-user-facing keys used for derived library group names.
const kUncategorizedGenre = '__wdmm_uncategorized__';

/// Empty artist/album group keys. A real tag whose text is the localized
/// word stays its own group; these keys are never written into tags.
const kUnknownArtist = '__wdmm_unknown_artist__';
const kUnknownAlbum = '__wdmm_unknown_album__';

bool isUncategorizedGenre(String value) => value == kUncategorizedGenre;

String localizedLibraryGroupName(AppLocalizations l10n, String key) {
  if (key == kUnknownArtist) return l10n.artistUnknown;
  if (key == kUnknownAlbum) return l10n.albumUnknown;
  if (isUncategorizedGenre(key)) return l10n.uncategorized;
  return key;
}
