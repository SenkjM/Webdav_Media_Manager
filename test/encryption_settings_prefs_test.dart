import 'package:flutter_test/flutter_test.dart';
import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    preferDartSecretbox();
  });

  test('prefer libsodium defaults from dart-define and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();

    expect(
      fresh.preferLibsodiumSecretboxEnabled,
      SettingsService.defaultPreferLibsodiumSecretbox,
    );
    // Without a successful load, backend stays Dart even if preference is on.
    expect(secretboxBackend, SecretboxBackend.dart);

    await fresh.setPreferLibsodiumSecretboxEnabled(true);
    expect(fresh.preferLibsodiumSecretboxEnabled, isTrue);
    expect(prefs.getBool('prefer_libsodium_secretbox'), isTrue);
    // Prefer API selects libsodium only when the library actually loads.
    if (fresh.libsodiumSecretboxAvailable) {
      expect(secretboxBackend, SecretboxBackend.libsodium);
    } else {
      expect(secretboxBackend, SecretboxBackend.dart);
    }

    await fresh.setPreferLibsodiumSecretboxEnabled(false);
    expect(secretboxBackend, SecretboxBackend.dart);

    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.preferLibsodiumSecretboxEnabled, isFalse);
    expect(secretboxBackend, SecretboxBackend.dart);
  });

  test('crypt sequential download still persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();
    expect(fresh.cryptSequentialDownloadEnabled, isFalse);

    await fresh.setCryptSequentialDownloadEnabled(true);
    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.cryptSequentialDownloadEnabled, isTrue);
    expect(prefs.getBool('crypt_sequential_download'), isTrue);
  });
}
