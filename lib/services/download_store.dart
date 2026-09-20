import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_task.dart';

/// SQLite persistence for the download queue.
class DownloadStore {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'download_queue.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE download_tasks (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
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
  cache_group_id TEXT
)
''');
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE download_tasks ADD COLUMN account_id TEXT NOT NULL DEFAULT 'legacy'",
          );
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE download_tasks ADD COLUMN cache_group_id TEXT');
        }
      },
    );
    return _db!;
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_status ON download_tasks(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_created ON download_tasks(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_account_path ON download_tasks(account_id, remote_path)',
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
            where: 'account_id = ? AND remote_path = ?',
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
