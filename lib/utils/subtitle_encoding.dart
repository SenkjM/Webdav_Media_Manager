import 'dart:convert';
import 'dart:typed_data';

import '../services/rust_core_service.dart';

/// Encodings the player can force for external / imported text subtitles.
///
/// [auto] detects. The choice lives in the player session only. Detection and
/// decoding are owned by Rust (`wdmm_subtitle_decode` / `_as`); this file is
/// only the thin model + call site.
enum SubtitleEncodingChoice {
  auto,
  utf8,
  utf16le,
  utf16be,
  gbk,
  gb18030,
  big5,
}

/// A successful text decode. [name] is the encoding Rust reported.
class DecodedSubtitle {
  const DecodedSubtitle({required this.name, required this.text});

  final String name;
  final String text;
}

/// Outcome of [decodeSubtitleBytes].
///
/// The failure reason is kept because callers distinguish a payload that is not
/// text at all (`binary`) from text that none of the candidate encodings could
/// decode (`decode`): the binder drops `.sub` sidecars only for `binary`.
class SubtitleDecodeResult {
  const SubtitleDecodeResult._({this.subtitle, this.reason});

  const SubtitleDecodeResult.ok(DecodedSubtitle subtitle)
    : this._(subtitle: subtitle);

  /// [reason] is `binary` or `decode`.
  const SubtitleDecodeResult.failed(String reason) : this._(reason: reason);

  final DecodedSubtitle? subtitle;
  final String? reason;

  bool get ok => subtitle != null;
}

const _subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub', 'smi'};

/// Text sidecar extensions we know how to hand to mpv.
bool isTextSubtitleExtension(String extension) =>
    _subtitleExtensions.contains(extension.toLowerCase().replaceAll('.', ''));

/// Decode [bytes], detecting the charset unless [override] forces one.
///
/// Rust answers `{"ok":false,"reason":"binary"|"not_text"}` for payloads it
/// cannot decode; both collapse into [SubtitleDecodeResult.reason] (`binary`
/// only when Rust said so).
SubtitleDecodeResult decodeSubtitleBytes(
  List<int> bytes, {
  SubtitleEncodingChoice? override,
}) {
  final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final forced = override;
  final reply =
      forced == null || forced == SubtitleEncodingChoice.auto
      ? RustCoreService.subtitleDecode(payload)
      : RustCoreService.subtitleDecodeAs(payload, _ffiWireName(forced));
  return _parseReply(reply);
}

SubtitleDecodeResult _parseReply(String? reply) {
  if (reply == null || reply.startsWith('error:')) {
    return const SubtitleDecodeResult.failed('decode');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(reply);
  } catch (_) {
    return const SubtitleDecodeResult.failed('decode');
  }
  if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
    return SubtitleDecodeResult.failed(
      decoded is Map<String, dynamic> && decoded['reason'] == 'binary'
          ? 'binary'
          : 'decode',
    );
  }
  final text = decoded['text'];
  if (text is! String) return const SubtitleDecodeResult.failed('decode');
  final name = decoded['encoding'];
  return SubtitleDecodeResult.ok(
    DecodedSubtitle(name: name is String ? name : 'utf-8', text: text),
  );
}

/// `.sub` that is really VobSub, or any payload Rust cannot decode as text.
bool subtitlePayloadIsText(List<int> bytes, String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');
  if (!isTextSubtitleExtension(ext)) return false;
  return decodeSubtitleBytes(bytes).ok;
}

/// FFI wire name used by the forced-decode entry point.
String _ffiWireName(SubtitleEncodingChoice choice) => switch (choice) {
  SubtitleEncodingChoice.utf8 => 'utf8',
  SubtitleEncodingChoice.utf16le => 'utf16le',
  SubtitleEncodingChoice.utf16be => 'utf16be',
  SubtitleEncodingChoice.gbk => 'gbk',
  SubtitleEncodingChoice.gb18030 => 'gb18030',
  SubtitleEncodingChoice.big5 => 'big5',
  SubtitleEncodingChoice.auto => 'utf8',
};

extension SubtitleEncodingChoiceX on SubtitleEncodingChoice {
  /// Display/selection name. Persisted in the binder's `side:` / `manual:`
  /// selection keys through [VideoSubtitleBinder]-style suffixes, so these
  /// values must not change.
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
