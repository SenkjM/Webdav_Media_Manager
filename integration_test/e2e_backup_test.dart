import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/providers/app_state.dart';
import 'package:webdav_media_manager/services/accounts_service.dart';
import 'package:webdav_media_manager/services/backup_service.dart';
import 'package:webdav_media_manager/services/rust_core_service.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/backup_pass_check.dart';

import 'e2e_support.dart';

/// Backup module: the Core archive is real bytes (correct magic), it uploads to
/// the WebDAV root the sync layout derives, the remote list/download reads it
/// back byte-identical enough to probe the passphrase, and a restore actually
/// applies the archive's data (a KV probe set before create comes back after a
/// mutation). Wrong or missing passphrases are refused instead of silently
/// writing an empty restore.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('backup: archive create, upload, list, probe, restore round trip',
      (tester) async {
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    await bootApp(tester);
    ensureE2eAccount();

    final settings = appService<SettingsService>(tester);
    final accounts = appService<AccountsService>(tester);
    final backup = appService<BackupService>(tester);

    // `ensureE2eAccount` only writes the account into the Rust core; reload the
    // Dart mirror and register the client routes (`WebDavService.hasAccount`
    // gates `uploadBackup` on that registration).
    await accounts.init();
    await appService<AppState>(tester).registerAllAccounts();

    final account = accounts.accountForSource(e2eAccountName);
    expect(account, isNotNull, reason: 'the e2e account is missing');

    // The lab root is fixed (shared with the sync suite): the account's file
    // source is writable below it and it stays applied after the run so the
    // module never has to be re-seeded by hand.
    await settings.setSyncRemoteRoot('/WDMM');

    const passphrase = 'e2e-backup-passphrase';
    const probeKey = 'e2e_backup_probe';
    const root = '/WDMM/';
    const probeDir = '${root}backup/e2e/';
    const probeTrack = 'e2e-backup-probe';
    const name = 'e2e_backup.wdmm';
    const remoteName = 'e2e_backup_webdav.wdmm';

    try {
      // 1) Archive bytes belong to the documented container formats.
      final encrypted = await backup.createArchiveBytes(passphrase: passphrase);
      expect(encrypted.length, greaterThan(64));
      expect(ascii.decode(encrypted.sublist(0, 8)), 'WDMMEN01',
          reason: 'a passphrase archive must be the encrypted envelope');
      final plain = await backup.createArchiveBytes(passphrase: '');
      expect(ascii.decode(plain.sublist(0, 8)), 'WDMMBK01',
          reason: 'no passphrase must produce the plain container');

      // 2) The destination the page shows is the backup root.
      expect(settings.backupRemotePath, startsWith(root),
          reason: 'the backup root must be derived from the sync root');

      // 3) Upload: writes the picked name plus the stable latest copy.
      await backup.uploadBackup(
        accountId: account!.id,
        passphrase: passphrase,
        remoteDir: probeDir,
        fileName: name,
      );
      expect(backup.lastError, isNull, reason: 'upload failed: ${backup.lastError}');
      final listed = await backup.listBackups(
        accountId: account.id,
        remoteDir: probeDir,
      );
      expect(listed, contains(name));
      expect(listed, contains(BackupService.defaultFileName));

      // 4) Download reads the archive back and its passphrase can be probed.
      final remote = await backup.downloadBackupBytes(
        accountId: account.id,
        remoteDir: probeDir,
        fileName: name,
      );
      expect(remote.length, greaterThan(64));
      expect(ascii.decode(remote.sublist(0, 8)), 'WDMMEN01');
      expect(
        await BackupService.probePassphrase(
            data: remote, passphrase: passphrase),
        BackupPassphraseProbe.matched,
      );
      expect(
        await BackupService.probePassphrase(data: remote, passphrase: 'wrong'),
        BackupPassphraseProbe.mismatched,
      );

      // 5) Restore applies archive data: a KV probe set before the archive is
      //    captured, mutated afterwards, and must come back after restore.
      final before = RustCoreService.kvSet(probeKey, probeTrack);
      expect(before, 'ok');
      final withProbe = await backup.createArchiveBytes(passphrase: passphrase);
      RustCoreService.kvSet(probeKey, 'mutated');
      await backup.restoreFromBytes(data: withProbe, passphrase: passphrase);
      expect(backup.lastError, isNull,
          reason: 'restore failed: ${backup.lastError}');
      expect(backup.lastMessage, isNotNull);
      expect(RustCoreService.kvGet(probeKey), probeTrack,
          reason: 'the restored settings must be the archive contents');

      // 6) A wrong passphrase must be refused, not applied.
      Object? failure;
      try {
        await backup.restoreFromBytes(data: withProbe, passphrase: 'wrong');
      } catch (e) {
        failure = e;
      }
      expect(failure, isNotNull,
          reason: 'a wrong passphrase must not restore the archive');
      expect('$failure', contains('decrypt failed'),
          reason: 'the failure must name the decryption step: $failure');

      // 7) A missing passphrase on an encrypted archive is its own error.
      Object? missing;
      try {
        await backup.restoreFromBytes(data: withProbe, passphrase: '');
      } catch (e) {
        missing = e;
      }
      expect('$missing', contains('err.backupEncryptedNeedPassphrase'));

      // 8) The real WebDAV path: upload an archive that carries a fresh probe,
      //    download it back, and restore it over a mutated database.
      const remoteValue = 'restored-from-webdav';
      RustCoreService.kvSet(probeKey, remoteValue);
      await backup.uploadBackup(
        accountId: account.id,
        passphrase: passphrase,
        remoteDir: probeDir,
        fileName: remoteName,
      );
      final uploaded = await backup.downloadBackupBytes(
        accountId: account.id,
        remoteDir: probeDir,
        fileName: remoteName,
      );
      RustCoreService.kvSet(probeKey, 'mutated-again');
      await backup.restoreFromBytes(data: uploaded, passphrase: passphrase);
      expect(RustCoreService.kvGet(probeKey), remoteValue,
          reason: 'the archive downloaded from WebDAV must restore its data');

      debugPrint('[E2E] backup ok: dir=$probeDir size=${remote.length} '
          'listed=${listed.length}');
    } finally {
      // Archives stay in ${root}backup/e2e/: the folder is the lab fixture,
      // overwritten by the next run instead of being wiped after this one.
      try {
        RustCoreService.kvDelete(probeKey);
      } catch (_) {
        // cleanup path
      }
    }
  });
}
