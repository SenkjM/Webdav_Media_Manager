import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../utils/backup_crypto.dart';
import '../utils/backup_paths.dart';
import '../utils/credential_vault_crypto.dart';
import 'accounts_service.dart';
import 'cloud_drive_service.dart';
import 'cloud_drivers/driver_registry.dart';
import '../utils/wmp_container.dart';
import 'cache_service.dart';
import 'cover_service.dart';
import 'library_shard_codec.dart';
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
/// Format: a `WmpContainer` (magic `WDMMBK01`), optionally wrapped in AES-256-GCM
/// with a passphrase (magic `WDMMEN01`).
class BackupService extends ChangeNotifier {
  BackupService({
    required LibraryDatabase libraryDb,
    required LibraryService library,
    required AccountsService accounts,
    required SettingsService settings,
    required PlaylistService playlists,
    required WebDavService webDav,
    CacheService? cache,
    CoverService? covers,
  })  : _libraryDb = libraryDb,
        _library = library,
        _accounts = accounts,
        _settings = settings,
        _playlists = playlists,
        _webDav = webDav,
        _cache = cache,
        _covers = covers ?? library.covers;

  final LibraryDatabase _libraryDb;
  final LibraryService _library;
  final AccountsService _accounts;
  final SettingsService _settings;
  final PlaylistService _playlists;
  final WebDavService _webDav;
  final CacheService? _cache;
  final CoverService _covers;

  static const defaultRemoteDir = '/WebdavMediaManager/backup/';
  static const defaultFileName = 'webdav_media_backup.wdmm';
  static const format = 'webdav_media_manager_backup';
  static const formatVersion = 5;

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
    // 账号凭证全量进备份（取代 99 §4.2.8「云盘账号不进备份」）：WebDAV 三件套
    // 之外，云盘账号的驱动配置 JSON 一并入库——其中「配置界面默认为密码」的
    // 字段（spec.secretFieldKeys，即表单 obscure）按口令逐字段加密；URL/
    // 名称/开关类字段保持明文，坏口令时账号与配置仍可恢复，仅密文留空。
    for (final a in _accounts.accounts) {
      if (CloudDriveService.isCloudType(a.providerType)) {
        final spec = cloudDriverSpec(a.providerType);
        final raw = await _accounts.loadDriverConfig(a.id) ?? const {};
        final cfg = <String, dynamic>{};
        for (final e in raw.entries) {
          final value = e.value;
          if (passphrase.isNotEmpty &&
              value is String &&
              value.isNotEmpty &&
              spec != null &&
              spec.secretFieldKeys.contains(e.key) &&
              !CredentialVaultCrypto.isEncrypted(value)) {
            cfg[e.key] = await _encodePassword(value, passphrase);
          } else {
            cfg[e.key] = value;
          }
        }
        accounts.add({
          ...a.toMap(),
          'password': '',
          'passwordEncrypted': false,
          'driverConfig': cfg,
        });
        continue;
      }
      if (a.providerType != 'webdav') continue;
      final pass = await _accounts.passwordFor(a.id) ?? '';
      accounts.add({
        ...a.toMap(),
        // URL + username stay readable; only the password may be encrypted.
        'password': await _encodePassword(pass, passphrase),
        'passwordEncrypted': passphrase.isNotEmpty && pass.isNotEmpty,
      });
    }

    return {
      'format': 'webdav_media_manager_sync',
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

  /// Build the backup archive as a [WmpContainer] (optionally encrypted).
  ///
  /// Sections: `META` + `TRACKS` (every row, CUE slices included, **each with its
  /// own cover copy** in the raw `COVERS` section) + `CUEALBUMS` +
  /// `CREDENTIALS` / `PLAYLISTS` / `SETTINGS` as JSON. Binary on purpose: the
  /// rows are compressed with deflate while the already-compressed covers are
  /// stored as-is — a ZIP would deflate those again for nothing.
  Future<Uint8List> buildArchiveBytes({
    required String passphrase,
  }) async {
    final payload = await buildPayload(passphrase: passphrase);
    final tracks = <LibraryTrack>[];
    for (final raw in (payload['library']?['tracks'] as List<dynamic>? ??
        const [])) {
      tracks.add(LibraryTrack.fromMap(Map<String, dynamic>.from(raw as Map)));
    }
    for (final raw in (payload['library']?['cueSlices'] as List<dynamic>? ??
        const [])) {
      tracks.add(LibraryTrack.fromMap(Map<String, dynamic>.from(raw as Map)));
    }

    final coverBlobs = <Uint8List?>[];
    final coverKinds = <int>[];
    for (final t in tracks) {
      Uint8List? blob;
      final path = t.coverPath;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (file.existsSync()) blob = await file.readAsBytes();
        } catch (_) {
          blob = null;
        }
      }
      coverBlobs.add(blob);
      coverKinds.add(blob == null ? WmpImageKind.none : WmpImageKind.detect(blob));
    }

    Uint8List json(Uint8List Function() encode) => encode();
    final container = WmpContainer.encode(
      {
        WmpSections.meta: encodeRecords([
          {
            WmpMeta.kind: WmpKind.backup,
            WmpMeta.count: tracks.length,
            WmpMeta.deviceId: _settings.deviceId,
            WmpMeta.createdAt: DateTime.now().toUtc().toIso8601String(),
            WmpMeta.note: jsonEncode({
              'format': format,
              'formatVersion': formatVersion,
              'activeAccountId': payload['activeAccountId'],
              'passwordEncryption': payload['passwordEncryption'],
            }),
          },
        ]),
        WmpSections.tracks: _trackRecordsOnly(tracks, coverBlobs, coverKinds),
        WmpSections.credentials: json(
          () => Uint8List.fromList(utf8.encode(jsonEncode(payload['credentials']))),
        ),
        WmpSections.playlists: json(
          () => Uint8List.fromList(utf8.encode(jsonEncode(payload['playlists']))),
        ),
        WmpSections.settings: json(
          () => Uint8List.fromList(utf8.encode(jsonEncode(payload['settings']))),
        ),
        WmpSections.cueAlbums: json(
          () => Uint8List.fromList(
            utf8.encode(jsonEncode(payload['library']?['cueAlbums'] ?? const [])),
          ),
        ),
        if (coverBlobs.any((b) => b != null))
          WmpSections.covers: buildCoverSection([
            for (var i = 0; i < coverBlobs.length; i++)
              if (coverBlobs[i] != null)
                (bytes: coverBlobs[i]!, kind: coverKinds[i]),
          ]),
      },
      kind: WmpFileKind.backup,
      rawIds: {WmpSections.covers},
    );
    if (passphrase.isEmpty) return container;
    return BackupCrypto.encrypt(plaintext: container, passphrase: passphrase);
  }

  /// Readable JSON export (no cover bytes) for troubleshooting / hand editing.
  Future<Uint8List> buildJsonExport({required String passphrase}) async {
    final payload = await buildPayload(passphrase: passphrase);
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  /// Track records with a cover index per row (the container's COVERS section
  /// holds one entry per covered row, in row order).
  Uint8List _trackRecordsOnly(
    List<LibraryTrack> tracks,
    List<Uint8List?> coverBlobs,
    List<int> coverKinds,
  ) {
    final records = <Map<int, Object?>>[];
    var coverIndex = 0;
    for (var i = 0; i < tracks.length; i++) {
      final has = coverBlobs[i] != null && coverBlobs[i]!.isNotEmpty;
      records.add(
        LibraryShardCodec.trackToRecord(
          tracks[i],
          coverIndex: has ? coverIndex++ : null,
        ),
      );
    }
    return encodeRecords(records);
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

  /// Write the archive to [remoteDir] **on the account the caller picked**,
  /// plus a stable `latest` copy. Nothing is scoped per site.
  Future<void> uploadBackup({
    required String accountId,
    required String passphrase,
    required String remoteDir,
    String? fileName,
  }) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      if (!_webDav.hasAccount(accountId)) {
        throw StateError('备份目的地网盘未配置');
      }
      final dir = normalizeDir(remoteDir);
      final name = fileName ?? backupFileNameNow();
      final bytes = await buildArchiveBytes(passphrase: passphrase);
      await _webDav.ensureDirectory(accountId, dir);
      final remote = '$dir$name';
      await _webDav.writeBytes(accountId, remote, bytes);
      await _webDav.writeBytes(accountId, '$dir$defaultFileName', bytes);
      lastMessage =
          '已备份到 $remote（${_fmtBytes(bytes.length)}；并更新 latest）';
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Uint8List> downloadBackupBytes({
    required String accountId,
    required String remoteDir,
    String? fileName,
  }) async {
    final dir = normalizeDir(remoteDir);
    final name = fileName ?? defaultFileName;
    return _webDav.readAsBytes(accountId, '$dir$name');
  }

  /// List available archives in [remoteDir] (newest first).
  Future<List<String>> listBackups({
    required String accountId,
    required String remoteDir,
  }) async {
    final dir = normalizeDir(remoteDir);
    try {
      final items = await _webDav.listDirectory(accountId, dir);
      final files = items
          .where((e) => !e.isDirectory && e.name.endsWith('.wdmm'))
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
    required String accountId,
    required String passphrase,
    required String remoteDir,
    String? fileName,
  }) async {
    final data = await downloadBackupBytes(
      accountId: accountId,
      remoteDir: remoteDir,
      fileName: fileName,
    );
    await restoreFromBytes(data: data, passphrase: passphrase);
  }

  // --- Restore ----------------------------------------------------------

  /// Restore an archive produced by [buildArchiveBytes] (or the readable JSON
  /// produced by [buildJsonExport]).
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
      Uint8List bytes = data;
      if (BackupCrypto.looksEncrypted(data)) {
        if (passphrase.isEmpty) {
          throw StateError('此备份已加密，请输入口令');
        }
        bytes = await BackupCrypto.decrypt(data: data, passphrase: passphrase);
      }

      final Map<String, dynamic> payload;
      if (WmpContainer.looksLikeContainer(bytes)) {
        payload = await _decodeContainer(bytes);
      } else {
        // Readable JSON export (no cover bytes) — accepted as an interchange
        // format for troubleshooting / hand editing.
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw StateError('无法识别的备份内容');
        payload = Map<String, dynamic>.from(decoded);
      }

      final missing = await _applyPayload(payload, passphrase);
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

  /// Decode a [WmpContainer] archive into the payload shape [_applyPayload]
  /// expects. Covers are written into this device's cover cache here, so the
  /// restored rows point at real local files.
  Future<Map<String, dynamic>> _decodeContainer(Uint8List bytes) async {
    final container = WmpContainer.fromBytes(bytes);
    // A shard is a valid container but not a backup: say so plainly instead of
    // failing later on a missing section.
    if (container.kind != WmpFileKind.backup &&
        container.kind != WmpFileKind.exportBundle) {
      throw WmpFormatException(
        '这是 ${container.kind} 类文件，不是备份归档',
      );
    }
    Map<String, dynamic> jsonSection(int id) {
      final raw = container.readSection(id);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(utf8.decode(raw));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    }

    List<dynamic> jsonList(int id) {
      final raw = container.readSection(id);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(utf8.decode(raw));
      return decoded is List ? decoded : const [];
    }

    final metaRaw = container.readSection(WmpSections.meta);
    final meta = metaRaw == null
        ? const <int, Object?>{}
        : (decodeRecords(metaRaw, intTags: kMetaIntTags).firstOrNull ??
              const <int, Object?>{});
    final noteRaw = meta[WmpMeta.note];
    var header = <String, dynamic>{};
    if (noteRaw is String && noteRaw.isNotEmpty) {
      final decoded = jsonDecode(noteRaw);
      if (decoded is Map) header = Map<String, dynamic>.from(decoded);
    }

    final tracksRaw = container.readSection(WmpSections.tracks);
    final records = tracksRaw == null
        ? const <Map<int, Object?>>[]
        : decodeRecords(tracksRaw, intTags: kTrackIntTags);
    final coversRaw = container.readSection(WmpSections.covers);
    final covers = coversRaw == null
        ? <WmpCoverEntry>[]
        : parseCoverSection(coversRaw);

    final tracks = <Map<String, dynamic>>[];
    for (final record in records) {
      final track = LibraryShardCodec.recordToTrack(record);
      final idx = record[WmpTrack.coverIndex];
      String? coverPath;
      if (idx is int && idx >= 0 && idx < covers.length) {
        coverPath = await _writeLocalCover(
          sourceName: track.sourceName,
          remotePath: track.remotePath,
          blob: covers[idx].bytesIn(coversRaw!),
        );
      }
      tracks.add({...track.toMap(), 'cover_path': coverPath});
    }

    return {
      'format': header['format'] ?? format,
      'formatVersion': header['formatVersion'] ?? formatVersion,
      'activeAccountId': header['activeAccountId'],
      'passwordEncryption': header['passwordEncryption'],
      'credentials': jsonSection(WmpSections.credentials),
      'library': {
        'tracks': tracks,
        'cueSlices': const <dynamic>[],
        'cueAlbums': jsonList(WmpSections.cueAlbums),
        'cache': const <dynamic>[],
      },
      'playlists': jsonList(WmpSections.playlists),
      'settings': jsonSection(WmpSections.settings),
    };
  }

  /// Write a restored cover under the deterministic local name for this row.
  Future<String?> _writeLocalCover({
    required String sourceName,
    required String remotePath,
    required Uint8List blob,
  }) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'covers'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, _covers.coverFileName(sourceName, remotePath)));
      await file.writeAsBytes(blob, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Apply a decoded payload. Returns the names of accounts whose password
  /// could not be decrypted.
  Future<List<String>> _applyPayload(
    Map<String, dynamic> payload,
    String passphrase,
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
        columns: ['music_id', 'source_name', 'remote_path', 'cover_path'],
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
            where: 'source_name = ? AND remote_path = ?',
            whereArgs: [row['source_name'], row['remote_path']],
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
