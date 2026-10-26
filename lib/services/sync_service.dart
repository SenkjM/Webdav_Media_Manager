import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/backup_paths.dart';
import '../utils/l10n_host.dart';
import '../utils/track_identity.dart';
import 'accounts_service.dart';
import 'backup_service.dart';
import 'credential_vault_service.dart';
import 'library_service.dart';
import 'library_sync_store.dart';
import 'cache_service.dart';
import 'library_database.dart';
import 'manga_cover_writer.dart';
import 'manga_library_service.dart';
import 'manga_sync_store.dart';
import 'user_folder_service.dart';
import 'user_folder_sync.dart';
import 'playlist_service.dart';
import 'platform_export_service.dart';
import '../models/account_capabilities.dart';

import 'settings_service.dart';
import 'webdav_service.dart';
import 'download_destination_service.dart';
import 'rust_core_service.dart';

/// What a single operation touched.
class SyncOutcome {
  SyncOutcome({required this.direction});

  /// `push` / `pull` / `sync` / `backup` / `restore` / `import` / `export`.
  final String direction;

  final List<String> steps = [];
  final List<String> warnings = [];

  bool ok = true;
  String? error;

  void step(String message) => steps.add(message);
  void warn(String message) => warnings.add(message);

  String get message {
    final l10n = L10nHost.current;
    if (!ok) {
      return l10n.syncOperationFailed(
        describeError(error ?? l10n.syncUnknownError, l10n),
      );
    }
    final body = steps.isEmpty
        ? l10n.syncNoChanges
        : steps.join(l10n.syncListSep);
    final warn = warnings.isEmpty
        ? ''
        : '\n${l10n.syncNotePrefix}${warnings.join(l10n.syncListSep)}';
    return '$body$warn';
  }

  /// Map stable error codes (and their `Bad state:` / `WmpFormatException:`
  /// wrappers) to localized text; unknown values pass through unchanged.
  static String describeError(String raw, AppLocalizations l10n) {
    var text = raw;
    for (final prefix in const ['Bad state: ', 'WmpFormatException: ']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length);
    }
    final bar = text.indexOf('|');
    if (bar > 0) {
      final code = text.substring(0, bar);
      final detail = text.substring(bar + 1);
      if (code == 'err.notBackupArchive') {
        return l10n.errNotBackupArchive(detail);
      }
      if (code == 'err.shardKindMismatch') {
        final bar2 = detail.indexOf('|');
        return l10n.errShardKindMismatch(
          bar2 > 0 ? detail.substring(0, bar2) : detail,
          bar2 > 0 ? detail.substring(bar2 + 1) : '',
        );
      }
      // `err.playlistKindMismatch|<found>|<expected>`, and the vault twin with
      // the same two-part shape.
      if (code == 'err.playlistKindMismatch' ||
          code == 'err.playlistDeletionKindMismatch' ||
          code == 'err.vaultKindMismatch') {
        final bar2 = detail.indexOf('|');
        final found = bar2 > 0 ? detail.substring(0, bar2) : detail;
        final expected = bar2 > 0 ? detail.substring(bar2 + 1) : '';
        return switch (code) {
          'err.playlistKindMismatch' => l10n.errPlaylistKindMismatch(
            found,
            expected,
          ),
          'err.playlistDeletionKindMismatch' =>
            l10n.errPlaylistDeletionKindMismatch(found, expected),
          _ => l10n.errVaultKindMismatch(found, expected),
        };
      }
    }
    switch (text) {
      case 'err.noWebdavAccount':
        return l10n.errNoWebdavAccount;
      case 'err.vaultDestNotConfigured':
        return l10n.errVaultDestNotConfigured;
      case 'err.backupDestNotConfigured':
        return l10n.errBackupDestNotConfigured;
      case 'err.backupEncryptedNeedPassphrase':
        return l10n.errBackupEncryptedNeedPassphrase;
      case 'err.backupUnrecognizedContent':
        return l10n.errBackupUnrecognizedContent;
      case 'err.notWdmmFile':
        return l10n.errNotWdmmFile;
      case 'err.playlistMissingId':
        return l10n.errPlaylistMissingId;
      case 'err.playlistDeletionMissingId':
        return l10n.errPlaylistDeletionMissingId;
    }
    return text;
  }
}

/// 同步 / 备份.
///
/// The app only has three kinds of data, and each gets the treatment that fits
/// it. There is **no per-site isolation** anywhere: one WebDAV account list, one
/// music library, one playlist set — and a backup picks its destination server
/// and path explicitly.
///
/// | data | behaviour |
/// |------|-----------|
/// | WebDAV 凭证 | **真同步**：与云端 `credentials.json` 双向合并；地址/用户名明文、仅密码可选加密；启动与切换账号时自动扫描 |
/// | 歌单 | **真同步**：整份 `WDMMPL01` 最后写入胜出；删除记在该歌单自己的 `WDMMPD01` 包里，拉取不会把本地副本无条件传回去 |
/// | 音乐库 | **增量**：本地新增即上传、云端新增即下载；也可手动**全量同步**（对齐删除） |
/// | 全部备份 | 凭证 + 音乐库 + 歌单打成一个归档，写到用户选定的网盘与路径；可恢复、可导出到本地下载目录 |
class SyncService extends ChangeNotifier {
  SyncService({
    required AccountsService accounts,
    required SettingsService settings,
    required WebDavService webDav,
    required CredentialVaultService vault,
    required LibraryService library,
    required PlaylistService playlists,
    required BackupService backup,
    PlatformExportService? export,
    MangaLibraryService? manga,
    UserFolderService? folders,
    LibraryDatabase? db,
    CacheService? cache,
    DownloadDestinationService? destination,
  }) : _manga = manga,
       _folders = folders,
       _db = db,
       _cache = cache,
       _accounts = accounts,
       _settings = settings,
       _webDav = webDav,
       _vault = vault,
       _library = library,
       _playlists = playlists,
       _backup = backup,
       _export = export ?? const PlatformExportService(),
       _destination = destination;

  final AccountsService _accounts;
  final SettingsService _settings;
  final WebDavService _webDav;
  final CredentialVaultService _vault;
  final LibraryService _library;
  final PlaylistService _playlists;
  final BackupService _backup;
  final PlatformExportService _export;
  final DownloadDestinationService? _destination;
  final MangaLibraryService? _manga;
  final UserFolderService? _folders;
  final LibraryDatabase? _db;
  final CacheService? _cache;

  static const localExportSubdir = 'WebdavMediaManager';
  static const localExportPrefix = 'wdmm-export';

  /// Incremental library index (state kept by [LibrarySyncStore]).
  ///
  /// WebDAV has no append: a `PUT` always replaces the whole file. A single
  /// `library_index.json` therefore meant **every** new downloaded track
  /// re-uploaded the entire library. Instead the directory now holds:
  ///
  /// * `library_index.json` — a small **manifest**: which snapshot + segments
  ///   make up the current index;
  /// * `seg-<ts>-<rand>.json` — an **append-only batch** with just the rows that
  ///   changed (one new track = one small file);
  /// * `snap-<ts>.json` — a **compacted snapshot** of everything, written when
  ///   the segments pile up (see [libraryMaxSegments]) or on a full sync.
  ///
  /// Reading merges snapshot + all segments by `remotePath`, newest
  /// `lastTagReadAt` winning.
  static const librarySubdir = 'library/';
  static const libraryIndexName = 'library_index.json';
  static const librarySegmentPrefix = 'seg-';
  static const librarySnapshotPrefix = 'snap-';

  /// Compact once the manifest lists more segments than this.
  static const libraryMaxSegments = 24;

  /// Marker for the per-account index format.
  static const libraryFormat = 'webdav_media_manager_library_index';
  static const libraryFormatVersion = 3;

  bool busy = false;
  String? lastError;
  String? lastMessage;
  double? progress;
  String? progressLabel;

  /// Result of the last background scan (shown in the sync screen).
  DateTime? lastAutoSyncAt;
  String? lastAutoSyncSummary;

  void _progress(String label, [double? value]) {
    progressLabel = label;
    progress = value;
    notifyListeners();
  }

  // --- Helpers ----------------------------------------------------------

  List<WebDavAccount> get accounts => _accounts.accounts;

  WebDavAccount? get targetAccount {
    // 同步目标需要写能力；查 WebDavService.can(id, AccountCaps.write)。
    final connectedId = _webDav.accountId;
    if (connectedId != null) {
      for (final a in _accounts.accounts) {
        if (a.id == connectedId) {
          return _webDav.can(a.id, AccountCaps.write) ? a : null;
        }
      }
    }
    final active = _accounts.activeAccount;
    return active != null && _webDav.can(active.id, AccountCaps.write)
        ? active
        : null;
  }

  String get syncRoot => _settings.syncRemoteRoot;

  /// Whether there is an account we could sync with (password may still be
  /// blank, which background scans treat as "not usable").
  bool get hasUsableAccount {
    final a = targetAccount;
    if (a == null) return false;
    return _accounts.accounts.any((e) => e.id == a.id);
  }

  Future<void> _run(SyncOutcome outcome, Future<void> Function() body) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    _progress(L10nHost.current.progressPreparing, 0.02);
    notifyListeners();
    try {
      await body();
      _progress(L10nHost.current.progressDone, 1);
    } catch (e) {
      outcome.ok = false;
      outcome.error = e.toString();
      lastError = e.toString();
    } finally {
      lastMessage = outcome.message;
      busy = false;
      notifyListeners();
    }
  }

  // --- Auto scan (credentials + playlists) ------------------------------

  /// Startup / periodic scan: pull credentials and playlists both ways.
  ///
  /// Runs in the background — never blocks the app, and silently does nothing
  /// when there is no account.
  ///
  /// The credential pull needs the **user's** unified decryption key; without it
  /// the scan still merges playlists, it just refuses to import accounts whose
  /// passwords it could not decrypt (that would only add blank-password mounts
  /// every launch).
  Future<void> autoScan() async {
    if (busy) return;
    final dest = await syncDestination();
    if (dest == null) return;
    final pass = _settings.vaultPassphrase;
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      if (pass.isEmpty) {
        outcome.step(L10nHost.current.warnCredentialsSkippedNoKey);
      } else {
        _progress(L10nHost.current.progressScanningCloudCredentials, 0.3);
        try {
          final result = await _vault.pull(accountId: dest, passphrase: pass);
          if (result != null) outcome.step(result.summary);
        } catch (e) {
          outcome.warn(L10nHost.current.warnCredentialScanSkipped('$e'));
        }
      }
      _progress(L10nHost.current.progressScanningPlaylists, 0.7);
      _playlists.configureSync(
        remotePath: _settings.playlistRemotePath,
        enabled: true,
        accountId: dest,
      );
      await _playlists.pullAndMergeFromWebDav();
      outcome.step(
        L10nHost.current.stepPlaylistsMerged(_playlists.playlists.length),
      );
    });
    lastAutoSyncAt = DateTime.now();
    lastAutoSyncSummary = outcome.message;
    notifyListeners();
  }

  // --- Credentials ------------------------------------------------------

  /// The **one** 网盘 凭证 / 歌单 / 音乐库 / 备份 all sync to (设置 → 同步与备份
  /// → 远端路径). Falls back to the active account when the user pinned none.
  Future<String?> syncDestination() async =>
      _settings.syncAccountId ?? _accounts.activeAccountId;

  /// Upload local credentials to the configured destination.
  ///
  /// Encryption uses the user's own [SettingsService.vaultPassphrase], never the
  /// destination account's login password.
  Future<SyncOutcome> pushCredentials({String? passphrase}) async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      final pass = passphrase ?? _settings.vaultPassphrase;
      _progress(L10nHost.current.progressUploadingCredentials, 0.5);
      await _vault.push(accountId: dest, passphrase: pass);
      outcome.step(
        L10nHost.current.stepCredentialsUploaded(_accounts.accounts.length),
      );
    });
    return outcome;
  }

  /// Download cloud credentials into this device. Passwords that cannot be
  /// decrypted are left empty rather than failing the whole operation.
  Future<SyncOutcome> pullCredentials({String? passphrase}) async {
    final outcome = SyncOutcome(direction: 'pull');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      final pass = passphrase ?? _settings.vaultPassphrase;
      _progress(L10nHost.current.progressDownloadingCredentials, 0.5);
      final result = await _vault.pull(accountId: dest, passphrase: pass);
      outcome.step(result?.summary ?? L10nHost.current.stepCloudNoCredentials);
      await _accounts.init();
    });
    return outcome;
  }

  // --- Playlists --------------------------------------------------------

  Future<SyncOutcome> syncPlaylistsNow() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      _playlists.configureSync(
        remotePath: _settings.playlistRemotePath,
        enabled: true,
        accountId: dest,
      );
      _progress(L10nHost.current.progressMergingPlaylists, 0.5);
      await _playlists.pullAndMergeFromWebDav();
      outcome.step(
        L10nHost.current.stepPlaylistsSynced(_playlists.playlists.length),
      );
    });
    return outcome;
  }

  /// Manual compact of the per-playlist deletion packs. No reminder, no timer.
  Future<SyncOutcome> compactPlaylistDeletions() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      _playlists.configureSync(
        remotePath: _settings.playlistRemotePath,
        enabled: true,
        accountId: dest,
      );
      _progress(L10nHost.current.progressCompactingPlaylistDeletions, 0.5);
      await _playlists.compactDeletionQueue();
      outcome.step(L10nHost.current.stepPlaylistDeletionsCompacted);
    });
    return outcome;
  }

  // --- Music library (incremental / rebuild) ----------------------------

  /// Fragments (delta + tombstone parts) currently on the cloud, for the
  /// "建议重建" hint in the sync screen.
  int cloudFragmentCount = 0;
  int cloudFragmentBytes = 0;

  /// Incremental library sync — delegates to Core FFI (`run_sync_all`).
  ///
  /// Runs credentials + music library + manga + playlists via
  /// [RustCoreService.syncTrigger]. Refreshes Dart caches on completion.
  Future<SyncOutcome> syncLibraryIncremental() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      await _runCoreSync(outcome, full: false);
    });
    return outcome;
  }

  /// Full library sync (base-shard rebuild) — delegates to Core FFI (`run_sync_full`).
  ///
  /// Runs credentials + music library + manga + playlists via
  /// [RustCoreService.syncFull]. Refreshes Dart caches on completion.
  /// The [tracksPerShard] and [withCovers] parameters are accepted for
  /// API compatibility but Core controls rebuild parameters internally.
  Future<SyncOutcome> syncLibraryFull({
    int tracksPerShard = LibrarySyncStore.defaultTracksPerShard,
    bool withCovers = true,
  }) async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      await _runCoreSync(outcome, full: true);
    });
    return outcome;
  }

  /// Compare the cloud manifest with the directory's real contents.
  Future<LibraryAudit> auditLibrary() async {
    final dest = await syncDestination();
    if (dest == null) throw StateError('err.noWebdavAccount');
    final store = await _libraryStore();
    return store.audit(dest);
  }

  /// Delete the orphan files an audit found (best effort).
  Future<int> tidyLibraryOrphans(LibraryAudit audit) async {
    final dest = await syncDestination();
    if (dest == null) throw StateError('err.noWebdavAccount');
    final store = await _libraryStore();
    return store.deleteOrphans(dest, audit);
  }

  /// Preview a rebuild (shard count + bytes) without touching the cloud.
  Future<RebuildEstimate> estimateLibraryRebuild({
    int tracksPerShard = LibrarySyncStore.defaultTracksPerShard,
    bool withCovers = true,
  }) async {
    final store = await _libraryStore();
    return store.estimate(
      tracks: _library.tracks,
      tracksPerShard: tracksPerShard,
      withCovers: withCovers,
    );
  }

  /// Shared Core FFI sync helper — resolves account, calls either
  /// [RustCoreService.syncTrigger] (incremental) or [RustCoreService.syncFull]
  /// (base-shard rebuild), then refreshes all Dart caches.
  ///
  /// Requires the configured sync destination to have `providerType == 'webdav'`
  /// (Core builds `WebDavDriver` from url/user/pass).
  Future<void> _runCoreSync(SyncOutcome outcome, {required bool full}) async {
    final dest = await syncDestination();
    if (dest == null) throw StateError('err.noWebdavAccount');
    final account = _accounts.accountById(dest);
    if (account == null) throw StateError('err.noWebdavAccount');
    if (account.providerType != 'webdav') {
      throw StateError(
        'Core sync requires providerType=webdav '
        '(got ${account.providerType}); choose a WebDAV sync destination',
      );
    }
    final password = await _accounts.passwordFor(account.id) ?? '';
    final remoteDir = _settings.syncRemoteRoot;
    _progress(L10nHost.current.progressReadingCloudIndex, 0.4);
    final result = full
        ? RustCoreService.syncFull(
            webdavUrl: account.url,
            username: account.username,
            password: password,
            remoteDir: remoteDir,
          )
        : RustCoreService.syncTrigger(
            webdavUrl: account.url,
            username: account.username,
            password: password,
            remoteDir: remoteDir,
          );
    if (result == null) {
      throw StateError('Core FFI unavailable — cannot run Core sync');
    }
    if (result.startsWith('error:')) {
      throw StateError('Core sync failed: $result');
    }
    // Core mutated rusqlite; refresh Dart caches.
    await _library.refresh();
    await _manga?.reload();
    outcome.step('Core ${full ? "syncFull" : "syncTrigger"} ok: $result');
  }

  /// The binary store, bound to the configured library sync root.
  Future<LibrarySyncStore> _libraryStore() async => LibrarySyncStore(
    webDav: _webDav,
    covers: _library.covers,
    settings: _settings,
  );
  // --- Manga library (incremental / rebuild), mirrors music --------------

  /// Manga fragments on the cloud (for the 建议重建 hint).
  int mangaCloudFragmentCount = 0;
  int mangaCloudFragmentBytes = 0;

  bool get hasMangaSync => _manga != null && _db != null && _cache != null;

  MangaSyncStore _mangaStore() => MangaSyncStore(
    webDav: _webDav,
    settings: _settings,
    coverFile: _cache!.mangaCoverFile,
  );

  /// Incremental manga sync via Core FFI ([RustCoreService.syncTrigger]).
  /// Core is the sole sync authority: it adopts cloud rows, applies peer
  /// tombstones, and publishes local deltas/tombstones for both the manga and
  /// music shard engines in one `run_sync_all` call.
  Future<SyncOutcome> syncMangaIncremental() async {
    final outcome = SyncOutcome(direction: 'sync');
    if (!hasMangaSync) return outcome;
    await _run(outcome, () async {
      await _runCoreSync(outcome, full: false);
    });
    return outcome;
  }

  /// Rebuild the cloud manga library via Core FFI ([RustCoreService.syncFull]).
  /// Core is the sole sync authority: materialises all local rows as the new
  /// base, clears all tombstones and cursors. Both manga and music shard engines
  /// rebuild in one `run_sync_full` call.
  Future<SyncOutcome> syncMangaFull({
    int perShard = MangaSyncStore.defaultMangasPerShard,
    bool withCovers = true,
  }) async {
    final outcome = SyncOutcome(direction: 'push');
    if (!hasMangaSync) return outcome;
    await _run(outcome, () async {
      await _runCoreSync(outcome, full: true);
    });
    return outcome;
  }

  Future<LibraryAudit> auditMangaLibrary() async {
    final dest = await syncDestination();
    if (dest == null) throw StateError('err.noWebdavAccount');
    return _mangaStore().audit(dest);
  }

  Future<int> tidyMangaOrphans(LibraryAudit audit) async {
    final dest = await syncDestination();
    if (dest == null) throw StateError('err.noWebdavAccount');
    return _mangaStore().deleteOrphans(dest, audit);
  }

  Future<RebuildEstimate> estimateMangaRebuild({
    int perShard = MangaSyncStore.defaultMangasPerShard,
    bool withCovers = true,
  }) async {
    return _mangaStore().estimate(
      rows: await _manga!.syncRows(),
      perShard: perShard,
      withCovers: withCovers,
    );
  }

  // --- User folders (whole-snapshot sync) -------------------------------

  static const _foldersLastSyncKey = 'folders_last_sync_at:';
  static const _foldersCloudSeenKey = 'folders_cloud_seen:';

  /// Sync the user-folder overlay with `library/folders/folders.json`
  /// (rules: [planFolderSync]).
  Future<SyncOutcome> syncUserFolders() async {
    final outcome = SyncOutcome(direction: 'sync');
    final folders = _folders;
    final db = _db;
    if (folders == null || db == null) return outcome;
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      _progress(L10nHost.current.progressSyncingFolders, 0.5);
      final dir = _settings.foldersRemotePath;
      final path = '$dir$userFoldersFileName';
      UserFoldersDoc? cloud;
      try {
        cloud = decodeUserFoldersDoc(await _webDav.readAsBytes(dest, path));
      } catch (e) {
        if (!LibrarySyncStore.isMissingError(e.toString().toLowerCase())) {
          rethrow;
        }
      }
      final snapshot = await db.exportUserFoldersSnapshot();
      final localEmpty =
          (snapshot['folders'] as List).isEmpty &&
          (snapshot['items'] as List).isEmpty;
      final action = planFolderSync(
        localChangedAtMs:
            int.tryParse(
              await db.loadMeta(LibraryDatabase.foldersChangedAtKey) ?? '',
            ) ??
            0,
        lastSyncAtMs:
            int.tryParse(
              await db.loadMeta('$_foldersLastSyncKey$dest') ?? '',
            ) ??
            0,
        cloudUpdatedAt: cloud?.updatedAt,
        lastSeenCloudUpdatedAt: await db.loadMeta('$_foldersCloudSeenKey$dest'),
        localEmpty: localEmpty,
      );
      var seen = cloud?.updatedAt;
      switch (action) {
        case FolderSyncAction.none:
          outcome.step(L10nHost.current.stepFoldersUnchanged);
        case FolderSyncAction.pull:
          await db.importUserFoldersSnapshot(cloud!.snapshot);
          await folders.reload();
          outcome.step(L10nHost.current.stepFoldersPulled);
        case FolderSyncAction.push:
          final stamp = DateTime.now().toUtc().toIso8601String();
          await _webDav.ensureDirectory(dest, dir);
          await _webDav.writeBytes(
            dest,
            path,
            encodeUserFoldersDoc(
              snapshot: snapshot,
              updatedAt: stamp,
              deviceId: _settings.deviceId,
            ),
          );
          seen = stamp;
          outcome.step(L10nHost.current.stepFoldersPushed);
      }
      if (action != FolderSyncAction.none) {
        await db.saveMeta(
          '$_foldersLastSyncKey$dest',
          '${DateTime.now().millisecondsSinceEpoch}',
        );
        if (seen != null) await db.saveMeta('$_foldersCloudSeenKey$dest', seen);
      }
    });
    return outcome;
  }

  // --- Whole-app backup -------------------------------------------------

  /// Back up **everything** (credentials + library + playlists) into
  /// `<远端路径>backup/` on the configured 网盘.
  ///
  /// Neither the server nor the directory is asked for here any more: the single
  /// 远端路径 栏 owns both, so 备份 can never drift away from the rest.
  Future<SyncOutcome> backupTo({required String passphrase}) async {
    final outcome = SyncOutcome(direction: 'backup');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      _progress(L10nHost.current.progressPackingBackup, 0.4);
      await _backup.uploadBackup(
        accountId: dest,
        passphrase: passphrase,
        remoteDir: _settings.backupRemotePath,
      );
      outcome.step(_backup.lastMessage ?? L10nHost.current.stepBackupDone);
    });
    return outcome;
  }

  /// List the archives under `<远端路径>backup/`.
  Future<List<String>> listBackups() async {
    final dest = await syncDestination();
    if (dest == null) return const [];
    return _backup.listBackups(
      accountId: dest,
      remoteDir: _settings.backupRemotePath,
    );
  }

  /// Download a whole-app archive from `<远端路径>backup/` without restoring.
  ///
  /// UI probes the passphrase on these bytes before calling
  /// [restoreFromBytes].
  Future<Uint8List> downloadBackup({String? fileName}) async {
    final dest = await syncDestination();
    if (dest == null) throw StateError('err.noWebdavAccount');
    return _backup.downloadBackupBytes(
      accountId: dest,
      remoteDir: _settings.backupRemotePath,
      fileName: fileName,
    );
  }

  /// Restore a whole-app archive from `<远端路径>backup/`.
  ///
  /// Prefer downloading with [downloadBackup], probing the passphrase, then
  /// [restoreFromBytes] when the UI needs a pre-check dialog.
  Future<SyncOutcome> restoreFrom({
    required String passphrase,
    String? fileName,
  }) async {
    final outcome = SyncOutcome(direction: 'restore');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');
      _progress(L10nHost.current.progressDownloadingRestore, 0.5);
      await _backup.restoreFromWebDav(
        accountId: dest,
        passphrase: passphrase,
        remoteDir: _settings.backupRemotePath,
        fileName: fileName,
      );
      outcome.step(_backup.lastMessage ?? L10nHost.current.stepRestoreDone);
      await _accounts.init();
      await _library.refresh();
      await _playlists.refresh();
      await _manga?.reload();
      await _folders?.reload();
    });
    return outcome;
  }

  /// Restore already-downloaded archive bytes (after passphrase pre-check).
  Future<SyncOutcome> restoreFromBytes({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    final outcome = SyncOutcome(direction: 'restore');
    await _run(outcome, () async {
      _progress(L10nHost.current.progressUnpackingRestore, 0.5);
      await _backup.restoreFromBytes(data: bytes, passphrase: passphrase);
      outcome.step(_backup.lastMessage ?? L10nHost.current.stepRestoreDone);
      await _accounts.init();
      await _library.refresh();
      await _playlists.refresh();
      await _manga?.reload();
      await _folders?.reload();
    });
    return outcome;
  }

  // --- Local export / import -------------------------------------------

  /// Export the whole-app backup into the Android Downloads folder.
  ///
  /// [readableJson] writes the plain-JSON form instead of the binary container:
  /// human-inspectable, cover bytes omitted, meant for troubleshooting and for
  /// moving data by hand.
  Future<ExportResult> exportToDownloads({
    required String passphrase,
    String? fileName,
    bool readableJson = false,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    _progress(L10nHost.current.progressGeneratingBackup, 0.2);
    try {
      final bytes = readableJson
          ? await _backup.buildJsonExport(passphrase: passphrase)
          // Phase D: binary export must use Core authority (not sqflite legacy).
          : await _backup.createArchiveBytes(passphrase: passphrase);
      _progress(L10nHost.current.progressWritingDownloads, 0.8);
      final name =
          fileName ??
          (readableJson
              ? '$localExportPrefix-${utcStamp()}.json'
              : '$localExportPrefix-${utcStamp()}.wdmm');
      final tmp = await PlatformExportService.writeTempExportFile(name, bytes);
      final destination = _destination;
      final ExportResult result;
      if (destination != null) {
        result = await destination.save(
          sourcePath: tmp.path,
          fileName: name,
          mimeType: readableJson
              ? 'application/json'
              : 'application/octet-stream',
          mediaStoreSubdir: localExportSubdir,
          retryOnFallback: true,
        );
      } else {
        result = await _export.saveToDownloads(
          sourcePath: tmp.path,
          fileName: name,
          mimeType: readableJson
              ? 'application/json'
              : 'application/octet-stream',
          subdir: localExportSubdir,
        );
      }
      if (result.ok) {
        final l10n = L10nHost.current;
        var locationDesc = PlatformExportService.describeLocation(
          result.location,
          l10n,
        );
        if (result.fellBack) {
          locationDesc = '$locationDesc\n${l10n.exportFellBackNotice}';
        }
        lastMessage = l10n.exportedTo(result.fileName, locationDesc);
      } else {
        lastError = result.error;
      }
      return result;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<SyncOutcome> importLocalArchive({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    final outcome = SyncOutcome(direction: 'import');
    await _run(outcome, () async {
      _progress(L10nHost.current.progressUnpackingRestore, 0.3);
      await _backup.restoreFromBytes(data: bytes, passphrase: passphrase);
      outcome.step(
        _backup.lastMessage ?? L10nHost.current.stepLocalBackupImported,
      );
      await _accounts.init();
      await _library.refresh();
      await _playlists.refresh();
      await _manga?.reload();
      await _folders?.reload();
      _progress(L10nHost.current.progressDone, 1);
    });
    return outcome;
  }

  Future<SyncOutcome> importLocalFile({
    required File file,
    required String passphrase,
  }) async {
    final bytes = await file.readAsBytes();
    return importLocalArchive(bytes: bytes, passphrase: passphrase);
  }

  Future<SyncOutcome> importLocalBase64({
    required String base64Text,
    required String passphrase,
  }) {
    return importLocalArchive(
      bytes: Uint8List.fromList(base64Decode(base64Text.trim())),
      passphrase: passphrase,
    );
  }
}
