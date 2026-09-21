import '../utils/audio_extensions.dart';

/// Broad classification of a WebDAV file based on its extension.
enum FileCategory { music, video, cue, other }

/// Extension sets the network library uses to classify files.
///
/// Music / video / cue lists are user-configurable in Settings; this model
/// carries both the defaults and the parsed, normalized runtime representation.
class FileTypeConfig {
  FileTypeConfig({
    List<String>? musicExtensions,
    List<String>? videoExtensions,
    List<String>? cueExtensions,
  })  : musicExtensions = _normalize(musicExtensions ?? defaultMusicExtensions),
        videoExtensions =
            _normalize(videoExtensions ?? defaultVideoExtensions),
        cueExtensions = _normalize(cueExtensions ?? defaultCueExtensions);

  static const List<String> defaultMusicExtensions = [
    'mp3',
    'flac',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'opus',
    'wma',
  ];

  static const List<String> defaultVideoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'webm',
    'flv',
    'ts',
    'm4v',
    'wmv',
    '3gp',
    'mpg',
    'mpeg',
  ];

  static const List<String> defaultCueExtensions = ['cue'];

  /// Lowercase extensions WITHOUT a leading dot (e.g. `mp4`).
  final List<String> musicExtensions;
  final List<String> videoExtensions;
  final List<String> cueExtensions;

  FileCategory categoryFor(String name) {
    if (isAudioFileNameWith(name, musicExtensions)) return FileCategory.music;
    if (isVideoFileNameWith(name, videoExtensions)) return FileCategory.video;
    if (isCueFileNameWith(name, cueExtensions)) return FileCategory.cue;
    return FileCategory.other;
  }

  /// Normalize a raw user-supplied list: trim, lowercase, strip leading dot,
  /// drop empty entries, dedupe while preserving order.
  static List<String> _normalize(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final e in raw) {
      var ext = e.trim().toLowerCase();
      while (ext.startsWith('.')) {
        ext = ext.substring(1);
      }
      if (ext.isEmpty) continue;
      if (seen.add(ext)) out.add(ext);
    }
    return out;
  }

  /// Human-readable list like `.mp3 .flac` (for display).
  static String displayList(List<String> exts) =>
      exts.map((e) => '.$e').join(' ');

  /// Parse user-entered text (`mp3, .flac m4a`) back into normalized extensions.
  static List<String> parseInput(String text) {
    final tokens = text
        .replaceAll(',', ' ')
        .replaceAll('，', ' ')
        .split(RegExp(r'\s+'));
    return _normalize(tokens);
  }

  Map<String, dynamic> toJson() => {
        'music': musicExtensions,
        'video': videoExtensions,
        'cue': cueExtensions,
      };

  factory FileTypeConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return FileTypeConfig();
    return FileTypeConfig(
      musicExtensions: _asStringList(json['music']),
      videoExtensions: _asStringList(json['video']),
      cueExtensions: _asStringList(json['cue']),
    );
  }

  static List<String> _asStringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}
