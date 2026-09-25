// 基准：量化 openlist_crypt 当前纯 Dart 实现的热点开销。
// 运行：dart run example/bench.dart
import 'dart:typed_data';

import 'package:openlist_crypt/openlist_crypt.dart';

Uint8List blob(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 5) & 0xFF));

void timeIt(String label, void Function() fn, {int repeat = 1}) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < repeat; i++) {
    fn();
  }
  sw.stop();
  final us = sw.elapsedMicroseconds / repeat;
  print('${label.padRight(34)} ${us.toStringAsFixed(0).padLeft(9)} us');
}

void main() {
  print('== scrypt 密钥派生（构造函数，一次性） ==');
  timeIt('RcloneCipher(password, salt)', () {
    RcloneCipher(password: 'bench', salt: 'bench');
  }, repeat: 10);

  print('');
  print('== 内容加解密（64 KiB 块吞吐） ==');
  final c = RcloneCipher(password: 'bench', salt: 'bench');
  final nonce = RcloneCipher.randomFileNonce();
  final plain1k = blob(1024);
  final plain64k = blob(kBlockDataSize);
  final plain1m = blob(1024 * 1024);

  timeIt('encryptBlock 1 KiB', () => c.encryptBlock(nonce, 0, plain1k));
  timeIt('encryptBlock 64 KiB', () => c.encryptBlock(nonce, 0, plain64k));
  final enc1m = c.encrypt(plain1m, nonce: nonce);
  timeIt('encrypt 1 MiB (16 blocks)', () => c.encrypt(plain1m, nonce: nonce));
  timeIt('decrypt 1 MiB (16 blocks)', () => c.decrypt(enc1m));

  print('');
  print('== 名字加密（目录列表场景） ==');
  timeIt('encryptFileName 1 个', () => c.encryptFileName('hello.txt'));
  final long = 'a' * 200;
  timeIt('encryptFileName 200 字符', () => c.encryptFileName(long));
  timeIt('decryptFileName 200 字符', () {
    final enc = c.encryptFileName(long);
    c.decryptFileName(enc);
  });
}
