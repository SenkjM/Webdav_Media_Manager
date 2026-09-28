import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// Global access to the current [AppLocalizations] for code that runs below
/// the widget tree (services, audio handlers, background callbacks).
///
/// Configured once from `main()` with a resolver that re-reads the persisted
/// locale preference on every call, so a settings change applies immediately.
/// Unconfigured access (service unit tests) falls back to Simplified Chinese,
/// matching the generated lookup for `Locale('zh', 'CN')`.
class L10nHost {
  L10nHost._();

  static AppLocalizations Function()? _resolver;

  /// Wire the global resolver. Pass a closure that reads current settings,
  /// NOT a pre-resolved instance.
  static void configure(AppLocalizations Function() resolver) {
    _resolver = resolver;
  }

  /// The active localization bundle. Falls back to zh_CN when unconfigured.
  static AppLocalizations get current {
    final resolver = _resolver;
    if (resolver != null) return resolver();
    return lookupAppLocalizations(const Locale('zh', 'CN'));
  }
}
