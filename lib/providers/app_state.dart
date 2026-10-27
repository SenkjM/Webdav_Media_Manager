import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cache_policy.dart';
import '../models/queue_task.dart';
import '../models/file_type_config.dart';
import '../models/library_track.dart';
import '../models/sync_interval.dart';
import '../utils/app_snack.dart';
import '../utils/track_identity.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/backup_service.dart';
import '../services/cache_index_db.dart';
import '../services/cache_service.dart';
import '../services/credential_vault_service.dart';
import '../services/download_destination_service.dart';
import '../services/task_queue_service.dart';
import '../services/library_database.dart';
import '../services/library_service.dart';
import '../services/user_folder_service.dart';
import '../services/manga_library_service.dart';
import '../utils/rev_clock.dart';
import '../services/music_audio_handler.dart';
import '../services/notification_permission_service.dart';
import '../services/platform_export_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/video_playback_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/cloud_drivers/webdav_source.dart';
import '../services/dlna_cast_service.dart';
import '../services/rust_core_service.dart';
import '../services/rust_dmr_prefs_service.dart';
import '../services/rust_library_probe.dart';
import '../services/webdav_service.dart';

/// Root composition / lifecycle for the app.
class AppState extends ChangeNotifier {
  AppState({required MusicAudioHandler audioHandler})
    : _audioHandler = audioHandler {
    settings = SettingsService();
    notificationPermission = NotificationPermissionService();
    cacheIndex = CacheIndexDb();
    cache = CacheService(indexDb: cacheIndex);
    library = LibraryService();
    userFolders = UserFolderService();
    mangaLibrary = MangaLibraryService();
    accounts = AccountsService();
    cloudDrive = CloudDriveService(accounts: accounts);
    webDav = WebDavService(cloudDrive: cloudDrive);
    // 包装驱动（如 Crypt）的 WebDAV 源解析：装配层注入工厂（99 §7.5），
    // 兼容层不依赖 WebDavService。
    cloudDrive.attachWebDavSourceFactory((id) {
      final acc = accounts.accountById(id);
      if (acc == null || acc.providerType != 'webdav') return null;
      return WebDavAccountSource(webDav: webDav, account: acc);
    });
    // Cover tier follows the music-library setting, so an embedded playlist
    // cover is the same art the library would show (docs/10 §4.2 cover policy).
    playlists = PlaylistService(webDav: webDav, covers: library.covers);
    // Built before BackupService: the archive embeds `encodeVaultBytes()`'s
    // output, so the vault service has to exist first (docs/10 §4.3).
    credentials = CredentialVaultService(
      accounts: accounts,
      settings: settings,
      webDav: webDav,
    );
    // DownloadDestinationService 管理所有「下载目录」写入
    final platformExport = PlatformExportService();
    downloadDestination = DownloadDestinationService(
      settings: settings,
      export: platformExport,
    );
    backup = BackupService(
      userFolders: userFolders,
      manga: mangaLibrary,
      library: library,
      accounts: accounts,
      settings: settings,
      playlists: playlists,
      credentials: credentials,
      webDav: webDav,
      cache: cache,
      // 备份导入后回调 alignNomedia
      onSettingsImported: () => downloadDestination.alignNomedia(),
      dmrPrefs: dmrPrefs,
    );
    sync = SyncService(
      accounts: accounts,
      settings: settings,
      webDav: webDav,
      vault: credentials,
      library: library,
      playlists: playlists,
      backup: backup,
      manga: mangaLibrary,
      folders: userFolders,
      cache: cache,
    );
    taskQueue = TaskQueueService(
      webDav: webDav,
      cache: cache,
      library: library,
      playlists: playlists,
      settings: settings,
      destination: downloadDestination,
      // The network library classifies entries with the configured extension
      // sets, so the queue must use the same list (never a hard-coded one).
      isMusicFile: (name) =>
          settings.fileTypes.categoryFor(name) == FileCategory.music,
    );
    player = AudioPlayerService(
      taskQueue: taskQueue,
      handler: audioHandler,
      webDav: webDav,
      cache: cache,
      settings: settings,
      library: library,
      accounts: accounts,
      playlists: playlists,
      notificationPermission: notificationPermission,
    );
    videoPlayback = VideoPlaybackService(handler: audioHandler);
    dmrPrefs = RustDmrPrefsService();
    dlnaCast = DlnaCastService(webDav: webDav, dmrPrefs: dmrPrefs);
  }

  final MusicAudioHandler _audioHandler;

  late final SettingsService settings;
  late final WebDavService webDav;
  late final DlnaCastService dlnaCast;
  late final RustDmrPrefsService dmrPrefs;
  late final CloudDriveService cloudDrive;
  late final CacheService cache;

  /// Access-time index shared by [cache]; owns `cache_index.db`.
  late final CacheIndexDb cacheIndex;
  late final LibraryService library;
  late final UserFolderService userFolders;
  late final MangaLibraryService mangaLibrary;
  late final AccountsService accounts;
  late final PlaylistService playlists;
  late final BackupService backup;
  late final CredentialVaultService credentials;
  late final DownloadDestinationService downloadDestination;
  late final SyncService sync;
  late final TaskQueueService taskQueue;
  late final NotificationPermissionService notificationPermission;
  late final AudioPlayerService player;
  late final VideoPlaybackService videoPlayback;

  bool ready = false;
  String? initError;
  String _initPhase = 'not_started';

  String get initPhase => _initPhase;

  Future<void> closeDatabases() async {
    await taskQueue.closeDatabase();
    await playlists.closeDatabase();
  }

  Future<void>? _shutdownFuture;

  Future<void> shutdown() {
    return _shutdownFuture ??= _shutdownImpl();
  }

  Future<void> _shutdownImpl() async {
    try {
      await videoPlayback.stop();
    } catch (_) {}
    try {
      await _audioHandler.disposePlayer();
    } catch (_) {}
    _disposeServices();
  }

  void _disposeServices() {
    dlnaCast.dispose();
    videoPlayback.dispose();
    player.dispose();
    taskQueue.dispose();
    cache.dispose();
    webDav.dispose();
    library.dispose();
    accounts.dispose();
    playlists.dispose();
    backup.dispose();
    downloadDestination.dispose();
    _periodicSync?.cancel();
    _libraryPushDebounce?.cancel();
    library.removeListener(_onLibraryChanged);
    credentials.dispose();
    sync.dispose();
    settings.dispose();
    notificationPermission.dispose();
  }

  Future<void> init() async {
    try {
      _initPhase = 'settings';
      await settings.init();
      AppSnack.attach(settings);
      // SAF 自定义下载目录：启动时校验可用性
      await downloadDestination.verifyOnOpen();
      // .nomedia 双向对齐（规格 §8：启动时不再只补不删）
      await downloadDestination.alignNomedia();
      _syncCoverThumbSize();
      _syncDownloadFileTypes();
      // Existing schema path first (onCreate / onUpgrade, including account
      // column compat). The 0.2.2 sentinel only rewrites rows and must not
      // run against tables the open has not created yet.
      _initPhase = 'databases';
      await playlists.openDatabase();
      await taskQueue.openDatabase();
      _initPhase = 'cache';
      await cache.init();
      _initPhase = 'dmr-prefs';
      final docs = await getApplicationDocumentsDirectory();
      await dmrPrefs.init(docs.path);
      // Configure Core cover roots once paths are known, so backup/restore operations
      // see them. Call here (not just in BackupService create/restore) to cover
      // upload/download paths that go through Core directly.
      await backup.ensureCoversConfigured();
      // 0.2.4: legacy sentinel migration removed (99 §18.4).
      // The rev clock is the single version source sync compares; it starts from
      // the persisted high-water mark and reports every advance back.
      // Music and manga rows share one clock, so their revs stay on one scale.
      final revClock = RevClock(
        nowMs: () => DateTime.now().millisecondsSinceEpoch,
        initial: settings.lastRev,
        onAdvance: settings.setLastRev,
      );
      library.attachRevClock(revClock);
      mangaLibrary.attachRevClock(revClock);
      // One-shot sqflite→Core import (Android only). Must run before
      // library.init() → refresh() consumes Core as truth, otherwise an
      // unimported sqflite DB would read back as an empty library. Idempotent
      // via Core KV `sqflite_imported` / `sqflite_imported_v6`; hard-fails on
      // error when the file exists so we never silently lose data.
      _initPhase = 'sqflite-import';
      final sqfliteDbPath = await _importLibraryFromSqfliteIfNeeded();
      _initPhase = 'library';
      await library.init();
      _initPhase = 'user-folders';
      await userFolders.init();
      await _migrateKvFoldersMeta();
      _initPhase = 'manga-library';
      await mangaLibrary.init();
      _initPhase = 'accounts';
      await accounts.init();
      await registerAllAccounts();
      // Retire the legacy sqflite file once all migrates have completed on
      // this same launch (library import + folders-kv migrate + cache groups
      // migrate + accounts migrate). Best-effort; errors are logged, not fatal.
      await _retireMusicLibraryDbIfMigrated(sqfliteDbPath);
      // The queue persists 网盘名, never an account id: it has to resolve one to
      // the other **after** the account list is loaded, or every transfer would
      // be judged "来源网盘未绑定".
      taskQueue.configureAccountResolver(accounts.idForSource);
      applySyncConfiguration();
      _initPhase = 'playlists';
      await playlists.init();
      taskQueue.attachLibrary(library);
      taskQueue.attachMangaLibrary(mangaLibrary);
      // Incremental library sync: whenever a download (or a restore) changes
      // the local library, push just the new rows to the cloud index.
      library.addListener(_onLibraryChanged);
      // Same 20 s debounce for manga rows / reading progress and user folders.
      mangaLibrary.addListener(_onMangaChanged);
      userFolders.addListener(_onFoldersChanged);
      // Changing 定时同步 in Settings must take effect immediately, not on the
      // next launch.
      settings.addListener(_onSettingsChanged);
      _initPhase = 'taskQueue';
      taskQueue.keepAliveEnabled = settings.downloadKeepAliveEnabled;
      await taskQueue.init();
      // Restore the persisted now-playing queue after accounts + library are
      // loaded (entries bind accounts by source name, metadata comes from the
      // library). Restoring never starts audio.
      await player.restoreQueue();
      // Download notifications: create the channel and honour the setting.
      taskQueue.notificationsEnabled = settings.downloadNotificationsEnabled;
      taskQueue.notificationService.enabled =
          settings.downloadNotificationsEnabled;
      unawaited(taskQueue.initNotifications());
      await notificationPermission.refresh();
      unawaited(runCacheCleanup());
      // Startup scan: credentials + playlists both ways (best-effort, never
      // blocks the first frame).
      unawaited(sync.autoScan());
      _schedulePeriodicSync();
      ready = true;
    } catch (e, stack) {
      initError = '$_initPhase: $e';
      debugPrint('AppState initialization failed at $_initPhase: $e');
      debugPrintStack(stackTrace: stack);
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
      // 云盘账号不建 WebDAV 客户端（99 §7.2.2），由 cloudDrive 统一登记。
      if (CloudDriveService.isCloudType(a.providerType)) continue;
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
    await cloudDrive.registerAccounts(
      accounts.accounts.where(
        (a) => CloudDriveService.isCloudType(a.providerType),
      ),
    );
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
  Timer? _mangaPushDebounce;
  Timer? _foldersPushDebounce;

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
    _mangaPushDebounce?.cancel();
    _mangaPushDebounce = null;
    _foldersPushDebounce?.cancel();
    _foldersPushDebounce = null;
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

  void _onMangaChanged() {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    _mangaPushDebounce?.cancel();
    _mangaPushDebounce = Timer(
      const Duration(seconds: 20),
      () => unawaited(pushMangaIncrement()),
    );
  }

  void _onFoldersChanged() {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    _foldersPushDebounce?.cancel();
    _foldersPushDebounce = Timer(
      const Duration(seconds: 20),
      () => unawaited(pushFoldersSync()),
    );
  }

  /// Background manga push (rows + tombstones + reading progress).
  Future<void> pushMangaIncrement() async {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    try {
      await sync.syncMangaIncremental();
    } catch (_) {}
  }

  /// Background user-folder snapshot sync.
  Future<void> pushFoldersSync() async {
    if (!ready || !sync.hasUsableAccount || _libraryMaintenance) return;
    try {
      await sync.syncUserFolders();
    } catch (_) {}
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
    if (taskQueue.keepAliveEnabled != settings.downloadKeepAliveEnabled) {
      unawaited(
        taskQueue.setKeepAliveEnabled(settings.downloadKeepAliveEnabled),
      );
    }
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
      await pushMangaIncrement();
      await pushFoldersSync();
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

  Future<int> runCacheCleanup() async {
    final removed = await cache.cleanupKnown(
      retention: settings.retention,
      customDuration: settings.customRetentionDuration,
      identityToLocal: taskQueue.completedIdentityToLocal,
      playingIdentityKey:
          player.currentSourceName != null && player.currentRemotePath != null
          ? trackIdentityKey(
              player.currentSourceName!,
              player.currentRemotePath!,
            )
          : null,
      downloadingIdentityKeys: taskQueue.downloadingIdentityKeys,
    );
    // Second pass by expiry alone: files whose identity is no longer in the
    // completed-task map still have to age out.
    final orphans = await cache.cleanupExpired(
      kind: CacheKind.music,
      policy: settings.musicCacheExpiryPolicy,
    );
    await runCacheCapacityEviction();
    return removed + orphans;
  }

  Future<int> manualClearCache() async {
    final protected = <String>{};
    for (final t in taskQueue.tasks) {
      if (t.status == TaskStatus.active || t.status == TaskStatus.pending) {
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
    await taskQueue.invalidateMissingCompleted();
    await cache.pruneIndex(CacheKind.music);
    return removed;
  }

  Future<void> setRetention(CacheRetention r) async {
    await settings.setRetention(r);
    unawaited(runCacheCleanup());
  }

  Future<void> setMusicCacheMaxMb(int mb) async {
    await settings.setMusicCacheMaxMb(mb);
    unawaited(runCacheCapacityEviction());
  }

  Future<int> runCacheCapacityEviction() {
    final maxBytes = settings.musicCacheMaxBytes;
    if (maxBytes <= 0) return Future.value(0);
    final protected = <String>{};
    for (final task in taskQueue.tasks) {
      if (task.status == TaskStatus.active ||
          task.status == TaskStatus.pending) {
        final f = cache.fileForRemote(
          task.remotePath,
          sourceName: task.sourceName,
        );
        protected.add(f.path);
        protected.add('${f.path}.part');
      }
    }
    return cache.evictToMaxBytes(
      maxBytes: maxBytes,
      playingLocalPath: player.current?.localPath,
      playingRemotePath: player.currentRemotePath,
      playingSourceName: player.currentSourceName,
      protectedLocalPaths: protected,
    );
  }

  Future<void> setCustomRetentionDuration(Duration d) async {
    await settings.setCustomRetentionDuration(d);
    if (settings.retention != CacheRetention.custom) {
      await settings.setRetention(CacheRetention.custom);
    }
    unawaited(runCacheCleanup());
  }

  // --- manga cache: same three knobs, its own settings ----------------------

  Future<int> runMangaCacheCleanup() async {
    final removed = await cache.cleanupExpired(
      kind: CacheKind.manga,
      policy: settings.mangaCacheExpiryPolicy,
    );
    await runMangaCacheCapacityEviction();
    return removed;
  }

  Future<int> runMangaCacheCapacityEviction() {
    final maxBytes = settings.mangaCacheMaxBytes;
    if (maxBytes <= 0) return Future.value(0);
    return cache.evictCacheToMaxBytes(
      kind: CacheKind.manga,
      maxBytes: maxBytes,
    );
  }

  Future<int> manualClearMangaCache() async {
    final removed = await cache.clearAllMangaCache();
    await cache.pruneIndex(CacheKind.manga);
    return removed;
  }

  Future<void> setMangaRetention(CacheRetention r) async {
    await settings.setMangaRetention(r);
    unawaited(runMangaCacheCleanup());
  }

  Future<void> setMangaCustomRetentionDuration(Duration d) async {
    await settings.setMangaCustomRetentionDuration(d);
    if (settings.mangaRetention != CacheRetention.custom) {
      await settings.setMangaRetention(CacheRetention.custom);
    }
    unawaited(runMangaCacheCleanup());
  }

  Future<void> setMangaCacheMaxMb(int mb) async {
    await settings.setMangaCacheMaxMb(mb);
    unawaited(runMangaCacheCapacityEviction());
  }

  void _syncCoverThumbSize() {
    library.covers.thumbSize = settings.coverThumbSizePx;
  }

  /// Keep the download queue's music classifier aligned with the configured
  /// extension sets (they are user-editable in 「文件后缀管理」).
  void _syncDownloadFileTypes() {
    taskQueue.configureFileTypes(
      (name) => settings.fileTypes.categoryFor(name) == FileCategory.music,
    );
  }

  /// Called after the user edits the extension sets in Settings.
  void refreshFileTypeClassifiers() => _syncDownloadFileTypes();

  Future<void> setCoverThumbSize(int size) async {
    await settings.setCoverThumbSize(size);
    _syncCoverThumbSize();
  }

  /// 销毁一首歌 —— **唯一的原子单位**。
  ///
  /// 批量销毁只是把它一首一首跑：循环的调用方只能在两首**之间**停下，绝不会停
  /// 在半首上。顺序是墓碑 → 本地音频 → 封面 → 库行 → 内存（最后一步连同
  /// `notifyListeners()` 在 [LibraryService.destroyTrack] 里完成）。
  ///
  /// 返回 false 表示这首歌已经不在了。返回值只管「这次有没有东西被销毁」；
  /// 要数字就数 [LibraryService.count] 前后的差，不要数它。
  Future<bool> destroyLibraryTrack(LibraryTrack track) async {
    final live = library.find(track.sourceName, track.remotePath);
    if (live == null) return false;
    final expanded = destroyTargets(<LibraryTrack>[live]);
    for (final one in expanded) {
      await _deleteCachedAudioFor(one);
      await library.destroyTrack(one);
    }
    return expanded.isNotEmpty;
  }

  /// 展开成「实际会被销毁的全集」：CUE 分片点中一片等于整张专辑，普通曲目就是自己。
  ///
  /// 组的成员要查**全库**，不能只在传入的集合里找——只点一片时那个集合里只有一片。
  /// 展开放在这里而不是 [LibraryService.destroyTrack]：销毁的原子单位始终是一片，
  /// 每片各删各的行、各留各的墓碑，只有「一次跑几片」是调用方的事。
  List<LibraryTrack> destroyTargets(Iterable<LibraryTrack> selected) {
    final parsed = <String, List<LibraryTrack>>{};
    for (final x in library.tracks) {
      final cuePath = x.cueRemotePath;
      if (!x.isCueVirtual || cuePath == null) continue;
      parsed
          .putIfAbsent('${x.sourceName}\u0000$cuePath', () => <LibraryTrack>[])
          .add(x);
    }
    final seen = <String>{};
    final out = <LibraryTrack>[];
    for (final t in selected) {
      final cuePath = t.cueRemotePath;
      final group = (t.isCueVirtual && cuePath != null)
          ? (parsed['${t.sourceName}\u0000$cuePath'] ?? <LibraryTrack>[t])
          : <LibraryTrack>[t];
      for (final one in group) {
        if (seen.add(one.musicId)) out.add(one);
      }
      // 兜底：选中的项万一不在内存里，也别把它漏掉。
      if (seen.add(t.musicId)) out.add(t);
    }
    return out;
  }

  /// 逐首销毁 [tracks]：每跑完一首回调一次 [onProgress]，并在两首之间询问
  /// [isCancelled]。返回真正销毁的曲目数。
  Future<int> destroyLibraryTracks(
    Iterable<LibraryTrack> tracks, {
    void Function(int processed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final list = List.of(tracks);
    var processed = 0;
    var destroyed = 0;
    for (final t in list) {
      if (isCancelled?.call() ?? false) break;
      if (await destroyLibraryTrack(t)) destroyed++;
      processed++;
      onProgress?.call(processed, list.length);
    }
    return destroyed;
  }

  /// 销毁整个音乐库：逐首走完，再清掉歌单里的悬空引用、失效掉已完成的下载记录，
  /// 最后把定时同步设为关闭（确认框里写明了）。
  ///
  /// 与 [overwriteLibraryFromCloud] 方向相反：这里不向云端拉任何东西，同步游标
  /// 与其它网盘的行都不动，**走的是删除**——下次同步以 `del-*.wdmm` 上传。
  Future<int> destroyMusicLibrary({
    void Function(int processed, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return _quietLibraryWrites(() async {
      final destroyed = await destroyLibraryTracks(
        List.of(library.tracks),
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      // 库空了，歌单里指向它的引用成了悬空引用，下载队列也要重新对账。
      await playlists.removeEntriesNotIn(const <String>{});
      await taskQueue.invalidateMissingCompleted();
      await settings.setSyncInterval(SyncInterval.off);
      return destroyed;
    });
  }

  /// 删掉这一首的本地音频：CUE 分片共用一整组，先删组；其余删单个文件。
  Future<void> _deleteCachedAudioFor(LibraryTrack t) async {
    final gid =
        t.cacheGroupId ??
        (t.cueRemotePath != null && t.cueRemotePath!.isNotEmpty
            ? cueCacheGroupId(t.sourceName, t.cueRemotePath!)
            : null);
    if (gid != null && gid.isNotEmpty) {
      await cache.deleteCacheGroup(gid);
    }
    if (!t.isCueVirtual) {
      await cache.deleteLocalFile(
        sourceName: t.sourceName,
        remotePath: t.effectiveAudioRemotePath,
      );
    }
  }

  /// 「从云端覆写音乐库」: drop the local index and pull the cloud copy whole.
  ///
  /// Only the index goes (tracks / CUE / tombstones / sync cursor) — the cache
  /// audio stays, so the rows coming back still
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

  /// 「从云端覆写漫画库」: drop the local manga index and pull the cloud copy.
  /// Reading progress and `manga_cache/` stay (progress then merges as usual).
  Future<SyncOutcome> overwriteMangaFromCloud() {
    return _quietLibraryWrites(() async {
      final clear = RustCoreService.mangaClearIndex();
      if (clear != null && clear.startsWith('error:')) {
        throw StateError('Core manga clear-index failed: $clear');
      }
      await mangaLibrary.reload();
      final outcome = await sync.syncMangaIncremental();
      await mangaLibrary.reload();
      return outcome;
    });
  }

  /// 「删除漫画库」: one manga at a time — cached archive, cover, then the row
  /// (which leaves a tombstone). Turns 定时同步 off at the end, like music.
  Future<int> destroyMangaLibrary({
    void Function(int processed, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return _quietLibraryWrites(() async {
      final list = List.of(mangaLibrary.mangas);
      var processed = 0;
      for (final m in list) {
        if (isCancelled?.call() ?? false) break;
        for (final f in [
          cache.mangaFileForRemote(m.remotePath, sourceName: m.sourceName),
          cache.mangaCoverFile(m.id),
        ]) {
          try {
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        await mangaLibrary.deleteManga(m.id);
        processed++;
        onProgress?.call(processed, list.length);
      }
      await mangaLibrary.reload();
      await settings.setSyncInterval(SyncInterval.off);
      return processed;
    });
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }

  /// On Android: if [LibraryDatabase.fileName] exists under Documents, run a
  /// one-shot sqflite→Core library import.
  ///
  /// The import is idempotent — Core KV `sqflite_imported` / `sqflite_imported_v6`
  /// guard it, so calling it every launch is cheap once the file is imported.
  ///
  /// Returns the absolute path to the db file when an import was attempted
  /// (whether already_done or freshly imported), or null when the file is
  /// absent / non-Android.
  ///
  /// Hard-fails with [StateError] when the file exists on Android but the
  /// import returns an error or null — same tone as other SoT cuts (e.g.
  /// [RustLibraryService.listAll], manga clear-index).
  static Future<String?> _importLibraryFromSqfliteIfNeeded() async {
    if (!Platform.isAndroid) return null;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, LibraryDatabase.fileName);
    if (!File(path).existsSync()) return null;

    final result = RustCoreService.libraryImportFromSqflite(path);
    if (result == null || result.startsWith('error:')) {
      throw StateError(
        'sqflite→Core library import failed ($result); '
        'aborting startup to protect data',
      );
    }
    final logLine = RustLibraryProbe.formatImportSummary(result);
    if (logLine != null) {
      debugPrint(logLine);
    } else {
      debugPrint('[AppState] sqflite import result: $result');
    }
    return path;
  }

  /// Best-effort delete of the legacy sqflite files once all migrates have
  /// succeeded on this launch.
  ///
  /// Only runs when [dbPath] is non-null (file existed at startup and the
  /// library import succeeded) and the `folders_changed_at` KV sentinel is
  /// set (confirming the folders-kv migrate ran this launch).
  /// [cache.init()] is guaranteed to have run before this is called.
  ///
  /// Delete errors are logged, never fatal.
  static Future<void> _retireMusicLibraryDbIfMigrated(String? dbPath) async {
    if (dbPath == null) return; // file was absent at startup — nothing to delete

    // Verify the folders-kv sentinel (same check as _migrateKvFoldersMeta).
    final foldersAt = RustCoreService.kvGet('folders_changed_at');
    final foldersOk = foldersAt != null &&
        foldersAt.isNotEmpty &&
        foldersAt != 'null' &&
        !foldersAt.startsWith('error:');
    if (!foldersOk) {
      debugPrint(
        '[AppState] retire: folders_changed_at not set — skipping delete',
      );
      return;
    }

    // Delete music_library.db and its WAL/SHM companions (best-effort).
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$dbPath$suffix');
      try {
        if (await file.exists()) {
          await file.delete();
          debugPrint('[AppState] retire: deleted ${file.path}');
        }
      } catch (e) {
        debugPrint('[AppState] retire: could not delete ${file.path}: $e');
      }
    }
  }

  /// One-shot migration: copy folder sync meta keys from sqflite [LibraryDatabase]
  /// into the Core KV store, then never read them from sqflite again.
  ///
  /// Opens a temporary [LibraryDatabase] for the read-only migration and closes
  /// it immediately after. Skipped when `folders_changed_at` is already present
  /// in the KV store, or when Core FFI is unavailable (non-Android).
  static Future<void> _migrateKvFoldersMeta() async {
    final existing = RustCoreService.kvGet('folders_changed_at');
    // Dart null → Core FFI unavailable (skip). Literal "null"/empty/error →
    // key absent or bad → migrate from sqflite. Any other value → already set.
    if (existing == null) return;
    final already =
        existing.isNotEmpty &&
        existing != 'null' &&
        !existing.startsWith('error:');
    if (already) return;

    final db = LibraryDatabase();
    try {
      // Migrate the three key families once.
      const keys = [
        'folders_changed_at',
        // last_sync and cloud_seen are per-destination (open-ended); we scan
        // all local_meta rows that match the prefix rather than enumerating dests.
      ];
      for (final k in keys) {
        final v = await db.loadMeta(k);
        if (v != null && v.isNotEmpty) RustCoreService.kvSet(k, v);
      }
      // Migrate per-destination keys by scanning known prefixes from the sqflite
      // local_meta table. We read them via loadMeta using the known pattern; the
      // dest string is opaque so we copy them all via the two prefixes.
      for (final prefix in const [
        'folders_last_sync_at:',
        'folders_cloud_seen:',
      ]) {
        final allMeta = await db.loadMetaByPrefix(prefix);
        for (final entry in allMeta.entries) {
          RustCoreService.kvSet(entry.key, entry.value);
        }
      }
      // Ensure the sentinel key exists so we do not re-scan sqflite every launch
      // when the old DB had no folders meta either.
      final after = RustCoreService.kvGet('folders_changed_at');
      if (after == null ||
          after.isEmpty ||
          after == 'null' ||
          after.startsWith('error:')) {
        RustCoreService.kvSet('folders_changed_at', '0');
      }
    } finally {
      await db.close();
    }
  }
}
