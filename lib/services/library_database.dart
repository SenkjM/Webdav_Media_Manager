import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_track.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import '../models/manga_progress.dart';
import '../models/manga_series.dart';
import '../models/user_folder.dart';
import '../models/user_folder_item.dart';
import '../models/webdav_account.dart';
import '../utils/cache_group_codec.dart';
import '../utils/track_identity.dart';

/// SQLite persistence for multi-WebDAV accounts and the local music library.
/// Separate from audio file cache — survives cache cleanup.
///
/// Schema v15: mangas.rev + `deleted_mangas` tombstones (manga cloud sync) and
/// `local_meta` (small key/value bookkeeping, e.g. user-folder snapshot sync).
/// Schema v14: mangas.page_turn (nullable per-manga page-turn override).
/// Schema v13: manga library tables (`manga_series` / `mangas` / `manga_pages` /
/// `manga_progress`; 99 §19) — additive; music path unchanged.
/// Schema v12: local user folder overlay (`user_folders` / `user_folder_items`;
/// 99 §18) — does not change track identity tables.
/// Schema v11: `accounts.name_key` + UNIQUE (normalized name; 99 §17.17).
/// Schema v10 adds `remote_missing` on tracks/cue_slices.
/// Schema v9:
/// - `accounts` — site (stable sourceName; display name separate)
/// - `tracks` — music_id PK, library identity (survives cache clear)
/// - `cue_albums` / `cue_slices` — CUE identity + clips stay in library
/// - `cache_groups` — runtime CUE-album membership (group id → member rows);
///   moved out of SharedPreferences in v8 (99 §6.2 T1)
/// - `cache_access` — runtime LRU timestamps (source + path → last play)
///
/// v9 drops the `cache` annex: no column ever carried information that could
/// not be derived from (source_name, remote_path) — local_path was always the
/// deterministic cache file name, etag / size_bytes had no readers. isLocal is
/// now a lazy File.exists on the derived path (CacheService).
class LibraryDatabase {
  Database? _db;

  /// True when historical same-name rows block the name_key UNIQUE index.
  /// Cleared after the user deletes conflicts and [applyAccountNameUnique] runs.
  bool accountNameUniquePending = false;

  /// Current schema. Wipe/rebuild on upgrade (migration cost ignored).
  static const schemaVersion = 15;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'music_library.db');
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Pre-v11: wipe library index tables and rebuild (historical policy).
        // v11→v12: keep tracks; only add the user-folder overlay tables.
        // v12→v13: keep tracks; only add manga library tables (99 §19).
        if (oldVersion < 11) {
          for (final table in [
            'cache',
            'cache_access',
            'cache_groups',
            'cue_slices',
            'cue_albums',
            'tracks',
            'deleted_tracks',
            'sync_state',
            'user_folder_items',
            'user_folders',
            'manga_pages',
            'manga_progress',
            'mangas',
            'manga_series',
            'deleted_mangas',
            'local_meta',
          ]) {
            await db.execute('DROP TABLE IF EXISTS $table');
          }
          await _createSchema(db);
        }
        // 云盘 provider（99 §7 阶段 0）：accounts 老表不重建（保留库名绑定），
        // 逐列补齐新列；新库由 _createSchema 直接带全列。
        await _ensureAccountColumns(db);
        await _ensureUserFolderTables(db);
        await _ensureMangaTables(db);
      },
    );
    // Always reconcile name_key / UNIQUE after open (also covers already-v11
    // installs that still had duplicate names when the index was deferred).
    await _ensureAccountColumns(_db!);
    await _ensureUserFolderTables(_db!);
    await _ensureMangaTables(_db!);
    await _reconcileAccountNameUnique(_db!);
    return _db!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL,
  url TEXT NOT NULL,
  username TEXT NOT NULL,
  provider_type TEXT NOT NULL DEFAULT 'webdav',
  remote_path TEXT NOT NULL DEFAULT '/',
  capabilities INTEGER NOT NULL DEFAULT 127,
  UNIQUE(name_key)
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS tracks (
  music_id TEXT PRIMARY KEY,
  source_name TEXT NOT NULL,
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
  rev INTEGER NOT NULL DEFAULT 0,
  last_downloaded_at TEXT NOT NULL,
  last_tag_read_at TEXT NOT NULL,
  remote_missing INTEGER NOT NULL DEFAULT 0,
  UNIQUE(source_name, remote_path)
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS cue_albums (
  cue_id TEXT PRIMARY KEY,
  source_name TEXT NOT NULL,
  cue_remote_path TEXT NOT NULL,
  title TEXT,
  performer TEXT,
  cache_group_id TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(source_name, cue_remote_path)
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS cue_slices (
  music_id TEXT PRIMARY KEY,
  cue_id TEXT NOT NULL,
  audio_music_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  track_index INTEGER NOT NULL,
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
  audio_remote_path TEXT,
  clip_start_ms INTEGER,
  clip_end_ms INTEGER,
  cache_group_id TEXT,
  rev INTEGER NOT NULL DEFAULT 0,
  last_downloaded_at TEXT NOT NULL,
  last_tag_read_at TEXT NOT NULL,
  remote_missing INTEGER NOT NULL DEFAULT 0,
  UNIQUE(source_name, remote_path)
)
''');
    // Runtime「CUE 整专辑一组」membership. Keyed by the CUE group id (not by
    // String.hashCode, so different groups can never collide); `members` is a
    // JSON array of `sourceName\u0000remotePath` identities. This used to live
    // in SharedPreferences and is migrated once in CacheService.init().
    await db.execute('''
CREATE TABLE IF NOT EXISTS cache_groups (
  group_id TEXT PRIMARY KEY,
  members TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
    // Runtime LRU timestamps for cache expiry, keyed by real source + path
    // (the old prefs keys hashed the identity and could not be reversed).
    await db.execute('''
CREATE TABLE IF NOT EXISTS cache_access (
  source_name TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  accessed_at TEXT NOT NULL,
  PRIMARY KEY (source_name, remote_path)
)
''');
    // Deletions live in their **own** table, never as a soft-delete column on
    // `tracks`: a flag would have to be filtered out of every list / search /
    // count / cover query, and one missed filter shows a destroyed song again.
    await db.execute('''
CREATE TABLE IF NOT EXISTS deleted_tracks (
  source_name TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  rev INTEGER NOT NULL,
  deleted_at TEXT NOT NULL,
  pushed INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (source_name, remote_path)
)
''');
    // Per-remote sync cursor: how far we have consumed, and which file satisfies
    // which rev range (so a rebuilt shard is re-fetched instead of trusted).
    await db.execute('''
CREATE TABLE IF NOT EXISTS sync_state (
  remote_key TEXT PRIMARY KEY,
  last_seq INTEGER NOT NULL DEFAULT 0,
  base_up_to INTEGER NOT NULL DEFAULT 0,
  parts TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL
)
''');
    await _ensureUserFolderTables(db);
    await _ensureMangaTables(db);
    await _createIndexes(db);
  }

  /// Local-only folder overlay (99 §18). Idempotent; safe on every open.
  Future<void> _ensureUserFolderTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS user_folders (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY(parent_id) REFERENCES user_folders(id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS user_folder_items (
  folder_id TEXT NOT NULL,
  ref_kind TEXT NOT NULL,
  ref_key TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  added_at TEXT NOT NULL,
  PRIMARY KEY(folder_id, ref_kind, ref_key),
  FOREIGN KEY(folder_id) REFERENCES user_folders(id) ON DELETE CASCADE
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_folders_parent '
      'ON user_folders(parent_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_folder_items_folder '
      'ON user_folder_items(folder_id)',
    );
  }


  /// Manga library tables (99 §19). Idempotent; safe on every open.
  Future<void> _ensureMangaTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS manga_series (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT,
  sort_title TEXT,
  created_at TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS mangas (
  id TEXT PRIMARY KEY,
  source_name TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT,
  series_id TEXT,
  volume TEXT,
  chapter_number TEXT,
  page_count INTEGER NOT NULL DEFAULT 0,
  cover_relpath TEXT,
  format TEXT NOT NULL DEFAULT 'unknown',
  remote_missing INTEGER NOT NULL DEFAULT 0,
  page_turn TEXT,
  updated_at TEXT NOT NULL,
  UNIQUE(source_name, remote_path),
  FOREIGN KEY(series_id) REFERENCES manga_series(id) ON DELETE SET NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS manga_pages (
  manga_id TEXT NOT NULL,
  page_index INTEGER NOT NULL,
  rel_path TEXT NOT NULL,
  PRIMARY KEY(manga_id, page_index),
  FOREIGN KEY(manga_id) REFERENCES mangas(id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS manga_progress (
  manga_id TEXT PRIMARY KEY,
  page_index INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(manga_id) REFERENCES mangas(id) ON DELETE CASCADE
)
''');
    // Manga deletions (cloud sync), same shape and rules as `deleted_tracks`.
    await db.execute('''
CREATE TABLE IF NOT EXISTS deleted_mangas (
  source_name TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  rev INTEGER NOT NULL,
  deleted_at TEXT NOT NULL,
  pushed INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (source_name, remote_path)
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS local_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_mangas_series ON mangas(series_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_mangas_author ON mangas(author)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_mangas_source ON mangas(source_name)',
    );
    await _ensureMangaColumns(db);
  }

  /// Additive manga columns (v14+). Idempotent PRAGMA check.
  Future<void> _ensureMangaColumns(Database db) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='mangas'",
    );
    if (table.isEmpty) return;
    final cols = (await db.rawQuery('PRAGMA table_info(mangas)'))
        .map((row) => row['name'] as String)
        .toSet();
    if (!cols.contains('page_turn')) {
      await db.execute('ALTER TABLE mangas ADD COLUMN page_turn TEXT');
    }
    if (!cols.contains('rev')) {
      await db.execute(
        'ALTER TABLE mangas ADD COLUMN rev INTEGER NOT NULL DEFAULT 0',
      );
    }
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tracks_source ON tracks(source_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cue_slices_cue ON cue_slices(cue_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cue_slices_audio ON cue_slices(audio_music_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cue_albums_source ON cue_albums(source_name)',
    );
  }

  /// accounts 表按需补列（PRAGMA 检查，幂等）。默认值与 [AccountCaps.all] 对齐。
  Future<void> _ensureAccountColumns(Database db) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts'",
    );
    if (table.isEmpty) {
      // Fresh open before onCreate finished, or wiped — nothing to patch.
      return;
    }
    final cols = (await db.rawQuery('PRAGMA table_info(accounts)'))
        .map((row) => row['name'] as String)
        .toSet();
    if (!cols.contains('provider_type')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN provider_type TEXT NOT NULL DEFAULT 'webdav'",
      );
    }
    if (!cols.contains('remote_path')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN remote_path TEXT NOT NULL DEFAULT '/'",
      );
    }
    if (!cols.contains('capabilities')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN capabilities INTEGER NOT NULL DEFAULT 127',
      );
    }
    if (!cols.contains('name_key')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN name_key TEXT NOT NULL DEFAULT ''",
      );
    }
    // 旧默认 63（六位掩码）→ 当前全量 127：能力勾选 UI 上线前不存在自定义值，
    // 全量替换安全（99 §7.2.3 的 mkdir 拆位）。
    await db.execute(
      'UPDATE accounts SET capabilities = 127 WHERE capabilities = 63',
    );
    await _backfillAccountNameKeys(db);
  }

  Future<void> _backfillAccountNameKeys(Database db) async {
    final rows = await db.query('accounts', columns: ['id', 'name', 'name_key']);
    for (final row in rows) {
      final id = row['id'] as String? ?? '';
      final name = row['name'] as String? ?? '';
      final key = accountNameKey(name);
      if (id.isEmpty) continue;
      if ((row['name_key'] as String? ?? '') == key) continue;
      await db.update(
        'accounts',
        {'name_key': key},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Duplicate [name_key] values still present in `accounts` (normalized).
  Future<List<String>> duplicateAccountNameKeys() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT name_key FROM accounts "
      "WHERE name_key != '' "
      "GROUP BY name_key "
      "HAVING COUNT(*) > 1",
    );
    return [
      for (final r in rows) (r['name_key'] as String?) ?? '',
    ].where((k) => k.isNotEmpty).toList();
  }

  Future<bool> _hasAccountNameKeyUnique(Database db) async {
    final master = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='accounts'",
    );
    final createSql = ((master.isEmpty ? null : master.first['sql']) as String?)
            ?.toUpperCase() ??
        '';
    if (createSql.contains('NAME_KEY') && createSql.contains('UNIQUE')) {
      return true;
    }
    final indexes = await db.rawQuery("PRAGMA index_list('accounts')");
    for (final idx in indexes) {
      if (idx['unique'] != 1) continue;
      final name = idx['name'] as String?;
      if (name == null) continue;
      final info = await db.rawQuery('PRAGMA index_info("$name")');
      if (info.length == 1 && info.first['name'] == 'name_key') {
        return true;
      }
    }
    return false;
  }

  Future<void> _reconcileAccountNameUnique(Database db) async {
    if (await _hasAccountNameKeyUnique(db)) {
      accountNameUniquePending = false;
      return;
    }
    // 0.2.4: only collapse duplicates when UNIQUE cannot be installed.
    await _collapseDuplicateAccountNames(db);
    final applied = await _tryCreateAccountNameUniqueIndex(db);
    accountNameUniquePending = !applied;
  }

  /// Keep one row per [name_key] (prefer [preferAccountId], else smallest id).
  /// Returns deleted account ids (caller clears secure storage).
  Future<List<String>> _collapseDuplicateAccountNames(
    Database db, {
    String? preferAccountId,
  }) async {
    final rows = await db.query('accounts', columns: ['id', 'name_key']);
    final byKey = <String, List<String>>{};
    for (final row in rows) {
      final key = (row['name_key'] as String?) ?? '';
      final id = (row['id'] as String?) ?? '';
      if (key.isEmpty || id.isEmpty) continue;
      byKey.putIfAbsent(key, () => []).add(id);
    }
    final deleted = <String>[];
    for (final ids in byKey.values) {
      if (ids.length < 2) continue;
      ids.sort();
      String keep = ids.first;
      if (preferAccountId != null && ids.contains(preferAccountId)) {
        keep = preferAccountId;
      }
      for (final id in ids) {
        if (id == keep) continue;
        await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
        deleted.add(id);
      }
    }
    return deleted;
  }

  /// Public entry used by AccountsService after load (clears secure for drops).
  Future<List<String>> collapseDuplicateAccountNames({
    String? preferAccountId,
  }) async {
    final db = await database;
    await _backfillAccountNameKeys(db);
    final deleted =
        await _collapseDuplicateAccountNames(db, preferAccountId: preferAccountId);
    await _reconcileAccountNameUnique(db);
    return deleted;
  }

  /// Returns true when the UNIQUE index is in place (or already was).
  Future<bool> _tryCreateAccountNameUniqueIndex(Database db) async {
    final dups = await db.rawQuery(
      "SELECT name_key FROM accounts "
      "WHERE name_key != '' "
      "GROUP BY name_key "
      "HAVING COUNT(*) > 1",
    );
    if (dups.isNotEmpty) return false;
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_name_key '
        'ON accounts(name_key)',
      );
      return true;
    } catch (_) {
      // Race or residual conflict — leave pending for cleanup UI.
      return false;
    }
  }

  /// After the user removes name conflicts, install the UNIQUE hard floor.
  /// Returns true when uniqueness is enforced.
  Future<bool> applyAccountNameUnique() async {
    final db = await database;
    await _backfillAccountNameKeys(db);
    if (await _hasAccountNameKeyUnique(db)) {
      accountNameUniquePending = false;
      return true;
    }
    final applied = await _tryCreateAccountNameUniqueIndex(db);
    accountNameUniquePending = !applied;
    return applied;
  }

  // --- Accounts ---

  Future<List<WebDavAccount>> loadAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(WebDavAccount.fromMap).toList();
  }

  Future<void> upsertAccount(WebDavAccount account) async {
    final db = await database;
    final map = Map<String, Object?>.from(account.toMap())
      ..['name_key'] = accountNameKey(account.name);
    // Never ConflictAlgorithm.replace: UNIQUE(name_key) would delete the other
    // account row on a name clash. Upsert by id only; name clashes abort.
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [account.id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('accounts', map);
    } else {
      await db.update(
        'accounts',
        map,
        where: 'id = ?',
        whereArgs: [account.id],
      );
    }
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Tracks (normal, non-CUE) ---

  Future<void> upsertTrack(LibraryTrack track) async {
    final db = await database;
    if (track.isCueVirtual) {
      await upsertCueSlice(track);
      return;
    }
    await db.insert(
      'tracks',
      track.toTrackTableMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCueSlice(LibraryTrack track) async {
    final db = await database;
    await _upsertCueSlice(db, track);
  }

  Future<void> _upsertCueSlice(DatabaseExecutor db, LibraryTrack track) async {
    final cuePath = track.cueRemotePath;
    if (cuePath == null || cuePath.isEmpty) {
      throw StateError('cue_slices require cue_remote_path');
    }
    final cueId = track.cueId ?? cueIdFor(track.sourceName, cuePath);
    await db.insert('cue_albums', {
      'cue_id': cueId,
      'source_name': track.sourceName,
      'cue_remote_path': normalizeRemotePath(cuePath),
      'title': track.album,
      'performer': track.albumArtist ?? track.artist,
      'cache_group_id': track.cacheGroupId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // Refresh cache_group_id / title if album already existed.
    final albumPatch = <String, Object?>{
      if (track.cacheGroupId != null) 'cache_group_id': track.cacheGroupId,
      if (track.album != null) 'title': track.album,
    };
    if (albumPatch.isNotEmpty) {
      await db.update(
        'cue_albums',
        albumPatch,
        where: 'cue_id = ?',
        whereArgs: [cueId],
      );
    }
    final slice = LibraryTrack(
      musicId: track.musicId,
      sourceName: track.sourceName,
      remotePath: track.remotePath,
      fileName: track.fileName,
      title: track.title,
      artist: track.artist,
      albumArtist: track.albumArtist,
      album: track.album,
      durationMs: track.durationMs,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      discNumber: track.discNumber,
      discTotal: track.discTotal,
      year: track.year,
      genre: track.genre,
      bitrate: track.bitrate,
      sampleRate: track.sampleRate,
      coverPath: track.coverPath,
      cueId: cueId,
      cueRemotePath: cuePath,
      cueTrackIndex: track.cueTrackIndex,
      audioMusicId:
          track.audioMusicId ??
          (track.audioRemotePath != null
              ? musicIdForRemote(track.sourceName, track.audioRemotePath!)
              : null),
      audioRemotePath: track.audioRemotePath,
      clipStartMs: track.clipStartMs,
      clipEndMs: track.clipEndMs,
      cacheGroupId: track.cacheGroupId,
      lastDownloadedAt: track.lastDownloadedAt,
      lastTagReadAt: track.lastTagReadAt,
    );
    await db.insert(
      'cue_slices',
      slice.toCueSliceTableMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LibraryTrack?> getTrack(String sourceName, String remotePath) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, remotePath],
      limit: 1,
    );
    if (rows.isNotEmpty) return LibraryTrack.fromMap(rows.first);

    final cueRows = await db.query(
      'cue_slices',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, remotePath],
      limit: 1,
    );
    if (cueRows.isEmpty) return null;
    return _hydrateSlice(cueRows.first);
  }

  Future<LibraryTrack?> getTrackByMusicId(String musicId) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'music_id = ?',
      whereArgs: [musicId],
      limit: 1,
    );
    if (rows.isNotEmpty) return LibraryTrack.fromMap(rows.first);
    final cueRows = await db.query(
      'cue_slices',
      where: 'music_id = ?',
      whereArgs: [musicId],
      limit: 1,
    );
    if (cueRows.isEmpty) return null;
    return _hydrateSlice(cueRows.first);
  }

  Future<LibraryTrack> _hydrateSlice(Map<String, dynamic> row) async {
    final db = await database;
    var map = Map<String, dynamic>.from(row);
    map['cue_track_index'] = row['track_index'] ?? row['cue_track_index'];
    if (map['cue_remote_path'] == null && row['cue_id'] != null) {
      final albums = await db.query(
        'cue_albums',
        where: 'cue_id = ?',
        whereArgs: [row['cue_id']],
        limit: 1,
      );
      if (albums.isNotEmpty) {
        map['cue_remote_path'] = albums.first['cue_remote_path'];
        map['cache_group_id'] ??= albums.first['cache_group_id'];
      }
    }
    return LibraryTrack.fromMap(map);
  }

  Future<List<LibraryTrack>> allTracks() async {
    final db = await database;
    final normal = await db.query(
      'tracks',
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    final slices = await db.query(
      'cue_slices',
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    final out = <LibraryTrack>[...normal.map(LibraryTrack.fromMap)];
    for (final s in slices) {
      out.add(await _hydrateSlice(s));
    }
    return out;
  }

  Future<List<LibraryTrack>> tracksForSource(String sourceName) async {
    final db = await database;
    final normal = await db.query(
      'tracks',
      where: 'source_name = ?',
      whereArgs: [sourceName],
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    final slices = await db.query(
      'cue_slices',
      where: 'source_name = ?',
      whereArgs: [sourceName],
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    final out = <LibraryTrack>[...normal.map(LibraryTrack.fromMap)];
    for (final s in slices) {
      out.add(await _hydrateSlice(s));
    }
    return out;
  }

  Future<List<LibraryTrack>> tracksByArtist(String artist) async {
    final all = await allTracks();
    return all.where((t) => t.displayArtist == artist).toList()
      ..sort(compareTracksByName);
  }

  Future<List<LibraryTrack>> tracksByAlbum(String album) async {
    final all = await allTracks();
    return all.where((t) => t.displayAlbum == album).toList()
      ..sort(compareTracksByAlbumOrder);
  }

  Future<List<String>> distinctArtists() async {
    final all = await allTracks();
    final set = all.map((t) => t.displayArtist).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return set;
  }

  Future<List<String>> distinctAlbums() async {
    final all = await allTracks();
    final set = all.map((t) => t.displayAlbum).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return set;
  }

  Future<int> trackCount() async {
    final db = await database;
    final a = await db.rawQuery('SELECT COUNT(*) AS c FROM tracks');
    final b = await db.rawQuery('SELECT COUNT(*) AS c FROM cue_slices');
    return (Sqflite.firstIntValue(a) ?? 0) + (Sqflite.firstIntValue(b) ?? 0);
  }

  Future<void> deleteTracksForSource(String sourceName) async {
    final db = await database;
    await db.delete(
      'cue_slices',
      where: 'source_name = ?',
      whereArgs: [sourceName],
    );
    await db.delete(
      'cue_albums',
      where: 'source_name = ?',
      whereArgs: [sourceName],
    );
    await db.delete(
      'tracks',
      where: 'source_name = ?',
      whereArgs: [sourceName],
    );
    // No cache-annex cleanup since v9: cache files are derived from
    // (source_name, remote_path), never keyed off library rows.
  }

  Future<void> deleteTrack(String sourceName, String remotePath) async {
    final db = await database;
    await db.delete(
      'tracks',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, remotePath],
    );
    await db.delete(
      'cue_slices',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, remotePath],
    );
    // No cache-annex cleanup since v9: whether the audio file survives is a
    // cache-side concern (deleteLocalFile), keyed by identity, not by rows.
  }

  /// Atomically replace one complete CUE album and remove any standalone rows
  /// for its CUE/audio files. Callers stage/read all metadata before entering.
  Future<void> replaceCueAlbumTracks({
    required String sourceName,
    required String cueRemotePath,
    required List<String> audioRemotePaths,
    required List<LibraryTrack> tracks,
  }) async {
    final db = await database;
    final cueId = cueIdFor(sourceName, cueRemotePath);
    final normalized = normalizeRemotePath(cueRemotePath);
    await db.transaction((txn) async {
      final albums = await txn.query(
        'cue_albums',
        columns: ['cue_id'],
        where: 'cue_id = ? OR (source_name = ? AND cue_remote_path = ?)',
        whereArgs: [cueId, sourceName, normalized],
      );
      final ids = <String>{cueId, ...albums.map((r) => r['cue_id'] as String)};
      for (final id in ids) {
        await txn.delete('cue_slices', where: 'cue_id = ?', whereArgs: [id]);
        await txn.delete('cue_albums', where: 'cue_id = ?', whereArgs: [id]);
      }

      final paths = <String>{cueRemotePath, ...audioRemotePaths};
      for (final path in paths) {
        await txn.delete(
          'tracks',
          where: 'source_name = ? AND remote_path = ?',
          whereArgs: [sourceName, path],
        );
        await txn.delete(
          'cue_slices',
          where: 'source_name = ? AND remote_path = ?',
          whereArgs: [sourceName, path],
        );
      }
      if (audioRemotePaths.isNotEmpty) {
        final placeholders = List.filled(
          audioRemotePaths.length,
          '?',
        ).join(', ');
        await txn.delete(
          'cue_slices',
          where:
              'source_name = ? AND (cue_remote_path = ? OR '
              'audio_remote_path IN ($placeholders) OR remote_path IN ($placeholders))',
          whereArgs: [
            sourceName,
            cueRemotePath,
            ...audioRemotePaths,
            ...audioRemotePaths,
          ],
        );
      }
      for (final track in tracks) {
        await _upsertCueSlice(txn, track);
      }
    });
  }

  /// Remove every library row belonging to a CUE album (virtual clips stay
  /// removable as a group; audio files are left to CacheService).
  Future<int> deleteTracksForCue(
    String sourceName,
    String cueRemotePath,
  ) async {
    final db = await database;
    final cueId = cueIdFor(sourceName, cueRemotePath);
    final normalized = normalizeRemotePath(cueRemotePath);
    // Resolve cue_id both by hash and by path lookup (legacy rows).
    final albums = await db.query(
      'cue_albums',
      columns: ['cue_id'],
      where: 'cue_id = ? OR (source_name = ? AND cue_remote_path = ?)',
      whereArgs: [cueId, sourceName, normalized],
    );
    final ids = <String>{cueId, ...albums.map((r) => r['cue_id'] as String)};
    var n = 0;
    for (final id in ids) {
      n += await db.delete('cue_slices', where: 'cue_id = ?', whereArgs: [id]);
      await db.delete('cue_albums', where: 'cue_id = ?', whereArgs: [id]);
    }
    return n;
  }

  // --- Bidirectional CUE relations ---

  /// Delete a **single** CUE slice row.
  ///
  /// 逐条墓碑必须配逐条删除：墓碑的 key 是那一片的虚拟路径，行也就只能一片一片地删。
  /// 整组一次性清空会让兄弟片拿不到墓碑，它们会被旧 base 从云端带回来。
  Future<int> deleteCueSlice(String sliceMusicId) async {
    final db = await database;
    return db.delete(
      'cue_slices',
      where: 'music_id = ?',
      whereArgs: [sliceMusicId],
    );
  }

  /// Drop a CUE album row (its slices are already gone).
  Future<void> deleteCueAlbum(String sourceName, String cueRemotePath) async {
    final db = await database;
    final cueId = cueIdFor(sourceName, cueRemotePath);
    final normalized = normalizeRemotePath(cueRemotePath);
    final albums = await db.query(
      'cue_albums',
      columns: ['cue_id'],
      where: 'cue_id = ? OR (source_name = ? AND cue_remote_path = ?)',
      whereArgs: [cueId, sourceName, normalized],
    );
    for (final id in <String>{
      cueId,
      ...albums.map((r) => r['cue_id'] as String),
    }) {
      await db.delete('cue_albums', where: 'cue_id = ?', whereArgs: [id]);
    }
  }

  /// How many slices a CUE album still has. 0 means the album can go too.
  Future<int> remainingSlicesForCue(
    String sourceName,
    String cueRemotePath,
  ) async {
    final db = await database;
    final cueId = cueIdFor(sourceName, cueRemotePath);
    final normalized = normalizeRemotePath(cueRemotePath);
    final albums = await db.query(
      'cue_albums',
      columns: ['cue_id'],
      where: 'cue_id = ? OR (source_name = ? AND cue_remote_path = ?)',
      whereArgs: [cueId, sourceName, normalized],
    );
    final ids = <String>{cueId, ...albums.map((r) => r['cue_id'] as String)};
    var n = 0;
    for (final id in ids) {
      n +=
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM cue_slices WHERE cue_id = ?',
              [id],
            ),
          ) ??
          0;
    }
    return n;
  }

  Future<Map<String, dynamic>?> cueAlbumForSlice(String sliceMusicId) async {
    final db = await database;
    final slices = await db.query(
      'cue_slices',
      where: 'music_id = ?',
      whereArgs: [sliceMusicId],
      limit: 1,
    );
    if (slices.isEmpty) return null;
    final cueId = slices.first['cue_id'] as String;
    final albums = await db.query(
      'cue_albums',
      where: 'cue_id = ?',
      whereArgs: [cueId],
      limit: 1,
    );
    if (albums.isEmpty) return null;
    return albums.first;
  }

  Future<List<LibraryTrack>> slicesForCue(String cueId) async {
    final db = await database;
    final rows = await db.query(
      'cue_slices',
      where: 'cue_id = ?',
      whereArgs: [cueId],
      orderBy: 'track_index ASC',
    );
    final out = <LibraryTrack>[];
    for (final r in rows) {
      out.add(await _hydrateSlice(r));
    }
    return out;
  }

  Future<List<String>> sliceMusicIdsForCue(String cueId) async {
    final db = await database;
    final rows = await db.query(
      'cue_slices',
      columns: ['music_id'],
      where: 'cue_id = ?',
      whereArgs: [cueId],
      orderBy: 'track_index ASC',
    );
    return rows.map((r) => r['music_id'] as String).toList();
  }

  Future<String?> audioMusicIdForCue(String cueId) async {
    final db = await database;
    final rows = await db.query(
      'cue_slices',
      columns: ['audio_music_id'],
      where: 'cue_id = ?',
      whereArgs: [cueId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['audio_music_id'] as String?;
  }

  Future<List<Map<String, dynamic>>> allCueAlbumsForSource(
    String sourceName,
  ) async {
    final db = await database;
    return db.query(
      'cue_albums',
      where: 'source_name = ?',
      whereArgs: [sourceName],
    );
  }

  /// Every CUE album row (all accounts) — used by whole-app backup/sync.
  Future<List<Map<String, dynamic>>> allCueAlbums() async {
    final db = await database;
    return db.query('cue_albums');
  }

  Future<List<LibraryTrack>> allCueSlicesForSource(String sourceName) async {
    final db = await database;
    final rows = await db.query(
      'cue_slices',
      where: 'source_name = ?',
      whereArgs: [sourceName],
    );
    final out = <LibraryTrack>[];
    for (final r in rows) {
      out.add(await _hydrateSlice(r));
    }
    return out;
  }

  // --- Cache groups (runtime CUE album membership) ---

  /// Member identities of a cache group, or empty when the group is unknown.
  Future<List<String>> cacheGroupMembers(String groupId) async {
    if (groupId.isEmpty) return const [];
    final db = await database;
    final rows = await db.query(
      'cache_groups',
      columns: ['members'],
      where: 'group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    return decodeCacheGroupMembers(rows.first['members'] as String?);
  }

  /// Add [identities] to a group, keeping existing members (idempotent).
  ///
  /// The membership row is keyed by the real group id, so two groups can no
  /// longer collide the way the legacy `hashCode`-keyed prefs entries could.
  Future<void> bindCacheGroupMembers({
    required String groupId,
    required Iterable<String> identities,
  }) async {
    if (groupId.isEmpty) return;
    final merged = (await cacheGroupMembers(groupId)).toSet();
    var added = false;
    for (final id in identities) {
      if (id.isEmpty) continue;
      if (merged.add(id)) added = true;
    }
    if (!added) return;
    final db = await database;
    await db.insert('cache_groups', {
      'group_id': groupId,
      'members': encodeCacheGroupMembers(merged),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Drop a group's membership row (the caller deletes its files separately).
  Future<void> deleteCacheGroup(String groupId) async {
    if (groupId.isEmpty) return;
    final db = await database;
    await db.delete(
      'cache_groups',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  }

  Future<List<Map<String, dynamic>>> allCacheGroups() async {
    final db = await database;
    return db.query('cache_groups');
  }

  // --- Cache access (runtime LRU timestamps) ---

  Future<void> touchCacheAccess({
    required String sourceName,
    required String remotePath,
  }) async {
    final db = await database;
    await db.insert('cache_access', {
      'source_name': sourceName,
      'remote_path': remotePath,
      'accessed_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> cacheAccessedAt(
    String sourceName,
    String remotePath,
  ) async {
    final db = await database;
    final rows = await db.query(
      'cache_access',
      columns: ['accessed_at'],
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, remotePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['accessed_at'] as String? ?? '');
  }

  Future<void> deleteCacheAccess({
    required String sourceName,
    required String remotePath,
  }) async {
    final db = await database;
    await db.delete(
      'cache_access',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, remotePath],
    );
  }

  /// Wipe all library-persisted rows: tracks, cue_albums, cue_slices, runtime
  /// cache groups / LRU timestamps, tombstones and sync cursors.
  /// Does **not** delete WebDAV accounts.
  Future<void> clearAllLibraryData() async {
    final db = await database;
    await db.delete('cache_access');
    await db.delete('cache_groups');
    await db.delete('cue_slices');
    await db.delete('cue_albums');
    await db.delete('tracks');
    await db.delete('deleted_tracks');
    await db.delete('sync_state');
    await db.delete('user_folder_items');
    await db.delete('user_folders');
    await db.delete('manga_pages');
    await db.delete('manga_progress');
    await db.delete('mangas');
    await db.delete('manga_series');
    await db.delete('deleted_mangas');
    await db.delete('local_meta');
  }

  /// Wipe the library **index** only: tracks, CUE tables, tombstones and the sync
  /// cursor. Runtime groups / LRU timestamps stay, and audio already on disk
  /// keeps resolving to local files through the deterministic cache path.
  ///
  /// Used by「从云端覆写音乐库」: the index is replaced, the files are not.
  Future<void> clearLibraryIndex() async {
    final db = await database;
    await db.delete('cue_slices');
    await db.delete('cue_albums');
    await db.delete('tracks');
    await db.delete('deleted_tracks');
    await clearSyncState(prefix: musicCursorPrefix);
  }

  /// Wipe the **manga** index only: series, mangas, pages, manga tombstones and
  /// the manga sync cursor. Reading progress and `manga_cache/` stay, so the
  /// rows pulled back resume where they were and keep their local files.
  ///
  /// Used by「从云端覆写漫画库」.
  Future<void> clearMangaIndex() async {
    final db = await database;
    await db.delete('manga_pages');
    await db.delete('mangas');
    await db.delete('manga_series');
    await db.delete('deleted_mangas');
    await clearSyncState(prefix: mangaCursorPrefix);
  }

  /// `sync_state.remote_key` prefixes, one per synced library kind.
  static const musicCursorPrefix = 'library:';
  static const mangaCursorPrefix = 'manga:';

  // --- Tombstones (deletions) ---

  /// Record (or bump) a tombstone for one path.
  Future<void> upsertTombstone({
    required String sourceName,
    required String remotePath,
    required int rev,
    DateTime? deletedAt,
  }) async {
    final db = await database;
    await db.insert('deleted_tracks', {
      'source_name': sourceName,
      'remote_path': normalizeRemotePath(remotePath),
      'rev': rev,
      'deleted_at': (deletedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'pushed': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Drop the tombstone for one path (a re-download resurrects the song).
  Future<void> clearTombstone(String sourceName, String remotePath) async {
    final db = await database;
    await db.delete(
      'deleted_tracks',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, normalizeRemotePath(remotePath)],
    );
  }

  Future<List<Map<String, dynamic>>> allTombstones() async {
    final db = await database;
    return db.query('deleted_tracks', orderBy: 'rev ASC');
  }

  Future<List<Map<String, dynamic>>> unpushedTombstones() async {
    final db = await database;
    return db.query('deleted_tracks', where: 'pushed = 0', orderBy: 'rev ASC');
  }

  Future<void> markTombstonesPushed(Iterable<int> revs) async {
    if (revs.isEmpty) return;
    final db = await database;
    for (final rev in revs) {
      await db.update(
        'deleted_tracks',
        {'pushed': 1},
        where: 'rev = ?',
        whereArgs: [rev],
      );
    }
  }

  /// Purge tombstones already materialised into a rebuilt base (`rev <= upTo`).
  Future<int> purgeTombstonesUpTo(int upTo) async {
    final db = await database;
    return db.delete('deleted_tracks', where: 'rev <= ?', whereArgs: [upTo]);
  }

  /// Song paths currently hidden by a tombstone (for the library UI + ingest).
  Future<Set<String>> tombstonedKeys(String sourceName) async {
    final db = await database;
    final rows = await db.query(
      'deleted_tracks',
      columns: ['remote_path'],
      where: 'source_name = ?',
      whereArgs: [sourceName],
    );
    return {
      for (final row in rows)
        trackIdentityKey(sourceName, row['remote_path'] as String),
    };
  }

  // --- Sync cursor ---

  Future<Map<String, dynamic>?> loadSyncState(String remoteKey) async {
    final db = await database;
    final rows = await db.query(
      'sync_state',
      where: 'remote_key = ?',
      whereArgs: [remoteKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveSyncState({
    required String remoteKey,
    required int lastSeq,
    required int baseUpTo,
    required String parts,
  }) async {
    final db = await database;
    await db.insert('sync_state', {
      'remote_key': remoteKey,
      'last_seq': lastSeq,
      'base_up_to': baseUpTo,
      'parts': parts,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Drop sync cursors; with [prefix] only that library kind's cursors.
  Future<void> clearSyncState({String? prefix}) async {
    final db = await database;
    if (prefix == null) {
      await db.delete('sync_state');
      return;
    }
    await db.delete(
      'sync_state',
      where: 'remote_key LIKE ?',
      whereArgs: ['$prefix%'],
    );
  }

  // --- Local meta (small key/value bookkeeping) ---

  Future<String?> loadMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'local_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> saveMeta(String key, String value) async {
    final db = await database;
    await db.insert('local_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Key of the last local user-folder change (ms since epoch, as text).
  static const foldersChangedAtKey = 'folders_changed_at';

  Future<void> _touchFolders() =>
      saveMeta(foldersChangedAtKey, '${DateTime.now().millisecondsSinceEpoch}');


  // --- User folders (local overlay, 99 §18) ---

  Future<List<UserFolder>> loadUserFolders() async {
    final db = await database;
    final rows = await db.query(
      'user_folders',
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return [for (final r in rows) UserFolder.fromMap(r)];
  }

  Future<List<UserFolderItem>> loadUserFolderItems({String? folderId}) async {
    final db = await database;
    final rows = folderId == null
        ? await db.query(
            'user_folder_items',
            orderBy: 'sort_order ASC, added_at ASC',
          )
        : await db.query(
            'user_folder_items',
            where: 'folder_id = ?',
            whereArgs: [folderId],
            orderBy: 'sort_order ASC, added_at ASC',
          );
    return [for (final r in rows) UserFolderItem.fromMap(r)];
  }

  Future<void> upsertUserFolder(UserFolder folder) async {
    final db = await database;
    await db.insert(
      'user_folders',
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _touchFolders();
  }

  Future<void> deleteUserFolder(String id) async {
    final db = await database;
    // Children first (FK CASCADE may be off if PRAGMA foreign_keys=0).
    final kids = await db.query(
      'user_folders',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    for (final kid in kids) {
      await deleteUserFolder(kid['id'] as String);
    }
    await db.delete(
      'user_folder_items',
      where: 'folder_id = ?',
      whereArgs: [id],
    );
    await db.delete('user_folders', where: 'id = ?', whereArgs: [id]);
    await _touchFolders();
  }

  Future<void> upsertUserFolderItem(UserFolderItem item) async {
    final db = await database;
    await db.insert(
      'user_folder_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _touchFolders();
  }

  Future<void> deleteUserFolderItem({
    required String folderId,
    required String refKind,
    required String refKey,
  }) async {
    final db = await database;
    await db.delete(
      'user_folder_items',
      where: 'folder_id = ? AND ref_kind = ? AND ref_key = ?',
      whereArgs: [folderId, refKind, refKey],
    );
    await _touchFolders();
  }

  /// Replace every folder + item with [folders] / [items] in one transaction.
  ///
  /// Used by the cloud folder pull and by backup restore. Does **not** touch
  /// [foldersChangedAtKey]: adopting a snapshot is not a local edit.
  Future<void> replaceUserFolders(
    List<UserFolder> folders,
    List<UserFolderItem> items,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('user_folder_items');
      await txn.delete('user_folders');
      for (final f in folders) {
        await txn.insert(
          'user_folders',
          f.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final i in items) {
        await txn.insert(
          'user_folder_items',
          i.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }


  // --- Manga library (99 §19) ---

  Future<List<MangaSeries>> loadMangaSeries() async {
    final db = await database;
    final rows = await db.query(
      'manga_series',
      orderBy: 'sort_title COLLATE NOCASE ASC, title COLLATE NOCASE ASC',
    );
    return [for (final r in rows) MangaSeries.fromMap(r)];
  }

  Future<void> upsertMangaSeries(MangaSeries series) async {
    final db = await database;
    await db.insert(
      'manga_series',
      series.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMangaSeries(String id) async {
    final db = await database;
    await db.update(
      'mangas',
      {'series_id': null},
      where: 'series_id = ?',
      whereArgs: [id],
    );
    await db.delete('manga_series', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Manga>> loadMangas({String? seriesId, String? author}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (seriesId != null) {
      where.add('series_id = ?');
      args.add(seriesId);
    }
    if (author != null) {
      where.add('author = ?');
      args.add(author);
    }
    final rows = await db.query(
      'mangas',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return [for (final r in rows) Manga.fromMap(r)];
  }

  Future<Manga?> loadMangaById(String id) async {
    final db = await database;
    final rows = await db.query(
      'mangas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Manga.fromMap(rows.first);
  }

  Future<Manga?> loadMangaByPath({
    required String sourceName,
    required String remotePath,
  }) async {
    final db = await database;
    final rows = await db.query(
      'mangas',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, normalizeRemotePath(remotePath)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Manga.fromMap(rows.first);
  }

  /// Source of new manga revs (the app's shared [RevClock]); falls back to the
  /// wall clock in tests that never attach one.
  int Function()? mangaRevSource;

  int _nextMangaRev() =>
      mangaRevSource?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// Write one manga row.
  ///
  /// A local write ([keepRev] false) stamps a fresh rev and clears any
  /// tombstone for the same path (re-adding after a delete resurrects it).
  /// Adopting a cloud row passes [keepRev] so its rev is stored verbatim.
  Future<Manga> upsertManga(Manga manga, {bool keepRev = false}) async {
    final db = await database;
    final row = keepRev ? manga : manga.copyWith(rev: _nextMangaRev());
    final map = Map<String, Object?>.from(row.toMap());
    map['remote_path'] = normalizeRemotePath(row.remotePath);
    await db.insert(
      'mangas',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (!keepRev) {
      await db.delete(
        'deleted_mangas',
        where: 'source_name = ? AND remote_path = ?',
        whereArgs: [row.sourceName, map['remote_path']],
      );
    }
    return row;
  }

  /// Delete one manga (pages + progress + row) and, unless [tombstone] is
  /// false, leave a tombstone so the deletion syncs.
  Future<void> deleteManga(String id, {bool tombstone = true}) async {
    final db = await database;
    if (tombstone) {
      final row = await loadMangaById(id);
      if (row != null) {
        await upsertMangaTombstone(
          sourceName: row.sourceName,
          remotePath: row.remotePath,
          rev: _nextMangaRev(),
        );
      }
    }
    await db.delete('manga_pages', where: 'manga_id = ?', whereArgs: [id]);
    await db.delete('manga_progress', where: 'manga_id = ?', whereArgs: [id]);
    await db.delete('mangas', where: 'id = ?', whereArgs: [id]);
  }

  // --- Manga tombstones (cloud sync) ---

  Future<void> upsertMangaTombstone({
    required String sourceName,
    required String remotePath,
    required int rev,
    DateTime? deletedAt,
  }) async {
    final db = await database;
    await db.insert('deleted_mangas', {
      'source_name': sourceName,
      'remote_path': normalizeRemotePath(remotePath),
      'rev': rev,
      'deleted_at': (deletedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'pushed': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearMangaTombstone(String sourceName, String remotePath) async {
    final db = await database;
    await db.delete(
      'deleted_mangas',
      where: 'source_name = ? AND remote_path = ?',
      whereArgs: [sourceName, normalizeRemotePath(remotePath)],
    );
  }

  Future<List<Map<String, dynamic>>> allMangaTombstones() async {
    final db = await database;
    return db.query('deleted_mangas', orderBy: 'rev ASC');
  }

  Future<List<Map<String, dynamic>>> unpushedMangaTombstones() async {
    final db = await database;
    return db.query('deleted_mangas', where: 'pushed = 0', orderBy: 'rev ASC');
  }

  Future<void> markMangaTombstonesPushed(Iterable<int> revs) async {
    if (revs.isEmpty) return;
    final db = await database;
    for (final rev in revs) {
      await db.update(
        'deleted_mangas',
        {'pushed': 1},
        where: 'rev = ?',
        whereArgs: [rev],
      );
    }
  }

  Future<int> purgeMangaTombstonesUpTo(int upTo) async {
    final db = await database;
    return db.delete('deleted_mangas', where: 'rev <= ?', whereArgs: [upTo]);
  }

  Future<List<MangaProgress>> allMangaProgress() async {
    final db = await database;
    final rows = await db.query('manga_progress');
    return [for (final r in rows) MangaProgress.fromMap(r)];
  }

  // --- Snapshots (backup archive + folder sync) ---

  /// Whole manga library as JSON-friendly maps (backup archive section).
  Future<Map<String, dynamic>> exportMangaSnapshot() async {
    final db = await database;
    return {
      'series': await db.query('manga_series'),
      'mangas': await db.query('mangas'),
      'progress': await db.query('manga_progress'),
      'tombstones': await db.query('deleted_mangas'),
    };
  }

  /// Replace the manga tables with a snapshot from [exportMangaSnapshot].
  Future<void> importMangaSnapshot(Map<String, dynamic> snap) async {
    final db = await database;
    List<Map<String, Object?>> rows(String key) => [
      for (final r in (snap[key] as List<dynamic>? ?? const []))
        if (r is Map) Map<String, Object?>.from(r),
    ];
    await db.transaction((txn) async {
      for (final t in [
        'manga_pages',
        'manga_progress',
        'mangas',
        'manga_series',
        'deleted_mangas',
      ]) {
        await txn.delete(t);
      }
      Future<void> put(String table, List<Map<String, Object?>> list) async {
        for (final r in list) {
          await txn.insert(
            table,
            r,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await put('manga_series', rows('series'));
      await put('mangas', rows('mangas'));
      await put('manga_progress', rows('progress'));
      await put('deleted_mangas', rows('tombstones'));
    });
  }

  /// Whole user-folder overlay as JSON-friendly maps.
  Future<Map<String, dynamic>> exportUserFoldersSnapshot() async {
    final folders = await loadUserFolders();
    final items = await loadUserFolderItems();
    return {
      'folders': [for (final f in folders) f.toMap()],
      'items': [for (final i in items) i.toMap()],
    };
  }

  Future<void> importUserFoldersSnapshot(Map<String, dynamic> snap) async {
    await replaceUserFolders(
      [
        for (final r in (snap['folders'] as List<dynamic>? ?? const []))
          if (r is Map) UserFolder.fromMap(Map<String, Object?>.from(r)),
      ],
      [
        for (final r in (snap['items'] as List<dynamic>? ?? const []))
          if (r is Map) UserFolderItem.fromMap(Map<String, Object?>.from(r)),
      ],
    );
  }

  Future<List<MangaPage>> loadMangaPages(String mangaId) async {
    final db = await database;
    final rows = await db.query(
      'manga_pages',
      where: 'manga_id = ?',
      whereArgs: [mangaId],
      orderBy: 'page_index ASC',
    );
    return [for (final r in rows) MangaPage.fromMap(r)];
  }

  /// Freeze the page list. Page order is a **local cache** (not synced, not
  /// in backups), so this never bumps the manga's rev.
  Future<void> replaceMangaPages(String mangaId, List<MangaPage> pages) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'manga_pages',
        where: 'manga_id = ?',
        whereArgs: [mangaId],
      );
      for (final page in pages) {
        await txn.insert('manga_pages', page.toMap());
      }
    });
  }

  Future<MangaProgress?> loadMangaProgress(String mangaId) async {
    final db = await database;
    final rows = await db.query(
      'manga_progress',
      where: 'manga_id = ?',
      whereArgs: [mangaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MangaProgress.fromMap(rows.first);
  }

  Future<void> upsertMangaProgress(MangaProgress progress) async {
    final db = await database;
    await db.insert(
      'manga_progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> loadMangaAuthors() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT author FROM mangas "
      "WHERE author IS NOT NULL AND TRIM(author) != '' "
      'ORDER BY author COLLATE NOCASE ASC',
    );
    return [
      for (final r in rows) (r['author'] as String?) ?? '',
    ].where((a) => a.isNotEmpty).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
