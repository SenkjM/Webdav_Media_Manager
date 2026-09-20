import '../utils/audio_extensions.dart';

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
  bool get isAudio => !isDirectory && isAudioFileName(name);
  bool get isCue => !isDirectory && isCueFileName(name);
}

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
    this.cueRemotePath,
    this.cueTrackIndex,
    this.audioRemotePath,
    this.clipStart,
    this.clipEnd,
    this.cacheGroupId,
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
  String? cueRemotePath;
  int? cueTrackIndex;
  String? audioRemotePath;
  Duration? clipStart;
  Duration? clipEnd;
  String? cacheGroupId;
  bool get isDownloaded => localPath != null;
  bool get isCueVirtual => cueTrackIndex != null && cueRemotePath != null;
  String get effectiveAudioRemotePath => audioRemotePath ?? remotePath;
  String get displayTitle {
    if (isDownloaded && title != null && title!.trim().isNotEmpty) return title!;
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

enum TrackUiState { queued, downloading, ready, playing, error }
