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
import '../utils/track_identity.dart';
import 'library_database.dart';

/// Local file cache for downloaded music. Playback always uses these files.
/// Cleanup NEVER touches library DB tracks/cue tables or cover thumbs.
///
/// Since library schema v9 there is no cache annex: a cache file's location
/// is **derived** from (source_name, remote_path) via [fileForRemote], so
/// isLocal is a lazy `File.exists` on the derived path — no table, no
/// startup reconciliation, nothing to go stale.
class CacheService extends ChangeNotifier {
  CacheService({SharedPreferences? prefs, LibraryDatabase? libraryDb})
      : _prefs = prefs,
        _libraryDb = libraryDb;

  // Legacy prefs key prefixes moved to [cache_group_codec.dart]; only used here
  // for the one-time migration in [_migrateLegacyPrefs].

  SharedPreferences? _prefs;
  LibraryDatabase? _libraryDb;
  Directory? _cacheDir;

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
    if (removed) notifyListeners();
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
  }

  Future<DateTime?> lastAccessed(String sourceName, String remotePath) async {
    return _libraryDb?.cacheAccessedAt(sourceName, remotePath);
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
}
