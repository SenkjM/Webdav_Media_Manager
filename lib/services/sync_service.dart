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

  /// Incremental library sync.
  ///
  /// Only locally-changed rows travel (one small binary `seg-*.wdmm` per pass) and
  /// only new tombstones are appended as `del-*.wdmm`. When nothing changed the
  /// pass uploads **zero** bytes — not even the manifest.
  Future<SyncOutcome> syncLibraryIncremental() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');

      // Core-first (flagged): exclusive path — no silent Dart fallback.
      if (kRustLibrarySyncEnabled) {
        await _syncLibraryViaCore(outcome, destAccountId: dest);
        return;
      }

      final store = await _libraryStore();

      _progress(L10nHost.current.progressReadingCloudIndex, 0.3);
      final manifest = await store.readManifest(dest);
      cloudFragmentCount = manifest.fragmentCount;
      cloudFragmentBytes = manifest.fragmentBytes;

      // Cursor: parts we already consumed are not downloaded again, and `lastSeq`
      // is the rev up to which the cloud already knows this device's rows.
      final cursorKey = '${LibraryDatabase.musicCursorPrefix}$dest';
      final cursor = await _library.loadSyncCursor(cursorKey);
      if (manifest.baseUpTo > cursor.baseUpTo) {
        // A rebuild replaced the base: every part name changed, so read afresh.
        await store.readCloud(dest, manifest);
      } else {
        await store.readCloud(
          dest,
          manifest,
          skipFiles: cursor.parts.keys.toSet(),
        );
      }
      final cloudTracks = store.lastCloud.tracks;
      final cloudTombstoned = store.lastCloud.tombstonedKeys;
      final remoteByKey = {
        for (final t in cloudTracks)
          trackIdentityKey(t.sourceName, t.remotePath): t,
      };

      final local = _library.tracks;
      final toAdopt = <LibraryTrack>[];
      final toUpload = <LibraryTrack>[];
      for (final t in local) {
        final rev = t.rev ?? 0;
        final r = remoteByKey[trackIdentityKey(t.sourceName, t.remotePath)];
        if (r != null) {
          if (rev > (r.rev ?? 0)) toUpload.add(t);
          continue;
        }
        // Not among the freshly read parts: either the cloud already had it (we
        // adopted it earlier, so its rev is <= our cursor) or it is new here.
        if (rev > cursor.lastSeq &&
            !(cursor.parts.isNotEmpty && rev <= cursor.baseUpTo)) {
          toUpload.add(t);
        }
      }
      for (final r in cloudTracks) {
        if (cloudTombstoned.contains(
          trackIdentityKey(r.sourceName, r.remotePath),
        )) {
          continue;
        }
        final l = _library.find(r.sourceName, r.remotePath);
        if (l == null || (r.rev ?? 0) > (l.rev ?? 0)) toAdopt.add(r);
      }

      if (toAdopt.isNotEmpty) {
        _progress(
          L10nHost.current.progressAdoptingCloudTracks(toAdopt.length),
          0.5,
        );
        await _library.upsertTracks(toAdopt);
        for (final t in toAdopt) {
          _library.observeRev(t.rev ?? 0);
        }
      }

      // Deletions this device made and has not published yet.
      final pendingTombs = await _library.pendingTombstones();
      // A row that was re-downloaded after the deletion must not be published as
      // deleted again.
      final resurrected = <int>{};
      for (final row in pendingTombs) {
        final path = row['remote_path'] as String? ?? '';
        final source = row['source_name'] as String? ?? '';
        final live = _library.find(source, path);
        if (live != null &&
            (live.rev ?? 0) > ((row['rev'] as num?)?.toInt() ?? 0)) {
          resurrected.add((row['rev'] as num?)?.toInt() ?? 0);
        }
      }
      final toPublishTombs = [
        for (final row in pendingTombs)
          if (!resurrected.contains((row['rev'] as num?)?.toInt() ?? 0)) row,
      ];
      if (resurrected.isNotEmpty) {
        await _library.clearTombstones(resurrected);
      }

      if (toUpload.isEmpty && toPublishTombs.isEmpty) {
        // Nothing changed here: still record the parts we just consumed so the
        // next pass can skip them, then upload nothing at all.
        await _saveLibraryCursor(
          cursorKey: cursorKey,
          manifest: await store.readManifest(dest),
          cursor: cursor,
          readParts: store.lastReadParts,
          highestLocalRev: toAdopt.fold<int>(
            cursor.lastSeq,
            (a, t) => (t.rev ?? 0) > a ? (t.rev ?? 0) : a,
          ),
        );
        outcome.step(L10nHost.current.stepIncrementalNoChange);
        return;
      }

      if (toPublishTombs.isNotEmpty) {
        _progress(
          L10nHost.current.progressUploadingTombstones(toPublishTombs.length),
          0.7,
        );
        final m = await store.appendTombstones(
          destAccountId: dest,
          tombstones: toPublishTombs,
        );
        await _library.markTombstonesPushed({
          for (final row in toPublishTombs) (row['rev'] as num?)?.toInt() ?? 0,
        });
        cloudFragmentCount = m.fragmentCount;
        cloudFragmentBytes = m.fragmentBytes;
      }
      if (toUpload.isNotEmpty) {
        _progress(
          L10nHost.current.progressAppendingSegments(toUpload.length),
          0.85,
        );
        final m = await store.appendDelta(
          destAccountId: dest,
          changed: toUpload,
        );
        cloudFragmentCount = m.fragmentCount;
        cloudFragmentBytes = m.fragmentBytes;
      }
      await _saveLibraryCursor(
        cursorKey: cursorKey,
        manifest: await store.readManifest(dest),
        cursor: cursor,
        readParts: store.lastReadParts,
        highestLocalRev: toUpload.fold<int>(
          cursor.lastSeq,
          (a, t) => (t.rev ?? 0) > a ? (t.rev ?? 0) : a,
        ),
      );
      await _library.refresh();
      outcome.step(
        L10nHost.current.stepIncrementalUploaded(
          toAdopt.length,
          toPublishTombs.length,
          toUpload.length,
        ),
      );
    });
    return outcome;
  }

  /// Full library sync = rebuild: write the whole local library as fixed-size
  /// binary base shards, fold away every old part and **materialise deletions**
  /// (tombstoned rows are simply absent).
  Future<SyncOutcome> syncLibraryFull({
    int tracksPerShard = LibrarySyncStore.defaultTracksPerShard,
    bool withCovers = true,
  }) async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');

      // `wdmm_sync_trigger` / `run_sync_all` only runs LibrarySyncEngine
      // incremental — there is no Core sync_full FFI yet. Keep Dart rebuild
      // even when [kRustLibrarySyncEnabled] is on (documented leftover; not a
      // silent half-cut of incremental).
      if (kRustLibrarySyncEnabled) {
        outcome.warn(
          'Core library sync_full FFI not exposed; full rebuild still uses Dart LibrarySyncStore',
        );
      }

      final store = await _libraryStore();

      _progress(L10nHost.current.progressReadingCloudIndex, 0.2);
      final manifest = await store.readManifest(dest);
      final cloud = await store.readCloud(dest, manifest);
      // Adopt cloud rows this device is missing, but never resurrect a row this
      // device deleted (that is exactly what the tombstone is for).
      final adopt = <LibraryTrack>[];
      for (final r in cloud.tracks) {
        if (cloud.tombstonedKeys.contains(
          trackIdentityKey(r.sourceName, r.remotePath),
        )) {
          continue;
        }
        final l = _library.find(r.sourceName, r.remotePath);
        if (l == null || (r.rev ?? 0) > (l.rev ?? 0)) adopt.add(r);
      }
      if (adopt.isNotEmpty) {
        await _library.upsertTracks(adopt);
        for (final t in adopt) {
          _library.observeRev(t.rev ?? 0);
        }
      }

      _progress(L10nHost.current.progressUploadingFullShards, 0.6);
      final written = await store.rebuild(
        destAccountId: dest,
        tracks: _library.tracks,
        tracksPerShard: tracksPerShard,
        withCovers: withCovers,
      );
      cloudFragmentCount = written.fragmentCount;
      cloudFragmentBytes = written.fragmentBytes;
      // Everything at or below the new base is materialised; those tombstones
      // have done their job.
      await _library.purgeTombstonesUpTo(written.baseUpTo);
      // 硬约束：重建之后本地不该再有任何墓碑。行已经不在了的先静默清掉；
      // 还清不掉的说明活行与墓碑同时存在，那是真异常，交给用户看见。
      final clearedDead = await _library.clearDeadTombstones();
      final leftoverTombs = await _library.allTombstones();
      if (leftoverTombs.isNotEmpty) {
        outcome.warn(
          L10nHost.current.warnLeftoverTombstones(leftoverTombs.length),
        );
      } else if (clearedDead > 0) {
        outcome.step(L10nHost.current.stepClearedDeadTombstones(clearedDead));
      }
      // Every part name changed; the cursor is meaningless now.
      await _library.clearSyncCursor();
      await _library.refresh();
      outcome.step(
        L10nHost.current.stepRebuildDone(
          _library.tracks.length,
          written.baseUpTo,
          written.shards.length,
        ),
      );
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

  /// Advance the per-remote cursor: every part we read (plus the ones this pass
  /// published) is recorded, and `lastSeq` becomes the highest rev we now know.
  Future<void> _saveLibraryCursor({
    required String cursorKey,
    required LibraryManifest manifest,
    required ({int lastSeq, int baseUpTo, Map<String, int> parts}) cursor,
    required Set<String> readParts,
    required int highestLocalRev,
  }) async {
    final parts = <String, int>{...cursor.parts};
    for (final name in readParts) {
      parts[name] = manifest.segments
          .where((s) => s.file == name)
          .map((s) => s.to)
          .followedBy(
            manifest.tombstones.where((t) => t.file == name).map((t) => t.to),
          )
          .followedBy([0])
          .first;
    }
    for (final s in [...manifest.segments, ...manifest.tombstones]) {
      if (parts.containsKey(s.file)) continue;
      // Parts published by this very pass are known to us by construction.
      if (readParts.isEmpty && s.to <= highestLocalRev) continue;
      if (s.to <= highestLocalRev) parts[s.file] = s.to;
    }
    var lastSeq = highestLocalRev;
    for (final rev in parts.values) {
      if (rev > lastSeq) lastSeq = rev;
    }
    if (manifest.baseUpTo > lastSeq) lastSeq = manifest.baseUpTo;
    await _library.saveSyncCursor(
      remoteKey: cursorKey,
      lastSeq: lastSeq,
      baseUpTo: manifest.baseUpTo,
      parts: parts,
    );
  }


  /// Core music-library cloud sync via [RustCoreService.syncTrigger].
  ///
  /// Only used when [kRustLibrarySyncEnabled] is true. Requires a WebDAV
  /// destination (FFI constructs `WebDavDriver`). Also runs Core credential +
  /// playlist engines (same as Desktop Settings "Sync now").
  Future<void> _syncLibraryViaCore(
    SyncOutcome outcome, {
    required String destAccountId,
  }) async {
    final account = _accounts.accountById(destAccountId);
    if (account == null) {
      throw StateError('err.noWebdavAccount');
    }
    if (account.providerType != 'webdav') {
      throw StateError(
        'Core library sync requires providerType=webdav '
        '(got ${account.providerType}); disable kRustLibrarySyncEnabled '
        'or choose a WebDAV sync destination',
      );
    }
    final password = await _accounts.passwordFor(account.id) ?? '';
    final remoteDir = _settings.syncRemoteRoot;
    _progress(L10nHost.current.progressReadingCloudIndex, 0.4);
    final result = RustCoreService.syncTrigger(
      webdavUrl: account.url,
      username: account.username,
      password: password,
      remoteDir: remoteDir,
    );
    if (result == null) {
      throw StateError('Core FFI unavailable — cannot sync library via Core');
    }
    if (result.startsWith('error:')) {
      throw StateError('Core library sync failed: $result');
    }
    // Core mutated rusqlite; refresh Dart LibraryService cache.
    await _library.refresh();
    outcome.step('Core syncTrigger ok: $result');
  }

  /// Core manga-library cloud sync via [RustCoreService.syncTrigger].
  ///
  /// Only used when [kRustMangaLibrarySyncEnabled] is true. Delegates to the
  /// same [RustCoreService.syncTrigger] call as [_syncLibraryViaCore] —
  /// `run_sync_all` wires both the music and manga shard engines.
  /// Requires a WebDAV destination (FFI constructs `WebDavDriver`).
  Future<void> _syncMangaViaCore(
    SyncOutcome outcome, {
    required String destAccountId,
  }) async {
    final account = _accounts.accountById(destAccountId);
    if (account == null) {
      throw StateError('err.noWebdavAccount');
    }
    if (account.providerType != 'webdav') {
      throw StateError(
        'Core manga sync requires providerType=webdav '
        '(got ${account.providerType}); disable kRustMangaLibrarySyncEnabled '
        'or choose a WebDAV sync destination',
      );
    }
    final password = await _accounts.passwordFor(account.id) ?? '';
    final remoteDir = _settings.syncRemoteRoot;
    _progress(L10nHost.current.progressReadingCloudMangaIndex, 0.4);
    final result = RustCoreService.syncTrigger(
      webdavUrl: account.url,
      username: account.username,
      password: password,
      remoteDir: remoteDir,
    );
    if (result == null) {
      throw StateError('Core FFI unavailable — cannot sync manga library via Core');
    }
    if (result.startsWith('error:')) {
      throw StateError('Core manga sync failed: $result');
    }
    outcome.step('Core syncTrigger ok (manga): $result');
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

  /// Incremental manga sync: adopt cloud rows, publish local tombstones and
  /// changed rows (covers included, like music), then merge reading progress.
  Future<SyncOutcome> syncMangaIncremental() async {
    final outcome = SyncOutcome(direction: 'sync');
    if (!hasMangaSync) return outcome;
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');

      // Core-first (flagged): exclusive path — no silent Dart fallback.
      if (kRustMangaLibrarySyncEnabled) {
        await _syncMangaViaCore(outcome, destAccountId: dest);
        // Core mutated rusqlite; refresh Dart manga cache. No obvious
        // separate "reload manifest" beyond [MangaLibraryService.reload].
        await _manga?.reload();
        return;
      }

      final manga = _manga!;
      final db = _db!;
      final store = _mangaStore();
      _progress(L10nHost.current.progressReadingCloudMangaIndex, 0.3);
      final manifest = await store.readManifest(dest);
      mangaCloudFragmentCount = manifest.fragmentCount;
      mangaCloudFragmentBytes = manifest.fragmentBytes;
      final cursorKey = '${LibraryDatabase.mangaCursorPrefix}$dest';
      final cursor = await _library.loadSyncCursor(cursorKey);
      if (manifest.baseUpTo > cursor.baseUpTo) {
        await store.readCloud(dest, manifest);
      } else {
        await store.readCloud(
          dest,
          manifest,
          skipFiles: cursor.parts.keys.toSet(),
        );
      }
      final cloudRows = store.lastCloud.rows;
      final cloudTombstoned = store.lastCloud.tombstonedKeys;
      final remoteByKey = {for (final r in cloudRows) r.key: r};

      final local = await manga.syncRows();
      final localByKey = {for (final r in local) r.key: r};
      final toUpload = <MangaSyncRow>[];
      for (final r in local) {
        final remote = remoteByKey[r.key];
        if (remote != null) {
          if (r.rev > remote.rev) toUpload.add(r);
          continue;
        }
        if (r.rev > cursor.lastSeq &&
            !(cursor.parts.isNotEmpty && r.rev <= cursor.baseUpTo)) {
          toUpload.add(r);
        }
      }
      final toAdopt = <MangaSyncRow>[
        for (final r in cloudRows)
          if (!cloudTombstoned.contains(r.key) &&
              (localByKey[r.key] == null || r.rev > localByKey[r.key]!.rev))
            r,
      ];
      if (toAdopt.isNotEmpty) {
        _progress(
          L10nHost.current.progressAdoptingCloudMangas(toAdopt.length),
          0.5,
        );
        await manga.adoptCloudRows(toAdopt);
        final cache = _cache;
        if (cache != null) {
          for (final row in toAdopt) {
            final blob = store.lastCoverBlobs[row.manga.id];
            if (blob == null || blob.isEmpty) continue;
            try {
              await replaceMangaCoverBytes(
                cache: cache,
                mangaId: row.manga.id,
                bytes: blob,
              );
            } catch (e) {
              debugPrint('manga cover replace failed');
            }
          }
        }
        for (final r in toAdopt) {
          _library.observeRev(r.rev);
        }
      }

      final pending = await db.unpushedMangaTombstones();
      final resurrected = <int>{};
      for (final row in pending) {
        final live =
            localByKey[(row['sync_key'] as String?) ??
                mangaSyncKey(
                  row['source_name'] as String? ?? '',
                  row['remote_path'] as String? ?? '',
                )];
        final rev = (row['rev'] as num?)?.toInt() ?? 0;
        if (live != null && live.rev > rev) resurrected.add(rev);
      }
      final toPublish = [
        for (final row in pending)
          if (!resurrected.contains((row['rev'] as num?)?.toInt() ?? 0)) row,
      ];
      for (final row in pending) {
        if (resurrected.contains((row['rev'] as num?)?.toInt() ?? 0)) {
          await db.clearMangaTombstone(
            (row['sync_key'] as String?) ??
                mangaSyncKey(
                  row['source_name'] as String? ?? '',
                  row['remote_path'] as String? ?? '',
                ),
          );
        }
      }
      if (toPublish.isNotEmpty) {
        _progress(
          L10nHost.current.progressUploadingTombstones(toPublish.length),
          0.65,
        );
        final m = await store.appendTombstones(
          dest: dest,
          tombstones: toPublish,
        );
        await db.markMangaTombstonesPushed({
          for (final row in toPublish) (row['rev'] as num?)?.toInt() ?? 0,
        });
        mangaCloudFragmentCount = m.fragmentCount;
        mangaCloudFragmentBytes = m.fragmentBytes;
      }
      if (toUpload.isNotEmpty) {
        _progress(
          L10nHost.current.progressAppendingMangaSegments(toUpload.length),
          0.8,
        );
        final m = await store.appendDelta(dest: dest, changed: toUpload);
        mangaCloudFragmentCount = m.fragmentCount;
        mangaCloudFragmentBytes = m.fragmentBytes;
      }
      await _saveCursorFor(
        cursorKey: cursorKey,
        manifest: await store.readManifest(dest),
        cursor: cursor,
        readParts: store.lastReadParts,
        highestLocalRev: [
          ...toUpload,
          ...toAdopt,
        ].fold<int>(cursor.lastSeq, (a, r) => r.rev > a ? r.rev : a),
      );

      _progress(L10nHost.current.progressSyncingMangaProgress, 0.92);
      final progress = await _syncMangaProgress(dest, store);
      outcome.step(
        // gen-l10n orders placeholders alphabetically:
        // adopted, progress, tombs, uploaded.
        L10nHost.current.stepMangaIncremental(
          toAdopt.length,
          progress,
          toPublish.length,
          toUpload.length,
        ),
      );
    });
    return outcome;
  }

  /// Merge reading progress with `progress.json`. Returns entries changed on
  /// either side.
  Future<int> _syncMangaProgress(String dest, MangaSyncStore store) async {
    final manga = _manga!;
    final merge = mergeMangaProgress(
      local: await manga.allProgress(),
      cloud: await store.readProgress(dest),
    );
    await manga.applyProgress(merge.toApplyLocally);
    if (merge.cloudNeedsUpdate) {
      await store.writeProgress(dest, merge.merged.values);
    }
    return merge.toApplyLocally.length + (merge.cloudNeedsUpdate ? 1 : 0);
  }

  /// Rebuild the cloud manga library from this device (materialises deletes).
  Future<SyncOutcome> syncMangaFull({
    int perShard = MangaSyncStore.defaultMangasPerShard,
    bool withCovers = true,
  }) async {
    final outcome = SyncOutcome(direction: 'push');
    if (!hasMangaSync) return outcome;
    await _run(outcome, () async {
      final dest = await syncDestination();
      if (dest == null) throw StateError('err.noWebdavAccount');

      // `wdmm_sync_trigger` / `run_sync_all` only runs MangaSyncEngine
      // incremental — there is no Core sync_full FFI for manga yet. Keep Dart
      // rebuild even when [kRustMangaLibrarySyncEnabled] is on (documented
      // leftover; not a silent half-cut of incremental).
      if (kRustMangaLibrarySyncEnabled) {
        outcome.warn(
          'Core manga sync_full FFI not exposed; full rebuild still uses Dart MangaSyncStore',
        );
      }
      final manga = _manga!;
      final db = _db!;
      final store = _mangaStore();
      _progress(L10nHost.current.progressReadingCloudMangaIndex, 0.2);
      final cloud = await store.readCloud(dest, await store.readManifest(dest));
      final local = {for (final r in await manga.syncRows()) r.key: r};
      final adopt = [
        for (final r in cloud.rows)
          if (!cloud.tombstonedKeys.contains(r.key) &&
              (local[r.key] == null || r.rev > local[r.key]!.rev))
            r,
      ];
      if (adopt.isNotEmpty) {
        await manga.adoptCloudRows(adopt);
        for (final r in adopt) {
          _library.observeRev(r.rev);
        }
      }
      _progress(L10nHost.current.progressUploadingFullMangaShards, 0.6);
      final written = await store.rebuild(
        dest: dest,
        rows: await manga.syncRows(),
        perShard: perShard,
        withCovers: withCovers,
      );
      mangaCloudFragmentCount = written.fragmentCount;
      mangaCloudFragmentBytes = written.fragmentBytes;
      // Every tombstone is materialised by the new base.
      for (final row in await db.allMangaTombstones()) {
        await db.clearMangaTombstone(
          (row['sync_key'] as String?) ??
              mangaSyncKey(
                row['source_name'] as String? ?? '',
                row['remote_path'] as String? ?? '',
              ),
        );
      }
      await db.clearSyncState(prefix: LibraryDatabase.mangaCursorPrefix);
      await _syncMangaProgress(dest, store);
      outcome.step(
        L10nHost.current.stepMangaRebuildDone(
          manga.count,
          written.shards.length,
        ),
      );
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

  /// Shared cursor bookkeeping (music + manga use the same rules).
  Future<void> _saveCursorFor({
    required String cursorKey,
    required LibraryManifest manifest,
    required ({int lastSeq, int baseUpTo, Map<String, int> parts}) cursor,
    required Set<String> readParts,
    required int highestLocalRev,
  }) => _saveLibraryCursor(
    cursorKey: cursorKey,
    manifest: manifest,
    cursor: cursor,
    readParts: readParts,
    highestLocalRev: highestLocalRev,
  );

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
