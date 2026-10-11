import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dio/dio.dart';

import '../models/webdav_stream.dart';
import 'tag_service.dart';

/// What a file header is, judged by magic bytes. The suffix is not consulted.
enum EmbeddedAudio { mp3, flac, mp4, ogg, wav, none }

const int _headBytes = 64 * 1024;
const int _maxPicture = 8 * 1024 * 1024;
const int _maxOggPrefix = 4 * 1024 * 1024;

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

/// Pull embedded pictures and tags with HTTP Range only.
class StreamCoverReader {
  StreamCoverReader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Pull an embedded picture with HTTP Range only. A miss returns null.
  ///
  /// Prefer [extractTags] when the caller also needs title / artist / lyrics;
  /// this keeps the cover-only path for older call sites.
  Future<Uint8List?> extract(
    WebDavStreamSource source, {
    CancelToken? cancel,
  }) async {
    final tags = await extractTags(source, cancel: cancel);
    final cover = tags?.coverBytes;
    if (cover != null && cover.isNotEmpty) return cover;
    return null;
  }

  /// Range-read text tags, cover, and embedded lyrics into memory.
  ///
  /// Writes fetched ranges into a temporary sparse file (or an OGG prefix with
  /// a synthetic EOS page) and reuses [audio_metadata_reader] parsers.
  /// Failures return null so playback is never blocked. SYLT is not supported
  /// by the library and is skipped. Tail-only tags (APE / ID3v1 at EOF) are
  /// not fetched.
  Future<ReadTags?> extractTags(
    WebDavStreamSource source, {
    CancelToken? cancel,
  }) async {
    try {
      int? total;
      final head = await _range(
        source,
        0,
        _headBytes - 1,
        cancel: cancel,
        onTotal: (value) => total = value,
      );
      if (head == null || head.length < 12) return null;
      final src = _Src(source, this, head, total, cancel);
      switch (sniffEmbeddedAudio(head)) {
        case EmbeddedAudio.mp3:
          if (!(head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33)) {
            return null;
          }
          return await _mp3Tags(src, head);
        case EmbeddedAudio.flac:
          return await _flacTags(src);
        case EmbeddedAudio.mp4:
          return await _mp4Tags(src);
        case EmbeddedAudio.ogg:
          return await _oggTags(src);
        case EmbeddedAudio.wav:
          return await _wavTags(src);
        case EmbeddedAudio.none:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<ReadTags?> _mp3Tags(_Src src, Uint8List head) async {
    if (head.length < 10) return null;
    final tagSize = _synchsafe(head.sublist(6, 10));
    final footer = (head[5] & 0x10) != 0 ? 10 : 0;
    final total = 10 + tagSize + footer;
    if (total <= 10 || total > _maxPicture) return null;
    final bytes = await src.prefix(total);
    if (bytes == null || bytes.length < total) return null;
    return _parseId3Tags(bytes.sublist(0, total));
  }

  Future<ReadTags?> _flacTags(_Src src) async {
    var pos = 4;
    var end = 4;
    for (var step = 0; step < 64; step++) {
      final hdr = await src.at(pos, 4);
      if (hdr == null || hdr.length < 4) break;
      final last = (hdr[0] & 0x80) != 0;
      final type = hdr[0] & 0x7f;
      final len = (hdr[1] << 16) | (hdr[2] << 8) | hdr[3];
      if (len < 0) break;
      // STREAMINFO(0), VORBIS_COMMENT(4), PICTURE(6) — skip huge unknown.
      if (type == 6 && len > _maxPicture) break;
      pos = pos + 4 + len;
      end = pos;
      if (last) break;
    }
    if (end <= 4) return null;
    final bytes = await src.prefix(end);
    if (bytes == null || bytes.length < end) return null;
    return _parseWithSparse(
      bytes: bytes,
      totalSize: end,
      ext: '.flac',
      parse: (raf) {
        final meta = FlacParser(fetchImage: true).parse(raf);
        return _fromVorbis(meta);
      },
    );
  }

  Future<ReadTags?> _oggTags(_Src src) async {
    var have = src.head.length;
    var window = src.head;
    while (true) {
      final cut = _oggCommentEnd(window);
      if (cut != null) {
        final prefix = window.sublist(0, cut);
        final serial = cut >= 18
            ? _u32le(prefix, 14)
            : 0;
        final prepared = _oggWithEos(prefix, serial);
        return _parseWithSparse(
          bytes: prepared,
          totalSize: prepared.length,
          ext: '.ogg',
          parse: (raf) {
            final meta = OGGParser(fetchImage: true).parse(raf);
            return _fromVorbis(meta, dropDuration: true);
          },
        );
      }
      if (have >= _maxOggPrefix) return null;
      final next = (have * 2).clamp(have + 1, _maxOggPrefix);
      final more = await src.at(0, next);
      if (more == null || more.length <= have) return null;
      window = more;
      have = more.length;
    }
  }

  Future<ReadTags?> _mp4Tags(_Src src) async {
    final fileSize = src.total;
    if (fileSize == null || fileSize < 8) {
      // Fall back to contiguous head only.
      final tags = await _mp4TagsFromMoov(src, src.head, 0, src.head.length, null);
      return tags;
    }
    var pos = 0;
    Uint8List? ftyp;
    for (var step = 0; step < 32 && pos + 8 <= fileSize; step++) {
      final hdr = await src.at(pos, 16);
      if (hdr == null || hdr.length < 8) return null;
      final box = _box(hdr, fileSize - pos);
      if (box == null) return null;
      if (box.type == 'ftyp' && box.size <= 256 * 1024) {
        ftyp = await src.at(pos, box.size);
      }
      if (box.type == 'moov') {
        return _mp4TagsFromMoov(src, null, pos, box.size, ftyp);
      }
      if (box.size < 8) return null;
      pos += box.size;
    }
    return null;
  }

  Future<ReadTags?> _mp4TagsFromMoov(
    _Src src,
    Uint8List? already,
    int start,
    int size,
    Uint8List? ftyp,
  ) async {
    final blob = already ?? await src.at(start, size);
    if (blob == null || blob.length < 8) return null;
    final head = ftyp ?? _minimalFtyp();
    final combined = Uint8List(head.length + blob.length);
    combined.setRange(0, head.length, head);
    combined.setRange(head.length, combined.length, blob);
    return _parseWithSparse(
      bytes: combined,
      totalSize: combined.length,
      ext: '.m4a',
      parse: (raf) {
        final meta = MP4Parser(fetchImage: true).parse(raf);
        return _fromMp4(meta);
      },
    );
  }

  Future<ReadTags?> _wavTags(_Src src) async {
    final fileSize = src.total;
    var pos = 12;
    for (var step = 0; step < 64; step++) {
      if (fileSize != null && pos + 8 > fileSize) return null;
      final hdr = await src.at(pos, 8);
      if (hdr == null || hdr.length < 8) return null;
      final id = _ascii(hdr, 0, 4).toLowerCase();
      final len = hdr[4] | (hdr[5] << 8) | (hdr[6] << 16) | (hdr[7] << 24);
      if (id == 'data') return null;
      if ((id == 'id3 ' || id == 'id3') && len > 0 && len <= _maxPicture) {
        final chunk = await src.at(pos + 8, len);
        if (chunk != null && chunk.length >= 10) {
          final tags = await _parseId3Tags(
            chunk.sublist(0, len.clamp(0, chunk.length)),
          );
          if (tags != null) return tags;
        }
      }
      pos += 8 + len + (len.isOdd ? 1 : 0);
    }
    return null;
  }

  Future<Uint8List?> _range(
    WebDavStreamSource source,
    int start,
    int end, {
    CancelToken? cancel,
    void Function(int? total)? onTotal,
  }) async {
    if (end < start) return null;
    try {
      final res = await _dio.get<ResponseBody>(
        source.uri,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...source.headers, 'Range': 'bytes=$start-$end'},
          validateStatus: (code) => code == 206,
        ),
      );
      final body = res.data;
      if (res.statusCode != 206 || body == null) {
        await _drop(body);
        return null;
      }
      onTotal?.call(
        _total(_header(body.headers, HttpHeaders.contentRangeHeader)),
      );
      final want = end - start + 1;
      final out = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (cancel?.isCancelled ?? false) break;
        if (out.length >= want) break;
        final room = want - out.length;
        if (chunk.length <= room) {
          out.add(chunk);
        } else {
          out.add(chunk.sublist(0, room));
          break;
        }
      }
      await _drop(body);
      final bytes = out.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } on DioException {
      return null;
    }
  }

  Future<void> _drop(ResponseBody? body) async {
    if (body == null) return;
    try {
      final sub = body.stream.listen((_) {});
      await sub.cancel();
    } catch (_) {}
  }
}

class _Src {
  _Src(this.source, this.reader, this.head, this.total, this.cancel);

  final WebDavStreamSource source;
  final StreamCoverReader reader;
  final Uint8List head;
  int? total;
  final CancelToken? cancel;

  Future<Uint8List?> at(int start, int len) async {
    if (len <= 0) return Uint8List(0);
    if (start < 0) return null;
    final end = start + len;
    if (end <= head.length) {
      return Uint8List.sublistView(head, start, end);
    }
    final got = await reader._range(
      source,
      start,
      end - 1,
      cancel: cancel,
      onTotal: (value) => total ??= value,
    );
    if (got == null || got.isEmpty) return null;
    return got.length <= len ? got : got.sublist(0, len);
  }

  Future<Uint8List?> prefix(int len) async {
    if (len <= head.length) return Uint8List.sublistView(head, 0, len);
    return at(0, len);
  }
}

class _Box {
  const _Box(this.size, this.type, this.header);
  final int size;
  final String type;
  final int header;
}

_Box? _box(Uint8List hdr, int remaining) {
  if (hdr.length < 8) return null;
  var size = _u32(hdr, 0);
  final type = _ascii(hdr, 4, 4);
  if (type.isEmpty || !_boxName(type)) return null;
  var header = 8;
  if (size == 1) {
    if (hdr.length < 16) return null;
    size = _u64(hdr, 8);
    header = 16;
  } else if (size == 0) {
    size = remaining;
  }
  if (size < header) return null;
  return _Box(size, type, header);
}

bool _boxName(String type) {
  if (type.length != 4) return false;
  for (final code in type.codeUnits) {
    if (code < 0x20 || code > 0x7e) return false;
  }
  return true;
}

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

/// Search a contiguous moov (or a small head) for a covr box.
Uint8List _minimalFtyp() {
  final bytes = Uint8List(20);
  bytes[3] = 20;
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  bytes.setRange(8, 12, 'M4A '.codeUnits);
  bytes.setRange(16, 20, 'M4A '.codeUnits);
  return bytes;
}

Uint8List? _pick(List<Picture> pictures) {
  for (final pic in pictures) {
    if (pic.pictureType == PictureType.coverFront && pic.bytes.isNotEmpty) {
      return pic.bytes;
    }
  }
  for (final pic in pictures) {
    if (pic.bytes.isNotEmpty) return pic.bytes;
  }
  return null;
}


/// METADATA_BLOCK_PICTURE payload (FLAC picture block / Vorbis comment).
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

Future<ReadTags?> _parseId3Tags(Uint8List bytes) async {
  final file = File(
    '${Directory.systemTemp.path}/stream-tags-${DateTime.now().microsecondsSinceEpoch}.bin',
  );
  RandomAccessFile? raf;
  try {
    await file.writeAsBytes(bytes, flush: true);
    raf = file.openSync();
    final parsed = ID3v2Parser(fetchImage: true).parse(raf);
    return _fromMp3(parsed);
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
    if (file.existsSync()) file.deleteSync();
  }
}

Future<ReadTags?> _parseWithSparse({
  required Uint8List bytes,
  required int totalSize,
  required String ext,
  required ReadTags? Function(RandomAccessFile raf) parse,
}) async {
  final file = File(
    '${Directory.systemTemp.path}/stream-tags-${DateTime.now().microsecondsSinceEpoch}$ext',
  );
  RandomAccessFile? raf;
  try {
    // Contiguous tag prefix (or ftyp+moov / OGG+EOS). Sparse holes are not
    // required for the parsers we call; write only the fetched bytes.
    final slice = bytes.length <= totalSize ? bytes : bytes.sublist(0, totalSize);
    await file.writeAsBytes(slice, flush: true);
    // If callers pass a larger logical size (future sparse path), extend with
    // truncate via File.length by appending zeros only when needed.
    if (totalSize > slice.length) {
      final rafW = file.openSync(mode: FileMode.append);
      try {
        final pad = totalSize - slice.length;
        const chunk = 64 * 1024;
        var left = pad;
        final zero = Uint8List(chunk);
        while (left > 0) {
          final n = left > chunk ? chunk : left;
          rafW.writeFromSync(zero, 0, n);
          left -= n;
        }
      } finally {
        rafW.closeSync();
      }
    }
    raf = file.openSync();
    return parse(raf);
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}

ReadTags _fromMp3(Mp3Metadata m) {
  final artist = m.leadPerformer ?? m.bandOrOrchestra ?? m.originalArtist;
  final genre = m.genres.isNotEmpty
      ? m.genres.where((g) => g.trim().isNotEmpty).join(', ')
      : (m.contentType);
  final year = m.year ?? m.originalReleaseYear;
  return ReadTags(
    title: _nz(m.songName),
    artist: _nz(artist),
    albumArtist: _nz(m.bandOrOrchestra),
    album: _nz(m.album),
    durationMs: (m.duration != null && m.duration! > Duration.zero)
        ? m.duration!.inMilliseconds
        : null,
    trackNumber: m.trackNumber,
    trackTotal: m.trackTotal,
    discNumber: m.discNumber,
    discTotal: m.totalDics,
    year: (year != null && year > 0) ? year : null,
    genre: _nz(genre),
    bitrate: m.bitrate,
    sampleRate: m.samplerate,
    language: _nz(m.languages),
    lyrics: _nz(m.lyric),
    coverBytes: _pick(m.pictures),
  );
}

ReadTags _fromVorbis(VorbisMetadata m, {bool dropDuration = false}) {
  final genre = m.genres.where((g) => g.trim().isNotEmpty).join(', ');
  final year = m.date.isNotEmpty ? m.date.first.year : null;
  var lyrics = _nz(m.lyric);
  lyrics ??= _nz(m.unknowns['UNSYNCEDLYRICS']);
  lyrics ??= _nz(m.unknowns['UNSYNCED LYRICS']);
  final durationMs = dropDuration
      ? null
      : ((m.duration != null && m.duration! > Duration.zero)
          ? m.duration!.inMilliseconds
          : null);
  return ReadTags(
    title: _nz(m.title.firstOrNull),
    artist: _nz(m.artist.firstOrNull ?? m.albumArtist.firstOrNull),
    albumArtist: _nz(m.albumArtist.firstOrNull),
    album: _nz(m.album.firstOrNull),
    durationMs: durationMs,
    trackNumber: m.trackNumber.firstOrNull,
    trackTotal: m.trackTotal,
    discNumber: m.discNumber,
    discTotal: m.discTotal,
    year: (year != null && year > 0) ? year : null,
    genre: genre.isEmpty ? null : genre,
    bitrate: m.bitrate,
    sampleRate: m.sampleRate,
    language: _nz(m.language.firstOrNull),
    lyrics: lyrics,
    coverBytes: _pick(m.pictures),
  );
}

ReadTags _fromMp4(Mp4Metadata m) {
  final year = m.year?.year;
  final pics = <Picture>[];
  if (m.picture != null) pics.add(m.picture!);
  return ReadTags(
    title: _nz(m.title),
    artist: _nz(m.artist),
    album: _nz(m.album),
    durationMs: (m.duration != null && m.duration! > Duration.zero)
        ? m.duration!.inMilliseconds
        : null,
    trackNumber: m.trackNumber,
    trackTotal: m.totalTracks,
    discNumber: m.discNumber,
    discTotal: m.totalDiscs,
    year: (year != null && year > 0) ? year : null,
    genre: _nz(m.genre),
    bitrate: m.bitrate,
    sampleRate: m.sampleRate,
    lyrics: _nz(m.lyrics),
    coverBytes: _pick(pics),
  );
}

String? _nz(String? value) {
  final t = value?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}

/// Byte offset just past the OGG page that finishes the comment packet.
int? _oggCommentEnd(Uint8List data) {
  final packets = <Uint8List>[];
  final current = BytesBuilder(copy: false);
  var offset = 0;
  var packetOpen = false;
  while (offset + 27 <= data.length) {
    if (_ascii(data, offset, 4) != 'OggS') {
      return packets.length >= 2 ? offset : null;
    }
    final segments = data[offset + 26];
    final table = offset + 27;
    if (table + segments > data.length) return null;
    var body = 0;
    for (var i = 0; i < segments; i++) {
      body += data[table + i];
    }
    final bodyAt = table + segments;
    if (bodyAt + body > data.length) return null;
    var cursor = bodyAt;
    for (var i = 0; i < segments; i++) {
      final size = data[table + i];
      current.add(data.sublist(cursor, cursor + size));
      cursor += size;
      packetOpen = true;
      if (size < 255) {
        packets.add(current.takeBytes());
        packetOpen = false;
        if (packets.length >= 2) {
          return bodyAt + body;
        }
      }
    }
    offset = bodyAt + body;
  }
  if (packetOpen) return null;
  return packets.length >= 2 ? offset : null;
}

/// Append a synthetic EOS page so [OGGParser] stops without scanning zeros.
Uint8List _oggWithEos(Uint8List prefix, int serial) {
  final eos = Uint8List(27);
  eos.setRange(0, 4, 'OggS'.codeUnits);
  eos[4] = 0; // version
  eos[5] = 0x04; // EOS
  // granule 6..13 already 0
  eos[14] = serial & 0xff;
  eos[15] = (serial >> 8) & 0xff;
  eos[16] = (serial >> 16) & 0xff;
  eos[17] = (serial >> 24) & 0xff;
  // page sequence / crc left 0; segment count 0
  final out = Uint8List(prefix.length + eos.length);
  out.setRange(0, prefix.length, prefix);
  out.setRange(prefix.length, out.length, eos);
  return out;
}

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

int _synchsafe(List<int> bytes) =>
    ((bytes[0] & 0x7f) << 21) |
    ((bytes[1] & 0x7f) << 14) |
    ((bytes[2] & 0x7f) << 7) |
    (bytes[3] & 0x7f);

int _u32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _u32le(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _u64(List<int> bytes, int offset) {
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

String _ascii(List<int> bytes, int offset, int len) {
  if (offset + len > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(offset, offset + len));
}

String? _header(Map<dynamic, dynamic> headers, String name) {
  final wanted = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toString().toLowerCase() != wanted) continue;
    final value = entry.value;
    if (value is List && value.isNotEmpty) return value.first.toString();
    return value?.toString();
  }
  return null;
}

int? _total(String? header) {
  if (header == null) return null;
  final slash = header.lastIndexOf('/');
  if (slash < 0 || slash + 1 >= header.length) return null;
  return int.tryParse(header.substring(slash + 1));
}
