// 基准：量化 openlist_crypt 纯 Dart 实现的热点开销（优化前后对比用）。
// 方法学：每个场景先预热（JIT 优化生效），再测多轮取中位数 —— 首调用
// 包含 JIT/懒加载，不代表稳态吞吐；前序场景的 GC 压力也会污染后续
// 测量，故每轮测量前重建待解数据。
// 运行：dart run example/bench.dart
//
// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:openlist_crypt/openlist_crypt.dart';

Uint8List blob(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 5) & 0xFF));

/// 预热 [warmup] 次后测 [iterations] 轮，取中位数（微秒）。
int timeIt(String label, void Function() fn,
    {int warmup = 5, int iterations = 20}) {
  for (var i = 0; i < warmup; i++) {
    fn();
  }
  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  final medianUs = samples[samples.length ~/ 2];
  print('${label.padRight(40)} ${medianUs.toString().padLeft(8)} us');
  return medianUs;
}

void main() {
  print('== scrypt 密钥派生（账号注册，一次性） ==');
  timeIt('RcloneCipher(password, salt)', () {
    RcloneCipher(password: 'bench', salt: 'bench');
  }, iterations: 10);

  print('');
  print('== 内容加解密（流播放 / 下载） ==');
  final c = RcloneCipher(password: 'bench', salt: 'bench');
  final nonce = RcloneCipher.randomFileNonce();
  final plain64k = blob(kBlockDataSize);
  final plain1m = blob(1024 * 1024);

  timeIt('encryptBlock 64 KiB', () => c.encryptBlock(nonce, 0, plain64k));

  // decrypt 用每轮新构造的密文：复用旧密文会被前序测量的堆状态污染。
  timeIt('encrypt 1 MiB (16 blocks)', () {
    c.encrypt(plain1m, nonce: nonce);
  });
  final enc1m = c.encrypt(plain1m, nonce: nonce);
  timeIt('decrypt 1 MiB (16 blocks)', () {
    c.decrypt(enc1m);
  });

  print('');
  print('== 名字加解密（目录列表：每条目一次） ==');
  final helloEnc = c.encryptFileName('hello.txt');
  timeIt('decryptFileName "hello.txt"', () {
    c.decryptFileName(helloEnc);
  }, warmup: 20, iterations: 50);
  timeIt('encryptFileName "hello.txt"', () {
    c.encryptFileName('hello.txt');
  }, warmup: 20, iterations: 50);

  // 目录列表真实形态：50 个名字连续解密（浏览一次列表的纯计算成本）。
  final names = List.generate(
      50, (i) => c.encryptFileName('track_$i - ${'a' * 30}.flac'));
  timeIt('decryptFileName ×50（典型目录）', () {
    for (final n in names) {
      c.decryptFileName(n);
    }
  }, warmup: 10, iterations: 50);

  final long = 'a' * 200;
  final encLong = c.encryptFileName(long);
  timeIt('encryptFileName 200 字符（16 块）', () => c.encryptFileName(long));
  timeIt('decryptFileName 200 字符（16 块）', () => c.decryptFileName(encLong));

  // 深路径浏览（dirNameEncrypt=true）：每跳解密路径上的目录段。
  final encDeepPath =
      List.generate(5, (i) => c.encryptDirName('dir$i')).join('/');
  timeIt('decryptDirName 深路径 5 段', () {
    for (final seg in encDeepPath.split('/')) {
      c.decryptDirName(seg);
    }
  }, warmup: 3, iterations: 10);
}
