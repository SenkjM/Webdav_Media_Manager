import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/library_track.dart';
import '../utils/audio_extensions.dart';
import '../utils/track_identity.dart';
import 'library_database.dart';

/// Local file cache for downloaded music. Playback always uses these files.
/// Cleanup NEVER touches library DB tracks/cue tables or cover thumbs.
///
/// Cache annex (`cache` table) maps music_id → localPath. [isLocal] requires
/// both a cache row and File.exists — stale rows are reconciled away.
class CacheService extends ChangeNotifier {
  CacheService({SharedPreferences? prefs, LibraryDatabase? libraryDb})
      : _prefs = prefs,
        _libraryDb = libraryDb;

  static const _kAccessPrefix = 'cache_access_';
  static const _kGroupPrefix = 'cache_group_';
  static const _kGroupMembersPrefix = 'cache_group_members_';

  SharedPreferences? _prefs;
  LibraryDatabase? _libraryDb;
  Directory? _cacheDir;

  /// In-memory annex: music_id → local_path (source of truth with DB).
  final Map<String, String> _annex = {};

  void attachLibraryDb(LibraryDatabase db) {
    _libraryDb = db;
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final root = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(root.path, 'music_cache'));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    await _reloadAnnexFromDb();
    await reconcileStaleAnnex();
  }

  Future<void> _reloadAnnexFromDb() async {
    _annex.clear();
    final db = _libraryDb;
    if (db == null) return;
    for (final e in await db.allCacheEntries()) {
      final id = e['music_id'] as String?;
      final path = e['local_path'] as String?;
      if (id != null && path != null && path.isNotEmpty) {
        _annex[id] = path;
      }
    }
  }

  Directory get cacheDir {
    final d = _cacheDir;
    if (d == null) throw StateError('CacheService 未初始化');
    return d;
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

  /// Drop annex rows whose files are gone.
  /// After backup restore: drop annex so nothing looks cached without files.
  Future<void> markAllUncached() async {
    _annex.clear();
    await _libraryDb?.clearAllCacheEntries();
    notifyListeners();
  }

    Future<int> reconcileStaleAnnex() async {
    final db = _libraryDb;
    if (db == null) return 0;
    final n = await db.reconcileStaleCacheEntries(
      fileExists: (path) => File(path).existsSync(),
    );
    // Drop stale from memory too.
    _annex.removeWhere((id, path) => !File(path).existsSync());
    if (n > 0) notifyListeners();
    return n;
  }

  /// Sync isLocal for a music_id via in-memory annex + file exists.
  bool isLocalForMusicId(String musicId) {
    final annexPath = _annex[musicId];
    if (annexPath == null || annexPath.isEmpty) return false;
    if (File(annexPath).existsSync()) return true;
    _annex.remove(musicId);
    unawaited(_libraryDb?.deleteCacheEntry(musicId) ?? Future<void>.value());
    return false;
  }

  /// Strict isLocal: annex row + file exists. Reconciles stale rows.
  Future<bool> isLocalAsync(String musicId) async {
    final path = _annex[musicId];
    if (path != null && File(path).existsSync()) return true;
    final db = _libraryDb;
    if (db == null) {
      _annex.remove(musicId);
      return false;
    }
    final entry = await db.getCacheEntry(musicId);
    if (entry == null) {
      _annex.remove(musicId);
      return false;
    }
    final dbPath = entry['local_path'] as String?;
    if (dbPath == null || dbPath.isEmpty || !File(dbPath).existsSync()) {
      _annex.remove(musicId);
      await db.deleteCacheEntry(musicId);
      notifyListeners();
      return false;
    }
    _annex[musicId] = dbPath;
    return true;
  }

  /// Library-track isLocal: annex row for [LibraryTrack.cacheMusicId] AND
  /// File(path).existsSync(). Stale annex (missing file) is cleared.
  bool isLocalTrack(LibraryTrack track) {
    final musicId = track.cacheMusicId;
    final annexPath = _annex[musicId];
    final audioRemote = track.effectiveAudioRemotePath;
    final file = fileForRemote(audioRemote, sourceName: track.sourceName);

    if (annexPath != null) {
      if (File(annexPath).existsSync()) return true;
      // Stale annex row.
      _annex.remove(musicId);
      unawaited(_libraryDb?.deleteCacheEntry(musicId) ?? Future.value());
      return false;
    }

    // No annex: not local even if a leftover file exists. Callers that finish
    // downloads must [registerCompleted] / [ensureAnnexForFile].
    // Exception: if the deterministic cache file exists, treat as local and
    // schedule annex repair so green dots recover after upgrade.
    if (file.existsSync()) {
      _annex[musicId] = file.path;
      unawaited(
        ensureAnnexForFile(musicId: musicId, localPath: file.path),
      );
      return true;
    }
    return false;
  }

  /// Pure policy helper for tests: annex path + file exists.
  static bool isLocalPolicy({
    required String? annexLocalPath,
    required bool fileExists,
  }) {
    if (annexLocalPath == null || annexLocalPath.isEmpty) return false;
    return fileExists;
  }

  /// Ensure annex matches an existing file (after download or reconcile).
  Future<void> ensureAnnexForFile({
    required String musicId,
    required String localPath,
    int? sizeBytes,
  }) async {
    if (!File(localPath).existsSync()) {
      _annex.remove(musicId);
      await _libraryDb?.deleteCacheEntry(musicId);
      return;
    }
    _annex[musicId] = localPath;
    final db = _libraryDb;
    if (db == null) return;
    await db.upsertCacheEntry(
      musicId: musicId,
      localPath: localPath,
      sizeBytes: sizeBytes ?? await File(localPath).length(),
    );
  }

  Future<bool> isCached(String remotePath, {required String sourceName}) async {
    final musicId = musicIdForRemote(sourceName, remotePath);
    final f = fileForRemote(remotePath, sourceName: sourceName);
    if (!await f.exists()) {
      await _libraryDb?.deleteCacheEntry(musicId);
      return false;
    }
    await ensureAnnexForFile(musicId: musicId, localPath: f.path);
    return true;
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
    final musicId = musicIdForRemote(sourceName, remotePath);
    if (await f.exists()) {
      await touch(sourceName, remotePath);
      await ensureAnnexForFile(musicId: musicId, localPath: f.path);
      return f.path;
    }
    await _libraryDb?.deleteCacheEntry(musicId);
    return null;
  }

  /// Resolve local path for a library track (CUE → audio file).
  Future<String?> localPathForTrack(LibraryTrack track) async {
    return localPathIfCached(
      track.effectiveAudioRemotePath,
      sourceName: track.sourceName,
    );
  }

  String _accessKey(String sourceName, String remotePath) =>
      '$_kAccessPrefix${trackIdentityKey(sourceName, remotePath).hashCode}';

  String _groupKey(String sourceName, String remotePath) =>
      '$_kGroupPrefix${trackIdentityKey(sourceName, remotePath).hashCode}';
  String _groupMembersKey(String groupId) =>
      '$_kGroupMembersPrefix${groupId.hashCode}';

  Future<void> bindCacheGroup({
    required String sourceName,
    required String remotePath,
    required String groupId,
  }) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_groupKey(sourceName, remotePath), groupId);
    final members = List<String>.from(groupMemberIdentities(groupId));
    final id = trackIdentityKey(sourceName, remotePath);
    if (!members.contains(id)) {
      members.add(id);
      await _prefs!.setString(_groupMembersKey(groupId), jsonEncode(members));
    }
  }

  String? cacheGroupIdFor(String sourceName, String remotePath) =>
      _prefs?.getString(_groupKey(sourceName, remotePath));

  List<String> groupMemberIdentities(String groupId) {
    final raw = _prefs?.getString(_groupMembersKey(groupId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  List<String> groupMemberFileNames(String groupId) =>
      groupMemberIdentities(groupId).map((id) {
        final parts = id.split('\u0000');
        final remote = parts.length > 1 ? parts.sublist(1).join('\u0000') : id;
        return p.basename(remote);
      }).toList();

  Future<bool> deleteLocalFile({
    required String sourceName,
    required String remotePath,
  }) async {
    final f = fileForRemote(remotePath, sourceName: sourceName);
    final musicId = musicIdForRemote(sourceName, remotePath);
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
    await _prefs?.remove(_accessKey(sourceName, remotePath));
    _annex.remove(musicId);
    await _libraryDb?.deleteCacheEntry(musicId);
    if (removed) notifyListeners();
    return removed;
  }

  Future<int> deleteCacheGroup(String groupId) async {
    var removed = 0;
    for (final identity in groupMemberIdentities(groupId)) {
      final parts = identity.split('\u0000');
      final sourceName = parts.isNotEmpty ? parts.first : '';
      final remote =
          parts.length > 1 ? parts.sublist(1).join('\u0000') : identity;
      if (await deleteLocalFile(sourceName: sourceName, remotePath: remote)) {
        removed++;
      }
      await _prefs?.remove(_groupKey(sourceName, remote));
    }
    await _prefs?.remove(_groupMembersKey(groupId));
    if (removed > 0) notifyListeners();
    return removed;
  }

  Future<void> touch(String sourceName, String remotePath) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _accessKey(sourceName, remotePath),
      DateTime.now().toIso8601String(),
    );
  }

  DateTime? lastAccessed(String sourceName, String remotePath) {
    final raw = _prefs?.getString(_accessKey(sourceName, remotePath));
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> registerCompleted(
    String sourceName,
    String remotePath,
    String localPath, {
    String? cacheGroupId,
    String? musicId,
  }) async {
    await touch(sourceName, remotePath);
    if (cacheGroupId != null && cacheGroupId.isNotEmpty) {
      await bindCacheGroup(
        sourceName: sourceName,
        remotePath: remotePath,
        groupId: cacheGroupId,
      );
    }
    final id = musicId ?? musicIdForRemote(sourceName, remotePath);
    await ensureAnnexForFile(musicId: id, localPath: localPath);
    notifyListeners();
  }

  /// Manual clear of all audio cache except playing / downloading.
  /// Does not delete library metadata or cover thumbs. Clears cache annex.
  Future<int> clearAll({
    String? playingRemotePath,
    String? playingSourceName,
    String? playingLocalPath,
    Set<String> protectedLocalPaths = const {},
  }) async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    final protected = <String>{...protectedLocalPaths};
    if (playingLocalPath != null) protected.add(playingLocalPath);
    String? protectedMusicId;
    if (playingRemotePath != null && playingSourceName != null) {
      final f = fileForRemote(playingRemotePath, sourceName: playingSourceName);
      protected.add(f.path);
      protected.add('${f.path}.part');
      protectedMusicId = musicIdForRemote(playingSourceName, playingRemotePath);
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
    // Clear annex except currently playing audio.
    final keepPath = protectedMusicId != null ? _annex[protectedMusicId] : null;
    final toRemove = _annex.keys
        .where((id) => id != protectedMusicId)
        .where((id) {
          final path = _annex[id];
          return path == null || !protected.contains(path);
        })
        .toList();
    for (final id in toRemove) {
      _annex.remove(id);
      await _libraryDb?.deleteCacheEntry(id);
    }
    if (protectedMusicId != null && keepPath != null) {
      _annex[protectedMusicId] = keepPath;
    }
    notifyListeners();
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
      final parts = identity.split('\u0000');
      final sourceName = parts.isNotEmpty ? parts.first : '';
      final remote =
          parts.length > 1 ? parts.sublist(1).join('\u0000') : identity;
      final accessed =
          lastAccessed(sourceName, remote) ?? (await file.stat()).modified;
      if (policy.shouldDelete(
        lastAccessed: accessed,
        now: clock,
        isCurrentlyPlaying: isPlaying,
        isDownloading: isDownloading,
      )) {
        try {
          await file.delete();
          await _prefs?.remove(_accessKey(sourceName, remote));
          await _libraryDb?.deleteCacheEntry(
            musicIdForRemote(sourceName, remote),
          );
          removed++;
        } catch (_) {}
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }
}

