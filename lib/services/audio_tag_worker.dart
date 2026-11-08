import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../utils/cover_image.dart';
import 'tag_service.dart';

/// Tags parsed from a local audio file, plus the cover thumb it produced.
///
/// The parse runs in a worker isolate: embedded art decoding and JPEG encoding
/// are CPU work (tens of milliseconds for a large cover), and doing it on the
/// UI isolate costs frames. Only plain values cross back: fields, a thumb path,
/// and — when explicitly asked — the raw cover bytes for the player backdrop.
class ParsedAudioMetadata {
  const ParsedAudioMetadata({required this.tags, this.thumbPath});

  final ReadTags tags;

  /// Square JPEG thumb written next to the library covers, or null.
  final String? thumbPath;
}

/// Parse [path] off the UI isolate.
///
/// [thumbPath] is the deterministic cover path for this track; a thumb is
/// written there only when it does not exist yet. [keepCoverBytes] is true for
/// the now-playing track (the player backdrop wants the full-size art) and
/// false for queue neighbours (they only need the thumb file).
Future<ParsedAudioMetadata?> parseAudioMetadata({
  required String path,
  required String? thumbPath,
  required int thumbSize,
  required bool keepCoverBytes,
}) => Isolate.run(
  () => _parseSync(path, thumbPath, thumbSize, keepCoverBytes),
);

/// Resize [bytes] into [thumbPath] off the UI isolate.
///
/// Used for the current track's remote cover read, which already has the bytes
/// in memory but should not pay the decode on the UI thread.
Future<String?> writeCoverThumbInWorker({
  required Uint8List bytes,
  required String thumbPath,
  required int thumbSize,
}) => Isolate.run(() => _writeThumb(bytes, thumbPath, thumbSize));

ParsedAudioMetadata? _parseSync(
  String path,
  String? thumbPath,
  int thumbSize,
  bool keepCoverBytes,
) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final tags = TagService().readFromFileSync(path);
  final cover = tags.coverBytes;
  if (cover == null || cover.isEmpty) {
    return ParsedAudioMetadata(tags: tags, thumbPath: _existing(thumbPath));
  }
  final written = _writeThumb(cover, thumbPath, thumbSize);
  return ParsedAudioMetadata(
    tags: keepCoverBytes ? tags : _withoutCover(tags),
    thumbPath: written,
  );
}

String? _writeThumb(Uint8List bytes, String? thumbPath, int thumbSize) {
  if (thumbPath == null || thumbPath.isEmpty) return null;
  if (_existing(thumbPath) != null) return thumbPath;
  final thumb = resizeCoverToThumb(bytes, size: thumbSize);
  if (thumb == null) return null;
  try {
    final target = File(thumbPath);
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(thumb, flush: true);
    return thumbPath;
  } catch (_) {
    return null;
  }
}

String? _existing(String? path) {
  if (path == null || path.isEmpty) return null;
  return File(path).existsSync() ? path : null;
}

ReadTags _withoutCover(ReadTags t) => ReadTags(
  title: t.title,
  artist: t.artist,
  albumArtist: t.albumArtist,
  album: t.album,
  durationMs: t.durationMs,
  trackNumber: t.trackNumber,
  trackTotal: t.trackTotal,
  discNumber: t.discNumber,
  discTotal: t.discTotal,
  year: t.year,
  genre: t.genre,
  bitrate: t.bitrate,
  sampleRate: t.sampleRate,
  language: t.language,
  lyrics: t.lyrics,
);
