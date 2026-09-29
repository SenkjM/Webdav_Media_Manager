import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/services/accounts_service.dart';
import 'package:webdav_media_manager/services/backup_service.dart';
import 'package:webdav_media_manager/services/credential_vault_codec.dart';
import 'package:webdav_media_manager/services/credential_vault_service.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/services/library_service.dart';
import 'package:webdav_media_manager/services/playlist_codec.dart';
import 'package:webdav_media_manager/services/playlist_service.dart';
import 'package:webdav_media_manager/services/playlist_store.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';
import 'package:webdav_media_manager/utils/backup_crypto.dart';
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

/// In-memory stand-in for the playlist sqlite table (these tests only need the
/// in-memory list the service keeps).
class _MemoryPlaylistStore implements PlaylistStore {
  final Map<String, Playlist> rows = {};

  @override
  Future<Database> get database async => throw UnimplementedError();

  @override
  Future<List<Playlist>> loadAll() async => rows.values.toList();

  @override
  Future<Playlist?> getById(String id) async => rows[id];

  @override
  Future<void> upsert(Playlist playlist) async => rows[playlist.id] = playlist;

  @override
  Future<void> delete(String id) async => rows.remove(id);

  @override
  Future<void> clearAll() async => rows.clear();

  @override
  Future<void> replaceAll(List<Playlist> playlists) async {
    rows
      ..clear()
      ..addEntries(playlists.map((p) => MapEntry(p.id, p)));
  }

  @override
  Future<String> databasePath() async => 'memory:playlists.db';

  @override
  Future<void> close() async {}
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

  /// Round-trip local accounts through the binary `WDMMCV01` document:
  /// build records → encode → decode → apply. This is the whole point of the
  /// container format, so every round-trip test goes through it rather than
  /// poking at [CredentialVaultCodec] directly.
  Future<Uint8List> encodeLocal({required String passphrase}) async {
    final records = await vault.buildRecords(passphrase: passphrase);
    return CredentialVaultCodec.encode(
      records,
      formatVersion: CredentialVaultService.formatVersion,
    );
  }

  Future<VaultApplyResult> applyTo(
    CredentialVaultService target,
    Uint8List bytes, {
    required String passphrase,
  }) {
    return target.applyVault(
      CredentialVaultCodec.decode(bytes),
      passphrase: passphrase,
    );
  }

  group('账号凭证库（credential vault 二进制容器）', () {
    test('WebDAV 条目：密码加密、地址用户名明文，圆回还原', () async {
      await accounts.addAccount(
        name: '家里NAS',
        url: 'https://nas.example.com',
        username: 'alice',
        password: 'hunter2',
      );

      final bytes = await encodeLocal(passphrase: '统一口令');

      // 魔数：这是本应用写出的 CV 文档，布局版本 01。
      expect(WmpContainer.kindOf(bytes), WmpFileKind.vault);
      expect(
        utf8.decode(bytes.sublist(0, 8)),
        'WDMM${WmpFileKind.vault}${WmpContainer.layoutVersion}',
      );

      final doc = CredentialVaultCodec.decode(bytes);
      expect(doc.formatVersion, CredentialVaultService.formatVersion);
      final entry = doc.entries.single;
      expect(entry.providerType, 'webdav');
      expect(entry.isCloud, isFalse);
      expect(entry.password, startsWith('AESGCMv1:'));
      expect(entry.passwordEncrypted, isTrue);
      // 地址类字段保持明文，无口令也能辨识账号。
      expect(entry.url, 'https://nas.example.com');
      expect(entry.username, 'alice');

      // 圆回：同口令解出原密码
      final back = await applyTo(vault, bytes, passphrase: '统一口令');
      expect(back.passwordsRestored, 1);
      expect(back.passwordsMissing, 0);
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

      final bytes = await encodeLocal(passphrase: '统一口令');
      final entry = CredentialVaultCodec.decode(
        bytes,
      ).entries.firstWhere((e) => e.providerType == 'netease_music');

      expect(entry.isCloud, isTrue);
      expect(entry.remotePath, '/音乐');
      // 密文字段（spec.secretFieldKeys：obscure 表单项）被加密…
      expect(entry.driverConfig!['cookie'], startsWith('AESGCMv1:'));
      // …非密码字段保持明文…
      expect(
        entry.driverConfig!['api_url_address'],
        'https://api.example.com',
      );
      // …开关原样保留。
      expect(entry.driverConfig!['local_refresh'], false);

      // 换一个全新环境圆回（账号行保留、仅凭证清空）：同 id 命中 → 更新；
      // 配置与 cookie 完整还原。
      secure.store.remove('cloud_driver_cfg_${netease.id}');
      final back = await applyTo(vault, bytes, passphrase: '统一口令');
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

      final bytes = await encodeLocal(passphrase: '统一口令');
      final entry = CredentialVaultCodec.decode(bytes).entries.single;
      expect(entry.driverConfig!['cookie'], 'MUSIC_U=x');
    });

    test('恢复时静默过滤未注册的网盘类型（不报错、不建账号）', () async {
      final bytes = CredentialVaultCodec.encode(
        const [
          VaultRecord(
            id: 'ghost-1',
            name: '幽灵盘',
            providerType: 'ghost_drive_2099',
            url: '',
            username: '',
            password: '',
            passwordEncrypted: false,
            remotePath: '/',
            driverConfig: {'refresh_token': 't'},
          ),
          VaultRecord(
            id: 'wd-1',
            name: 'NAS',
            providerType: 'webdav',
            url: 'https://nas.example.com',
            username: 'alice',
            password: '',
            passwordEncrypted: false,
            remotePath: '/',
          ),
        ],
        formatVersion: CredentialVaultService.formatVersion,
      );

      final result = await applyTo(vault, bytes, passphrase: '');
      expect(result.skippedUnknown, 1);
      expect(result.imported, 1); // 只有 NAS
      expect(accounts.accounts.map((a) => a.name), ['NAS']);
      expect(
        accounts.accounts.every((a) => a.providerType != 'ghost_drive_2099'),
        isTrue,
      );
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

      final bytes = await encodeLocal(passphrase: '正确口令');

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

      final result = await applyTo(freshVault, bytes, passphrase: '错误口令');
      // webdav 密码 + 云盘 cookie，两处密文都解不开。
      expect(result.passwordsMissing, 2);
      expect(freshVault.missingPasswordAccounts, hasLength(2));
      final cloudEntry = freshAccounts.accounts.firstWhere(
        (a) => a.providerType == 'netease_music',
      );
      // 云盘密文字段解不开 → 字段留空待补填（账号本身仍在）。
      final cfg = await freshAccounts.loadDriverConfig(cloudEntry.id);
      expect(cfg?['cookie'] ?? '', '');
    });

    test('无口令时密码明文入库（与旧 JSON 语义一致）', () async {
      await accounts.addAccount(
        name: 'NAS',
        url: 'https://nas.example.com',
        username: 'u',
        password: 'plain-pw',
      );

      final bytes = await encodeLocal(passphrase: '');
      final entry = CredentialVaultCodec.decode(bytes).entries.single;
      expect(entry.password, 'plain-pw');
      expect(entry.passwordEncrypted, isFalse);

      final back = await applyTo(vault, bytes, passphrase: '');
      expect(back.passwordsRestored, 1);
      expect(back.passwordsMissing, 0);
    });

    test('decode 拒绝 magic 与 META.kind 不一致的文档', () {
      // 伪造一份 CV 魔数、却把 META.kind 写成 playlist 的文档。
      final meta = encodeRecords([
        {WmpMeta.kind: WmpKind.playlist, WmpMeta.count: 0},
      ]);
      final bogus = WmpContainer.encode(
        {WmpSections.meta: meta},
        kind: WmpFileKind.vault,
      );

      expect(
        () => CredentialVaultCodec.decode(bogus),
        throwsA(
          isA<WmpFormatException>().having(
            (e) => e.message,
            'message',
            contains('err.vaultKindMismatch'),
          ),
        ),
      );
    });

    test('push/fetchVault 走 .wdmcv 二进制文件', () async {
      await accounts.addAccount(
        name: 'NAS',
        url: 'https://nas.example.com',
        username: 'u',
        password: 'p',
      );

      await vault.push(accountId: 'dest', passphrase: '统一口令');
      expect(vault.remotePath, endsWith(CredentialVaultService.fileName));
      expect(vault.remotePath, endsWith('.wdmcv'));

      final stored = webDav.files[vault.remotePath];
      expect(stored, isNotNull);
      expect(WmpContainer.kindOf(stored!), WmpFileKind.vault);

      final fetched = await vault.fetchVault(accountId: 'dest');
      expect(fetched, isNotNull);
      expect(fetched!.entryCount, 1);
      expect(fetched.formatVersion, CredentialVaultService.formatVersion);
    });

    test('fetchVault 对不存在的文件返回 null（而不是抛错）', () async {
      expect(await vault.fetchVault(accountId: 'dest'), isNull);
    });
  });

  group('备份归档（内嵌 CV / PL 容器）', () {
    late PlaylistService playlists;
    late BackupService backup;

    setUp(() {
      playlists = PlaylistService(store: _MemoryPlaylistStore(), webDav: webDav);
      backup = BackupService(
        libraryDb: db,
        library: LibraryService(db: db),
        accounts: accounts,
        settings: settings,
        playlists: playlists,
        credentials: vault,
        webDav: webDav,
      );
    });

    test('CREDENTIALS 段内嵌完整 CV 文档，与同步出口是同一种编码', () async {
      await accounts.addAccount(
        name: 'NAS',
        url: 'https://nas.example.com',
        username: 'alice',
        password: 'hunter2',
      );
      final netease = await accounts.addAccount(
        name: '网易云',
        url: '',
        username: '',
        password: '',
        providerType: 'netease_music',
        remotePath: '/音乐',
      );
      await accounts.saveDriverConfig(netease.id, {
        'cookie': 'MUSIC_U=secret',
        'api_url_address': 'https://api.example.com',
      });

      final archive = await backup.buildArchiveBytes(passphrase: '归档口令');
      // 非空口令会套一层 EN 信封（BackupCrypto）；解开才是 BK 容器。
      expect(BackupCrypto.looksEncrypted(archive), isTrue);
      final container = WmpContainer.fromBytes(
        await BackupCrypto.decrypt(data: archive, passphrase: '归档口令'),
      );
      expect(container.kind, WmpFileKind.backup);

      final section = container.readSection(WmpSections.credentials)!;
      // 段里就是一份完整的 CV 文档，不是 JSON。
      expect(WmpContainer.looksLikeContainer(section), isTrue);
      expect(WmpContainer.kindOf(section), WmpFileKind.vault);
      expect(utf8.decode(section.sublist(0, 8)), 'WDMMCV01');

      final embedded = CredentialVaultCodec.decode(section);
      expect(embedded.entryCount, 2);
      expect(embedded.formatVersion, CredentialVaultService.formatVersion);
      final cloud = embedded.entries.firstWhere(
        (e) => e.providerType == 'netease_music',
      );
      expect(cloud.remotePath, '/音乐');
      expect(cloud.driverConfig!['cookie'], startsWith('AESGCMv1:'));
      expect(cloud.driverConfig!['api_url_address'], 'https://api.example.com');
      final web = embedded.entries.firstWhere((e) => e.providerType == 'webdav');
      expect(web.password, startsWith('AESGCMv1:'));
      expect(web.url, 'https://nas.example.com');

      // 同步出口写出去的也是同一份文档：同样的条目、同样的编码。
      // 密文本身每次都不同（AES-GCM 每次新盐新随机数），所以比的是解出来的明文。
      await vault.push(accountId: 'dest', passphrase: '归档口令');
      final remoteBytes = webDav.files[vault.remotePath]!;
      expect(WmpContainer.kindOf(remoteBytes), WmpFileKind.vault);
      final remoteDoc = CredentialVaultCodec.decode(remoteBytes);
      expect(remoteDoc.entryCount, embedded.entryCount);

      Future<String> plain(VaultRecord e) async {
        final pwd = e.passwordEncrypted
            ? await CredentialVaultCrypto.tryDecrypt(
                encoded: e.password,
                passphrase: '归档口令',
              )
            : e.password;
        final cookie = e.driverConfig?['cookie'];
        final secret = cookie is String
            ? await CredentialVaultCrypto.tryDecrypt(
                encoded: cookie,
                passphrase: '归档口令',
              )
            : null;
        return '${e.id}|${e.name}|${e.providerType}|${e.url}|${e.username}|'
            '${e.remotePath}|$pwd|encrypted=${e.passwordEncrypted}|'
            '${e.driverConfig?['api_url_address']}|$secret';
      }

      expect(
        [for (final e in embedded.entries) await plain(e)],
        [for (final e in remoteDoc.entries) await plain(e)],
      );
      // 而且两个出口都是真密文：密文格式在，且解出来就是原始明文（密钥一致）。
      final webEntry = embedded.entries.firstWhere(
        (e) => e.providerType == 'webdav',
      );
      expect(webEntry.passwordEncrypted, isTrue);
      expect(CredentialVaultCrypto.isEncrypted(webEntry.password), isTrue);
      final cloudEntry = embedded.entries.firstWhere(
        (e) => e.providerType == 'netease_music',
      );
      expect(
        CredentialVaultCrypto.isEncrypted(
          cloudEntry.driverConfig!['cookie']! as String,
        ),
        isTrue,
      );
      final plains = [for (final e in embedded.entries) await plain(e)].join('\n');
      expect(plains, contains('hunter2'));
      expect(plains, contains('MUSIC_U=secret'));

      // 恢复侧：这段字节直接喂给同一个解码器，与拉取远端走同一条路。
      secure.store.clear();
      final freshAccounts = AccountsService(
        db: _FakeLibraryDatabase(),
        secureStorage: secure,
      );
      await freshAccounts.init();
      final freshVault = CredentialVaultService(
        accounts: freshAccounts,
        settings: settings,
        webDav: webDav,
      );
      final applied = await freshVault.applyVault(
        CredentialVaultCodec.decode(section),
        passphrase: '归档口令',
      );
      expect(applied.imported, 2);
      expect(applied.passwordsMissing, 0);
      final nas = freshAccounts.accounts.firstWhere((a) => a.name == 'NAS');
      expect(await freshAccounts.passwordFor(nas.id), 'hunter2');
      final restoredCloud = freshAccounts.accounts.firstWhere(
        (a) => a.providerType == 'netease_music',
      );
      final cfg = await freshAccounts.loadDriverConfig(restoredCloud.id);
      expect(cfg?['cookie'], 'MUSIC_U=secret');
      expect(cfg?['api_url_address'], 'https://api.example.com');
    });

    test('PLAYLISTS 段每歌单一条 blob 记录，用的是 .wdmp 同一个解码函数', () async {
      final pl = await playlists.create(
        name: '最爱',
        entries: [
          const PlaylistEntry(
            sourceName: '123pan',
            remotePath: '/m/a.flac',
            title: 'a.flac',
            durationMs: 215000,
          ),
        ],
      );

      final archive = await backup.buildArchiveBytes(passphrase: '');
      final container = WmpContainer.fromBytes(archive);
      final raw = container.readSection(WmpSections.playlists)!;

      final records = decodeRecords(
        raw,
        intTags: const {},
        bytesTags: const {WmpBackupPlaylist.blob},
      );
      expect(records, hasLength(1));
      final blob = records.single[WmpBackupPlaylist.blob];
      expect(blob, isA<Uint8List>());
      expect(WmpContainer.kindOf(blob! as Uint8List), WmpFileKind.playlist);

      final doc = PlaylistCodec.decode(blob as Uint8List);
      expect(doc.playlist.id, pl.id);
      expect(doc.playlist.name, '最爱');
      expect(doc.entryCount, 1);
      expect(
        doc.playlist.entries.single.identityKey,
        pl.entries.single.identityKey,
      );
      // 单播出口（上传远端用）产出的也是同一类文档。
      expect(
        WmpContainer.kindOf(await playlists.encodePlaylistBytes(pl)),
        WmpFileKind.playlist,
      );

      // 恢复：解出来直接交给 merge，不删本地其它歌单。
      final target = PlaylistService(
        store: _MemoryPlaylistStore(),
        webDav: webDav,
      );
      await target.mergeFromPlaylists([doc.playlist]);
      expect(target.playlists.single.id, pl.id);
      expect(target.playlists.single.entries, hasLength(1));
    });

    test('没有歌单时不写 PLAYLISTS 段', () async {
      final archive = await backup.buildArchiveBytes(passphrase: '');
      final container = WmpContainer.fromBytes(archive);
      expect(container.has(WmpSections.playlists), isFalse);
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

      final missing = await accounts.restoreFromBackup(
        json,
        passphrase: '归档口令',
      );
      expect(missing, isEmpty);
      expect(accounts.accounts.map((a) => a.name), containsAll(['NAS', '网易云']));
      expect(
        accounts.accounts.any((a) => a.providerType == 'ghost_drive_2099'),
        isFalse,
      );

      final nt = accounts.accounts.firstWhere((a) => a.name == '网易云');
      expect(nt.remotePath, '/音乐');
      final cfg = await accounts.loadDriverConfig(nt.id);
      expect(cfg?['cookie'], 'MUSIC_U=restored');
      expect(cfg?['api_url_address'], 'https://x');
      expect(secure.store['webdav_pass_wd-1'], 'p');
    });
  });
}
