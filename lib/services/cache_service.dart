import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cache_policy.dart';
import '../models/library_track.dart';
import '../utils/audio_extensions.dart';
import '../utils/l10n_host.dart';
import 'rust_core_service.dart';

/// Local file cache for downloaded music. Playback always uses these files.
/// Cleanup NEVER touches library DB tracks/cue tables or cover thumbs.
///
/// Since library schema v9 there is no cache annex: a cache file's location
/// is **derived** from (source_name, remote_path) via [fileForRemote], so
/// isLocal is a lazy `File.exists` on the derived path — no table, no
/// startup reconciliation, nothing to go stale.
///
/// The cache **index** (access times + CUE group membership) lives in Rust
/// (`wdmm_cache_cmd` / `wdmm_cache_query`, storage schema v17). This class owns
/// only the filesystem side: roots, derived paths, size accounting and the
/// actual unlink calls. Every index mutation/read goes through the FFI, so
/// there is exactly one authority and no Dart-side schema.
class CacheService extends ChangeNotifier {
  CacheService();

  Directory? _cacheDir;
  Directory? _mangaCacheDir;

  Future<void> init() async {
    final root = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(root.path, 'music_cache'));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    _mangaCacheDir = Directory(p.join(root.path, 'manga_cache'));
    if (!await _mangaCacheDir!.exists()) {
      await _mangaCacheDir!.create(recursive: true);
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

  /// Thin ensure helper: write manga thumb bytes only if the deterministic file
  /// is absent. Returns the file path on success, `null` if bytes are not
  /// available or the write fails.
  ///
  /// Does **not** write to the database; callers update [CoverState] after
  /// this returns a non-null path.
  ///
  /// [fetchBytes] is called at most once, only when the file is missing.
  Future<String?> ensureMangaCoverFile({
    required String mangaId,
    required Future<Uint8List?> Function() fetchBytes,
  }) async {
    final file = mangaCoverFile(mangaId);
    if (file.existsSync()) return file.path;
    // Ensure the covers sub-directory exists.
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    final bytes = await fetchBytes();
    if (bytes == null || bytes.isEmpty) return null;
    try {
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
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
        removed++;
      } catch (_) {}
    }
    if (removed > 0) notifyListeners();
    _forgetKind(CacheKind.manga);
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
      _deleteIndexRows([f.path]);
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
    final deleted = <String>[];
    if (await deleteLocalMangaFile(
      sourceName: sourceName,
      remotePath: remotePath,
    )) {
      deleted.add(
        mangaFileForRemote(remotePath, sourceName: sourceName).path,
      );
    }
    var removed = deleted.length;
    if (_mangaCacheDir != null) {
      final cover = mangaCoverFile(mangaId);
      for (final path in <String>[cover.path, '${cover.path}.part']) {
        final f = File(path);
        if (!await f.exists()) continue;
        try {
          await f.delete();
          deleted.add(path);
          removed++;
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
    if (deleted.isNotEmpty) _deleteIndexRows(deleted);
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
    final path = fileForRemote(remotePath, sourceName: sourceName).path;
    _cmd({
      'cmd': 'bind_group',
      'group_id': groupId,
      'paths': [path],
    });
  }

  /// Local absolute paths that belong to [groupId].
  ///
  /// Storage schema v17 keeps `(group_id, local path)` rows, so this is the
  /// authoritative membership — no identity string is reconstructed from the
  /// remote side.
  Future<List<String>> groupMemberIdentities(String groupId) async {
    final reply = _query({'q': 'group_paths', 'group_id': groupId});
    final paths = reply?['paths'];
    if (paths is! List) return const [];
    return [
      for (final path in paths)
        if (path is String && path.isNotEmpty) path,
    ];
  }

  Future<List<String>> groupMemberFileNames(String groupId) async {
    final paths = await groupMemberIdentities(groupId);
    return paths.map(p.basename).toList();
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
    final part = File('${f.path}.part');
    if (await part.exists()) {
      try {
        await part.delete();
      } catch (_) {}
    }
    if (removed) {
      _deleteIndexRows([f.path]);
      notifyListeners();
    }
    return removed;
  }

  Future<int> deleteCacheGroup(String groupId) async {
    var removed = 0;
    final paths = await groupMemberIdentities(groupId);
    for (final path in paths) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
          removed++;
        } catch (_) {}
      }
    }
    _cmd({'cmd': 'delete_group', 'group_id': groupId});
    if (removed > 0) notifyListeners();
    return removed;
  }

  Future<void> touch(String sourceName, String remotePath) async {
    await _indexTouch(
      fileForRemote(remotePath, sourceName: sourceName),
      CacheKind.music,
    );
  }

  Future<DateTime?> lastAccessed(String sourceName, String remotePath) async {
    if (_cacheDir != null) {
      final path = fileForRemote(remotePath, sourceName: sourceName).path;
      final indexed = await _indexAt(path, CacheKind.music);
      if (indexed != null) return indexed;
    }
    // Fall back to file mtime when the index has no record (pre-index files).
    try {
      final f = fileForRemote(remotePath, sourceName: sourceName);
      if (await f.exists()) return (await f.stat()).modified;
    } catch (_) {}
    return null;
  }

  // --- access-time index (Rust `wdmm_cache_*`) -----------------------------

  Map<String, dynamic>? _cmd(Map<String, dynamic> body) {
    try {
      return _decode(RustCoreService.cacheCmd(jsonEncode(body)));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _query(Map<String, dynamic> body) {
    try {
      return _decode(RustCoreService.cacheQuery(jsonEncode(body)));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded['ok'] == true ? decoded : null;
      }
    } catch (_) {}
    return null;
  }

  /// Index rows of [kind] (`{"q":"list"}` reply), newest access first order
  /// irrelevant — callers build a path→time map.
  List<Map<String, dynamic>> _entries(CacheKind kind) {
    final reply = _query({'q': 'list', 'kind': kind.storageKey});
    final entries = reply?['entries'];
    if (entries is! List) return const [];
    return [
      for (final entry in entries)
        if (entry is Map<String, dynamic>) entry,
    ];
  }

  Map<String, DateTime> _accessedTimes(CacheKind kind) {
    final out = <String, DateTime>{};
    for (final entry in _entries(kind)) {
      final path = entry['path'];
      final at = entry['accessed_at'];
      if (path is String && at is int) {
        out[path] = DateTime.fromMillisecondsSinceEpoch(at);
      }
    }
    return out;
  }

  Future<void> _indexPut(File f, CacheKind kind, {String? remotePath}) async {
    try {
      if (!await f.exists()) return;
      final size = await f.length();
      _cmd({
        'cmd': 'put',
        'kind': kind.storageKey,
        'path': f.path,
        'size': size,
        'remote_path': ?remotePath,
      });
    } catch (_) {}
  }

  Future<void> _indexTouch(File f, CacheKind kind) => _indexPut(f, kind);

  Future<DateTime?> _indexAt(String path, CacheKind kind) async {
    final entries = _entries(kind);
    for (final entry in entries) {
      if (entry['path'] == path) {
        final at = entry['accessed_at'];
        if (at is int) return DateTime.fromMillisecondsSinceEpoch(at);
      }
    }
    return null;
  }

  void _deleteIndexRows(Iterable<String> paths) {
    final list = [
      for (final path in paths)
        if (path.isNotEmpty) path,
    ];
    if (list.isEmpty) return;
    _cmd({'cmd': 'delete', 'paths': list});
  }

  void _forgetKind(CacheKind kind) {
    _cmd({'cmd': 'forget_kind', 'kind': kind.storageKey});
  }

  /// Last access for [f]: the index when it knows the file, else its mtime —
  /// which is precisely the pre-index behaviour.
  Future<DateTime> _accessTime(
    File f, {
    Map<String, DateTime>? index,
  }) async {
    final indexed = index?[f.path];
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
    await _indexTouch(
      mangaFileForRemote(remotePath, sourceName: sourceName),
      CacheKind.manga,
    );
  }

  /// Record that a manga cover thumb was read.
  Future<void> touchMangaCover(String mangaId) async {
    await _indexTouch(mangaCoverFile(mangaId), CacheKind.manga);
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

  /// Record a freshly written manga cover thumb and repaint listeners.
  Future<void> registerMangaCoverWritten(String mangaId) async {
    await _indexTouch(mangaCoverFile(mangaId), CacheKind.manga);
    notifyListeners();
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
    final index = _accessedTimes(kind);
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
            accessed: await _accessTime(entity, index: index),
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
    final deleted = <String>[];
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
        deleted.add(e.file.path);
        removed++;
      } catch (_) {}
    }
    if (deleted.isNotEmpty) _deleteIndexRows(deleted);
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Evict least-recently-used entries of [kind] until the evictable total is
  /// at or below [maxBytes]. `maxBytes <= 0` means unlimited.
  ///
  /// Rust owns the LRU order (`{"q":"lru"}` / the `evict` command); this side
  /// only unlinks the files it can see and then drops their index rows by local
  /// path. Those rows are exactly the ones the index still holds — the budget
  /// itself (`SettingsService.cacheBudgetMb`) stays a Dart decision.
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
    final deleted = <String>[];
    for (final e in candidates) {
      if (total <= maxBytes) break;
      try {
        await e.file.delete();
        deleted.add(e.file.path);
        total -= e.size;
        removed++;
      } catch (_) {}
    }
    if (deleted.isNotEmpty) _deleteIndexRows(deleted);
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Drop index rows for [kind] whose file is gone (lazy sweep).
  Future<void> pruneIndex(CacheKind kind) async {
    final doomed = <String>[];
    for (final entry in _entries(kind)) {
      final path = entry['path'];
      if (path is! String) continue;
      if (!File(path).existsSync()) doomed.add(path);
    }
    if (doomed.isNotEmpty) _deleteIndexRows(doomed);
  }

  Future<void> registerCompleted(
    String sourceName,
    String remotePath,
    String localPath, {
    String? cacheGroupId,
    String? musicId,
  }) async {
    final file = File(localPath);
    await _indexPut(file, CacheKind.music, remotePath: remotePath);
    if (cacheGroupId != null && cacheGroupId.isNotEmpty) {
      final groupId = cacheGroupId;
      _cmd({
        'cmd': 'bind_group',
        'group_id': groupId,
        'paths': [localPath],
      });
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
    _forgetKind(CacheKind.music);
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
    final index = _accessedTimes(CacheKind.music);
    var removed = 0;
    final deleted = <String>[];
    for (final entry in identityToLocal.entries) {
      final identity = entry.key;
      final local = entry.value;
      final file = File(local);
      if (!await file.exists()) continue;
      final isPlaying = playingIdentityKey == identity;
      final isDownloading = downloadingIdentityKeys.contains(identity);
      final accessed =
          index[local] ?? (await _accessTime(file, index: index));
      if (policy.shouldDelete(
        lastAccessed: accessed,
        now: clock,
        isCurrentlyPlaying: isPlaying,
        isDownloading: isDownloading,
      )) {
        try {
          await file.delete();
          deleted.add(local);
          removed++;
        } catch (_) {}
      }
    }
    if (deleted.isNotEmpty) _deleteIndexRows(deleted);
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
