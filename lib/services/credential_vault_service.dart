import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/webdav_account.dart';
import '../utils/l10n_host.dart';
import 'accounts_service.dart';
import 'wdmm_vfs/driver_registry.dart';
import 'rust_core_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

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

  String get summary {
    final l10n = L10nHost.current;
    return '${l10n.vaultSummaryAccounts(imported, updated)}'
        '${l10n.vaultSummaryPasswords(passwordsMissing, passwordsRestored)}'
        '${hasMissingPasswords ? l10n.vaultSummaryMissingNote : ''}'
        '${skippedUnknown > 0 ? l10n.vaultSummarySkipped(skippedUnknown) : ''}';
  }
}

/// Account credential vault stored **on the WebDAV cloud** (同步根目录).
///
/// Layout under [SettingsService.syncRemoteRoot]:
/// * `credentials.wdmcv` — one `WDMMCV01` container: WebDAV mounts with
///   **plaintext URL + username** and an encrypted (`AESGCMv1:`) or plaintext
///   password, plus cloud-driver accounts whose driver config carries the
///   credentials (cookie / refresh_token / client_secret / crypt
///   password+salt …). Encoded and decoded by Rust — this service never
///   implements the wire format itself.
///
/// Only「配置界面默认为密码」的数据 is ever encrypted, which is what makes
/// recovery possible without the passphrase: the rest still identifies the
/// account, and empty secrets are simply left for the user to fill in.
class CredentialVaultService extends ChangeNotifier {
  CredentialVaultService({
    required AccountsService accounts,
    required SettingsService settings,
    required WebDavService webDav,
  }) : _accounts = accounts,
       _settings = settings,
       _webDav = webDav;

  final AccountsService _accounts;
  final SettingsService _settings;
  final WebDavService _webDav;

  /// Remote file name of the vault document (`WDMMCV01`).
  ///
  /// Renamed from `credentials.json`: the content is now a binary container, and
  /// a `.json` extension would be a lie that also makes a downgraded build fail
  /// with a parse error instead of a clear "unsupported kind". The old file is
  /// left on the server untouched (docs/10 §4.5) — deleting is irreversible and
  /// the stale file is harmless.
  static const fileName = 'credentials.wdmcv';
  static const format = 'webdav_media_manager_credentials';

  /// v2：新增云盘驱动条目（providerType + driverConfig，密文字段逐个加密）。
  /// v1 文件（只有 WebDAV 条目）按原语义读取。
  static const formatVersion = 2;

  bool busy = false;
  String? lastError;
  String? lastMessage;

  /// Passwords left empty by the last [pull] / [applyVault] because the vault
  /// was encrypted with a key we could not reproduce.
  final List<String> missingPasswordAccounts = [];

  String get remotePath {
    final root = _settings.syncRemoteRoot;
    return root.endsWith('/') ? '$root$fileName' : '$root/$fileName';
  }

  /// Build the vault records from the local account list.
  ///
  /// [passphrase] empty (or [encryptPassword] false) stores plaintext
  /// passwords — the same trust level as the old backup archives. Only fields
  /// the UI treats as secrets are ever encrypted; address fields stay readable
  /// so a vault without the key still identifies the accounts.
  Future<List<VaultRecord>> buildRecords({
    required String passphrase,
    bool? encryptPassword,
  }) async {
    final encrypt =
        (encryptPassword ?? _settings.syncEncryptPassword) &&
        passphrase.isNotEmpty;
    final entries = <VaultRecord>[];
    // 账号凭证库：WebDAV 三件套 + 云盘驱动配置。云盘条目的密文字段
    // （spec.secretFieldKeys）逐字段加密，地址类字段保持明文可辨识。
    for (final a in _accounts.accounts) {
      // 云盘条目走驱动配置通道（判 providerType 而非 isCloudType，防止
      // webdav 账号因 isCloudType=true 进错分支——webdav 用密码通道）。
      if (a.providerType != 'webdav') {
        final spec = wdmmVfsSpec(a.providerType);
        final raw = await _accounts.loadDriverConfig(a.id) ?? const {};
        final stored = <String, dynamic>{};
        for (final e in raw.entries) {
          final value = e.value;
          if (encrypt &&
              value is String &&
              value.isNotEmpty &&
              spec != null &&
              spec.secretFieldKeys.contains(e.key) &&
              !await _vaultIsEncrypted(value)) {
            stored[e.key] = await _vaultEncrypt(value, passphrase);
          } else {
            stored[e.key] = value;
          }
        }
        entries.add(
          VaultRecord(
            id: a.id,
            name: a.name,
            providerType: a.providerType,
            remotePath: a.remotePath,
            url: '',
            username: '',
            password: '',
            passwordEncrypted: false,
            driverConfig: stored,
          ),
        );
        continue;
      }
      final pass = await _accounts.passwordFor(a.id) ?? '';
      var stored = pass;
      var encrypted = false;
      if (encrypt && pass.isNotEmpty) {
        stored = await _vaultEncrypt(pass, passphrase);
        encrypted = true;
      }
      entries.add(
        VaultRecord(
          id: a.id,
          name: a.name,
          providerType: 'webdav',
          url: a.url,
          username: a.username,
          password: stored,
          passwordEncrypted: encrypted,
          remotePath: '/',
        ),
      );
    }
    return entries;
  }

  /// Whether the last [buildRecords] run encrypted anything.
  ///
  /// Kept as state so callers can report the same「已加密同步 / 明文同步」
  /// message the JSON form used to derive from its own payload.
  bool _lastBuildEncrypted = false;

  /// Build the vault records and remember whether encryption was applied.
  Future<List<VaultRecord>> buildRecordsTracked({
    required String passphrase,
    bool? encryptPassword,
  }) async {
    final encrypt =
        (encryptPassword ?? _settings.syncEncryptPassword) &&
        passphrase.isNotEmpty;
    _lastBuildEncrypted = encrypt;
    return buildRecords(
      passphrase: passphrase,
      encryptPassword: encryptPassword,
    );
  }

  /// Encode the current account list as one `WDMMCV01` document.
  ///
  /// The backup archive embeds **these exact bytes** (docs/10 §4.3), so the
  /// vault has a single encoding and two exits — the sync root and the archive
  /// can never drift apart. Deliberately free of side effects: [push] owns the
  /// sync status fields, and building a backup must not disturb them.
  Future<Uint8List> encodeVaultBytes({
    required String passphrase,
    bool? encryptPassword,
  }) async {
    final records = await buildRecords(
      passphrase: passphrase,
      encryptPassword: encryptPassword,
    );
    return _encodeRecords(records);
  }

  Uint8List _encodeRecords(List<VaultRecord> records) {
    final reply = _rustReply(
      RustCoreService.vaultEncode(
        jsonEncode({
          'device_id': '',
          'format_version': formatVersion,
          'records': [for (final record in records) record.toJson()],
        }),
      ),
      'vault encode',
    );
    final encoded = reply['bytes_base64'];
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException('vault encode returned no bytes');
    }
    return base64Decode(encoded);
  }

  /// Upload the vault to [accountId] (the credentials destination the user
  /// configured for this feature).
  Future<List<VaultRecord>> push({
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
      final records = await buildRecordsTracked(
        passphrase: passphrase,
        encryptPassword: encryptPassword,
      );
      final bytes = _encodeRecords(records);
      await _webDav.ensureDirectory(accountId, _settings.syncRemoteRoot);
      await _webDav.writeBytes(accountId, remotePath, bytes);
      lastMessage = _lastBuildEncrypted
          ? L10nHost.current.vaultSyncedEncrypted
          : L10nHost.current.vaultSyncedPlaintext;
      return records;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Download and decode the vault document from [accountId].
  ///
  /// Returns null when the file does not exist yet (nothing to pull).
  /// A file whose magic is not `WDMMCV01` throws — we never guess at a
  /// half-understood payload when the thing at stake is credentials.
  Future<DecodedVault?> fetchVault({required String accountId}) async {
    _requireAccount(accountId);
    try {
      final bytes = await _webDav.readAsBytes(accountId, remotePath);
      final reply = _rustReply(
        RustCoreService.vaultDecode(bytes),
        'vault decode',
      );
      final entries = <VaultRecord>[
        for (final record in (reply['records'] as List? ?? const []))
          if (record is Map)
            VaultRecord.fromJson(Map<String, dynamic>.from(record)),
      ];
      return DecodedVault(
        formatVersion: (reply['format_version'] as num?)?.toInt() ?? 1,
        deviceId: reply['device_id'] as String? ?? '',
        createdAt: reply['created_at'] as String? ?? '',
        entries: entries,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final missing =
          msg.contains('404') ||
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
      final vault = await fetchVault(accountId: accountId);
      if (vault == null) {
        lastMessage = L10nHost.current.vaultCloudNoFile(remotePath);
        return null;
      }
      final result = await applyVault(vault, passphrase: passphrase);
      lastMessage = L10nHost.current.vaultRestoredFromCloud(result.summary);
      return result;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Merge a decoded vault into the local account list.
  ///
  /// Other local accounts are never deleted, so a partial vault cannot wipe
  /// mounts that were added after the last upload. Entries whose
  /// providerType is not registered on this build are **silently skipped**
  /// (不支持的网盘类型：不报错、不建账号).
  Future<VaultApplyResult> applyVault(
    DecodedVault vault, {
    required String passphrase,
  }) async {
    missingPasswordAccounts.clear();
    var imported = 0;
    var updated = 0;
    var restored = 0;
    var missing = 0;
    var skippedUnknown = 0;
    for (final entry in vault.entries) {
      // 云盘条目走驱动配置通道；本机没有注册该类型时静默跳过。
      if (entry.isCloud) {
        final spec = wdmmVfsSpec(entry.providerType);
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
      if (entry.passwordEncrypted && await _vaultIsEncrypted(entry.password)) {
        final clear = await _vaultTryDecrypt(entry.password, passphrase);
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

      // Name is the logical identity; also accept id / url hits so re-pull
      // updates the same mount instead of creating a same-name twin.
      final existing = _accounts.accountById(entry.id) ??
          (entry.name.trim().isEmpty
              ? null
              : _accounts.accountNamed(entry.name)) ??
          _accounts.accounts.cast<WebDavAccount?>().firstWhere(
            (a) => a?.url == entry.url && entry.url.trim().isNotEmpty,
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
        final nextName =
            entry.name.isEmpty ? existing.name : entry.name;
        // If vault wants a name already used by a *different* row, keep local
        // name so uniqueness holds.
        final nameClash = _accounts.accountNamed(nextName, exceptId: existing.id);
        await _accounts.updateAccount(
          id: existing.id,
          name: nameClash == null ? nextName : existing.name,
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
    VaultRecord entry,
    String passphrase,
  ) async {
    final raw = entry.driverConfig ?? const <String, dynamic>{};
    final local =
        (await _accounts.loadDriverConfig(entry.id)) ??
        (await _accounts.loadDriverConfigByName(entry.name)) ??
        const <String, dynamic>{};
    final merged = <String, dynamic>{...local};
    var restoredSecrets = true;
    for (final e in raw.entries) {
      final value = e.value;
      if (value is String && await _vaultIsEncrypted(value)) {
        final clear = await _vaultTryDecrypt(value, passphrase);
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
        entry.name.isEmpty ? entry.providerType : entry.name,
      );
    }

    final existing = _accounts.accountById(entry.id) ??
        (entry.name.trim().isEmpty
            ? null
            : _accounts.accountNamed(entry.name));
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
    final nextName = entry.name.isEmpty ? existing.name : entry.name;
    final nameClash = _accounts.accountNamed(nextName, exceptId: existing.id);
    await _accounts.updateAccount(
      id: existing.id,
      name: nameClash == null ? nextName : existing.name,
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
      throw StateError('err.vaultDestNotConfigured');
    }
  }
}

/// One account entry inside the credential vault document (`WDMMCV01`).
///
/// The document is encoded and decoded by Rust (`wdmm_vault_encode` /
/// `wdmm_vault_decode`); this class is the Dart view of one record, not a
/// second implementation of the wire format.
class VaultRecord {
  const VaultRecord({
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
  final String providerType;

  /// Stored in **plain text** by design (WebDAV mount address).
  final String url;

  /// Stored in **plain text** by design.
  final String username;

  /// Plaintext password, or the `AESGCMv1:` blob when [passwordEncrypted].
  final String password;
  final bool passwordEncrypted;

  /// 云盘账号的远端路径（WebDAV 条目恒 '/'）。
  final String remotePath;

  /// 云盘驱动的配置；null = WebDAV 条目。密文字段带 `AESGCMv1:` 前缀。
  final Map<String, dynamic>? driverConfig;

  bool get isCloud => providerType != 'webdav';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'provider_type': providerType,
    'url': url,
    'username': username,
    'password': password,
    'password_encrypted': passwordEncrypted,
    'remote_path': remotePath,
    'driver_config': driverConfig,
  };

  factory VaultRecord.fromJson(Map<String, dynamic> json) => VaultRecord(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    providerType: json['provider_type'] as String? ?? 'webdav',
    url: json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    passwordEncrypted: json['password_encrypted'] as bool? ?? false,
    remotePath: json['remote_path'] as String? ?? '/',
    driverConfig: json['driver_config'] is Map
        ? Map<String, dynamic>.from(json['driver_config'] as Map)
        : null,
  );
}

/// One decoded `WDMMCV01` vault document.
class DecodedVault {
  const DecodedVault({
    required this.formatVersion,
    required this.deviceId,
    required this.createdAt,
    required this.entries,
  });

  final int formatVersion;
  final String deviceId;
  final String createdAt;
  final List<VaultRecord> entries;

  int get entryCount => entries.length;
}

/// Parse the JSON reply of an `ext::json_reply` handler.
///
/// Handlers answer `{"ok":true,...}` on success and `error:<msg>` on failure.
/// A null reply means the native library is not available at all.
Map<String, dynamic> _rustReply(String? raw, String what) {
  if (raw == null || raw.isEmpty) {
    throw StateError('err.rustUnavailable:$what');
  }
  if (raw.startsWith('error:')) {
    throw FormatException('$what failed: ${raw.substring('error:'.length)}');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw FormatException('$what returned invalid JSON');
  }
  if (decoded is! Map) {
    throw FormatException('$what returned a non-object reply');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (map['ok'] != true) {
    throw FormatException('$what failed: ${map['error'] ?? raw}');
  }
  return map;
}

/// Bridge to the Rust-owned `AESGCMv1:` field crypto.
///
/// The wire format and PBKDF2 work live in `wdmm_sync::vault_crypto`; the
/// helpers below only translate the JSON replies back into Dart values.
Future<bool> _vaultIsEncrypted(String value) async {
  final reply = await RustCoreService.vaultCryptoIsEncrypted(value);
  if (reply == null || reply.isEmpty) {
    throw StateError('err.rustUnavailable:vault crypto');
  }
  final decoded = jsonDecode(reply);
  if (decoded is! Map || decoded['ok'] != true) {
    throw FormatException('vault crypto is_encrypted failed: $reply');
  }
  return decoded['encrypted'] == true;
}

Future<String?> _vaultTryDecrypt(String value, String passphrase) async {
  final reply = await RustCoreService.vaultCryptoDecrypt(value, passphrase);
  if (reply == null || reply.isEmpty) {
    throw StateError('err.rustUnavailable:vault crypto');
  }
  final decoded = jsonDecode(reply);
  if (decoded is! Map) {
    throw FormatException('vault crypto decrypt failed: $reply');
  }
  if (decoded['ok'] == true) {
    return decoded['plaintext'] as String?;
  }
  if (decoded['reason'] == 'damaged') {
    throw FormatException(L10nHost.current.vaultCiphertextDamaged);
  }
  return null;
}

Future<String> _vaultEncrypt(String plaintext, String passphrase) async {
  final reply = await RustCoreService.vaultCryptoEncrypt(plaintext, passphrase);
  if (reply == null || reply.isEmpty) {
    throw StateError('err.rustUnavailable:vault crypto');
  }
  final decoded = jsonDecode(reply);
  if (decoded is! Map || decoded['ok'] != true) {
    throw FormatException('vault crypto encrypt failed: $reply');
  }
  return decoded['value'] as String;
}
