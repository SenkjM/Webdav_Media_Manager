import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../models/playlist_deletion.dart';
import '../utils/cover_image.dart';
import '../utils/wmp_container.dart';
import 'cover_service.dart';
import 'playlist_codec.dart';
import 'playlist_cover_policy.dart';
import 'playlist_deletion_codec.dart';
import 'playlist_deletion_log.dart';
import 'playlist_store.dart';
import 'playlist_sync_plan.dart';
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
      _deletions ??= SqlitePlaylistDeletionLog(() => _store.database);

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

  Future<void> init() async {
    await _store.database;
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
    pl.remoteFileName = PlaylistCodec.safeFileName(pl.name, pl.id);
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
    pl.remoteFileName ??= PlaylistCodec.safeFileName(pl.name, pl.id);
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
        if (!item.name.toLowerCase().endsWith(
          '.${PlaylistCodec.fileExtension}',
        )) {
          continue;
        }
        try {
          final bytes = await _webDav.readAsBytes(_syncAccountId!, item.path);
          final kind = WmpContainer.kindOf(bytes);
          if (kind == WmpFileKind.playlistDeletion) {
            final decoded = PlaylistDeletionCodec.decode(bytes);
            remotePacks
                .putIfAbsent(decoded.playlistId, () => [])
                .addAll(decoded.records);
            if (item.name ==
                PlaylistDeletionCodec.fileNameFor(decoded.playlistId)) {
              canonicalPackSeen.add(decoded.playlistId);
            } else {
              // Content is merged, but the canonical name is what the next
              // pull looks up. A misnamed pack is rewritten, then removed.
              stalePackNames.add(item.name);
            }
          } else if (kind == WmpFileKind.playlist) {
            final decoded = PlaylistCodec.decode(bytes);
            decoded.playlist.remoteFileName = item.name;
            remotes.add(decoded.playlist);
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
      if (!item.name.toLowerCase().endsWith(
        '.${PlaylistCodec.fileExtension}',
      )) {
        continue;
      }
      try {
        final bytes = await _webDav.readAsBytes(_syncAccountId!, item.path);
        if (WmpContainer.kindOf(bytes) != WmpFileKind.playlistDeletion) {
          continue;
        }
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
    pl.remoteFileName ??= PlaylistCodec.safeFileName(pl.name, pl.id);
    await _webDav.ensureDirectory(_syncAccountId!, _remotePath);
    final bytes = await encodePlaylistBytes(pl);
    await _webDav.writeBytes(_syncAccountId!, _remoteFilePath(pl), bytes);
    await _store.upsert(pl);
  }

  /// Encode [pl] to bytes without uploading — used by backup embedding (⑥) and
  /// by tests.
  Future<Uint8List> encodePlaylistBytes(
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
    return PlaylistCodec.encode(pl, coverBlobs: covers);
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
    final bytes = PlaylistDeletionCodec.encode(playlistId, records);
    await _webDav.writeBytes(
      _syncAccountId!,
      _filePath(PlaylistDeletionCodec.fileNameFor(playlistId)),
      bytes,
    );
  }

  String _remoteFilePath(Playlist pl) {
    final file =
        pl.remoteFileName ?? PlaylistCodec.safeFileName(pl.name, pl.id);
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
