import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:openlist_crypt/openlist_crypt.dart';

/// base32768 移植的正确性由两类向量保证：
/// * rclone 自带 golden 向量（backend/crypt/cipher_test.go 的 TestEncodeFileNameBase32768
///   与 TestDecodeFileNameBase32768）；
/// * 全长度往返（0..200 字节），覆盖补位与末块 7 位编码。
void main() {
  const vectors = <List<String>>[
    ['', ''],
    ['1', '㼿'],
    ['12', '㻙ɟ'],
    ['123', '㻙ⲿ'],
    ['1234', '㻙ⲍƟ'],
    ['12345', '㻙ⲍ⍟'],
    ['123456', '㻙ⲍ⍆ʏ'],
    ['1234567', '㻙ⲍ⍆觟'],
    ['12345678', '㻙ⲍ⍆觓ɧ'],
    ['123456789', '㻙ⲍ⍆觓栯'],
    ['1234567890', '㻙ⲍ⍆觓栩ɣ'],
    ['12345678901', '㻙ⲍ⍆觓栩朧'],
    ['123456789012', '㻙ⲍ⍆觓栩朤ʅ'],
    ['1234567890123', '㻙ⲍ⍆觓栩朤談'],
    ['12345678901234', '㻙ⲍ⍆觓栩朤諆ɔ'],
    ['123456789012345', '㻙ⲍ⍆觓栩朤諆媕'],
    ['1234567890123456', '㻙ⲍ⍆觓栩朤諆媕䆿'],
  ];

  test('编码与 rclone golden 向量一致', () {
    for (final v in vectors) {
      expect(Base32768Encoding.safe.encode(utf8.encode(v[0])), v[1],
          reason: 'in=${v[0]}');
    }
  });

  test('解码与 rclone golden 向量一致', () {
    for (final v in vectors) {
      expect(utf8.decode(Base32768Encoding.safe.decode(v[1])), v[0],
          reason: 'in=${v[1]}');
    }
  });

  test('非法输入抛错位置与 rclone 一致', () {
    const bad = <List<Object>>[
      ['㼿c', 1],
      ['!', 0],
      ['㻙ⲿ=㻙ⲿ', 2],
      ['怪=', 1],
    ];
    for (final b in bad) {
      expect(
        () => Base32768Encoding.safe.decode(b[0] as String),
        throwsA(isA<Base32768CorruptInput>()
            .having((e) => e.index, 'index', b[1])),
        reason: 'in=${b[0]}',
      );
    }
  });

  test('全长度往返与长度计算', () {
    for (var n = 0; n <= 200; n++) {
      final src = Uint8List.fromList(
          List<int>.generate(n, (i) => (i * 31 + 7) & 0xFF));
      final enc = Base32768Encoding.safe.encode(src);
      expect(enc.runes.length, Base32768Encoding.safe.encodedLengthInChars(n),
          reason: 'chars n=$n');
      expect(Base32768Encoding.safe.decode(enc), src, reason: 'roundtrip n=$n');
    }
  });

  test('换行被忽略（与 rclone 相同）', () {
    final enc = Base32768Encoding.safe.encode(utf8.encode('1234567890'));
    final wrapped = '${enc.substring(0, 2)}\n${enc.substring(2)}';
    expect(utf8.decode(Base32768Encoding.safe.decode(wrapped)), '1234567890');
  });
}
