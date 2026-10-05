import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('home_tab_index persists across SettingsService reloads', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();
    expect(fresh.homeTab, 0);

    await fresh.setHomeTab(2);
    expect(fresh.homeTab, 2);
    expect(prefs.getInt('home_tab_index'), 2);

    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.homeTab, 2);
  });

  test('network_last_path stays in memory and is not persisted', () async {
    SharedPreferences.setMockInitialValues({
      'network_last_path': '/old/deep',
      'network_remember_last_path': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();

    // Stale prefs key scrubbed; cold start always begins at root.
    expect(fresh.networkLastPath, '/');
    expect(prefs.containsKey('network_last_path'), isFalse);
    expect(fresh.networkRememberLastPath, isTrue);

    await fresh.setNetworkLastPath('/music/album');
    expect(fresh.networkLastPath, '/music/album');
    expect(prefs.containsKey('network_last_path'), isFalse);

    final again = SettingsService(prefs: prefs);
    await again.init();
    expect(again.networkLastPath, '/');
    expect(again.exportForBackup().containsKey('network_last_path'), isFalse);

    await again.importFromBackup({
      'network_last_path': '/from/backup',
      'network_remember_last_path': false,
    });
    expect(again.networkLastPath, '/');
    expect(again.networkRememberLastPath, isFalse);
  });
}
