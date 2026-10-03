import '../l10n/generated/app_localizations.dart';
import '../models/file_type_config.dart';
import '../utils/track_identity.dart';
import 'library_sentinels.dart';

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
  bool get isImage => !isDirectory && category == FileCategory.image;
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

  String get effectiveAudioRemotePath => audioRemotePath ?? remotePath;

  /// 权威身份键，与曲库 [LibraryTrack.musicId] 同源（docs/10 §4.4）。
  ///
  /// CUE 虚拟切片用 `musicIdForCueSlice(网盘名, cuePath, idx)` 区分单曲；普通
  /// 条目用 `musicIdForRemote(网盘名, remotePath)`。注意这与
  /// [PlaylistEntry.identityKey] 的 CUE 回退不同——后者在缺少显式 id 时退回
  /// backing audio 的整轨 hash，因为虚拟路径无法反推 .cue 源路径。
  String get musicId => musicIdForLibraryRow(
    sourceName: sourceName,
    remotePath: remotePath,
    cueRemotePath: cueRemotePath,
    cueTrackIndex: cueTrackIndex,
  );

  String get displayTitle {
    if (isDownloaded && title != null && title!.trim().isNotEmpty) {
      return title!;
    }
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return fileName;
  }

  /// Empty artist uses [kUnknownArtist]. Display goes through [displayArtistFor].
  String get displayArtist {
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return kUnknownArtist;
  }

  /// Locale-aware render of [displayArtist].
  String displayArtistFor(AppLocalizations l10n) {
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return l10n.artistUnknown;
  }

  String get displayAlbum {
    final a = album?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '';
  }
}

enum TrackUiState { remote, queued, downloading, ready, playing, error }
