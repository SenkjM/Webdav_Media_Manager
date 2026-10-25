import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/account_capabilities.dart';
import '../models/account_sentinels.dart';
import '../models/webdav_account.dart';
import '../utils/credential_vault_crypto.dart';
import '../utils/l10n_host.dart';
import '../utils/track_identity.dart';
import 'cloud_drivers/driver_registry.dart';
import 'library_database.dart';
import 'rust_core_service.dart';

/// Multi-WebDAV account management. Passwords in secure storage.
class AccountsService extends ChangeNotifier {
  AccountsService({
    required LibraryDatabase db,
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  }) : _db = db,
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
  /// Serializes [init] so concurrent clear/await/addAll cannot multiply rows.
  Future<void>? _initInFlight;

  /// Always false after 0.2.4: duplicates are collapsed at open (99 §18.4).
  bool get needsNameCleanup => false;

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
  List<String> get sourceNames => [for (final a in _accounts) a.name.trim()];

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

  /// Normalized name key used for uniqueness (case-insensitive).
  static String nameKey(String name) => accountNameKey(name);

  String _resolvedName(String name, String url) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? url.trim() : trimmed;
  }

  /// Name is the logical identity; refuse a second account with the same name.
  void _assertNameAvailable(String name, {String? exceptId}) {
    final clash = accountNamed(name, exceptId: exceptId);
    if (clash != null) {
      throw StateError('err.accountNameTaken');
    }
  }

  Future<void> init() async {
    while (_initInFlight != null) {
      try {
        await _initInFlight;
      } catch (_) {
        // Prior attempt failed; this caller still reloads.
      }
    }
    final gate = Completer<void>();
    _initInFlight = gate.future;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _migrateLegacyIfNeeded();
      final rows = await _db.loadAccounts();
      // Replace in one step after await so overlapping inits cannot append.
      final deduped = <WebDavAccount>[];
      final seen = <String>{};
      for (final a in rows) {
        if (seen.add(a.id)) deduped.add(a);
      }
      _accounts
        ..clear()
        ..addAll(deduped);
      _activeAccountId = _prefs!.getString(_kActiveAccount);
      if (_activeAccountId != null &&
          !_accounts.any((a) => a.id == _activeAccountId)) {
        _activeAccountId = null;
      }
      if (_activeAccountId == null && _accounts.isNotEmpty) {
        _activeAccountId = _accounts.first.id;
        await _prefs!.setString(_kActiveAccount, _activeAccountId!);
      }
      await _collapseDuplicatesIfNeeded();
      _loaded = true;
      notifyListeners();
      // Best-effort sync all accounts to Core once.
      for (final a in _accounts) {
        await _syncAccountToCore(a);
      }
      gate.complete();
    } catch (e, st) {
      gate.completeError(e, st);
      rethrow;
    } finally {
      if (identical(_initInFlight, gate.future)) {
        _initInFlight = null;
      }
    }
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
      name: kDefaultServerName,
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
    // Reload account by id and sync to Core.
    final account = accountById(accountId);
    if (account != null) {
      await _syncAccountToCore(account);
    }
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

  /// 按**账号名**找驱动配置（凭证恢复兜底：账号被删后重添同名账号，
  /// id 变了但名字没变——与 crypt 的 resolveSourceByName 同一先例）。
  Future<Map<String, dynamic>?> loadDriverConfigByName(String name) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final a in _accounts) {
      if (a.name.trim().toLowerCase() != wanted) continue;
      final cfg = await loadDriverConfig(a.id);
      if (cfg != null && cfg.isNotEmpty) return cfg;
    }
    return null;
  }

  /// Normalized name keys that appear more than once in memory.
  Set<String> _duplicateNameKeys() {
    final counts = <String, int>{};
    for (final a in _accounts) {
      final key = nameKey(a.name);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return {
      for (final e in counts.entries)
        if (e.value > 1) e.key,
    };
  }

  /// Conflicting accounts grouped by normalized name (diagnostics).
  Map<String, List<WebDavAccount>> duplicateNameGroups() {
    final dups = _duplicateNameKeys();
    final groups = <String, List<WebDavAccount>>{};
    for (final a in _accounts) {
      final key = nameKey(a.name);
      if (!dups.contains(key)) continue;
      groups.putIfAbsent(key, () => []).add(a);
    }
    return groups;
  }

  /// Collapse same-name rows only when UNIQUE is not yet enforceable.
  Future<void> _collapseDuplicatesIfNeeded() async {
    if (_duplicateNameKeys().isEmpty && !_db.accountNameUniquePending) {
      await _db.applyAccountNameUnique();
      return;
    }
    final deleted = await _db.collapseDuplicateAccountNames(
      preferAccountId: _activeAccountId,
    );
    for (final id in deleted) {
      await _secure.delete(key: '$_kPassPrefix$id');
      await _secure.delete(key: '$_kDriverCfgPrefix$id');
      _accounts.removeWhere((a) => a.id == id);
    }
    // Reload from DB so memory matches keep-one result.
    final rows = await _db.loadAccounts();
    _accounts
      ..clear()
      ..addAll(rows);
    if (_activeAccountId != null &&
        !_accounts.any((a) => a.id == _activeAccountId)) {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      _prefs ??= await SharedPreferences.getInstance();
      if (_activeAccountId == null) {
        await _prefs!.remove(_kActiveAccount);
      } else {
        await _prefs!.setString(_kActiveAccount, _activeAccountId!);
      }
    }
    await _db.applyAccountNameUnique();
  }

  /// Mirror a Dart account into Core DB via FFI.
  /// Called after addAccount/updateAccount/saveDriverConfig and during init.
  /// Fail-soft: logs errors in debug mode but never blocks the local sqflite save.
  Future<void> _syncAccountToCore(WebDavAccount a) async {
    try {
      // Load driver config (tokens/cookies) for cloud accounts.
      final driverCfg = await loadDriverConfig(a.id);

      // Build credentials JSON based on provider_type.
      Map<String, dynamic> credentials;
      if (a.providerType == 'webdav') {
        // WebDAV: Core expects {username, password, remote_dir}.
        final password = await passwordFor(a.id) ?? '';
        credentials = {
          'username': a.username,
          'password': password,
          'remote_dir': a.remotePath,
        };
      } else {
        // Cloud driver: credentials = driver config (or {} if null).
        credentials = driverCfg ?? {};

        // If crypt and config has source account name but not nested source structure,
        // resolve the source account + its config and nest it as Core expects.
        if (a.providerType == 'crypt' && credentials.containsKey('source_account_id_name')) {
          final sourceName = credentials['source_account_id_name'] as String?;
          if (sourceName != null && !credentials.containsKey('source')) {
            final sourceAccount = accountForSource(sourceName);
            if (sourceAccount != null) {
              final sourceCfg = await loadDriverConfig(sourceAccount.id);
              final sourceCredentials = <String, dynamic>{};
              if (sourceAccount.providerType == 'webdav') {
                final sourcePw = await passwordFor(sourceAccount.id) ?? '';
                sourceCredentials['username'] = sourceAccount.username;
                sourceCredentials['password'] = sourcePw;
                sourceCredentials['remote_dir'] = sourceAccount.remotePath;
              } else {
                sourceCredentials.addAll(sourceCfg ?? {});
              }
              credentials['source'] = {
                'provider_type': sourceAccount.providerType,
                'config': sourceCredentials,
              };
            }
          }
        }
      }

      // Call Core FFI upsert.
      final coreJson = jsonEncode({
        'id': a.id,
        'provider_type': a.providerType,
        'display_name': a.name,
        'base_url': a.url,
        'credentials': credentials,
      });
      final result = RustCoreService.accountUpsert(coreJson);
      if (result != null && result.startsWith('error:') && kDebugMode) {
        debugPrint('[AccountsService] Core upsert failed for ${a.id}: $result');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AccountsService] _syncAccountToCore failed for ${a.id}: $e');
      }
    }
  }

  /// Public wrapper for CloudDriveService to ensure an account is in Core DB
  /// before driver instantiation. Fail-soft.
  Future<void> syncAccountToCoreById(String accountId) async {
    final account = accountById(accountId);
    if (account != null) {
      await _syncAccountToCore(account);
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
    final resolvedName = _resolvedName(name, url);
    _assertNameAvailable(resolvedName);
    final account = WebDavAccount(
      id: _uuid.v4(),
      name: resolvedName,
      url: url.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username,
      providerType: providerType,
      remotePath: WebDavAccount.normalizeRemotePath(remotePath),
      capabilities:
          capabilities ??
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
    await _syncAccountToCore(account);
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
    final resolvedName = _resolvedName(name, url);
    _assertNameAvailable(resolvedName, exceptId: id);
    final updated = _accounts[idx].copyWith(
      name: resolvedName,
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
    await _syncAccountToCore(updated);
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    await _db.deleteAccount(id);
    await _secure.delete(key: '$_kPassPrefix$id');
    await _secure.delete(key: '$_kDriverCfgPrefix$id');
    _accounts.removeWhere((a) => a.id == id);
    // Delete from Core DB.
    final result = RustCoreService.accountDelete(id);
    if (result != null && result.startsWith('error:') && kDebugMode) {
      debugPrint('[AccountsService] Core delete failed for $id: $result');
    }
    if (_activeAccountId == id) {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      _prefs ??= await SharedPreferences.getInstance();
      if (_activeAccountId == null) {
        await _prefs!.remove(_kActiveAccount);
      } else {
        await _prefs!.setString(_kActiveAccount, _activeAccountId!);
      }
    }
    await _collapseDuplicatesIfNeeded();
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
      throw StateError(L10nHost.current.svcBackupAccountMissingId);
    }
    final url = (accountJson['url'] as String? ?? '').trim().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final name =
        accountJson['name'] as String? ??
        accountJson['url'] as String? ??
        '服务器';
    final username = accountJson['username'] as String? ?? '';
    final rawPass = accountJson['password'] as String? ?? '';
    final encrypted =
        accountJson['passwordEncrypted'] as bool? ??
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

    final resolvedName = _resolvedName(name, url);
    // Name is logical identity: drop any other row that already owns this name.
    final clash = accountNamed(resolvedName, exceptId: id);
    if (clash != null) {
      await _db.deleteAccount(clash.id);
      await _secure.delete(key: '$_kPassPrefix${clash.id}');
      await _secure.delete(key: '$_kDriverCfgPrefix${clash.id}');
      _accounts.removeWhere((a) => a.id == clash.id);
    }

    final account = WebDavAccount(
      id: id,
      name: resolvedName,
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
  ///
  /// 云盘账号（v2 备份）：驱动配置 JSON（含 cookie/refresh_token 等令牌）随
  /// 档案走，密文字段逐字段解密；本机未注册的 providerType **静默跳过**
  /// （不支持 = 不报错、不建账号）。返回无法解密密码的账号名列表。
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
    final seenNames = <String>{};
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final providerType = m['providerType'] as String? ?? 'webdav';
      // 不支持的网盘类型：静默过滤，不报错也不留空壳账号。
      if (providerType != 'webdav' && cloudDriverSpec(providerType) == null) {
        continue;
      }
      final account = WebDavAccount(
        id: m['id'] as String,
        name: m['name'] as String? ?? m['url'] as String? ?? '服务器',
        url: (m['url'] as String? ?? '').trim().replaceAll(RegExp(r'/+$'), ''),
        username: m['username'] as String? ?? '',
        providerType: providerType,
        remotePath: m['remote_path'] as String? ?? '/',
      );
      final nKey = nameKey(account.name);
      if (nKey.isNotEmpty && !seenNames.add(nKey)) {
        // Same logical identity already restored from this archive.
        continue;
      }
      keepIds.add(account.id);
      await _db.upsertAccount(account);

      // 云盘条目：恢复驱动配置（密文字段逐字段尝试解密）。
      if (providerType != 'webdav') {
        final rawCfg = m['driverConfig'];
        final cfg = rawCfg is Map ? Map<String, dynamic>.from(rawCfg) : null;
        if (cfg != null) {
          var secretsRecovered = true;
          for (final e in List<MapEntry<String, dynamic>>.from(
            cfg.entries.toList(),
          )) {
            final value = e.value;
            if (value is String && CredentialVaultCrypto.isEncrypted(value)) {
              final clear = await CredentialVaultCrypto.tryDecrypt(
                encoded: value,
                passphrase: passphrase,
              );
              if (clear == null) {
                cfg[e.key] = '';
                secretsRecovered = false;
              } else {
                cfg[e.key] = clear;
              }
            }
          }
          await _secure.write(
            key: '$_kDriverCfgPrefix${account.id}',
            value: jsonEncode(cfg),
          );
          if (!secretsRecovered) missing.add(account.name);
        }
        continue;
      }

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
        await _secure.delete(key: '$_kDriverCfgPrefix${a.id}');
      }
    }
    final restoredRows = await _db.loadAccounts();
    _accounts
      ..clear()
      ..addAll(restoredRows);
    await _collapseDuplicatesIfNeeded();
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
