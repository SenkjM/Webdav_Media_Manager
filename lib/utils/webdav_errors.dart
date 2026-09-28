import '../l10n/generated/app_localizations.dart';

/// Detect permission / auth failures from WebDAV / Dio errors.
bool isWebDavPermissionError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('401') || s.contains('403')) return true;
  if (s.contains('unauthorized') || s.contains('forbidden')) return true;
  if (s.contains('permission denied') || s.contains('insufficient')) {
    return true;
  }
  if (s.contains('access denied') || s.contains('not allowed')) return true;
  return false;
}

String webDavErrorMessage(Object error, AppLocalizations l10n) {
  if (isWebDavPermissionError(error)) {
    return l10n.webdavErrorPermDetail;
  }
  return error.toString();
}
