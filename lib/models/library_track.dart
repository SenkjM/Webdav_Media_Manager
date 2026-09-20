import '../utils/track_identity.dart';

/// Persisted library record for a track that has been cached at least once.
/// Survives audio cache deletion; [coverPath] is a small local thumb only.
class LibraryTrack {
  LibraryTrack({
    required this.accountId,
    required this.remotePath,
    required this.fileName,
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.durationMs,
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
    this.clipStartMs,
    this.clipEndMs,
    this.cacheGroupId,
    DateTime? lastDownloadedAt,
    DateTime? lastTagReadAt,
  })  : lastDownloadedAt = lastDownloadedAt ?? DateTime.now(),
        lastTagReadAt = lastTagReadAt ?? DateTime.now();

  final String accountId;
  final String remotePath;
  final String fileName;
  String? title;
  String? artist;
  String? albumArtist;
  String? album;
  int? durationMs;
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
  int? clipStartMs;
  int? clipEndMs;
  String? cacheGroupId;
  DateTime lastDownloadedAt;
  DateTime lastTagReadAt;

  String get identityKey => trackIdentityKey(accountId, remotePath);
  bool get isCueVirtual => cueTrackIndex != null && (cueRemotePath?.isNotEmpty ?? false);
  String get effectiveAudioRemotePath => audioRemotePath ?? remotePath;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return fileName;
  }

  String get displayArtist {
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '未知艺术家';
  }

  String get displayAlbumArtist {
    final a = albumArtist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return displayArtist;
  }

  String get displayAlbum {
    final a = album?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '未知专辑';
  }

  Map<String, dynamic> toMap() => {
        'account_id': accountId,
        'remote_path': remotePath,
        'file_name': fileName,
        'title': title,
        'artist': artist,
        'album_artist': albumArtist,
        'album': album,
        'duration_ms': durationMs,
        'track_number': trackNumber,
        'track_total': trackTotal,
        'disc_number': discNumber,
        'disc_total': discTotal,
        'year': year,
        'genre': genre,
        'bitrate': bitrate,
        'sample_rate': sampleRate,
        'cover_path': coverPath,
        'cue_remote_path': cueRemotePath,
        'cue_track_index': cueTrackIndex,
        'audio_remote_path': audioRemotePath,
        'clip_start_ms': clipStartMs,
        'clip_end_ms': clipEndMs,
        'cache_group_id': cacheGroupId,
        'last_downloaded_at': lastDownloadedAt.toIso8601String(),
        'last_tag_read_at': lastTagReadAt.toIso8601String(),
      };

  factory LibraryTrack.fromMap(Map<String, dynamic> map) => LibraryTrack(
        accountId: map['account_id'] as String,
        remotePath: map['remote_path'] as String,
        fileName: map['file_name'] as String,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        albumArtist: map['album_artist'] as String?,
        album: map['album'] as String?,
        durationMs: map['duration_ms'] as int?,
        trackNumber: map['track_number'] as int?,
        trackTotal: map['track_total'] as int?,
        discNumber: map['disc_number'] as int?,
        discTotal: map['disc_total'] as int?,
        year: map['year'] as int?,
        genre: map['genre'] as String?,
        bitrate: map['bitrate'] as int?,
        sampleRate: map['sample_rate'] as int?,
        coverPath: map['cover_path'] as String?,
        cueRemotePath: map['cue_remote_path'] as String?,
        cueTrackIndex: map['cue_track_index'] as int?,
        audioRemotePath: map['audio_remote_path'] as String?,
        clipStartMs: map['clip_start_ms'] as int?,
        clipEndMs: map['clip_end_ms'] as int?,
        cacheGroupId: map['cache_group_id'] as String?,
        lastDownloadedAt: DateTime.parse(map['last_downloaded_at'] as String),
        lastTagReadAt: DateTime.parse(map['last_tag_read_at'] as String),
      );
}

/// How to order tracks in the local library title list / album detail.
enum LibrarySortMode {
  /// Title / display name (case-insensitive).
  byName,

  /// Disc number then track number within an album; missing numbers last.
  byAlbumTrack,
}

extension LibrarySortModeX on LibrarySortMode {
  String get storageKey => switch (this) {
        LibrarySortMode.byName => 'name',
        LibrarySortMode.byAlbumTrack => 'album_track',
      };

  String get labelZh => switch (this) {
        LibrarySortMode.byName => '按名称',
        LibrarySortMode.byAlbumTrack => '按曲序',
      };

  static LibrarySortMode fromStorageKey(String? key) {
    switch (key) {
      case 'album_track':
        return LibrarySortMode.byAlbumTrack;
      case 'name':
      default:
        return LibrarySortMode.byName;
    }
  }
}

/// Shared comparators for library lists.
int compareTracksByName(LibraryTrack a, LibraryTrack b) {
  final byTitle =
      a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
  if (byTitle != 0) return byTitle;
  return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
}

/// Disc → track → name. Missing disc defaults to 1; missing track sorts last.
int compareTracksByAlbumOrder(LibraryTrack a, LibraryTrack b) {
  final discA = a.discNumber ?? 1;
  final discB = b.discNumber ?? 1;
  if (discA != discB) return discA.compareTo(discB);
  const missing = 1 << 30;
  final trackA = a.trackNumber ?? missing;
  final trackB = b.trackNumber ?? missing;
  if (trackA != trackB) return trackA.compareTo(trackB);
  return compareTracksByName(a, b);
}
