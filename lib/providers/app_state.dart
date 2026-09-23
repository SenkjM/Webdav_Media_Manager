import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cache_policy.dart';
import '../models/download_task.dart';
import '../models/file_type_config.dart';
import '../models/sync_interval.dart';
import '../utils/app_snack.dart';
import '../utils/track_identity.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/backup_service.dart';
import '../services/cache_service.dart';
import '../services/credential_vault_service.dart';
import '../services/download_queue_service.dart';
import '../services/library_database.dart';
import '../services/library_service.dart';
import '../utils/rev_clock.dart';
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
      library: library,
      playlists: playlists,
      backup: backup,
    );
    downloads = DownloadQueueService(
      webDav: webDav,
      cache: cache,
      library: library,
      // The network library classifies entries with the configured extension
      // sets, so the queue must use the same list (never a hard-coded one).
      isMusicFile: (name) =>
          settings.fileTypes.categoryFor(name) == FileCategory.music,
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
      AppSnack.attach(settings);
      _syncCoverThumbSize();
      _syncDownloadFileTypes();
      await cache.init();
      // The rev clock is the single version source sync compares; it starts from
      // the persisted high-water mark and reports every advance back.
      library.attachRevClock(
        RevClock(
          nowMs: () => DateTime.now().millisecondsSinceEpoch,
          initial: settings.lastRev,
          onAdvance: settings.setLastRev,
        ),
      );
      await library.init();
      await accounts.init();
      await registerAllAccounts();
      // The queue persists 网盘名, never an account id: it has to resolve one to
      // the other **after** the account list is loaded, or every transfer would
      // be judged "来源网盘未绑定".
      downloads.configureAccountResolver(accounts.idForSource);
      applySyncConfiguration();
      await playlists.init();
      downloads.attachLibrary(library);
      // Incremental library sync: whenever a download (or a restore) changes
      // the local library, push just the new rows to the cloud index.
      library.addListener(_onLibraryChanged);
      // Changing 定时同步 in Settings must take effect immediately, not on the
      // next launch.
      settings.addListener(_onSettingsChanged);
      await downloads.init();
      // Download notifications: create the channel and honour the setting.
      downloads.notificationsEnabled = settings.downloadNotificationsEnabled;
      downloads.notificationService.enabled =
          settings.downloadNotificationsEnabled;
      unawaited(downloads.initNotifications());
      await notificationPermission.refresh();
      unawaited(runCacheCleanup());
      // Startup scan: credentials + playlists both ways (best-effort, never
      // blocks the first frame).
      unawaited(sync.autoScan());
      _schedulePeriodicSync();
      ready = true;
    } catch (e) {
      initError = e.toString();
      ready = true;
    }
    notifyListeners();
  }

  /// Register **every** configured account with [WebDavService].
  ///
  /// This is what makes the music library independent of the network library's
  /// selection: a track row carries its own `accountId`, and its client stays
  /// available no matter which account the user is browsing.
  Future<void> registerAllAccounts() async {
    for (final a in accounts.accounts) {
      final pass = await accounts.passwordFor(a.id) ?? '';
      webDav.configure(
        accountId: a.id,
        url: a.url,
        username: a.username,
        password: pass,
        makeActive: false,
      );
    }
    // Drop clients for accounts that no longer exist.
    final live = accounts.accounts.map((a) => a.id).toSet();
    for (final id in webDav.registeredAccountIds) {
      if (!live.contains(id)) webDav.disconnect(accountId: id);
    }
    webDav.setActiveAccount(accounts.activeAccountId ?? '');
  }

  /// (Re)point playlist sync at the unified 远端路径 + 网盘.
  ///
  /// Called on boot, on account switch, and whenever the 远端路径 栏 in
  /// 设置 → 同步与备份 changes ([_onSettingsChanged] notices that for us).
  void applySyncConfiguration() {
    _appliedSyncRoot = settings.syncRemoteRoot;
    _appliedSyncAccountId = settings.syncAccountId;
    playlists.configureSync(
      remotePath: settings.playlistRemotePath,
      enabled: settings.playlistSyncEnabled,
      accountId: settings.syncAccountId ?? accounts.activeAccountId,
    );
  }

  Future<void> switchAccount(String accountId) async {
    await accounts.setActiveAccount(accountId);
    webDav.setActiveAccount(accountId);
    applySyncConfiguration();
    unawaited(sync.autoScan());
    notifyListeners();
  }

  Timer? _periodicSync;
  Timer? _libraryPushDebounce;

  /// True while a library maintenance action (从云端覆写 / 销毁) owns the library
  /// tables. Automatic writers are shut off for its duration rather than raced
  /// against: a background scan firing mid-wipe would push a half-empty index (or
  /// adopt rows back into it) and leave the two sides out of step.
  bool _libraryMaintenance = false;

  /// Run [body] with the 20 s push debounce and the 定时同步 scan silenced.
  Future<T> _quietLibraryWrites<T>(Future<T> Function() body) async {
    final wasQuiet = _libraryMaintenance;
    _libraryMaintenance = true;
    _libraryPushDebounce?.cancel();
    _libraryPushDebounce = null;
    try {
      return await body();
    } finally {
      _libraryMaintenance = wasQuiet;
    }
  }

  /// Coalesce rapid library changes (a folder download fires once per file).
  void _onLibraryChanged() {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    _libraryPushDebounce?.cancel();
    _libraryPushDebounce = Timer(
      const Duration(seconds: 20),
      () => unawaited(pushLibraryIncrement()),
    );
  }

  SyncInterval _appliedSyncInterval = SyncIntervalX.fallback;

  /// Last 远端路径 / 网盘 [applySyncConfiguration] saw, so an edit in
  /// 设置 → 同步与备份 reaches the playlist service immediately.
  String _appliedSyncRoot = '';
  String? _appliedSyncAccountId;

  /// Re-arm the background timer when the interval setting changes, and re-point
  /// playlist sync when the shared 远端路径 changes.
  void _onSettingsChanged() {
    if (!ready) return;
    if (settings.syncRemoteRoot != _appliedSyncRoot ||
        settings.syncAccountId != _appliedSyncAccountId) {
      applySyncConfiguration();
    }
    if (settings.syncInterval == _appliedSyncInterval) return;
    _appliedSyncInterval = settings.syncInterval;
    _schedulePeriodicSync();
  }

  /// Background scan on the interval chosen in 同步与备份 → 定时同步.
  ///
  /// It runs the **whole** sync: credentials pull (needs the user's key),
  /// playlist merge, and the incremental library push. `off` disables it — the
  /// timer is then simply not created. Cheap no-op when nothing changed.
  void _schedulePeriodicSync() {
    _periodicSync?.cancel();
    _periodicSync = null;
    _appliedSyncInterval = settings.syncInterval;
    final interval = settings.syncInterval.duration;
    if (interval == null) return;
    _periodicSync = Timer.periodic(
      interval,
      (_) => unawaited(runScheduledSync()),
    );
  }

  /// One scheduled pass; also used by the "立即同步一次" action.
  Future<void> runScheduledSync() async {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    try {
      await sync.autoScan();
      await pushLibraryIncrement();
    } catch (_) {
      // Background best-effort — the sync screen surfaces real errors.
    }
  }

  /// Push newly added library rows without waiting for a manual action.
  /// Called after a download finishes so the cloud index follows local changes.
  Future<void> pushLibraryIncrement() async {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    try {
      await sync.syncLibraryIncremental();
    } catch (_) {
      // Background best-effort — the sync screen surfaces real errors.
    }
  }

  Future<int> runCacheCleanup() {
    return cache.cleanupKnown(
      retention: settings.retention,
      customDuration: settings.customRetentionDuration,
      identityToLocal: downloads.completedIdentityToLocal,
      playingIdentityKey:
          player.currentSourceName != null && player.currentRemotePath != null
          ? trackIdentityKey(
              player.currentSourceName!,
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
        final f = cache.fileForRemote(t.remotePath, sourceName: t.sourceName);
        protected.add(f.path);
        protected.add('${f.path}.part');
      }
    }
    final removed = await cache.clearAll(
      playingRemotePath: player.currentRemotePath,
      playingSourceName: player.currentSourceName,
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

  /// Keep the download queue's music classifier aligned with the configured
  /// extension sets (they are user-editable in 「文件后缀管理」).
  void _syncDownloadFileTypes() {
    downloads.configureFileTypes(
      (name) => settings.fileTypes.categoryFor(name) == FileCategory.music,
    );
  }

  /// Called after the user edits the extension sets in Settings.
  void refreshFileTypeClassifiers() => _syncDownloadFileTypes();

  Future<void> setCoverThumbSize(int size) async {
    await settings.setCoverThumbSize(size);
    _syncCoverThumbSize();
  }

  /// Mark every song in the local library as destroyed: one tombstone per track
  /// and nothing else. No row, no cached audio, no cover and no playlist entry is
  /// touched — locally the library is left exactly as it is.
  ///
  /// The **deletion record** is what this action produces: the next sync uploads
  /// the tombstones as `del-*.wdmm` and the cloud materialises them on its next
  /// rebuild. That is the whole difference from [overwriteLibraryFromCloud],
  /// which pulls the cloud copy down over the local one.
  ///
  /// Ends by switching 定时同步 off (the confirmation says so): the user is
  /// deciding *that* these songs die and *when* the cloud hears about it, instead
  /// of the app pushing the deletion on its own schedule.
  ///
  /// Returns how many songs were tombstoned, so the caller can report a number
  /// even though nothing visible changed.
  Future<int> destroyMusicLibrary() async {
    return _quietLibraryWrites(() async {
      final destroyed = await _tombstoneEveryLibraryTrack();
      await settings.setSyncInterval(SyncInterval.off);
      return destroyed;
    });
  }

  /// One tombstone per track, taken from a snapshot so the loop cannot be
  /// disturbed by the library changing underneath it.
  Future<int> _tombstoneEveryLibraryTrack() async {
    final snapshot = List.of(library.tracks);
    for (final t in snapshot) {
      await library.recordTombstone(t.sourceName, t.remotePath);
    }
    return snapshot.length;
  }

  /// 「从云端覆写音乐库」: drop the local index and pull the cloud copy whole.
  ///
  /// Only the index goes (tracks / CUE / tombstones / sync cursor) — the cache
  /// annex, covers and downloaded audio stay, so the rows coming back still
  /// resolve to local files instead of queueing a second full download. The cost
  /// is that local changes not yet pushed disappear with the index; the
  /// confirmation dialog states that.
  Future<SyncOutcome> overwriteLibraryFromCloud() {
    return _quietLibraryWrites(() async {
      await library.prepareCloudOverwrite();
      final outcome = await sync.syncLibraryIncremental();
      await library.refresh();
      return outcome;
    });
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
    _periodicSync?.cancel();
    _libraryPushDebounce?.cancel();
    library.removeListener(_onLibraryChanged);
    credentials.dispose();
    sync.dispose();
    settings.dispose();
    notificationPermission.dispose();
    super.dispose();
  }
}
