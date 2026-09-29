import 'package:sqflite/sqflite.dart';

import '../models/playlist_deletion.dart';

/// Local queue of playlist deletions waiting to be published, and the copy of
/// what we last merged. Not the library tombstone table.
abstract class PlaylistDeletionLog {
  Future<List<PlaylistDeletion>> loadAll();

  Future<void> upsert(List<PlaylistDeletion> records);

  Future<void> replaceAll(List<PlaylistDeletion> records);

  Future<void> clear();
}

/// `playlist_deletions` in `playlists.db`. Created lazily so existing installs
/// pick it up without dropping the playlist table.
class SqlitePlaylistDeletionLog implements PlaylistDeletionLog {
  SqlitePlaylistDeletionLog(this._database);

  final Future<Database> Function() _database;
  bool _ready = false;

  Future<Database> _db() async {
    final db = await _database();
    if (!_ready) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS playlist_deletions (
  playlist_id TEXT NOT NULL,
  entry_identity TEXT NOT NULL DEFAULT '',
  deleted_at TEXT NOT NULL,
  PRIMARY KEY (playlist_id, entry_identity)
)
''');
      _ready = true;
    }
    return db;
  }

  @override
  Future<List<PlaylistDeletion>> loadAll() async {
    final db = await _db();
    final rows = await db.query(
      'playlist_deletions',
      orderBy: 'playlist_id ASC, entry_identity ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> upsert(List<PlaylistDeletion> records) async {
    if (records.isEmpty) return;
    final db = await _db();
    await db.transaction((txn) async {
      for (final record in records) {
        if (record.deletesPlaylist) {
          await txn.delete(
            'playlist_deletions',
            where: 'playlist_id = ?',
            whereArgs: [record.playlistId],
          );
        }
        await txn.insert('playlist_deletions', {
          'playlist_id': record.playlistId,
          'entry_identity': record.entryIdentity,
          'deleted_at': record.deletedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> replaceAll(List<PlaylistDeletion> records) async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.delete('playlist_deletions');
      for (final record in records) {
        await txn.insert('playlist_deletions', {
          'playlist_id': record.playlistId,
          'entry_identity': record.entryIdentity,
          'deleted_at': record.deletedAt.toUtc().toIso8601String(),
        });
      }
    });
  }

  @override
  Future<void> clear() async {
    final db = await _db();
    await db.delete('playlist_deletions');
  }

  PlaylistDeletion _fromRow(Map<String, Object?> row) {
    return PlaylistDeletion(
      playlistId: row['playlist_id']?.toString() ?? '',
      entryIdentity: row['entry_identity']?.toString() ?? '',
      deletedAt:
          DateTime.tryParse(row['deleted_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
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
