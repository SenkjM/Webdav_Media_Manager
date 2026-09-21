import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import '../utils/backup_paths.dart';
import '../utils/track_identity.dart';
import 'accounts_service.dart';
import 'backup_service.dart';
import 'credential_vault_service.dart';
import 'library_service.dart';
import 'library_sync_store.dart';
import 'playlist_service.dart';
import 'platform_export_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

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
    if (!ok) return '操作失败：${error ?? '未知错误'}';
    final body = steps.isEmpty ? '无变更' : steps.join('；');
    final warn = warnings.isEmpty ? '' : '\n注意：${warnings.join('；')}';
    return '$body$warn';
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
/// | 歌单 | **真同步**：双向 M3U8，`updatedAt` 最后写入胜出；改动即时上传，启动/切换账号/定期拉取 |
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
  }) : _accounts = accounts,
       _settings = settings,
       _webDav = webDav,
       _vault = vault,
       _library = library,
       _playlists = playlists,
       _backup = backup,
       _export = export ?? const PlatformExportService();

  final AccountsService _accounts;
  final SettingsService _settings;
  final WebDavService _webDav;
  final CredentialVaultService _vault;
  final LibraryService _library;
  final PlaylistService _playlists;
  final BackupService _backup;
  final PlatformExportService _export;

  static const localExportSubdir = 'WebDAVMusic';
  static const localExportPrefix = 'wmp-sync';

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
  static const libraryFormat = 'webdav_music_player_library_index';
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
    final connectedId = _webDav.accountId;
    if (connectedId != null) {
      for (final a in _accounts.accounts) {
        if (a.id == connectedId) return a;
      }
    }
    return _accounts.activeAccount;
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
    _progress('准备中…', 0.02);
    notifyListeners();
    try {
      await body();
      _progress('完成', 1);
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
    final credentialsDest = await credentialsDestination();
    final playlistsDest = await playlistsDestination();
    if (credentialsDest == null && playlistsDest == null) return;
    final pass = _settings.vaultPassphrase;
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      if (credentialsDest != null) {
        if (pass.isEmpty) {
          outcome.step('凭证同步已跳过（未设置统一加密密钥）');
        } else {
          _progress('扫描云端凭证…', 0.3);
          try {
            final result = await _vault.pull(
              accountId: credentialsDest,
              passphrase: pass,
            );
            if (result != null) outcome.step(result.summary);
          } catch (e) {
            outcome.warn('凭证扫描跳过：$e');
          }
        }
      }
      if (playlistsDest != null) {
        _progress('扫描歌单…', 0.7);
        _playlists.configureSync(
          remotePath: _settings.playlistRemotePath,
          enabled: true,
          accountId: playlistsDest,
        );
        await _playlists.pullAndMergeFromWebDav();
        outcome.step('歌单已合并（${_playlists.playlists.length} 个）');
      }
    });
    lastAutoSyncAt = DateTime.now();
    lastAutoSyncSummary = outcome.message;
    notifyListeners();
  }

  // --- Credentials ------------------------------------------------------

  /// Credentials destination account (falls back to the active account).
  Future<String?> credentialsDestination() async =>
      _settings.credentialsAccountId ?? _accounts.activeAccountId;

  /// Playlists destination account (falls back to the active account).
  Future<String?> playlistsDestination() async =>
      _settings.playlistsAccountId ?? _accounts.activeAccountId;

  /// Music-library destination account (falls back to the active one).
  Future<String?> libraryDestination() async =>
      _settings.libraryAccountId ?? _accounts.activeAccountId;

  /// Upload local credentials to the configured destination.
  ///
  /// Encryption uses the user's own [SettingsService.vaultPassphrase], never the
  /// destination account's login password.
  Future<SyncOutcome> pushCredentials({String? passphrase}) async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      final dest = await credentialsDestination();
      if (dest == null) throw StateError('请先添加 WebDAV 账号');
      final pass = passphrase ?? _settings.vaultPassphrase;
      _progress('上传凭证…', 0.5);
      await _vault.push(accountId: dest, passphrase: pass);
      outcome.step('凭证已同步到云端（${_accounts.accounts.length} 个服务器）');
    });
    return outcome;
  }

  /// Download cloud credentials into this device. Passwords that cannot be
  /// decrypted are left empty rather than failing the whole operation.
  Future<SyncOutcome> pullCredentials({String? passphrase}) async {
    final outcome = SyncOutcome(direction: 'pull');
    await _run(outcome, () async {
      final dest = await credentialsDestination();
      if (dest == null) throw StateError('请先添加 WebDAV 账号');
      final pass = passphrase ?? _settings.vaultPassphrase;
      _progress('下载凭证…', 0.5);
      final result = await _vault.pull(accountId: dest, passphrase: pass);
      outcome.step(result?.summary ?? '云端暂无凭证文件');
      await _accounts.init();
    });
    return outcome;
  }

  // --- Playlists --------------------------------------------------------

  Future<SyncOutcome> syncPlaylistsNow() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final dest = await playlistsDestination();
      if (dest == null) throw StateError('请先添加 WebDAV 账号');
      _playlists.configureSync(
        remotePath: _settings.playlistRemotePath,
        enabled: true,
        accountId: dest,
      );
      _progress('合并歌单…', 0.5);
      await _playlists.pullAndMergeFromWebDav();
      for (final pl in _playlists.playlists) {
        await _playlists.uploadPlaylist(pl);
      }
      outcome.step('歌单已同步（${_playlists.playlists.length} 个）');
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
  /// Only locally-changed rows travel (one small binary `seg-*.wmp` per pass) and
  /// only new tombstones are appended as `del-*.wmp`. When nothing changed the
  /// pass uploads **zero** bytes — not even the manifest.
  Future<SyncOutcome> syncLibraryIncremental() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final dest = await libraryDestination();
      if (dest == null) throw StateError('请先添加 WebDAV 账号');
      final store = await _libraryStore();

      _progress('读取云端曲库索引…', 0.3);
      final manifest = await store.readManifest(dest);
      cloudFragmentCount = manifest.fragmentCount;
      cloudFragmentBytes = manifest.fragmentBytes;

      // Cursor: parts we already consumed are not downloaded again, and `lastSeq`
      // is the rev up to which the cloud already knows this device's rows.
      final cursorKey = 'library:$dest';
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
        _progress('采纳云端 ${toAdopt.length} 首…', 0.5);
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
        outcome.step('增量同步：无变化（未上传任何内容）');
        return;
      }

      if (toPublishTombs.isNotEmpty) {
        _progress('上传 ${toPublishTombs.length} 条删除记录…', 0.7);
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
        _progress('追加 ${toUpload.length} 首到云端增量分片…', 0.85);
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
        '增量同步：上传 ${toUpload.length} 首，采纳 ${toAdopt.length} 首，'
        '删除 ${toPublishTombs.length} 条',
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
      final dest = await libraryDestination();
      if (dest == null) throw StateError('请先添加 WebDAV 账号');
      final store = await _libraryStore();

      _progress('读取云端曲库索引…', 0.2);
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

      _progress('上传完整曲库分片…', 0.6);
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
      // Every part name changed; the cursor is meaningless now.
      await _library.clearSyncCursor();
      await _library.refresh();
      outcome.step(
        '重建完成：${written.shards.length} 个分片，'
        'base 覆盖到 rev ${written.baseUpTo}（本机 ${_library.tracks.length} 首）',
      );
    });
    return outcome;
  }

  /// Compare the cloud manifest with the directory's real contents.
  Future<LibraryAudit> auditLibrary() async {
    final dest = await libraryDestination();
    if (dest == null) throw StateError('请先添加 WebDAV 账号');
    final store = await _libraryStore();
    return store.audit(dest);
  }

  /// Delete the orphan files an audit found (best effort).
  Future<int> tidyLibraryOrphans(LibraryAudit audit) async {
    final dest = await libraryDestination();
    if (dest == null) throw StateError('请先添加 WebDAV 账号');
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

  /// The binary store, bound to the configured library sync root.
  Future<LibrarySyncStore> _libraryStore() async => LibrarySyncStore(
    webDav: _webDav,
    covers: _library.covers,
    settings: _settings,
  );
  // --- Whole-app backup -------------------------------------------------

  /// Back up **everything** (credentials + library + playlists) to the chosen
  /// server and directory. Nothing is scoped per site.
  Future<SyncOutcome> backupTo({
    required WebDavAccount destination,
    required String remoteDir,
    required String passphrase,
  }) async {
    final outcome = SyncOutcome(direction: 'backup');
    await _run(outcome, () async {
      _progress('打包凭证 / 音乐库 / 歌单…', 0.4);
      await _backup.uploadBackup(
        accountId: destination.id,
        passphrase: passphrase,
        remoteDir: remoteDir,
      );
      outcome.step(_backup.lastMessage ?? '备份完成');
      await _settings.setSyncAccount('backup', destination.id);
    });
    return outcome;
  }

  /// List archives available in [remoteDir] on [source].
  Future<List<String>> listBackups({
    required WebDavAccount source,
    required String remoteDir,
  }) {
    return _backup.listBackups(accountId: source.id, remoteDir: remoteDir);
  }

  /// Restore a whole-app archive from the chosen server and path.
  Future<SyncOutcome> restoreFrom({
    required WebDavAccount source,
    required String remoteDir,
    required String passphrase,
    String? fileName,
  }) async {
    final outcome = SyncOutcome(direction: 'restore');
    await _run(outcome, () async {
      _progress('下载并恢复…', 0.5);
      await _backup.restoreFromWebDav(
        accountId: source.id,
        passphrase: passphrase,
        remoteDir: remoteDir,
        fileName: fileName,
      );
      outcome.step(_backup.lastMessage ?? '恢复完成');
      await _accounts.init();
      await _library.refresh();
      await _playlists.refresh();
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
    _progress('生成备份…', 0.2);
    try {
      final bytes = readableJson
          ? await _backup.buildJsonExport(passphrase: passphrase)
          : await _backup.buildArchiveBytes(passphrase: passphrase);
      _progress('写入下载目录…', 0.8);
      final name =
          fileName ??
          (readableJson
              ? '$localExportPrefix-${backupFileNameNow()}.json'
              : '$localExportPrefix-${backupFileNameNow()}');
      final tmp = await PlatformExportService.writeTempExportFile(name, bytes);
      final result = await _export.saveToDownloads(
        sourcePath: tmp.path,
        fileName: name,
        mimeType: readableJson
            ? 'application/json'
            : 'application/octet-stream',
        subdir: localExportSubdir,
      );
      if (result.ok) {
        lastMessage = '已导出到${result.location}：${result.fileName}';
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
      _progress('解包并恢复…', 0.3);
      await _backup.restoreFromBytes(data: bytes, passphrase: passphrase);
      outcome.step(_backup.lastMessage ?? '本地备份已导入');
      await _accounts.init();
      await _library.refresh();
      await _playlists.refresh();
      _progress('完成', 1);
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
