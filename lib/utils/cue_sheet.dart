import 'package:path/path.dart' as p;

class CueSheet {
  const CueSheet({
    required this.files,
    required this.tracks,
    this.title,
    this.performer,
    this.remGenre,
    this.remDate,
  });
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

class CueTrack {
  const CueTrack({
    required this.number,
    required this.fileName,
    required this.index01,
    this.title,
    this.performer,
    this.isrc,
  });
  final int number;
  final String fileName;
  final Duration index01;
  final String? title;
  final String? performer;
  final String? isrc;
}

class CueSheetParser {
  static CueSheet parse(String text) {
    final r = tryParse(text);
    if (r == null) throw StateError('无法解析的 CUE：需要标准 FILE + TRACK/INDEX');
    return r;
  }

  static CueSheet? tryParse(String text) {
    if (text.trim().isEmpty) return null;
    String? albumTitle, albumPerformer, remGenre, remDate, currentFile;
    final files = <String>[];
    final tracks = <CueTrack>[];
    int? trackNumber;
    String? trackTitle, trackPerformer, trackIsrc;
    Duration? index01;
    var inTrack = false;
    var incomplete = false;

    void flush() {
      if (!inTrack || trackNumber == null) return;
      if (currentFile == null || currentFile!.isEmpty || index01 == null) {
        incomplete = true;
        inTrack = false;
        trackNumber = null; trackTitle = null; trackPerformer = null; trackIsrc = null; index01 = null;
        return;
      }
      tracks.add(CueTrack(number: trackNumber!, fileName: currentFile!, index01: index01!, title: trackTitle, performer: trackPerformer, isrc: trackIsrc));
      inTrack = false;
      trackNumber = null; trackTitle = null; trackPerformer = null; trackIsrc = null; index01 = null;
    }

    for (var raw in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      var line = raw.trim();
      if (line.startsWith('\uFEFF')) line = line.substring(1).trim();
      if (line.isEmpty) continue;
      final u = line.toUpperCase();
      if (u.startsWith('REM ')) {
        final rem = line.substring(4).trim();
        final ru = rem.toUpperCase();
        if (ru.startsWith('GENRE ')) remGenre = _uq(rem.substring(6).trim());
        else if (ru.startsWith('DATE ')) remDate = _uq(rem.substring(5).trim());
        continue;
      }
      if (u.startsWith('TITLE ')) { final v = _uq(line.substring(6).trim()); if (inTrack) trackTitle = v; else albumTitle = v; continue; }
      if (u.startsWith('PERFORMER ')) { final v = _uq(line.substring(10).trim()); if (inTrack) trackPerformer = v; else albumPerformer = v; continue; }
      if (u.startsWith('FILE ')) {
        flush();
        final fn = _file(line.substring(5).trim());
        if (fn == null || fn.isEmpty) return null;
        currentFile = fn;
        if (!files.contains(fn)) files.add(fn);
        continue;
      }
      if (u.startsWith('TRACK ')) {
        flush();
        if (currentFile == null) return null;
        final n = int.tryParse(line.substring(6).trim().split(RegExp(r'\s+')).first);
        if (n == null || n < 1) return null;
        inTrack = true; trackNumber = n; continue;
      }
      if (u.startsWith('INDEX ')) {
        if (!inTrack) continue;
        final parts = line.substring(6).trim().split(RegExp(r'\s+'));
        if (parts.length < 2 || int.tryParse(parts[0]) != 1) continue;
        final d = parseCueIndexTime(parts[1]);
        if (d == null) return null;
        index01 = d; continue;
      }
      if (u.startsWith('ISRC ') && inTrack) trackIsrc = _uq(line.substring(5).trim());
    }
    flush();
    if (incomplete || files.isEmpty || tracks.isEmpty) return null;
    return CueSheet(files: List.unmodifiable(files), tracks: List.unmodifiable(tracks), title: albumTitle, performer: albumPerformer, remGenre: remGenre, remDate: remDate);
  }

  static Duration? parseCueIndexTime(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 3) return null;
    final m = int.tryParse(parts[0]); final s = int.tryParse(parts[1]); final f = int.tryParse(parts[2]);
    if (m == null || s == null || f == null || m < 0 || s < 0 || s > 59 || f < 0 || f > 74) return null;
    return Duration(milliseconds: ((m * 60 + s) * 1000) + ((f * 1000) / 75).round());
  }

  static String? _file(String rest) {
    final q = RegExp(r'^"([^"]*)"').firstMatch(rest);
    if (q != null) return q.group(1);
    final s = RegExp(r"^'([^']*)'").firstMatch(rest);
    if (s != null) return s.group(1);
    final sp = rest.split(RegExp(r'\s+'));
    return (sp.isEmpty || sp.first.isEmpty) ? null : sp.first;
  }

  static String _uq(String s) {
    if (s.length >= 2 && ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}

List<({Duration start, Duration? end})> cueClipRanges(List<CueTrack> tracks, {Map<String, Duration?> fileDurations = const {}}) {
  final byFile = <String, List<int>>{};
  for (var i = 0; i < tracks.length; i++) {
    byFile.putIfAbsent(tracks[i].fileName, () => []).add(i);
  }
  final out = List<({Duration start, Duration? end})>.generate(tracks.length, (i) => (start: tracks[i].index01, end: null));
  for (final e in byFile.entries) {
    final idxs = e.value;
    for (var j = 0; j < idxs.length; j++) {
      final i = idxs[j];
      out[i] = (start: tracks[i].index01, end: j + 1 < idxs.length ? tracks[idxs[j + 1]].index01 : fileDurations[e.key]);
    }
  }
  return out;
}

({String? title, String? artist, String? albumArtist, String? album, int? trackNumber, int? year, String? genre}) mergeCueOverFileTags({
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
  final dateParts = sheet.remDate?.trim().split(RegExp(r'\D+')) ?? const <String>[];
  final cueYear = dateParts.isEmpty ? null : int.tryParse(dateParts.first);
  String? first(List<String?> vs) {
    for (final v in vs) { final t = v?.trim(); if (t != null && t.isNotEmpty) return t; }
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
