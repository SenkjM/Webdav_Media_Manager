import 'package:flutter/material.dart';

enum AppLocalePreference { system, zhCN, zhTW, en }

extension AppLocalePreferenceX on AppLocalePreference {
  String get storageKey => switch (this) {
    AppLocalePreference.system => 'system',
    AppLocalePreference.zhCN => 'zh-CN',
    AppLocalePreference.zhTW => 'zh-TW',
    AppLocalePreference.en => 'en',
  };

  Locale? get locale => switch (this) {
    AppLocalePreference.system => null,
    AppLocalePreference.zhCN => const Locale('zh', 'CN'),
    AppLocalePreference.zhTW => const Locale('zh', 'TW'),
    AppLocalePreference.en => const Locale('en'),
  };

  static AppLocalePreference fromStorageKey(String? value) => switch (value) {
    'zh-CN' => AppLocalePreference.zhCN,
    'zh-TW' => AppLocalePreference.zhTW,
    'en' => AppLocalePreference.en,
    _ => AppLocalePreference.system,
  };
}

/// Simplified Chinese, including system `zh_CN` / `zh_Hans` / bare `zh`,
/// stays `Locale('zh', 'CN')` so Android picks a sans CJK face.
/// Traditional (`zh_TW` or Hant) and English are unchanged.
/// `lookupAppLocalizations` already maps every non-TW `zh` onto simplified.
Locale resolveAppLocaleList(
  List<Locale>? locales,
  Iterable<Locale> supportedLocales,
) {
  for (final locale in locales ?? const <Locale>[]) {
    switch (locale.languageCode) {
      case 'en':
        return const Locale('en');
      case 'zh':
        final country = locale.countryCode?.toUpperCase();
        final script = locale.scriptCode?.toLowerCase();
        if (country == 'TW' || script == 'hant') {
          return const Locale('zh', 'TW');
        }
        return const Locale('zh', 'CN');
    }
  }
  return const Locale('zh', 'CN');
}
