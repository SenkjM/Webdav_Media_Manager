import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/rust_core_service.dart';
import 'credential_vault_crypto.dart';

/// Result of probing a backup archive's passphrase **before** writing the DB.
///
/// The verdict comes from Rust (`wdmm_backup_probe`): Dart no longer implements
/// the `WDMMBK01` container, the `WDMMEN01` envelope, or PBKDF2/GCM. A wrong
/// outer envelope key and a failed field-level pass-check both arrive as
/// [mismatched].
enum BackupPassphraseProbe {
  /// Nothing to verify (unprotected archive or unreadable bytes) — proceed.
  notNeeded,

  /// Rust opened the archive and every stored check passed.
  matched,

  /// The archive opened (or claims) encryption but the passphrase is wrong.
  /// UI offers cancel / force-continue; force may leave secret fields empty.
  mismatched,
}

/// Verifiable passphrase canary for backup archives.
///
/// New archives store an `AESGCMv1:` blob of [plainToken] under the
/// pass-check section (binary) or top-level `passCheck` (JSON export). Restore
/// probes it in Rust before applying the payload so a wrong key does not
/// silently empty credential fields.
class BackupPassCheck {
  BackupPassCheck._();

  /// Known plaintext sealed into the check block. Changing it breaks
  /// verification of archives written with the previous token — bump the
  /// trailing version digit if you ever must rotate. Must stay in sync with
  /// `PASS_CHECK_PLAIN` in `wdmm-sync/src/backup.rs`.
  static const plainToken = 'WDMM-BACKUP-PASS-OK\u0001';

  /// Build the `AESGCMv1:…` canary for [passphrase].
  static Future<String> create(String passphrase) {
    return CredentialVaultCrypto.encrypt(
      plaintext: plainToken,
      passphrase: passphrase,
    );
  }

  /// Probe [data] without writing the database.
  ///
  /// Rust receives a temp-file copy of the raw bytes and answers
  /// `{"ok":true,"valid":…,"version":…,"created_at":…,"reason":…}`.
  static Future<BackupPassphraseProbe> probe({
    required Uint8List data,
    required String passphrase,
  }) async {
    final reply = await _probeWithCore(data, passphrase);
    if (reply == null) return BackupPassphraseProbe.notNeeded;
    if (reply['valid'] == true) return BackupPassphraseProbe.matched;
    return switch (reply['reason']) {
      'bad-passphrase' => BackupPassphraseProbe.mismatched,
      // `not-backup` (a readable JSON export / unknown file) has nothing to verify.
      _ => BackupPassphraseProbe.notNeeded,
    };
  }

  static Future<Map<String, dynamic>?> _probeWithCore(
    Uint8List data,
    String passphrase,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      p.join(
        tempDir.path,
        'backup_probe_${DateTime.now().microsecondsSinceEpoch}.bin',
      ),
    );
    try {
      await tempFile.writeAsBytes(data, flush: true);
      final raw = RustCoreService.backupProbe(tempFile.path, passphrase);
      if (raw == null || raw.startsWith('error:')) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      // Core probe unavailable (old `.so`) — never block a restore on the probe.
      return null;
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }
}
