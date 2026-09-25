import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:openlist_crypt/openlist_crypt.dart';

import 'crypt_cipher_test.dart' show hexEncode, standardCipher;

Uint8List bytes(int n, [int seed = 5]) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + seed) & 0xFF));

void main() {
  group('encryptBlock', () {
    final c = standardCipher();
    final nonce = Uint8List.fromList(List.filled(24, 7));

    test('round-trips with decryptBlock at various sizes', () {
      for (final n in [1, 15, 16, 17, 1023, kBlockDataSize]) {
        final plain = bytes(n);
        final block = c.encryptBlock(nonce, 0, plain);
        expect(block.length, n + kBlockHeaderSize, reason: 'len n=$n');
        expect(c.decryptBlock(nonce, 0, block), plain, reason: 'n=$n');
      }
    });

    test('matches encrypt() output for the same nonce (golden cross-check)', () {
      final plain = bytes(kBlockDataSize + 10);
      final whole = c.encrypt(plain, nonce: nonce);
      final b0 = c.encryptBlock(
          nonce, 0, Uint8List.sublistView(plain, 0, kBlockDataSize));
      final b1 = c.encryptBlock(nonce, 1,
          Uint8List.sublistView(plain, kBlockDataSize));
      final rebuilt = BytesBuilder()
        ..add(Uint8List.sublistView(whole, 0, kFileHeaderSize))
        ..add(b0)
        ..add(b1);
      expect(rebuilt.toBytes(), whole);
    });

    test('rejects bad nonce / index / oversized block', () {
      expect(() => c.encryptBlock(Uint8List(23), 0, bytes(1)),
          throwsA(isA<RcloneCipherException>()));
      expect(() => c.encryptBlock(nonce, -1, bytes(1)),
          throwsA(isA<RcloneCipherException>()));
      expect(
          () => c.encryptBlock(nonce, 0, bytes(kBlockDataSize + 1)),
          throwsA(isA<RcloneCipherException>()));
    });
  });

  group('encrypt with explicit nonce', () {
    final c = standardCipher();
    final nonce = Uint8List.fromList(List.filled(24, 9));

    test('is deterministic for the same nonce', () {
      final plain = bytes(1000);
      expect(c.encrypt(plain, nonce: nonce), c.encrypt(plain, nonce: nonce));
    });

    test('round-trips through decrypt', () {
      final plain = bytes(200 * 1000);
      final enc = c.encrypt(plain, nonce: nonce);
      expect(enc.length, RcloneCipher.encryptedSize(plain.length));
      expect(c.decrypt(enc), plain);
    });

    test('empty file: header only, decrypts to empty', () {
      final enc = c.encrypt(Uint8List(0), nonce: nonce);
      expect(enc.length, kFileHeaderSize);
      expect(c.decrypt(enc), Uint8List(0));
    });

    test('bad nonce length is rejected', () {
      expect(() => c.encrypt(bytes(10), nonce: Uint8List(10)),
          throwsA(isA<RcloneCipherException>()));
    });

    test('golden vector: fixed nonce produces fixed ciphertext', () {
      // 固定密码派生 + 固定 nonce → 输出完全确定，作黄金向量防回归。
      final enc = c.encrypt(bytes(64, 3), nonce: nonce);
      final expectedHead = hexEncode(Uint8List.fromList(
          [...kFileMagic, ...List.filled(24, 9)]));
      final expectedBlock = hexEncode(c.encryptBlock(nonce, 0, bytes(64, 3)));
      expect(hexEncode(enc), startsWith(expectedHead));
      expect(hexEncode(enc), '$expectedHead$expectedBlock');
    });
  });

  group('RcloneStreamEncrypter', () {
    final c = standardCipher();
    final nonce = Uint8List.fromList(List.filled(24, 4));

    List<Uint8List> runStream(Iterable<Uint8List> chunks,
        {Uint8List? nonce}) {
      final enc = RcloneStreamEncrypter(c, nonce: nonce);
      final out = <Uint8List>[enc.header()];
      for (final chunk in chunks) {
        out.addAll(enc.push(chunk));
      }
      out.addAll(enc.close());
      return out;
    }

    test('random chunk sizes round-trip and match whole-buffer encrypt', () {
      final rnd = _SeededRandom(42);
      for (final total in [
        0, 1, 100, kBlockDataSize - 1, kBlockDataSize,
        kBlockDataSize + 1, 3 * kBlockDataSize + 777
      ]) {
        final plain = bytes(total);
        // 任意切块（含 0 长度块），流式输出必须与整体加密一致。
        final chunks = <Uint8List>[];
        var off = 0;
        while (off < total) {
          final n = rnd.nextInt(kBlockDataSize * 2);
          final end = (off + n) > total ? total : off + n;
          chunks.add(Uint8List.sublistView(plain, off, end));
          off = end;
        }
        final parts = runStream(chunks, nonce: nonce);
        final bb = BytesBuilder();
        for (final p in parts) {
          bb.add(p);
        }
        final streamed = bb.toBytes();
        final whole = c.encrypt(plain, nonce: nonce);
        expect(hexEncode(streamed), hexEncode(whole),
            reason: 'total=$total');
        expect(c.decrypt(streamed), plain, reason: 'total=$total');
      }
    });

    test('exactly-block-sized pushes produce one block each', () {
      final enc = RcloneStreamEncrypter(c, nonce: nonce);
      final head = enc.header();
      expect(head.length, kFileHeaderSize);
      expect(hexEncode(Uint8List.sublistView(head, 8, 32)), '04' * 24);
      final b0 = enc.push(bytes(kBlockDataSize));
      expect(b0.length, 1);
      expect(b0[0].length, kBlockSize);
      final b1 = enc.push(bytes(10));
      expect(b1.length, 0); // 不足一块，暂存
      final tail = enc.close();
      expect(tail.length, 1);
      expect(tail[0].length, 10 + kBlockHeaderSize);
    });

    test('empty file via stream: header only', () {
      final parts = runStream(const [], nonce: nonce);
      expect(parts.length, 1);
      expect(parts[0].length, kFileHeaderSize);
      final streamed = parts[0];
      expect(hexEncode(streamed), hexEncode(c.encrypt(Uint8List(0), nonce: nonce)));
    });

    test('misuse: header not taken / double close / push after close', () {
      final enc = RcloneStreamEncrypter(c, nonce: nonce);
      expect(() => enc.push(bytes(1)),
          throwsA(isA<RcloneCipherException>()));
      enc.header();
      enc.push(bytes(1));
      enc.close();
      expect(() => enc.close(), throwsA(isA<RcloneCipherException>()));
      expect(() => enc.push(bytes(1)),
          throwsA(isA<RcloneCipherException>()));
      expect(() => enc.header(), throwsA(isA<RcloneCipherException>()));
    });

    test('random nonce by default; two instances differ', () {
      final a = RcloneStreamEncrypter(c).header();
      final b = RcloneStreamEncrypter(c).header();
      expect(hexEncode(Uint8List.sublistView(a, 8, 32)),
          isNot(hexEncode(Uint8List.sublistView(b, 8, 32))));
    });

    test('cipherBytesProduced tracks progress', () {
      final enc = RcloneStreamEncrypter(c, nonce: nonce);
      enc.header();
      expect(enc.cipherBytesProduced, 0);
      enc.push(bytes(kBlockDataSize));
      expect(enc.cipherBytesProduced, kBlockSize);
      enc.push(bytes(10));
      expect(enc.cipherBytesProduced, kBlockSize); // 余数未封块
      enc.close();
      expect(enc.cipherBytesProduced, kBlockSize + 10 + kBlockHeaderSize);
    });
  });
}

/// 可复现的伪随机（仅测试切块用；密码学随机不参与黄金向量）。
class _SeededRandom {
  _SeededRandom(int seed) : _state = seed;
  int _state;

  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % max;
  }
}
