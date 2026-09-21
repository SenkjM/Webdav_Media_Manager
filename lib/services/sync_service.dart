import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/webdav_account.dart';
import '../utils/backup_paths.dart';
import 'accounts_service.dart';
import 'backup_service.dart';
import 'credential_vault_service.dart';
import 'library_service.dart';
import 'library_sync_service.dart';
import 'platform_export_service.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// What a single 同步 run touched. Empty fields mean "not part of this run".
class SyncOutcome {
  SyncOutcome({required this.direction});

  /// `push` (本机 → 云端) or `pull` (云端 → 本机).
  final String direction;

  final List<String> steps = [];
  final List<String> warnings = [];

  bool ok = true;
  String? error;

  void step(String message) => steps.add(message);
  void warn(String message) => warnings.add(message);

  String get message {
    final head = direction == 'push' ? '已同步到云端' : '已从云端同步';
    if (!ok) return '$head失败：${error ?? '未知错误'}';
    final body = steps.isEmpty ? '无变更' : steps.join('；');
    final warn = warnings.isEmpty ? '' : '\n注意：${warnings.join('；')}';
    return '$head。$body$warn';
  }
}

/// Unified「同步 / 备份」feature.
///
/// Replaces the three separate entries (歌单同步、歌曲库同步、WebDAV 备份) with one
/// screen and two directions:
///
/// **push (本机 → 云端)**
/// 1. `credentials.json` — WebDAV accounts, **URL + username plaintext**, only
///    the password optionally encrypted (`AESGCMv1:`) with the sync passphrase.
/// 2. song library index + cover thumbs (bidirectional merge, then push).
/// 3. playlists (M3U8, last-write-wins).
/// 4. a site backup archive (`.wmpbak`, optionally AES-256-GCM) under the
///    backup root so a fresh install can rebuild everything at once.
///
/// **pull (云端 → 本机)**
/// 1. credentials vault → merge into local accounts. An entry whose password
///    cannot be decrypted (no unified key) is restored with an **empty
///    password** instead of failing the whole sync.
/// 2. library + playlists merge.
/// 3. optionally the backup archive.
class SyncService extends ChangeNotifier {
  SyncService({
    required AccountsService accounts,
    required SettingsService settings,
    required WebDavService webDav,
    required CredentialVaultService vault,
    required LibrarySyncService librarySync,
    required LibraryService library,
    required PlaylistService playlists,
    required BackupService backup,
    PlatformExportService? export,
  })  : _accounts = accounts,
        _settings = settings,
        _webDav = webDav,
        _vault = vault,
        _librarySync = librarySync,
        _library = library,
        _playlists = playlists,
        _backup = backup,
        _export = export ?? const PlatformExportService();

  final AccountsService _accounts;
  final SettingsService _settings;
  final WebDavService _webDav;
  final CredentialVaultService _vault;
  final LibrarySyncService _librarySync;
  final LibraryService _library;
  final PlaylistService _playlists;
  final BackupService _backup;
  final PlatformExportService _export;

  /// File name used for local export inside the Downloads folder.
  static const localExportSubdir = 'WebDAVMusic';
  static const localExportPrefix = 'wmp-sync';

  bool busy = false;
  String? lastError;
  String? lastMessage;
  double? progress;
  String? progressLabel;

  void _progress(String label, [double? value]) {
    progressLabel = label;
    progress = value;
    notifyListeners();
  }

  /// The account whose credentials authenticate the cloud session.
  WebDavAccount? get targetAccount {
    final connectedId = _webDav.accountId;
    if (connectedId != null) {
      for (final a in _accounts.accounts) {
        if (a.id == connectedId) return a;
      }
    }
    return _accounts.activeAccount;
  }

  Future<void> _ensureConnected(WebDavAccount account) async {
    if (_webDav.isConnected && _webDav.accountId == account.id) return;
    await _accounts.setActiveAccount(account.id);
    final pass = await _accounts.passwordFor(account.id) ?? '';
    _webDav.configure(
      accountId: account.id,
      url: account.url,
      username: account.username,
      password: pass,
    );
  }

  // --- Cloud sync -------------------------------------------------------

  /// Upload local state to the WebDAV cloud.
  Future<SyncOutcome> push({
    required String passphrase,
    bool includeCredentials = true,
    bool includeLibrary = true,
    bool includePlaylists = true,
    bool includeBackup = true,
  }) async {
    final outcome = SyncOutcome(direction: 'push');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      _ensureVaultConfigured();
      await _ensureConnected(account);
      await _webDav.ensureDirectory(_settings.syncRemoteRoot);

      if (includeCredentials) {
        _progress('同步 WebDAV 凭证…', 0.1);
        await _vault.push(passphrase: passphrase);
        outcome.step('凭证已上传（${_accounts.accounts.length} 个服务器）');
      }

      if (includeLibrary) {
        _progress('同步歌曲库与封面…', 0.35);
        await _librarySync.syncLibrary(account: account);
        outcome.step(_librarySync.lastMessage ?? '歌曲库已同步');
      }

      if (includePlaylists) {
        _progress('同步歌单…', 0.6);
        await _playlists.pullAndMergeFromWebDav();
        _playlists.configureSync(
          remotePath: _settings.playlistRemotePath,
          enabled: true,
        );
        for (final pl in _playlists.playlists) {
          await _playlists.uploadPlaylist(pl);
        }
        outcome.step('歌单已上传（${_playlists.playlists.length} 个）');
      }

      if (includeBackup) {
        _progress('上传站点备份…', 0.85);
        await _backup.uploadAccountBackup(
          account: account,
          passphrase: passphrase,
        );
        outcome.step(_backup.lastMessage ?? '站点备份已上传');
      }
    });
    return outcome;
  }

  /// Pull cloud state into this device.
  ///
  /// When the local account's password is missing the vault is applied first so
  /// the rest of the pull can authenticate.
  Future<SyncOutcome> pull({
    required String passphrase,
    bool includeCredentials = true,
    bool includeLibrary = true,
    bool includePlaylists = true,
    bool restoreBackup = false,
  }) async {
    final outcome = SyncOutcome(direction: 'pull');
    await _run(outcome, () async {
      final account = targetAccount;
      if (account == null) throw StateError('请先添加 WebDAV 账号');
      _ensureVaultConfigured();

      var localPass = await _accounts.passwordFor(account.id) ?? '';
      if (localPass.isEmpty) {
        // Fresh device / forgotten password: pull credentials from cloud first.
        _ensureConnected(account);
        _progress('从云端读取凭证…', 0.1);
        final result = await _vault.pull(passphrase: passphrase);
        if (result != null) outcome.step(result.summary);
        final refreshed = targetAccount ?? account;
        localPass = await _accounts.passwordFor(refreshed.id) ?? '';
        if (localPass.isEmpty) {
          outcome.warn(
            '云端凭证无法解密（缺少统一解密密钥），密码留空；'
            '请先在该账号手动填写密码后再同步内容',
          );
        }
        await _ensureConnected(refreshed);
      } else {
        await _ensureConnected(account);
        if (includeCredentials) {
          _progress('合并云端凭证…', 0.1);
          final result = await _vault.pull(passphrase: passphrase);
          if (result != null) outcome.step(result.summary);
        }
      }

      if (includeLibrary) {
        _progress('同步歌曲库与封面…', 0.4);
        final refreshed = targetAccount ?? account;
        await _ensureConnected(refreshed);
        await _librarySync.syncLibrary(account: refreshed);
        outcome.step(_librarySync.lastMessage ?? '歌曲库已同步');
      }

      if (includePlaylists) {
        _progress('拉取歌单…', 0.65);
        _playlists.configureSync(
          remotePath: _settings.playlistRemotePath,
          enabled: true,
        );
        await _playlists.pullAndMergeFromWebDav();
        outcome.step('歌单已合并（${_playlists.playlists.length} 个）');
      }

      if (restoreBackup) {
        _progress('下载站点备份…', 0.85);
        await _backup.restoreFromWebDav(
          passphrase: passphrase,
          account: targetAccount ?? account,
        );
        outcome.step(_backup.lastMessage ?? '站点备份已恢复');
        await _library.refresh();
        await _playlists.refresh();
      }

      await _accounts.init();
      await _library.refresh();
    });
    return outcome;
  }

  /// The most common recovery path: sync **everything** down from the cloud.
  Future<SyncOutcome> pullAll({required String passphrase}) => pull(
        passphrase: passphrase,
        includeCredentials: true,
        includeLibrary: true,
        includePlaylists: true,
        restoreBackup: true,
      );

  // --- Local import / export -------------------------------------------

  /// Build a portable local archive (same format as the cloud backup).
  Future<Uint8List> buildLocalArchive({
    required String passphrase,
    bool fullMultiAccount = true,
  }) {
    if (fullMultiAccount) {
      return _backup.buildFullArchiveBytes(passphrase: passphrase);
    }
    final account = targetAccount;
    if (account == null) throw StateError('请先添加 WebDAV 账号');
    return _backup.buildAccountArchiveBytes(
      account: account,
      passphrase: passphrase,
    );
  }

  /// Export to the Android **Downloads** directory (falls back to the app
  /// documents directory when the native channel is unavailable, e.g. desktop
  /// or a bare `flutter test` run).
  Future<ExportResult> exportToDownloads({
    required String passphrase,
    bool fullMultiAccount = true,
    String? fileName,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    _progress('生成本地备份…', 0.2);
    try {
      final bytes = await buildLocalArchive(
        passphrase: passphrase,
        fullMultiAccount: fullMultiAccount,
      );
      _progress('写入下载目录…', 0.8);
      final name = fileName ?? '$localExportPrefix-${backupFileNameNow()}';
      final result = await _export.saveToDownloads(
        sourcePath: (await PlatformExportService.writeTempExportFile(name, bytes))
            .path,
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

  /// Import a local archive produced by [exportToDownloads] (or by the cloud
  /// backup). Merges accounts, library, playlists and settings.
  Future<SyncOutcome> importLocalArchive({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    final outcome = SyncOutcome(direction: 'import');
    await _run(outcome, () async {
      _progress('解包本地备份…', 0.2);
      await _backup.restoreFromBytes(data: bytes, passphrase: passphrase);
      outcome.step(_backup.lastMessage ?? '本地备份已导入');
      await _accounts.init();
      await _library.refresh();
      await _playlists.refresh();
      _progress('完成', 1);
    });
    return outcome;
  }

  /// Read an archive file picked by the user and import it.
  Future<SyncOutcome> importLocalFile({
    required File file,
    required String passphrase,
  }) async {
    final bytes = await file.readAsBytes();
    return importLocalArchive(bytes: bytes, passphrase: passphrase);
  }

  /// Decode an archive the user pasted as base64 (helps on devices without a
  /// file picker).
  Future<SyncOutcome> importLocalBase64({
    required String base64Text,
    required String passphrase,
  }) {
    return importLocalArchive(
      bytes: Uint8List.fromList(base64Decode(base64Text.trim())),
      passphrase: passphrase,
    );
  }

  /// Path of the app-private export fallback (when Downloads is unavailable).
  static Future<String> fallbackExportPath(String fileName) async {
    return p.join(Directory.systemTemp.path, fileName);
  }

  // --- Internals --------------------------------------------------------

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

  /// Point the playlist / library sync helpers at the current settings while
  /// tolerating older installs where the paths were configured separately.
  void _ensureVaultConfigured() {
    _playlists.configureSync(
      remotePath: _settings.playlistRemotePath,
      enabled: _settings.playlistSyncEnabled,
    );
  }
}
