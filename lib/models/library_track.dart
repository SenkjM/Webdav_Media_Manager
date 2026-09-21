import '../utils/track_identity.dart';

/// Persisted library record. Identity is [musicId] (stable offline hash).
/// Survives audio cache deletion; [coverPath] is a small local thumb only.
/// CUE slices live in `cue_slices` but are presented as [LibraryTrack] too.
class LibraryTrack {
  LibraryTrack({
    String? musicId,
    required this.sourceName,
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
    this.cueId,
    this.cueRemotePath,
    this.cueTrackIndex,
    this.audioMusicId,
    this.audioRemotePath,
    this.clipStartMs,
    this.clipEndMs,
    this.cacheGroupId,
    this.rev,
    DateTime? lastDownloadedAt,
    DateTime? lastTagReadAt,
  })  : musicId = musicId ??
            musicIdForLibraryRow(
              sourceName: sourceName,
              remotePath: remotePath,
              cueRemotePath: cueRemotePath,
              cueTrackIndex: cueTrackIndex,
            ),
        lastDownloadedAt = lastDownloadedAt ?? DateTime.now(),
        lastTagReadAt = lastTagReadAt ?? DateTime.now();

  /// Stable offline primary key (SHA-1 hex).
  final String musicId;
  /// 网盘名 —— the single binding point (URL/username live in the account table).
  final String sourceName;
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
  /// Cue album id when this row is a CUE slice.
  String? cueId;
  /// Absolute WebDAV path of the source `.cue`.
  String? cueRemotePath;
  /// CUE `TRACK` number.
  int? cueTrackIndex;
  /// music_id of the backing audio file (CUE slices).
  String? audioMusicId;
  String? audioRemotePath;
  int? clipStartMs;
  int? clipEndMs;
  String? cacheGroupId;
  /// Monotonic version of this row (see [RevClock]); the only value sync compares.
  int? rev;
  DateTime lastDownloadedAt;
  DateTime lastTagReadAt;

  /// Legacy playlist / UI key (网盘名 + remotePath). Prefer [musicId].
  String get identityKey => trackIdentityKey(sourceName, remotePath);

  /// music_id used for cache annex lookups (audio file, not virtual slice).
  String get cacheMusicId =>
      audioMusicId ??
      (audioRemotePath != null
          ? musicIdForRemote(sourceName, audioRemotePath!)
          : musicId);

  /// True when this row is a CUE-sliced virtual track.
  bool get isCueVirtual =>
      cueTrackIndex != null && (cueRemotePath?.isNotEmpty ?? false);

  /// Chinese label for CUE multi-song merged/sliced items (details UI).
  static const cueMultiSliceLabel = '多歌曲合并分片';

  /// Non-null when this track is part of a CUE album (not a standalone file).
  String? get cueTypeLabel => isCueVirtual ? cueMultiSliceLabel : null;

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
        'music_id': musicId,
        'source_name': sourceName,
        'rev': rev ?? lastTagReadAt.millisecondsSinceEpoch,
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
        'cue_id': cueId,
        'cue_remote_path': cueRemotePath,
        'cue_track_index': cueTrackIndex,
        'audio_music_id': audioMusicId,
        'audio_remote_path': audioRemotePath,
        'clip_start_ms': clipStartMs,
        'clip_end_ms': clipEndMs,
        'cache_group_id': cacheGroupId,
        'last_downloaded_at': lastDownloadedAt.toIso8601String(),
        'last_tag_read_at': lastTagReadAt.toIso8601String(),
      };

  /// Map for the `tracks` table (no CUE-only columns).
  Map<String, dynamic> toTrackTableMap() => {
        'music_id': musicId,
        'source_name': sourceName,
        'rev': rev ?? lastTagReadAt.millisecondsSinceEpoch,
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
        'last_downloaded_at': lastDownloadedAt.toIso8601String(),
        'last_tag_read_at': lastTagReadAt.toIso8601String(),
      };

  /// Map for the `cue_slices` table.
  Map<String, dynamic> toCueSliceTableMap() => {
        'music_id': musicId,
        'cue_id': cueId ??
            (cueRemotePath != null
                ? cueIdFor(sourceName, cueRemotePath!)
                : ''),
        'audio_music_id': audioMusicId ??
            (audioRemotePath != null
                ? musicIdForRemote(sourceName, audioRemotePath!)
                : musicId),
        'source_name': sourceName,
        'rev': rev ?? lastTagReadAt.millisecondsSinceEpoch,
        'remote_path': remotePath,
        'file_name': fileName,
        'track_index': cueTrackIndex,
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
        'audio_remote_path': audioRemotePath,
        'clip_start_ms': clipStartMs,
        'clip_end_ms': clipEndMs,
        'cache_group_id': cacheGroupId,
        'last_downloaded_at': lastDownloadedAt.toIso8601String(),
        'last_tag_read_at': lastTagReadAt.toIso8601String(),
      };

  factory LibraryTrack.fromMap(Map<String, dynamic> map) {
    final sourceName = (map['source_name'] ?? map['account_id']) as String;
    final remotePath = map['remote_path'] as String;
    final cueRemotePath = map['cue_remote_path'] as String?;
    final cueTrackIndex = _asInt(map['cue_track_index'] ?? map['track_index']);
    final storedId = map['music_id'] as String?;
    return LibraryTrack(
      musicId: (storedId != null && storedId.isNotEmpty)
          ? storedId
          : musicIdForLibraryRow(
              sourceName: sourceName,
              remotePath: remotePath,
              cueRemotePath: cueRemotePath,
              cueTrackIndex: cueTrackIndex,
            ),
      sourceName: sourceName,
      remotePath: remotePath,
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
      cueId: map['cue_id'] as String?,
      cueRemotePath: cueRemotePath,
      cueTrackIndex: cueTrackIndex,
      audioMusicId: map['audio_music_id'] as String?,
      audioRemotePath: map['audio_remote_path'] as String?,
      clipStartMs: _asInt(map['clip_start_ms']),
      clipEndMs: _asInt(map['clip_end_ms']),
      cacheGroupId: map['cache_group_id'] as String?,
      rev: _asInt(map['rev']),
      lastDownloadedAt: DateTime.tryParse(
            map['last_downloaded_at'] as String? ?? '') ??
          DateTime.now(),
      lastTagReadAt: DateTime.tryParse(
            map['last_tag_read_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
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
