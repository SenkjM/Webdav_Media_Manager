import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/services/cloud_drivers/crypt/cipher/rclone_cipher.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/cipher/secretbox.dart';

Uint8List hexDecode(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexEncode(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

RcloneCipher standardCipher() => RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
    );

void main() {
  test('secretbox matches NaCl reference vector', () {
    final key = Uint8List.fromList(List.filled(32, 1));
    final nonce = Uint8List.fromList(List.filled(24, 2));
    final message = Uint8List.fromList(List.filled(64, 3));
    final expected = hexDecode(
        '8442bc313f4626f1359e3b50122b6ce6fe66ddfe7d39d14e637eb4fd5b45bead'
        'ab55198df6ab5368439792a23c87db70acb6156dc5ef957ac04f6276cf6093b'
        '84be77ff0849cc33e34b7254d5a8f65ad');
    final box = secretboxSeal(message, nonce, key);
    expect(hexEncode(box), hexEncode(expected));
    final opened = secretboxOpen(expected, nonce, key);
    expect(opened, isNotNull);
    expect(hexEncode(opened!), hexEncode(message));
  });

  test('secretbox rejects tampered ciphertext', () {
    final key = Uint8List.fromList(List.filled(32, 1));
    final nonce = Uint8List.fromList(List.filled(24, 2));
    final box = secretboxSeal(Uint8List.fromList(List.filled(64, 3)), nonce, key);
    box[20] ^= 0x20;
    expect(secretboxOpen(box, nonce, key), isNull);
  });

  group('rclone file name vectors (standard)', () {
    final c = standardCipher();

    test('encrypt matches rclone output', () {
      expect(c.encryptFileName('hello.txt'), '9ph489uqiu6hppkcbp0g4328c4');
      expect(c.encryptFileName('emptyish.txt'), 'gc9nhgjcfp5t0tfuf681lv7ffo');
      expect(c.encryptFileName('big.bin'), '5kpt7oum5a13es2i6ai1tmoaek');
      expect(c.encryptDirName('photos'), 'ghd9crjufd2a4sartqaskk87rc');
      expect(
          c.encryptFileName('photos/trip 2026 report.pdf'),
          'ghd9crjufd2a4sartqaskk87rc'
          '/lcftbecu8jsq2d0n4h5351qpccccqgegc2op9v366huan3kkiuag');
    });

    test('decrypt rclone names back', () {
      expect(c.decryptFileName('9ph489uqiu6hppkcbp0g4328c4'), 'hello.txt');
      expect(c.decryptFileName('gc9nhgjcfp5t0tfuf681lv7ffo'), 'emptyish.txt');
      expect(c.decryptFileName('5kpt7oum5a13es2i6ai1tmoaek'), 'big.bin');
      expect(c.decryptDirName('ghd9crjufd2a4sartqaskk87rc'), 'photos');
      expect(
          c.decryptFileName('ghd9crjufd2a4sartqaskk87rc'
              '/lcftbecu8jsq2d0n4h5351qpccccqgegc2op9v366huan3kkiuag'),
          'photos/trip 2026 report.pdf');
    });

    test('rclone ciphertext decrypts to plaintext (hello)', () {
      expect(utf8.decode(c.decrypt(hexDecode(
        '52434c4f4e4500005aec6b92d0a9c18d271aa8a7d9f0820eb5781dbfe10c58a4'
        '10abcbafd5e66a17a5042ee1ad2c02a0f495731a3606e633bcd0a3b7caa5647c'
        'e643'
          ))), 'hello crypt 你好');
    });

    test('rclone ciphertext decrypts to plaintext (trip report)', () {
      expect(utf8.decode(c.decrypt(hexDecode(
        '52434c4f4e4500005912f0fd1f42da73222dc800d8a016c7b5db06795541e0fd'
        'd9246b69c9c283030ac8de16b8ef1205df3dbcf93a3d341ee9033a'
          ))), 'photo bytes');
    });
  });

  group('rclone obfuscate vectors', () {
    final c = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.obfuscate,
      dirNameEncrypt: true,
    );
    test('hello.txt matches rclone obfuscate output', () {
      expect(c.encryptFileName('hello.txt'), '162.vszzC.HLH');
      expect(c.decryptFileName('162.vszzC.HLH'), 'hello.txt');
    });
  });


  group('rclone base64 encoding and suffix vectors', () {
    final c64 = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
      nameEncoding: 'base64',
    );
    test('base64 name matches rclone output', () {
      expect(c64.encryptFileName('hello.txt'), 'TmJEJ9qXjRzmjF5BAgxIYQ');
      expect(c64.decryptFileName('TmJEJ9qXjRzmjF5BAgxIYQ'), 'hello.txt');
    });
    test('base64 ciphertext decrypts to plaintext', () {
      expect(
          utf8.decode(c64.decrypt(hexDecode(
        '52434c4f4e4500004d50b1a26c918189d8b380ba0e04e8d806465cd386316012'
        '5ad1d999bef11bfd162438c154c9859842ce76a8f993e45fb1912f43a88c44d9'
        '4d30'
          ))),
          'hello crypt 你好');
    });
    test('off mode uses custom suffix', () {
      final off = RcloneCipher(
        password: 'testpass',
        salt: 'testsalt',
        mode: NameEncryptionMode.off,
        dirNameEncrypt: true,
        encryptedSuffix: '.bin',
      );
      expect(off.encryptFileName('emptyish.txt'), 'emptyish.txt.bin');
      expect(off.decryptFileName('emptyish.txt.bin'), 'emptyish.txt');
    });
  });

  group('roundtrip', () {
    final c = standardCipher();
    for (final size in [0, 1, 15, 16, 17, 65535, 65536, 65537, 131072, 200000]) {
      test('content roundtrip size=$size', () {
        final plain = Uint8List(size);
        for (var i = 0; i < size; i++) {
          plain[i] = i % 251;
        }
        final enc = c.encrypt(plain);
        expect(RcloneCipher.encryptedSize(size), enc.length);
        expect(RcloneCipher.decryptedSize(enc.length), size);
        expect(c.decrypt(enc), plain);
      });
    }

    test('name roundtrip unicode and long', () {
      const names = [
        '你好 世界 2026.flac',
        'a very long name with spaces and dots.m4a.bak',
        'emoji🎵and中文.mp3',
      ];
      for (final n in names) {
        expect(c.decryptFileName(c.encryptFileName(n)), n);
      }
    });

    test('off mode appends .bin to files only', () {
      final off = RcloneCipher(
        password: 'testpass',
        salt: 'testsalt',
        mode: NameEncryptionMode.off,
        dirNameEncrypt: true,
      );
      expect(off.encryptFileName('a.txt'), 'a.txt.bin');
      expect(off.decryptFileName('a.txt.bin'), 'a.txt');
      expect(off.encryptDirName('dir'), 'dir');
    });

    test('dirNameEncrypt=false keeps directories plain', () {
      final c2 = RcloneCipher(
        password: 'testpass',
        salt: 'testsalt',
        mode: NameEncryptionMode.standard,
        dirNameEncrypt: false,
      );
      final enc = c2.encryptFileName('photos/a.txt');
      expect(enc.startsWith('photos/'), isTrue);
      expect(enc, isNot('photos/a.txt'));
      expect(c2.decryptFileName(enc), 'photos/a.txt');
    });

    test('bad magic and tampering throw', () {
      final enc = c.encrypt(Uint8List.fromList(List.filled(100, 7)));
      final bad = Uint8List.fromList(enc);
      bad[2] = 0xFF;
      expect(() => c.decrypt(bad), throwsA(isA<RcloneCipherException>()));
      final tampered = Uint8List.fromList(enc);
      tampered[tampered.length - 1] ^= 0xFF;
      expect(() => c.decrypt(tampered), throwsA(isA<RcloneCipherException>()));
    });
  });



  group('分段读取（下载进度走块，99 §7.5）', () {
    test('逐块解密与整包解密一致', () {
      final c = standardCipher();
      // 跨 3 个块：2 个满块 + 余块。
      final plain = Uint8List.fromList(
        List<int>.generate(kBlockDataSize * 2 + 1234, (i) => (i * 37 + 11) & 0xFF),
      );
      final enc = c.encrypt(plain);
      expect(enc.length, RcloneCipher.encryptedSize(plain.length));

      final nonce = RcloneCipher.fileNonceOf(
        Uint8List.sublistView(enc, 0, kFileHeaderSize),
      );
      final out = BytesBuilder();
      var off = kFileHeaderSize;
      var block = 0;
      while (off < enc.length) {
        final n =
            (enc.length - off) < kBlockSize ? (enc.length - off) : kBlockSize;
        out.add(
          c.decryptBlock(nonce, block, Uint8List.sublistView(enc, off, off + n)),
        );
        off += n;
        block++;
      }
      expect(block, 3);
      expect(out.toBytes(), plain);
      expect(c.decrypt(enc), plain);
    });

    test('坏块与坏文件头立即报错', () {
      final c = standardCipher();
      final enc =
          c.encrypt(Uint8List.fromList(List.filled(kBlockDataSize + 10, 5)));
      final header = Uint8List.sublistView(enc, 0, kFileHeaderSize);
      final nonce = RcloneCipher.fileNonceOf(header);
      final good = Uint8List.sublistView(enc, kFileHeaderSize, kFileHeaderSize + kBlockSize);
      final tampered = Uint8List.fromList(good);
      tampered[0] ^= 0xFF;
      expect(
        () => c.decryptBlock(nonce, 0, tampered),
        throwsA(isA<RcloneCipherException>()),
      );
      // 同一块用错块号（nonce 不同）也必须失败。
      expect(
        () => c.decryptBlock(nonce, 1, good),
        throwsA(isA<RcloneCipherException>()),
      );
      final badHeader = Uint8List.fromList(header);
      badHeader[0] = 0;
      expect(
        () => RcloneCipher.fileNonceOf(badHeader),
        throwsA(isA<RcloneCipherException>()),
      );
    });
  });
}
