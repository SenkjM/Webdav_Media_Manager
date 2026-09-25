import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/services/accounts_service.dart';
import 'package:webdav_media_manager/services/backup_service.dart';
import 'package:webdav_media_manager/services/credential_vault_service.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/services/library_service.dart';
import 'package:webdav_media_manager/services/playlist_service.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';
import 'package:webdav_media_manager/utils/credential_vault_crypto.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';

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

/// In-memory stand-in for the accounts sqlite table.
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

/// Records bytes written / hands them back: the vault round-trip never
/// touches a real WebDAV server.
class _FakeWebDav extends WebDavService {
  final Map<String, Uint8List> files = {};

  @override
  bool hasAccount(String accountId) => true;

  @override
  Future<void> ensureDirectory(String accountId, String path) async {}

  @override
  Future<void> writeBytes(
    String accountId,
    String remotePath,
    Uint8List data,
  ) async {
    files[remotePath] = data;
  }

  @override
  Future<Uint8List> readAsBytes(String accountId, String remotePath) async {
    final f = files[remotePath];
    if (f == null) {
      throw Exception('404 not found: $remotePath');
    }
    return f;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorage secure;
  late _FakeLibraryDatabase db;
  late _FakeWebDav webDav;
  late AccountsService accounts;
  late SettingsService settings;
  late CredentialVaultService vault;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secure = _FakeSecureStorage();
    db = _FakeLibraryDatabase();
    webDav = _FakeWebDav();
    settings = SettingsService(secureStorage: secure);
    await settings.init();
    accounts = AccountsService(db: db, secureStorage: secure);
    await accounts.init();
    vault = CredentialVaultService(
      accounts: accounts,
      settings: settings,
      webDav: webDav,
    );
  });

  group('账号凭证库（credential vault v2）', () {
    test('WebDAV 条目保持 v1 语义：密码加密、地址用户名明文', () async {
      await accounts.addAccount(
        name: '家里NAS',
        url: 'https://nas.example.com',
        username: 'alice',
        password: 'hunter2',
      );

      final json = await vault.buildJson(
        passphrase: '统一口令',
        encryptPassword: true,
      );
      final entry = (json['accounts'] as List).first
          as Map<String, dynamic>;

      expect(entry['providerType'], isNull); // webdav 条目不写类型键
      expect(entry['password'], startsWith('AESGCMv1:'));
      expect(entry['url'], 'https://nas.example.com');
      expect(entry['username'], 'alice');

      // 圆回：同口令解出原密码
      final back = await vault.applyJson(json, passphrase: '统一口令');
      expect(back.passwordsRestored, 1);
      expect(await accounts.passwordFor(accounts.accounts.first.id), 'hunter2');
    });

    test('云盘条目：驱动配置进库，密文字段按 spec 加密，圆回还原', () async {
      final netease = await accounts.addAccount(
        name: '网易云',
        url: '',
        username: '',
        password: '',
        providerType: 'netease_music',
        remotePath: '/音乐',
      );
      await accounts.saveDriverConfig(netease.id, {
        'cookie': 'MUSIC_U=secret-cookie-value',
        'api_url_address': 'https://api.example.com',
        'local_refresh': false,
      });

      final json = await vault.buildJson(passphrase: '统一口令');
      final entry = (json['accounts'] as List)
          .whereType<Map<String, dynamic>>()
          .firstWhere((e) => e['providerType'] == 'netease_music');

      // 密文字段（spec.secretFieldKeys：obscure 表单项）被加密…
      expect(entry['driverConfig']['cookie'], startsWith('AESGCMv1:'));
      // …非密码字段保持明文…
      expect(entry['driverConfig']['api_url_address'], 'https://api.example.com');
      // …开关原样保留。
      expect(entry['driverConfig']['local_refresh'], false);
      expect(json['formatVersion'], 2);

      // 换一个全新环境圆回（账号行保留、仅凭证清空）：同 id 命中 → 更新；
      // 配置与 cookie 完整还原。
      secure.store.remove('cloud_driver_cfg_${netease.id}');
      final back = await vault.applyJson(json, passphrase: '统一口令');
      expect(back.imported, 0);
      expect(back.updated, 1);
      final restored = await accounts.loadDriverConfig(netease.id);
      expect(restored?['cookie'], 'MUSIC_U=secret-cookie-value');
      expect(restored?['api_url_address'], 'https://api.example.com');
    });

    test('密文加密开关关闭时驱动配置整体明文', () async {
      final netease = await accounts.addAccount(
        name: '网易云',
        url: '',
        username: '',
        password: '',
        providerType: 'netease_music',
      );
      await accounts.saveDriverConfig(netease.id, {'cookie': 'MUSIC_U=x'});
      settings.setSyncEncryptPassword(false);

      final json = await vault.buildJson(passphrase: '统一口令');
      final entry = (json['accounts'] as List).first as Map<String, dynamic>;
      expect(entry['driverConfig']['cookie'], 'MUSIC_U=x');
    });

    test('恢复时静默过滤未注册的网盘类型（不报错、不建账号）', () async {
      final json = {
        'format': CredentialVaultService.format,
        'formatVersion': 2,
        'accounts': [
          {
            'id': 'ghost-1',
            'name': '幽灵盘',
            'providerType': 'ghost_drive_2099',
            'url': '',
            'username': '',
            'password': '',
            'driverConfig': {'refresh_token': 't'},
          },
          {
            'id': 'wd-1',
            'name': 'NAS',
            'url': 'https://nas.example.com',
            'username': 'alice',
            'password': '',
          },
        ],
      };

      final result = await vault.applyJson(json, passphrase: '');
      expect(result.skippedUnknown, 1);
      expect(result.imported, 1); // 只有 NAS
      expect(accounts.accounts.map((a) => a.name), ['NAS']);
      expect(accounts.accounts.every((a) => a.providerType != 'ghost_drive_2099'),
          isTrue);
    });

    test('坏口令：WebDAV 密码留空并计入 missing，云盘密文字段留空', () async {
      await accounts.addAccount(
        name: 'NAS',
        url: 'https://nas.example.com',
        username: 'u',
        password: 'p',
      );
      final netease = await accounts.addAccount(
        name: '网易云',
        url: '',
        username: '',
        password: '',
        providerType: 'netease_music',
      );
      await accounts.saveDriverConfig(netease.id, {'cookie': 'MUSIC_U=c'});

      final json = await vault.buildJson(passphrase: '正确口令');

      // 全新环境（本地无任何账号与配置），用错误口令恢复。
      secure.store.clear();
      final freshDb = _FakeLibraryDatabase();
      final freshAccounts = AccountsService(db: freshDb, secureStorage: secure);
      await freshAccounts.init();
      final freshVault = CredentialVaultService(
        accounts: freshAccounts,
        settings: settings,
        webDav: webDav,
      );

      final result = await freshVault.applyJson(json, passphrase: '错误口令');
      // webdav 密码 + 云盘 cookie，两处密文都解不开。
      expect(result.passwordsMissing, 2);
      final cloudEntry =
          freshAccounts.accounts.firstWhere((a) => a.providerType == 'netease_music');
      // 云盘密文字段解不开 → 字段留空待补填（账号本身仍在）。
      final cfg = await freshAccounts.loadDriverConfig(cloudEntry.id);
      expect(cfg?['cookie'] ?? '', '');
    });
  });

  group('备份归档（backup payload v2）', () {
    test('云盘账号随档案走：驱动配置密文字段加密、明文字段保留', () async {
      final netease = await accounts.addAccount(
        name: '网易云',
        url: '',
        username: '',
        password: '',
        providerType: 'netease_music',
      );
      await accounts.saveDriverConfig(netease.id, {
        'cookie': 'MUSIC_U=token-1',
        'api_url_address': 'https://api.example.com',
      });
      await accounts.addAccount(
        name: 'NAS',
        url: 'https://nas.example.com',
        username: 'u',
        password: 'p',
      );

      final backup = BackupService(
        libraryDb: db,
        library: LibraryService(db: db),
        accounts: accounts,
        settings: settings,
        playlists: PlaylistService(webDav: webDav),
        webDav: webDav,
      );
      final payload = await backup.buildPayload(passphrase: '归档口令');
      final list = (payload['credentials']['accounts'] as List)
          .cast<Map<String, dynamic>>();

      final cloudRow = list.firstWhere((m) => m['provider_type'] == 'netease_music');
      expect(cloudRow['driverConfig']['cookie'], startsWith('AESGCMv1:'));
      expect(cloudRow['driverConfig']['api_url_address'], 'https://api.example.com');
      final webRow = list.firstWhere((m) => m['provider_type'] == 'webdav');
      expect(webRow['password'], startsWith('AESGCMv1:'));
    });

    test('restoreFromBackup 接受云盘行并写回驱动配置；未知类型静默跳过', () async {
      final cookie = await CredentialVaultCrypto.encrypt(
        plaintext: 'MUSIC_U=restored',
        passphrase: '归档口令',
      );
      final json = {
        'activeAccountId': 'wd-1',
        'accounts': [
          {
            'id': 'wd-1',
            'name': 'NAS',
            'url': 'https://nas.example.com',
            'username': 'u',
            'password': 'p',
            'providerType': 'webdav',
          },
          {
            'id': 'nt-1',
            'name': '网易云',
            'url': '',
            'username': '',
            'password': '',
            'providerType': 'netease_music',
            'remote_path': '/音乐',
            'driverConfig': {'cookie': cookie, 'api_url_address': 'https://x'},
          },
          {
            'id': 'gz-1',
            'name': '未来盘',
            'url': '',
            'username': '',
            'password': '',
            'providerType': 'ghost_drive_2099',
            'driverConfig': {'refresh_token': 't'},
          },
        ],
      };

      final missing = await accounts.restoreFromBackup(json, passphrase: '归档口令');
      expect(missing, isEmpty);
      expect(accounts.accounts.map((a) => a.name), containsAll(['NAS', '网易云']));
      expect(accounts.accounts.any((a) => a.providerType == 'ghost_drive_2099'),
          isFalse);

      final nt = accounts.accounts.firstWhere((a) => a.name == '网易云');
      expect(nt.remotePath, '/音乐');
      final cfg = await accounts.loadDriverConfig(nt.id);
      expect(cfg?['cookie'], 'MUSIC_U=restored');
      expect(cfg?['api_url_address'], 'https://x');
      expect(secure.store['webdav_pass_wd-1'], 'p');
    });

    test('归档容器往返：CREDENTIALS 段带上云盘条目', () async {
      final netease = await accounts.addAccount(
        name: '网易云',
        url: '',
        username: '',
        password: '',
        providerType: 'netease_music',
      );
      await accounts.saveDriverConfig(netease.id, {'cookie': 'MUSIC_U=c1'});
      await accounts.addAccount(
        name: 'NAS',
        url: 'https://nas.example.com',
        username: 'u',
        password: 'p',
      );

      final backup = BackupService(
        libraryDb: db,
        library: LibraryService(db: db),
        accounts: accounts,
        settings: settings,
        playlists: PlaylistService(webDav: webDav),
        webDav: webDav,
      );
      final bytes = await backup.buildArchiveBytes(passphrase: '');
      final container = WmpContainer.fromBytes(bytes);
      final section = container.readSection(WmpSections.credentials)!;
      final credentials = jsonDecode(utf8.decode(section)) as Map<String, dynamic>;
      final list = (credentials['accounts'] as List).cast<Map<String, dynamic>>();
      expect(
        list.where((m) => m['provider_type'] == 'netease_music'),
        hasLength(1),
      );
      // 明文口令为空：cookie 原样保留（无加密）。
      final cloud = list.firstWhere((m) => m['provider_type'] == 'netease_music');
      expect(cloud['driverConfig']['cookie'], 'MUSIC_U=c1');
      expect(netease.id, isNotEmpty);
    });
  });
}
