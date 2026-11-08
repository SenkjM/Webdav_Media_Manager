// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/webdav_stream.dart';
import '../services/rust_core_service.dart';

/// Thrown when the remote refuses HTTP Range (not 206) — caller must full-cache.
class CbzRangeUnsupportedException implements Exception {
  CbzRangeUnsupportedException([this.detail]);
  final String? detail;
  @override
  String toString() => detail ?? 'Range unsupported';
}

/// One central-directory entry, as reported by `wdmm_zip_open`.
class CbzZipEntry {
  const CbzZipEntry({
    required this.index,
    required this.name,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
  });

  /// Index into the archive's central directory; this is what
  /// `wdmm_zip_read_entry` takes.
  final int index;
  final String name;
  final int compressedSize;
  final int uncompressedSize;

  /// 0 = store, 8 = deflate, 99 = anything else (PKZIP).
  final int compressionMethod;

  bool get isDirectory => name.endsWith('/');
}

/// Thin client over the Rust ZIP reader (`wdmm_zip_open` /
/// `wdmm_zip_read_entry`).
///
/// The end-of-central-directory scan, the central-directory walk, range
/// fetching and decompression all happen in Rust; Dart only carries the entry
/// list and page bytes. The remote is read through the account driver, so no
/// Dart-side HTTP client is involved (AGENTS.md forbids constructing `Dio`
/// outside the service layer) and cached archives are read page by page from
/// the local file the same way.
///
/// Page order comes from Rust's `images` list, which applies the same natural
/// key as [mangaPageSortKey] on the Dart side, so the reader shows pages in the
/// same order as before.
class CbzRangeZip {
  CbzRangeZip({
    this.source,
    this.file,
    String? accountId,
    String? remotePath,
  }) : assert(
         file != null ||
             source != null ||
             (accountId != null && remotePath != null),
         'needs a file, a source, or accountId + remotePath',
       ),
       _accountId = accountId ?? source?.accountId,
       _remotePath = remotePath ?? source?.remotePath;

  /// Remote source the caller already resolved. Only its account/path are used;
  /// the bytes are fetched in Rust.
  final WebDavStreamSource? source;

  /// Local archive to read from. Takes precedence over [source].
  final File? file;

  final String? _accountId;
  final String? _remotePath;

  String? _handle;
  int? _totalSize;
  List<CbzZipEntry> _entries = const [];
  List<CbzZipEntry> _images = const [];

  int? get totalSize => _totalSize;
  List<CbzZipEntry> get entries => List.unmodifiable(_entries);

  /// Image entries in natural manga page order.
  List<CbzZipEntry> get imageEntries => List.unmodifiable(_images);

  /// Load the central directory (Rust keeps the archive open under [handle]).
  ///
  /// [cancel] is accepted for call-site compatibility but has no effect: the
  /// FFI entry point is synchronous and cancellation is decided by the caller's
  /// retry loop between calls.
  Future<void> open({Object? cancel}) async {
    final local = file;
    final String accountId;
    final String remotePath;
    if (local != null) {
      accountId = '';
      remotePath = local.path;
    } else {
      final id = _accountId;
      final path = _remotePath;
      if (id == null || path == null) {
        throw StateError('CBZ: no archive location');
      }
      accountId = id;
      remotePath = path;
    }

    final raw = await RustCoreService.runOffMain<String?>(
      () => RustCoreService.zipOpen(accountId, remotePath),
    );
    if (raw == null) {
      throw StateError('CBZ: native Rust core unavailable (wdmm_zip_open)');
    }
    final Map<String, dynamic> reply = _decodeReply(raw, 'wdmm_zip_open');

    final entries = <CbzZipEntry>[
      for (final item in _asList(reply['entries']))
        if (item is Map<String, dynamic>)
          CbzZipEntry(
            index: _asInt(item['index']),
            name: _asString(item['name']),
            compressedSize: _asInt(item['compressed_size']),
            uncompressedSize: _asInt(item['uncompressed_size']),
            compressionMethod: _asInt(item['method']),
          ),
    ];
    // `images` is a list of indices into `entries`, already in page order.
    final images = <CbzZipEntry>[
      for (final index in _asList(reply['images']))
        if (index is int && index >= 0 && index < entries.length)
          entries[index],
    ];

    _handle = _asString(reply['handle']);
    _totalSize = _asInt(reply['size']);
    _entries = entries;
    _images = images;
  }

  /// Extract one entry's uncompressed bytes.
  ///
  /// [cancel] is accepted for call-site compatibility but ignored (see [open]).
  Future<Uint8List> extractEntry(
    CbzZipEntry entry, {
    Object? cancel,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw StateError('CBZ: call open() before extractEntry()');
    }
    final index = entry.index;
    final raw = await RustCoreService.runOffMain<String?>(
      () => RustCoreService.zipReadEntry(handle, '$index'),
    );
    if (raw == null) {
      throw StateError('CBZ: native Rust core unavailable (wdmm_zip_read_entry)');
    }
    final reply = _decodeReply(raw, 'wdmm_zip_read_entry');
    final encoded = reply['bytes_b64'];
    if (encoded is! String) {
      throw StateError('CBZ: entry reply missing bytes_b64');
    }
    return base64Decode(encoded);
  }

  /// Find ComicInfo.xml (any folder depth, case-insensitive).
  CbzZipEntry? findComicInfo() {
    for (final entry in _entries) {
      final base = _basename(entry.name);
      if (base.toLowerCase() == 'comicinfo.xml') return entry;
    }
    return null;
  }
}

/// Decode a cut-over reply, mapping the Rust error convention
/// (`"error:<msg>"`) onto Dart exceptions. Range refusal keeps its own type so
/// callers can offer the full-cache fallback.
Map<String, dynamic> _decodeReply(String raw, String symbol) {
  if (raw.startsWith('error:')) {
    final message = raw.substring('error:'.length).trim();
    if (message == 'range_unsupported' || message.contains('range_unsupported')) {
      throw CbzRangeUnsupportedException(message);
    }
    throw StateError('$symbol failed: $message');
  }
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw StateError('$symbol: unexpected reply: $raw');
  }
  if (decoded['ok'] == false) {
    throw StateError('$symbol failed: ${decoded['error'] ?? 'unknown error'}');
  }
  return decoded;
}

List<Object?> _asList(Object? value) => value is List ? value : const [];

int _asInt(Object? value) => value is num ? value.toInt() : 0;

String _asString(Object? value) => value is String ? value : '';

String _basename(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
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
