import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import '../utils/cache_group_codec.dart';
import '../utils/track_identity.dart';

/// SQLite persistence for multi-WebDAV accounts and the local music library.
/// Separate from audio file cache — survives cache cleanup.
///
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

  /// Current schema. Wipe/rebuild on upgrade (migration cost ignored).
  static const schemaVersion = 9;

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
        // Wipe the **library** tables and rebuild — no migration branches by
        // design. Accounts are deliberately kept: they carry the disk names that
        // every library row is bound to, and they are not part of this schema.
        for (final table in [
          'cache',
          'cache_access',
          'cache_groups',
          'cue_slices',
          'cue_albums',
          'tracks',
          'deleted_tracks',
          'sync_state',
        ]) {
          await db.execute('DROP TABLE IF EXISTS $table');
        }
        await _createSchema(db);
        // 云盘 provider（99 §7 阶段 0）：accounts 老表不重建（保留库名绑定），
        // 逐列补齐新列；新库由 _createSchema 直接带全列。
        await _ensureAccountColumns(db);
      },
    );
    return _db!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  username TEXT NOT NULL,
  provider_type TEXT NOT NULL DEFAULT 'webdav',
  remote_path TEXT NOT NULL DEFAULT '/',
  capabilities INTEGER NOT NULL DEFAULT 127
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
    await _createIndexes(db);
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
    final cols = (await db.rawQuery('PRAGMA table_info(accounts)'))
        .map((row) => row['name'] as String)
        .toSet();
    if (!cols.contains('provider_type')) {
      await db.execute(
          "ALTER TABLE accounts ADD COLUMN provider_type TEXT NOT NULL DEFAULT 'webdav'");
    }
    if (!cols.contains('remote_path')) {
      await db.execute(
          "ALTER TABLE accounts ADD COLUMN remote_path TEXT NOT NULL DEFAULT '/'");
    }
    if (!cols.contains('capabilities')) {
      await db.execute(
          'ALTER TABLE accounts ADD COLUMN capabilities INTEGER NOT NULL DEFAULT 127');
    }
    // 旧默认 63（六位掩码）→ 当前全量 127：能力勾选 UI 上线前不存在自定义值，
    // 全量替换安全（99 §7.2.3 的 mkdir 拆位）。
    await db.execute(
        'UPDATE accounts SET capabilities = 127 WHERE capabilities = 63');
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
    final cuePath = track.cueRemotePath;
    if (cuePath == null || cuePath.isEmpty) {
      throw StateError('cue_slices require cue_remote_path');
    }
    final cueId = track.cueId ?? cueIdFor(track.sourceName, cuePath);
    await db.insert(
      'cue_albums',
      {
        'cue_id': cueId,
        'source_name': track.sourceName,
        'cue_remote_path': normalizeRemotePath(cuePath),
        'title': track.album,
        'performer': track.albumArtist ?? track.artist,
        'cache_group_id': track.cacheGroupId,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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
      audioMusicId: track.audioMusicId ??
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
    final out = <LibraryTrack>[
      ...normal.map(LibraryTrack.fromMap),
    ];
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
    await db.delete('cue_slices', where: 'source_name = ?', whereArgs: [sourceName]);
    await db.delete('cue_albums', where: 'source_name = ?', whereArgs: [sourceName]);
    await db.delete('tracks', where: 'source_name = ?', whereArgs: [sourceName]);
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

  /// Remove every library row belonging to a CUE album (virtual clips stay
  /// removable as a group; audio files are left to CacheService).
  Future<int> deleteTracksForCue(String sourceName, String cueRemotePath) async {
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
    return db.delete('cue_slices', where: 'music_id = ?', whereArgs: [sliceMusicId]);
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
    for (final id in <String>{cueId, ...albums.map((r) => r['cue_id'] as String)}) {
      await db.delete('cue_albums', where: 'cue_id = ?', whereArgs: [id]);
    }
  }

  /// How many slices a CUE album still has. 0 means the album can go too.
  Future<int> remainingSlicesForCue(String sourceName, String cueRemotePath) async {
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
      n += Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM cue_slices WHERE cue_id = ?',
            [id],
          )) ??
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
    await db.delete('cache_groups', where: 'group_id = ?', whereArgs: [groupId]);
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
    await db.delete('sync_state');
  }

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
    return db.query(
      'deleted_tracks',
      where: 'pushed = 0',
      orderBy: 'rev ASC',
    );
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
    return db.delete(
      'deleted_tracks',
      where: 'rev <= ?',
      whereArgs: [upTo],
    );
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

  Future<void> clearSyncState() async {
    final db = await database;
    await db.delete('sync_state');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
