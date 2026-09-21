import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import '../utils/track_identity.dart';

/// SQLite persistence for multi-WebDAV accounts and the local music library.
/// Separate from audio file cache — survives cache cleanup.
///
/// Schema v5:
/// - `accounts` — site (stable accountId; display name separate)
/// - `tracks` — music_id PK, library identity (survives cache clear)
/// - `cue_albums` / `cue_slices` — CUE identity + clips stay in library
/// - `cache` — annex: music_id → localPath (reconcile against disk)
class LibraryDatabase {
  Database? _db;

  /// Current schema. Wipe/rebuild on upgrade (migration cost ignored).
  static const schemaVersion = 5;

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
        // Wipe and rebuild — user approved schema bump without migration.
        await db.execute('DROP TABLE IF EXISTS cache');
        await db.execute('DROP TABLE IF EXISTS cue_slices');
        await db.execute('DROP TABLE IF EXISTS cue_albums');
        await db.execute('DROP TABLE IF EXISTS tracks');
        await db.execute('DROP TABLE IF EXISTS accounts');
        await _createSchema(db);
      },
    );
    return _db!;
  }

  Future<void> _createSchema(Database db) async {
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
  music_id TEXT PRIMARY KEY,
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
  last_downloaded_at TEXT NOT NULL,
  last_tag_read_at TEXT NOT NULL,
  UNIQUE(account_id, remote_path)
)
''');
    await db.execute('''
CREATE TABLE cue_albums (
  cue_id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  cue_remote_path TEXT NOT NULL,
  title TEXT,
  performer TEXT,
  cache_group_id TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(account_id, cue_remote_path)
)
''');
    await db.execute('''
CREATE TABLE cue_slices (
  music_id TEXT PRIMARY KEY,
  cue_id TEXT NOT NULL,
  audio_music_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
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
  last_downloaded_at TEXT NOT NULL,
  last_tag_read_at TEXT NOT NULL,
  UNIQUE(account_id, remote_path)
)
''');
    await db.execute('''
CREATE TABLE cache (
  music_id TEXT PRIMARY KEY,
  local_path TEXT NOT NULL,
  size_bytes INTEGER,
  etag TEXT,
  cached_at TEXT NOT NULL
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
      'CREATE INDEX IF NOT EXISTS idx_tracks_account ON tracks(account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cue_slices_cue ON cue_slices(cue_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cue_slices_audio ON cue_slices(audio_music_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cue_albums_account ON cue_albums(account_id)',
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
    final cueId = track.cueId ?? cueIdFor(track.accountId, cuePath);
    await db.insert(
      'cue_albums',
      {
        'cue_id': cueId,
        'account_id': track.accountId,
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
      accountId: track.accountId,
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
              ? musicIdForRemote(track.accountId, track.audioRemotePath!)
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

  Future<LibraryTrack?> getTrack(String accountId, String remotePath) async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      where: 'account_id = ? AND remote_path = ?',
      whereArgs: [accountId, remotePath],
      limit: 1,
    );
    if (rows.isNotEmpty) return LibraryTrack.fromMap(rows.first);

    final cueRows = await db.query(
      'cue_slices',
      where: 'account_id = ? AND remote_path = ?',
      whereArgs: [accountId, remotePath],
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

  Future<List<LibraryTrack>> tracksForAccount(String accountId) async {
    final db = await database;
    final normal = await db.query(
      'tracks',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    final slices = await db.query(
      'cue_slices',
      where: 'account_id = ?',
      whereArgs: [accountId],
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

  Future<void> deleteTracksForAccount(String accountId) async {
    final db = await database;
    // Collect audio music_ids for cache cleanup of this account's library.
    final slices = await db.query(
      'cue_slices',
      columns: ['audio_music_id'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final trackIds = await db.query(
      'tracks',
      columns: ['music_id'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    await db.delete('cue_slices', where: 'account_id = ?', whereArgs: [accountId]);
    await db.delete('cue_albums', where: 'account_id = ?', whereArgs: [accountId]);
    await db.delete('tracks', where: 'account_id = ?', whereArgs: [accountId]);
    for (final r in [...slices, ...trackIds]) {
      final id = (r['audio_music_id'] ?? r['music_id']) as String?;
      if (id != null) {
        await db.delete('cache', where: 'music_id = ?', whereArgs: [id]);
      }
    }
  }

  Future<void> deleteTrack(String accountId, String remotePath) async {
    final db = await database;
    final existing = await getTrack(accountId, remotePath);
    await db.delete(
      'tracks',
      where: 'account_id = ? AND remote_path = ?',
      whereArgs: [accountId, remotePath],
    );
    await db.delete(
      'cue_slices',
      where: 'account_id = ? AND remote_path = ?',
      whereArgs: [accountId, remotePath],
    );
    // Do not drop cache annex if cue_slices still use this music_id as audio.
    // ingestCueAlbum deletes standalone audio rows after writing slices; wiping
    // annex there made virtual tracks look uncached despite files on disk.
    if (existing != null && !existing.isCueVirtual) {
      final stillUsed = await db.query(
        'cue_slices',
        columns: ['music_id'],
        where: 'audio_music_id = ?',
        whereArgs: [existing.musicId],
        limit: 1,
      );
      if (stillUsed.isEmpty) {
        await db.delete(
          'cache',
          where: 'music_id = ?',
          whereArgs: [existing.musicId],
        );
      }
    }
  }

  /// Remove every library row belonging to a CUE album (virtual clips stay
  /// removable as a group; cache annex for audio is left to CacheService).
  Future<int> deleteTracksForCue(String accountId, String cueRemotePath) async {
    final db = await database;
    final cueId = cueIdFor(accountId, cueRemotePath);
    final normalized = normalizeRemotePath(cueRemotePath);
    // Resolve cue_id both by hash and by path lookup (legacy rows).
    final albums = await db.query(
      'cue_albums',
      columns: ['cue_id'],
      where: 'cue_id = ? OR (account_id = ? AND cue_remote_path = ?)',
      whereArgs: [cueId, accountId, normalized],
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

  Future<List<Map<String, dynamic>>> allCueAlbumsForAccount(
    String accountId,
  ) async {
    final db = await database;
    return db.query(
      'cue_albums',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  /// Every CUE album row (all accounts) — used by whole-app backup/sync.
  Future<List<Map<String, dynamic>>> allCueAlbums() async {
    final db = await database;
    return db.query('cue_albums');
  }

  Future<List<LibraryTrack>> allCueSlicesForAccount(String accountId) async {
    final db = await database;
    final rows = await db.query(
      'cue_slices',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final out = <LibraryTrack>[];
    for (final r in rows) {
      out.add(await _hydrateSlice(r));
    }
    return out;
  }

  // --- Cache annex ---

  Future<void> upsertCacheEntry({
    required String musicId,
    required String localPath,
    int? sizeBytes,
    String? etag,
  }) async {
    final db = await database;
    await db.insert(
      'cache',
      {
        'music_id': musicId,
        'local_path': localPath,
        'size_bytes': sizeBytes,
        'etag': etag,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCacheEntry(String musicId) async {
    final db = await database;
    final rows = await db.query(
      'cache',
      where: 'music_id = ?',
      whereArgs: [musicId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> deleteCacheEntry(String musicId) async {
    final db = await database;
    await db.delete('cache', where: 'music_id = ?', whereArgs: [musicId]);
  }

  Future<void> clearAllCacheEntries() async {
    final db = await database;
    await db.delete('cache');
  }

  Future<List<Map<String, dynamic>>> allCacheEntries() async {
    final db = await database;
    return db.query('cache');
  }

  /// Drop cache rows whose local_path is missing on disk.
  Future<int> reconcileStaleCacheEntries({
    required bool Function(String localPath) fileExists,
  }) async {
    final entries = await allCacheEntries();
    var removed = 0;
    for (final e in entries) {
      final path = e['local_path'] as String?;
      final id = e['music_id'] as String?;
      if (id == null) continue;
      if (path == null || path.isEmpty || !fileExists(path)) {
        await deleteCacheEntry(id);
        removed++;
      }
    }
    return removed;
  }


  /// Wipe all library-persisted rows: tracks, cue_albums, cue_slices, cache annex.
  /// Does **not** delete WebDAV accounts.
  Future<void> clearAllLibraryData() async {
    final db = await database;
    await db.delete('cache');
    await db.delete('cue_slices');
    await db.delete('cue_albums');
    await db.delete('tracks');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
