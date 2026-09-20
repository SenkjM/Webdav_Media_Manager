import '../utils/track_identity.dart';

/// Persisted library record for a track that has been cached at least once.
/// Survives audio cache deletion; cover is a small local thumb only.
class LibraryTrack {
  LibraryTrack({
    required this.accountId,
    required this.remotePath,
    required this.fileName,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.coverPath,
    DateTime? lastDownloadedAt,
    DateTime? lastTagReadAt,
  })  : lastDownloadedAt = lastDownloadedAt ?? DateTime.now(),
        lastTagReadAt = lastTagReadAt ?? DateTime.now();

  final String accountId;
  final String remotePath;
  final String fileName;
  String? title;
  String? artist;
  String? album;
  int? durationMs;
  String? coverPath;
  DateTime lastDownloadedAt;
  DateTime lastTagReadAt;

  String get identityKey => trackIdentityKey(accountId, remotePath);

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
        'album': album,
        'duration_ms': durationMs,
        'cover_path': coverPath,
        'last_downloaded_at': lastDownloadedAt.toIso8601String(),
        'last_tag_read_at': lastTagReadAt.toIso8601String(),
      };

  factory LibraryTrack.fromMap(Map<String, dynamic> map) => LibraryTrack(
        accountId: map['account_id'] as String,
        remotePath: map['remote_path'] as String,
        fileName: map['file_name'] as String,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        durationMs: map['duration_ms'] as int?,
        coverPath: map['cover_path'] as String?,
        lastDownloadedAt: DateTime.parse(map['last_downloaded_at'] as String),
        lastTagReadAt: DateTime.parse(map['last_tag_read_at'] as String),
      );
}
