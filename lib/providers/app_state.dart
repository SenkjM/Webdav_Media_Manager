import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cache_policy.dart';
import '../models/download_task.dart';
import '../utils/track_identity.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/backup_service.dart';
import '../services/library_sync_service.dart';
import '../services/cache_service.dart';
import '../services/credential_vault_service.dart';
import '../services/download_queue_service.dart';
import '../services/library_database.dart';
import '../services/library_service.dart';
import '../services/music_audio_handler.dart';
import '../services/notification_permission_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/video_playback_service.dart';
import '../services/webdav_service.dart';

/// Root composition / lifecycle for the app.
class AppState extends ChangeNotifier {
  AppState({required MusicAudioHandler audioHandler}) {
    settings = SettingsService();
    webDav = WebDavService();
    notificationPermission = NotificationPermissionService();
    final db = LibraryDatabase();
    libraryDb = db;
    cache = CacheService(libraryDb: db);
    library = LibraryService(db: db);
    accounts = AccountsService(db: db);
    playlists = PlaylistService(webDav: webDav);
    backup = BackupService(
      libraryDb: db,
      library: library,
      accounts: accounts,
      settings: settings,
      playlists: playlists,
      webDav: webDav,
      cache: cache,
    );
    librarySync = LibrarySyncService(
      library: library,
      accounts: accounts,
      settings: settings,
      playlists: playlists,
      webDav: webDav,
    );
    credentials = CredentialVaultService(
      accounts: accounts,
      settings: settings,
      webDav: webDav,
    );
    sync = SyncService(
      accounts: accounts,
      settings: settings,
      webDav: webDav,
      vault: credentials,
      librarySync: librarySync,
      library: library,
      playlists: playlists,
      backup: backup,
    );
    downloads = DownloadQueueService(
      webDav: webDav,
      cache: cache,
      library: library,
    );
    player = AudioPlayerService(
      downloads: downloads,
      handler: audioHandler,
      notificationPermission: notificationPermission,
    );
    videoPlayback = VideoPlaybackService(handler: audioHandler);
  }

  late final SettingsService settings;
  late final WebDavService webDav;
  late final CacheService cache;
  late final LibraryDatabase libraryDb;
  late final LibraryService library;
  late final AccountsService accounts;
  late final PlaylistService playlists;
  late final BackupService backup;
  late final LibrarySyncService librarySync;
  late final CredentialVaultService credentials;
  late final SyncService sync;
  late final DownloadQueueService downloads;
  late final NotificationPermissionService notificationPermission;
  late final AudioPlayerService player;
  late final VideoPlaybackService videoPlayback;

  bool ready = false;
  String? initError;

  Future<void> init() async {
    try {
      await settings.init();
      _syncCoverThumbSize();
      await cache.init();
      await library.init();
      await accounts.init();
      playlists.configureSync(
        remotePath: settings.playlistRemotePath,
        enabled: settings.playlistSyncEnabled,
      );
      await playlists.init();
      downloads.attachLibrary(library);
      await downloads.init();
      await notificationPermission.refresh();
      await connectActiveAccount();
      unawaited(runCacheCleanup());
      // Pull remote playlists after connect (best-effort).
      unawaited(playlists.pullAndMergeFromWebDav());
      ready = true;
    } catch (e) {
      initError = e.toString();
      ready = true;
    }
    notifyListeners();
  }

  Future<void> connectActiveAccount() async {
    final account = accounts.activeAccount;
    if (account == null) {
      webDav.disconnect();
      return;
    }
    final pass = await accounts.passwordFor(account.id) ?? '';
    webDav.configure(
      accountId: account.id,
      url: account.url,
      username: account.username,
      password: pass,
    );
    playlists.configureSync(
      remotePath: settings.playlistRemotePath,
      enabled: settings.playlistSyncEnabled,
    );
  }

  Future<void> switchAccount(String accountId) async {
    await accounts.setActiveAccount(accountId);
    await connectActiveAccount();
    unawaited(playlists.pullAndMergeFromWebDav());
    notifyListeners();
  }

  Future<int> runCacheCleanup() {
    return cache.cleanupKnown(
      retention: settings.retention,
      customDuration: settings.customRetentionDuration,
      identityToLocal: downloads.completedIdentityToLocal,
      playingIdentityKey: player.currentAccountId != null &&
              player.currentRemotePath != null
          ? trackIdentityKey(
              player.currentAccountId!,
              player.currentRemotePath!,
            )
          : null,
      downloadingIdentityKeys: downloads.downloadingIdentityKeys,
    );
  }

  Future<int> manualClearCache() async {
    final protected = <String>{};
    for (final t in downloads.tasks) {
      if (t.status == DownloadStatus.active ||
          t.status == DownloadStatus.pending) {
        final f = cache.fileForRemote(t.remotePath, accountId: t.accountId);
        protected.add(f.path);
        protected.add('${f.path}.part');
      }
    }
    final removed = await cache.clearAll(
      playingRemotePath: player.currentRemotePath,
      playingAccountId: player.currentAccountId,
      playingLocalPath: player.current?.localPath,
      protectedLocalPaths: protected,
    );
    // Drop stale completed entries so CUE clips re-download cleanly and
    // clip trimming still applies from library DB metadata.
    await downloads.invalidateMissingCompleted();
    return removed;
  }

  Future<void> setRetention(CacheRetention r) async {
    await settings.setRetention(r);
    unawaited(runCacheCleanup());
  }

  Future<void> setCustomRetentionDuration(Duration d) async {
    await settings.setCustomRetentionDuration(d);
    if (settings.retention != CacheRetention.custom) {
      await settings.setRetention(CacheRetention.custom);
    }
    unawaited(runCacheCleanup());
  }


  void _syncCoverThumbSize() {
    library.covers.thumbSize = settings.coverThumbSizePx;
  }

  Future<void> setCoverThumbSize(int size) async {
    await settings.setCoverThumbSize(size);
    _syncCoverThumbSize();
  }

  /// Wipe music library tags, cue tables, covers, cache annex, and local audio
  /// for former library tracks. Distinct from [manualClearCache] (keeps tags).
  /// Network library / accounts untouched. Playlist shells kept; orphan track
  /// refs removed.
  Future<void> destroyMusicLibrary() async {
    final snapshot = List.of(library.tracks);
    final groupIds = <String>{};
    final audioKeys = <String>{}; // accountId\0remotePath

    for (final t in snapshot) {
      final audio = t.effectiveAudioRemotePath;
      audioKeys.add('${t.accountId}\u0000$audio');
      if (t.cueRemotePath != null && t.cueRemotePath!.isNotEmpty) {
        audioKeys.add('${t.accountId}\u0000${t.cueRemotePath}');
      }
      final gid = t.cacheGroupId;
      if (gid != null && gid.isNotEmpty) groupIds.add(gid);
    }

    // Delete CUE cache groups first (also clears member prefs).
    for (final gid in groupIds) {
      await cache.deleteCacheGroup(gid);
    }
    // Delete remaining library audio files.
    for (final key in audioKeys) {
      final parts = key.split('\u0000');
      if (parts.length < 2) continue;
      final accountId = parts[0];
      final remote = parts.sublist(1).join('\u0000');
      await cache.deleteLocalFile(accountId: accountId, remotePath: remote);
    }

    await library.destroyAll();
    await cache.markAllUncached();
    // After destroy, no library tracks remain — strip all playlist track refs.
    await playlists.removeEntriesNotIn(const <String>{});
    await downloads.invalidateMissingCompleted();
    notifyListeners();
  }

  @override
  void dispose() {
    videoPlayback.dispose();
    player.dispose();
    downloads.dispose();
    cache.dispose();
    webDav.dispose();
    library.dispose();
    accounts.dispose();
    playlists.dispose();
    backup.dispose();
    librarySync.dispose();
    credentials.dispose();
    sync.dispose();
    settings.dispose();
    notificationPermission.dispose();
    super.dispose();
  }
}
