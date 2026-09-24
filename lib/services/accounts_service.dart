import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/account_capabilities.dart';
import '../models/webdav_account.dart';
import '../utils/credential_vault_crypto.dart';
import '../utils/track_identity.dart';
import 'cloud_drivers/driver_registry.dart';
import 'library_database.dart';

/// Multi-WebDAV account management. Passwords in secure storage.
class AccountsService extends ChangeNotifier {
  AccountsService({
    required LibraryDatabase db,
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  })  : _db = db,
        _secure = secureStorage ?? const FlutterSecureStorage(),
        _prefs = prefs;

  static const _kActiveAccount = 'active_webdav_account_id';
  static const _kPassPrefix = 'webdav_pass_';
  // Legacy single-account keys (migrated once).
  static const _legacyUrl = 'webdav_url';
  static const _legacyUser = 'webdav_username';
  static const _legacyPass = 'webdav_password';

  final LibraryDatabase _db;
  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;
  final _uuid = const Uuid();

  final List<WebDavAccount> _accounts = [];
  String? _activeAccountId;
  bool _loaded = false;

  UnmodifiableListView<WebDavAccount> get accounts =>
      UnmodifiableListView(_accounts);
  bool get loaded => _loaded;
  String? get activeAccountId => _activeAccountId;

  WebDavAccount? get activeAccount {
    if (_activeAccountId == null) return null;
    try {
      return _accounts.firstWhere((a) => a.id == _activeAccountId);
    } catch (_) {
      return _accounts.isEmpty ? null : _accounts.first;
    }
  }

  /// Resolve a library row's binding point (the disk **name**) to a local account.
  ///
  /// The name is the only thing the cloud library and backups carry — URL,
  /// username and password stay in this table. A name that has no local account
  /// means the row is "unbound": it can be listed, but not played or downloaded
  /// until the user adds/renames a disk to match.
  WebDavAccount? accountForSource(String sourceName) {
    final wanted = normalizeSourceName(sourceName);
    if (wanted.isEmpty) return null;
    for (final a in _accounts) {
      if (normalizeSourceName(a.name) == wanted) return a;
    }
    return null;
  }

  String? idForSource(String sourceName) => accountForSource(sourceName)?.id;

  /// Whether a library row bound to [sourceName] can actually transfer bytes.
  bool isSourceBound(String sourceName) => accountForSource(sourceName) != null;

  /// Reverse lookup: a WebDAV account id → the library binding name.
  String? nameForAccount(String accountId) {
    for (final a in _accounts) {
      if (a.id == accountId) return a.name;
    }
    return null;
  }

  /// Disk names already taken (used to warn about the single binding point).
  List<String> get sourceNames =>
      [for (final a in _accounts) a.name.trim()];

  /// An account that already uses [name] (case-insensitive), if any.
  WebDavAccount? accountNamed(String name, {String? exceptId}) {
    final wanted = normalizeSourceName(name).toLowerCase();
    if (wanted.isEmpty) return null;
    for (final a in _accounts) {
      if (a.id == exceptId) continue;
      if (normalizeSourceName(a.name).toLowerCase() == wanted) return a;
    }
    return null;
  }

  /// 按 id 取账号（云盘分流缝 / 能力解析用）。
  WebDavAccount? accountById(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool get hasAccounts => _accounts.isNotEmpty;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded();
    _accounts
      ..clear()
      ..addAll(await _db.loadAccounts());
    _activeAccountId = _prefs!.getString(_kActiveAccount);
    if (_activeAccountId != null &&
        !_accounts.any((a) => a.id == _activeAccountId)) {
      _activeAccountId = null;
    }
    if (_activeAccountId == null && _accounts.isNotEmpty) {
      _activeAccountId = _accounts.first.id;
      await _prefs!.setString(_kActiveAccount, _activeAccountId!);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _migrateLegacyIfNeeded() async {
    final existing = await _db.loadAccounts();
    if (existing.isNotEmpty) return;
    final url = await _secure.read(key: _legacyUrl) ?? '';
    if (url.trim().isEmpty) return;
    final user = await _secure.read(key: _legacyUser) ?? '';
    final pass = await _secure.read(key: _legacyPass) ?? '';
    final id = _uuid.v4();
    final account = WebDavAccount(
      id: id,
      name: '默认服务器',
      url: url.trim(),
      username: user,
    );
    await _db.upsertAccount(account);
    await _secure.write(key: '$_kPassPrefix$id', value: pass);
    await _secure.delete(key: _legacyUrl);
    await _secure.delete(key: _legacyUser);
    await _secure.delete(key: _legacyPass);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kActiveAccount, id);
  }

  Future<String?> passwordFor(String accountId) async {
    return _secure.read(key: '$_kPassPrefix$accountId');
  }

  /// 云盘驱动的凭证与配置（99 §7.2.2）：JSON 存 secure storage，按账号隔离。
  /// 内容例：refresh_token / client_id / client_secret / api_url_address /
  /// local_refresh / access_token 缓存。
  static const _kDriverCfgPrefix = 'cloud_driver_cfg_';

  Future<void> saveDriverConfig(
    String accountId,
    Map<String, dynamic> config,
  ) async {
    await _secure.write(
      key: '$_kDriverCfgPrefix$accountId',
      value: jsonEncode(config),
    );
  }

  Future<Map<String, dynamic>?> loadDriverConfig(String accountId) async {
    final raw = await _secure.read(key: '$_kDriverCfgPrefix$accountId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<WebDavAccount> addAccount({
    required String name,
    required String url,
    required String username,
    required String password,
    String providerType = 'webdav',
    String remotePath = '/',
    int? capabilities,
  }) async {
    final account = WebDavAccount(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? url.trim() : name.trim(),
      url: url.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username,
      providerType: providerType,
      remotePath: WebDavAccount.normalizeRemotePath(remotePath),
      capabilities: capabilities ??
          (providerType == 'webdav'
              ? AccountCaps.all
              // 云盘静态位由驱动声明（99 §7.2.10）；读取时也以注册表为准。
              : (cloudDriverSpec(providerType)?.capabilities ??
                  AccountCaps.list)),
    );
    await _db.upsertAccount(account);
    await _secure.write(key: '$_kPassPrefix${account.id}', value: password);
    _accounts.add(account);
    _activeAccountId ??= account.id;
    _prefs ??= await SharedPreferences.getInstance();
    if (_prefs!.getString(_kActiveAccount) == null) {
      await _prefs!.setString(_kActiveAccount, account.id);
      _activeAccountId = account.id;
    }
    notifyListeners();
    return account;
  }

  Future<void> updateAccount({
    required String id,
    required String name,
    required String url,
    required String username,
    String? password,
    String? providerType,
    String? remotePath,
    int? capabilities,
  }) async {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final updated = _accounts[idx].copyWith(
      name: name.trim().isEmpty ? url.trim() : name.trim(),
      url: url.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username,
      providerType: providerType,
      remotePath: remotePath == null
          ? null
          : WebDavAccount.normalizeRemotePath(remotePath),
      capabilities: capabilities,
    );
    await _db.upsertAccount(updated);
    if (password != null) {
      await _secure.write(key: '$_kPassPrefix$id', value: password);
    }
    _accounts[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    await _db.deleteAccount(id);
    await _secure.delete(key: '$_kPassPrefix$id');
    await _secure.delete(key: '$_kDriverCfgPrefix$id');
    _accounts.removeWhere((a) => a.id == id);
    if (_activeAccountId == id) {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      _prefs ??= await SharedPreferences.getInstance();
      if (_activeAccountId == null) {
        await _prefs!.remove(_kActiveAccount);
      } else {
        await _prefs!.setString(_kActiveAccount, _activeAccountId!);
      }
    }
    notifyListeners();
  }

  Future<void> setActiveAccount(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeAccountId = id;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kActiveAccount, id);
    notifyListeners();
  }


  /// Restore **one** account from a per-site backup without touching other mounts.
  /// Never copies credentials onto a different account id.
  /// Recreates the mount if [account.id] is missing locally.
  ///
  /// Only the password may be encrypted (`AESGCMv1:`); when [passphrase] cannot
  /// decrypt it the account is still restored with an **empty password** so the
  /// user can fill it in, instead of failing the whole restore.
  Future<bool> mergeAccountFromBackup(
    Map<String, dynamic> accountJson, {
    String passphrase = '',
  }) async {
    final id = accountJson['id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('备份账号缺少 id，无法安全恢复');
    }
    final url = (accountJson['url'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    final name = accountJson['name'] as String? ??
        accountJson['url'] as String? ??
        '服务器';
    final username = accountJson['username'] as String? ?? '';
    final rawPass = accountJson['password'] as String? ?? '';
    final encrypted = accountJson['passwordEncrypted'] as bool? ??
        CredentialVaultCrypto.isEncrypted(rawPass);
    var passwordRecovered = true;
    String pass = rawPass;
    if (encrypted && CredentialVaultCrypto.isEncrypted(rawPass)) {
      final clear = await CredentialVaultCrypto.tryDecrypt(
        encoded: rawPass,
        passphrase: passphrase,
      );
      if (clear == null) {
        // Missing unified decryption key → restore the mount, leave password blank.
        pass = '';
        passwordRecovered = false;
      } else {
        pass = clear;
      }
    }

    final account = WebDavAccount(
      id: id,
      name: name,
      url: url,
      username: username,
    );
    await _db.upsertAccount(account);
    await _secure.write(key: '$_kPassPrefix$id', value: pass);

    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _accounts[idx] = account;
    } else {
      _accounts.add(account);
    }
    // Prefer restored account as active when it was the backup target.
    _prefs ??= await SharedPreferences.getInstance();
    _activeAccountId = id;
    await _prefs!.setString(_kActiveAccount, id);
    notifyListeners();
    return passwordRecovered;
  }

  /// Restore accounts + passwords from backup JSON.
  /// Expects `{ activeAccountId, accounts: [{id,name,url,username,password}, ...] }`.
  ///
  /// Passwords may be `AESGCMv1:` blobs; entries that cannot be decrypted with
  /// [passphrase] are restored with an empty password rather than aborting.
  Future<List<String>> restoreFromBackup(
    Map<String, dynamic> json, {
    String passphrase = '',
  }) async {
    final list = json['accounts'] as List<dynamic>? ?? [];
    final missing = <String>[];
    _prefs ??= await SharedPreferences.getInstance();
    // Clear existing passwords for current accounts.
    for (final a in List<WebDavAccount>.from(_accounts)) {
      await _secure.delete(key: '$_kPassPrefix${a.id}');
    }
    // Replace accounts table by upserting backup set and deleting missing.
    final existing = await _db.loadAccounts();
    final keepIds = <String>{};
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final account = WebDavAccount(
        id: m['id'] as String,
        name: m['name'] as String? ?? m['url'] as String? ?? '服务器',
        url: (m['url'] as String? ?? '').trim().replaceAll(RegExp(r'/+$'), ''),
        username: m['username'] as String? ?? '',
      );
      keepIds.add(account.id);
      await _db.upsertAccount(account);
      final rawPass = m['password'] as String? ?? '';
      String pass = rawPass;
      if (CredentialVaultCrypto.isEncrypted(rawPass)) {
        final clear = await CredentialVaultCrypto.tryDecrypt(
          encoded: rawPass,
          passphrase: passphrase,
        );
        if (clear == null) {
          pass = '';
          missing.add(account.name);
        } else {
          pass = clear;
        }
      }
      await _secure.write(key: '$_kPassPrefix${account.id}', value: pass);
    }
    for (final a in existing) {
      if (!keepIds.contains(a.id)) {
        await _db.deleteAccount(a.id);
        await _secure.delete(key: '$_kPassPrefix${a.id}');
      }
    }
    _accounts
      ..clear()
      ..addAll(await _db.loadAccounts());
    final active = json['activeAccountId'] as String?;
    if (active != null && _accounts.any((a) => a.id == active)) {
      _activeAccountId = active;
    } else {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
    }
    if (_activeAccountId == null) {
      await _prefs!.remove(_kActiveAccount);
    } else {
      await _prefs!.setString(_kActiveAccount, _activeAccountId!);
    }
    notifyListeners();
    return missing;
  }

}
