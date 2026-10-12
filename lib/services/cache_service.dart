import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/library_track.dart';
import '../utils/audio_extensions.dart';
import '../utils/cache_group_codec.dart';
import '../utils/l10n_host.dart';
import '../utils/track_identity.dart';
import 'cache_index_db.dart';
import 'library_database.dart';

/// Local file cache for downloaded music. Playback always uses these files.
/// Cleanup NEVER touches library DB tracks/cue tables or cover thumbs.
///
/// Since library schema v9 there is no cache annex: a cache file's location
/// is **derived** from (source_name, remote_path) via [fileForRemote], so
/// isLocal is a lazy `File.exists` on the derived path — no table, no
/// startup reconciliation, nothing to go stale.
class CacheService extends ChangeNotifier {
  CacheService({
    SharedPreferences? prefs,
    LibraryDatabase? libraryDb,
    CacheIndexDb? indexDb,
  }) : _prefs = prefs,
       _libraryDb = libraryDb,
       _index = indexDb;

  // Legacy prefs key prefixes moved to [cache_group_codec.dart]; only used here
  // for the one-time migration in [_migrateLegacyPrefs].

  SharedPreferences? _prefs;
  LibraryDatabase? _libraryDb;
  CacheIndexDb? _index;
  Directory? _cacheDir;
  Directory? _mangaCacheDir;

  void attachLibraryDb(LibraryDatabase db) {
    _libraryDb = db;
  }

  /// Attach the access-time index. Optional on purpose: every path below
  /// keeps working without it, falling back to file mtime.
  void attachIndexDb(CacheIndexDb index) {
    _index = index;
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final root = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(root.path, 'music_cache'));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    _mangaCacheDir = Directory(p.join(root.path, 'manga_cache'));
    if (!await _mangaCacheDir!.exists()) {
      await _mangaCacheDir!.create(recursive: true);
    }
    await _migrateLegacyPrefs();
  }

  /// One-time move of the legacy prefs group membership into
  /// `music_library.db` (`cache_groups`), then drop the old keys.
  ///
  /// The legacy `cache_group_*` keys are `String.hashCode`-suffixed: the
  /// member lists (stored in the value) are recoverable, but the per-path LRU
  /// `cache_access_*` timestamps are not — those keys are simply removed and
  /// expiry falls back to file mtime (the existing behaviour when no timestamp
  /// is recorded).
  Future<void> _migrateLegacyPrefs() async {
    final prefs = _prefs;
    final db = _libraryDb;
    if (prefs == null || db == null) return;

    final keys = prefs.getKeys();
    final entries = <String, String>{};
    for (final k in keys) {
      // Legacy preferences may contain bool/int values under keys that share
      // the cache prefix. Only string values are cache-group payloads.
      final v = prefs.get(k);
      if (v is String) entries[k] = v;
    }

    final groups = parseLegacyCacheGroups(entries);
    for (final g in groups) {
      await db.bindCacheGroupMembers(groupId: g.groupId, identities: g.members);
    }

    for (final k in keys) {
      if (k.startsWith(legacyCacheGroupKeyPrefix) ||
          k.startsWith(legacyCacheAccessKeyPrefix)) {
        await prefs.remove(k);
      }
    }
  }

  Directory get cacheDir {
    final d = _cacheDir;
    if (d == null) throw StateError(L10nHost.current.svcCacheNotInitialized);
    return d;
  }

  Directory get mangaCacheDir {
    final d = _mangaCacheDir;
    if (d == null) throw StateError(L10nHost.current.svcCacheNotInitialized);
    return d;
  }

  /// Local CBZ / page archive under manga_cache (identity-derived name).
  File mangaFileForRemote(String remotePath, {required String sourceName}) {
    final name = cacheFileNameForRemote(remotePath, sourceName: sourceName);
    return File(p.join(mangaCacheDir.path, name));
  }

  bool hasLocalMangaFile(String remotePath, {required String sourceName}) {
    return mangaFileForRemote(remotePath, sourceName: sourceName).existsSync();
  }

  /// Cover thumb for a manga id under manga_cache/covers/.
  File mangaCoverFile(String mangaId) {
    final stem = mangaId.length >= 16 ? mangaId.substring(0, 16) : mangaId;
    return File(p.join(mangaCacheDir.path, 'covers', '$stem.jpg'));
  }

  /// Everything the manga library keeps on disk: the whole-file archives and
  /// cover thumbs under `manga_cache/`, plus the reader's page images.
  Future<int> mangaCacheSizeBytes() => cacheSizeFor(CacheKind.manga);

  /// Combined music + manga cache size for the shared settings UI.
  Future<int> totalMediaCacheSizeBytes() async {
    return (await cacheSizeBytes()) + (await mangaCacheSizeBytes());
  }

  Future<int> clearAllMangaCache() async {
    final doomed = <File>[];
    for (final root in await _cacheRoots(CacheKind.manga)) {
      if (!await root.dir.exists()) continue;
      await for (final entity in root.dir.list(recursive: root.recursive)) {
        if (entity is File) doomed.add(entity);
      }
    }
    var removed = 0;
    for (final file in doomed) {
      try {
        await file.delete();
        await _index?.forget(file.path);
        removed++;
      } catch (_) {}
    }
    if (removed > 0) notifyListeners();
    await _index?.forgetKind(CacheKind.manga);
    return removed;
  }

  Future<bool> deleteLocalMangaFile({
    required String sourceName,
    required String remotePath,
  }) async {
    final f = mangaFileForRemote(remotePath, sourceName: sourceName);
    var removed = false;
    if (await f.exists()) {
      try {
        await f.delete();
        removed = true;
      } catch (_) {}
    }
    final part = File('${f.path}.part');
    if (await part.exists()) {
      try {
        await part.delete();
      } catch (_) {}
    }
    if (removed) {
      await _index?.forget(f.path);
      notifyListeners();
    }
    return removed;
  }

  /// Deletes every cached artifact belonging to one manga: the whole-file
  /// archive, its cover thumbnail and the page images prefetched for the
  /// reader. Used by the library clear-cache action, which must not touch the
  /// library rows themselves.
  Future<int> clearMangaArtifacts({
    required String mangaId,
    required String sourceName,
    required String remotePath,
  }) async {
    var removed = 0;
    if (await deleteLocalMangaFile(
      sourceName: sourceName,
      remotePath: remotePath,
    )) {
      removed++;
    }
    if (_mangaCacheDir != null) {
      final cover = mangaCoverFile(mangaId);
      for (final path in <String>[cover.path, '${cover.path}.part']) {
        final f = File(path);
        if (!await f.exists()) continue;
        try {
          await f.delete();
          removed++;
          await _index?.forget(path);
        } catch (_) {}
      }
    }
    final pages = await mangaPageDir(mangaId);
    if (await pages.exists()) {
      try {
        await for (final entity in pages.list()) {
          if (entity is File) removed++;
        }
        await pages.delete(recursive: true);
      } catch (_) {}
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Prefetched page images the reader keeps under the app cache directory.
  /// Mirrors MangaReaderPrep._mangaPageDir so a manual cache clear can drop
  /// them without reaching into that service.
  Future<Directory> mangaPageDir(String mangaId) async {
    final cache = await getApplicationCacheDirectory();
    return Directory(
      p.join(cache.path, 'prefetch_cache', 'manga_pages', mangaId),
    );
  }

  Future<int> evictMangaToMaxBytes({required int maxBytes}) {
    return evictCacheToMaxBytes(kind: CacheKind.manga, maxBytes: maxBytes);
  }

  File fileForRemote(String remotePath, {required String sourceName}) {
    final name = cacheFileNameForRemote(remotePath, sourceName: sourceName);
    return File(p.join(cacheDir.path, name));
  }

  File fileForMusicId(String musicId, String remotePath) {
    // Keep filename basename for readability; stem is stable music_id prefix.
    final base = sanitizeFileName(p.basename(remotePath));
    final stem = musicId.length >= 16 ? musicId.substring(0, 16) : musicId;
    return File(p.join(cacheDir.path, '${stem}_$base'));
  }

  /// No-op since v9: with no annex there is nothing to mark. Kept for the
  /// backup-restore call site (files must exist on disk to be considered
  /// cached, which the derived path already guarantees).
  Future<void> markAllUncached() async {}

  /// Sync isLocal for a music_id via the derived cache path.
  /// The caller must know the remote path — identity, not the hash, names
  /// the file (stem is only the first 16 hex of music_id).
  bool isLocalForMusicId(String musicId, String remotePath) {
    return fileForMusicId(musicId, remotePath).existsSync();
  }

  /// Library-track isLocal: derived cache file for the track's audio exists.
  bool isLocalTrack(LibraryTrack track) {
    return fileForRemote(
      track.effectiveAudioRemotePath,
      sourceName: track.sourceName,
    ).existsSync();
  }

  /// Pure policy helper for tests: derived file exists.
  static bool isLocalPolicy({required bool fileExists}) {
    return fileExists;
  }

  Future<bool> isCached(String remotePath, {required String sourceName}) async {
    return fileForRemote(remotePath, sourceName: sourceName).exists();
  }

  /// Sync check whether the audio file is present in the local cache.
  bool hasLocalFile(String remotePath, {required String sourceName}) {
    return fileForRemote(remotePath, sourceName: sourceName).existsSync();
  }

  Future<String?> localPathIfCached(
    String remotePath, {
    required String sourceName,
  }) async {
    final f = fileForRemote(remotePath, sourceName: sourceName);
    if (await f.exists()) {
      await touch(sourceName, remotePath);
      return f.path;
    }
    return null;
  }

  /// Resolve local path for a library track (CUE → audio file).
  Future<String?> localPathForTrack(LibraryTrack track) async {
    return localPathIfCached(
      track.effectiveAudioRemotePath,
      sourceName: track.sourceName,
    );
  }

  Future<void> bindCacheGroup({
    required String sourceName,
    required String remotePath,
    required String groupId,
  }) async {
    if (groupId.isEmpty) return;
    final db = _libraryDb;
    if (db == null) return;
    await db.bindCacheGroupMembers(
      groupId: groupId,
      identities: [trackIdentityKey(sourceName, remotePath)],
    );
  }

  Future<List<String>> groupMemberIdentities(String groupId) async {
    final db = _libraryDb;
    if (db == null) return const [];
    return db.cacheGroupMembers(groupId);
  }

  Future<List<String>> groupMemberFileNames(String groupId) async {
    final ids = await groupMemberIdentities(groupId);
    return ids
        .map((id) => splitCacheIdentity(id)?.remotePath ?? id)
        .map(p.basename)
        .toList();
  }

  Future<bool> deleteLocalFile({
    required String sourceName,
    required String remotePath,
  }) async {
    final f = fileForRemote(remotePath, sourceName: sourceName);
    var removed = false;
    if (await f.exists()) {
      try {
        await f.delete();
        removed = true;
      } catch (_) {}
    }
    final part = File('$f.part');
    if (await part.exists()) {
      try {
        await part.delete();
      } catch (_) {}
    }
    await _libraryDb?.deleteCacheAccess(
      sourceName: sourceName,
      remotePath: remotePath,
    );
    if (removed) {
      await _index?.forget(f.path);
      notifyListeners();
    }
    return removed;
  }

  Future<int> deleteCacheGroup(String groupId) async {
    var removed = 0;
    final identities = await groupMemberIdentities(groupId);
    for (final identity in identities) {
      final parts = splitCacheIdentity(identity);
      if (parts == null) continue;
      if (await deleteLocalFile(
        sourceName: parts.sourceName,
        remotePath: parts.remotePath,
      )) {
        removed++;
      }
    }
    await _libraryDb?.deleteCacheGroup(groupId);
    if (removed > 0) notifyListeners();
    return removed;
  }

  Future<void> touch(String sourceName, String remotePath) async {
    await _libraryDb?.touchCacheAccess(
      sourceName: sourceName,
      remotePath: remotePath,
    );
    await _indexTouchRead(
      fileForRemote(remotePath, sourceName: sourceName).path,
      CacheKind.music,
    );
  }

  Future<DateTime?> lastAccessed(String sourceName, String remotePath) async {
    if (_cacheDir != null) {
      final indexed = await _indexAt(
        fileForRemote(remotePath, sourceName: sourceName).path,
      );
      if (indexed != null) return indexed;
    }
    return _libraryDb?.cacheAccessedAt(sourceName, remotePath);
  }

  // --- access-time index ---------------------------------------------------

  Future<void> _indexTouch(File f, CacheKind kind) async {
    final idx = _index;
    if (idx == null) return;
    try {
      if (!await f.exists()) return;
      await idx.touch(f.path, kind: kind, size: await f.length());
    } catch (_) {}
  }

  Future<void> _indexTouchRead(String path, CacheKind kind) async {
    await _index?.touchRead(path, kind: kind);
  }

  Future<DateTime?> _indexAt(String path) async {
    final idx = _index;
    if (idx == null) return null;
    try {
      return await idx.accessedAt(path);
    } catch (_) {
      return null;
    }
  }

  /// Last access for [f]: the index when it knows the file, else its mtime —
  /// which is precisely the pre-index behaviour.
  Future<DateTime> _accessTime(File f) async {
    final indexed = await _indexAt(f.path);
    if (indexed != null) return indexed;
    try {
      return (await f.stat()).modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Record that a cached manga archive was read (reader / cache-hit path).
  Future<void> touchMangaFile(
    String remotePath, {
    required String sourceName,
  }) async {
    await _indexTouchRead(
      mangaFileForRemote(remotePath, sourceName: sourceName).path,
      CacheKind.manga,
    );
  }

  /// Record that a manga cover thumb was read.
  Future<void> touchMangaCover(String mangaId) async {
    await _indexTouchRead(mangaCoverFile(mangaId).path, CacheKind.manga);
  }

  /// Record a freshly written manga archive together with its size.
  Future<void> registerMangaFileWritten(
    String remotePath, {
    required String sourceName,
  }) async {
    await _indexTouch(
      mangaFileForRemote(remotePath, sourceName: sourceName),
      CacheKind.manga,
    );
    notifyListeners();
  }

  /// Record a freshly written manga cover thumb.
  Future<void> registerMangaCoverWritten(String mangaId) async {
    await _indexTouch(mangaCoverFile(mangaId), CacheKind.manga);
  }

  // --- unified cleanup -----------------------------------------------------

  bool _isMangaCoverPath(String path) {
    final dir = _mangaCacheDir;
    if (dir == null) return false;
    return p.split(p.relative(path, from: dir.path)).first == 'covers';
  }

  /// Every directory that belongs to the cache of [kind].
  ///
  /// Music is one flat directory. The manga library has two roots: archives
  /// and cover thumbs under `manga_cache/`, and the page images the reader
  /// materialises under `prefetch_cache/manga_pages/`. Both are manga cache —
  /// counting only the first would hide the largest part of the footprint.
  Future<List<({Directory dir, bool recursive})>> _cacheRoots(
    CacheKind kind,
  ) async {
    final out = <({Directory dir, bool recursive})>[];
    if (kind == CacheKind.music) {
      final dir = _cacheDir;
      if (dir != null) out.add((dir: dir, recursive: false));
      return out;
    }
    final dir = _mangaCacheDir;
    if (dir != null) out.add((dir: dir, recursive: true));
    out.add((dir: await _mangaPageRoot(), recursive: true));
    return out;
  }

  /// `<appCache>/prefetch_cache/manga_pages`; mirrors
  /// `MangaReaderPrep._mangaPageDir`.
  Future<Directory> _mangaPageRoot() async {
    final cache = await getApplicationCacheDirectory();
    return Directory(p.join(cache.path, 'prefetch_cache', 'manga_pages'));
  }

  /// Files a cleanup pass may consider for [kind].
  ///
  /// Cover thumbs are excluded on purpose: they are tiny, and they are the
  /// one cache entry the UI cannot regenerate by itself (it only reads them).
  /// So neither expiry nor the size cap removes them; [clearAllMangaCache] —
  /// the explicit button — still does.
  Future<List<({File file, int size, DateTime accessed})>> _cacheCandidates(
    CacheKind kind,
  ) async {
    final out = <({File file, int size, DateTime accessed})>[];
    for (final root in await _cacheRoots(kind)) {
      if (!await root.dir.exists()) continue;
      await for (final entity in root.dir.list(recursive: root.recursive)) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.part')) continue;
        if (kind == CacheKind.manga && _isMangaCoverPath(entity.path)) {
          continue;
        }
        try {
          out.add((
            file: entity,
            size: await entity.length(),
            accessed: await _accessTime(entity),
          ));
        } catch (_) {}
      }
    }
    return out;
  }

  /// Delete entries of [kind] last accessed longer ago than [policy] allows.
  Future<int> cleanupExpired({
    required CacheKind kind,
    required CacheExpiryPolicy policy,
    Set<String> protectedPaths = const {},
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    var removed = 0;
    for (final e in await _cacheCandidates(kind)) {
      if (protectedPaths.contains(e.file.path)) continue;
      final expired = policy.shouldDelete(
        lastAccessed: e.accessed,
        now: clock,
        isCurrentlyPlaying: false,
        isDownloading: false,
      );
      if (!expired) continue;
      try {
        await e.file.delete();
        await _index?.forget(e.file.path);
        removed++;
      } catch (_) {}
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Evict least-recently-used entries of [kind] until the evictable total is
  /// at or below [maxBytes]. `maxBytes <= 0` means unlimited.
  Future<int> evictCacheToMaxBytes({
    required CacheKind kind,
    required int maxBytes,
    Set<String> protectedPaths = const {},
  }) async {
    if (maxBytes <= 0) return 0;
    final candidates = (await _cacheCandidates(kind))
        .where((e) => !protectedPaths.contains(e.file.path))
        .toList();
    var total = 0;
    for (final e in candidates) {
      total += e.size;
    }
    if (total <= maxBytes) return 0;
    candidates.sort((a, b) => a.accessed.compareTo(b.accessed));
    var removed = 0;
    for (final e in candidates) {
      if (total <= maxBytes) break;
      try {
        await e.file.delete();
        await _index?.forget(e.file.path);
        total -= e.size;
        removed++;
      } catch (_) {}
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Drop index rows for [kind] whose file is gone (lazy sweep).
  Future<void> pruneIndex(CacheKind kind) async {
    final idx = _index;
    if (idx == null) return;
    try {
      final known = await idx.entries(kind);
      await idx.pruneMissing(known.keys);
    } catch (_) {}
  }

  Future<void> registerCompleted(
    String sourceName,
    String remotePath,
    String localPath, {
    String? cacheGroupId,
    String? musicId,
  }) async {
    await touch(sourceName, remotePath);
    await _indexTouch(File(localPath), CacheKind.music);
    if (cacheGroupId != null && cacheGroupId.isNotEmpty) {
      await bindCacheGroup(
        sourceName: sourceName,
        remotePath: remotePath,
        groupId: cacheGroupId,
      );
    }
    notifyListeners();
  }

  /// Manual clear of all audio cache except playing / downloading.
  /// Does not delete library metadata or cover thumbs.
  Future<int> clearAll({
    String? playingRemotePath,
    String? playingSourceName,
    String? playingLocalPath,
    Set<String> protectedLocalPaths = const {},
  }) async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    final protected = <String>{...protectedLocalPaths};
    if (playingLocalPath != null) protected.add(playingLocalPath);
    if (playingRemotePath != null && playingSourceName != null) {
      final f = fileForRemote(playingRemotePath, sourceName: playingSourceName);
      protected.add(f.path);
      protected.add('$f.part');
    }
    var removed = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is! File) continue;
      if (protected.contains(entity.path)) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {}
    }
    if (removed > 0) notifyListeners();
    await _index?.forgetKind(CacheKind.music);
    return removed;
  }

  Future<int> cacheSizeBytes() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    var total = 0;
    await for (final entity in _cacheDir!.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Cleanup using known remote→local mapping from download tasks.
  /// Only deletes audio cache files — never library DB tracks or covers/.
  Future<int> cleanupKnown({
    required CacheRetention retention,
    Duration? customDuration,
    required Map<String, String> identityToLocal,
    String? playingIdentityKey,
    Set<String> downloadingIdentityKeys = const {},
    DateTime? now,
  }) async {
    final policy = CacheExpiryPolicy(
      retention: retention,
      customDuration: customDuration,
    );
    final clock = now ?? DateTime.now();
    var removed = 0;
    for (final entry in identityToLocal.entries) {
      final identity = entry.key;
      final local = entry.value;
      final file = File(local);
      if (!await file.exists()) continue;
      final isPlaying = playingIdentityKey == identity;
      final isDownloading = downloadingIdentityKeys.contains(identity);
      final parts = splitCacheIdentity(identity);
      if (parts == null) continue;
      final sourceName = parts.sourceName;
      final remote = parts.remotePath;
      final accessed =
          await lastAccessed(sourceName, remote) ??
          (await file.stat()).modified;
      if (policy.shouldDelete(
        lastAccessed: accessed,
        now: clock,
        isCurrentlyPlaying: isPlaying,
        isDownloading: isDownloading,
      )) {
        try {
          await file.delete();
          await _libraryDb?.deleteCacheAccess(
            sourceName: sourceName,
            remotePath: remote,
          );
          removed++;
        } catch (_) {}
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// True when [path] lives under the music_cache directory (not prefetch_cache).
  bool isMusicCachePath(String path) {
    final dir = _cacheDir;
    if (dir == null) return false;
    final root = p.normalize(dir.path);
    final normalized = p.normalize(path);
    return normalized == root || p.isWithin(root, normalized);
  }

  /// Drop least-recently-used music_cache files until total size <= [maxBytes].
  /// Skips [protectedLocalPaths] and the currently playing file.
  Future<int> evictToMaxBytes({
    required int maxBytes,
    String? playingLocalPath,
    String? playingRemotePath,
    String? playingSourceName,
    Set<String> protectedLocalPaths = const {},
  }) async {
    if (maxBytes <= 0) return 0;
    final protected = <String>{...protectedLocalPaths};
    if (playingLocalPath != null) protected.add(playingLocalPath);
    if (playingRemotePath != null && playingSourceName != null) {
      final f = fileForRemote(playingRemotePath, sourceName: playingSourceName);
      protected.add(f.path);
      protected.add('${f.path}.part');
    }
    return evictCacheToMaxBytes(
      kind: CacheKind.music,
      maxBytes: maxBytes,
      protectedPaths: protected,
    );
  }

  /// Total size of one cache in bytes (covers and reader pages included).
  Future<int> cacheSizeFor(CacheKind kind) async {
    var total = 0;
    for (final root in await _cacheRoots(kind)) {
      if (!await root.dir.exists()) continue;
      await for (final entity in root.dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }
}
