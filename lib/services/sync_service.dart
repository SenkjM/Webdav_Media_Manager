import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import '../utils/backup_paths.dart';
import 'accounts_service.dart';
import 'backup_service.dart';
import 'credential_vault_service.dart';
import 'library_service.dart';
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
  })  : _accounts = accounts,
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

  /// Incremental library index: one JSON file per accountId under the sync root.
  static const librarySubdir = 'library/';
  static const libraryIndexName = 'library_index.json';

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

  String libraryIndexPath(String accountId) {
    final root = syncRoot.endsWith('/') ? syncRoot : '$syncRoot/';
    final safe = accountId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final short = safe.length <= 12 ? safe : safe.substring(0, 12);
    return '$root$librarySubdir$short/$libraryIndexName';
  }

  /// Authenticate against [account] (any server, not just the "library" one).
  Future<void> connectTo(WebDavAccount account) async {
    final pass = await _accounts.passwordFor(account.id) ?? '';
    _webDav.configure(
      accountId: account.id,
      url: account.url,
      username: account.username,
      password: pass,
    );
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
  /// when there is no account or no stored password.
  Future<void> autoScan({bool force = false}) async {
    if (busy) return;
    final account = targetAccount;
    if (account == null) return;
    final pass = await _accounts.passwordFor(account.id) ?? '';
    if (!force && pass.isEmpty) return;
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      await connectTo(account);
      _progress('扫描云端凭证…', 0.3);
      try {
        final result = await _vault.pull(passphrase: pass);
        if (result != null) outcome.step(result.summary);
      } catch (e) {
        outcome.warn('凭证扫描跳过：$e');
      }
      _progress('扫描歌单…', 0.7);
      _playlists.configureSync(
        remotePath: _settings.playlistRemotePath,
        enabled: true,
      );
      await _playlists.pullAndMergeFromWebDav();
      outcome.step('歌单已合并（${_playlists.playlists.length} 个）');
    });
    lastAutoSyncAt = DateTime.now();
    lastAutoSyncSummary = outcome.message;
    notifyListeners();
  }

  // --- Credentials ------------------------------------------------------

  /// Upload local credentials to the cloud.
  Future<SyncOutcome> pushCredentials() async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      await connectTo(account);
      final pass = await _accounts.passwordFor(account.id) ?? '';
      _progress('上传凭证…', 0.5);
      await _vault.push(passphrase: pass);
      outcome.step('凭证已同步到云端（${_accounts.accounts.length} 个服务器）');
    });
    return outcome;
  }

  /// Download cloud credentials into this device. Passwords that cannot be
  /// decrypted are left empty rather than failing the whole operation.
  Future<SyncOutcome> pullCredentials() async {
    final outcome = SyncOutcome(direction: 'pull');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      await connectTo(account);
      final pass = await _accounts.passwordFor(account.id) ?? '';
      _progress('下载凭证…', 0.5);
      final result = await _vault.pull(passphrase: pass);
      outcome.step(result?.summary ?? '云端暂无凭证文件');
      await _accounts.init();
    });
    return outcome;
  }

  // --- Playlists --------------------------------------------------------

  Future<SyncOutcome> syncPlaylistsNow() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      await connectTo(account);
      _playlists.configureSync(
        remotePath: _settings.playlistRemotePath,
        enabled: true,
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

  // --- Music library (incremental / full) -------------------------------

  /// Incremental library sync: copy rows the other side does not have yet, and
  /// prefer whichever side read its tags later.
  ///
  /// Never deletes: pruning is the job of [syncLibraryFull], so a fresh install
  /// can never wipe the cloud index.
  Future<SyncOutcome> syncLibraryIncremental() async {
    final outcome = SyncOutcome(direction: 'sync');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      await connectTo(account);
      _progress('读取云端曲库索引…', 0.3);
      final remote = await _fetchLibraryIndex(account.id);
      final local = _library.tracksForAccount(account.id);
      final remoteByPath = {for (final t in remote) t.remotePath: t};
      final localByPath = {for (final t in local) t.remotePath: t};

      final toUpload = <LibraryTrack>[];
      final toDownload = <LibraryTrack>[];
      for (final t in local) {
        final r = remoteByPath[t.remotePath];
        if (r == null || t.lastTagReadAt.isAfter(r.lastTagReadAt)) {
          toUpload.add(t);
        }
      }
      for (final r in remote) {
        final l = localByPath[r.remotePath];
        if (l == null || r.lastTagReadAt.isAfter(l.lastTagReadAt)) {
          toDownload.add(r);
        }
      }

      if (toDownload.isNotEmpty) {
        _progress('下载云端新增 ${toDownload.length} 首…', 0.5);
        await _library.upsertTracks(toDownload);
      }
      if (toUpload.isNotEmpty) {
        _progress('上传本地新增 ${toUpload.length} 首…', 0.8);
        await _pushLibraryIndex(
          accountId: account.id,
          accountUrl: account.url,
          tracks: _library.tracksForAccount(account.id),
        );
      }
      await _library.refresh();
      outcome.step('增量同步：上传 ${toUpload.length} 首，下载 ${toDownload.length} 首');
    });
    return outcome;
  }

  /// Full library sync: adopt newer remote rows, then push the complete local
  /// index — this is what prunes cloud-only rows the user deleted locally.
  Future<SyncOutcome> syncLibraryFull() async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      await connectTo(account);
      _progress('拉取云端曲库索引…', 0.3);
      final remote = await _fetchLibraryIndex(account.id);
      final local = _library.tracksForAccount(account.id);
      final localByPath = {for (final t in local) t.remotePath: t};

      final adopt = <LibraryTrack>[];
      for (final r in remote) {
        final l = localByPath[r.remotePath];
        if (l == null || r.lastTagReadAt.isAfter(l.lastTagReadAt)) {
          adopt.add(r);
        }
      }
      if (adopt.isNotEmpty) await _library.upsertTracks(adopt);

      _progress('上传完整曲库索引…', 0.7);
      await _pushLibraryIndex(
        accountId: account.id,
        accountUrl: account.url,
        tracks: _library.tracksForAccount(account.id),
      );
      await _library.refresh();
      final total = _library.tracksForAccount(account.id).length;
      outcome.step('全量同步完成：云端索引已对齐（本机 $total 首，采纳云端 ${adopt.length} 首）');
    });
    return outcome;
  }

  Future<List<LibraryTrack>> _fetchLibraryIndex(String accountId) async {
    try {
      final bytes = await _webDav.readAsBytes(libraryIndexPath(accountId));
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map) return [];
      final list = json['tracks'] as List<dynamic>? ?? const [];
      return list
          .map((e) => LibraryTrack.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('404') ||
          msg.contains('not found') ||
          msg.contains('does not exist')) {
        return [];
      }
      rethrow;
    }
  }

  Future<void> _pushLibraryIndex({
    required String accountId,
    required String accountUrl,
    required List<LibraryTrack> tracks,
  }) async {
    final portable = <Map<String, dynamic>>[];
    for (final t in tracks) {
      final m = Map<String, dynamic>.from(t.toMap());
      final cover = t.coverPath;
      if (cover != null && cover.isNotEmpty) {
        m['cover_path'] = p.basename(cover);
      }
      portable.add(m);
    }
    final payload = {
      'format': 'webdav_music_player_library_index',
      'formatVersion': 2,
      'accountId': accountId,
      'accountUrl': accountUrl,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'trackCount': portable.length,
      'tracks': portable,
    };
    final path = libraryIndexPath(accountId);
    await _webDav.ensureDirectory(p.url.dirname(path));
    await _webDav.writeBytes(
      path,
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
      ),
    );
  }

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
      _progress('连接备份网盘…', 0.1);
      await connectTo(destination);
      _progress('打包凭证 / 音乐库 / 歌单…', 0.4);
      await _backup.uploadBackup(passphrase: passphrase, remoteDir: remoteDir);
      outcome.step(_backup.lastMessage ?? '备份完成');
    });
    return outcome;
  }

  /// List archives available in [remoteDir] on [source].
  Future<List<String>> listBackups({
    required WebDavAccount source,
    required String remoteDir,
  }) async {
    await connectTo(source);
    return _backup.listBackups(remoteDir: remoteDir);
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
      _progress('连接备份网盘…', 0.1);
      await connectTo(source);
      _progress('下载并恢复…', 0.5);
      await _backup.restoreFromWebDav(
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

  /// Export the same whole-app archive into the Android Downloads folder.
  Future<ExportResult> exportToDownloads({
    required String passphrase,
    String? fileName,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    _progress('生成备份…', 0.2);
    try {
      final bytes = await _backup.buildArchiveBytes(passphrase: passphrase);
      _progress('写入下载目录…', 0.8);
      final name = fileName ?? '$localExportPrefix-${backupFileNameNow()}';
      final tmp = await PlatformExportService.writeTempExportFile(name, bytes);
      final result = await _export.saveToDownloads(
        sourcePath: tmp.path,
        fileName: name,
        mimeType: 'application/zip',
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
