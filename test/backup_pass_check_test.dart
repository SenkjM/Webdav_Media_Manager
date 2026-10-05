import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/credential_vault_codec.dart';
import 'package:webdav_media_manager/utils/backup_crypto.dart';
import 'package:webdav_media_manager/utils/backup_pass_check.dart';
import 'package:webdav_media_manager/utils/credential_vault_crypto.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';

Uint8List _jsonBytes(Map<String, dynamic> map) =>
    Uint8List.fromList(utf8.encode(jsonEncode(map)));

Uint8List _backupWithPassCheck(String checkToken, {String? passwordEncryption}) {
  return WmpContainer.encode(
    {
      WmpSections.meta: encodeRecords([
        {
          WmpMeta.kind: WmpKind.backup,
          WmpMeta.count: 0,
          WmpMeta.deviceId: 'dev',
          WmpMeta.createdAt: '2026-10-06T00:00:00Z',
          WmpMeta.note: jsonEncode({
            'format': 'webdav_media_manager_backup',
            'formatVersion': 6,
            'passwordEncryption': passwordEncryption ?? 'aes-256-gcm',
            'hasPassCheck': true,
          }),
        },
      ]),
      WmpSections.tracks: encodeRecords(const []),
      WmpSections.passCheck: Uint8List.fromList(utf8.encode(checkToken)),
    },
    kind: WmpFileKind.backup,
  );
}

Uint8List _legacyBackupWithEncryptedPassword(String encryptedPassword) {
  final vault = CredentialVaultCodec.encode(
    [
      VaultRecord(
        id: 'acc-1',
        name: 'nas',
        providerType: 'webdav',
        url: 'https://example.com',
        username: 'u',
        password: encryptedPassword,
        passwordEncrypted: true,
        remotePath: '/',
      ),
    ],
    formatVersion: 2,
    deviceId: 'dev',
  );
  return WmpContainer.encode(
    {
      WmpSections.meta: encodeRecords([
        {
          WmpMeta.kind: WmpKind.backup,
          WmpMeta.count: 0,
          WmpMeta.deviceId: 'dev',
          WmpMeta.createdAt: '2026-10-06T00:00:00Z',
          WmpMeta.note: jsonEncode({
            'format': 'webdav_media_manager_backup',
            'formatVersion': 5,
            'passwordEncryption': 'aes-256-gcm',
          }),
        },
      ]),
      WmpSections.tracks: encodeRecords(const []),
      WmpSections.credentials: vault,
    },
    kind: WmpFileKind.backup,
    rawIds: {WmpSections.credentials},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupPassCheck', () {
    test('create/verify round-trip', () async {
      final token = await BackupPassCheck.create('secret');
      expect(CredentialVaultCrypto.isEncrypted(token), isTrue);
      expect(await BackupPassCheck.verify(token, 'secret'), isTrue);
      expect(await BackupPassCheck.verify(token, 'wrong'), isFalse);
      expect(await BackupPassCheck.verify(token, ''), isFalse);
    });

    test('probe: unencrypted archive → notNeeded', () async {
      final plain = WmpContainer.encode(
        {
          WmpSections.meta: encodeRecords([
            {
              WmpMeta.kind: WmpKind.backup,
              WmpMeta.count: 0,
              WmpMeta.note: jsonEncode({
                'format': 'webdav_media_manager_backup',
                'formatVersion': 6,
                'passwordEncryption': 'none',
              }),
            },
          ]),
          WmpSections.tracks: encodeRecords(const []),
        },
        kind: WmpFileKind.backup,
      );
      expect(
        await BackupPassCheck.probe(data: plain, passphrase: ''),
        BackupPassphraseProbe.notNeeded,
      );
      expect(
        await BackupPassCheck.probe(data: plain, passphrase: 'anything'),
        BackupPassphraseProbe.notNeeded,
      );
    });

    test('probe: check block matched / mismatched / empty', () async {
      final token = await BackupPassCheck.create('right');
      final archive = _backupWithPassCheck(token);
      expect(
        await BackupPassCheck.probe(data: archive, passphrase: 'right'),
        BackupPassphraseProbe.matched,
      );
      expect(
        await BackupPassCheck.probe(data: archive, passphrase: 'wrong'),
        BackupPassphraseProbe.mismatched,
      );
      expect(
        await BackupPassCheck.probe(data: archive, passphrase: ''),
        BackupPassphraseProbe.mismatched,
      );
    });

    test('probe: outer envelope matched / mismatched', () async {
      final token = await BackupPassCheck.create('right');
      final inner = _backupWithPassCheck(token);
      final enc = await BackupCrypto.encrypt(
        plaintext: inner,
        passphrase: 'right',
      );
      expect(
        await BackupPassCheck.probe(data: enc, passphrase: 'right'),
        BackupPassphraseProbe.matched,
      );
      expect(
        await BackupPassCheck.probe(data: enc, passphrase: 'wrong'),
        BackupPassphraseProbe.mismatched,
      );
      expect(
        await BackupPassCheck.probe(data: enc, passphrase: ''),
        BackupPassphraseProbe.mismatched,
      );
    });

    test('probe: legacy archive tries credential ciphertext', () async {
      final encPass = await CredentialVaultCrypto.encrypt(
        plaintext: 'webdav-secret',
        passphrase: 'right',
      );
      final archive = _legacyBackupWithEncryptedPassword(encPass);
      expect(
        await BackupPassCheck.probe(data: archive, passphrase: 'right'),
        BackupPassphraseProbe.matched,
      );
      expect(
        await BackupPassCheck.probe(data: archive, passphrase: 'wrong'),
        BackupPassphraseProbe.mismatched,
      );
    });

    test('probe: claimed encryption but nothing to try → unverifiable', () async {
      final archive = WmpContainer.encode(
        {
          WmpSections.meta: encodeRecords([
            {
              WmpMeta.kind: WmpKind.backup,
              WmpMeta.count: 0,
              WmpMeta.note: jsonEncode({
                'format': 'webdav_media_manager_backup',
                'formatVersion': 5,
                'passwordEncryption': 'aes-256-gcm',
              }),
            },
          ]),
          WmpSections.tracks: encodeRecords(const []),
        },
        kind: WmpFileKind.backup,
      );
      expect(
        await BackupPassCheck.probe(data: archive, passphrase: 'x'),
        BackupPassphraseProbe.unverifiable,
      );
    });

    test('probe: JSON export with passCheck', () async {
      final token = await BackupPassCheck.create('right');
      final bytes = _jsonBytes({
        'format': 'webdav_media_manager_sync',
        'formatVersion': 6,
        'passwordEncryption': 'aes-256-gcm',
        'passCheck': token,
        'hasPassCheck': true,
        'credentials': {'accounts': []},
      });
      expect(
        await BackupPassCheck.probe(data: bytes, passphrase: 'right'),
        BackupPassphraseProbe.matched,
      );
      expect(
        await BackupPassCheck.probe(data: bytes, passphrase: 'wrong'),
        BackupPassphraseProbe.mismatched,
      );
    });
  });
}
