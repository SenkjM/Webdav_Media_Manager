import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/services/accounts_service.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

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
  bool uniqueApplied = false;
  bool _pending = false;

  @override
  bool get accountNameUniquePending => _pending;

  @override
  set accountNameUniquePending(bool value) => _pending = value;

  @override
  Future<List<WebDavAccount>> loadAccounts() async => List.of(rows);

  @override
  Future<void> upsertAccount(WebDavAccount account) async {
    final key = accountNameKey(account.name);
    if (uniqueApplied) {
      final clash = rows.any(
        (r) => r.id != account.id && accountNameKey(r.name) == key,
      );
      if (clash) {
        throw StateError('UNIQUE constraint failed: accounts.name_key');
      }
    }
    rows.removeWhere((r) => r.id == account.id);
    rows.add(account);
  }

  @override
  Future<void> deleteAccount(String id) async {
    rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<String>> duplicateAccountNameKeys() async {
    final counts = <String, int>{};
    for (final a in rows) {
      final k = accountNameKey(a.name);
      if (k.isEmpty) continue;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return [for (final e in counts.entries) if (e.value > 1) e.key];
  }

  @override
  Future<bool> applyAccountNameUnique() async {
    final dups = await duplicateAccountNameKeys();
    if (dups.isNotEmpty) {
      accountNameUniquePending = true;
      return false;
    }
    uniqueApplied = true;
    accountNameUniquePending = false;
    return true;
  }

  @override
  Future<List<String>> collapseDuplicateAccountNames({
    String? preferAccountId,
  }) async {
    final byKey = <String, List<WebDavAccount>>{};
    for (final a in rows) {
      byKey.putIfAbsent(accountNameKey(a.name), () => []).add(a);
    }
    final deleted = <String>[];
    for (final group in byKey.values) {
      if (group.length < 2) continue;
      group.sort((a, b) => a.id.compareTo(b.id));
      var keep = group.first;
      if (preferAccountId != null) {
        for (final a in group) {
          if (a.id == preferAccountId) {
            keep = a;
            break;
          }
        }
      }
      for (final a in group) {
        if (a.id == keep.id) continue;
        rows.removeWhere((r) => r.id == a.id);
        deleted.add(a.id);
      }
    }
    accountNameUniquePending = false;
    return deleted;
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
    final db = _FakeLibraryDatabase()..uniqueApplied = true;
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
      throwsA(isA<StateError>()),
    );
  });

  test('init collapses duplicate names preferring active id', () async {
    SharedPreferences.setMockInitialValues({
      'active_webdav_account_id': 'keep',
    });
    final prefs = await SharedPreferences.getInstance();
    final secure = _FakeSecureStorage()
      ..store['webdav_pass_drop'] = 'old'
      ..store['webdav_pass_keep'] = 'new';
    final db = _FakeLibraryDatabase()
      ..accountNameUniquePending = true
      ..rows.addAll([
        const WebDavAccount(
          id: 'drop',
          name: '123crypt',
          url: 'https://old.example',
          username: 'u',
        ),
        const WebDavAccount(
          id: 'keep',
          name: '123Crypt',
          url: 'https://new.example',
          username: 'u',
        ),
      ]);
    final accounts = AccountsService(
      db: db,
      prefs: prefs,
      secureStorage: secure,
    );
    await accounts.init();
    expect(accounts.accounts, hasLength(1));
    expect(accounts.accounts.single.id, 'keep');
    expect(accounts.needsNameCleanup, isFalse);
    expect(db.uniqueApplied, isTrue);
    expect(secure.store.containsKey('webdav_pass_drop'), isFalse);
    expect(secure.store['webdav_pass_keep'], 'new');
  });
}
