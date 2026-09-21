import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/utils/credential_vault_crypto.dart';

void main() {
  group('CredentialVaultCrypto', () {
    test('round-trips a password', () async {
      final blob = await CredentialVaultCrypto.encrypt(
        plaintext: 'sup3r-secret',
        passphrase: 'correct horse',
      );
      expect(CredentialVaultCrypto.isEncrypted(blob), isTrue);
      expect(blob, startsWith(CredentialVaultCrypto.prefix));
      expect(blob.contains('sup3r-secret'), isFalse);
      final clear = await CredentialVaultCrypto.decrypt(
        encoded: blob,
        passphrase: 'correct horse',
      );
      expect(clear, 'sup3r-secret');
    });

    test('plaintext values pass through decrypt unchanged', () async {
      expect(
        await CredentialVaultCrypto.decrypt(
          encoded: 'plain-pass',
          passphrase: 'anything',
        ),
        'plain-pass',
      );
    });

    test('tryDecrypt returns null for a wrong passphrase', () async {
      final blob = await CredentialVaultCrypto.encrypt(
        plaintext: 'secret',
        passphrase: 'right',
      );
      expect(
        await CredentialVaultCrypto.tryDecrypt(
          encoded: blob,
          passphrase: 'wrong',
        ),
        isNull,
      );
      expect(
        await CredentialVaultCrypto.tryDecrypt(encoded: blob, passphrase: ''),
        isNull,
      );
    });

    test('two encryptions of the same value differ (random salt)', () async {
      final a = await CredentialVaultCrypto.encrypt(
        plaintext: 'x',
        passphrase: 'p',
      );
      final b = await CredentialVaultCrypto.encrypt(
        plaintext: 'x',
        passphrase: 'p',
      );
      expect(a == b, isFalse);
    });
  });
}
