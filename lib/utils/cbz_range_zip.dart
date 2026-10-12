// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import '../models/webdav_stream.dart';
import 'manga_file_types.dart';

/// Thrown when the remote refuses HTTP Range (not 206) — caller must full-cache.
class CbzRangeUnsupportedException implements Exception {
  CbzRangeUnsupportedException([this.detail]);
  final String? detail;
  @override
  String toString() => detail ?? 'Range unsupported';
}

class CbzZipEntry {
  const CbzZipEntry({
    required this.name,
    required this.localHeaderOffset,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
    required this.generalBitFlag,
  });

  final String name;
  final int localHeaderOffset;
  final int compressedSize;
  final int uncompressedSize;

  /// 0 = store, 8 = deflate (PKZIP).
  final int compressionMethod;
  final int generalBitFlag;

  bool get isDirectory => name.endsWith('/');
}

/// HTTP Range ZIP: EOCD → central directory → per-entry local header + payload.
class CbzRangeZip {
  CbzRangeZip({required this.source, Dio? dio}) : _dio = dio ?? Dio();

  final WebDavStreamSource source;
  final Dio _dio;

  int? _totalSize;
  List<CbzZipEntry>? _entries;

  int? get totalSize => _totalSize;
  List<CbzZipEntry> get entries =>
      List.unmodifiable(_entries ?? const <CbzZipEntry>[]);

  /// Image entries sorted by natural manga page key.
  List<CbzZipEntry> get imageEntries {
    final list =
        [
          for (final e in entries)
            if (!e.isDirectory && isMangaImageFileName(_basename(e.name))) e,
        ]..sort(
          (a, b) =>
              mangaPageSortKey(a.name).compareTo(mangaPageSortKey(b.name)),
        );
    return list;
  }

  /// Load central directory. Throws [CbzRangeUnsupportedException] if not 206.
  Future<void> open({CancelToken? cancel}) async {
    // Probe size + Range support with a tiny tail read.
    await _rangeBytes(0, 0, cancel: cancel, allowEmpty: true);
    // Prefer Content-Range total from a real tail fetch.
    final tailWant = 65536;
    // If total unknown, try last 64KiB via suffix range first.
    Uint8List? tail;
    if (_totalSize != null && _totalSize! > 0) {
      final start = (_totalSize! - tailWant).clamp(0, _totalSize! - 1);
      tail = await _rangeBytes(start, _totalSize! - 1, cancel: cancel);
    } else {
      // bytes=-N suffix
      tail = await _rangeSuffix(tailWant, cancel: cancel);
    }
    if (tail == null || tail.length < 22) {
      throw StateError('CBZ EOCD not found');
    }
    final eocd = _findEocd(tail);
    if (eocd == null) {
      throw StateError('CBZ EOCD signature missing');
    }
    final cdSize = _u32(tail, eocd + 12);
    final cdOffset = _u32(tail, eocd + 16);
    final total = _totalSize;
    if (total == null || cdOffset + cdSize > total) {
      throw StateError('CBZ central directory out of range');
    }
    final cd = await _rangeBytes(
      cdOffset,
      cdOffset + cdSize - 1,
      cancel: cancel,
    );
    if (cd == null || cd.length < cdSize) {
      throw StateError('CBZ central directory incomplete');
    }
    _entries = _parseCentralDirectory(cd);
  }

  /// Extract one entry's uncompressed bytes via Range.
  Future<Uint8List> extractEntry(
    CbzZipEntry entry, {
    CancelToken? cancel,
  }) async {
    // Local file header is at least 30 bytes + name + extra.
    final headerPeek = await _rangeBytes(
      entry.localHeaderOffset,
      entry.localHeaderOffset + 29,
      cancel: cancel,
    );
    if (headerPeek == null || headerPeek.length < 30) {
      throw StateError('local header short');
    }
    if (_u32(headerPeek, 0) != 0x04034b50) {
      throw StateError('bad local header signature');
    }
    final nameLen = _u16(headerPeek, 26);
    final extraLen = _u16(headerPeek, 28);
    final dataStart = entry.localHeaderOffset + 30 + nameLen + extraLen;
    final dataEnd = dataStart + entry.compressedSize - 1;
    if (entry.compressedSize <= 0) {
      return Uint8List(0);
    }
    final compressed = await _rangeBytes(dataStart, dataEnd, cancel: cancel);
    if (compressed == null || compressed.length < entry.compressedSize) {
      throw StateError('compressed payload incomplete');
    }
    return _decompress(entry, compressed);
  }

  /// Find ComicInfo.xml (any folder depth, case-insensitive).
  CbzZipEntry? findComicInfo() {
    for (final e in entries) {
      if (_basename(e.name).toLowerCase() == 'comicinfo.xml') return e;
    }
    return null;
  }

  Future<Uint8List> _decompress(CbzZipEntry entry, Uint8List compressed) async {
    switch (entry.compressionMethod) {
      case 0:
        return compressed;
      case 8:
        final out = Inflate(compressed).getBytes();
        return Uint8List.fromList(out);
      default:
        throw StateError('unsupported ZIP method ${entry.compressionMethod}');
    }
  }

  Future<Uint8List?> _rangeBytes(
    int start,
    int end, {
    CancelToken? cancel,
    bool allowEmpty = false,
  }) async {
    if (end < start && !allowEmpty) return null;
    try {
      final res = await _dio.get<List<int>>(
        source.uri,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {...source.headers, 'Range': 'bytes=$start-$end'},
          validateStatus: (c) => c == 206 || c == 200,
        ),
      );
      if (res.statusCode == 200) {
        // Server ignored Range — refuse stream path.
        throw CbzRangeUnsupportedException('HTTP ${res.statusCode}');
      }
      if (res.statusCode != 206) {
        throw CbzRangeUnsupportedException('HTTP ${res.statusCode}');
      }
      _noteTotal(res.headers.value(HttpHeaders.contentRangeHeader));
      final data = res.data;
      if (data == null) return allowEmpty ? Uint8List(0) : null;
      return Uint8List.fromList(data);
    } on CbzRangeUnsupportedException {
      rethrow;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 200 || (code != null && code != 206)) {
        throw CbzRangeUnsupportedException('HTTP $code');
      }
      rethrow;
    }
  }

  Future<Uint8List?> _rangeSuffix(int length, {CancelToken? cancel}) async {
    try {
      final res = await _dio.get<List<int>>(
        source.uri,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {...source.headers, 'Range': 'bytes=-$length'},
          validateStatus: (c) => c == 206 || c == 200,
        ),
      );
      if (res.statusCode != 206) {
        throw CbzRangeUnsupportedException('HTTP ${res.statusCode}');
      }
      _noteTotal(res.headers.value(HttpHeaders.contentRangeHeader));
      final data = res.data;
      if (data == null) return null;
      return Uint8List.fromList(data);
    } on CbzRangeUnsupportedException {
      rethrow;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null && code != 206) {
        throw CbzRangeUnsupportedException('HTTP $code');
      }
      rethrow;
    }
  }

  void _noteTotal(String? contentRange) {
    if (contentRange == null) return;
    // bytes start-end/total
    final slash = contentRange.lastIndexOf('/');
    if (slash < 0) return;
    final totalStr = contentRange.substring(slash + 1).trim();
    final t = int.tryParse(totalStr);
    if (t != null && t > 0) _totalSize = t;
  }

  static int? _findEocd(Uint8List buf) {
    // Scan backwards for PK\x05\x06
    for (var i = buf.length - 22; i >= 0; i--) {
      if (buf[i] == 0x50 &&
          buf[i + 1] == 0x4b &&
          buf[i + 2] == 0x05 &&
          buf[i + 3] == 0x06) {
        return i;
      }
    }
    return null;
  }

  static List<CbzZipEntry> _parseCentralDirectory(Uint8List cd) {
    final out = <CbzZipEntry>[];
    var o = 0;
    while (o + 46 <= cd.length) {
      if (_u32(cd, o) != 0x02014b50) break;
      final flag = _u16(cd, o + 8);
      final method = _u16(cd, o + 10);
      final comp = _u32(cd, o + 20);
      final uncomp = _u32(cd, o + 24);
      final nameLen = _u16(cd, o + 28);
      final extraLen = _u16(cd, o + 30);
      final commentLen = _u16(cd, o + 32);
      final localOff = _u32(cd, o + 42);
      final nameStart = o + 46;
      final nameEnd = nameStart + nameLen;
      if (nameEnd > cd.length) break;
      final name = utf8.decode(
        cd.sublist(nameStart, nameEnd),
        allowMalformed: true,
      );
      out.add(
        CbzZipEntry(
          name: name.replaceAll('\\', '/'),
          localHeaderOffset: localOff,
          compressedSize: comp,
          uncompressedSize: uncomp,
          compressionMethod: method,
          generalBitFlag: flag,
        ),
      );
      o = nameEnd + extraLen + commentLen;
    }
    return out;
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}

/// Minimal ComicInfo.xml field scrape (title / series / writer|penciller).
class ComicInfoMeta {
  const ComicInfoMeta({
    this.title,
    this.series,
    this.writer,
    this.volume,
    this.number,
  });
  final String? title;
  final String? series;
  final String? writer;
  final String? volume;
  final String? number;

  static ComicInfoMeta? parse(Uint8List xmlBytes) {
    final text = utf8.decode(xmlBytes, allowMalformed: true);
    String? tag(String name) {
      final re = RegExp('<$name>([^<]*)</$name>', caseSensitive: false);
      final m = re.firstMatch(text);
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final title = tag('Title');
    final series = tag('Series');
    final writer = tag('Writer') ?? tag('Penciller') ?? tag('Author');
    final volume = tag('Volume');
    final number = tag('Number');
    if (title == null &&
        series == null &&
        writer == null &&
        volume == null &&
        number == null) {
      return null;
    }
    return ComicInfoMeta(
      title: title,
      series: series,
      writer: writer,
      volume: volume,
      number: number,
    );
  }
}
