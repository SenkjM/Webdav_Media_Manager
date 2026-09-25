import 'dart:typed_data';

import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:test/test.dart';

void main() {
  group('deriveKeyMaterial', () {
    test('async derivation matches sync byte-for-byte', () async {
      final sync = deriveKeyMaterialSync(password: 'testpass', salt: 'testsalt');
      final async = await deriveKeyMaterial(password: 'testpass', salt: 'testsalt');
      expect(async, equals(sync));
      expect(sync.length, kKeyMaterialLength);
    });

    test('empty password yields zero key material (rclone format detail)', () {
      expect(
        deriveKeyMaterialSync(password: '', salt: 'anything'),
        equals(Uint8List(kKeyMaterialLength)),
      );
    });

    test('distinct salt / password change the material', () {
      final a = deriveKeyMaterialSync(password: 'p', salt: 's1');
      final b = deriveKeyMaterialSync(password: 'p', salt: 's2');
      final c = deriveKeyMaterialSync(password: 'q', salt: 's1');
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });
  });

  group('RcloneCipher.fromKeyMaterial', () {
    test('behaves exactly like the deriving constructor', () async {
      final material = await deriveKeyMaterial(password: 'testpass', salt: 'testsalt');
      final derived = RcloneCipher(
        password: 'testpass',
        salt: 'testsalt',
        mode: NameEncryptionMode.standard,
        dirNameEncrypt: true,
      );
      final rebuilt = RcloneCipher.fromKeyMaterial(
        material,
        mode: NameEncryptionMode.standard,
        dirNameEncrypt: true,
      );

      for (final name in ['hello.txt', 'sub dir', 'a-very-long-file-name.mp4']) {
        expect(rebuilt.encryptFileName(name), derived.encryptFileName(name));
        expect(rebuilt.encryptDirName(name), derived.encryptDirName(name));
      }
      final plain = Uint8List.fromList(List<int>.generate(200000, (i) => i % 251));
      final sealed = derived.encrypt(plain, nonce: Uint8List(24));
      expect(rebuilt.decrypt(sealed), equals(plain));
    });

    test('honours name encoding / mode carried by the caller', () {
      final material = deriveKeyMaterialSync(password: 'p', salt: 's');
      final b64 = RcloneCipher.fromKeyMaterial(material, nameEncoding: 'base64');
      final b32 = RcloneCipher.fromKeyMaterial(material, nameEncoding: 'base32');
      expect(b64.encryptFileName('hello.txt'), isNot(b32.encryptFileName('hello.txt')));
      expect(b64.decryptFileName(b64.encryptFileName('hello.txt')), 'hello.txt');
      expect(b32.decryptFileName(b32.encryptFileName('hello.txt')), 'hello.txt');
    });

    test('rejects a material buffer of the wrong length', () {
      expect(
        () => RcloneCipher.fromKeyMaterial(Uint8List(79)),
        throwsA(isA<RcloneCipherException>()),
      );
    });
  });
}
