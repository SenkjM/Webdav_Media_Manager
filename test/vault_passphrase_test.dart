import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/services/settings_service.dart';

/// In-memory stand-in for the platform keystore.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage();

  final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vault key round-trips through secure storage', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = _FakeSecureStorage();
    final settings = SettingsService(secureStorage: secure);
    await settings.init();

    expect(settings.vaultPassphrase, isEmpty);
    expect(settings.hasVaultPassphrase, isFalse);

    await settings.setVaultPassphrase('my-own-key');
    expect(settings.vaultPassphrase, 'my-own-key');
    expect(settings.hasVaultPassphrase, isTrue);
    // Stored where account passwords live, not in SharedPreferences.
    expect(secure.store.values, contains('my-own-key'));

    // A new instance (fresh launch) reads the same key back.
    final reloaded = SettingsService(secureStorage: secure);
    await reloaded.init();
    expect(reloaded.vaultPassphrase, 'my-own-key');

    await reloaded.setVaultPassphrase('');
    expect(secure.store, isEmpty);
  });

  test('the vault key is never exported with a backup', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(secureStorage: _FakeSecureStorage());
    await settings.init();
    await settings.setVaultPassphrase('secret-key');

    final json = settings.exportForBackup();
    // Exporting the key next to the ciphertext would defeat the encryption.
    expect(json.values.join('|'), isNot(contains('secret-key')));
    expect(json.containsKey('vault_passphrase'), isFalse);
    expect(json.containsKey('sync_vault_passphrase'), isFalse);
  });
}
