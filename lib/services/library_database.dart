import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';

/// SQLite persistence for multi-WebDAV accounts and the local music library.
/// Separate from audio file cache — survives cache cleanup.
class LibraryDatabase {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'music_library.db');
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  username TEXT NOT NULL
)
''');
        await db.execute('''
CREATE TABLE tracks (
  account_id TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  title TEXT,
  artist TEXT,
  album_artist TEXT,
  album TEXT,
  duration_ms INTEGER,
  track_number INTEGER,
  track_total INTEGER,
  disc_number INTEGER,
  disc_total INTEGER,
  year INTEGER,
  genre TEXT,
  bitrate INTEGER,
  sample_rate INTEGER,
  cover_path TEXT,
  cue_remote_path TEXT,
  cue_track_index INTEGER,
  audio_remote_path TEXT,
  clip_start_ms INTEGER,
  clip_end_ms INTEGER,
  cache_group_id TEXT,
  last_downloaded_at TEXT NOT NULL,
  last_tag_read_at TEXT NOT NULL,
  PRIMARY KEY (account_id, remote_path)
)
''');
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN track_number INTEGER',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN disc_number INTEGER',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN album_artist TEXT',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN track_total INTEGER',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN disc_total INTEGER',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN year INTEGER',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN genre TEXT',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN bitrate INTEGER',
          );
          await db.execute(
            'ALTER TABLE tracks ADD COLUMN sample_rate INTEGER',
          );
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE tracks ADD COLUMN cue_remote_path TEXT');
          await db.execute('ALTER TABLE tracks ADD COLUMN cue_track_index INTEGER');
          await db.execute('ALTER TABLE tracks ADD COLUMN audio_remote_path TEXT');
          await db.execute('ALTER TABLE tracks ADD COLUMN clip_start_ms INTEGER');
          await db.execute('ALTER TABLE tracks ADD COLUMN clip_end_ms INTEGER');
          await db.execute('ALTER TABLE tracks ADD COLUMN cache_group_id TEXT');
        }
      },
    );
    return _db!;
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title)',
    );
  }

  // --- Accounts ---

  Future<List<WebDavAccount>> loadAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(WebDavAccount.fromMap).toList();
  }

  Future<void> upsertAccount(WebDavAccount account) async {
    final db = await database;
    await db.insert(
      'accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Tracks ---

  Future<void> upsertTrack(LibraryTrack track) async {
    final db = await database;
    await db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LibraryTrack?> getTrack(String accountId, String remotePath) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'account_id = ? AND remote_path = ?',
      whereArgs: [accountId, remotePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LibraryTrack.fromMap(rows.first);
  }

  Future<List<LibraryTrack>> allTracks() async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    return rows.map(LibraryTrack.fromMap).toList();
  }

  Future<List<LibraryTrack>> tracksForAccount(String accountId) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    return rows.map(LibraryTrack.fromMap).toList();
  }

  Future<List<LibraryTrack>> tracksByArtist(String artist) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'IFNULL(NULLIF(TRIM(artist), ""), "未知艺术家") = ?',
      whereArgs: [artist],
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    return rows.map(LibraryTrack.fromMap).toList();
  }

  Future<List<LibraryTrack>> tracksByAlbum(String album) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'IFNULL(NULLIF(TRIM(album), ""), "未知专辑") = ?',
      whereArgs: [album],
      orderBy:
          'IFNULL(disc_number, 1) ASC, IFNULL(track_number, 2147483647) ASC, '
          'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    return rows.map(LibraryTrack.fromMap).toList();
  }

  Future<List<String>> distinctArtists() async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT DISTINCT IFNULL(NULLIF(TRIM(artist), ''), '未知艺术家') AS a
FROM tracks ORDER BY a COLLATE NOCASE ASC
''');
    return rows.map((r) => r['a'] as String).toList();
  }

  Future<List<String>> distinctAlbums() async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT DISTINCT IFNULL(NULLIF(TRIM(album), ''), '未知专辑') AS a
FROM tracks ORDER BY a COLLATE NOCASE ASC
''');
    return rows.map((r) => r['a'] as String).toList();
  }

  Future<int> trackCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM tracks');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> deleteTracksForAccount(String accountId) async {
    final db = await database;
    await db.delete('tracks', where: 'account_id = ?', whereArgs: [accountId]);
  }

  Future<void> deleteTrack(String accountId, String remotePath) async {
    final db = await database;
    await db.delete(
      'tracks',
      where: 'account_id = ? AND remote_path = ?',
      whereArgs: [accountId, remotePath],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
