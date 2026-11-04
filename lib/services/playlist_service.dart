import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../models/playlist_deletion.dart';
import '../models/playlist_sentinels.dart';
import '../utils/cover_image.dart';
import '../utils/track_identity.dart';
import 'cover_service.dart';
import 'playlist_cover_policy.dart';
import 'playlist_deletion_log.dart';
import 'playlist_store.dart';
import 'playlist_sync_plan.dart';
import 'rust_core_service.dart';
import 'webdav_service.dart';

/// Local playlist CRUD + optional WebDAV `WDMMPL01` sync (last-write-wins).
///
/// Each playlist is one self-contained `.wdmp` document — see docs/10 §4.2.
/// There is no `.m3u8` write path any more: the plan is to write only the new
/// format and never delete whatever legacy files a server already holds
/// (docs/10 §4.5).
class PlaylistService extends ChangeNotifier {
  PlaylistService({
    PlaylistStore? store,
    PlaylistDeletionLog? deletions,
    required WebDavService webDav,
    CoverService? covers,
  }) : _store = store ?? PlaylistStore(),
       _deletions = deletions,
       _webDav = webDav,
       coverPolicy = PlaylistCoverPolicy(covers: covers),
       _coverService = covers;

  final PlaylistStore _store;
  PlaylistDeletionLog? _deletions;
  final WebDavService _webDav;
  final CoverService? _coverService;
  final _uuid = const Uuid();

  /// Cover tier / edge-length for embedded playlist art.
  final PlaylistCoverPolicy coverPolicy;

  final List<Playlist> _playlists = [];
  bool _loaded = false;
  String _remotePath = '/Playlists/';
  bool _syncEnabled = true;

  /// Account that owns the playlist `.wdmp` mirror (set from Settings). The
  /// music library never depends on it.
  String? _syncAccountId;
  String? _lastSyncError;

  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);
  bool get loaded => _loaded;
  String get remotePath => _remotePath;
  bool get syncEnabled => _syncEnabled;
  String? get lastSyncError => _lastSyncError;
  PlaylistStore get store => _store;

  PlaylistDeletionLog get _log =>
      _deletions ??= MemoryPlaylistDeletionLog();

  /// Library-side thumb edge length, used when [coverPolicy] has no override.
  int get _libraryCoverEdge => _coverService?.thumbSize ?? coverThumbSize;

  Future<void> closeDatabase() => _store.close();

  /// Whether a usable destination account is configured for playlist sync.
  bool get canSync =>
      _syncEnabled &&
      _syncAccountId != null &&
      _webDav.hasAccount(_syncAccountId!);

  void configureSync({
    required String remotePath,
    required bool enabled,
    String? accountId,
  }) {
    _remotePath = _normalizeDir(remotePath);
    _syncEnabled = enabled;
    _syncAccountId = accountId;
  }

  /// No-op stub kept for call-site compatibility. The sqflite backing is gone;
  /// no separate database open step is needed.
  Future<void> openDatabase() async {}

  Future<void> init() async {
    _playlists
      ..clear()
      ..addAll(await _store.loadAll());
    _loaded = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    _playlists
      ..clear()
      ..addAll(await _store.loadAll());
    notifyListeners();
  }

  Playlist? findById(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Playlist> create({
    required String name,
    List<PlaylistEntry> entries = const [],
  }) async {
    final pl = Playlist(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? '新歌单' : name.trim(),
      entries: entries,
      updatedAt: DateTime.now().toUtc(),
    );
    pl.remoteFileName = _playlistFileName(pl);
    await _store.upsert(pl);
    _playlists.add(pl);
    _sortLocal();
    notifyListeners();
    unawaitedSyncUpload(pl);
    return pl;
  }

  /// Snapshot the ephemeral playback queue into a new saved playlist.
  Future<Playlist> createFromQueue({
    required String name,
    required List<PlaylistEntry> queueEntries,
  }) {
    return create(name: name, entries: queueEntries);
  }

  Future<void> rename(String id, String name) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final pl = _playlists[idx];
    pl.name = name.trim().isEmpty ? pl.name : name.trim();
    pl.updatedAt = DateTime.now().toUtc();
    pl.remoteFileName ??= _playlistFileName(pl);
    await _store.upsert(pl);
    _sortLocal();
    notifyListeners();
    unawaitedSyncUpload(pl);
  }

  Future<void> deletePlaylist(String id, {bool deleteRemote = true}) async {
    final pl = findById(id);
    await _store.delete(id);
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    if (!deleteRemote || pl == null) return;
    final deletedAt = DateTime.now().toUtc();
    await _log.upsert([PlaylistDeletion(playlistId: id, deletedAt: deletedAt)]);
    _publish(() async {
      await _uploadPack(id);
      try {
        await _webDav.deletePath(_syncAccountId!, _remoteFilePath(pl));
      } catch (_) {}
    });
  }

  Future<void> addTrack(String playlistId, PlaylistEntry entry) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = _playlists[idx];
    if (pl.entries.any((e) => e.identityKey == entry.identityKey)) return;
    pl.entries.add(entry);
    pl.updatedAt = DateTime.now().toUtc();
    await _store.upsert(pl);
    notifyListeners();
    unawaitedSyncUpload(pl);
  }

  Future<void> removeTrack(String playlistId, PlaylistEntry entry) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = _playlists[idx];
    final before = pl.entries.length;
    pl.entries.removeWhere((e) => e.identityKey == entry.identityKey);
    if (pl.entries.length == before) return;
    final now = DateTime.now().toUtc();
    pl.updatedAt = now;
    await _log.upsert([
      PlaylistDeletion(
        playlistId: playlistId,
        entryIdentity: entry.identityKey,
        deletedAt: now,
      ),
    ]);
    await _store.upsert(pl);
    notifyListeners();
    _publish(() async {
      await _uploadPack(playlistId);
      await uploadPlaylist(pl);
    });
  }

  /// Replace [oldEntry] with [newEntry] in place (same list index).
  ///
  /// Used after remote-missing redirect: library row is retargeted, then the
  /// playlist reference follows the new musicId / path. Records a deletion for
  /// the old identity so sync peers drop the stale reference.
  Future<void> replaceTrack(
    String playlistId,
    PlaylistEntry oldEntry,
    PlaylistEntry newEntry,
  ) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = _playlists[idx];
    final at = pl.entries.indexWhere((e) => e.identityKey == oldEntry.identityKey);
    if (at < 0) return;
    if (oldEntry.identityKey == newEntry.identityKey) {
      pl.entries[at] = newEntry;
      pl.updatedAt = DateTime.now().toUtc();
      await _store.upsert(pl);
      notifyListeners();
      unawaitedSyncUpload(pl);
      return;
    }
    // Avoid duplicate if new identity already exists elsewhere in the list.
    final dup = pl.entries.indexWhere((e) => e.identityKey == newEntry.identityKey);
    if (dup >= 0 && dup != at) {
      pl.entries.removeAt(at);
    } else {
      pl.entries[at] = newEntry;
    }
    final now = DateTime.now().toUtc();
    pl.updatedAt = now;
    await _log.upsert([
      PlaylistDeletion(
        playlistId: playlistId,
        entryIdentity: oldEntry.identityKey,
        deletedAt: now,
      ),
    ]);
    await _store.upsert(pl);
    notifyListeners();
    _publish(() async {
      await _uploadPack(playlistId);
      await uploadPlaylist(pl);
    });
  }

  /// Mirror cloud-absence onto playlist entries (independent of music library).
  ///
  /// Matches by [identityKeys] (musicId). No-op when nothing changes. Persists
  /// and notifies; sync upload is best-effort like other entry edits.
  Future<void> setRemoteMissingForIdentities({
    required Iterable<String> identityKeys,
    required bool missing,
  }) async {
    final keys = identityKeys.where((k) => k.isNotEmpty).toSet();
    if (keys.isEmpty) return;
    final touched = <Playlist>[];
    for (final pl in _playlists) {
      var changed = false;
      for (var i = 0; i < pl.entries.length; i++) {
        final e = pl.entries[i];
        if (!keys.contains(e.identityKey) || e.remoteMissing == missing) {
          continue;
        }
        pl.entries[i] = e.copyWith(remoteMissing: missing);
        changed = true;
      }
      if (changed) {
        pl.updatedAt = DateTime.now().toUtc();
        touched.add(pl);
      }
    }
    if (touched.isEmpty) return;
    for (final pl in touched) {
      await _store.upsert(pl);
    }
    notifyListeners();
    for (final pl in touched) {
      unawaitedSyncUpload(pl);
    }
  }

  /// Convenience: resolve musicId from source + path (+ optional CUE index).
  Future<void> setRemoteMissingForPath({
    required String sourceName,
    required String remotePath,
    int? cueTrackIndex,
    String? cueRemotePath,
    required bool missing,
  }) {
    final id = musicIdForLibraryRow(
      sourceName: sourceName,
      remotePath: remotePath,
      cueRemotePath: cueRemotePath,
      cueTrackIndex: cueTrackIndex,
    );
    return setRemoteMissingForIdentities(
      identityKeys: [id],
      missing: missing,
    );
  }

    /// Drop playlist entries whose identity is not in [validKeys]
  /// (`accountId\0remotePath` via [PlaylistEntry.identityKey]).
  /// Keeps playlist shells; empties entries that all became orphans.
  Future<int> removeEntriesNotIn(Set<String> validKeys) async {
    var removed = 0;
    for (final pl in _playlists) {
      final removedEntries = <PlaylistEntry>[];
      pl.entries.removeWhere((e) {
        if (validKeys.contains(e.identityKey)) return false;
        removedEntries.add(e);
        return true;
      });
      final n = removedEntries.length;
      if (n > 0) {
        removed += n;
        final now = DateTime.now().toUtc();
        pl.updatedAt = now;
        await _log.upsert([
          for (final entry in removedEntries)
            PlaylistDeletion(
              playlistId: pl.id,
              entryIdentity: entry.identityKey,
              deletedAt: now,
            ),
        ]);
        await _store.upsert(pl);
        _publish(() async {
          await _uploadPack(pl.id);
          await uploadPlaylist(pl);
        });
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  Future<void> clearAllLocal() async {
    await _store.clearAll();
    await _log.clear();
    _playlists.clear();
    notifyListeners();
  }

  /// Pull remote playlist documents and per-playlist deletion packs.
  ///
  /// Legacy `.m3u`/`.m3u8` files are **ignored, not read and not deleted**.
  /// A malformed file is skipped. Unchanged local playlists are **not**
  /// uploaded: re-uploading every document after a pull is how a delete on
  /// another device comes back.
  ///
  /// Returns false when the pull itself failed (nothing was published).
  Future<bool> pullAndMergeFromWebDav({bool publishPacks = true}) async {
    if (!canSync) return false;
    try {
      await _webDav.ensureDirectory(_syncAccountId!, _remotePath);
      final items = await _webDav.listDirectory(_syncAccountId!, _remotePath);
      final remotes = <Playlist>[];
      final remotePacks = <String, List<PlaylistDeletion>>{};
      final stalePackNames = <String>[];
      final canonicalPackSeen = <String>{};
      for (final item in items) {
        if (item.isDirectory) continue;
        if (!_looksLikePlaylistFileName(item.name)) continue;
        try {
          final bytes = await _webDav.readAsBytes(_syncAccountId!, item.path);
          final decoded = _decodePlaylistDocument(bytes);
          // 同目录下的其它 `WDMM*` 容器不属于歌单，直接忽略。
          if (decoded == null) continue;
          if (decoded['kind'] == 'deletion') {
            final playlistId = decoded['playlist_id'] as String? ?? '';
            if (playlistId.isEmpty) continue;
            remotePacks
                .putIfAbsent(playlistId, () => [])
                .addAll(_deletionsFromReply(decoded, playlistId));
            if (item.name == _deletionFileName(playlistId)) {
              canonicalPackSeen.add(playlistId);
            } else {
              // Content is merged, but the canonical name is what the next
              // pull looks up. A misnamed pack is rewritten, then removed.
              stalePackNames.add(item.name);
            }
          } else {
            final remote = _playlistFromReply(decoded);
            remote.remoteFileName = item.name;
            remotes.add(remote);
          }
        } catch (e) {
          // Format/CRC failure on one file: skip it, keep the rest.
          _lastSyncError = e.toString();
        }
      }

      final localDeletions = await _log.loadAll();
      final plan = planPlaylistSync(
        local: _playlists,
        remote: remotes,
        tombstones: [
          ...localDeletions,
          for (final rows in remotePacks.values) ...rows,
        ],
        remotePacks: remotePacks,
      );
      await _store.replaceAll(plan.playlists);
      await _log.replaceAll(plan.tombstones);
      _playlists
        ..clear()
        ..addAll(plan.playlists);
      _sortLocal();
      notifyListeners();

      if (publishPacks) {
        final packIds = {
          ...plan.uploadPackIds,
          for (final record in plan.tombstones)
            if (!canonicalPackSeen.contains(record.playlistId))
              record.playlistId,
        };
        for (final id in packIds) {
          await _uploadPack(id);
        }
      }
      for (final name in {...stalePackNames, ...plan.deleteRemoteNames}) {
        try {
          await _webDav.deletePath(_syncAccountId!, _filePath(name));
        } catch (_) {}
      }
      for (final pl in plan.upload) {
        await uploadPlaylist(pl);
      }
      _lastSyncError = null;
      return true;
    } catch (e) {
      _lastSyncError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Materialise the current playlists, then drop every deletion pack.
  ///
  /// Manual only. There is no periodic prompt: after this, an offline device
  /// that still has the old copy can upload it again, the same way a library
  /// rebuild drops `del-*` once the snapshot is the truth.
  Future<void> compactDeletionQueue() async {
    if (!canSync) throw StateError('err.noWebdavAccount');
    final ok = await pullAndMergeFromWebDav(publishPacks: false);
    if (!ok) {
      throw StateError(_lastSyncError ?? 'err.noWebdavAccount');
    }
    final items = await _webDav.listDirectory(_syncAccountId!, _remotePath);
    for (final item in items) {
      if (item.isDirectory) continue;
      if (!_looksLikePlaylistFileName(item.name)) continue;
      try {
        final bytes = await _webDav.readAsBytes(_syncAccountId!, item.path);
        final decoded = _decodePlaylistDocument(bytes);
        if (decoded == null || decoded['kind'] != 'deletion') continue;
        await _webDav.deletePath(_syncAccountId!, item.path);
      } catch (e) {
        _lastSyncError = e.toString();
        notifyListeners();
        throw StateError(_lastSyncError!);
      }
    }
    await _log.clear();
    _lastSyncError = null;
  }

  /// Encode one playlist as a `WDMMPL01` document (with its entries' covers)
  /// and upload it.
  ///
  /// Cover bytes are read fresh from disk on every upload instead of being
  /// cached: the library can re-ingest art at any time, and a stale embedded
  /// copy is worse than no copy. Missing art is not an error — the entry is
  /// written without a `coverIndex`.
  Future<void> uploadPlaylist(Playlist pl) async {
    if (!canSync) return;
    final document = await encodePlaylistDocument(pl);
    pl.remoteFileName = document.fileName;
    await _webDav.ensureDirectory(_syncAccountId!, _remotePath);
    await _webDav.writeBytes(
      _syncAccountId!,
      _filePath(document.fileName),
      document.bytes,
    );
    await _store.upsert(pl);
  }

  /// Encode [pl] to bytes without uploading — used by backup embedding (⑥) and
  /// by tests.
  Future<Uint8List> encodePlaylistBytes(
    Playlist pl, {
    bool withCovers = true,
  }) async {
    return (await encodePlaylistDocument(pl, withCovers: withCovers)).bytes;
  }

  /// Encode [pl] with the Rust document engine; the reply carries the file
  /// name (Rust is the only place the naming rule lives).
  Future<({String fileName, Uint8List bytes})> encodePlaylistDocument(
    Playlist pl, {
    bool withCovers = true,
  }) async {
    final covers = withCovers
        ? await readCoversForPlaylist(
            pl,
            policy: coverPolicy,
            fallbackEdgeSize: _libraryCoverEdge,
          )
        : null;
    return _encodePlaylistDocument(pl, covers: covers);
  }

  void unawaitedSyncUpload(Playlist pl) {
    _publish(() => uploadPlaylist(pl));
  }

  void _publish(Future<void> Function() body) {
    if (!canSync) return;
    Future(() async {
      try {
        await body();
        _lastSyncError = null;
      } catch (e) {
        _lastSyncError = e.toString();
        notifyListeners();
      }
    });
  }

  Future<void> _uploadPack(String playlistId) async {
    if (!canSync) return;
    final records = [
      for (final record in await _log.loadAll())
        if (record.playlistId == playlistId) record,
    ];
    if (records.isEmpty) return;
    await _webDav.ensureDirectory(_syncAccountId!, _remotePath);
    final pack = _encodeDeletionPack(playlistId, records);
    await _webDav.writeBytes(
      _syncAccountId!,
      _filePath(pack.fileName),
      pack.bytes,
    );
  }

  String _remoteFilePath(Playlist pl) {
    final file = pl.remoteFileName ?? _playlistFileName(pl);
    return _filePath(file);
  }

  String _filePath(String fileName) {
    final base = _remotePath.endsWith('/') ? _remotePath : '$_remotePath/';
    return '$base$fileName';
  }

  void _sortLocal() {
    _playlists.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  // ── WDMMPL01 / WDMMPD01 document engine (Rust owns the wire format) ──────

  /// `.wdmp` is the only extension the playlist sync root holds.
  static const _playlistFileExtension = 'wdmp';

  bool _looksLikePlaylistFileName(String name) =>
      name.toLowerCase().endsWith('.$_playlistFileExtension');

  /// Encode [pl] through `wdmm_playlist_encode`; covers are parallel to entries.
  ({String fileName, Uint8List bytes}) _encodePlaylistDocument(
    Playlist pl, {
    List<Uint8List?>? covers,
  }) {
    final payload = {
      'kind': 'playlist',
      'device_id': '',
      'playlist': {
        'id': pl.id,
        'name': pl.name,
        'created_at': null,
        'updated_at': pl.updatedAt.toUtc().toIso8601String(),
        'entries': [
          for (final entry in pl.entries)
            {
              'music_id': entry.musicId,
              'source_name': entry.sourceName,
              'remote_path': entry.remotePath,
              'title': entry.title,
              'duration_ms': entry.durationMs,
              'cue_track_index': entry.cueTrackIndex,
              'cover_index': null,
              'remote_missing': entry.remoteMissing,
            },
        ],
      },
      'covers': [
        for (final cover in covers ?? const <Uint8List?>[])
          if (cover == null || cover.isEmpty) null else base64Encode(cover),
      ],
    };
    return _encodePlaylistReply(
      payload,
      'playlist encode',
      fallbackFileName: pl.remoteFileName,
    );
  }

  /// File name the Rust engine assigns to [pl] (no cover bytes needed).
  String _playlistFileName(Playlist pl) =>
      _encodePlaylistDocument(pl, covers: null).fileName;

  /// Encode one playlist deletion pack (`WDMMPD01`).
  ({String fileName, Uint8List bytes}) _encodeDeletionPack(
    String playlistId,
    List<PlaylistDeletion> records,
  ) {
    final payload = {
      'kind': 'deletion',
      'device_id': '',
      'playlist_id': playlistId,
      'created_at': null,
      'updated_at': null,
      'records': [
        for (final record in records)
          {
            'entry_identity': record.entryIdentity,
            'deleted_at': record.deletedAt.toUtc().toIso8601String(),
          },
      ],
    };
    return _encodePlaylistReply(payload, 'deletion encode');
  }

  /// Canonical file name of a playlist's deletion pack.
  String _deletionFileName(String playlistId) =>
      _encodeDeletionPack(playlistId, const []).fileName;

  ({String fileName, Uint8List bytes}) _encodePlaylistReply(
    Map<String, dynamic> payload,
    String what, {
    String? fallbackFileName,
  }) {
    final reply = _rustReply(
      RustCoreService.playlistEncode(jsonEncode(payload)),
      what,
    );
    final encoded = reply['bytes_base64'];
    if (encoded is! String || encoded.isEmpty) {
      throw FormatException('$what returned no bytes');
    }
    final name = reply['file_name'];
    final fileName = name is String && name.isNotEmpty
        ? name
        : (fallbackFileName ?? '${payload['playlist_id'] ?? ''}.wdmp');
    return (fileName: fileName, bytes: base64Decode(encoded));
  }

  /// Decode one `.wdmp` file; null when the container is not a playlist or a
  /// playlist deletion pack (some other feature's document in the same dir).
  Map<String, dynamic>? _decodePlaylistDocument(Uint8List bytes) {
    final raw = RustCoreService.playlistDecode(bytes);
    if (raw == null || raw.isEmpty) {
      throw StateError('err.rustUnavailable:playlist decode');
    }
    if (raw == _unsupportedContainerError) return null;
    return _rustReply(raw, 'playlist decode');
  }

  Playlist _playlistFromReply(Map<String, dynamic> reply) {
    final raw = reply['playlist'];
    if (raw is! Map) {
      throw const FormatException('playlist decode returned no playlist');
    }
    final data = Map<String, dynamic>.from(raw);
    final entries = <PlaylistEntry>[];
    for (final entry in (data['entries'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final values = Map<String, dynamic>.from(entry);
      entries.add(
        PlaylistEntry(
          sourceName: values['source_name'] as String? ?? '',
          remotePath: values['remote_path'] as String? ?? '',
          musicId: values['music_id'] as String?,
          title: values['title'] as String?,
          durationMs: (values['duration_ms'] as num?)?.toInt(),
          cueTrackIndex: (values['cue_track_index'] as num?)?.toInt(),
          remoteMissing: values['remote_missing'] == true,
        ),
      );
    }
    final name = (data['name'] as String? ?? '').trim();
    return Playlist(
      id: data['id'] as String? ?? '',
      name: name.isEmpty ? kUnnamedPlaylistName : name,
      entries: entries,
      updatedAt:
          DateTime.tryParse(data['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  List<PlaylistDeletion> _deletionsFromReply(
    Map<String, dynamic> reply,
    String playlistId,
  ) {
    final records = <PlaylistDeletion>[];
    for (final record in (reply['records'] as List? ?? const [])) {
      if (record is! Map) continue;
      final values = Map<String, dynamic>.from(record);
      final deletedAt = DateTime.tryParse(
        values['deleted_at'] as String? ?? '',
      );
      if (deletedAt == null) continue;
      records.add(
        PlaylistDeletion(
          playlistId: playlistId,
          entryIdentity: values['entry_identity'] as String? ?? '',
          deletedAt: deletedAt.toUtc(),
        ),
      );
    }
    return records;
  }

  static String _normalizeDir(String path) {
    var p = path.trim();
    if (p.isEmpty) p = '/Playlists/';
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    return p;
  }

  /// Playlists that reference [accountId] (any entry). Entries keep their sourceName labels.
  List<Map<String, dynamic>> exportJsonForAccount(String accountId) {
    return _playlists
        .where((p) => p.entries.any((e) => e.sourceName == accountId))
        .map((p) => p.toJson())
        .toList();
  }

  /// Merge playlists decoded from a backup document without wiping unrelated
  /// local lists.
  Future<void> mergeFromPlaylists(List<Playlist> incoming) async {
    for (final pl in incoming) {
      final local = findById(pl.id);
      final winner = local == null
          ? pl
          : mergePlaylistsLastWriteWins(local, pl);
      // Keep the file name we already know; the backup blob carries no name.
      if (winner.remoteFileName == null && local != null) {
        winner.remoteFileName = local.remoteFileName;
      }
      await _store.upsert(winner);
    }
    await refresh();
  }

  /// Export all playlists as JSON — human-inspectable export channel only
  /// (`buildJsonExport`). The sync and backup paths use `encodePlaylistBytes`.
  List<Map<String, dynamic>> exportJson() =>
      _playlists.map((p) => p.toJson()).toList();

  Future<void> importFromJson(List<dynamic> list) async {
    for (final raw in list) {
      final pl = Playlist.fromJson(Map<String, dynamic>.from(raw as Map));
      await _store.upsert(pl);
    }
    await refresh();
  }
}

/// Reply of `wdmm_playlist_decode` for a `WDMM*` container that is not a
/// playlist document — the caller skips the file instead of reporting an error.
const _unsupportedContainerError = 'error:unsupported container kind';

/// Parse the JSON reply of an `ext::json_reply` handler.
///
/// Handlers answer `{"ok":true,...}` on success and `error:<msg>` on failure.
/// A null reply means the native library is not available at all.
Map<String, dynamic> _rustReply(String? raw, String what) {
  if (raw == null || raw.isEmpty) {
    throw StateError('err.rustUnavailable:$what');
  }
  if (raw.startsWith('error:')) {
    throw FormatException('$what failed: ${raw.substring('error:'.length)}');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw FormatException('$what returned invalid JSON');
  }
  if (decoded is! Map) {
    throw FormatException('$what returned a non-object reply');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (map['ok'] != true) {
    throw FormatException('$what failed: ${map['error'] ?? raw}');
  }
  return map;
}
