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
