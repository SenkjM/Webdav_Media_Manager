import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/backup_crypto.dart';
import 'accounts_service.dart';
import 'library_database.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// WebDAV backup / restore of app data.
///
/// Included:
/// - music_library.db (accounts metadata + tracks / tags)
/// - covers/ thumbs (relative paths; cover_path in DB rewritten on restore)
/// - playlists.db + playlists JSON snapshot
/// - non-secret settings (cache retention, library sort, backup/playlist paths)
/// - **WebDAV usernames + passwords** (in accounts.json inside archive)
///
/// NOT included: audio cache blobs (music_cache/), download queue.
///
/// Format: ZIP, optionally AES-256-GCM encrypted with user passphrase (WMPB1).
/// Default remote path: `/WebDAVMusicPlayer/backup/webdav_music_backup.wmpbak`
class BackupService extends ChangeNotifier {
  BackupService({
    required LibraryDatabase libraryDb,
    required AccountsService accounts,
    required SettingsService settings,
    required PlaylistService playlists,
    required WebDavService webDav,
  })  : _libraryDb = libraryDb,
        _accounts = accounts,
        _settings = settings,
        _playlists = playlists,
        _webDav = webDav;

  final LibraryDatabase _libraryDb;
  final AccountsService _accounts;
  final SettingsService _settings;
  final PlaylistService _playlists;
  final WebDavService _webDav;

  static const defaultRemoteDir = '/WebDAVMusicPlayer/backup/';
  static const defaultFileName = 'webdav_music_backup.wmpbak';
  static const formatVersion = 1;

  bool busy = false;
  String? lastError;
  String? lastMessage;

  Future<Uint8List> buildArchiveBytes({required String passphrase}) async {
    final archive = Archive();
    final manifest = <String, dynamic>{
      'format': 'webdav_music_player_backup',
      'formatVersion': formatVersion,
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

    // Settings (non-secret prefs + path configs).
    final settingsMap = _settings.exportForBackup();
    archive.addFile(ArchiveFile.bytes('settings.json', utf8.encode(jsonEncode(settingsMap)),
    ));

    // Accounts + passwords (SECRETS).
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
        'activeAccountId': _accounts.activeAccountId,
        'accounts': accountPayload,
        'warning': 'Contains plaintext WebDAV passwords inside this archive. '
            'Prefer encrypting the backup with a passphrase.',
      })),
    ));

    // Library DB copy.
    await _libraryDb.database;
    final docs = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(docs.path, 'music_library.db'));
    if (await dbFile.exists()) {
      // Checkpoint WAL if present by closing/reopening is hard; copy raw bytes.
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile.bytes('music_library.db', bytes));
    }

    // Covers thumbs.
    final coversDir = Directory(p.join(docs.path, 'covers'));
    if (await coversDir.exists()) {
      await for (final entity in coversDir.list(recursive: false)) {
        if (entity is File) {
          final name = p.basename(entity.path);
          final bytes = await entity.readAsBytes();
          archive.addFile(
            ArchiveFile.bytes('covers/$name', bytes),
          );
        }
      }
    }

    // Playlists DB + JSON snapshot.
    final plPath = await _playlists.store.databasePath();
    final plFile = File(plPath);
    if (await plFile.exists()) {
      final bytes = await plFile.readAsBytes();
      archive.addFile(ArchiveFile.bytes('playlists.db', bytes));
    }
    archive.addFile(ArchiveFile.bytes('playlists.json', utf8.encode(jsonEncode(_playlists.exportJson())),
    ));

    final zip = ZipEncoder().encode(archive);
    final zipBytes = Uint8List.fromList(zip);
    if (passphrase.isEmpty) return zipBytes;
    return BackupCrypto.encrypt(plaintext: zipBytes, passphrase: passphrase);
  }

  Future<void> uploadBackup({
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
      final dir = _settings.backupRemotePath.isNotEmpty
          ? _settings.backupRemotePath
          : (remoteDir ?? defaultRemoteDir);
      final name = fileName ?? defaultFileName;
      final bytes = await buildArchiveBytes(passphrase: passphrase);
      await _webDav.ensureDirectory(dir);
      final remote = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
      await _webDav.writeBytes(remote, bytes);
      lastMessage = '已上传备份到 $remote（${bytes.length} 字节）';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Uint8List> downloadBackupBytes({
    String? remoteDir,
    String? fileName,
  }) async {
    if (!_webDav.isConnected) throw StateError('请先连接 WebDAV 账号');
    final dir = _settings.backupRemotePath.isNotEmpty
        ? _settings.backupRemotePath
        : (remoteDir ?? defaultRemoteDir);
    final name = fileName ?? defaultFileName;
    final remote = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
    return _webDav.readAsBytes(remote);
  }

  /// Restore from encrypted or plain zip bytes. Overwrites local library /
  /// accounts / playlists / settings. Passwords written to secure storage.
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
        // Try decrypt anyway in case magic check failed on truncated head.
        try {
          zipBytes = await BackupCrypto.decrypt(
            data: data,
            passphrase: passphrase,
          );
        } catch (_) {
          // treat as plain zip
        }
      }

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final docs = await getApplicationDocumentsDirectory();

      // Close DBs before replacing files.
      await _libraryDb.close();
      await _playlists.store.close();

      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name;
        final content = file.content;
        if (name == 'music_library.db') {
          final out = File(p.join(docs.path, 'music_library.db'));
          // Also remove WAL/SHM sidecars.
          for (final side in [
            'music_library.db-wal',
            'music_library.db-shm',
          ]) {
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

      // Re-open library DB then apply accounts passwords + settings + playlists JSON.
      await _libraryDb.database;
      await _accounts.init();

      final accountsFile = archive.findFile('accounts.json');
      if (accountsFile != null) {
        final json = jsonDecode(utf8.decode(accountsFile.content))
            as Map<String, dynamic>;
        await _accounts.restoreFromBackup(json);
      }

      final settingsFile = archive.findFile('settings.json');
      if (settingsFile != null) {
        final json = jsonDecode(utf8.decode(settingsFile.content))
            as Map<String, dynamic>;
        await _settings.importFromBackup(json);
      }

      // Prefer playlists.json for merge if present (after DB restore).
      await _playlists.init();
      final plJson = archive.findFile('playlists.json');
      if (plJson != null) {
        final list =
            jsonDecode(utf8.decode(plJson.content)) as List<dynamic>;
        await _playlists.importFromJson(list);
      }

      // Fix cover_path absolute paths to current docs/covers/.
      await _rewriteCoverPaths(docs.path);

      lastMessage = '恢复完成。请确认 WebDAV 账号与歌单是否正确。';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restoreFromWebDav({required String passphrase}) async {
    final data = await downloadBackupBytes();
    await restoreFromBytes(data: data, passphrase: passphrase);
  }

  Future<void> _rewriteCoverPaths(String docsPath) async {
    final db = await _libraryDb.database;
    final rows = await db.query('tracks', columns: ['account_id', 'remote_path', 'cover_path']);
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
