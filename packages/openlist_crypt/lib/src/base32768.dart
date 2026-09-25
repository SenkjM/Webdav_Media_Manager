import 'dart:typed_data';

import 'base32768_table.dart';

/// base32768 解码失败（对应上游 CorruptInputError；[index] 为出错字符下标）。
class Base32768CorruptInput implements Exception {
  Base32768CorruptInput(this.index);

  final int index;

  @override
  String toString() => 'base32768: corrupt input at $index';
}

/// `github.com/Max-Sum/base32768` 的 Dart 移植（rclone backend/crypt 用的 SafeEncoding）。
///
/// 逐条对齐上游 Go 实现：每 15 位一个字符，末块用 7 位字符，位不足补 1；字符表按
/// 码点排序后前 4 个为尾部块字母表、其余 1024 个为 15 位块字母表。
class Base32768Encoding {
  Base32768Encoding._(List<int> alphabet) {
    final sorted = [...alphabet]..sort();
    _splitter = sorted[4];
    _encodeA = sorted.sublist(4);
    _encodeB = sorted.sublist(0, 4);
    _decodeMap = List<int>.filled(2048, _invalid);
    for (var i = 0; i < _encodeA.length; i++) {
      final idx = _encodeA[i] >> kBlockBit;
      if (_decodeMap[idx] != _invalid) {
        throw StateError('base32768 alphabet contains a repeated character');
      }
      _decodeMap[idx] = i << kBlockBit;
    }
    for (var i = 0; i < _encodeB.length; i++) {
      final idx = _encodeB[i] >> kBlockBit;
      if (_decodeMap[idx] != _invalid) {
        throw StateError('base32768 alphabet contains a repeated character');
      }
      _decodeMap[idx] = i << kBlockBit;
    }
  }

  /// rclone / OpenList 使用的安全字母表（`base32768.SafeEncoding`）。
  static final Base32768Encoding safe = Base32768Encoding._(kBase32768Alphabet);

  static const int _invalid = 0xFFFD;

  late final int _splitter;
  late final List<int> _encodeA;
  late final List<int> _encodeB;
  late final List<int> _decodeMap;

  /// 上游 `EncodedLen`：n 字节输入编码后的 UTF-16 字节数。
  int encodedLength(int n) => ((8 * n + 14) ~/ 15) * 2;

  /// 上游 `EncodedLen` 的字符数版本（便于测试断言长度）。
  int encodedLengthInChars(int n) => (8 * n + 14) ~/ 15;

  String encode(List<int> src) => String.fromCharCodes(_encodeToChars(src));

  List<int> encodeToCodeUnits(List<int> src) => _encodeToChars(src);

  /// 解码；遇非法字符抛 [Base32768CorruptInput]。换行会被忽略（与上游一致）。
  Uint8List decode(String s) {
    final units = <int>[];
    for (final r in s.runes) {
      if (r == 0x0A || r == 0x0D) continue;
      units.add(r);
    }
    final dst = Uint8List(units.length * 15 ~/ 8 + 8);
    final n = _decodeUnits(dst, units);
    return Uint8List.sublistView(dst, 0, n);
  }

  List<int> _encodeToChars(List<int> src) {
    final dst = <int>[];
    var left = 0;
    var leftn = 0;
    var i = 0;
    while (i < src.length) {
      var chunk = left << (15 - leftn);
      chunk |= src[i] << (7 - leftn);
      if (leftn < 7 && i + 1 < src.length) {
        chunk |= src[i + 1] >> (1 + leftn);
        left = src[i + 1] & ((1 << (1 + leftn)) - 1);
        leftn++;
        i += 2;
      } else {
        chunk |= (1 << (7 - leftn)) - 1; // 位不足补 1
        left = 0;
        leftn = 0;
        i += 1;
      }
      dst.add(_encode15(chunk));
    }
    if (leftn > 0) {
      left = left << (7 - leftn);
      left |= (1 << (7 - leftn)) - 1;
      dst.add(_encode7(left));
    }
    return dst;
  }

  int _encode15(int src) {
    final v = src & 0x7FFF;
    return _encodeA[v >> kBlockBit] | (v & ((1 << kBlockBit) - 1));
  }

  int _encode7(int src) {
    final v = src & 0x7F;
    return _encodeB[v >> kBlockBit] | (v & ((1 << kBlockBit) - 1));
  }

  (int, bool, bool) _decodeChar(int src) {
    final isTrailing = src < _splitter;
    final idx = src >> kBlockBit;
    var dst = idx < _decodeMap.length ? _decodeMap[idx] : _invalid;
    if (dst == _invalid) return (dst, isTrailing, false);
    dst |= src & ((1 << kBlockBit) - 1);
    return (dst, isTrailing, true);
  }

  int _decodeUnits(Uint8List dst, List<int> src) {
    final olen = src.length;
    var left = 0;
    var leftn = 0;
    var n = 0;
    var di = 0;
    var si = 0;
    while (si < src.length) {
      final (d, trailing, ok) = _decodeChar(src[si]);
      if (!ok) throw Base32768CorruptInput(olen - (src.length - si));
      if (trailing) {
        if (leftn > 0) {
          dst[di++] = ((left << (8 - leftn)) | (d >> (leftn - 1))) & 0xFF;
          n++;
        }
        return n;
      }
      if (leftn > 0) {
        dst[di++] = ((left << (8 - leftn)) | (d >> (7 + leftn))) & 0xFF;
        dst[di++] = (d >> (leftn - 1)) & 0xFF;
        left = d & ((1 << (leftn - 1)) - 1);
        leftn--;
        n += 2;
      } else {
        dst[di++] = (d >> 7) & 0xFF;
        left = d & 0x7F;
        leftn = 7;
        n++;
      }
      si++;
    }
    return n;
  }
}

/// 上游 `blockBit`：每块 5 位（表内码点必须是 32 的倍数）。
const int kBlockBit = 5;
