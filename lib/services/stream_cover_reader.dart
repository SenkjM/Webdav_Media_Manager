import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dio/dio.dart';

import '../models/webdav_stream.dart';

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

/// Pull an embedded picture with HTTP Range only. A miss returns null.
class StreamCoverReader {
  StreamCoverReader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<Uint8List?> extract(
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
          return await _mp3(src, head);
        case EmbeddedAudio.flac:
          return await _flac(src);
        case EmbeddedAudio.mp4:
          return await _mp4(src);
        case EmbeddedAudio.ogg:
          return await _ogg(src);
        case EmbeddedAudio.wav:
          return await _wav(src);
        case EmbeddedAudio.none:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _mp3(_Src src, Uint8List head) async {
    if (head.length < 10) return null;
    final tagSize = _synchsafe(head.sublist(6, 10));
    final footer = (head[5] & 0x10) != 0 ? 10 : 0;
    final total = 10 + tagSize + footer;
    if (total <= 10 || total > _maxPicture) return null;
    final bytes = await src.prefix(total);
    if (bytes == null || bytes.length < total) return null;
    return _id3(bytes.sublist(0, total));
  }

  Future<Uint8List?> _flac(_Src src) async {
    Uint8List? first;
    var pos = 4;
    for (var step = 0; step < 64; step++) {
      final hdr = await src.at(pos, 4);
      if (hdr == null || hdr.length < 4) return first;
      final last = (hdr[0] & 0x80) != 0;
      final type = hdr[0] & 0x7f;
      final len = (hdr[1] << 16) | (hdr[2] << 8) | hdr[3];
      final dataAt = pos + 4;
      if (type == 6 && len > 0 && len <= _maxPicture) {
        final block = await src.at(dataAt, len);
        if (block != null && block.length >= len) {
          final slice = block.sublist(0, len);
          final image = decodePictureBlock(slice);
          if (image != null) {
            if (slice.length >= 4 && _u32(slice, 0) == 3) return image;
            first ??= image;
          }
        }
      } else if (len < 0 || (len > _maxPicture && type == 6)) {
        return first;
      }
      pos = dataAt + len;
      if (last) break;
    }
    return first;
  }

  Future<Uint8List?> _ogg(_Src src) async {
    var have = src.head.length;
    var window = src.head;
    while (true) {
      final image = _oggIn(window);
      if (image != null) return image;
      if (_oggCommentComplete(window) || have >= _maxOggPrefix) return null;
      final next = (have * 2).clamp(have + 1, _maxOggPrefix);
      final more = await src.at(0, next);
      if (more == null || more.length <= have) return null;
      window = more;
      have = more.length;
    }
  }

  Future<Uint8List?> _mp4(_Src src) async {
    final fileSize = src.total;
    if (fileSize == null || fileSize < 8) {
      return _moovIn(src, src.head, 0, src.head.length);
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
        return _moov(src, pos, box.size, ftyp);
      }
      if (box.size < 8) return null;
      pos += box.size;
    }
    return null;
  }

  Future<Uint8List?> _moov(
    _Src src,
    int start,
    int size,
    Uint8List? ftyp,
  ) async {
    if (size < 8 || size > _maxPicture) {
      final nested = await _walkCovr(src, start + 8, size - 8, 0);
      return nested;
    }
    final blob = await src.at(start, size);
    if (blob == null) return null;
    final local = await _moovIn(src, blob, 0, blob.length);
    if (local != null) return local;
    final head = ftyp ?? _minimalFtyp();
    return _mp4Parser(head, blob);
  }

  Future<Uint8List?> _wav(_Src src) async {
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
          final image = await _id3(
            chunk.sublist(0, len.clamp(0, chunk.length)),
          );
          if (image != null) return image;
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

const _containers = {
  'moov',
  'udta',
  'ilst',
  'trak',
  'mdia',
  'minf',
  'stbl',
  'meta',
};

Future<Uint8List?> _walkCovr(_Src src, int start, int size, int depth) async {
  if (depth > 8 || size < 8) return null;
  final end = start + size;
  var pos = start;
  if (size >= 8) {
    final probe = await src.at(start, 8);
    if (probe != null && probe.length >= 8) {
      final child = _u32(probe, 0);
      final name = _ascii(probe, 4, 4);
      final plausible = child >= 8 && child <= size && _boxName(name);
      if (!plausible) pos += 4;
    }
  }
  for (var step = 0; step < 48 && pos + 8 <= end; step++) {
    final hdr = await src.at(pos, 16);
    if (hdr == null || hdr.length < 8) return null;
    final box = _box(hdr, end - pos);
    if (box == null) return null;
    if (box.type == 'covr' && box.size <= _maxPicture) {
      final raw = await src.at(pos, box.size);
      if (raw != null) {
        final image = imageFromCovrBox(raw);
        if (image != null && image.isNotEmpty) return image;
      }
    } else if (_containers.contains(box.type)) {
      final found = await _walkCovr(
        src,
        pos + box.header,
        box.size - box.header,
        depth + 1,
      );
      if (found != null) return found;
    }
    pos += box.size;
  }
  return null;
}

Future<Uint8List?> _moovIn(
  _Src src,
  Uint8List bytes,
  int start,
  int size,
) async {
  final image = imageFromCovrBoxTree(bytes);
  return image;
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
Uint8List? imageFromCovrBoxTree(Uint8List bytes) {
  Uint8List? walk(int start, int end, int depth) {
    if (depth > 8 || end - start < 8) return null;
    var pos = start;
    if (end - start >= 8) {
      final child = _u32(bytes, start);
      final name = _ascii(bytes, start + 4, 4);
      if (!(child >= 8 && child <= end - start && _boxName(name))) {
        pos += 4;
      }
    }
    while (pos + 8 <= end) {
      final size = _u32(bytes, pos);
      final type = _ascii(bytes, pos + 4, 4);
      if (!_boxName(type) || size < 8 || pos + size > end) return null;
      if (type == 'covr') {
        return imageFromCovrBox(bytes.sublist(pos, pos + size));
      }
      if (_containers.contains(type)) {
        final found = walk(pos + 8, pos + size, depth + 1);
        if (found != null) return found;
      }
      pos += size;
    }
    return null;
  }

  return walk(0, bytes.length, 0);
}

Future<Uint8List?> _mp4Parser(Uint8List ftyp, Uint8List moov) async {
  final file = File(
    '${Directory.systemTemp.path}/stream-cover-${DateTime.now().microsecondsSinceEpoch}.m4a',
  );
  RandomAccessFile? raf;
  try {
    await file.writeAsBytes([...ftyp, ...moov], flush: true);
    raf = file.openSync();
    final parsed = MP4Parser(fetchImage: true).parse(raf);
    final bytes = parsed.picture?.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
    if (file.existsSync()) file.deleteSync();
  }
}

Uint8List _minimalFtyp() {
  final bytes = Uint8List(20);
  bytes[3] = 20;
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  bytes.setRange(8, 12, 'M4A '.codeUnits);
  bytes.setRange(16, 20, 'M4A '.codeUnits);
  return bytes;
}

Future<Uint8List?> _id3(Uint8List bytes) async {
  final file = File(
    '${Directory.systemTemp.path}/stream-cover-${DateTime.now().microsecondsSinceEpoch}.bin',
  );
  RandomAccessFile? raf;
  try {
    await file.writeAsBytes(bytes, flush: true);
    raf = file.openSync();
    final parsed = ID3v2Parser(fetchImage: true).parse(raf);
    return _pick(parsed.pictures);
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
    if (file.existsSync()) file.deleteSync();
  }
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

bool _oggCommentComplete(Uint8List data) => _oggPackets(data) != null;

Uint8List? _oggIn(Uint8List data) {
  final packets = _oggPackets(data);
  if (packets == null || packets.length < 2) return null;
  final comment = packets[1];
  final body = _commentBody(comment);
  if (body == null) return null;
  return _pictureFromVorbis(body);
}

Uint8List? _commentBody(Uint8List packet) {
  if (packet.length >= 8 && _ascii(packet, 0, 8) == 'OpusTags') {
    return packet.sublist(8);
  }
  if (packet.length >= 7 &&
      packet[0] == 3 &&
      _ascii(packet, 1, 6) == 'vorbis') {
    return packet.sublist(7);
  }
  return null;
}

Uint8List? _pictureFromVorbis(Uint8List body) {
  var offset = 0;
  if (body.length < 8) return null;
  final vendor = _u32le(body, offset);
  offset += 4 + vendor;
  if (vendor < 0 || offset + 4 > body.length) return null;
  final count = _u32le(body, offset);
  offset += 4;
  Uint8List? first;
  for (var i = 0; i < count; i++) {
    if (offset + 4 > body.length) return first;
    final len = _u32le(body, offset);
    offset += 4;
    if (len < 0 || offset + len > body.length) return first;
    final comment = utf8.decode(
      body.sublist(offset, offset + len),
      allowMalformed: true,
    );
    offset += len;
    final eq = comment.indexOf('=');
    if (eq <= 0) continue;
    if (comment.substring(0, eq).toUpperCase() != 'METADATA_BLOCK_PICTURE') {
      continue;
    }
    try {
      final decoded = base64.decode(comment.substring(eq + 1).trim());
      final image = decodePictureBlock(decoded);
      if (image == null || image.isEmpty) continue;
      final type = _u32(decoded, 0);
      if (type == 3) return image;
      first ??= image;
    } catch (_) {}
  }
  return first;
}

List<Uint8List>? _oggPackets(Uint8List data) {
  final packets = <Uint8List>[];
  final current = BytesBuilder(copy: false);
  var offset = 0;
  var packetOpen = false;
  while (offset + 27 <= data.length) {
    if (_ascii(data, offset, 4) != 'OggS') {
      return packets.length >= 2 ? packets : null;
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
        if (packets.length >= 2) return packets;
      }
    }
    offset = bodyAt + body;
  }
  if (packetOpen) return null;
  return packets.length >= 2 ? packets : null;
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
