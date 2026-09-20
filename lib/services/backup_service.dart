import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import '../utils/backup_crypto.dart';
import '../utils/backup_paths.dart';
import 'accounts_service.dart';
import 'library_database.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// WebDAV backup / restore of app data.
///
/// **Default: per WebDAV account/site** keyed by `accountId` + base URL.
/// Remote path:
/// `/WebDAVMusicPlayer/backup/<accountDir>/backup-<timestamp>.wmpbak`
/// and a stable `webdav_music_backup.wmpbak` ("latest") in the same folder.
///
/// Optional full multi-account backup goes under the backup root as
/// `full-backup-….wmpbak` and on restore replaces all mounts.
///
/// Per-account zip includes: that account's credentials, its library tracks
/// (JSON), playlists that reference it (entries keep accountId), cover thumbs,
/// and settings. Never includes audio cache or download queue.
///
/// Format: ZIP, optionally AES-256-GCM with passphrase (WMPB1).
class BackupService extends ChangeNotifier {
  BackupService({
    required LibraryDatabase libraryDb,
    required LibraryService library,
    required AccountsService accounts,
    required SettingsService settings,
    required PlaylistService playlists,
    required WebDavService webDav,
  })  : _libraryDb = libraryDb,
        _library = library,
        _accounts = accounts,
        _settings = settings,
        _playlists = playlists,
        _webDav = webDav;

  final LibraryDatabase _libraryDb;
  final LibraryService _library;
  final AccountsService _accounts;
  final SettingsService _settings;
  final PlaylistService _playlists;
  final WebDavService _webDav;

  static const defaultRemoteDir = '/WebDAVMusicPlayer/backup/';
  static const defaultFileName = 'webdav_music_backup.wmpbak';
  static const formatVersion = 2;

  bool busy = false;
  String? lastError;
  String? lastMessage;

  String get _backupRoot {
    final root = _settings.backupRemotePath.trim();
    if (root.isEmpty) return defaultRemoteDir;
    return root.endsWith('/') ? root : '$root/';
  }

  /// Per-account archive (default). Identity: [account.id] + [account.url].
  Future<Uint8List> buildAccountArchiveBytes({
    required WebDavAccount account,
    required String passphrase,
  }) async {
    final archive = Archive();
    final pass = await _accounts.passwordFor(account.id) ?? '';
    final tracks = await _libraryDb.tracksForAccount(account.id);
    final coverNames = <String>{};
    for (final t in tracks) {
      final cover = t.coverPath;
      if (cover != null && cover.isNotEmpty) {
        coverNames.add(p.basename(cover));
      }
    }

    final manifest = <String, dynamic>{
      'format': 'webdav_music_player_backup',
      'formatVersion': formatVersion,
      'scope': 'account',
      'accountId': account.id,
      'accountUrl': account.url,
      'accountName': account.name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'containsSecrets': true,
      'encrypted': passphrase.isNotEmpty,
      'trackCount': tracks.length,
      'includes': [
        'account_credentials',
        'tracks_json',
        'covers',
        'playlists_json',
        'settings',
      ],
      'excludes': ['audio_cache', 'download_queue', 'other_accounts'],
    };
    archive.addFile(ArchiveFile.bytes(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    ));

    archive.addFile(ArchiveFile.bytes(
      'settings.json',
      utf8.encode(jsonEncode(_settings.exportForBackup())),
    ));

    archive.addFile(ArchiveFile.bytes(
      'accounts.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'scope': 'account',
        'activeAccountId': account.id,
        'accounts': [
          {
            ...account.toMap(),
            'password': pass,
          }
        ],
        'warning':
            'Contains plaintext WebDAV password for this account only. '
            'Prefer encrypting the backup with a passphrase.',
      })),
    ));

    archive.addFile(ArchiveFile.bytes(
      'tracks.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'accountId': account.id,
        'accountUrl': account.url,
        'tracks': tracks.map((t) => t.toMap()).toList(),
      })),
    ));

    final docs = await getApplicationDocumentsDirectory();
    final coversDir = Directory(p.join(docs.path, 'covers'));
    if (await coversDir.exists() && coverNames.isNotEmpty) {
      await for (final entity in coversDir.list(recursive: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!coverNames.contains(name)) continue;
        archive.addFile(
          ArchiveFile.bytes('covers/$name', await entity.readAsBytes()),
        );
      }
    }

    archive.addFile(ArchiveFile.bytes(
      'playlists.json',
      utf8.encode(jsonEncode(_playlists.exportJsonForAccount(account.id))),
    ));

    final zip = ZipEncoder().encode(archive);
    final zipBytes = Uint8List.fromList(zip);
    if (passphrase.isEmpty) return zipBytes;
    return BackupCrypto.encrypt(plaintext: zipBytes, passphrase: passphrase);
  }

  /// Full multi-account archive (optional / legacy).
  Future<Uint8List> buildFullArchiveBytes({required String passphrase}) async {
    final archive = Archive();
    final manifest = <String, dynamic>{
      'format': 'webdav_music_player_backup',
      'formatVersion': formatVersion,
      'scope': 'all',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'containsSecrets': true,
      'encrypted': passphrase.isNotEmpty,
      'includes': [
        'library_db',
        'covers',
        'playlists',
        'settings',
        'webdav_accounts_with_passwords',
      ],
      'excludes': ['audio_cache', 'download_queue'],
    };
    archive.addFile(ArchiveFile.bytes(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    ));

    archive.addFile(ArchiveFile.bytes(
      'settings.json',
      utf8.encode(jsonEncode(_settings.exportForBackup())),
    ));

    final accountPayload = <Map<String, dynamic>>[];
    for (final a in _accounts.accounts) {
      final pass = await _accounts.passwordFor(a.id) ?? '';
      accountPayload.add({
        ...a.toMap(),
        'password': pass,
      });
    }
    archive.addFile(ArchiveFile.bytes(
      'accounts.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'scope': 'all',
        'activeAccountId': _accounts.activeAccountId,
        'accounts': accountPayload,
        'warning':
            'Contains plaintext WebDAV passwords for ALL accounts. '
            'Prefer encrypting the backup with a passphrase.',
      })),
    ));

    await _libraryDb.database;
    final docs = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(docs.path, 'music_library.db'));
    if (await dbFile.exists()) {
      archive.addFile(
        ArchiveFile.bytes('music_library.db', await dbFile.readAsBytes()),
      );
    }

    final coversDir = Directory(p.join(docs.path, 'covers'));
    if (await coversDir.exists()) {
      await for (final entity in coversDir.list(recursive: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        archive.addFile(
          ArchiveFile.bytes('covers/$name', await entity.readAsBytes()),
        );
      }
    }

    final plPath = await _playlists.store.databasePath();
    final plFile = File(plPath);
    if (await plFile.exists()) {
      archive.addFile(
        ArchiveFile.bytes('playlists.db', await plFile.readAsBytes()),
      );
    }
    archive.addFile(ArchiveFile.bytes(
      'playlists.json',
      utf8.encode(jsonEncode(_playlists.exportJson())),
    ));

    final zip = ZipEncoder().encode(archive);
    final zipBytes = Uint8List.fromList(zip);
    if (passphrase.isEmpty) return zipBytes;
    return BackupCrypto.encrypt(plaintext: zipBytes, passphrase: passphrase);
  }

  /// Legacy alias — prefer [buildAccountArchiveBytes].
  Future<Uint8List> buildArchiveBytes({required String passphrase}) =>
      buildFullArchiveBytes(passphrase: passphrase);

  /// Default: backup one WebDAV account into its own remote folder.
  Future<void> uploadAccountBackup({
    required WebDavAccount account,
    required String passphrase,
    String? remoteDir,
    String? fileName,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      if (!_webDav.isConnected) {
        throw StateError('请先连接 WebDAV 账号');
      }
      if (_webDav.accountId != null && _webDav.accountId != account.id) {
        throw StateError(
          '当前已连接的 WebDAV 与所选备份账号不一致。'
          '请先切换到该账号再备份，以免把站点 A 的备份写到站点 B。',
        );
      }
      final dir = remoteDir ?? perAccountBackupDir(_backupRoot, account);
      final name = fileName ?? backupFileNameNow();
      final bytes = await buildAccountArchiveBytes(
        account: account,
        passphrase: passphrase,
      );
      await _webDav.ensureDirectory(dir);
      final remote = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
      await _webDav.writeBytes(remote, bytes);
      final latest =
          dir.endsWith('/') ? '$dir$defaultFileName' : '$dir/$defaultFileName';
      await _webDav.writeBytes(latest, bytes);
      lastMessage =
          '已备份站点「${account.name}」到 $remote（${bytes.length} 字节；并更新 latest）';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Optional full multi-account backup to the backup root.
  Future<void> uploadFullBackup({
    required String passphrase,
    String? remoteDir,
    String? fileName,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      if (!_webDav.isConnected) {
        throw StateError('请先连接 WebDAV 账号');
      }
      final dir = remoteDir ?? _backupRoot;
      final name = fileName ?? 'full-${backupFileNameNow()}';
      final bytes = await buildFullArchiveBytes(passphrase: passphrase);
      await _webDav.ensureDirectory(dir);
      final remote = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
      await _webDav.writeBytes(remote, bytes);
      lastMessage = '已上传【全部账号】备份到 $remote（${bytes.length} 字节）';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Default entry used by settings UI: per-account backup.
  Future<void> uploadBackup({
    required String passphrase,
    String? remoteDir,
    String? fileName,
    WebDavAccount? account,
    bool fullMultiAccount = false,
  }) async {
    if (fullMultiAccount) {
      return uploadFullBackup(
        passphrase: passphrase,
        remoteDir: remoteDir,
        fileName: fileName,
      );
    }
    WebDavAccount? target = account;
    if (target == null && _webDav.accountId != null) {
      for (final a in _accounts.accounts) {
        if (a.id == _webDav.accountId) {
          target = a;
          break;
        }
      }
    }
    target ??= _accounts.activeAccount;
    if (target == null) {
      throw StateError('请先选择要备份的 WebDAV 账号');
    }
    return uploadAccountBackup(
      account: target,
      passphrase: passphrase,
      remoteDir: remoteDir,
      fileName: fileName,
    );
  }

  Future<Uint8List> downloadBackupBytes({
    String? remoteDir,
    String? fileName,
    WebDavAccount? account,
  }) async {
    if (!_webDav.isConnected) throw StateError('请先连接 WebDAV 账号');
    String dir;
    if (remoteDir != null) {
      dir = remoteDir;
    } else if (account != null) {
      dir = perAccountBackupDir(_backupRoot, account);
    } else {
      WebDavAccount? match;
      final connectedId = _webDav.accountId;
      if (connectedId != null) {
        for (final a in _accounts.accounts) {
          if (a.id == connectedId) {
            match = a;
            break;
          }
        }
      }
      dir = match != null
          ? perAccountBackupDir(_backupRoot, match)
          : _backupRoot;
    }
    final name = fileName ?? defaultFileName;
    final remote = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
    return _webDav.readAsBytes(remote);
  }

  Future<void> restoreFromBytes({
    required Uint8List data,
    required String passphrase,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      Uint8List zipBytes = data;
      if (BackupCrypto.looksEncrypted(data)) {
        if (passphrase.isEmpty) {
          throw StateError('此备份已加密，请输入口令');
        }
        zipBytes = await BackupCrypto.decrypt(
          data: data,
          passphrase: passphrase,
        );
      } else if (passphrase.isNotEmpty) {
        try {
          zipBytes = await BackupCrypto.decrypt(
            data: data,
            passphrase: passphrase,
          );
        } catch (_) {}
      }

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.findFile('manifest.json');
      Map<String, dynamic> manifest = {};
      if (manifestFile != null) {
        manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>;
      }
      final scope = manifest['scope'] as String? ?? _inferScope(archive);

      if (scope == 'account') {
        await _restoreAccountScope(archive, manifest);
        lastMessage =
            '已按站点恢复「${manifest['accountName'] ?? manifest['accountId']}」。'
            '其他 WebDAV 账号未改动。';
      } else {
        await _restoreFullScope(archive);
        lastMessage = '全部账号恢复完成。请确认 WebDAV 账号与歌单是否正确。';
      }
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _inferScope(Archive archive) {
    if (archive.findFile('tracks.json') != null) return 'account';
    final accountsFile = archive.findFile('accounts.json');
    if (accountsFile != null) {
      try {
        final json = jsonDecode(utf8.decode(accountsFile.content as List<int>))
            as Map<String, dynamic>;
        if (json['scope'] == 'account') return 'account';
      } catch (_) {}
    }
    return 'all';
  }

  Future<void> _restoreAccountScope(
    Archive archive,
    Map<String, dynamic> manifest,
  ) async {
    final docs = await getApplicationDocumentsDirectory();

    final accountsFile = archive.findFile('accounts.json');
    if (accountsFile == null) {
      throw StateError('备份缺少 accounts.json');
    }
    final accountsJson = jsonDecode(
            utf8.decode(accountsFile.content as List<int>))
        as Map<String, dynamic>;
    final list = accountsJson['accounts'] as List<dynamic>? ?? [];
    if (list.isEmpty) {
      throw StateError('备份中没有账号数据');
    }
    final accountMap = Map<String, dynamic>.from(list.first as Map);
    final backupId =
        accountMap['id'] as String? ?? manifest['accountId'] as String?;
    final backupUrl = (accountMap['url'] as String? ??
            manifest['accountUrl'] as String? ??
            '')
        .trim()
        .replaceAll(RegExp(r'/+$'), '');

    final connectedId = _webDav.accountId;
    final connectedUrl = _webDav.baseUrl?.replaceAll(RegExp(r'/+$'), '');
    if (connectedId != null &&
        backupId != null &&
        connectedId != backupId &&
        connectedUrl != null &&
        backupUrl.isNotEmpty &&
        connectedUrl != backupUrl) {
      throw StateError(
        '备份属于站点「${manifest['accountName'] ?? backupUrl}」'
        '（id=$backupId），与当前连接的站点不一致。'
        '请切换到对应账号后再恢复，避免把站点 A 的凭证写入站点 B。',
      );
    }

    await _accounts.mergeAccountFromBackup(accountMap);

    final tracksFile = archive.findFile('tracks.json');
    if (tracksFile != null) {
      final tracksJson = jsonDecode(
              utf8.decode(tracksFile.content as List<int>))
          as Map<String, dynamic>;
      final accountId = tracksJson['accountId'] as String? ?? backupId;
      if (accountId == null) {
        throw StateError('tracks.json 缺少 accountId');
      }
      final rawTracks = tracksJson['tracks'] as List<dynamic>? ?? [];
      final tracks = <LibraryTrack>[];
      for (final e in rawTracks) {
        final t = LibraryTrack.fromMap(Map<String, dynamic>.from(e as Map));
        if (t.accountId != accountId) {
          throw StateError(
            '备份曲目 accountId=${t.accountId} 与站点 $accountId 不一致，已中止以免串站',
          );
        }
        tracks.add(t);
      }
      await _library.replaceTracksForAccount(accountId, tracks);
    }

    for (final file in archive) {
      if (!file.isFile) continue;
      if (!file.name.startsWith('covers/')) continue;
      final covers = Directory(p.join(docs.path, 'covers'));
      if (!await covers.exists()) await covers.create(recursive: true);
      final base = p.basename(file.name);
      await File(p.join(covers.path, base))
          .writeAsBytes(file.content as List<int>, flush: true);
    }

    final settingsFile = archive.findFile('settings.json');
    if (settingsFile != null) {
      final json = jsonDecode(utf8.decode(settingsFile.content as List<int>))
          as Map<String, dynamic>;
      await _settings.importFromBackup(json);
    }

    final plJson = archive.findFile('playlists.json');
    if (plJson != null) {
      final list =
          jsonDecode(utf8.decode(plJson.content as List<int>)) as List<dynamic>;
      await _playlists.mergeFromJson(list);
    }

    await _rewriteCoverPaths(docs.path);
    await _library.refresh();
  }

  Future<void> _restoreFullScope(Archive archive) async {
    final docs = await getApplicationDocumentsDirectory();

    await _libraryDb.close();
    await _playlists.store.close();

    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name;
      final content = file.content as List<int>;
      if (name == 'music_library.db') {
        final out = File(p.join(docs.path, 'music_library.db'));
        for (final side in ['music_library.db-wal', 'music_library.db-shm']) {
          final f = File(p.join(docs.path, side));
          if (await f.exists()) await f.delete();
        }
        await out.writeAsBytes(content, flush: true);
      } else if (name == 'playlists.db') {
        final out = File(p.join(docs.path, 'playlists.db'));
        for (final side in ['playlists.db-wal', 'playlists.db-shm']) {
          final f = File(p.join(docs.path, side));
          if (await f.exists()) await f.delete();
        }
        await out.writeAsBytes(content, flush: true);
      } else if (name.startsWith('covers/')) {
        final covers = Directory(p.join(docs.path, 'covers'));
        if (!await covers.exists()) await covers.create(recursive: true);
        final base = p.basename(name);
        await File(p.join(covers.path, base))
            .writeAsBytes(content, flush: true);
      }
    }

    await _libraryDb.database;
    await _accounts.init();

    final accountsFile = archive.findFile('accounts.json');
    if (accountsFile != null) {
      final json = jsonDecode(utf8.decode(accountsFile.content as List<int>))
          as Map<String, dynamic>;
      await _accounts.restoreFromBackup(json);
    }

    final settingsFile = archive.findFile('settings.json');
    if (settingsFile != null) {
      final json = jsonDecode(utf8.decode(settingsFile.content as List<int>))
          as Map<String, dynamic>;
      await _settings.importFromBackup(json);
    }

    await _playlists.init();
    final plJson = archive.findFile('playlists.json');
    if (plJson != null) {
      final list =
          jsonDecode(utf8.decode(plJson.content as List<int>)) as List<dynamic>;
      await _playlists.importFromJson(list);
    }

    await _rewriteCoverPaths(docs.path);
    await _library.refresh();
  }

  Future<void> restoreFromWebDav({
    required String passphrase,
    WebDavAccount? account,
    String? remoteDir,
    String? fileName,
  }) async {
    final data = await downloadBackupBytes(
      account: account,
      remoteDir: remoteDir,
      fileName: fileName,
    );
    await restoreFromBytes(data: data, passphrase: passphrase);
  }

  Future<void> _rewriteCoverPaths(String docsPath) async {
    final db = await _libraryDb.database;
    final rows = await db
        .query('tracks', columns: ['account_id', 'remote_path', 'cover_path']);
    final coversRoot = p.join(docsPath, 'covers');
    for (final row in rows) {
      final cover = row['cover_path'] as String?;
      if (cover == null || cover.isEmpty) continue;
      final base = p.basename(cover);
      final newPath = p.join(coversRoot, base);
      if (cover == newPath) continue;
      await db.update(
        'tracks',
        {'cover_path': newPath},
        where: 'account_id = ? AND remote_path = ?',
        whereArgs: [row['account_id'], row['remote_path']],
      );
    }
  }
}
