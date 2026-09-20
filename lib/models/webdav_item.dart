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

/// Local playback metadata. Tags are only filled after download.
class TrackInfo {
  TrackInfo({
    required this.accountId,
    required this.remotePath,
    required this.fileName,
    this.localPath,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.coverPath,
  });

  final String accountId;
  final String remotePath;
  final String fileName;
  String? localPath;
  String? title;
  String? artist;
  String? album;
  Duration? duration;
  String? coverPath;

  bool get isDownloaded => localPath != null;

  /// Display title: prefer tag title only when downloaded; else filename.
  String get displayTitle {
    if (isDownloaded && title != null && title!.trim().isNotEmpty) {
      return title!;
    }
    return fileName;
  }

  String get displayArtist {
    if (isDownloaded && artist != null && artist!.trim().isNotEmpty) {
      return artist!;
    }
    return '未知艺术家';
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
