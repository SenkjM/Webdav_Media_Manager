import '../l10n/generated/app_localizations.dart';

/// Stable non-user-facing key for the account created from legacy settings.
const kDefaultServerName = '__wdmm_default_server__';

bool isDefaultServerName(String value) => value == kDefaultServerName;

String localizedAccountName(AppLocalizations l10n, String name) {
  return isDefaultServerName(name) ? l10n.defaultServer : name;
}
