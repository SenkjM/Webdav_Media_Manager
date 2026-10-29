import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/account_capabilities.dart';
import '../models/account_sentinels.dart';
import '../models/webdav_account.dart';
import '../utils/credential_vault_crypto.dart';
import '../utils/l10n_host.dart';
import '../utils/track_identity.dart';
import 'wdmm_vfs/driver_registry.dart';
import 'rust_core_service.dart';

/// Multi-WebDAV account management.
///
/// Core DB (wdmm-core via FFI) is the sole source of truth for account
/// metadata. Passwords and driver configs stay in [FlutterSecureStorage] so
/// Dart-side drivers can read them without an extra FFI round-trip.
///
/// First-launch upgrade path (one-shot, never repeated):
///   Core empty → sqflite has rows  → upsert each to Core, then ignore sqflite.
///   Core empty + sqflite empty     → check legacy flutter_secure single-server keys.
class AccountsService extends ChangeNotifier {
  AccountsService({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _kActiveAccount = 'active_webdav_account_id';
  static const _kPassPrefix = 'webdav_pass_';
  static const _kDriverCfgPrefix = 'cloud_driver_cfg_';
  // Legacy single-account keys (migrated once).
  static const _legacyUrl = 'webdav_url';
  static const _legacyUser = 'webdav_username';
  static const _legacyPass = 'webdav_password';

  final FlutterSecureStorage _secure;
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
  WebDavAccount? accountForSource(String sourceName) {
    final wanted = normalizeSourceName(sourceName);
    if (wanted.isEmpty) return null;
    for (final a in _accounts) {
      if (normalizeSourceName(a.name) == wanted) return a;
    }
    return null;
  }

  String? idForSource(String sourceName) => accountForSource(sourceName)?.id;
  bool isSourceBound(String sourceName) => accountForSource(sourceName) != null;

  /// Reverse lookup: account id → library binding name.
  String? nameForAccount(String accountId) {
    for (final a in _accounts) {
      if (a.id == accountId) return a.name;
    }
    return null;
  }

  List<String> get sourceNames => [for (final a in _accounts) a.name.trim()];

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

  static String nameKey(String name) => accountNameKey(name);

  String _resolvedName(String name, String url) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? url.trim() : trimmed;
  }

  void _assertNameAvailable(String name, {String? exceptId}) {
    final clash = accountNamed(name, exceptId: exceptId);
    if (clash != null) throw StateError('err.accountNameTaken');
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    while (_initInFlight != null) {
      try {
        await _initInFlight;
      } catch (_) {}
    }
    final gate = Completer<void>();
    _initInFlight = gate.future;
    try {
      // 1. Load from Core.
      var loaded = await _loadFromCore();

      // 2. One-shot migrate: Core empty — try legacy flutter_secure keys.
      if (loaded.isEmpty) {
        await _migrateLegacyIfNeeded();
        loaded = await _loadFromCore();
      }

      // Replace in one step so overlapping inits cannot append.
      final deduped = <WebDavAccount>[];
      final seen = <String>{};
      for (final a in loaded) {
        if (seen.add(a.id)) deduped.add(a);
      }
      _accounts
        ..clear()
        ..addAll(deduped);

      await _collapseDuplicatesIfNeeded();

      _activeAccountId = RustCoreService.kvGet(_kActiveAccount);
      if (_activeAccountId != null &&
          !_accounts.any((a) => a.id == _activeAccountId)) {
        _activeAccountId = null;
      }
      if (_activeAccountId == null && _accounts.isNotEmpty) {
        _activeAccountId = _accounts.first.id;
        RustCoreService.kvSet(_kActiveAccount, _activeAccountId!);
      }

      _loaded = true;
      notifyListeners();
      gate.complete();
    } catch (e, st) {
      gate.completeError(e, st);
      rethrow;
    } finally {
      if (identical(_initInFlight, gate.future)) _initInFlight = null;
    }
  }

  /// Load accounts from Core FFI, mirroring passwords/configs into secure
  /// storage so Dart-side drivers keep working without per-call FFI hits.
  /// Returns an empty list when FFI is unavailable, Core reports an error,
  /// or no accounts exist — callers then run one-shot migrate helpers.
  Future<List<WebDavAccount>> _loadFromCore() async {
    final raw = RustCoreService.accountList();
    // null / empty → Core has no accounts (or FFI not ready); migrate may run.
    // Explicit Core error must fail hard — never treat as empty (would re-migrate).
    if (raw != null && raw.startsWith('error:')) {
      throw StateError(
        '[AccountsService] Core accountList failed: $raw',
      );
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      final result = <WebDavAccount>[];
      for (final item in arr) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final providerType = m['provider_type'] as String? ?? 'webdav';
        final name = m['display_name'] as String? ?? '';
        final url = m['base_url'] as String? ?? '';

        // credentials may be a nested map (upsert shape) or base64 blob.
        final credentials = (m['credentials'] as Map<String, dynamic>?) ??
            _decodeCredentialsB64(m['credentials_b64'] as String?) ??
            <String, dynamic>{};

        String username = '';
        String remotePath = '/';
        if (providerType == 'webdav') {
          username = credentials['username'] as String? ?? '';
          remotePath = WebDavAccount.normalizeRemotePath(
            credentials['remote_dir'] as String? ?? '/',
          );
          final password = credentials['password'] as String? ?? '';
          if (password.isNotEmpty) {
            final stored = await _secure.read(key: '$_kPassPrefix$id');
            if (stored == null || stored.isEmpty) {
              await _secure.write(key: '$_kPassPrefix$id', value: password);
            }
          }
        } else if (credentials.isNotEmpty) {
          // Cloud driver: mirror flat driver config if missing (drop nested source).
          final stored = await _secure.read(key: '$_kDriverCfgPrefix$id');
          if (stored == null || stored.isEmpty) {
            final flat = Map<String, dynamic>.from(credentials)..remove('source');
            await _secure.write(
              key: '$_kDriverCfgPrefix$id',
              value: jsonEncode(flat),
            );
          }
        }

        result.add(WebDavAccount(
          id: id,
          name: name,
          url: url,
          username: username,
          providerType: providerType,
          remotePath: remotePath,
        ));
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AccountsService] _loadFromCore parse error: $e');
      }
      return [];
    }
  }

  /// Decode a base64-encoded credentials JSON blob (Desktop/older Core shape).
  static Map<String, dynamic>? _decodeCredentialsB64(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      final bytes = base64Decode(b64);
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // One-shot migrations (run only when Core is empty)
  // ---------------------------------------------------------------------------

  /// Legacy: single-server keys from flutter_secure → upsert into Core.
  /// Only reached when Core is empty.
  Future<void> _migrateLegacyIfNeeded() async {
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
    await _secure.write(key: '$_kPassPrefix$id', value: pass);
    await _upsertToCore(account); // throws on error
    await _secure.delete(key: _legacyUrl);
    await _secure.delete(key: _legacyUser);
    await _secure.delete(key: _legacyPass);
    RustCoreService.kvSet(_kActiveAccount, id);
  }

  // ---------------------------------------------------------------------------
  // Passwords + driver configs
  // ---------------------------------------------------------------------------

  Future<String?> passwordFor(String accountId) =>
      _secure.read(key: '$_kPassPrefix$accountId');

  Future<void> saveDriverConfig(
    String accountId,
    Map<String, dynamic> config,
  ) async {
    await _secure.write(
      key: '$_kDriverCfgPrefix$accountId',
      value: jsonEncode(config),
    );
    final account = accountById(accountId);
    if (account != null) await _upsertToCore(account); // throws on error
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

  /// 按**账号名**找驱动配置（凭证恢复兜底）。
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

  // ---------------------------------------------------------------------------
  // Core upsert — the single path that writes account metadata to Core.
  // All CRUD operations flow through here; errors are never swallowed.
  // ---------------------------------------------------------------------------

  /// Ensure an in-memory account is present in Core DB. Used by
  /// [CloudDriveService] before driver instantiation. Throws [StateError]
  /// when the account is not in memory, FFI is unavailable, or Core errors.
  Future<void> ensureAccountInCore(String accountId) async {
    final account = accountById(accountId);
    if (account == null) {
      throw StateError(
        '[AccountsService] ensureAccountInCore: account $accountId not in memory',
      );
    }
    await _upsertToCore(account); // throws on Core error
  }

  /// Upsert [a] to Core DB. Throws [StateError] when FFI is unavailable or
  /// Core returns an error string. Never logs-and-continues.
  Future<void> _upsertToCore(WebDavAccount a) async {
    final driverCfg = await loadDriverConfig(a.id);
    Map<String, dynamic> credentials;
    if (a.providerType == 'webdav') {
      final password = await passwordFor(a.id) ?? '';
      credentials = {
        'username': a.username,
        'password': password,
        'remote_dir': a.remotePath,
      };
    } else {
      credentials = driverCfg ?? {};
      // Crypt: embed resolved source if name present but nested source absent.
      if (a.providerType == 'crypt' &&
          credentials.containsKey('source_account_id_name') &&
          !credentials.containsKey('source')) {
        final sourceName = credentials['source_account_id_name'] as String?;
        if (sourceName != null) {
          final src = accountForSource(sourceName);
          if (src != null) {
            final srcCfg = await loadDriverConfig(src.id);
            final srcCreds = <String, dynamic>{};
            if (src.providerType == 'webdav') {
              // Rust create_driver('webdav', …) requires 'url'; the URL lives in
              // src.url (base_url), not in the credential map — add it explicitly.
              srcCreds['url'] = src.url;
              srcCreds['username'] = src.username;
              srcCreds['password'] = await passwordFor(src.id) ?? '';
              srcCreds['remote_dir'] = src.remotePath;
            } else {
              srcCreds.addAll(srcCfg ?? {});
            }
            credentials['source'] = {
              'provider_type': src.providerType,
              'config': srcCreds,
            };
          }
        }
      }
    }

    final coreJson = jsonEncode({
      'id': a.id,
      'provider_type': a.providerType,
      'display_name': a.name,
      'base_url': a.url,
      'credentials': credentials,
    });
    final result = RustCoreService.accountUpsert(coreJson);
    if (result == null) {
      throw StateError(
        '[AccountsService] Core FFI unavailable (accountUpsert null) for ${a.id}',
      );
    }
    if (result.startsWith('error:')) {
      throw StateError(
        '[AccountsService] Core accountUpsert failed for ${a.id}: $result',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Duplicate-name collapse (in-memory + Core; no sqflite)
  // ---------------------------------------------------------------------------

  Set<String> _duplicateNameKeys() {
    final counts = <String, int>{};
    for (final a in _accounts) {
      final k = nameKey(a.name);
      if (k.isEmpty) continue;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return {for (final e in counts.entries) if (e.value > 1) e.key};
  }

  Map<String, List<WebDavAccount>> duplicateNameGroups() {
    final dups = _duplicateNameKeys();
    final groups = <String, List<WebDavAccount>>{};
    for (final a in _accounts) {
      final k = nameKey(a.name);
      if (!dups.contains(k)) continue;
      groups.putIfAbsent(k, () => []).add(a);
    }
    return groups;
  }

  /// Collapse same-name rows: keep one per group (prefer active id), delete
  /// the rest from Core and secure storage.
  Future<void> _collapseDuplicatesIfNeeded() async {
    if (_duplicateNameKeys().isEmpty) return;
    final byKey = <String, List<WebDavAccount>>{};
    for (final a in _accounts) {
      byKey.putIfAbsent(nameKey(a.name), () => []).add(a);
    }
    final toDelete = <String>[];
    for (final group in byKey.values) {
      if (group.length < 2) continue;
      group.sort((a, b) => a.id.compareTo(b.id));
      var keep = group.first;
      for (final a in group) {
        if (a.id == _activeAccountId) {
          keep = a;
          break;
        }
      }
      for (final a in group) {
        if (a.id != keep.id) toDelete.add(a.id);
      }
    }
    for (final id in toDelete) {
      final result = RustCoreService.accountDelete(id);
      if (result != null && result.startsWith('error:') && kDebugMode) {
        debugPrint(
          '[AccountsService] Core delete failed during collapse for $id: $result',
        );
      }
      await _secure.delete(key: '$_kPassPrefix$id');
      await _secure.delete(key: '$_kDriverCfgPrefix$id');
      _accounts.removeWhere((a) => a.id == id);
    }
    if (_activeAccountId != null &&
        !_accounts.any((a) => a.id == _activeAccountId)) {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      if (_activeAccountId == null) {
        RustCoreService.kvDelete(_kActiveAccount);
      } else {
        RustCoreService.kvSet(_kActiveAccount, _activeAccountId!);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD — Core only, fail hard
  // ---------------------------------------------------------------------------

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
      capabilities: capabilities ??
          (providerType == 'webdav'
              ? AccountCaps.all
              : (wdmmVfsSpec(providerType)?.capabilities ?? AccountCaps.list)),
    );
    await _secure.write(key: '$_kPassPrefix${account.id}', value: password);
    await _upsertToCore(account); // throws on error
    _accounts.add(account);
    _activeAccountId ??= account.id;
    if (RustCoreService.kvGet(_kActiveAccount) == null) {
      RustCoreService.kvSet(_kActiveAccount, account.id);
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
    final resolvedName = _resolvedName(name, url);
    _assertNameAvailable(resolvedName, exceptId: id);
    final updated = _accounts[idx].copyWith(
      name: resolvedName,
      url: url.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username,
      providerType: providerType,
      remotePath:
          remotePath == null ? null : WebDavAccount.normalizeRemotePath(remotePath),
      capabilities: capabilities,
    );
    if (password != null) {
      await _secure.write(key: '$_kPassPrefix$id', value: password);
    }
    await _upsertToCore(updated); // throws on error
    _accounts[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    // Core first — throws on error; do not remove from memory on FFI failure.
    final result = RustCoreService.accountDelete(id);
    if (result == null) {
      throw StateError(
        '[AccountsService] Core FFI unavailable (accountDelete null) for $id',
      );
    }
    if (result.startsWith('error:')) {
      throw StateError(
        '[AccountsService] Core accountDelete failed for $id: $result',
      );
    }
    await _secure.delete(key: '$_kPassPrefix$id');
    await _secure.delete(key: '$_kDriverCfgPrefix$id');
    _accounts.removeWhere((a) => a.id == id);
    if (_activeAccountId == id) {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      if (_activeAccountId == null) {
        RustCoreService.kvDelete(_kActiveAccount);
      } else {
        RustCoreService.kvSet(_kActiveAccount, _activeAccountId!);
      }
    }
    notifyListeners();
  }

  Future<void> setActiveAccount(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeAccountId = id;
    RustCoreService.kvSet(_kActiveAccount, id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Backup restore — Core-only, no sqflite
  // ---------------------------------------------------------------------------

  /// Restore **one** account from a per-site backup without touching other mounts.
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
        pass = '';
        passwordRecovered = false;
      } else {
        pass = clear;
      }
    }

    final resolvedName = _resolvedName(name, url);
    final clash = accountNamed(resolvedName, exceptId: id);
    if (clash != null) {
      final delResult = RustCoreService.accountDelete(clash.id);
      if (delResult != null && delResult.startsWith('error:')) {
        throw StateError(
          '[AccountsService] Core delete of clashing account failed: $delResult',
        );
      }
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
    await _secure.write(key: '$_kPassPrefix$id', value: pass);
    await _upsertToCore(account); // throws on error

    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _accounts[idx] = account;
    } else {
      _accounts.add(account);
    }
    _activeAccountId = id;
    RustCoreService.kvSet(_kActiveAccount, id);
    notifyListeners();
    return passwordRecovered;
  }

  /// Restore accounts + passwords from backup JSON.
  ///
  /// 云盘账号（v2 备份）：驱动配置 JSON 随档案走，密文字段逐字段解密；
  /// 本机未注册的 providerType **静默跳过**。返回无法解密密码的账号名列表。
  Future<List<String>> restoreFromBackup(
    Map<String, dynamic> json, {
    String passphrase = '',
  }) async {
    final list = json['accounts'] as List<dynamic>? ?? [];
    final missing = <String>[];
    final existingIds = {for (final a in _accounts) a.id};
    final keepIds = <String>{};
    final seenNames = <String>{};

    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final providerType = m['providerType'] as String? ?? 'webdav';
      if (providerType != 'webdav' && wdmmVfsSpec(providerType) == null) {
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
      if (nKey.isNotEmpty && !seenNames.add(nKey)) continue;
      keepIds.add(account.id);

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
      } else {
        await _secure.delete(key: '$_kPassPrefix${account.id}');
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

      await _upsertToCore(account); // throws on error
    }

    // Delete accounts absent from the backup.
    for (final id in existingIds) {
      if (keepIds.contains(id)) continue;
      final delResult = RustCoreService.accountDelete(id);
      if (delResult != null && delResult.startsWith('error:')) {
        throw StateError(
          '[AccountsService] Core delete failed during restore for $id: $delResult',
        );
      }
      await _secure.delete(key: '$_kPassPrefix$id');
      await _secure.delete(key: '$_kDriverCfgPrefix$id');
    }

    // Reload from Core so memory reflects the restored state exactly.
    final reloaded = await _loadFromCore();
    _accounts
      ..clear()
      ..addAll(reloaded);
    await _collapseDuplicatesIfNeeded();

    final active = json['activeAccountId'] as String?;
    if (active != null && _accounts.any((a) => a.id == active)) {
      _activeAccountId = active;
    } else {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
    }
    if (_activeAccountId == null) {
      RustCoreService.kvDelete(_kActiveAccount);
    } else {
      RustCoreService.kvSet(_kActiveAccount, _activeAccountId!);
    }
    notifyListeners();
    return missing;
  }
}
