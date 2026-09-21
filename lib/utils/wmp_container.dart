import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Fixed section ids inside a [WmpContainer].
///
/// Unknown ids are ignored on read, so new sections can be added without
/// bumping the container version.
class WmpSections {
  WmpSections._();

  /// Binary tag/value metadata (kind, rev range, device, counts…).
  static const int meta = 1;

  /// Track records (tag/value per record, self-contained).
  static const int tracks = 2;

  /// Cover image blobs — one **own copy per track**, laid out contiguously so a
  /// single cover can be read by offset without inflating anything else.
  ///
  /// There is deliberately **no** interning/dedupe here: two tracks of the same
  /// album each carry their own bytes. The contiguous layout is a seek
  /// affordance, not sharing.
  static const int covers = 3;

  /// Tombstone records (deletions), same tag/value shape as [tracks].
  static const int tombs = 4;

  /// Backup archives only: WebDAV accounts (URL/username in clear, password may
  /// be an `AESGCMv1:` blob).
  static const int credentials = 5;

  /// Backup archives only: playlists JSON payload.
  static const int playlists = 6;

  /// Backup archives only: settings JSON payload.
  static const int settings = 7;

  /// Backup archives only: CUE album rows (small JSON payload).
  static const int cueAlbums = 8;
}

/// Per-section storage codec.
class WmpCodec {
  WmpCodec._();

  static const int raw = 0;
  static const int deflate = 1;
}

/// What a container file describes.
class WmpKind {
  WmpKind._();

  /// A rebuilt base shard: a slice of the complete live library.
  static const int base = 0;

  /// An append-only delta shard (new/updated rows only).
  static const int seg = 1;

  /// An append-only tombstone shard (deletions only).
  static const int tomb = 2;

  /// A whole-app backup archive.
  static const int backup = 3;
}

/// META tag ids.
class WmpMeta {
  WmpMeta._();

  static const int kind = 1;
  static const int seqFrom = 2;
  static const int seqTo = 3;
  static const int count = 4;
  static const int deviceId = 5;
  static const int createdAt = 6;
  static const int appVersion = 7;
  static const int note = 8;
}

/// Track record tag ids (a record is `tag value… 0x00`).
class WmpTrack {
  WmpTrack._();

  static const int sourceName = 1;
  static const int remotePath = 2;
  static const int fileName = 3;
  static const int rev = 4;
  static const int title = 5;
  static const int artist = 6;
  static const int albumArtist = 7;
  static const int album = 8;
  static const int durationMs = 9;
  static const int trackNumber = 10;
  static const int trackTotal = 11;
  static const int discNumber = 12;
  static const int discTotal = 13;
  static const int year = 14;
  static const int genre = 15;
  static const int bitrate = 16;
  static const int sampleRate = 17;
  static const int cueId = 18;
  static const int cueRemotePath = 19;
  static const int cueTrackIndex = 20;
  static const int audioMusicId = 21;
  static const int audioRemotePath = 22;
  static const int clipStartMs = 23;
  static const int clipEndMs = 24;
  static const int cacheGroupId = 25;

  /// Index into the container's cover table (each entry is that track's own
  /// copy); absent means "no cover".
  static const int coverIndex = 26;

  static const int lastDownloadedAt = 28;
  static const int lastTagReadAt = 29;
}

/// Tombstone record tag ids.
class WmpTomb {
  WmpTomb._();

  static const int sourceName = 1;
  static const int remotePath = 2;
  static const int rev = 3;
  static const int deletedAt = 4;
}

/// Encoding of an inline cover blob.
class WmpImageKind {
  WmpImageKind._();

  static const int none = 0;
  static const int webp = 1;
  static const int jpeg = 2;
  static const int png = 3;

  /// Best-effort guess from the bytes' magic number.
  static int detect(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return webp;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return jpeg;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return png;
    }
    return none;
  }

  static String extensionFor(int kind) => switch (kind) {
    webp => 'webp',
    jpeg => 'jpg',
    png => 'png',
    _ => 'bin',
  };

  static String mimeFor(int kind) => switch (kind) {
    webp => 'image/webp',
    jpeg => 'image/jpeg',
    png => 'image/png',
    _ => 'application/octet-stream',
  };
}

/// Where a section lives inside the encoded container.
class WmpSectionInfo {
  const WmpSectionInfo({
    required this.id,
    required this.codec,
    required this.offset,
    required this.storedLength,
    required this.rawLength,
    required this.crc32,
  });

  final int id;
  final int codec;

  /// Byte offset of the stored payload, from the start of the file. A
  /// file-based reader can fetch just this range.
  final int offset;
  final int storedLength;
  final int rawLength;
  final int crc32;
}

/// Thrown for malformed input; never for a merely unknown section id.
class WmpFormatException implements Exception {
  const WmpFormatException(this.message);

  final String message;

  @override
  String toString() => 'WmpFormatException: $message';
}

/// Immutable per-track cover entry in the container's cover table.
class WmpCoverEntry {
  const WmpCoverEntry({
    required this.offset,
    required this.length,
    required this.kind,
  });

  /// Byte offset of this entry's image bytes inside the COVERS section.
  final int offset;
  final int length;

  /// See [WmpImageKind].
  final int kind;

  Uint8List bytesIn(Uint8List section) =>
      Uint8List.sublistView(section, offset, offset + length);
}

/// Build a COVERS section from one blob per track.
///
/// Layout: `[u8 kind][u32 length][bytes]` repeated. Each track's image is its
/// **own** copy — the contiguous layout exists so a reader can seek to a single
/// cover without inflating anything, not to share bytes between tracks.
Uint8List buildCoverSection(List<({Uint8List bytes, int kind})> covers) {
  final out = BytesBuilder();
  for (final cover in covers) {
    out.addByte(cover.kind);
    out.add(
      Uint8List.fromList([
        cover.bytes.length & 0xFF,
        (cover.bytes.length >> 8) & 0xFF,
        (cover.bytes.length >> 16) & 0xFF,
        (cover.bytes.length >> 24) & 0xFF,
      ]),
    );
    out.add(cover.bytes);
  }
  return out.toBytes();
}

/// Parse a COVERS section produced by [buildCoverSection].
List<WmpCoverEntry> parseCoverSection(Uint8List section) {
  final out = <WmpCoverEntry>[];
  var at = 0;
  while (at < section.length) {
    if (at + 5 > section.length) {
      throw const WmpFormatException('truncated cover entry header');
    }
    final kind = section[at];
    final length = WmpContainer._u32(section, at + 1);
    final start = at + 5;
    if (start + length > section.length) {
      throw const WmpFormatException('cover entry runs past end of section');
    }
    out.add(WmpCoverEntry(offset: start, length: length, kind: kind));
    at = start + length;
  }
  return out;
}

/// A tiny self-describing binary container.
///
/// Layout:
/// ```
/// 'WMPC' | u16 version | u16 sectionCount | u32 reserved
/// section table: sectionCount × 18 bytes
///   u8 id | u8 codec | u32 offset | u32 storedLen | u32 rawLen | u32 crc32
/// payload: sections back to back
/// ```
///
/// Why not ZIP: covers are already-compressed images (deflate would waste CPU),
/// and a plain byte range lets a reader pull a single cover without inflating
/// the record block. CRC32 + per-section lengths make corruption detectable
/// per section instead of per file.
class WmpContainer {
  WmpContainer._(this._bytes, this.sections);

  static const List<int> magic = [0x57, 0x4D, 0x50, 0x43]; // 'WMPC'
  static const int version = 1;
  static const int headerLength = 12;
  static const int entryLength = 18;

  final Uint8List _bytes;
  final List<WmpSectionInfo> sections;

  /// Section ids present, in file order.
  List<int> get sectionIds => [for (final s in sections) s.id];

  bool has(int id) => sections.any((s) => s.id == id);

  WmpSectionInfo? info(int id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Raw stored bytes of a section (still deflated when its codec says so).
  ///
  /// Kept public so a file-backed reader can pull one range with a single seek.
  Uint8List storedBytes(int id) {
    final s = info(id);
    if (s == null) return Uint8List(0);
    return Uint8List.sublistView(_bytes, s.offset, s.offset + s.storedLength);
  }

  /// Decoded bytes of a section, or null when the section is absent.
  Uint8List? readSection(int id) {
    final s = info(id);
    if (s == null) return null;
    final stored = storedBytes(id);
    final raw = s.codec == WmpCodec.deflate ? _inflate(stored) : stored;
    if (raw.length != s.rawLength) {
      throw WmpFormatException(
        'section ${s.id} length mismatch: got ${raw.length}, want ${s.rawLength}',
      );
    }
    if (crc32(raw) != s.crc32) {
      throw WmpFormatException('section ${s.id} CRC mismatch');
    }
    return raw;
  }

  /// Cheap magic check, so a caller can tell a container from a JSON export (or
  /// anything else) before parsing.
  static bool looksLikeContainer(Uint8List bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// Parse just the header + section table.
  static WmpContainer fromBytes(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw const WmpFormatException('file too short');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const WmpFormatException('bad magic');
      }
    }
    final ver = _u16(bytes, 4);
    if (ver != version) {
      throw WmpFormatException('unsupported container version $ver');
    }
    final count = _u16(bytes, 6);
    final tableEnd = headerLength + count * entryLength;
    if (bytes.length < tableEnd) {
      throw const WmpFormatException('truncated section table');
    }
    final out = <WmpSectionInfo>[];
    for (var i = 0; i < count; i++) {
      final base = headerLength + i * entryLength;
      final info = WmpSectionInfo(
        id: bytes[base],
        codec: bytes[base + 1],
        offset: _u32(bytes, base + 2),
        storedLength: _u32(bytes, base + 6),
        rawLength: _u32(bytes, base + 10),
        crc32: _u32(bytes, base + 14),
      );
      if (info.offset + info.storedLength > bytes.length) {
        throw WmpFormatException('section ${info.id} runs past end of file');
      }
      out.add(info);
    }
    return WmpContainer._(bytes, out);
  }

  /// Build a container from raw section payloads.
  ///
  /// [rawIds] are stored uncompressed (use it for sections holding
  /// already-compressed bytes, such as covers).
  static Uint8List encode(
    Map<int, Uint8List> sections, {
    Set<int> rawIds = const {},
  }) {
    final ids = sections.keys.toList()..sort();
    final stored = <int, Uint8List>{};
    for (final id in ids) {
      final raw = sections[id]!;
      stored[id] = rawIds.contains(id) ? raw : _deflate(raw);
    }
    var offset = headerLength + ids.length * entryLength;
    final header = BytesBuilder();
    header.add(magic);
    header.add(_u16Bytes(version));
    header.add(_u16Bytes(ids.length));
    header.add(_u32Bytes(0));
    final payload = BytesBuilder();
    for (final id in ids) {
      final raw = sections[id]!;
      final blob = stored[id]!;
      final entry = BytesBuilder();
      entry.addByte(id);
      entry.addByte(rawIds.contains(id) ? WmpCodec.raw : WmpCodec.deflate);
      entry.add(_u32Bytes(offset));
      entry.add(_u32Bytes(blob.length));
      entry.add(_u32Bytes(raw.length));
      entry.add(_u32Bytes(crc32(raw)));
      header.add(entry.toBytes());
      payload.add(blob);
      offset += blob.length;
    }
    final out = BytesBuilder()
      ..add(header.toBytes())
      ..add(payload.toBytes());
    return out.toBytes();
  }

  static Uint8List _deflate(Uint8List raw) =>
      Uint8List.fromList(ZLibCodec(raw: true).encode(raw));

  static Uint8List _inflate(Uint8List stored) {
    try {
      return Uint8List.fromList(ZLibCodec(raw: true).decode(stored));
    } catch (e) {
      throw WmpFormatException('deflate failed: $e');
    }
  }

  static int _u16(Uint8List b, int at) => b[at] | (b[at + 1] << 8);

  static int _u32(Uint8List b, int at) =>
      b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

  static Uint8List _u16Bytes(int v) =>
      Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);

  static Uint8List _u32Bytes(int v) => Uint8List.fromList([
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ]);
}

/// Standard CRC-32 (IEEE), used for per-section integrity.
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte & 0xFF;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Writer for one tag/value record.
///
/// Supported values: `int` (varint) and `String` (UTF-8, length-prefixed).
class WmpRecordWriter {
  final BytesBuilder _out = BytesBuilder();

  void integer(int tag, int? value) {
    if (value == null) return;
    _out.addByte(tag);
    _out.add(encodeVarint(value));
  }

  void text(int tag, String? value) {
    if (value == null) return;
    _out.addByte(tag);
    final bytes = utf8.encode(value);
    _out.add(encodeVarint(bytes.length));
    _out.add(bytes);
  }

  Uint8List finish() {
    _out.addByte(0);
    return _out.toBytes();
  }
}

/// Encode a list of records back to back.
Uint8List encodeRecords(List<Map<int, Object?>> records) {
  final out = BytesBuilder();
  for (final record in records) {
    final tags = record.keys.toList()..sort();
    final w = WmpRecordWriter();
    for (final tag in tags) {
      final value = record[tag];
      switch (value) {
        case null:
          break;
        case int v:
          w.integer(tag, v);
        case String v:
          w.text(tag, v);
        default:
          throw WmpFormatException(
            'record tag $tag has unsupported type ${value.runtimeType}',
          );
      }
    }
    out.add(w.finish());
  }
  return out.toBytes();
}

/// Decode records produced by [encodeRecords].
///
/// [intTags] must list every tag in this section that holds a varint; everything
/// else is a UTF-8 string. Tags are numbered per section family (tag 1 is
/// `META.kind` *and* `TRACK.sourceName`), so the expected type has to come from
/// the caller rather than a global table.
List<Map<int, Object?>> decodeRecords(
  Uint8List raw, {
  required Set<int> intTags,
}) {
  final out = <Map<int, Object?>>[];
  var at = 0;
  Map<int, Object?>? current = <int, Object?>{};
  while (at < raw.length) {
    final tag = raw[at++];
    if (tag == 0) {
      out.add(current!);
      current = <int, Object?>{};
      continue;
    }
    final (value, next) = _readValue(raw, at, intTags.contains(tag));
    at = next;
    current![tag] = value;
  }
  if (current!.isNotEmpty) {
    throw const WmpFormatException('record not terminated');
  }
  return out;
}

(Object, int) _readValue(Uint8List raw, int at, bool isInt) {
  final (length, afterLength) = decodeVarint(raw, at);
  if (isInt) return (length, afterLength);
  final end = afterLength + length;
  if (end > raw.length) {
    throw const WmpFormatException('text runs past end of record');
  }
  return (utf8.decode(Uint8List.sublistView(raw, afterLength, end)), end);
}

/// Varint tags inside the META section.
const Set<int> kMetaIntTags = {
  WmpMeta.kind,
  WmpMeta.seqFrom,
  WmpMeta.seqTo,
  WmpMeta.count,
};

/// Varint tags inside the TRACKS section.
const Set<int> kTrackIntTags = {
  WmpTrack.rev,
  WmpTrack.durationMs,
  WmpTrack.trackNumber,
  WmpTrack.trackTotal,
  WmpTrack.discNumber,
  WmpTrack.discTotal,
  WmpTrack.year,
  WmpTrack.bitrate,
  WmpTrack.sampleRate,
  WmpTrack.cueTrackIndex,
  WmpTrack.clipStartMs,
  WmpTrack.clipEndMs,
  WmpTrack.coverIndex,
};

/// Varint tags inside the TOMBS section.
const Set<int> kTombIntTags = {WmpTomb.rev};

/// Varint (LEB128) helpers, shared by every record in the container.
Uint8List encodeVarint(int value) {
  if (value < 0) {
    throw WmpFormatException('varint cannot encode negative value $value');
  }
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return Uint8List.fromList(out);
}

(int, int) decodeVarint(Uint8List raw, int at) {
  var result = 0;
  var shift = 0;
  var i = at;
  while (true) {
    if (i >= raw.length) {
      throw const WmpFormatException('truncated varint');
    }
    final byte = raw[i++];
    result |= (byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) break;
    shift += 7;
    if (shift > 63) {
      throw const WmpFormatException('varint too long');
    }
  }
  return (result, i);
}
