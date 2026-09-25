import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/webdav_account.dart';
import '../utils/credential_vault_crypto.dart';
import 'accounts_service.dart';
import 'cloud_drive_service.dart';
import 'cloud_drivers/driver_registry.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// One account entry inside the credential vault.
///
/// v2: WebDAV 服务器条目（url+username+password 三件套）之外，新增云盘
/// 驱动条目——凭证收在驱动配置 JSON（secure storage `cloud_driver_cfg_<id>`）
/// 里，其中「配置界面默认为密码」的字段（spec.secretFieldKeys，即
/// CloudDriverField.obscure）逐字段按 [CredentialVaultCrypto] 加密。
class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.passwordEncrypted,
    this.providerType = 'webdav',
    this.remotePath = '/',
    this.driverConfig,
  });

  final String id;
  final String name;

  /// Stored in **plain text** by design.
  final String url;

  /// Stored in **plain text** by design.
  final String username;

  /// Plaintext password, or the `AESGCMv1:` blob when [passwordEncrypted].
  final String password;
  final bool passwordEncrypted;

  /// 账号类型：'webdav' 或云盘驱动 typeId（99 §7.2.10）。
  final String providerType;

  /// 云盘账号的远端路径（WebDAV 条目恒 '/'）。
  final String remotePath;

  /// 云盘驱动的配置 JSON；null = WebDAV 条目。密文字段带 `AESGCMv1:` 前缀。
  final Map<String, dynamic>? driverConfig;

  bool get isCloud => providerType != 'webdav';

  bool get isActive => false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (isCloud) 'providerType': providerType,
        'url': url,
        'username': username,
        'password': password,
        'passwordEncrypted': passwordEncrypted,
        'remote_path': remotePath,
        if (driverConfig != null) 'driverConfig': driverConfig,
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ??
            json['url'] as String? ??
            '服务器',
        providerType: json['providerType'] as String? ?? 'webdav',
        url: json['url'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        passwordEncrypted: json['passwordEncrypted'] as bool? ??
            CredentialVaultCrypto.isEncrypted(json['password'] as String?),
        remotePath: json['remote_path'] as String? ?? '/',
        driverConfig: json['driverConfig'] is Map
            ? Map<String, dynamic>.from(json['driverConfig'] as Map)
            : null,
      );
}

/// Result of applying a vault to the local account list.
class VaultApplyResult {
  const VaultApplyResult({
    required this.imported,
    required this.updated,
    required this.passwordsRestored,
    required this.passwordsMissing,
    this.skippedUnknown = 0,
  });

  final int imported;
  final int updated;

  /// Accounts whose password could be decrypted (or was plaintext).
  final int passwordsRestored;

  /// Accounts whose password stayed empty because no matching key was given.
  final int passwordsMissing;

  /// 静默过滤掉的条目数：providerType 在本机构未注册（不支持）的网盘类型。
  /// 不报错、不建账号——只是跳过。
  final int skippedUnknown;

  bool get hasMissingPasswords => passwordsMissing > 0;

  String get summary =>
      '账号：新增 $imported，更新 $updated；'
      '密码恢复 $passwordsRestored，'
      '留空 $passwordsMissing${hasMissingPasswords ? '（缺少统一解密密钥，可稍后手动填写）' : ''}'
      '${skippedUnknown > 0 ? '；跳过 $skippedUnknown 个不支持的网盘类型' : ''}';
}

/// Account credential vault stored **on the WebDAV cloud** (同步根目录).
///
/// Layout under [SettingsService.syncRemoteRoot]:
/// * `credentials.json` — all accounts: WebDAV mounts with **plaintext
///   URL + username** and an encrypted (`AESGCMv1:`) or plaintext password,
///   plus cloud-driver accounts whose driver config carries the credentials
///   (cookie / refresh_token / client_secret / crypt password+salt …).
///
/// Only「配置界面默认为密码」的数据 is ever encrypted, which is what makes
/// recovery possible without the passphrase: the rest still identifies the
/// account, and empty secrets are simply left for the user to fill in.
class CredentialVaultService extends ChangeNotifier {
  CredentialVaultService({
    required AccountsService accounts,
    required SettingsService settings,
    required WebDavService webDav,
  })  : _accounts = accounts,
        _settings = settings,
        _webDav = webDav;

  final AccountsService _accounts;
  final SettingsService _settings;
  final WebDavService _webDav;

  static const fileName = 'credentials.json';
  static const format = 'webdav_media_manager_credentials';

  /// v2：新增云盘驱动条目（providerType + driverConfig，密文字段逐个加密）。
  /// v1 文件（只有 WebDAV 条目）按原语义读取。
  static const formatVersion = 2;

  bool busy = false;
  String? lastError;
  String? lastMessage;

  /// Passwords left empty by the last [pull]/[applyJson] because the vault was
  /// encrypted with a key we could not reproduce.
  final List<String> missingPasswordAccounts = [];

  String get remotePath {
    final root = _settings.syncRemoteRoot;
    return root.endsWith('/') ? '$root$fileName' : '$root/$fileName';
  }

  /// Build the vault JSON from the local account list.
  ///
  /// [passphrase] empty (or [encryptPassword] false) stores plaintext
  /// passwords — the same trust level as the old backup archives.
  Future<Map<String, dynamic>> buildJson({
    required String passphrase,
    bool? encryptPassword,
  }) async {
    final encrypt =
        (encryptPassword ?? _settings.syncEncryptPassword) && passphrase.isNotEmpty;
    final entries = <Map<String, dynamic>>[];
    // 账号凭证库：WebDAV 三件套 + 云盘驱动配置。云盘条目的密文字段
    // （spec.secretFieldKeys）逐字段加密，地址类字段保持明文可辨识。
    for (final a in _accounts.accounts) {
      if (CloudDriveService.isCloudType(a.providerType)) {
        final spec = cloudDriverSpec(a.providerType);
        final raw = await _accounts.loadDriverConfig(a.id) ?? const {};
        final stored = <String, dynamic>{};
        for (final e in raw.entries) {
          final value = e.value;
          if (encrypt &&
              value is String &&
              value.isNotEmpty &&
              spec != null &&
              spec.secretFieldKeys.contains(e.key) &&
              !CredentialVaultCrypto.isEncrypted(value)) {
            stored[e.key] = await CredentialVaultCrypto.encrypt(
              plaintext: value,
              passphrase: passphrase,
            );
          } else {
            stored[e.key] = value;
          }
        }
        entries.add(VaultEntry(
          id: a.id,
          name: a.name,
          providerType: a.providerType,
          remotePath: a.remotePath,
          url: '',
          username: '',
          password: '',
          passwordEncrypted: false,
          driverConfig: stored,
        ).toJson());
        continue;
      }
      final pass = await _accounts.passwordFor(a.id) ?? '';
      var stored = pass;
      var encrypted = false;
      if (encrypt && pass.isNotEmpty) {
        stored = await CredentialVaultCrypto.encrypt(
          plaintext: pass,
          passphrase: passphrase,
        );
        encrypted = true;
      }
      entries.add(VaultEntry(
        id: a.id,
        name: a.name,
        url: a.url,
        username: a.username,
        password: stored,
        passwordEncrypted: encrypted,
      ).toJson());
    }
    return {
      'format': format,
      'formatVersion': formatVersion,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'activeAccountId': _accounts.activeAccountId,
      'passwordEncryption': encrypt ? 'aes-256-gcm' : 'none',
      'note': encrypt
          ? '密码类字段（含云盘驱动令牌）加密（AES-256-GCM），其余字段为明文。'
          : '密码类字段为明文存储。',
      'accountCount': entries.length,
      'accounts': entries,
    };
  }

  /// Upload the vault to [accountId] (the credentials destination the user
  /// configured for this feature).
  Future<Map<String, dynamic>> push({
    required String accountId,
    required String passphrase,
    bool? encryptPassword,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      _requireAccount(accountId);
      final json = await buildJson(
        passphrase: passphrase,
        encryptPassword: encryptPassword,
      );
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
      );
      await _webDav.ensureDirectory(accountId, _settings.syncRemoteRoot);
      await _webDav.writeBytes(accountId, remotePath, bytes);
      lastMessage = (json['passwordEncryption'] == 'aes-256-gcm')
          ? '账号凭证已同步到云端（密码已加密）'
          : '账号凭证已同步到云端（明文密码）';
      return json;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Download the vault JSON from [accountId].
  ///
  /// Returns null when the file does not exist yet (nothing to pull).
  Future<Map<String, dynamic>?> fetchJson({
    required String accountId,
  }) async {
    _requireAccount(accountId);
    try {
      final bytes = await _webDav.readAsBytes(accountId, remotePath);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final missing = msg.contains('404') ||
          msg.contains('not found') ||
          msg.contains('does not exist');
      if (missing) return null;
      rethrow;
    }
  }

  /// Pull the vault from the cloud and apply it locally.
  ///
  /// When [passphrase] cannot decrypt an entry's password the account is still
  /// restored (url/username/name) with an **empty password**.
  Future<VaultApplyResult?> pull({
    required String accountId,
    required String passphrase,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      final json = await fetchJson(accountId: accountId);
      if (json == null) {
        lastMessage = '云端暂无凭证文件（$remotePath），已跳过';
        return null;
      }
      final result = await applyJson(json, passphrase: passphrase);
      lastMessage = '已从云端恢复账号凭证：${result.summary}';
      return result;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Merge a vault JSON into the local account list.
  ///
  /// Other local accounts are never deleted, so a partial vault cannot wipe
  /// mounts that were added after the last upload. Entries whose
  /// providerType is not registered on this build are **silently skipped**
  /// (不支持的网盘类型：不报错、不建账号).
  Future<VaultApplyResult> applyJson(
    Map<String, dynamic> json, {
    required String passphrase,
  }) async {
    missingPasswordAccounts.clear();
    final list = json['accounts'] as List<dynamic>? ?? const [];
    var imported = 0;
    var updated = 0;
    var restored = 0;
    var missing = 0;
    var skippedUnknown = 0;
    for (final raw in list) {
      if (raw is! Map) continue;
      final entry = VaultEntry.fromJson(Map<String, dynamic>.from(raw));

      // 云盘条目走驱动配置通道；本机没有注册该类型时静默跳过。
      if (entry.isCloud) {
        final spec = cloudDriverSpec(entry.providerType);
        if (spec == null) {
          skippedUnknown++;
          continue;
        }
        final outcome = await _applyCloudEntry(entry, passphrase);
        if (outcome.restoredSecrets) {
          restored++;
        } else {
          missing++;
        }
        if (outcome.imported) {
          imported++;
        } else {
          updated++;
        }
        continue;
      }

      if (entry.url.trim().isEmpty) continue;
      final String resolved;
      if (entry.passwordEncrypted && CredentialVaultCrypto.isEncrypted(entry.password)) {
        final clear = await CredentialVaultCrypto.tryDecrypt(
          encoded: entry.password,
          passphrase: passphrase,
        );
        if (clear == null) {
          // No unified decryption key: restore the account, leave password blank.
          resolved = '';
          missing++;
          missingPasswordAccounts.add(
            entry.name.isEmpty ? entry.url : '${entry.name}（${entry.url}）',
          );
        } else {
          resolved = clear;
          restored++;
        }
      } else {
        resolved = entry.password;
        restored++;
      }

      final existing = _accounts.accounts
          .cast<WebDavAccount?>()
          .firstWhere(
            (a) => a?.id == entry.id || a?.url == entry.url,
            orElse: () => null,
          );
      if (existing == null) {
        await _accounts.addAccount(
          name: entry.name,
          url: entry.url,
          username: entry.username,
          password: resolved,
        );
        imported++;
      } else {
        await _accounts.updateAccount(
          id: existing.id,
          name: entry.name.isEmpty ? existing.name : entry.name,
          url: entry.url,
          username: entry.username,
          // Never overwrite a working local password with an empty recovery.
          password: resolved.isEmpty ? null : resolved,
        );
        updated++;
      }
    }
    notifyListeners();
    return VaultApplyResult(
      imported: imported,
      updated: updated,
      passwordsRestored: restored,
      passwordsMissing: missing,
      skippedUnknown: skippedUnknown,
    );
  }

  /// Apply one cloud-driver vault entry.
  ///
  /// Per-field recovery: a secret field that cannot be decrypted keeps the
  /// **local** value when there is one and only counts as missing when the
  /// account is brand new (or the local field is empty too) — one lost field
  /// must not blank out tokens that still work.
  Future<({bool imported, bool restoredSecrets})> _applyCloudEntry(
    VaultEntry entry,
    String passphrase,
  ) async {
    final raw = entry.driverConfig ?? const <String, dynamic>{};
    final local = (await _accounts.loadDriverConfig(entry.id)) ??
        (await _accounts.loadDriverConfigByName(entry.name)) ??
        const <String, dynamic>{};
    final merged = <String, dynamic>{...local};
    var restoredSecrets = true;
    for (final e in raw.entries) {
      final value = e.value;
      if (value is String && CredentialVaultCrypto.isEncrypted(value)) {
        final clear = await CredentialVaultCrypto.tryDecrypt(
          encoded: value,
          passphrase: passphrase,
        );
        if (clear == null) {
          // 留用本地值（若有）；新账号则该字段留空待用户补填。
          final localValue = local[e.key];
          if (localValue is! String || localValue.isEmpty) {
            restoredSecrets = false;
          }
          continue;
        }
        merged[e.key] = clear;
      } else {
        merged[e.key] = value;
      }
    }
    if (!restoredSecrets) {
      missingPasswordAccounts.add(
          entry.name.isEmpty ? entry.providerType : entry.name);
    }

    final existing = _accounts.accounts
        .cast<WebDavAccount?>()
        .firstWhere((a) => a?.id == entry.id, orElse: () => null);
    if (existing == null) {
      final account = await _accounts.addAccount(
        name: entry.name,
        url: '',
        username: '',
        password: '',
        providerType: entry.providerType,
        remotePath: entry.remotePath,
      );
      await _accounts.saveDriverConfig(account.id, merged);
      return (imported: true, restoredSecrets: restoredSecrets);
    }
    await _accounts.updateAccount(
      id: existing.id,
      name: entry.name.isEmpty ? existing.name : entry.name,
      url: existing.url,
      username: existing.username,
      remotePath: entry.remotePath,
    );
    await _accounts.saveDriverConfig(existing.id, merged);
    return (imported: false, restoredSecrets: restoredSecrets);
  }

  /// Throws when the destination account has no registered client.
  void _requireAccount(String accountId) {
    if (!_webDav.hasAccount(accountId)) {
      throw StateError('凭证同步目的地网盘未配置');
    }
  }
}
