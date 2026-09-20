import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../utils/audio_extensions.dart';
import '../utils/track_identity.dart';

/// Local file cache for downloaded music. Playback always uses these files.
/// Cleanup NEVER touches library DB or cover thumbs (separate directories).
class CacheService extends ChangeNotifier {
  CacheService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kAccessPrefix = 'cache_access_';
  static const _kGroupPrefix = 'cache_group_';
  static const _kGroupMembersPrefix = 'cache_group_members_';

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

  File fileForRemote(String remotePath, {required String accountId}) {
    final name = cacheFileNameForRemote(remotePath, accountId: accountId);
    return File(p.join(cacheDir.path, name));
  }

  Future<bool> isCached(String remotePath, {required String accountId}) async {
    final f = fileForRemote(remotePath, accountId: accountId);
    return f.exists();
  }

  /// Sync check whether the audio file is present in the local cache.
  bool hasLocalFile(String remotePath, {required String accountId}) {
    return fileForRemote(remotePath, accountId: accountId).existsSync();
  }

  Future<String?> localPathIfCached(
    String remotePath, {
    required String accountId,
  }) async {
    final f = fileForRemote(remotePath, accountId: accountId);
    if (await f.exists()) {
      await touch(accountId, remotePath);
      return f.path;
    }
    return null;
  }

  String _accessKey(String accountId, String remotePath) =>
      '$_kAccessPrefix${trackIdentityKey(accountId, remotePath).hashCode}';


  String _groupKey(String accountId, String remotePath) =>
      '$_kGroupPrefix${trackIdentityKey(accountId, remotePath).hashCode}';
  String _groupMembersKey(String groupId) => '$_kGroupMembersPrefix${groupId.hashCode}';
  Future<void> bindCacheGroup({required String accountId, required String remotePath, required String groupId}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_groupKey(accountId, remotePath), groupId);
    final members = List<String>.from(groupMemberIdentities(groupId));
    final id = trackIdentityKey(accountId, remotePath);
    if (!members.contains(id)) {
      members.add(id);
      await _prefs!.setString(_groupMembersKey(groupId), jsonEncode(members));
    }
  }
  String? cacheGroupIdFor(String accountId, String remotePath) => _prefs?.getString(_groupKey(accountId, remotePath));
  List<String> groupMemberIdentities(String groupId) {
    final raw = _prefs?.getString(_groupMembersKey(groupId));
    if (raw == null || raw.isEmpty) return const [];
    try { return (jsonDecode(raw) as List).map((e) => e.toString()).toList(); } catch (_) { return const []; }
  }
  List<String> groupMemberFileNames(String groupId) => groupMemberIdentities(groupId).map((id) {
    final parts = id.split('\u0000');
    final remote = parts.length > 1 ? parts.sublist(1).join('\u0000') : id;
    return p.basename(remote);
  }).toList();
  Future<bool> deleteLocalFile({required String accountId, required String remotePath}) async {
    final f = fileForRemote(remotePath, accountId: accountId);
    var removed = false;
    if (await f.exists()) { try { await f.delete(); removed = true; } catch (_) {} }
    final part = File('${f.path}.part');
    if (await part.exists()) { try { await part.delete(); } catch (_) {} }
    await _prefs?.remove(_accessKey(accountId, remotePath));
    if (removed) notifyListeners();
    return removed;
  }
  Future<int> deleteCacheGroup(String groupId) async {
    var removed = 0;
    for (final identity in groupMemberIdentities(groupId)) {
      final parts = identity.split('\u0000');
      final accountId = parts.isNotEmpty ? parts.first : '';
      final remote = parts.length > 1 ? parts.sublist(1).join('\u0000') : identity;
      if (await deleteLocalFile(accountId: accountId, remotePath: remote)) removed++;
      await _prefs?.remove(_groupKey(accountId, remote));
    }
    await _prefs?.remove(_groupMembersKey(groupId));
    if (removed > 0) notifyListeners();
    return removed;
  }
  Future<void> touch(String accountId, String remotePath) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _accessKey(accountId, remotePath),
      DateTime.now().toIso8601String(),
    );
  }

  DateTime? lastAccessed(String accountId, String remotePath) {
    final raw = _prefs?.getString(_accessKey(accountId, remotePath));
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> registerCompleted(
    String accountId,
    String remotePath,
    String localPath, {
    String? cacheGroupId,
  }) async {
    await touch(accountId, remotePath);
    if (cacheGroupId != null && cacheGroupId.isNotEmpty) {
      await bindCacheGroup(accountId: accountId, remotePath: remotePath, groupId: cacheGroupId);
    }
    notifyListeners();
  }

  /// Manual clear of all audio cache except playing / downloading.
  /// Does not delete library metadata or cover thumbs.
  Future<int> clearAll({
    String? playingRemotePath,
    String? playingAccountId,
    String? playingLocalPath,
    Set<String> protectedLocalPaths = const {},
  }) async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    final protected = <String>{...protectedLocalPaths};
    if (playingLocalPath != null) protected.add(playingLocalPath);
    if (playingRemotePath != null && playingAccountId != null) {
      final f = fileForRemote(playingRemotePath, accountId: playingAccountId);
      protected.add(f.path);
      protected.add('${f.path}.part');
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

  /// Cleanup using known remote→local mapping from download tasks.
  /// Only deletes audio cache files — never library DB or covers/.
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
      // Parse accountId\0remotePath
      final parts = identity.split('\u0000');
      final accountId = parts.isNotEmpty ? parts.first : '';
      final remote = parts.length > 1 ? parts.sublist(1).join('\u0000') : identity;
      final accessed =
          lastAccessed(accountId, remote) ?? (await file.stat()).modified;
      if (policy.shouldDelete(
        lastAccessed: accessed,
        now: clock,
        isCurrentlyPlaying: isPlaying,
        isDownloading: isDownloading,
      )) {
        try {
          await file.delete();
          await _prefs?.remove(_accessKey(accountId, remote));
          removed++;
        } catch (_) {}
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }
}
