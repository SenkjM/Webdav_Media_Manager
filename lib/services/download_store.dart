import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_task.dart';

/// SQLite persistence for the download queue.
///
/// IMPORTANT: [upsert] passes `task.toMap()` straight to `db.insert`, so **the
/// map keys are the column names**. Any field added to [DownloadTask] must get a
/// matching column here and a schema bump, or every insert throws
/// `table download_tasks has no column named <field>` and the queue silently
/// stays empty (the error used to be swallowed by `enqueue(...).ignore()`).
class DownloadStore {
  Database? _db;

  /// Bumped whenever the queue schema changes.
  ///
  /// There is deliberately **no** migration code: an older on-disk schema is
  /// dropped and recreated (see [onUpgrade]). The queue is a transient list —
  /// losing it costs a re-enqueue, not data.
  static const schemaVersion = 5;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'download_queue.db');
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS download_tasks');
        await _createSchema(db);
      },
    );
    return _db!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE download_tasks (
  id TEXT PRIMARY KEY,
  remote_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  status TEXT NOT NULL,
  local_path TEXT,
  error_message TEXT,
  progress REAL NOT NULL DEFAULT 0,
  completed_at TEXT,
  bytes_total INTEGER,
  bytes_received INTEGER NOT NULL DEFAULT 0,
  cache_group_id TEXT,
  source_name TEXT NOT NULL DEFAULT '',
  target TEXT NOT NULL DEFAULT 'cache'
)
''');
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_status ON download_tasks(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_created ON download_tasks(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_source_path ON download_tasks(source_name, remote_path)',
    );
  }

  Future<List<DownloadTask>> loadAll() async {
    final db = await database;
    final rows = await db.query(
      'download_tasks',
      orderBy: 'created_at ASC',
    );
    return rows.map(DownloadTask.fromMap).toList();
  }

  Future<void> upsert(DownloadTask task) async {
    final db = await database;
    await db.insert(
      'download_tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('download_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByStatus(DownloadStatus status) async {
    final db = await database;
    await db.delete(
      'download_tasks',
      where: 'status = ?',
      whereArgs: [status.name],
    );
  }

  Future<DownloadTask?> findByRemotePath(
    String remotePath, {
    String? accountId,
  }) async {
    final db = await database;
    final rows = accountId == null
        ? await db.query(
            'download_tasks',
            where: 'remote_path = ?',
            whereArgs: [remotePath],
            limit: 1,
          )
        : await db.query(
            'download_tasks',
            where: 'source_name = ? AND remote_path = ?',
            whereArgs: [accountId, remotePath],
            limit: 1,
          );
    if (rows.isEmpty) return null;
    return DownloadTask.fromMap(rows.first);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
