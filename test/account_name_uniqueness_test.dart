import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/services/accounts_service.dart';
import 'package:webdav_media_manager/services/library_database.dart';

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

class _FakeLibraryDatabase extends LibraryDatabase {
  final List<WebDavAccount> rows = [];

  @override
  Future<List<WebDavAccount>> loadAccounts() async => List.of(rows);

  @override
  Future<void> upsertAccount(WebDavAccount account) async {
    rows.removeWhere((r) => r.id == account.id);
    rows.add(account);
  }

  @override
  Future<void> deleteAccount(String id) async {
    rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<LibraryTrack>> allTracks() async => const [];

  @override
  Future<List<Map<String, dynamic>>> allCueAlbums() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addAccount refuses duplicate names', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = _FakeLibraryDatabase();
    final accounts = AccountsService(
      db: db,
      prefs: prefs,
      secureStorage: _FakeSecureStorage(),
    );
    await accounts.init();

    await accounts.addAccount(
      name: '123crypt',
      url: 'https://a.example',
      username: 'u',
      password: 'p',
    );
    expect(
      () => accounts.addAccount(
        name: '123Crypt',
        url: 'https://b.example',
        username: 'u2',
        password: 'p2',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'err.accountNameTaken',
        ),
      ),
    );
    expect(accounts.accounts, hasLength(1));
  });

  test('init collapses preexisting same-name rows preferring active', () async {
    SharedPreferences.setMockInitialValues({
      'active_webdav_account_id': 'keep',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = _FakeLibraryDatabase()
      ..rows.addAll([
        const WebDavAccount(
          id: 'drop',
          name: '123crypt',
          url: 'https://old.example',
          username: 'u',
        ),
        const WebDavAccount(
          id: 'keep',
          name: '123crypt',
          url: 'https://new.example',
          username: 'u',
        ),
      ]);
    final accounts = AccountsService(
      db: db,
      prefs: prefs,
      secureStorage: _FakeSecureStorage(),
    );
    await accounts.init();
    expect(accounts.accounts, hasLength(1));
    expect(accounts.accounts.single.id, 'keep');
    expect(db.rows, hasLength(1));
  });
}
