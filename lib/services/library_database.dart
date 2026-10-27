import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/webdav_account.dart';

/// Thin migrate/recovery shell around the legacy `music_library.db`.
///
/// Cold-start no longer opens this database. Remaining callers:
/// - [AccountsService._migrateFromSqfliteIfNeeded] → [loadAccounts]
/// - [AppState._migrateKvFoldersMeta] → [loadMeta] / [loadMetaByPrefix]
/// - [LocalDatabaseRecoveryService] → [fileName]
///
/// All product CRUD (tracks, CUE, manga, user-folders, cache groups,
/// tombstones, sync cursors) was removed. Sync-cursor key prefixes moved to
/// [LibrarySyncKeys]. Tables are left on disk for devices that have not yet
/// migrated — DROP TABLE is out of scope for this wave.
class LibraryDatabase {
  Database? _db;

  /// On-disk name; [LocalDatabaseRecoveryService] reads it from here so a
  /// rename cannot leave the recovery export behind.
  static const fileName = 'music_library.db';

  /// Opens the existing database file without running any schema upgrade.
  ///
  /// Only called from the load methods below, which guard with a file-existence
  /// check first — a missing file never reaches here and will not be created.
  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, fileName);
    // No version / onCreate / onUpgrade — open as-is for read-only migrate.
    _db = await openDatabase(path);
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // Migrate helpers — the only public API still used at runtime.
  // ---------------------------------------------------------------------------

  /// Return all accounts from the legacy sqflite store.
  ///
  /// Returns an empty list when the database file does not exist or when the
  /// `accounts` table cannot be read (e.g. schema predates v9).
  Future<List<WebDavAccount>> loadAccounts() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = p.join(dir.path, fileName);
    if (!File(file).existsSync()) return const [];
    try {
      final db = await database;
      final rows = await db.query(
        'accounts',
        orderBy: 'name COLLATE NOCASE ASC',
      );
      return rows.map(WebDavAccount.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Return the value for a single `local_meta` key, or null if absent.
  Future<String?> loadMeta(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = p.join(dir.path, fileName);
    if (!File(file).existsSync()) return null;
    try {
      final db = await database;
      final rows = await db.query(
        'local_meta',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Return all `local_meta` rows whose key starts with [prefix].
  Future<Map<String, String>> loadMetaByPrefix(String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = p.join(dir.path, fileName);
    if (!File(file).existsSync()) return const {};
    try {
      final db = await database;
      final rows = await db.query(
        'local_meta',
        where: 'key LIKE ?',
        whereArgs: [
          '${prefix.replaceAll('%', '\\%').replaceAll('_', '\\_')}%',
        ],
      );
      return {
        for (final r in rows) r['key'] as String: r['value'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
