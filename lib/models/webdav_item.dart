import '../models/file_type_config.dart';

class WebDavItem {
  const WebDavItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
    this.category = FileCategory.other,
  });
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  /// Classification derived from the extension sets in effect when the item
  /// was listed. Folders are always [FileCategory.other].
  final FileCategory category;

  bool get isAudio => !isDirectory && category == FileCategory.music;
  bool get isVideo => !isDirectory && category == FileCategory.video;
  bool get isCue => !isDirectory && category == FileCategory.cue;
}

class TrackInfo {
  TrackInfo({
    required this.sourceName,
    this.accountId = '',
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
  /// 网盘名 —— the library binding point (cache / identity side).
  final String sourceName;
  /// Local WebDAV account resolved from [sourceName] for the HTTP transfer.
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
  bool get isCueVirtual =>
      cueTrackIndex != null && (cueRemotePath?.isNotEmpty ?? false);
  /// See [LibraryTrack.cueMultiSliceLabel].
  String? get cueTypeLabel =>
      isCueVirtual ? '多歌曲合并分片' : null;
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

enum TrackUiState { remote, queued, downloading, ready, playing, error }
