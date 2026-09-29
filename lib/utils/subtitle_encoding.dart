import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:enough_convert/enough_convert.dart' as extra;

/// Encodings the player can force for external / imported text subtitles.
///
/// [auto] detects. The choice lives in the player session only.
enum SubtitleEncodingChoice {
  auto,
  utf8,
  utf16le,
  utf16be,
  gbk,
  gb18030,
  big5,
}

/// A successful text decode. [name] is the encoding that won.
class DecodedSubtitle {
  const DecodedSubtitle({required this.name, required this.text});

  final String name;
  final String text;
}

const _gbk = GbkCodec(allowMalformed: false);
const _big5 = extra.Big5Codec(allowInvalid: false);
const _utf16 = Utf16Decoder();

const _subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub'};

/// Text sidecar extensions we know how to hand to mpv.
bool isTextSubtitleExtension(String extension) =>
    _subtitleExtensions.contains(extension.toLowerCase().replaceAll('.', ''));

/// VobSub / MPEG packet `.sub` payloads are not text. UTF-16 text is not binary.
bool looksLikeBinarySubtitle(List<int> bytes) {
  if (bytes.isEmpty) return true;
  if (bytes.length >= 4 &&
      bytes[0] == 0x00 &&
      bytes[1] == 0x00 &&
      bytes[2] == 0x01) {
    return true;
  }
  final n = bytes.length < 4096 ? bytes.length : 4096;
  var nuls = 0;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) nuls++;
  }
  if (nuls == 0) return false;
  if (_looksLikeUtf16(bytes, n)) return false;
  return true;
}

bool _looksLikeUtf16(List<int> bytes, int n) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    return bytes.length.isEven;
  }
  if (n < 8 || bytes.length.isOdd) return false;
  var zeroEven = 0;
  var zeroOdd = 0;
  final pairs = n ~/ 2;
  for (var i = 0; i < pairs; i++) {
    if (bytes[i * 2] == 0) zeroEven++;
    if (bytes[i * 2 + 1] == 0) zeroOdd++;
  }
  return zeroEven > pairs * 0.6 || zeroOdd > pairs * 0.6;
}

/// `.sub` that is really VobSub, or any payload we cannot decode as text.
bool subtitlePayloadIsText(List<int> bytes, String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');
  if (!isTextSubtitleExtension(ext)) return false;
  if (ext == 'sub' && looksLikeBinarySubtitle(bytes)) return false;
  if (looksLikeBinarySubtitle(bytes) && ext != 'sub') {
    // UTF-16 srt is text; other nuls are not.
    if (!_looksLikeUtf16(bytes, bytes.length < 4096 ? bytes.length : 4096)) {
      return false;
    }
  }
  return decodeSubtitleBytes(bytes) != null;
}

/// Decode [bytes] to Unicode. [override] skips detection.
///
/// Returns null when the bytes are not valid in the chosen encoding, or when
/// auto detection cannot find a decode that looks like text.
DecodedSubtitle? decodeSubtitleBytes(
  List<int> bytes, {
  SubtitleEncodingChoice? override,
}) {
  if (bytes.isEmpty) return null;
  if (looksLikeBinarySubtitle(bytes) &&
      !_hasTextBom(bytes) &&
      !_looksLikeUtf16(bytes, bytes.length < 4096 ? bytes.length : 4096)) {
    return null;
  }
  final forced = override ?? SubtitleEncodingChoice.auto;
  if (forced != SubtitleEncodingChoice.auto) {
    final text = _decodeAs(forced, bytes);
    if (text == null || _tooCorrupt(text)) return null;
    return DecodedSubtitle(name: _nameOf(forced), text: text);
  }
  final bom = _decodeBom(bytes);
  if (bom != null && !_tooCorrupt(bom.text)) return bom;

  final candidates = <DecodedSubtitle>[];
  void consider(SubtitleEncodingChoice choice, List<int> payload) {
    final text = _decodeAs(choice, payload);
    if (text == null || _tooCorrupt(text)) return;
    candidates.add(DecodedSubtitle(name: _nameOf(choice), text: text));
  }

  consider(SubtitleEncodingChoice.utf8, _stripUtf8Bom(bytes));
  if (_shouldTryUtf16(bytes)) {
    consider(SubtitleEncodingChoice.utf16le, bytes);
    consider(SubtitleEncodingChoice.utf16be, bytes);
  }
  consider(SubtitleEncodingChoice.gbk, bytes);
  consider(SubtitleEncodingChoice.gb18030, bytes);
  consider(SubtitleEncodingChoice.big5, bytes);
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final score = _score(a, bytes).compareTo(_score(b, bytes));
    if (score != 0) return score;
    return _preference(a.name).compareTo(_preference(b.name));
  });
  return candidates.first;
}

bool _hasTextBom(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return true;
  }
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    return true;
  }
  return false;
}

DecodedSubtitle? _decodeBom(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    final text = _decodeAs(SubtitleEncodingChoice.utf8, bytes.sublist(3));
    if (text == null) return null;
    return DecodedSubtitle(name: 'utf-8', text: text);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final text = _decodeAs(SubtitleEncodingChoice.utf16le, bytes);
    if (text == null) return null;
    return DecodedSubtitle(name: 'utf-16le', text: text);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final text = _decodeAs(SubtitleEncodingChoice.utf16be, bytes);
    if (text == null) return null;
    return DecodedSubtitle(name: 'utf-16be', text: text);
  }
  return null;
}

List<int> _stripUtf8Bom(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return bytes.sublist(3);
  }
  return bytes;
}

bool _shouldTryUtf16(List<int> bytes) {
  if (bytes.length < 4 || bytes.length.isOdd) return false;
  return _looksLikeUtf16(bytes, bytes.length < 4096 ? bytes.length : 4096);
}

String? _decodeAs(SubtitleEncodingChoice choice, List<int> bytes) {
  try {
    switch (choice) {
      case SubtitleEncodingChoice.auto:
        return null;
      case SubtitleEncodingChoice.utf8:
        final text = utf8.decode(_stripUtf8Bom(bytes));
        return text.replaceFirst('\uFEFF', '');
      case SubtitleEncodingChoice.utf16le:
        if (bytes.length < 2 || bytes.length.isOdd) return null;
        final text = _utf16.decodeUtf16Le(bytes);
        if (text.contains('\uFFFD')) return null;
        return text.replaceFirst('\uFEFF', '');
      case SubtitleEncodingChoice.utf16be:
        if (bytes.length < 2 || bytes.length.isOdd) return null;
        final text = _utf16.decodeUtf16Be(bytes);
        if (text.contains('\uFFFD')) return null;
        return text.replaceFirst('\uFEFF', '');
      case SubtitleEncodingChoice.gbk:
        return _gbk.decode(bytes);
      case SubtitleEncodingChoice.gb18030:
        return _decodeGb18030(bytes);
      case SubtitleEncodingChoice.big5:
        return _big5.decode(bytes);
    }
  } catch (_) {
    return null;
  }
}

String _nameOf(SubtitleEncodingChoice choice) => switch (choice) {
  SubtitleEncodingChoice.auto => 'auto',
  SubtitleEncodingChoice.utf8 => 'utf-8',
  SubtitleEncodingChoice.utf16le => 'utf-16le',
  SubtitleEncodingChoice.utf16be => 'utf-16be',
  SubtitleEncodingChoice.gbk => 'gbk',
  SubtitleEncodingChoice.gb18030 => 'gb18030',
  SubtitleEncodingChoice.big5 => 'big5',
};

int _preference(String name) => switch (name) {
  'utf-8' => 0,
  'utf-16le' => 1,
  'utf-16be' => 2,
  'gbk' => 3,
  'gb18030' => 4,
  'big5' => 5,
  _ => 9,
};

int _score(DecodedSubtitle decoded, List<int> original) {
  var bad = 0;
  var cjk = 0;
  var runes = 0;
  for (final r in decoded.text.runes) {
    runes++;
    if (r == 0xFFFD) bad += 8;
    if (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) bad += 4;
    if (r >= 0x4E00 && r <= 0x9FFF) cjk++;
  }
  var score = bad * 100 - cjk;
  if (_roundTrips(decoded, original)) score -= 10000;
  if (runes == 0) score += 100000;
  return score;
}

bool _roundTrips(DecodedSubtitle decoded, List<int> original) {
  try {
    List<int> encoded;
    switch (decoded.name) {
      case 'utf-8':
        encoded = utf8.encode(decoded.text);
        final stripped = _stripUtf8Bom(original);
        return _bytesEqual(encoded, stripped);
      case 'gbk':
        encoded = _gbk.encode(decoded.text);
        return _bytesEqual(encoded, original);
      case 'big5':
        encoded = _big5.encode(decoded.text);
        return _bytesEqual(encoded, original);
      default:
        return false;
    }
  } catch (_) {
    return false;
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _tooCorrupt(String text) {
  if (text.isEmpty) return true;
  var bad = 0;
  var n = 0;
  for (final r in text.runes) {
    n++;
    if (r == 0xFFFD || (r < 0x20 && r != 9 && r != 10 && r != 13)) bad++;
  }
  return n > 0 && bad / n > 0.25;
}

/// GB18030: 2-byte sequences go through the GBK decoder; 4-byte sequences use
/// the WHATWG `index-gb18030-ranges` pointer map. Strict: any illegal sequence
/// fails the whole buffer.
String? _decodeGb18030(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      out.writeCharCode(b);
      i++;
      continue;
    }
    if (b == 0x80) {
      out.writeCharCode(0x20AC);
      i++;
      continue;
    }
    if (b < 0x81 || b > 0xFE) return null;
    if (i + 1 >= bytes.length) return null;
    final b2 = bytes[i + 1];
    if (b2 >= 0x30 && b2 <= 0x39) {
      if (i + 3 >= bytes.length) return null;
      final b3 = bytes[i + 2];
      final b4 = bytes[i + 3];
      if (b3 < 0x81 || b3 > 0xFE || b4 < 0x30 || b4 > 0x39) return null;
      final pointer = ((b - 0x81) * 10 * 126 * 10) +
          ((b2 - 0x30) * 10 * 126) +
          ((b3 - 0x81) * 10) +
          (b4 - 0x30);
      final cp = _gb18030RangesCodePoint(pointer);
      if (cp == null) return null;
      out.writeCharCode(cp);
      i += 4;
      continue;
    }
    try {
      out.write(_gbk.decode(<int>[b, b2]));
    } catch (_) {
      return null;
    }
    i += 2;
  }
  return out.toString();
}

int? _gb18030RangesCodePoint(int pointer) {
  if ((pointer > 39419 && pointer < 189000) || pointer > 1237575) return null;
  if (pointer == 7457) return 0xE7C7;
  var offset = -1;
  var codePointOffset = 0;
  for (final row in _gb18030Ranges) {
    if (row[0] <= pointer) {
      offset = row[0];
      codePointOffset = row[1];
    } else {
      break;
    }
  }
  if (offset < 0) return null;
  final cp = codePointOffset + pointer - offset;
  if (cp < 0 || cp > 0x10FFFF) return null;
  if (cp >= 0xD800 && cp <= 0xDFFF) return null;
  return cp;
}

/// WHATWG index gb18030 ranges (pointer, code point), 2024-09-18.
const List<List<int>> _gb18030Ranges = <List<int>>[
  [0, 128],
  [36, 165],
  [38, 169],
  [45, 178],
  [50, 184],
  [81, 216],
  [89, 226],
  [95, 235],
  [96, 238],
  [100, 244],
  [103, 248],
  [104, 251],
  [105, 253],
  [109, 258],
  [126, 276],
  [133, 284],
  [148, 300],
  [172, 325],
  [175, 329],
  [179, 334],
  [208, 364],
  [306, 463],
  [307, 465],
  [308, 467],
  [309, 469],
  [310, 471],
  [311, 473],
  [312, 475],
  [313, 477],
  [341, 506],
  [428, 594],
  [443, 610],
  [544, 712],
  [545, 716],
  [558, 730],
  [741, 930],
  [742, 938],
  [749, 962],
  [750, 970],
  [805, 1026],
  [819, 1104],
  [820, 1106],
  [7922, 8209],
  [7924, 8215],
  [7925, 8218],
  [7927, 8222],
  [7934, 8231],
  [7943, 8241],
  [7944, 8244],
  [7945, 8246],
  [7950, 8252],
  [8062, 8365],
  [8148, 8452],
  [8149, 8454],
  [8152, 8458],
  [8164, 8471],
  [8174, 8482],
  [8236, 8556],
  [8240, 8570],
  [8262, 8596],
  [8264, 8602],
  [8374, 8713],
  [8380, 8720],
  [8381, 8722],
  [8384, 8726],
  [8388, 8731],
  [8390, 8737],
  [8392, 8740],
  [8393, 8742],
  [8394, 8748],
  [8396, 8751],
  [8401, 8760],
  [8406, 8766],
  [8416, 8777],
  [8419, 8781],
  [8424, 8787],
  [8437, 8802],
  [8439, 8808],
  [8445, 8816],
  [8482, 8854],
  [8485, 8858],
  [8496, 8870],
  [8521, 8896],
  [8603, 8979],
  [8936, 9322],
  [8946, 9372],
  [9046, 9548],
  [9050, 9588],
  [9063, 9616],
  [9066, 9622],
  [9076, 9634],
  [9092, 9652],
  [9100, 9662],
  [9108, 9672],
  [9111, 9676],
  [9113, 9680],
  [9131, 9702],
  [9162, 9735],
  [9164, 9738],
  [9218, 9793],
  [9219, 9795],
  [11329, 11906],
  [11331, 11909],
  [11334, 11913],
  [11336, 11917],
  [11346, 11928],
  [11361, 11944],
  [11363, 11947],
  [11366, 11951],
  [11370, 11956],
  [11372, 11960],
  [11375, 11964],
  [11389, 11979],
  [11682, 12284],
  [11686, 12292],
  [11687, 12312],
  [11692, 12319],
  [11694, 12330],
  [11714, 12351],
  [11716, 12436],
  [11723, 12447],
  [11725, 12535],
  [11730, 12543],
  [11736, 12586],
  [11982, 12842],
  [11989, 12850],
  [12102, 12964],
  [12336, 13200],
  [12348, 13215],
  [12350, 13218],
  [12384, 13253],
  [12393, 13263],
  [12395, 13267],
  [12397, 13270],
  [12510, 13384],
  [12553, 13428],
  [12851, 13727],
  [12962, 13839],
  [12973, 13851],
  [13738, 14617],
  [13823, 14703],
  [13919, 14801],
  [13933, 14816],
  [14080, 14964],
  [14298, 15183],
  [14585, 15471],
  [14698, 15585],
  [15583, 16471],
  [15847, 16736],
  [16318, 17208],
  [16434, 17325],
  [16438, 17330],
  [16481, 17374],
  [16729, 17623],
  [17102, 17997],
  [17122, 18018],
  [17315, 18212],
  [17320, 18218],
  [17402, 18301],
  [17418, 18318],
  [17859, 18760],
  [17909, 18811],
  [17911, 18814],
  [17915, 18820],
  [17916, 18823],
  [17936, 18844],
  [17939, 18848],
  [17961, 18872],
  [18664, 19576],
  [18703, 19620],
  [18814, 19738],
  [18962, 19887],
  [19043, 40870],
  [33469, 59244],
  [33470, 59336],
  [33471, 59367],
  [33484, 59413],
  [33485, 59417],
  [33490, 59423],
  [33497, 59431],
  [33501, 59437],
  [33505, 59443],
  [33513, 59452],
  [33520, 59460],
  [33536, 59478],
  [33550, 59493],
  [37845, 63789],
  [37921, 63866],
  [37948, 63894],
  [38029, 63976],
  [38038, 63986],
  [38064, 64016],
  [38065, 64018],
  [38066, 64021],
  [38069, 64025],
  [38075, 64034],
  [38076, 64037],
  [38078, 64042],
  [39108, 65074],
  [39109, 65093],
  [39113, 65107],
  [39114, 65112],
  [39115, 65127],
  [39116, 65132],
  [39265, 65375],
  [39394, 65510],
  [189000, 65536],
];

extension SubtitleEncodingChoiceX on SubtitleEncodingChoice {
  String get wireName => switch (this) {
    SubtitleEncodingChoice.auto => 'auto',
    SubtitleEncodingChoice.utf8 => 'utf-8',
    SubtitleEncodingChoice.utf16le => 'utf-16le',
    SubtitleEncodingChoice.utf16be => 'utf-16be',
    SubtitleEncodingChoice.gbk => 'gbk',
    SubtitleEncodingChoice.gb18030 => 'gb18030',
    SubtitleEncodingChoice.big5 => 'big5',
  };
}

/// UTF-8 bytes of [text], for the temp file mpv will read.
Uint8List utf8SubtitleBytes(String text) =>
    Uint8List.fromList(utf8.encode(text));
