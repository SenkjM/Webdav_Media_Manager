import 'package:path/path.dart' as p;

/// Builds an ffmpeg argv to crop [startMs]..[endMs] from [inputPath] into
/// [outputPath], writing CUE-priority tags as metadata.
///
/// Uses decode+re-encode (not stream copy) so INDEX boundaries are accurate
/// for MP3/FLAC/etc. Output container follows [outputPath] extension;
/// prefer `.mp3` for broad Android share targets.
List<String> buildCueClipFfmpegArgs({
  required String inputPath,
  required String outputPath,
  required int startMs,
  int? endMs,
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  int? trackNumber,
  int? trackTotal,
  int? discNumber,
  int? year,
  String? genre,
}) {
  if (startMs < 0) {
    throw ArgumentError.value(startMs, 'startMs', 'must be >= 0');
  }
  if (endMs != null && endMs <= startMs) {
    throw ArgumentError.value(endMs, 'endMs', 'must be > startMs');
  }

  final startSec = (startMs / 1000).toStringAsFixed(3);
  final args = <String>[
    '-hide_banner',
    '-y',
    '-ss',
    startSec,
    '-i',
    inputPath,
  ];
  if (endMs != null) {
    final durMs = endMs - startMs;
    args.addAll(['-t', (durMs / 1000).toStringAsFixed(3)]);
  }

  void meta(String key, String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return;
    args.addAll(['-metadata', '$key=$v']);
  }

  meta('title', title);
  meta('artist', artist);
  meta('album', album);
  meta('album_artist', albumArtist);
  if (trackNumber != null) {
    final tn = trackTotal != null ? '$trackNumber/$trackTotal' : '$trackNumber';
    meta('track', tn);
  }
  if (discNumber != null) meta('disc', '$discNumber');
  if (year != null && year > 0) meta('date', '$year');
  meta('genre', genre);

  final ext = p.extension(outputPath).toLowerCase();
  switch (ext) {
    case '.mp3':
      args.addAll(['-c:a', 'libmp3lame', '-q:a', '2']);
      break;
    case '.m4a':
    case '.aac':
      args.addAll(['-c:a', 'aac', '-b:a', '192k']);
      break;
    case '.flac':
      args.addAll(['-c:a', 'flac']);
      break;
    case '.ogg':
      args.addAll(['-c:a', 'libvorbis', '-q:a', '5']);
      break;
    default:
      // Safe default for unknown share targets.
      args.addAll(['-c:a', 'libmp3lame', '-q:a', '2']);
  }
  args.add(outputPath);
  return args;
}

/// Safe file stem for share exports (Android Intent extras).
String sanitizeShareFileStem(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'track';
  return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
}
