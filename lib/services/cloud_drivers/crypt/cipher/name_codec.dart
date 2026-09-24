import 'dart:typed_data';

/// rclone crypt 的名字层：Base32（Hex 表，小写、去填充）+ PKCS7 + 混淆。
/// 逐行对照 rclone v1.75.1 backend/crypt/cipher.go。

int _hexVal(int ch) {
  if (ch >= 0x30 && ch <= 0x39) return ch - 0x30;
  if (ch >= 0x41 && ch <= 0x56) return ch - 0x41 + 10;
  return -1;
}

String _hexChar(int v) => v < 10
    ? String.fromCharCode(0x30 + v)
    : String.fromCharCode(0x61 + v - 10);

Uint8List base32HexLowerDecode(String s) {
  // 大小写不敏感；残位丢弃（rclone 同）。
  final up = s.toUpperCase();
  var bits = 0;
  var acc = 0;
  final out = <int>[];
  for (final ch in up.codeUnits) {
    final v = _hexVal(ch);
    if (v < 0) throw const FormatException('bad base32 char');
    acc = (acc << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((acc >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}

String base32HexLowerEncode(Uint8List src) {
  var acc = 0;
  var bits = 0;
  final out = StringBuffer();
  for (final b in src) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_hexChar((acc >> (bits - 5)) & 31));
      bits -= 5;
    }
  }
  if (bits > 0) {
    out.write(_hexChar((acc << (5 - bits)) & 31));
  }
  return out.toString();
}

Uint8List pkcs7Pad16(Uint8List data) {
  final pad = 16 - (data.length % 16);
  return Uint8List.fromList([...data, ...List.filled(pad, pad)]);
}

Uint8List pkcs7Unpad16(Uint8List data) {
  if (data.isEmpty) throw const FormatException('pkcs7: empty');
  final pad = data.last;
  if (pad < 1 || pad > 16 || pad > data.length) {
    throw const FormatException('pkcs7: bad length');
  }
  for (var i = data.length - pad; i < data.length; i++) {
    if (data[i] != pad) throw const FormatException('pkcs7: bad byte');
  }
  return Uint8List.sublistView(data, 0, data.length - pad);
}

const int obfuscQuoteRune = 0x21; // '!'

bool _validRune(int r) => r > 0 && !(r >= 0xD800 && r <= 0xDFFF);

/// 混淆（cipher.go obfuscateSegment）：首段数字 = 旋转量（名字码点和），
/// 实际旋转再叠加 nameKey 字节和；数字 / 字母 / latin1 / ≥U+100 各有区段；
/// '!' 双写转义；非 UTF-8 场景（Dart 不会出现）保留 `!.` 前缀透传语义。
String obfuscateSegment(String plaintext, Uint8List nameKey) {
  if (plaintext.isEmpty) return '';
  var dir = 0;
  for (final r in plaintext.runes) {
    dir += r;
  }
  dir %= 256;
  final out = StringBuffer();
  out.write(dir);
  out.write('.');
  for (final b in nameKey) {
    dir += b;
  }
  for (final runeValue in plaintext.runes) {
    if (runeValue == obfuscQuoteRune) {
      out.writeCharCode(obfuscQuoteRune);
      out.writeCharCode(obfuscQuoteRune);
    } else if (runeValue >= 0x30 && runeValue <= 0x39) {
      final thisdir = (dir % 9) + 1;
      out.writeCharCode(0x30 + (runeValue - 0x30 + thisdir) % 10);
    } else if ((runeValue >= 0x41 && runeValue <= 0x5A) ||
        (runeValue >= 0x61 && runeValue <= 0x7A)) {
      final thisdir = (dir % 25) + 1;
      var pos = runeValue - 0x41;
      if (pos >= 26) pos -= 6;
      pos = (pos + thisdir) % 52;
      if (pos >= 26) pos += 6;
      out.writeCharCode(0x41 + pos);
    } else if (runeValue >= 0xA0 && runeValue <= 0xFF) {
      final thisdir = (dir % 95) + 1;
      out.writeCharCode(0xA0 + (runeValue - 0xA0 + thisdir) % 96);
    } else if (runeValue >= 0x100) {
      final thisdir = (dir % 127) + 1;
      final base = runeValue - (runeValue % 256);
      final newRune = base + (runeValue - base + thisdir) % 256;
      if (!_validRune(newRune)) {
        out.writeCharCode(obfuscQuoteRune);
        out.writeCharCode(runeValue);
      } else {
        out.writeCharCode(newRune);
      }
    } else {
      out.writeCharCode(runeValue);
    }
  }
  return out.toString();
}

String deobfuscateSegment(String ciphertext, Uint8List nameKey) {
  if (ciphertext.isEmpty) return '';
  final dot = ciphertext.indexOf('.');
  if (dot < 0) throw const FormatException('not an obfuscated name');
  final numPart = ciphertext.substring(0, dot);
  final after = ciphertext.substring(dot + 1);
  if (numPart == '!') return after; // 非 UTF-8 原样透传
  var dir = int.parse(numPart);
  for (final b in nameKey) {
    dir += b;
  }
  final out = StringBuffer();
  var inQuote = false;
  for (final runeValue in after.runes) {
    if (inQuote) {
      out.writeCharCode(runeValue);
      inQuote = false;
    } else if (runeValue == obfuscQuoteRune) {
      inQuote = true;
    } else if (runeValue >= 0x30 && runeValue <= 0x39) {
      final thisdir = (dir % 9) + 1;
      var newRune = 0x30 + runeValue - 0x30 - thisdir;
      if (newRune < 0x30) newRune += 10;
      out.writeCharCode(newRune);
    } else if ((runeValue >= 0x41 && runeValue <= 0x5A) ||
        (runeValue >= 0x61 && runeValue <= 0x7A)) {
      final thisdir = (dir % 25) + 1;
      var pos = runeValue - 0x41;
      if (pos >= 26) pos -= 6;
      pos -= thisdir;
      if (pos < 0) pos += 52;
      if (pos >= 26) pos += 6;
      out.writeCharCode(0x41 + pos);
    } else if (runeValue >= 0xA0 && runeValue <= 0xFF) {
      final thisdir = (dir % 95) + 1;
      var newRune = 0xA0 + runeValue - 0xA0 - thisdir;
      if (newRune < 0xA0) newRune += 96;
      out.writeCharCode(newRune);
    } else if (runeValue >= 0x100) {
      final thisdir = (dir % 127) + 1;
      final base = runeValue - (runeValue % 256);
      var newRune = base + (runeValue - base - thisdir);
      if (newRune < base) newRune += 256;
      out.writeCharCode(newRune);
    } else {
      out.writeCharCode(runeValue);
    }
  }
  return out.toString();
}
