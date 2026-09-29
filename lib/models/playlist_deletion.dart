/// One deletion inside a playlist's own deletion pack.
///
/// [entryIdentity] empty means the whole playlist was deleted. These records
/// never go into the music library's `deleted_tracks` table.
class PlaylistDeletion {
  const PlaylistDeletion({
    required this.playlistId,
    required this.deletedAt,
    this.entryIdentity = '',
  });

  final String playlistId;

  /// `musicId` of a removed entry. Empty when the whole playlist is gone.
  final String entryIdentity;

  final DateTime deletedAt;

  bool get deletesPlaylist => entryIdentity.isEmpty;

  PlaylistDeletion copyWith({DateTime? deletedAt}) => PlaylistDeletion(
    playlistId: playlistId,
    entryIdentity: entryIdentity,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
