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
import 'cloud_drive_service.dart';
import 'cloud_drivers/driver_registry.dart';
import '../utils/wmp_container.dart';
import 'cache_service.dart';
import 'cover_service.dart';
import 'credential_vault_codec.dart';
import 'credential_vault_service.dart';
import 'library_shard_codec.dart';
import 'playlist_codec.dart';
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

  /// Build backup archive bytes (Android WMP container format).
  ///
  /// Data is sourced from Core FFI — no sqflite reads. This method is used by
  /// [buildJsonExport] and tests. Production upload uses [uploadBackup] which
  /// delegates to [createArchiveBytes] (Core JSON format).
  ///
  /// Sections: `META` + `TRACKS` (every row, CUE slices included, **each with its
  /// own cover copy** in the raw `COVERS` section) + `SETTINGS` / `CUEALBUMS`
  /// as JSON, all of those deflated. On top of them two sections hold **whole
  /// documents** instead of JSON:
  ///
  /// * `CREDENTIALS` — the complete bytes of one `WDMMCV01` file, the very same
  ///   bytes [CredentialVaultService.push] uploads to the sync root.
  /// * `PLAYLISTS` — one record per playlist, whose [WmpBackupPlaylist.blob]
  ///   holds that playlist's complete `WDMMPL01` file.
  ///
  /// Both are listed in `rawIds`: their payloads are already-compressed
  /// containers, so deflating them again would burn CPU and shrink nothing
  /// (docs/10 §4.3). Nesting stops at this one level — an embedded container
  /// never embeds another.
  Future<Uint8List> buildArchiveBytes({required String passphrase}) async {
    final allTracks = RustLibraryService.listAll();
    if (allTracks == null) {
      throw StateError(
          'buildArchiveBytes: Core FFI unavailable — listAll returned null');
    }
    // Non-CUE rows first, then CUE slices: the order the JSON payload used, so
    // cover indices stay aligned with what earlier archives produced.
    final tracks = <LibraryTrack>[
      ...allTracks.where((t) => !t.isCueVirtual),
      ...allTracks.where((t) => t.isCueVirtual),
    ];

    final coverBlobs = <Uint8List?>[];
    final coverKinds = <int>[];
    for (final t in tracks) {
      Uint8List? blob;
      // Use the deterministic thumb path — never a stored absolute path.
      final file = await _covers.coverFile(t.sourceName, t.remotePath);
      if (file.existsSync()) {
        try {
          blob = await file.readAsBytes();
        } catch (_) {
          blob = null;
        }
      }
      coverBlobs.add(blob);
      coverKinds.add(
        blob == null ? WmpImageKind.none : WmpImageKind.detect(blob),
      );
    }

    final cueAlbums = RustLibraryService.listCueAlbums();

    final credentialsBytes = await _credentials.encodeVaultBytes(
      passphrase: passphrase,
    );

    final playlistRecords = <Map<int, Object?>>[];
    for (final pl in _playlists.playlists) {
      playlistRecords.add({
        WmpBackupPlaylist.blob: await _playlists.encodePlaylistBytes(pl),
      });
    }

    final passCheck = passphrase.isEmpty
        ? null
        : await BackupPassCheck.create(passphrase);

    // Manga thumbnails travel like track covers: bytes in their own section,
    // an index on the row. The path is derived from the manga id, so nothing
    // about this device's cache leaks into the archive.
    final mangaSnapshot = await _manga.exportCoreMangaSnapshot();
    final mangaCoverBlobs = await collectMangaCovers(
      snapshot: mangaSnapshot,
      cache: _cache,
    );

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
              'activeAccountId': _accounts.activeAccountId,
              'passwordEncryption': passphrase.isEmpty ? 'none' : 'aes-256-gcm',
              if (passCheck != null) 'hasPassCheck': true,
            }),
          },
        ]),
        WmpSections.tracks: _trackRecordsOnly(tracks, coverBlobs, coverKinds),
        if (credentialsBytes.isNotEmpty)
          WmpSections.credentials: credentialsBytes,
        if (playlistRecords.isNotEmpty)
          WmpSections.playlists: encodeRecords(playlistRecords),
        WmpSections.settings: _jsonBytes(_settings.exportForBackup()),
        WmpSections.cueAlbums: _jsonBytes(cueAlbums),
        WmpSections.mangaLibrary: _jsonBytes(mangaSnapshot),
        WmpSections.userFolders: _jsonBytes(
          _userFolders.exportSnapshot(),
        ),
        if (mangaCoverBlobs.isNotEmpty)
          WmpSections.mangaCovers: buildCoverSection([
            for (final blob in mangaCoverBlobs)
              (bytes: blob, kind: WmpImageKind.detect(blob)),
          ]),
        if (coverBlobs.any((b) => b != null))
          WmpSections.covers: buildCoverSection([
            for (var i = 0; i < coverBlobs.length; i++)
              if (coverBlobs[i] != null)
                (bytes: coverBlobs[i]!, kind: coverKinds[i]),
          ]),
        if (passCheck != null)
          WmpSections.passCheck: Uint8List.fromList(utf8.encode(passCheck)),
        if (_dmrPrefs != null)
          WmpSections.dmrPrefs: _jsonBytes(
            _dmrPrefs.values.map((p) => p.toJson()).toList(),
          ),
      },
      kind: WmpFileKind.backup,
      rawIds: {
        WmpSections.covers,
        WmpSections.mangaCovers,
        WmpSections.credentials,
        WmpSections.playlists,
      },
    );
    if (passphrase.isEmpty) return container;
    return BackupCrypto.encrypt(plaintext: container, passphrase: passphrase);
  }

  /// UTF-8 JSON section payload (used for the sections that stay JSON).
  static Uint8List _jsonBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  /// Read every manga thumbnail this device has and stamp its index onto the
  /// snapshot's rows (in place). Returns the blobs in index order.
  ///
  /// A row whose thumbnail is missing here loses any `cover_index` it had, so
  /// an archive never points at a blob it does not carry.
  ///
  /// Static and cache-explicit so the pairing with [restoreMangaThumbnails] can
  /// be exercised without a database or a service graph.
  @visibleForTesting
  static Future<List<Uint8List>> collectMangaCovers({
    required Map<String, dynamic> snapshot,
    required CacheService? cache,
  }) async {
    final rows = snapshot['mangas'];
    if (rows is! List) return const [];
    final blobs = <Uint8List>[];
    final cleaned = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final id = row['id'];
      final blob = id is String ? await _readMangaCover(cache, id) : null;
      if (blob == null) {
        row.remove('cover_index');
      } else {
        row['cover_index'] = blobs.length;
        blobs.add(blob);
      }
      cleaned.add(row);
    }
    snapshot['mangas'] = cleaned;
    return blobs;
  }

  /// This device's thumbnail for [mangaId]. The name is derived from the id
  /// (`manga_cache/covers/<id prefix>.jpg`), which is why the archive needs no
  /// path. Null when the cache is unavailable or the book has no thumbnail.
  static Future<Uint8List?> _readMangaCover(
    CacheService? cache,
    String mangaId,
  ) async {
    if (cache == null) return null;
    try {
      final file = cache.mangaCoverFile(mangaId);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
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
  /// All production archive creators ([uploadBackup], [SyncService.exportToDownloads]
  /// binary path) must use this — not [buildArchiveBytes] (sqflite legacy).
  /// When Rust lib is loaded, use Core; else throw (no silent sqflite fallback).
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
          throw StateError('err.backupEncryptedNeedPassphrase');
        }
        bytes = await BackupCrypto.decrypt(data: data, passphrase: passphrase);
      }

      final Map<String, dynamic> payload;
      if (WmpContainer.looksLikeContainer(bytes)) {
        // Peek section 2 (tracks) to detect Core JSON vs Android binary BK.
        final container = WmpContainer.fromBytes(bytes);
        final tracksRaw = container.readSection(WmpSections.tracks);

        if (tracksRaw != null && _looksLikeJsonSection(tracksRaw)) {
          // Core JSON backup → route through FFI restore.
          // Write the **original** data (encrypted envelope if that's what
          // caller passed) to temp, so Core decrypts itself.
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

        // Android binary backup → existing decode path.
        payload = await _decodeContainer(bytes);
      } else {
        // Readable JSON export (no cover bytes) — accepted as an interchange
        // format for troubleshooting / hand editing.
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw StateError('err.backupUnrecognizedContent');
        payload = Map<String, dynamic>.from(decoded);
      }

      final missing = await _applyPayload(payload, passphrase);
      // Two credential shapes reach here: a [DecodedVault] from a binary
      // archive section, or the `{accounts: [...]}` map from a JSON export.
      final accountCount = switch (payload['credentials']) {
        DecodedVault v => v.entryCount,
        Map m => (m['accounts'] as List<dynamic>?)?.length ?? 0,
        _ => 0,
      };
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

  /// Decode a [WmpContainer] archive into the payload shape [_applyPayload]
  /// expects. Covers are written into this device's cover cache here, so the
  /// restored rows point at real local files.
  ///
  /// `credentials` comes out as a [DecodedVault] and `playlists` as
  /// `List<Playlist>` — the very objects the WebDAV pull path applies, so a
  /// restored archive and a pulled sync cannot disagree. `settings` and
  /// `cueAlbums` stay JSON.
  Future<Map<String, dynamic>> _decodeContainer(Uint8List bytes) async {
    final container = WmpContainer.fromBytes(bytes);
    // A shard is a valid container but not a backup: say so plainly instead of
    // failing later on a missing section.
    if (container.kind != WmpFileKind.backup &&
        container.kind != WmpFileKind.exportBundle) {
      throw WmpFormatException('err.notBackupArchive|${container.kind}');
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
      int coverStateOverride = 0;
      if (idx is int && idx >= 0 && idx < covers.length) {
        final written = await _writeLocalCover(
          sourceName: track.sourceName,
          remotePath: track.remotePath,
          blob: covers[idx].bytesIn(coversRaw!),
        );
        if (written != null) coverStateOverride = 2;
      }
      tracks.add({...track.toMap(), 'cover_state': coverStateOverride});
    }

    // Credentials: this section is one whole `WDMMCV01` document (or absent).
    // Decoding through the vault codec — rather than re-inventing the fields —
    // is what makes the archive and the sync root share a single encoder.
    final credentialsRaw = container.readSection(WmpSections.credentials);
    final vault = (credentialsRaw == null || credentialsRaw.isEmpty)
        ? null
        : CredentialVaultCodec.decode(credentialsRaw);

    // Playlists: one record per playlist, each blob a whole `WDMMPL01` file.
    final playlistsRaw = container.readSection(WmpSections.playlists);
    final playlistRecords = (playlistsRaw == null || playlistsRaw.isEmpty)
        ? const <Map<int, Object?>>[]
        : decodeRecords(
            playlistsRaw,
            intTags: const {},
            bytesTags: const {WmpBackupPlaylist.blob},
          );
    final playlists = <Playlist>[];
    for (final record in playlistRecords) {
      final blob = record[WmpBackupPlaylist.blob];
      if (blob is! Uint8List || blob.isEmpty) continue;
      // The same decoder the WebDAV pull uses (docs/10 §4.3).
      playlists.add(PlaylistCodec.decode(blob).playlist);
    }

    // Manga thumbnails: written straight to this device's id-derived cache
    // path, so the row itself needs nothing back. `cover_index` is consumed
    // here — a restored row must not index a section it no longer carries.
    final mangaLibrary = await restoreMangaThumbnails(
      snapshot: jsonSection(WmpSections.mangaLibrary),
      coversSection: container.readSection(WmpSections.mangaCovers),
      cache: _cache,
    );

    return {
      'format': header['format'] ?? format,
      'formatVersion': header['formatVersion'] ?? formatVersion,
      'activeAccountId': header['activeAccountId'],
      'passwordEncryption': header['passwordEncryption'],
      'credentials': vault,
      'library': {
        'tracks': tracks,
        'cueSlices': const <dynamic>[],
        'cueAlbums': jsonList(WmpSections.cueAlbums),
        'cache': const <dynamic>[],
      },
      'playlists': playlists,
      'settings': jsonSection(WmpSections.settings),
      'mangaLibrary': mangaLibrary,
      'userFolders': jsonSection(WmpSections.userFolders),
      'dmrPrefs': jsonList(WmpSections.dmrPrefs),
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
      final file = File(
        p.join(dir.path, _covers.coverFileName(sourceName, remotePath)),
      );
      await file.writeAsBytes(blob, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Write a restored manga thumbnail back to its derived cache path. A
  /// failure costs a thumbnail, never the library row.
  static Future<void> _writeMangaCover(
    CacheService? cache,
    String mangaId,
    Uint8List blob,
  ) async {
    if (cache == null) return;
    try {
      final file = cache.mangaCoverFile(mangaId);
      final dir = file.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      await file.writeAsBytes(blob, flush: true);
    } catch (_) {}
  }

  /// The inverse of [collectMangaCovers]: write the archive's manga thumbnails
  /// into this device's cache and strip the `cover_index` the archive used
  /// internally.
  ///
  /// Separate from [_decodeContainer] because this half needs no database — the
  /// path comes from the row id alone. An out-of-range index or a row without an
  /// id costs that one thumbnail; nothing else in the archive is affected.
  @visibleForTesting
  static Future<Map<String, dynamic>> restoreMangaThumbnails({
    required Map<String, dynamic> snapshot,
    required Uint8List? coversSection,
    required CacheService? cache,
  }) async {
    final rows = snapshot['mangas'];
    if (rows is! List) return snapshot;
    final covers = coversSection == null
        ? const <WmpCoverEntry>[]
        : parseCoverSection(coversSection);
    final kept = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final idx = row.remove('cover_index');
      final id = row['id'];
      if (id is String &&
          idx is int &&
          idx >= 0 &&
          idx < covers.length &&
          coversSection != null) {
        await _writeMangaCover(cache, id, covers[idx].bytesIn(coversSection));
      }
      kept.add(row);
    }
    snapshot['mangas'] = kept;
    return snapshot;
  }

  /// Check if [raw] bytes look like UTF-8 JSON (starts with `[` or `{`).
  static bool _looksLikeJsonSection(Uint8List raw) {
    if (raw.isEmpty) return false;
    try {
      final str = utf8.decode(raw, allowMalformed: false).trim();
      return str.startsWith('[') || str.startsWith('{');
    } catch (_) {
      return false;
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
