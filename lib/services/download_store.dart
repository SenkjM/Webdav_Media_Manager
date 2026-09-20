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
      version: 1,
      onCreate: (db, version) async {
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
  bytes_received INTEGER NOT NULL DEFAULT 0
)
''');
        await db.execute(
          'CREATE INDEX idx_tasks_status ON download_tasks(status)',
        );
        await db.execute(
          'CREATE INDEX idx_tasks_created ON download_tasks(created_at)',
        );
      },
    );
    return _db!;
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

  Future<DownloadTask?> findByRemotePath(String remotePath) async {
    final db = await database;
    final rows = await db.query(
      'download_tasks',
      where: 'remote_path = ?',
      whereArgs: [remotePath],
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
