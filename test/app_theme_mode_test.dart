import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/app_theme_mode.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme mode storage keys round-trip and unknown stays light', () {
    for (final mode in AppThemeMode.values) {
      expect(AppThemeModeX.fromStorageKey(mode.storageKey), mode);
    }
    expect(AppThemeModeX.fromStorageKey(null), AppThemeMode.light);
    expect(AppThemeModeX.fromStorageKey('nope'), AppThemeMode.light);
    expect(AppThemeMode.light.themeMode, ThemeMode.light);
    expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
    expect(AppThemeMode.system.themeMode, ThemeMode.system);
  });

  test('settings persist theme mode and default to light', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();
    expect(fresh.appThemeMode, AppThemeMode.light);
    expect(fresh.themeMode, ThemeMode.light);

    await fresh.setAppThemeMode(AppThemeMode.dark);
    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.appThemeMode, AppThemeMode.dark);
    expect(prefs.getString('theme_mode'), 'dark');

    await restored.setAppThemeMode(AppThemeMode.system);
    final again = SettingsService(prefs: prefs);
    await again.init();
    expect(again.themeMode, ThemeMode.system);
  });

  test('light and dark themes are generated from the default seed', () {
    final light = AppTheme.light;
    final dark = AppTheme.dark;
    final expectedLight = ColorScheme.fromSeed(
      seedColor: AppTheme.defaultSeed,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final expectedDark = ColorScheme.fromSeed(
      seedColor: AppTheme.defaultSeed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    expect(AppTheme.defaultSeed, const Color(0xFF2EC4B6));
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.visualDensity, VisualDensity.compact);
    expect(dark.visualDensity, VisualDensity.compact);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, expectedLight.primary);
    expect(light.colorScheme.onPrimary, expectedLight.onPrimary);
    expect(dark.colorScheme.primary, expectedDark.primary);
    expect(dark.colorScheme.onPrimary, expectedDark.onPrimary);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    expect(
      (light.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(10),
    );
  });

  testWidgets('MaterialApp reads the saved theme mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs: prefs);
    await settings.setAppThemeMode(AppThemeMode.dark);

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          themeMode: settings.themeMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: const SizedBox.shrink(),
        ),
      ),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await settings.setAppThemeMode(AppThemeMode.light);
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });
}
