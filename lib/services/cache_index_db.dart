import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cache_policy.dart';

/// Access-time index for the two media caches, kept in its **own** SQLite file
/// (`cache_index.db`) so cache bookkeeping never shares storage with the
/// library database.
///
/// Why a separate index at all: a cache file's *name* is derived from its
/// remote identity, so the file list is always reconstructible — but the two
/// things cleanup needs, "when was this last read" and "how big is it", are
/// not. Reading a file does not move its mtime, so mtime-based LRU silently
/// degrades into "oldest download wins" and expiry stops tracking real use.
/// [CacheService] pokes [touch] on every read and every completed download,
/// and both cleanup passes sort by `accessed_at`.
///
/// The table is a **best-effort index, never a source of truth**: a row whose
/// file vanished is ignored (and swept lazily), and a live file with no row
/// falls back to its mtime — the pre-index behaviour.
class CacheIndexDb {
  CacheIndexDb({Database? database}) : _db = database;

  /// Bumped whenever the index schema changes. There is deliberately no
  /// migration: the index is rebuildable bookkeeping, so an older on-disk
  /// schema is dropped and recreated.
  static const schemaVersion = 1;

  static const fileName = 'cache_index.db';
  static const table = 'cache_entries';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    // Same root as the cache directories themselves (`CacheService.init`), so
    // wiping app support wipes the index along with the files it describes.
    final dir = await getApplicationSupportDirectory();
    _db = await openDatabase(
      p.join(dir.path, fileName),
      version: schemaVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS $table');
        await _createSchema(db);
      },
    );
    return _db!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE $table (
  path TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  size INTEGER NOT NULL DEFAULT 0,
  accessed_at INTEGER NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cache_entries_kind ON $table(kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cache_entries_accessed ON $table(accessed_at)',
    );
  }

  /// Record (or refresh) [path] as accessed now. [size] is cached so eviction
  /// does not have to stat every file it considers.
  Future<void> touch(
    String path, {
    required CacheKind kind,
    int size = 0,
    DateTime? at,
  }) async {
    try {
      final db = await database;
      await db.insert(table, {
        'path': path,
        'kind': kind.name,
        'size': size,
        'accessed_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Bookkeeping must never break playback or reading.
    }
  }

  /// Record a read. Inserts a row when the path is not indexed yet (size stays
  /// 0 until a write or [touch] fills it in), so a first read is never lost.
  /// Existing rows only bump `accessed_at`.
  Future<void> touchRead(String path, {required CacheKind kind}) async {
    try {
      final db = await database;
      await db.rawInsert(
        'INSERT INTO $table (path, kind, size, accessed_at) VALUES (?, ?, 0, ?) '
        'ON CONFLICT(path) DO UPDATE SET accessed_at = excluded.accessed_at',
        [path, kind.storageKey, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (_) {}
  }

  Future<DateTime?> accessedAt(String path) async {
    try {
      final db = await database;
      final rows = await db.query(
        table,
        columns: ['accessed_at'],
        where: 'path = ?',
        whereArgs: [path],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        (rows.first['accessed_at'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Every indexed entry of [kind], keyed by absolute path. Cleanup passes read
  /// this once instead of querying per file.
  Future<Map<String, ({DateTime accessed, int size})>> entries(
    CacheKind kind,
  ) async {
    final out = <String, ({DateTime accessed, int size})>{};
    try {
      final db = await database;
      final rows = await db.query(table, where: 'kind = ?', whereArgs: [kind.name]);
      for (final r in rows) {
        final path = r['path'] as String?;
        if (path == null) continue;
        out[path] = (
          accessed: DateTime.fromMillisecondsSinceEpoch(
            (r['accessed_at'] as num?)?.toInt() ?? 0,
          ),
          size: (r['size'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return out;
  }

  Future<void> forget(String path) async {
    try {
      final db = await database;
      await db.delete(table, where: 'path = ?', whereArgs: [path]);
    } catch (_) {}
  }

  Future<void> forgetAll(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    try {
      final db = await database;
      final batch = db.batch();
      for (final path in list) {
        batch.delete(table, where: 'path = ?', whereArgs: [path]);
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  Future<void> forgetKind(CacheKind kind) async {
    try {
      final db = await database;
      await db.delete(table, where: 'kind = ?', whereArgs: [kind.name]);
    } catch (_) {}
  }

  /// Drop rows whose file no longer exists. Cheap to call after a mass delete.
  Future<void> pruneMissing(Iterable<String> candidatePaths) async {
    final gone = <String>[];
    for (final path in candidatePaths) {
      try {
        if (!await _fileExists(path)) gone.add(path);
      } catch (_) {}
    }
    await forgetAll(gone);
  }

  Future<bool> _fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
