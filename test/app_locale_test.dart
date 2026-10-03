import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/app_locale.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('locale preferences round-trip stable storage keys', () {
    for (final preference in AppLocalePreference.values) {
      expect(
        AppLocalePreferenceX.fromStorageKey(preference.storageKey),
        preference,
      );
    }
  });

  test('unknown locale preference follows system', () {
    expect(
      AppLocalePreferenceX.fromStorageKey('fr-FR'),
      AppLocalePreference.system,
    );
    expect(AppLocalePreference.system.locale, isNull);
    expect(AppLocalePreference.zhCN.locale?.languageCode, 'zh');
    expect(AppLocalePreference.zhCN.locale?.countryCode, 'CN');
    expect(AppLocalePreference.zhTW.locale?.countryCode, 'TW');
    expect(AppLocalePreference.en.locale?.languageCode, 'en');
  });

  testWidgets('MaterialApp refreshes localized text when locale changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs: prefs);
    await settings.setAppLocale(AppLocalePreference.zhCN);

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          locale: settings.appLocale.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(AppLocalizations.of(context)!.settings),
          ),
        ),
      ),
    );
    expect(find.text('设置'), findsOneWidget);

    await settings.setAppLocale(AppLocalePreference.en);
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
  });

  test('settings persist locale preference across reinitialization', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs: prefs);

    await settings.setAppLocale(AppLocalePreference.zhTW);

    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.appLocale, AppLocalePreference.zhTW);
    expect(prefs.getString('app_locale'), 'zh-TW');
  });

  test('simplified locales resolve to zh_CN, traditional and english stay', () {
    expect(
      resolveAppLocaleList(const [Locale('zh', 'CN')], const []),
      const Locale('zh', 'CN'),
    );
    expect(
      resolveAppLocaleList(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')], const []),
      const Locale('zh', 'CN'),
    );
    expect(
      resolveAppLocaleList(const [Locale('zh')], const []),
      const Locale('zh', 'CN'),
    );
    expect(
      resolveAppLocaleList(const [Locale('zh', 'TW')], const []),
      const Locale('zh', 'TW'),
    );
    expect(
      resolveAppLocaleList(
        const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')],
        const [],
      ),
      const Locale('zh', 'TW'),
    );
    expect(
      resolveAppLocaleList(const [Locale('en', 'US')], const []),
      const Locale('en'),
    );
  });
}
