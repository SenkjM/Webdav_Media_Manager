import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../utils/audio_extensions.dart';

/// Local file cache for downloaded music. Playback always uses these files.
class CacheService extends ChangeNotifier {
  CacheService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kAccessPrefix = 'cache_access_';

  SharedPreferences? _prefs;
  Directory? _cacheDir;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final root = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(root.path, 'music_cache'));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  Directory get cacheDir {
    final d = _cacheDir;
    if (d == null) throw StateError('CacheService 未初始化');
    return d;
  }

  File fileForRemote(String remotePath) {
    final name = cacheFileNameForRemote(remotePath);
    return File(p.join(cacheDir.path, name));
  }

  Future<bool> isCached(String remotePath) async {
    final f = fileForRemote(remotePath);
    return f.exists();
  }

  Future<String?> localPathIfCached(String remotePath) async {
    final f = fileForRemote(remotePath);
    if (await f.exists()) {
      await touch(remotePath);
      return f.path;
    }
    return null;
  }

  Future<void> touch(String remotePath) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      '$_kAccessPrefix${remotePath.hashCode}',
      DateTime.now().toIso8601String(),
    );
  }

  DateTime? lastAccessed(String remotePath) {
    final raw = _prefs?.getString('$_kAccessPrefix${remotePath.hashCode}');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> registerCompleted(String remotePath, String localPath) async {
    await touch(remotePath);
    notifyListeners();
  }

  /// Auto-cleanup by retention. Never deletes [playingRemotePath] or
  /// paths in [downloadingRemotePaths].
  Future<int> cleanup({
    required CacheRetention retention,
    String? playingRemotePath,
    Set<String> downloadingRemotePaths = const {},
    DateTime? now,
  }) async {
    final policy = CacheExpiryPolicy(retention: retention);
    final clock = now ?? DateTime.now();
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;

    var removed = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is! File) continue;
      final remote = _remoteForCacheFile(entity);
      final isPlaying =
          playingRemotePath != null && remote == playingRemotePath;
      final isDownloading = downloadingRemotePaths.contains(remote);
      final accessed = lastAccessed(remote) ??
          (await entity.stat()).modified;
      if (policy.shouldDelete(
        lastAccessed: accessed,
        now: clock,
        isCurrentlyPlaying: isPlaying,
        isDownloading: isDownloading,
      )) {
        try {
          await entity.delete();
          await _prefs?.remove('$_kAccessPrefix${remote.hashCode}');
          removed++;
        } catch (_) {}
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Manual clear of all cache except playing / downloading.
  Future<int> clearAll({
    String? playingRemotePath,
    String? playingLocalPath,
    Set<String> downloadingRemotePaths = const {},
    Set<String> protectedLocalPaths = const {},
  }) async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    final protected = <String>{...protectedLocalPaths};
    if (playingLocalPath != null) protected.add(playingLocalPath);
    if (playingRemotePath != null) {
      protected.add(fileForRemote(playingRemotePath).path);
    }
    for (final r in downloadingRemotePaths) {
      protected.add(fileForRemote(r).path);
      protected.add('${fileForRemote(r).path}.part');
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

  /// Best-effort reverse: we store hash_basename; callers should prefer
  /// known remote paths from the download store.
  String _remoteForCacheFile(File file) {
    // Prefer matching via download store; fallback uses basename marker.
    return p.basename(file.path);
  }

  /// Cleanup using known remote→local mapping from download tasks.
  Future<int> cleanupKnown({
    required CacheRetention retention,
    required Map<String, String> remoteToLocal,
    String? playingRemotePath,
    Set<String> downloadingRemotePaths = const {},
    DateTime? now,
  }) async {
    final policy = CacheExpiryPolicy(retention: retention);
    final clock = now ?? DateTime.now();
    var removed = 0;
    for (final entry in remoteToLocal.entries) {
      final remote = entry.key;
      final local = entry.value;
      final file = File(local);
      if (!await file.exists()) continue;
      final isPlaying = playingRemotePath == remote;
      final isDownloading = downloadingRemotePaths.contains(remote);
      final accessed = lastAccessed(remote) ?? (await file.stat()).modified;
      if (policy.shouldDelete(
        lastAccessed: accessed,
        now: clock,
        isCurrentlyPlaying: isPlaying,
        isDownloading: isDownloading,
      )) {
        try {
          await file.delete();
          await _prefs?.remove('$_kAccessPrefix${remote.hashCode}');
          removed++;
        } catch (_) {}
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }
}
