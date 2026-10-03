import 'package:flutter/material.dart';

/// Light / dark / follow system. Missing or unknown storage stays light so
/// existing installs keep the previous hardcoded [ThemeMode.light].
enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  String get storageKey => switch (this) {
    AppThemeMode.system => 'system',
    AppThemeMode.light => 'light',
    AppThemeMode.dark => 'dark',
  };

  ThemeMode get themeMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  static AppThemeMode fromStorageKey(String? value) => switch (value) {
    'system' => AppThemeMode.system,
    'dark' => AppThemeMode.dark,
    _ => AppThemeMode.light,
  };
}
