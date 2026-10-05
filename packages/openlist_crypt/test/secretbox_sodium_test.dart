import 'dart:typed_data';

import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:test/test.dart';

Uint8List hexDecode(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexEncode(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  tearDown(() {
    preferDartSecretbox();
  });

  test('Dart secretbox still matches NaCl reference vector', () {
    preferDartSecretbox();
    final key = Uint8List.fromList(List.filled(32, 1));
    final nonce = Uint8List.fromList(List.filled(24, 2));
    final message = Uint8List.fromList(List.filled(64, 3));
    final expected = hexDecode(
        '8442bc313f4626f1359e3b50122b6ce6fe66ddfe7d39d14e637eb4fd5b45bead'
        'ab55198df6ab5368439792a23c87db70acb6156dc5ef957ac04f6276cf6093b'
        '84be77ff0849cc33e34b7254d5a8f65ad');
    expect(hexEncode(secretboxSeal(message, nonce, key)), hexEncode(expected));
    expect(hexEncode(secretboxOpen(expected, nonce, key)!), hexEncode(message));
  });

  test('libsodium load is optional on host without Android jniLibs', () {
    // Box Linux may have system libsodium; Android device has packaged .so.
    final loaded = tryLoadLibsodium(forceReload: true);
    // Soft assertion: either loads or reports an error string.
    if (!loaded) {
      expect(libsodiumLoadError, isNotNull);
      expect(libsodiumSecretboxReady, isFalse);
    } else {
      expect(libsodiumSecretboxReady, isTrue);
      expect(libsodiumVersionString(), isNotNull);
    }
  });

  test('libsodium secretbox matches Dart when library available', () {
    final loaded = preferLibsodiumSecretbox();
    if (!loaded) {
      // Documented: no device / no system lib → skip native equality.
      // ignore: avoid_print
      print('SKIP sodium equality: load failed ($libsodiumLoadError)');
      return;
    }
    secretboxRequireLibsodium = true;
    final key = Uint8List.fromList(List.filled(32, 1));
    final nonce = Uint8List.fromList(List.filled(24, 2));
    final message = Uint8List.fromList(List.filled(64, 3));
    final expected = hexDecode(
        '8442bc313f4626f1359e3b50122b6ce6fe66ddfe7d39d14e637eb4fd5b45bead'
        'ab55198df6ab5368439792a23c87db70acb6156dc5ef957ac04f6276cf6093b'
        '84be77ff0849cc33e34b7254d5a8f65ad');

    final sealed = secretboxSeal(message, nonce, key);
    expect(hexEncode(sealed), hexEncode(expected));
    final opened = secretboxOpen(expected, nonce, key);
    expect(opened, isNotNull);
    expect(hexEncode(opened!), hexEncode(message));

    // Cross-engine: Dart seal → sodium open and reverse.
    preferDartSecretbox();
    final dartBox = secretboxSealDart(message, nonce, key);
    preferLibsodiumSecretbox(require: true);
    expect(hexEncode(secretboxOpen(dartBox, nonce, key)!), hexEncode(message));
    final sodiumBox = secretboxSeal(message, nonce, key);
    preferDartSecretbox();
    expect(hexEncode(secretboxOpenDart(sodiumBox, nonce, key)!), hexEncode(message));
  });

  test('preferDart keeps backend on dart even if sodium loads', () {
    tryLoadLibsodium(forceReload: true);
    preferDartSecretbox();
    expect(secretboxBackend, SecretboxBackend.dart);
    final key = Uint8List.fromList(List.filled(32, 9));
    final nonce = Uint8List.fromList(List.filled(24, 8));
    final msg = Uint8List.fromList([1, 2, 3, 4, 5]);
    final box = secretboxSeal(msg, nonce, key);
    expect(secretboxOpen(box, nonce, key), msg);
  });

  /// Regression: preferLibsodiumSecretbox / secretboxBackend must never
  /// change EME / filename / dirname codecs (pure Dart only).
  test('filename and dirname codecs ignore secretboxBackend', () {
    final cipher = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
    );

    preferDartSecretbox();
    expect(secretboxBackend, SecretboxBackend.dart);
    final fileDart = cipher.encryptFileName('hello.txt');
    final dirDart = cipher.encryptDirName('photos');
    final pathDart = cipher.encryptFileName('photos/trip 2026 report.pdf');
    final filePlain = cipher.decryptFileName(fileDart);
    final dirPlain = cipher.decryptDirName(dirDart);

    // Golden rclone vectors (same as crypt_cipher_test).
    expect(fileDart, '9ph489uqiu6hppkcbp0g4328c4');
    expect(dirDart, 'ghd9crjufd2a4sartqaskk87rc');

    // Flip preference; name output must stay identical regardless of whether
    // libsodium actually loads.
    preferLibsodiumSecretbox();
    final fileSodiumPref = cipher.encryptFileName('hello.txt');
    final dirSodiumPref = cipher.encryptDirName('photos');
    final pathSodiumPref =
        cipher.encryptFileName('photos/trip 2026 report.pdf');

    expect(fileSodiumPref, fileDart);
    expect(dirSodiumPref, dirDart);
    expect(pathSodiumPref, pathDart);
    expect(cipher.decryptFileName(fileSodiumPref), filePlain);
    expect(cipher.decryptDirName(dirSodiumPref), dirPlain);
    expect(cipher.decryptFileName(pathSodiumPref), 'photos/trip 2026 report.pdf');

    // Force backend enum to libsodium even without a successful load so
    // name APIs are still pure Dart if someone mis-wires secretbox later.
    secretboxBackend = SecretboxBackend.libsodium;
    secretboxRequireLibsodium = false;
    expect(cipher.encryptFileName('hello.txt'), fileDart);
    expect(cipher.encryptDirName('photos'), dirDart);
    expect(
      cipher.encryptFileName('photos/trip 2026 report.pdf'),
      pathDart,
    );

    // Obfuscate path likewise must ignore secretbox backend.
    final obf = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.obfuscate,
      dirNameEncrypt: true,
    );
    preferDartSecretbox();
    final obfDart = obf.encryptFileName('hello.txt');
    secretboxBackend = SecretboxBackend.libsodium;
    expect(obf.encryptFileName('hello.txt'), obfDart);
    expect(obfDart, '162.vszzC.HLH');
  });
}
