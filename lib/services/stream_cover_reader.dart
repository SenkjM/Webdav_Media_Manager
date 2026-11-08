import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/webdav_stream.dart';
import 'rust_core_service.dart';
import 'tag_service.dart';

/// What a file header is, judged by magic bytes. The suffix is not consulted.
enum EmbeddedAudio { mp3, flac, mp4, ogg, wav, none }

/// Classify a file header by magic bytes.
///
/// Kept as a pure helper for callers that only have a small header buffer (the
/// tag extraction itself is owned by Rust now).
EmbeddedAudio sniffEmbeddedAudio(Uint8List head) {
  if (head.length < 12) return EmbeddedAudio.none;
  if (head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
    return EmbeddedAudio.mp3;
  }
  if (head[0] == 0x66 &&
      head[1] == 0x4c &&
      head[2] == 0x61 &&
      head[3] == 0x43) {
    return EmbeddedAudio.flac;
  }
  if (_ascii(head, 4, 4) == 'ftyp') return EmbeddedAudio.mp4;
  if (_ascii(head, 0, 4) == 'OggS') return EmbeddedAudio.ogg;
  if (_ascii(head, 0, 4) == 'RIFF' && _ascii(head, 8, 4) == 'WAVE') {
    return EmbeddedAudio.wav;
  }
  if (_mp3Frame(head)) return EmbeddedAudio.mp3;
  return EmbeddedAudio.none;
}

/// Thin facade over Rust's `wdmm_tags_extract`.
///
/// Tags, duration, bitrate and embedded covers are extracted by Rust through
/// `read_account_range` (byte ranges only — the file is never downloaded in
/// full). This class exists for call-site compatibility and does not perform any
/// HTTP, Range requests, or temp-file parsing in Dart.
class StreamCoverReader {
  const StreamCoverReader();

  /// Pull an embedded picture. A miss (or a probe failure) returns null.
  ///
  /// [cancel] is accepted for call-site compatibility only: the Rust range read
  /// cannot be interrupted from Dart.
  Future<Uint8List?> extract(
    WebDavStreamSource source, {
    Object? cancel,
  }) async {
    final tags = await extractTags(source, cancel: cancel);
    final cover = tags?.coverBytes;
    if (cover != null && cover.isNotEmpty) return cover;
    return null;
  }

  /// Read tags, properties and embedded cover into a [ReadTags].
  ///
  /// A null result means the file has no readable tags (or the native library is
  /// unavailable); it is not an error the caller must report.
  Future<ReadTags?> extractTags(
    WebDavStreamSource source, {
    Object? cancel,
  }) async {
    final accountId = source.accountId;
    final remotePath = source.remotePath;
    final raw = await Isolate.run(
      () => RustCoreService.tagsExtract(accountId, remotePath),
    );
    return _parseTags(raw);
  }
}

ReadTags? _parseTags(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['ok'] == false) return null;
  final tags = decoded['tags'];
  final values = tags is Map ? tags : const <Object?, Object?>{};
  return ReadTags(
    title: _text(values['title']),
    artist: _text(values['artist']),
    albumArtist: _text(values['album_artist']),
    album: _text(values['album']),
    durationMs: _int(decoded['duration_ms']),
    trackNumber: _int(values['track']),
    trackTotal: _int(values['track_total']),
    discNumber: _int(values['disc']),
    discTotal: _int(values['disc_total']),
    year: _int(values['year']),
    genre: _text(values['genre']),
    bitrate: _int(decoded['bitrate']),
    sampleRate: _int(decoded['sample_rate']),
    language: _text(values['language']),
    lyrics: _text(values['lyrics']),
    coverBytes: _coverBytes(decoded['cover']),
  );
}

Uint8List? _coverBytes(Object? cover) {
  if (cover is! Map) return null;
  final encoded = cover['bytes_b64'];
  if (encoded is! String || encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } catch (_) {
    // A malformed cover payload means "no cover"; metadata still displays.
    return null;
  }
}

String? _text(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Extract the JPEG/PNG payload from an MP4 `covr` box.
///
/// Pure byte helper kept for callers that already hold the box bytes; tag
/// extraction proper happens in Rust.
Uint8List? imageFromCovrBox(Uint8List box) {
  if (box.length < 16 || _ascii(box, 4, 4) != 'covr') return null;
  final payload = box.sublist(8);
  final Uint8List data;
  if (payload.length >= 16 && _ascii(payload, 4, 4) == 'data') {
    data = payload.sublist(16);
  } else if (payload.length > 4) {
    data = payload.sublist(4);
  } else {
    return null;
  }
  return data.isEmpty ? null : Uint8List.fromList(data);
}

/// Extract the picture payload from a FLAC/Vorbis METADATA_BLOCK_PICTURE block.
Uint8List? decodePictureBlock(Uint8List block) {
  var offset = 0;
  int need(int n) {
    if (offset + n > block.length) return -1;
    final value = _u32(block, offset);
    offset += n;
    return value;
  }

  final type = need(4);
  final mimeLen = need(4);
  if (type < 0 || mimeLen < 0 || mimeLen > 256) return null;
  if (offset + mimeLen > block.length) return null;
  offset += mimeLen;
  final descLen = need(4);
  if (descLen < 0 || offset + descLen + 16 + 4 > block.length) return null;
  offset += descLen + 16;
  final dataLen = need(4);
  if (dataLen <= 0 || offset + dataLen > block.length) return null;
  return Uint8List.fromList(block.sublist(offset, offset + dataLen));
}

int _u32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

bool _mp3Frame(Uint8List head) {
  if (head.length < 4 || head[0] != 0xff || (head[1] & 0xe0) != 0xe0) {
    return false;
  }
  final version = (head[1] >> 3) & 0x03;
  final layer = (head[1] >> 1) & 0x03;
  if (version == 1 || layer == 0) return false;
  final bitrate = (head[2] >> 4) & 0x0f;
  final sample = (head[2] >> 2) & 0x03;
  if (bitrate == 0 || bitrate == 0x0f || sample == 0x03) return false;
  return true;
}

String _ascii(List<int> bytes, int offset, int len) {
  if (offset + len > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(offset, offset + len));
}
