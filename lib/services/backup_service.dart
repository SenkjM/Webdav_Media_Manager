import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../utils/backup_crypto.dart';
import '../utils/backup_paths.dart';
import '../utils/credential_vault_crypto.dart';
import 'accounts_service.dart';
import 'cache_service.dart';
import 'library_database.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// Whole-app backup archive. **No site isolation**: one archive contains every
/// WebDAV credential, the complete music library and all playlists, and it is
/// written to a path the user picks together with the destination server.
///
/// The app only has three kinds of data, and this archive holds all of them:
/// 1. `credentials.json` — WebDAV accounts (URL + username plaintext, password
///    optionally encrypted with `AESGCMv1:`)
/// 2. `library.json` — music library rows + CUE albums/slices
/// 3. `playlists.json` — playlists
/// plus the cover thumbnails those rows reference.
///
/// Never includes cached audio files or the download queue. On restore the
/// cache annex is cleared, so the player never believes a file exists unless it
/// really is on disk.
///
/// Format: ZIP, optionally wrapped in AES-256-GCM with a passphrase (`WMPB1`).
class BackupService extends ChangeNotifier {
  BackupService({
    required LibraryDatabase libraryDb,
    required LibraryService library,
    required AccountsService accounts,
    required SettingsService settings,
    required PlaylistService playlists,
    required WebDavService webDav,
    CacheService? cache,
  })  : _libraryDb = libraryDb,
        _library = library,
        _accounts = accounts,
        _settings = settings,
        _playlists = playlists,
        _webDav = webDav,
        _cache = cache;

  final LibraryDatabase _libraryDb;
  final LibraryService _library;
  final AccountsService _accounts;
  final SettingsService _settings;
  final PlaylistService _playlists;
  final WebDavService _webDav;
  final CacheService? _cache;

  static const defaultRemoteDir = '/WebDAVMusicPlayer/backup/';
  static const defaultFileName = 'webdav_music_backup.wmpbak';
  static const format = 'webdav_music_player_backup';
  static const formatVersion = 4;

  bool busy = false;
  String? lastError;
  String? lastMessage;

  // --- Build ------------------------------------------------------------

  /// Serialise everything into `{ credentials, library, playlists }` JSON.
  ///
  /// Exposed because the local export and the cloud backup share this payload;
  /// the ZIP wrapper (and optional encryption) is applied by
  /// [buildArchiveBytes].
  Future<Map<String, dynamic>> buildPayload({
    required String passphrase,
  }) async {
    final tracks = await _libraryDb.allTracks();
    final cueAlbums = <Map<String, dynamic>>[];
    final cueSlices = <Map<String, dynamic>>[];
    for (final t in tracks) {
      if (t.isCueVirtual) {
        cueSlices.add(t.toMap());
      }
    }
    for (final e in await _libraryDb.allCueAlbums()) {
      cueAlbums.add(e);
    }

    final accounts = <Map<String, dynamic>>[];
    for (final a in _accounts.accounts) {
      final pass = await _accounts.passwordFor(a.id) ?? '';
      accounts.add({
        ...a.toMap(),
        // URL + username stay readable; only the password may be encrypted.
        'password': await _encodePassword(pass, passphrase),
        'passwordEncrypted': passphrase.isNotEmpty && pass.isNotEmpty,
      });
    }

    return {
      'format': 'webdav_music_player_sync',
      'formatVersion': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'activeAccountId': _accounts.activeAccountId,
      'passwordEncryption': passphrase.isEmpty ? 'none' : 'aes-256-gcm',
      // 1. WebDAV credentials
      'credentials': {
        'accounts': accounts,
      },
      // 2. Music library
      'library': {
        'tracks': tracks.where((t) => !t.isCueVirtual).map((t) => t.toMap()).toList(),
        'cueAlbums': cueAlbums,
        'cueSlices': cueSlices,
        'cache': <Map<String, dynamic>>[],
      },
      // 3. Playlists
      'playlists': _playlists.exportJson(),
      'settings': _settings.exportForBackup(),
    };
  }

  /// The cover file names referenced by the library (for the ZIP payload).
  Future<Set<String>> _referencedCovers() async {
    final names = <String>{};
    for (final t in await _libraryDb.allTracks()) {
      final cover = t.coverPath;
      if (cover != null && cover.isNotEmpty) names.add(p.basename(cover));
    }
    return names;
  }

  /// Build the ZIP archive (optionally passphrase-encrypted).
  Future<Uint8List> buildArchiveBytes({
    required String passphrase,
  }) async {
    final payload = await buildPayload(passphrase: passphrase);
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes(
      'backup.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    ));
    // Keep the legacy file names too so the payload is easy to inspect/unzip
    // by hand; they are derived from the same object.
    archive.addFile(ArchiveFile.bytes(
      'credentials.json',
      utf8.encode(jsonEncode(payload['credentials'])),
    ));
    archive.addFile(ArchiveFile.bytes(
      'library.json',
      utf8.encode(jsonEncode(payload['library'])),
    ));
    archive.addFile(ArchiveFile.bytes(
      'playlists.json',
      utf8.encode(jsonEncode(payload['playlists'])),
    ));
    archive.addFile(ArchiveFile.bytes(
      'settings.json',
      utf8.encode(jsonEncode(payload['settings'])),
    ));

    final coverNames = await _referencedCovers();
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

    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (passphrase.isEmpty) return zipBytes;
    return BackupCrypto.encrypt(plaintext: zipBytes, passphrase: passphrase);
  }

  /// Encrypt one account password for storage in the archive.
  ///
  /// Empty passphrase (or empty password) keeps the value readable, matching
  /// the credential vault rule: 地址与用户名明文，仅密码可选加密.
  Future<String> _encodePassword(String password, String passphrase) async {
    if (passphrase.isEmpty || password.isEmpty) return password;
    return CredentialVaultCrypto.encrypt(
      plaintext: password,
      passphrase: passphrase,
    );
  }

  // --- Upload / download -----------------------------------------------

  /// Normalise the user-chosen backup directory.
  String normalizeDir(String dir) {
    var value = dir.trim();
    if (value.isEmpty) value = defaultRemoteDir;
    if (!value.startsWith('/')) value = '/$value';
    if (!value.endsWith('/')) value = '$value/';
    return value;
  }

  /// Write the archive to [remoteDir] on the **connected** server, plus a
  /// stable `latest` copy. No per-site folders: the whole app state goes to the
  /// path the user selected.
  Future<void> uploadBackup({
    required String passphrase,
    required String remoteDir,
    String? fileName,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      if (!_webDav.isConnected) {
        throw StateError('请先连接要存放备份的 WebDAV 账号');
      }
      final dir = normalizeDir(remoteDir);
      final name = fileName ?? backupFileNameNow();
      final bytes = await buildArchiveBytes(passphrase: passphrase);
      await _webDav.ensureDirectory(dir);
      final remote = '$dir$name';
      await _webDav.writeBytes(remote, bytes);
      await _webDav.writeBytes('$dir$defaultFileName', bytes);
      lastMessage = '已备份到 $remote'
          '（${_fmtBytes(bytes.length)}；并更新 latest）';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Uint8List> downloadBackupBytes({
    required String remoteDir,
    String? fileName,
  }) async {
    if (!_webDav.isConnected) throw StateError('请先连接 WebDAV 账号');
    final dir = normalizeDir(remoteDir);
    final name = fileName ?? defaultFileName;
    return _webDav.readAsBytes('$dir$name');
  }

  /// List available archives in [remoteDir] (newest first).
  Future<List<String>> listBackups({required String remoteDir}) async {
    if (!_webDav.isConnected) throw StateError('请先连接 WebDAV 账号');
    final dir = normalizeDir(remoteDir);
    try {
      final items = await _webDav.listDirectory(dir);
      final files = items
          .where((e) => !e.isDirectory && e.name.endsWith('.wmpbak'))
          .map((e) => e.name)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      return files;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('404') || msg.contains('not found')) return [];
      rethrow;
    }
  }

  Future<void> restoreFromWebDav({
    required String passphrase,
    required String remoteDir,
    String? fileName,
  }) async {
    final data = await downloadBackupBytes(
      remoteDir: remoteDir,
      fileName: fileName,
    );
    await restoreFromBytes(data: data, passphrase: passphrase);
  }

  // --- Restore ----------------------------------------------------------

  /// Restore an archive produced by [buildArchiveBytes].
  ///
  /// Passwords that cannot be decrypted with [passphrase] are left **empty**
  /// instead of aborting; everything else is restored.
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
      }

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final payload = _readPayload(archive);
      final missing = await _applyPayload(payload, passphrase, archive);
      lastMessage = missing.isEmpty
          ? '备份已恢复：${payload['credentials']?['accounts']?.length ?? 0} 个服务器、'
              '音乐库与歌单已写回'
          : '备份已恢复，但以下服务器的密码无法解密并已留空：'
              '${missing.join('、')}。请在账号管理中补填。';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _readPayload(Archive archive) {
    final file = archive.findFile('backup.json');
    if (file != null) {
      return jsonDecode(utf8.decode(file.content as List<int>))
          as Map<String, dynamic>;
    }
    // Tolerate a hand-made archive with the split files.
    Map<String, dynamic> readJson(String name) {
      final f = archive.findFile(name);
      if (f == null) return const {};
      final decoded = jsonDecode(utf8.decode(f.content as List<int>));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    }

    final credentials = readJson('credentials.json');
    final lib = readJson('library.json');
    final playlists = archive.findFile('playlists.json') == null
        ? const <dynamic>[]
        : jsonDecode(
            utf8.decode(
              archive.findFile('playlists.json')!.content as List<int>,
            ),
          );
    final settings = readJson('settings.json');
    if (credentials.isEmpty && lib.isEmpty) {
      throw StateError('备份缺少 backup.json / library.json');
    }
    return {
      'credentials': credentials,
      'library': lib,
      'playlists': playlists,
      'settings': settings,
    };
  }

  /// Apply a decoded payload. Returns the names of accounts whose password
  /// could not be decrypted.
  Future<List<String>> _applyPayload(
    Map<String, dynamic> payload,
    String passphrase,
    Archive archive,
  ) async {
    final docs = await getApplicationDocumentsDirectory();
    final missing = <String>[];

    // 1. Credentials.
    final credentials = payload['credentials'];
    if (credentials is Map) {
      final accountsJson = Map<String, dynamic>.from(credentials);
      final list = accountsJson['accounts'] as List<dynamic>? ?? const [];
      if (list.isNotEmpty) {
        missing.addAll(
          await _accounts.restoreFromBackup(accountsJson, passphrase: passphrase),
        );
      }
    }

    // 2. Library (replaces all library rows — this is a whole-app backup).
    final libraryJson = payload['library'];
    if (libraryJson is Map) {
      final lib = Map<String, dynamic>.from(libraryJson);
      final tracks = <LibraryTrack>[];
      for (final raw in (lib['tracks'] as List<dynamic>? ?? const [])) {
        tracks.add(LibraryTrack.fromMap(Map<String, dynamic>.from(raw as Map)));
      }
      for (final raw in (lib['cueSlices'] as List<dynamic>? ?? const [])) {
        tracks.add(LibraryTrack.fromMap(Map<String, dynamic>.from(raw as Map)));
      }
      await _libraryDb.clearAllLibraryData();
      for (final t in tracks) {
        await _libraryDb.upsertTrack(t);
      }
      // Never trust the archived cache annex: files must exist on disk.
      if (_cache != null) {
        await _cache.markAllUncached();
      }
    }

    // 3. Covers: write the archived thumbnails into the local covers folder,
    // then re-point every library row at that folder below.
    final covers = Directory(p.join(docs.path, 'covers'));
    if (!await covers.exists()) await covers.create(recursive: true);
    for (final file in archive) {
      if (!file.isFile) continue;
      if (!file.name.startsWith('covers/')) continue;
      final base = p.basename(file.name);
      await File(p.join(covers.path, base))
          .writeAsBytes(file.content as List<int>, flush: true);
    }

    // 4. Playlists.
    final playlists = payload['playlists'];
    if (playlists is List) {
      await _playlists.importFromJson(playlists);
    }

    // 5. Settings.
    final settings = payload['settings'];
    if (settings is Map) {
      await _settings.importFromBackup(Map<String, dynamic>.from(settings));
    }

    await _rewriteCoverPaths(docs.path);
    await _library.refresh();
    return missing;
  }

  Future<void> _rewriteCoverPaths(String docsPath) async {
    final db = await _libraryDb.database;
    final coversRoot = p.join(docsPath, 'covers');
    for (final table in ['tracks', 'cue_slices']) {
      final rows = await db.query(
        table,
        columns: ['music_id', 'account_id', 'remote_path', 'cover_path'],
      );
      for (final row in rows) {
        final cover = row['cover_path'] as String?;
        if (cover == null || cover.isEmpty) continue;
        final base = p.basename(cover);
        final newPath = p.join(coversRoot, base);
        if (cover == newPath) continue;
        final musicId = row['music_id'] as String?;
        if (musicId != null && musicId.isNotEmpty) {
          await db.update(
            table,
            {'cover_path': newPath},
            where: 'music_id = ?',
            whereArgs: [musicId],
          );
        } else {
          await db.update(
            table,
            {'cover_path': newPath},
            where: 'account_id = ? AND remote_path = ?',
            whereArgs: [row['account_id'], row['remote_path']],
          );
        }
      }
    }
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
