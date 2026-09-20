import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/utils/backup_crypto.dart';

void main() {
  test('encrypt/decrypt round-trip', () async {
    final plain = Uint8List.fromList(utf8.encode('hello backup secrets'));
    final enc = await BackupCrypto.encrypt(
      plaintext: plain,
      passphrase: 'test-pass',
    );
    expect(BackupCrypto.looksEncrypted(enc), isTrue);
    final dec = await BackupCrypto.decrypt(
      data: enc,
      passphrase: 'test-pass',
    );
    expect(utf8.decode(dec), 'hello backup secrets');
  });

  test('wrong passphrase throws', () async {
    final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
    final enc = await BackupCrypto.encrypt(
      plaintext: plain,
      passphrase: 'right',
    );
    await expectLater(
      BackupCrypto.decrypt(data: enc, passphrase: 'wrong'),
      throwsA(anything),
    );
  });

  test('plain zip is not looksEncrypted', () {
    final zipish = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]);
    expect(BackupCrypto.looksEncrypted(zipish), isFalse);
  });
}
