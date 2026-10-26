import '../models/playlist_deletion.dart';

/// Local queue of playlist deletions waiting to be published, and the copy of
/// what we last merged. Not the library tombstone table.
abstract class PlaylistDeletionLog {
  Future<List<PlaylistDeletion>> loadAll();

  Future<void> upsert(List<PlaylistDeletion> records);

  Future<void> replaceAll(List<PlaylistDeletion> records);

  Future<void> clear();
}

/// In-memory log for tests.
class MemoryPlaylistDeletionLog implements PlaylistDeletionLog {
  final Map<String, PlaylistDeletion> rows = {};

  String _key(PlaylistDeletion record) =>
      '${record.playlistId}\u0000${record.entryIdentity}';

  @override
  Future<List<PlaylistDeletion>> loadAll() async {
    final list = rows.values.toList()
      ..sort((a, b) {
        final byId = a.playlistId.compareTo(b.playlistId);
        if (byId != 0) return byId;
        return a.entryIdentity.compareTo(b.entryIdentity);
      });
    return list;
  }

  @override
  Future<void> upsert(List<PlaylistDeletion> records) async {
    for (final record in records) {
      if (record.deletesPlaylist) {
        rows.removeWhere(
          (key, _) => key.startsWith('${record.playlistId}\u0000'),
        );
      }
      rows[_key(record)] = record;
    }
  }

  @override
  Future<void> replaceAll(List<PlaylistDeletion> records) async {
    rows
      ..clear()
      ..addEntries(records.map((r) => MapEntry(_key(r), r)));
  }

  @override
  Future<void> clear() async => rows.clear();
}
