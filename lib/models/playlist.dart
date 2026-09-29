import '../utils/track_identity.dart';
import 'playlist_sentinels.dart';

/// A playlist track identity: 权威身份为 [musicId]（docs/10 §4.4）。
///
/// `sourceName` + `remotePath` 保留用于显示与按曲库回退查找；身份按归一化
/// 规则计算（`sha1(网盘名\0remotePath)`），CUE 切片用显式 [cueTrackIndex]
/// （`sha1(网盘名\0cuePath\0idx)`），不再从 `#cue:` 路径字符串取身份。
class PlaylistEntry {
  const PlaylistEntry({
    required this.sourceName,
    required this.remotePath,
    this.musicId,
    this.title,
    this.durationMs,
    this.cueTrackIndex,
  });

  final String sourceName;
  final String remotePath;

  /// 权威身份键（与曲库 musicId 同源）。缺省时按归一化规则即时计算。
  final String? musicId;
  final String? title;
  final int? durationMs;

  /// CUE 切片的曲目序号；参与身份计算。
  final int? cueTrackIndex;

  /// 条目身份键：显式 [musicId] 优先（所有新写入路径都会带上）。
  ///
  /// 缺省时按归一化规则即时计算，仅用于旧本地行兜底：普通条目可与曲库
  /// 重新对齐；CUE 虚拟路径无法反推 .cue 源路径（切片 id 以 .cue 路径参与
  /// 散列），退回 backing audio 的 musicId，至少能解析到整轨而不是永远缺失。
  String get identityKey {
    final explicit = musicId;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final cue = parseCueVirtualRemotePath(remotePath);
    if (cue != null) {
      return musicIdForRemote(sourceName, cue.audioRemotePath);
    }
    return musicIdForRemote(sourceName, remotePath);
  }

  Map<String, dynamic> toJson() => {
    'sourceName': sourceName,
    'remotePath': remotePath,
    if (musicId != null) 'musicId': musicId,
    if (title != null) 'title': title,
    if (durationMs != null) 'durationMs': durationMs,
    if (cueTrackIndex != null) 'cueTrackIndex': cueTrackIndex,
  };

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) => PlaylistEntry(
    sourceName: (json['sourceName'] ?? json['accountId']) as String? ?? '',
    remotePath: json['remotePath'] as String? ?? '',
    musicId: json['musicId'] as String?,
    title: json['title'] as String?,
    durationMs: json['durationMs'] as int?,
    cueTrackIndex: json['cueTrackIndex'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}

/// Local + syncable playlist. Survives audio cache cleanup.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<PlaylistEntry>? entries,
    DateTime? updatedAt,
    this.remoteFileName,
  }) : entries = List<PlaylistEntry>.from(entries ?? const []),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  final List<PlaylistEntry> entries;
  DateTime updatedAt;

  /// Remote playlist file name under the playlists dir, e.g. `favorites.wdmp`.
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
    name: json['name'] as String? ?? kUnnamedPlaylistName,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
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
