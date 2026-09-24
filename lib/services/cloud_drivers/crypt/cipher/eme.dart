import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// EME（ECB-Mix-ECB / Encrypt-Mix-Encrypt）宽块加密，Halevi & Rogaway 2003。
/// 字面移植 github.com/rfjakob/eme（rclone 文件名加密用的就是这个包），
/// 上限 128 个 16 字节块（2048 字节）。
class EmeCipher {
  EmeCipher(Uint8List key32) : _key = Uint8List.fromList(key32);

  final Uint8List _key;
  late final BlockCipher _aes = BlockCipher('AES');

  void _aesBlock(Uint8List out, int outOff, Uint8List src, int srcOff, bool enc) {
    _aes
      ..init(enc, KeyParameter(_key))
      ..processBlock(src, srcOff, out, outOff);
  }

  static void _xor(Uint8List a, int ao, Uint8List b, int bo) {
    for (var i = 0; i < 16; i++) {
      a[ao + i] ^= b[bo + i];
    }
  }

  static Uint8List _multByTwo(Uint8List b) {
    final out = Uint8List(16);
    out[0] = ((2 * b[0]) & 0xFF) ^ (135 & (-(b[15] >> 7)));
    for (var j = 1; j < 16; j++) {
      out[j] = ((2 * b[j]) + (b[j - 1] >> 7)) & 0xFF;
    }
    return out;
  }

  List<Uint8List> _tabulateL(int m) {
    final li = Uint8List(16);
    _aesBlock(li, 0, Uint8List(16), 0, true);
    final table = List<Uint8List>.generate(m, (_) => Uint8List(16));
    for (var i = 0; i < m; i++) {
      li.setAll(0, _multByTwo(li));
      table[i].setAll(0, li);
    }
    return table;
  }

  /// [data] 长度必须是 16 的非零倍且 ≤ 2048；[tweak] 16 字节。
  /// 加密与解密共用一套流程（仅块密码方向不同），照 eme.go Transform。
  Uint8List transform(Uint8List tweak, Uint8List data, bool encrypt) {
    final m = data.length ~/ 16;
    final l = _tabulateL(m);
    final c = Uint8List(data.length);
    final pp = Uint8List(16);
    for (var j = 0; j < m; j++) {
      pp.setAll(0, Uint8List.sublistView(data, j * 16, j * 16 + 16));
      _xor(pp, 0, l[j], 0);
      _aesBlock(c, j * 16, pp, 0, encrypt);
    }
    final mp = Uint8List.fromList(Uint8List.sublistView(c, 0, 16));
    _xor(mp, 0, tweak, 0);
    for (var j = 1; j < m; j++) {
      _xor(mp, 0, Uint8List.sublistView(c, j * 16, j * 16 + 16), 0);
    }
    final mc = Uint8List(16);
    _aesBlock(mc, 0, mp, 0, encrypt);
    final mm = Uint8List.fromList(mp);
    _xor(mm, 0, mc, 0);
    final ccc = Uint8List(16);
    for (var j = 1; j < m; j++) {
      mm.setAll(0, _multByTwo(mm));
      ccc.setAll(0, Uint8List.sublistView(c, j * 16, j * 16 + 16));
      _xor(ccc, 0, mm, 0);
      c.setRange(j * 16, j * 16 + 16, ccc);
    }
    final ccc1 = Uint8List.fromList(mc);
    _xor(ccc1, 0, tweak, 0);
    for (var j = 1; j < m; j++) {
      _xor(ccc1, 0, Uint8List.sublistView(c, j * 16, j * 16 + 16), 0);
    }
    c.setRange(0, 16, ccc1);
    for (var j = 0; j < m; j++) {
      _aesBlock(c, j * 16, c, j * 16, encrypt);
      _xor(c, j * 16, l[j], 0);
    }
    return c;
  }
}
