import 'package:flutter/material.dart';

/// Light / dark / follow system. Missing storage defaults to follow system;
/// an explicit stored choice is always honored as-is.
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
    'light' => AppThemeMode.light,
    'dark' => AppThemeMode.dark,
    // Missing or unknown storage follows the system by default.
    _ => AppThemeMode.system,
  };
}
