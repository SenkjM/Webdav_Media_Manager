import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../utils/track_identity.dart';
import 'playlist_store.dart';
import 'rust_core_service.dart';

/// Local playlist CRUD, plus a "publish right after the edit" hop into Core.
///
/// The cloud side lives entirely in Rust: `wdmm_sync_run` reconciles playlists
/// together with their deletion packs, and `wdmm_playlist_publish` writes the
/// one document a user just changed. This service only owns the in-memory list
/// and the local store, so the old second sync engine (planner, deletion log,
/// cover policy, `.wdmp` encoders) has no reason to exist here.
class PlaylistService extends ChangeNotifier {
  PlaylistService({PlaylistStore? store}) : _store = store ?? PlaylistStore();

  final PlaylistStore _store;
  final _uuid = const Uuid();

  final List<Playlist> _playlists = [];
  bool _loaded = false;

  /// Root of the unified sync tree. Core appends its own `playlists/` segment,
  /// so this is the same root the music/manga sync uses.
  String _syncRoot = '/wdmm_sync';
  bool _syncEnabled = true;
  String? _syncAccountId;
  String? _lastSyncError;

  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);
  bool get loaded => _loaded;
  PlaylistStore get store => _store;

  /// Last failure of a post-edit publish. Full sync failures are reported by
  /// `SyncService`'s own outcome.
  String? get lastSyncError => _lastSyncError;

  Future<void> closeDatabase() => _store.close();

  /// Whether a usable destination is configured for publishing edits.
  bool get canSync => _syncEnabled && _syncAccountId != null;

  /// Point the publisher at the unified 远端路径 + account.
  void configureSync({
    required String syncRoot,
    required bool enabled,
    String? accountId,
  }) {
    _syncRoot = syncRoot;
    _syncEnabled = enabled;
    _syncAccountId = accountId;
  }

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
    for (final pl in _playlists) {
      if (pl.id == id) return pl;
    }
    return null;
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
    await _store.upsert(pl);
    _playlists.add(pl);
    _sortLocal();
    notifyListeners();
    _publishRemote(pl.id);
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
    final pl = findById(id);
    if (pl == null) return;
    pl.name = name.trim().isEmpty ? pl.name : name.trim();
    pl.updatedAt = DateTime.now().toUtc();
    await _store.upsert(pl);
    _sortLocal();
    notifyListeners();
    _publishRemote(pl.id);
  }

  Future<void> deletePlaylist(String id, {bool deleteRemote = true}) async {
    await _store.delete(id);
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    if (!deleteRemote) return;
    // Core's delete wrote the whole-playlist tombstone; publishing it removes
    // the cloud document and leaves a pack peers can consume.
    _publishRemote(id);
  }

  Future<void> addTrack(String playlistId, PlaylistEntry entry) async {
    final pl = findById(playlistId);
    if (pl == null) return;
    if (pl.entries.any((e) => e.identityKey == entry.identityKey)) return;
    pl.entries.add(entry);
    pl.updatedAt = DateTime.now().toUtc();
    await _store.upsert(pl);
    notifyListeners();
    _publishRemote(pl.id);
  }

  Future<void> removeTrack(String playlistId, PlaylistEntry entry) async {
    final pl = findById(playlistId);
    if (pl == null) return;
    final before = pl.entries.length;
    pl.entries.removeWhere((e) => e.identityKey == entry.identityKey);
    if (pl.entries.length == before) return;
    pl.updatedAt = DateTime.now().toUtc();
    // Store diffs the rows, so the removal becomes an entry tombstone that the
    // publish below ships next to the trimmed document.
    await _store.upsert(pl);
    notifyListeners();
    _publishRemote(pl.id);
  }

  /// Replace [oldEntry] with [newEntry] in place (same list index).
  ///
  /// Used after a remote-missing redirect: the library row is retargeted, then
  /// the playlist reference follows the new musicId / path. The store records
  /// the old identity as a tombstone as part of the same upsert.
  Future<void> replaceTrack(
    String playlistId,
    PlaylistEntry oldEntry,
    PlaylistEntry newEntry,
  ) async {
    final pl = findById(playlistId);
    if (pl == null) return;
    final at =
        pl.entries.indexWhere((e) => e.identityKey == oldEntry.identityKey);
    if (at < 0) return;
    if (oldEntry.identityKey == newEntry.identityKey) {
      pl.entries[at] = newEntry;
      pl.updatedAt = DateTime.now().toUtc();
      await _store.upsert(pl);
      notifyListeners();
      _publishRemote(pl.id);
      return;
    }
    // Avoid a duplicate if the new identity already exists elsewhere.
    final dup =
        pl.entries.indexWhere((e) => e.identityKey == newEntry.identityKey);
    if (dup >= 0 && dup != at) {
      pl.entries.removeAt(at);
    } else {
      pl.entries[at] = newEntry;
    }
    pl.updatedAt = DateTime.now().toUtc();
    await _store.upsert(pl);
    notifyListeners();
    _publishRemote(pl.id);
  }

  /// Mirror cloud-absence onto playlist entries (independent of the library).
  ///
  /// Matches by [identityKeys] (musicId). No-op when nothing changes.
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
      _publishRemote(pl.id);
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

  /// Drop playlist entries whose identity is not in [validKeys].
  /// Keeps playlist shells; empties entries that all became orphans.
  Future<int> removeEntriesNotIn(Set<String> validKeys) async {
    var removed = 0;
    for (final pl in _playlists) {
      final before = pl.entries.length;
      pl.entries.removeWhere((e) => !validKeys.contains(e.identityKey));
      final n = before - pl.entries.length;
      if (n == 0) continue;
      removed += n;
      pl.updatedAt = DateTime.now().toUtc();
      await _store.upsert(pl);
      _publishRemote(pl.id);
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Ask Core to write [playlistId] (document + deletion pack) now.
  ///
  /// Best effort: a failure is kept for the playlists screen to show, never
  /// retried in a loop — the next full sync reconciles whatever is left.
  void _publishRemote(String playlistId) {
    if (!canSync) return;
    final accountId = _syncAccountId!;
    Future(() async {
      try {
        final reply = await RustCoreService.runOffMain<String?>(() {
          return RustCoreService.playlistPublish(
            accountId: accountId,
            playlistId: playlistId,
            remoteDir: _syncRoot,
          );
        });
        if (reply == null || reply.startsWith('error:')) {
          _lastSyncError = reply ?? 'err.rustUnavailable:playlist publish';
          notifyListeners();
          return;
        }
        _lastSyncError = null;
      } catch (e) {
        _lastSyncError = e.toString();
        notifyListeners();
      }
    });
  }

  void _sortLocal() {
    _playlists.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  /// Playlists that reference [accountId] (any entry). Entries keep their
  /// sourceName labels.
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
      final winner =
          local == null ? pl : mergePlaylistsLastWriteWins(local, pl);
      await _store.upsert(winner);
    }
    await refresh();
  }

  /// Export all playlists as JSON — human-inspectable export channel only.
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
