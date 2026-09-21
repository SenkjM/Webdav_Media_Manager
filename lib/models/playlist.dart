import '../utils/track_identity.dart';

/// A playlist track identity: 网盘名 + remotePath (library key).
class PlaylistEntry {
  const PlaylistEntry({
    required this.sourceName,
    required this.remotePath,
    this.title,
    this.durationMs,
  });

  final String sourceName;
  final String remotePath;
  final String? title;
  final int? durationMs;

  String get identityKey => trackIdentityKey(sourceName, remotePath);

  Map<String, dynamic> toJson() => {
        'sourceName': sourceName,
        'remotePath': remotePath,
        if (title != null) 'title': title,
        if (durationMs != null) 'durationMs': durationMs,
      };

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) => PlaylistEntry(
        sourceName:
            (json['sourceName'] ?? json['accountId']) as String? ?? '',
        remotePath: json['remotePath'] as String? ?? '',
        title: json['title'] as String?,
        durationMs: json['durationMs'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry &&
      other.sourceName == sourceName &&
      other.remotePath == remotePath;

  @override
  int get hashCode => Object.hash(sourceName, remotePath);
}

/// Local + syncable playlist. Survives audio cache cleanup.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<PlaylistEntry>? entries,
    DateTime? updatedAt,
    this.remoteFileName,
  })  : entries = List<PlaylistEntry>.from(entries ?? const []),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  final List<PlaylistEntry> entries;
  DateTime updatedAt;

  /// Remote M3U8 file name under playlists path, e.g. `favorites.m3u8`.
  String? remoteFileName;

  int get length => entries.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'updatedAt': updatedAt.toIso8601String(),
        'remoteFileName': remoteFileName,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未命名',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        remoteFileName: json['remoteFileName'] as String?,
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => PlaylistEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Playlist copyWith({
    String? name,
    List<PlaylistEntry>? entries,
    DateTime? updatedAt,
    String? remoteFileName,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      entries: entries ?? List<PlaylistEntry>.from(this.entries),
      updatedAt: updatedAt ?? this.updatedAt,
      remoteFileName: remoteFileName ?? this.remoteFileName,
    );
  }
}

/// Last-write-wins merge: keep the playlist with the newer [updatedAt].
/// Equal timestamps prefer [local] (no remote overwrite of simultaneous edits).
Playlist mergePlaylistsLastWriteWins(Playlist local, Playlist remote) {
  if (remote.updatedAt.isAfter(local.updatedAt)) return remote;
  return local;
}
