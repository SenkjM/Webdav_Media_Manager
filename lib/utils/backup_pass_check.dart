import 'dart:convert';
import 'dart:typed_data';

import '../services/credential_vault_codec.dart';
import 'backup_crypto.dart';
import 'credential_vault_crypto.dart';
import 'wmp_container.dart';

/// Result of probing a backup archive's passphrase **before** writing the DB.
enum BackupPassphraseProbe {
  /// Archive carries no encryption (outer envelope, check block, or field ciphertext).
  notNeeded,

  /// Passphrase verified (outer GCM and/or check block / sample ciphertext).
  matched,

  /// Archive needs a passphrase but it is empty or failed verification.
  mismatched,

  /// Encryption is claimed (or likely) but there is no check block and no
  /// sample ciphertext to try — typically an old archive. UI should say
  /// 「无法预检」and offer cancel / force-continue.
  unverifiable,
}

/// Verifiable passphrase canary for backup archives.
///
/// New archives store an [AESGCMv1] blob of [plainToken] under
/// [WmpSections.passCheck] (binary) or top-level `passCheck` (JSON export).
/// Restore probes it before applying the payload so a wrong key does not
/// silently empty credential fields.
class BackupPassCheck {
  BackupPassCheck._();

  /// Known plaintext sealed into the check block. Changing it breaks
  /// verification of archives written with the previous token — bump the
  /// trailing version digit if you ever must rotate.
  static const plainToken = 'WDMM-BACKUP-PASS-OK\u0001';

  /// Build the `AESGCMv1:…` canary for [passphrase].
  static Future<String> create(String passphrase) {
    return CredentialVaultCrypto.encrypt(
      plaintext: plainToken,
      passphrase: passphrase,
    );
  }

  /// True when [encoded] decrypts to [plainToken] with [passphrase].
  static Future<bool> verify(String encoded, String passphrase) async {
    if (passphrase.isEmpty || !CredentialVaultCrypto.isEncrypted(encoded)) {
      return false;
    }
    final plain = await CredentialVaultCrypto.tryDecrypt(
      encoded: encoded,
      passphrase: passphrase,
    );
    return plain == plainToken;
  }

  /// Probe [data] without writing anything.
  ///
  /// Order: outer `WDMMEN01` envelope → pass-check section / JSON field →
  /// sample `AESGCMv1:` credential ciphertext → META / JSON
  /// `passwordEncryption` claim → [BackupPassphraseProbe.notNeeded].
  static Future<BackupPassphraseProbe> probe({
    required Uint8List data,
    required String passphrase,
  }) async {
    Uint8List body = data;

    if (BackupCrypto.looksEncrypted(data)) {
      if (passphrase.isEmpty) return BackupPassphraseProbe.mismatched;
      try {
        body = await BackupCrypto.decrypt(data: data, passphrase: passphrase);
      } catch (_) {
        return BackupPassphraseProbe.mismatched;
      }
      // Outer GCM auth already proves the key. Still prefer the inner check
      // when present (defence in depth / future unwrapped copies).
      final inner = await _probeReadable(body, passphrase);
      if (inner == BackupPassphraseProbe.mismatched) {
        return BackupPassphraseProbe.mismatched;
      }
      return BackupPassphraseProbe.matched;
    }

    return _probeReadable(body, passphrase);
  }

  static Future<BackupPassphraseProbe> _probeReadable(
    Uint8List body,
    String passphrase,
  ) async {
    if (WmpContainer.looksLikeContainer(body)) {
      return _probeContainer(body, passphrase);
    }
    return _probeJson(body, passphrase);
  }

  static Future<BackupPassphraseProbe> _probeContainer(
    Uint8List body,
    String passphrase,
  ) async {
    late final WmpContainer container;
    try {
      container = WmpContainer.fromBytes(body);
    } catch (_) {
      return BackupPassphraseProbe.notNeeded;
    }

    final checkRaw = container.readSection(WmpSections.passCheck);
    if (checkRaw != null && checkRaw.isNotEmpty) {
      final token = utf8.decode(checkRaw);
      if (passphrase.isEmpty) return BackupPassphraseProbe.mismatched;
      final ok = await verify(token, passphrase);
      return ok
          ? BackupPassphraseProbe.matched
          : BackupPassphraseProbe.mismatched;
    }

    final sample = _sampleFromCredentialsSection(
      container.readSection(WmpSections.credentials),
    );
    if (sample != null) {
      if (passphrase.isEmpty) return BackupPassphraseProbe.mismatched;
      final plain = await CredentialVaultCrypto.tryDecrypt(
        encoded: sample,
        passphrase: passphrase,
      );
      return plain != null
          ? BackupPassphraseProbe.matched
          : BackupPassphraseProbe.mismatched;
    }

    if (_metaClaimsEncryption(container)) {
      return BackupPassphraseProbe.unverifiable;
    }
    return BackupPassphraseProbe.notNeeded;
  }

  static Future<BackupPassphraseProbe> _probeJson(
    Uint8List body,
    String passphrase,
  ) async {
    late final Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) return BackupPassphraseProbe.notNeeded;
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return BackupPassphraseProbe.notNeeded;
    }

    final check = map['passCheck'];
    if (check is String && check.isNotEmpty) {
      if (passphrase.isEmpty) return BackupPassphraseProbe.mismatched;
      final ok = await verify(check, passphrase);
      return ok
          ? BackupPassphraseProbe.matched
          : BackupPassphraseProbe.mismatched;
    }

    final sample = _sampleFromJsonPayload(map);
    if (sample != null) {
      if (passphrase.isEmpty) return BackupPassphraseProbe.mismatched;
      final plain = await CredentialVaultCrypto.tryDecrypt(
        encoded: sample,
        passphrase: passphrase,
      );
      return plain != null
          ? BackupPassphraseProbe.matched
          : BackupPassphraseProbe.mismatched;
    }

    if (map['passwordEncryption'] == 'aes-256-gcm') {
      return BackupPassphraseProbe.unverifiable;
    }
    return BackupPassphraseProbe.notNeeded;
  }

  static bool _metaClaimsEncryption(WmpContainer container) {
    final metaRaw = container.readSection(WmpSections.meta);
    if (metaRaw == null || metaRaw.isEmpty) return false;
    try {
      final records = decodeRecords(metaRaw, intTags: kMetaIntTags);
      final meta = records.isEmpty ? const <int, Object?>{} : records.first;
      final noteRaw = meta[WmpMeta.note];
      if (noteRaw is! String || noteRaw.isEmpty) return false;
      final decoded = jsonDecode(noteRaw);
      if (decoded is! Map) return false;
      return decoded['passwordEncryption'] == 'aes-256-gcm';
    } catch (_) {
      return false;
    }
  }

  static String? _sampleFromCredentialsSection(Uint8List? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final vault = CredentialVaultCodec.decode(raw);
      return firstEncryptedSecret(vault);
    } catch (_) {
      return null;
    }
  }

  static String? _sampleFromJsonPayload(Map<String, dynamic> map) {
    final credentials = map['credentials'];
    if (credentials is! Map) return null;
    final accounts = credentials['accounts'];
    if (accounts is! List) return null;
    for (final item in accounts) {
      if (item is! Map) continue;
      final password = item['password'];
      if (password is String && CredentialVaultCrypto.isEncrypted(password)) {
        return password;
      }
      final cfg = item['driverConfig'];
      if (cfg is Map) {
        for (final value in cfg.values) {
          if (value is String && CredentialVaultCrypto.isEncrypted(value)) {
            return value;
          }
        }
      }
    }
    return null;
  }

  /// First `AESGCMv1:` value in a decoded vault (password or driver secret).
  static String? firstEncryptedSecret(DecodedVault vault) {
    for (final entry in vault.entries) {
      if (CredentialVaultCrypto.isEncrypted(entry.password)) {
        return entry.password;
      }
      final cfg = entry.driverConfig;
      if (cfg == null) continue;
      for (final value in cfg.values) {
        if (value is String && CredentialVaultCrypto.isEncrypted(value)) {
          return value;
        }
      }
    }
    return null;
  }
}
