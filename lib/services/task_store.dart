import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/queue_task.dart';

/// SQLite persistence for the task queue.
///
/// IMPORTANT: [upsert] passes `task.toMap()` straight to `db.insert`, so **the
/// map keys are the column names**. Any field added to [QueueTask] must get a
/// matching column here and a schema bump, or every insert throws
/// `table queue_tasks has no column named <field>` and the queue silently
/// stays empty.
class TaskStore {
  Database? _db;

  /// Bumped whenever the queue schema changes.
  ///
  /// There is deliberately **no** migration code: an older on-disk schema is
  /// dropped and recreated (see [onUpgrade]). The queue is a transient list —
  /// losing it costs a re-enqueue, not data.
  ///
  /// v9: added `is_enumerator`, which [QueueTask] had been writing all along —
  /// without the column every insert threw and nothing was ever persisted.
  ///
  /// v10: added `local_uri` for JIT SAF materialisation (local CBZ upload).
  static const schemaVersion = 10;

  /// On-disk name; see [LocalDatabaseRecoveryService].
  static const fileName = 'task_queue.db';

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, fileName);
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS queue_tasks');
        await db.execute('DROP TABLE IF EXISTS download_tasks');
        await _createSchema(db);
      },
    );
    return _db!;
  }

  /// The `queue_tasks` DDL.
  ///
  /// Public on purpose: `test/task_store_schema_test.dart` diffs it against
  /// `QueueTask.toMap()`. The map keys *are* the column names, so a field with
  /// no column here throws `no column named <field>` on **every** insert while
  /// `flutter analyze` stays green — that is exactly how `is_enumerator`
  /// shipped broken and the queue silently stopped persisting.
  static const createTableSql = '''
CREATE TABLE queue_tasks (
  id TEXT PRIMARY KEY,
  remote_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'download',
  status TEXT NOT NULL,
  local_path TEXT,
  local_uri TEXT,
  error_message TEXT,
  progress REAL NOT NULL DEFAULT 0,
  progress_mode TEXT NOT NULL DEFAULT 'bytes',
  completed_at TEXT,
  bytes_total INTEGER,
  bytes_received INTEGER NOT NULL DEFAULT 0,
  units_total INTEGER,
  units_done INTEGER NOT NULL DEFAULT 0,
  cache_group_id TEXT,
  is_enumerator INTEGER NOT NULL DEFAULT 0,
  source_name TEXT NOT NULL DEFAULT '',
  target TEXT NOT NULL DEFAULT 'cache',
  download_mode TEXT,
  remote_size INTEGER,
  remote_modified TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at TEXT
)
''';

  Future<void> _createSchema(Database db) async {
    await db.execute(createTableSql);
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_status ON queue_tasks(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_kind ON queue_tasks(kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_created ON queue_tasks(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_source_path ON queue_tasks(source_name, remote_path)',
    );
  }

  Future<List<QueueTask>> loadAll() async {
    final db = await database;
    final rows = await db.query('queue_tasks', orderBy: 'created_at ASC');
    return rows.map(QueueTask.fromMap).toList();
  }

  Future<void> upsert(QueueTask task) async {
    final db = await database;
    await db.insert(
      'queue_tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('queue_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByStatus(TaskStatus status) async {
    final db = await database;
    await db.delete(
      'queue_tasks',
      where: 'status = ?',
      whereArgs: [status.name],
    );
  }

  Future<QueueTask?> findByRemotePath(
    String remotePath, {
    String? accountId,
  }) async {
    final db = await database;
    final rows = accountId == null
        ? await db.query(
            'queue_tasks',
            where: 'remote_path = ?',
            whereArgs: [remotePath],
            limit: 1,
          )
        : await db.query(
            'queue_tasks',
            where: 'source_name = ? AND remote_path = ?',
            whereArgs: [accountId, remotePath],
            limit: 1,
          );
    if (rows.isEmpty) return null;
    return QueueTask.fromMap(rows.first);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
