import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/playlist.dart';

/// Dedicated playlist SQLite store under app documents.
/// Independent from audio cache — never wiped by [CacheService] cleanup.
class PlaylistStore {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'playlists.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE playlists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_file_name TEXT,
  entries_json TEXT NOT NULL
)
''');
      },
    );
    return _db!;
  }

  Future<List<Playlist>> loadAll() async {
    final db = await database;
    final rows = await db.query('playlists', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(_fromRow).toList();
  }

  Future<Playlist?> getById(String id) async {
    final db = await database;
    final rows = await db.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> upsert(Playlist playlist) async {
    final db = await database;
    await db.insert(
      'playlists',
      {
        'id': playlist.id,
        'name': playlist.name,
        'updated_at': playlist.updatedAt.toUtc().toIso8601String(),
        'remote_file_name': playlist.remoteFileName,
        'entries_json': jsonEncode(playlist.entries.map((e) => e.toJson()).toList()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('playlists');
  }

  Future<void> replaceAll(List<Playlist> playlists) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('playlists');
      for (final pl in playlists) {
        await txn.insert('playlists', {
          'id': pl.id,
          'name': pl.name,
          'updated_at': pl.updatedAt.toUtc().toIso8601String(),
          'remote_file_name': pl.remoteFileName,
          'entries_json': jsonEncode(pl.entries.map((e) => e.toJson()).toList()),
        });
      }
    });
  }

  Playlist _fromRow(Map<String, dynamic> row) {
    final raw = row['entries_json'] as String? ?? '[]';
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => PlaylistEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return Playlist(
      id: row['id'] as String,
      name: row['name'] as String,
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      remoteFileName: row['remote_file_name'] as String?,
      entries: list,
    );
  }

  /// Absolute path of the DB file (for backup).
  Future<String> databasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'playlists.db');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
