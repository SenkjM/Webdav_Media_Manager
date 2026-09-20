/// A WebDAV directory entry. Undownloaded items expose filename/path only
/// — no ID3/tag scan until the file is in local cache.
class WebDavItem {
  const WebDavItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  bool get isAudio {
    if (isDirectory) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.wma');
  }
}

/// Local playback metadata. Tags are only filled after download / library ingest.
class TrackInfo {
  TrackInfo({
    required this.accountId,
    required this.remotePath,
    required this.fileName,
    this.localPath,
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.duration,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.discTotal,
    this.year,
    this.genre,
    this.bitrate,
    this.sampleRate,
    this.coverPath,
  });

  final String accountId;
  final String remotePath;
  final String fileName;
  String? localPath;
  String? title;
  String? artist;
  String? albumArtist;
  String? album;
  Duration? duration;
  int? trackNumber;
  int? trackTotal;
  int? discNumber;
  int? discTotal;
  int? year;
  String? genre;
  int? bitrate;
  int? sampleRate;
  String? coverPath;

  bool get isDownloaded => localPath != null;

  /// Display title: prefer tag title only when downloaded; else filename.
  String get displayTitle {
    if (isDownloaded && title != null && title!.trim().isNotEmpty) {
      return title!;
    }
    // Library-backed tracks may have title without localPath set yet.
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return fileName;
  }

  String get displayArtist {
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '未知艺术家';
  }

  String get displayAlbum {
    final a = album?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '';
  }
}

/// UI playback / download state for a track.
enum TrackUiState {
  queued,
  downloading,
  ready,
  playing,
  error,
}
