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
    AppLocalePreference.zhCN => const Locale('zh'),
    AppLocalePreference.zhTW => const Locale('zh', 'TW'),
    AppLocalePreference.en => const Locale('en'),
  };

  /// Endonym shown in the language menu. Null for "follow system", which is
  /// translated. Language names stay in their own script so a user can find
  /// theirs without reading the current UI language.
  String? get nativeName => switch (this) {
    AppLocalePreference.system => null,
    AppLocalePreference.zhCN => '简体中文',
    AppLocalePreference.zhTW => '繁體中文',
    AppLocalePreference.en => 'English',
  };

  static AppLocalePreference fromStorageKey(String? value) => switch (value) {
    'zh-CN' => AppLocalePreference.zhCN,
    'zh-TW' => AppLocalePreference.zhTW,
    'en' => AppLocalePreference.en,
    _ => AppLocalePreference.system,
  };
}
