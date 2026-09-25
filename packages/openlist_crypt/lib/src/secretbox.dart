import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'salsa20.dart';

/// NaCl secretbox（XSalsa20-Poly1305），字面对齐
/// golang.org/x/crypto/nacl/secretbox——rclone crypt 内容块用它。
/// 布局：box = tag(16) || ciphertext。
///
/// 性能：rclone 的内容块循环里，同一文件的 [nonce24] 只有后 8 字节
/// （块计数器）在变，前 16 字节与 key32 恒定 → hsalsa20 派生的 subKey
/// 同文件全部块相同。单条目备忘（逐字节比对命中）让同文件第 2 块起
/// 免重复派生；Poly1305 实例复用（init 只换 key 参数）。
/// 两个函数仍保持无状态语义：换文件/换 key 自动失效重派生。
const int kSecretboxOverhead = 16;

int _ctEq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return 0;
  var v = 0;
  for (var i = 0; i < a.length; i++) {
    v |= a[i] ^ b[i];
  }
  return v == 0 ? 1 : 0;
}

/// 复用的 Poly1305 实例（init 重置内部状态，线程安全性与原实现一致：
/// 都是单 isolate 顺序调用）。
final Poly1305 _poly = Poly1305();

Uint8List _polyMac(Uint8List data, Uint8List key32) {
  _poly.init(KeyParameter(key32));
  return _poly.process(data);
}

/// subKey 备忘：命中条件 = key32 与 nonce24[0..16] 逐字节相同。
Uint8List? _memoKey;
Uint8List? _memoNonce16;
Uint8List? _memoSubKey;

Uint8List _subKeyFor(Uint8List nonce24, Uint8List key32) {
  final mk = _memoKey;
  final mn = _memoNonce16;
  if (mk != null && mn != null && _ctEq(mk, key32) == 1 && _ctEq(mn, Uint8List.sublistView(nonce24, 0, 16)) == 1) {
    return _memoSubKey!;
  }
  final sub = hsalsa20(Uint8List.sublistView(nonce24, 0, 16), key32);
  _memoKey = Uint8List.fromList(key32);
  _memoNonce16 = Uint8List.fromList(nonce24.sublist(0, 16));
  _memoSubKey = sub;
  return sub;
}

/// 密文认证失败返回 null；成功返回明文。
Uint8List? secretboxOpen(Uint8List box, Uint8List nonce24, Uint8List key32) {
  if (box.length < kSecretboxOverhead) return null;
  final subKey = _subKeyFor(nonce24, key32);
  final counter = Uint8List(16)..setRange(0, 8, nonce24, 16);
  // Poly1305 key = 首 64 字节块的前 32 字节 keystream（XOR 全零即得）。
  final first = Uint8List(64);
  salsa20Xor(first, Uint8List(64), 0, 0, 64, counter, subKey);
  final polyKey = Uint8List.sublistView(first, 0, 32);
  final tag = Uint8List.sublistView(box, 0, kSecretboxOverhead);
  final ct = Uint8List.sublistView(box, kSecretboxOverhead);
  if (_ctEq(_polyMac(ct, polyKey), tag) == 0) return null;
  final m = Uint8List(ct.length);
  // 前 32 字节明文用首块的 [32:64]；其余从 counter 块 1 起流式 XOR。
  final n1 = ct.length < 32 ? ct.length : 32;
  for (var i = 0; i < n1; i++) {
    m[i] = ct[i] ^ first[32 + i];
  }
  if (ct.length > 32) {
    final c2 = Uint8List.fromList(counter);
    c2[8] = 1;
    salsa20Xor(m, ct, 32, 32, ct.length - 32, c2, subKey);
  }
  return m;
}

/// box = tag(16) || ciphertext。
Uint8List secretboxSeal(Uint8List msg, Uint8List nonce24, Uint8List key32) {
  final subKey = _subKeyFor(nonce24, key32);
  final counter = Uint8List(16)..setRange(0, 8, nonce24, 16);
  final first = Uint8List(64);
  salsa20Xor(first, Uint8List(64), 0, 0, 64, counter, subKey);
  final box = Uint8List(kSecretboxOverhead + msg.length);
  final n1 = msg.length < 32 ? msg.length : 32;
  for (var i = 0; i < n1; i++) {
    box[kSecretboxOverhead + i] = first[32 + i] ^ msg[i];
  }
  if (msg.length > 32) {
    final c2 = Uint8List.fromList(counter);
    c2[8] = 1;
    salsa20Xor(box, msg, kSecretboxOverhead + 32, 32, msg.length - 32, c2, subKey);
  }
  final tag = _polyMac(
    Uint8List.sublistView(box, kSecretboxOverhead),
    Uint8List.sublistView(first, 0, 32),
  );
  box.setRange(0, kSecretboxOverhead, tag);
  return box;
}
