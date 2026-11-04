import 'dart:convert';

import 'package:path/path.dart' as p;

import '../services/rust_core_service.dart';

/// Decode CUE file bytes for parsing.
///
/// Many Chinese / Exact Audio Copy CUEs are GBK or UTF-16, not strict
/// UTF-8. [File.readAsString] throws on those and previously caused
/// `_maybeIngestCueGroup` to abort — downloads succeeded but virtual
/// tracks never entered 音乐库. Structural keywords (FILE/TRACK/INDEX)
/// are ASCII, so a lenient decode is enough to ingest slices.
///
/// Decoding stays here because `wdmm_cue_parse` takes text; the parse itself is
/// owned by Rust (`wdmm_text::cue`).
String decodeCueText(List<int> bytes) {
  if (bytes.isEmpty) return '';
  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // UTF-16 LE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final codes = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      codes.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codes);
  }
  // UTF-16 BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final codes = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      codes.add(bytes[i + 1] | (bytes[i] << 8));
    }
    return String.fromCharCodes(codes);
  }
  // Prefer strict UTF-8 when valid (keeps Chinese titles correct).
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // GBK / Latin1 / mixed: keep ASCII structure; titles may be lossy.
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// A parsed `.cue` sheet.
///
/// The parser lives in Rust (`wdmm_text::cue`, exposed as `wdmm_cue_parse`);
/// this class is only the model plus the remote-path helpers the library uses.
class CueSheet {
  const CueSheet({
    required this.files,
    required this.tracks,
    this.title,
    this.performer,
    this.remGenre,
    this.remDate,
  });

  /// Parse [text] through Rust.
  ///
  /// Returns `null` when the native library is unavailable (host unit tests,
  /// older `.so`) or when Rust rejects the sheet (no complete `TRACK`), which is
  /// the old `CueSheetParser.tryParse` contract.
  static CueSheet? parseOrNull(String text) {
    final reply = RustCoreService.cueParse(text);
    if (reply == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(reply);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) return null;
    final sheet = decoded['sheet'];
    if (sheet is! Map<String, dynamic>) return null;
    return CueSheet._fromJson(sheet);
  }

  /// Parse [text] or throw `StateError('err.cueMalformed')`, like the old
  /// `CueSheetParser.parse`.
  static CueSheet parse(String text) {
    final sheet = parseOrNull(text);
    if (sheet == null) throw StateError('err.cueMalformed');
    return sheet;
  }

  factory CueSheet._fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final rawTracks = json['tracks'];
    return CueSheet(
      files: rawFiles is List
          ? List<String>.unmodifiable(rawFiles.whereType<String>())
          : const <String>[],
      tracks: rawTracks is List
          ? List<CueTrack>.unmodifiable(
              rawTracks
                  .whereType<Map<String, dynamic>>()
                  .map(CueTrack._fromJson),
            )
          : const <CueTrack>[],
      title: _emptyToNull(json['title']),
      performer: _emptyToNull(json['performer']),
      remGenre: _emptyToNull(json['rem_genre']),
      remDate: _emptyToNull(json['rem_date']),
    );
  }

  final List<String> files;
  final List<CueTrack> tracks;
  final String? title;
  final String? performer;
  final String? remGenre;
  final String? remDate;
  bool get isStandard => files.isNotEmpty && tracks.isNotEmpty;
  List<String> audioRemotePaths(String cueRemotePath) {
    final dir = p.posix.dirname(cueRemotePath);
    final out = <String>[];
    final seen = <String>{};
    for (final f in files) {
      final remote = joinRemote(dir, f);
      if (seen.add(remote)) out.add(remote);
    }
    return out;
  }

  static String joinRemote(String dir, String fileName) {
    final cleaned = fileName.replaceAll('\\', '/');
    final base = cleaned.contains('/') ? p.posix.basename(cleaned) : cleaned;
    if (dir == '/' || dir.isEmpty) return '/$base';
    final d = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    return '$d/$base';
  }
}

/// One track of a [CueSheet].
class CueTrack {
  const CueTrack({
    required this.number,
    required this.fileName,
    required this.index01,
    this.title,
    this.performer,
    this.isrc,
  });

  factory CueTrack._fromJson(Map<String, dynamic> json) {
    return CueTrack(
      number: (json['number'] as num?)?.toInt() ?? 0,
      fileName: json['file_name'] as String? ?? '',
      index01: Duration(milliseconds: (json['start_ms'] as num?)?.toInt() ?? 0),
      title: _emptyToNull(json['title']),
      performer: _emptyToNull(json['performer']),
      isrc: _emptyToNull(json['isrc']),
    );
  }

  final int number;
  final String fileName;
  final Duration index01;
  final String? title;
  final String? performer;
  final String? isrc;
}

/// Clip ranges (`INDEX 01` … next track / file duration) for [tracks].
///
/// Tracks of the same `FILE` are chained; the last track of a file ends at
/// [fileDurations] (resolved from local tags) or stays open.
List<({Duration start, Duration? end})> cueClipRanges(
  List<CueTrack> tracks, {
  Map<String, Duration?> fileDurations = const {},
}) {
  final byFile = <String, List<int>>{};
  for (var i = 0; i < tracks.length; i++) {
    byFile.putIfAbsent(tracks[i].fileName, () => []).add(i);
  }
  final out = List<({Duration start, Duration? end})>.generate(
    tracks.length,
    (i) => (start: tracks[i].index01, end: null),
  );
  for (final e in byFile.entries) {
    final idxs = e.value;
    for (var j = 0; j < idxs.length; j++) {
      final i = idxs[j];
      out[i] = (
        start: tracks[i].index01,
        end: j + 1 < idxs.length
            ? tracks[idxs[j + 1]].index01
            : fileDurations[e.key],
      );
    }
  }
  return out;
}

({
  String? title,
  String? artist,
  String? albumArtist,
  String? album,
  int? trackNumber,
  int? year,
  String? genre,
})
mergeCueOverFileTags({
  required CueSheet sheet,
  required CueTrack cueTrack,
  String? fileTitle,
  String? fileArtist,
  String? fileAlbumArtist,
  String? fileAlbum,
  int? fileTrackNumber,
  int? fileYear,
  String? fileGenre,
}) {
  final dateParts =
      sheet.remDate?.trim().split(RegExp(r'\D+')) ?? const <String>[];
  final cueYear = dateParts.isEmpty ? null : int.tryParse(dateParts.first);
  String? first(List<String?> vs) {
    for (final v in vs) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  String? prefer(String? a, String? b) => first([a, b]);
  return (
    title: prefer(cueTrack.title, fileTitle),
    artist: first([cueTrack.performer, sheet.performer, fileArtist]),
    albumArtist: first([sheet.performer, fileAlbumArtist, fileArtist]),
    album: prefer(sheet.title, fileAlbum),
    trackNumber: cueTrack.number,
    year: cueYear ?? fileYear,
    genre: prefer(sheet.remGenre, fileGenre),
  );
}

/// `null` for absent/empty JSON strings, so the model keeps the old nullable
/// semantics (`TITLE ""` was indistinguishable from no title for consumers).
String? _emptyToNull(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return value;
}
