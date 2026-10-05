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
}
