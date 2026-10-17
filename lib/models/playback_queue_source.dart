/// Where the now-playing queue came from.
///
/// Persisted together with the queue (identity-only entries) so the queue can
/// be regenerated, its metadata re-resolved from the library, and the
/// auto-scrape scope decided without asking the originating screen again.
enum PlaybackQueueSourceKind {
  /// A folder opened in the network library (walk window from Settings).
  networkFolder,

  /// A music-library list (album / artist / genre / title / all).
  libraryQueue,

  /// A saved playlist.
  savedPlaylist,

  /// A user folder (direct music refs only, no child folders).
  userFolder,

  /// One CUE album opened from the network library preview.
  cueAlbum,
}

class PlaybackQueueSource {
  const PlaybackQueueSource({
    required this.kind,
    this.accountId = '',
    this.folderPath = '',
    this.includeSubdirs = false,
    this.maxDepth = 0,
    this.playlistId = '',
    this.userFolderId = '',
    this.cueRemotePath = '',
  });

  factory PlaybackQueueSource.networkFolder({
    required String accountId,
    required String folderPath,
    required bool includeSubdirs,
    required int maxDepth,
  }) => PlaybackQueueSource(
    kind: PlaybackQueueSourceKind.networkFolder,
    accountId: accountId,
    folderPath: folderPath,
    includeSubdirs: includeSubdirs,
    maxDepth: maxDepth,
  );

  factory PlaybackQueueSource.libraryQueue() =>
      const PlaybackQueueSource(kind: PlaybackQueueSourceKind.libraryQueue);

  factory PlaybackQueueSource.savedPlaylist(String playlistId) =>
      PlaybackQueueSource(
        kind: PlaybackQueueSourceKind.savedPlaylist,
        playlistId: playlistId,
      );

  factory PlaybackQueueSource.userFolder(String userFolderId) =>
      PlaybackQueueSource(
        kind: PlaybackQueueSourceKind.userFolder,
        userFolderId: userFolderId,
      );

  factory PlaybackQueueSource.cueAlbum({
    required String accountId,
    required String folderPath,
    required String cueRemotePath,
  }) => PlaybackQueueSource(
    kind: PlaybackQueueSourceKind.cueAlbum,
    accountId: accountId,
    folderPath: folderPath,
    cueRemotePath: cueRemotePath,
  );

  final PlaybackQueueSourceKind kind;
  final String accountId;
  final String folderPath;
  final bool includeSubdirs;
  final int maxDepth;
  final String playlistId;
  final String userFolderId;
  final String cueRemotePath;

  /// True when the source has one folder root whose walk window also defines
  /// the auto-scrape / subdirectory scope.
  bool get isFolderRoot =>
      kind == PlaybackQueueSourceKind.networkFolder ||
      kind == PlaybackQueueSourceKind.cueAlbum;

  /// Root used by queue-root auto-backfill; empty for non-folder sources.
  String get scrapeRoot => isFolderRoot ? folderPath : '';

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'accountId': accountId,
    'folderPath': folderPath,
    'includeSubdirs': includeSubdirs,
    'maxDepth': maxDepth,
    'playlistId': playlistId,
    'userFolderId': userFolderId,
    'cueRemotePath': cueRemotePath,
  };

  static PlaybackQueueSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final kindName = map['kind']?.toString();
    PlaybackQueueSourceKind? kind;
    for (final k in PlaybackQueueSourceKind.values) {
      if (k.name == kindName) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;
    final maxDepth = map['maxDepth'];
    return PlaybackQueueSource(
      kind: kind,
      accountId: map['accountId']?.toString() ?? '',
      folderPath: map['folderPath']?.toString() ?? '',
      includeSubdirs: map['includeSubdirs'] == true,
      maxDepth: maxDepth is num ? maxDepth.toInt() : 0,
      playlistId: map['playlistId']?.toString() ?? '',
      userFolderId: map['userFolderId']?.toString() ?? '',
      cueRemotePath: map['cueRemotePath']?.toString() ?? '',
    );
  }
}
