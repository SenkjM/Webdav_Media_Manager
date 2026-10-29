import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../models/playlist.dart';
import '../utils/backup_crypto.dart';
import '../utils/backup_pass_check.dart';
import '../utils/backup_paths.dart';
import '../utils/credential_vault_crypto.dart';
import '../utils/l10n_host.dart';
import 'accounts_service.dart';
import 'wdmm_vfs/driver_registry.dart';
import '../utils/wmp_container.dart';
import 'cache_service.dart';
import 'cover_service.dart';
import 'credential_vault_codec.dart';
import 'credential_vault_service.dart';
import 'library_service.dart';
import 'manga_library_service.dart';
import 'rust_library_service.dart';
import 'user_folder_service.dart';
import 'playlist_service.dart';
import 'rust_core_service.dart';
import 'rust_dmr_prefs_service.dart';
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
/// 4. manga library — mangas / pages / reading progress / tombstones; the
///    series a book belongs to is the row's own `series` tag, so there is no
///    series table to snapshot
/// 5. user folders — folders + their soft refs (music / manga / series …)
/// plus the cover thumbnails the music rows reference, and the manga
/// thumbnails (section `MANGA_COVERS`), which are the same idea: bytes in
/// their own section, an index on the row, the path derived from the id.
///
/// Never includes cached audio files or the download queue. On restore the
/// cached state is derived from disk, so the player never believes a file
/// exists unless it
/// really is on disk.
///
/// Format: a `WmpContainer` (magic `WDMMBK01`), optionally wrapped in AES-256-GCM
/// with a passphrase (magic `WDMMEN01`).
class BackupService extends ChangeNotifier {
  BackupService({
    required UserFolderService userFolders,
    required MangaLibraryService manga,
    required LibraryService library,
    required AccountsService accounts,
    required SettingsService settings,
    required PlaylistService playlists,
    required CredentialVaultService credentials,
    required WebDavService webDav,
    CacheService? cache,
    CoverService? covers,
    Future<void> Function()? onSettingsImported,
    RustDmrPrefsService? dmrPrefs,
  }) : _userFolders = userFolders,
       _manga = manga,
       _library = library,
       _accounts = accounts,
       _settings = settings,
       _playlists = playlists,
       _credentials = credentials,
       _webDav = webDav,
       _cache = cache,
       _covers = covers ?? library.covers,
       _dmrPrefs = dmrPrefs,
       _onSettingsImported = onSettingsImported;

  final UserFolderService _userFolders;
  final MangaLibraryService _manga;
  final LibraryService _library;
  final AccountsService _accounts;
  final SettingsService _settings;
  final PlaylistService _playlists;

  /// Owns the vault encoding. The archive embeds the **same bytes** this
  /// service uploads to the sync root (docs/10 §4.3) — one encoding, two exits.
  final CredentialVaultService _credentials;
  final WebDavService _webDav;
  final CacheService? _cache;
  final CoverService _covers;
  final RustDmrPrefsService? _dmrPrefs;

  /// 备份导入后回调（用于 alignNomedia）
  final Future<void> Function()? _onSettingsImported;

  static const defaultRemoteDir = '/WebdavMediaManager/backup/';
  static const defaultFileName = 'webdav_media_backup.wdmm';
  static const format = 'webdav_media_manager_backup';
  static const formatVersion = 7;

  bool busy = false;
  String? lastError;
  String? lastMessage;

  /// Configure Core cover roots before backup create/restore.
  /// Creates manga covers dir if missing. Tolerates cache being null by
  /// still resolving the path via getApplicationSupportDirectory.
  Future<void> ensureCoversConfigured() async {
    try {
      final musicDir = await _covers.coversDir; // creates docs/covers
      // manga covers subdir may not exist until first write — create it
      Directory mangaCovers;
      if (_cache != null) {
        mangaCovers = Directory(p.join(_cache.mangaCacheDir.path, 'covers'));
      } else {
        // Cache not initialized yet — resolve path directly
        final support = await getApplicationSupportDirectory();
        mangaCovers = Directory(p.join(support.path, 'manga_cache', 'covers'));
      }
      if (!await mangaCovers.exists()) {
        await mangaCovers.create(recursive: true);
      }
      final r = RustCoreService.coversConfigure(musicDir.path, mangaCovers.path);
      if (r != null && r.startsWith('error:')) {
        debugPrint('[Backup] coversConfigure failed: $r');
      }
    } catch (e) {
      debugPrint('[Backup] ensureCoversConfigured error: $e');
    }
  }

  // --- Build ------------------------------------------------------------

  /// Serialise everything into `{ credentials, library, playlists }` JSON.
  ///
  /// **Only the human-readable export uses this** ([buildJsonExport]). The
  /// binary archive does not: its `CREDENTIALS` / `PLAYLISTS` sections carry
  /// whole `WDMMCV01` / `WDMMPL01` documents, built by
  /// [CredentialVaultService.encodeVaultBytes] and
  /// [PlaylistService.encodePlaylistBytes] (docs/10 §4.3). Keeping the JSON
  /// shape here means a hand-edited export still restores through
  /// [restoreFromBytes].
  Future<Map<String, dynamic>> _buildPayload({
    required String passphrase,
  }) async {
    final tracks = RustLibraryService.listAll();
    if (tracks == null) {
      throw StateError(
          '_buildPayload: Core FFI unavailable — listAll returned null');
    }
    final cueAlbums = <Map<String, dynamic>>[];
    final cueSlices = <Map<String, dynamic>>[];
    for (final t in tracks) {
      if (t.isCueVirtual) {
        cueSlices.add(t.toMap());
      }
    }
    for (final e in RustLibraryService.listCueAlbums()) {
      cueAlbums.add(e);
    }

    final accounts = <Map<String, dynamic>>[];
    // 账号凭证全量进备份（取代 99 §4.2.8「云盘账号不进备份」）：WebDAV 三件套
    // 之外，云盘账号的驱动配置 JSON 一并入库——其中「配置界面默认为密码」的
    // 字段（spec.secretFieldKeys，即表单 obscure）按口令逐字段加密；URL/
    // 名称/开关类字段保持明文，坏口令时账号与配置仍可恢复，仅密文留空。
    for (final a in _accounts.accounts) {
      // 云盘账号走驱动配置通道；webdav 账号走密码通道（判 providerType
      // 而非 isCloudType，B1 step 4 后 isCloudType 对 webdav 也返回 true）。
      if (a.providerType != 'webdav') {
        final spec = wdmmVfsSpec(a.providerType);
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
      'credentials': {'accounts': accounts},
      // 2. Music library
      'library': {
        'tracks': tracks
            .where((t) => !t.isCueVirtual)
            .map((t) => t.toMap())
            .toList(),
        'cueAlbums': cueAlbums,
        'cueSlices': cueSlices,
        'cache': <Map<String, dynamic>>[],
      },
      // 3. Playlists
      'playlists': _playlists.exportJson(),
      'settings': _settings.exportForBackup(),
      'mangaLibrary': await _manga.exportCoreMangaSnapshot(),
      'userFolders': _userFolders.exportSnapshot(),
    };
  }

  /// Readable JSON export (no cover bytes) for troubleshooting / hand editing.
  ///
  /// Not the archive format: it stays JSON on purpose so a human can diff and
  /// edit it, and [restoreFromBytes] still accepts it.
  Future<Uint8List> buildJsonExport({required String passphrase}) async {
    final payload = await _buildPayload(passphrase: passphrase);
    if (passphrase.isNotEmpty) {
      payload['passCheck'] = await BackupPassCheck.create(passphrase);
      payload['hasPassCheck'] = true;
    }
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  /// Probe [data]'s passphrase without writing the database.
  ///
  /// Used by restore / local-import UI before the irreversible apply step.
  static Future<BackupPassphraseProbe> probePassphrase({
    required Uint8List data,
    required String passphrase,
  }) => BackupPassCheck.probe(data: data, passphrase: passphrase);


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
        throw StateError('err.backupDestNotConfigured');
      }
      final dir = normalizeDir(remoteDir);
      final name = fileName ?? backupFileNameNow();

      // Phase D: Full cutover to Core FFI for backup create when Rust lib loaded
      final bytes = await createArchiveBytes(passphrase: passphrase);

      await _webDav.ensureDirectory(accountId, dir);
      final remote = '$dir$name';
      await _webDav.writeBytes(accountId, remote, bytes);
      await _webDav.writeBytes(accountId, '$dir$defaultFileName', bytes);
      lastMessage = L10nHost.current.backupDoneLatest(
        remote,
        _fmtBytes(bytes.length),
      );
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Production `.wdmm` create via Core FFI (Phase D cutover).
  ///
  /// All production archive creators ([uploadBackup], [SyncService.exportToDownloads])
  /// must use this. When Rust lib is loaded, use Core; else throw (no silent fallback).
  Future<Uint8List> createArchiveBytes({required String passphrase}) async {
    await ensureCoversConfigured();
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(
      tempDir.path,
      'backup_create_${DateTime.now().millisecondsSinceEpoch}.wdmm',
    ));
    try {
      final result = RustCoreService.backupCreate(passphrase, tempFile.path);
      if (result == null) {
        throw StateError('Core FFI unavailable — cannot create backup');
      }
      if (result.startsWith('error:')) {
        throw StateError('Core backup create failed: $result');
      }
      // result = "ok:created:{sections}"
      final bytes = await tempFile.readAsBytes();
      return bytes;
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
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
      final files =
          items
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

  /// Restore an archive produced by the Core FFI (`.wdmm`) or the readable JSON
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
          throw StateError('err.backupEncryptedNeedPassphrase');
        }
        bytes = await BackupCrypto.decrypt(data: data, passphrase: passphrase);
      }

      if (WmpContainer.looksLikeContainer(bytes)) {
        // All WmpContainer archives → Core FFI restore (handles both legacy and
        // current Core JSON format).
        await ensureCoversConfigured();
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(p.join(tempDir.path, 'restore_${DateTime.now().millisecondsSinceEpoch}.wdmm'));
        try {
          await tempFile.writeAsBytes(data, flush: true);
          final result = RustCoreService.backupRestore(passphrase, tempFile.path);
          if (result == null) {
            throw StateError('Core FFI unavailable');
          }
          if (result.startsWith('error:')) {
            throw StateError(result);
          }
          lastMessage = 'Restored via Core JSON backup';
          return;
        } finally {
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
        }
      }

      // Readable JSON export (no cover bytes) — accepted as an interchange
      // format for troubleshooting / hand editing.
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw StateError('err.backupUnrecognizedContent');
      final payload = Map<String, dynamic>.from(decoded);

      final missing = await _applyPayload(payload, passphrase);
      final accountCount =
          (payload['credentials'] as Map?)?['accounts'] is List
              ? ((payload['credentials'] as Map)['accounts'] as List).length
              : 0;
      lastMessage = missing.isEmpty
          ? L10nHost.current.backupRestoredFull(accountCount)
          : L10nHost.current.backupRestoredMissingPasswords(
              missing.join(L10nHost.current.nameJoiner),
            );
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Apply a decoded payload. Returns the names of accounts whose password
  /// could not be decrypted.
  Future<List<String>> _applyPayload(
    Map<String, dynamic> payload,
    String passphrase,
  ) async {
    final missing = <String>[];

    // 1. Credentials — a [DecodedVault] from a binary archive section, or the
    //    `{accounts: [...]}` map from a readable JSON export.
    final credentials = payload['credentials'];
    if (credentials is DecodedVault) {
      final result = await _credentials.applyVault(
        credentials,
        passphrase: passphrase,
      );
      missing.addAll(_credentials.missingPasswordAccounts);
      if (result.skippedUnknown > 0) {
        // Unregistered cloud types are skipped by design (不报错、不建账号);
        // note it for debugging instead of failing the whole restore.
        debugPrint(
          'backup restore: skipped ${result.skippedUnknown} vault entries '
          'whose cloud provider type is not registered on this build',
        );
      }
    } else if (credentials is Map) {
      final accountsJson = Map<String, dynamic>.from(credentials);
      final list = accountsJson['accounts'] as List<dynamic>? ?? const [];
      if (list.isNotEmpty) {
        missing.addAll(
          await _accounts.restoreFromBackup(
            accountsJson,
            passphrase: passphrase,
          ),
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
      // Hard-fail: backup restore must not silently leave stale library rows.
      final clearResult = RustLibraryService.clearLibraryAll();
      if (clearResult == null || clearResult.startsWith('error:')) {
        throw StateError(
            'backup restore: clearLibraryAll failed: $clearResult');
      }
      // CUE albums before slices: cue_slices FK references cue_albums.
      for (final raw in (lib['cueAlbums'] as List<dynamic>? ?? const [])) {
        RustLibraryService.upsertCueAlbum(jsonEncode(raw));
      }
      for (final t in tracks) {
        RustLibraryService.upsertTrack(t);
      }
      // Cached state is derived from disk (v9): nothing to clear, kept for the
      // call-site contract.
      if (_cache != null) {
        await _cache.markAllUncached();
      }
    }

    // 3. Manga library + user folders.
    final manga = payload['mangaLibrary'];
    if (manga is Map && manga.isNotEmpty) {
      await _manga.importCoreMangaSnapshot(Map<String, dynamic>.from(manga));
    }
    final folders = payload['userFolders'];
    if (folders is Map && folders.isNotEmpty) {
      await _userFolders.importSnapshot(Map<String, dynamic>.from(folders));
    }

    // 4. Playlists.
    final playlists = payload['playlists'];
    if (playlists is List<Playlist>) {
      // Decoded `.wdmp` documents: last-write-wins merge, never a wipe, so a
      // restored archive cannot delete a list created after the backup.
      await _playlists.mergeFromPlaylists(playlists);
    } else if (playlists is List) {
      // Readable JSON export — notes-only, same merge contract downstream.
      await _playlists.importFromJson(playlists);
    }

    // 5. Settings.
    final settings = payload['settings'];
    if (settings is Map) {
      await _settings.importFromBackup(Map<String, dynamic>.from(settings));
      // 导入 settings 后回调 alignNomedia（规格 §7 末）
      if (_onSettingsImported != null) {
        await _onSettingsImported();
      }
    }

    // 6. DMR preferences.
    final dmrPrefs = payload['dmrPrefs'];
    if (dmrPrefs is List && dmrPrefs.isNotEmpty && _dmrPrefs != null) {
      for (final raw in dmrPrefs) {
        if (raw is! Map) continue;
        try {
          final pref = DmrPreference.fromJson(Map<String, dynamic>.from(raw));
          await _dmrPrefs.save(pref);
        } catch (_) {}
      }
    }

    await _library.refresh();
    return missing;
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
