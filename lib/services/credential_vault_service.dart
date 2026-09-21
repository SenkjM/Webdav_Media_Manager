import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/webdav_account.dart';
import '../utils/credential_vault_crypto.dart';
import 'accounts_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// One account entry inside the WebDAV credential vault.
class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.passwordEncrypted,
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

  bool get isActive => false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'passwordEncrypted': passwordEncrypted,
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? json['url'] as String? ?? '服务器',
        url: json['url'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        passwordEncrypted: json['passwordEncrypted'] as bool? ??
            CredentialVaultCrypto.isEncrypted(json['password'] as String?),
      );
}

/// Result of applying a vault to the local account list.
class VaultApplyResult {
  const VaultApplyResult({
    required this.imported,
    required this.updated,
    required this.passwordsRestored,
    required this.passwordsMissing,
  });

  final int imported;
  final int updated;

  /// Accounts whose password could be decrypted (or was plaintext).
  final int passwordsRestored;

  /// Accounts whose password stayed empty because no matching key was given.
  final int passwordsMissing;

  bool get hasMissingPasswords => passwordsMissing > 0;

  String get summary =>
      '账号：新增 $imported，更新 $updated；'
      '密码恢复 $passwordsRestored，'
      '留空 $passwordsMissing${hasMissingPasswords ? '（缺少统一解密密钥，可稍后手动填写）' : ''}';
}

/// WebDAV credential vault stored **on the WebDAV cloud**.
///
/// Layout under [SettingsService.syncRemoteRoot]:
/// * `credentials.json` — account list with **plaintext URL + username** and
///   either an encrypted (`AESGCMv1:`) or plaintext password.
///
/// Only the password is ever encrypted, which is what makes recovery possible
/// without the passphrase: URL/username still identify the mount, and the
/// password is simply left empty until the user types it in.
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
  static const format = 'webdav_music_player_credentials';
  static const formatVersion = 1;

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
    for (final a in _accounts.accounts) {
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
      entries.add({
        'id': a.id,
        'name': a.name,
        'url': a.url,
        'username': a.username,
        'password': stored,
        'passwordEncrypted': encrypted,
      });
    }
    return {
      'format': format,
      'formatVersion': formatVersion,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'activeAccountId': _accounts.activeAccountId,
      'passwordEncryption': encrypt ? 'aes-256-gcm' : 'none',
      'note': encrypt
          ? '仅密码被加密（AES-256-GCM）；地址与用户名为明文，便于识别站点。'
          : '密码为明文存储（未启用加密）。',
      'accountCount': entries.length,
      'accounts': entries,
    };
  }

  /// Upload the vault to the connected WebDAV server.
  Future<Map<String, dynamic>> push({
    required String passphrase,
    bool? encryptPassword,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      _requireConnection();
      final json = await buildJson(
        passphrase: passphrase,
        encryptPassword: encryptPassword,
      );
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
      );
      await _webDav.ensureDirectory(_settings.syncRemoteRoot);
      await _webDav.writeBytes(remotePath, bytes);
      lastMessage = (json['passwordEncryption'] == 'aes-256-gcm')
          ? '凭证已同步到云端（密码已加密）'
          : '凭证已同步到云端（明文密码）';
      return json;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Download the vault JSON from the connected WebDAV server.
  ///
  /// Returns null when the file does not exist yet (nothing to pull).
  Future<Map<String, dynamic>?> fetchJson() async {
    _requireConnection();
    try {
      final bytes = await _webDav.readAsBytes(remotePath);
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
  Future<VaultApplyResult?> pull({required String passphrase}) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      final json = await fetchJson();
      if (json == null) {
        lastMessage = '云端暂无凭证文件（$remotePath），已跳过';
        return null;
      }
      final result = await applyJson(json, passphrase: passphrase);
      lastMessage = '已从云端恢复凭证：${result.summary}';
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
  /// mounts that were added after the last upload.
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
    for (final raw in list) {
      if (raw is! Map) continue;
      final entry = VaultEntry.fromJson(Map<String, dynamic>.from(raw));
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
    );
  }

  void _requireConnection() {
    if (!_webDav.isConnected) {
      throw StateError('请先连接 WebDAV 账号');
    }
  }
}
