import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../utils/m3u8_playlist.dart';
import 'playlist_store.dart';
import 'webdav_service.dart';

/// Local playlist CRUD + optional WebDAV M3U8 sync (last-write-wins).
class PlaylistService extends ChangeNotifier {
  PlaylistService({
    PlaylistStore? store,
    required WebDavService webDav,
  })  : _store = store ?? PlaylistStore(),
        _webDav = webDav;

  final PlaylistStore _store;
  final WebDavService _webDav;
  final _uuid = const Uuid();

  final List<Playlist> _playlists = [];
  bool _loaded = false;
  String _remotePath = '/Playlists/';
  bool _syncEnabled = true;
  String? _lastSyncError;

  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);
  bool get loaded => _loaded;
  String get remotePath => _remotePath;
  bool get syncEnabled => _syncEnabled;
  String? get lastSyncError => _lastSyncError;
  PlaylistStore get store => _store;

  void configureSync({required String remotePath, required bool enabled}) {
    _remotePath = _normalizeDir(remotePath);
    _syncEnabled = enabled;
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
    pl.remoteFileName = M3u8PlaylistCodec.safeFileName(pl.name, pl.id);
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
    pl.remoteFileName ??= M3u8PlaylistCodec.safeFileName(pl.name, pl.id);
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
    if (deleteRemote && pl != null && _syncEnabled && _webDav.isConnected) {
      final remote = _remoteFilePath(pl);
      try {
        await _webDav.deletePath(remote);
      } catch (_) {}
    }
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
    pl.entries.removeWhere((e) => e.identityKey == entry.identityKey);
    pl.updatedAt = DateTime.now().toUtc();
    await _store.upsert(pl);
    notifyListeners();
    unawaitedSyncUpload(pl);
  }

  Future<void> clearAllLocal() async {
    await _store.clearAll();
    _playlists.clear();
    notifyListeners();
  }

  /// Pull remote M3U8 files and merge last-write-wins into local store.
  Future<void> pullAndMergeFromWebDav() async {
    if (!_syncEnabled || !_webDav.isConnected) return;
    try {
      await _webDav.ensureDirectory(_remotePath);
      final items = await _webDav.listDirectory(_remotePath);
      final remotes = <Playlist>[];
      for (final item in items) {
        if (item.isDirectory) continue;
        final name = item.name.toLowerCase();
        if (!name.endsWith('.m3u8') && !name.endsWith('.m3u')) continue;
        final bytes = await _webDav.readAsBytes(item.path);
        final text = utf8.decode(bytes, allowMalformed: true);
        final decoded = M3u8PlaylistCodec.decode(
          text,
          fallbackName: item.name.replaceAll(RegExp(r'\.m3u8?$', caseSensitive: false), ''),
        );
        decoded.remoteFileName = item.name;
        remotes.add(decoded);
      }

      final byId = {for (final p in _playlists) p.id: p};
      for (final remote in remotes) {
        final local = byId[remote.id];
        if (local == null) {
          byId[remote.id] = remote;
        } else {
          byId[remote.id] = mergePlaylistsLastWriteWins(local, remote);
        }
      }
      // Also match by remote file name if id differs (imported plain m3u8).
      for (final remote in remotes) {
        if (byId.containsKey(remote.id)) continue;
      }

      final merged = byId.values.toList();
      await _store.replaceAll(merged);
      _playlists
        ..clear()
        ..addAll(merged);
      _sortLocal();
      _lastSyncError = null;
      notifyListeners();

      // Push locals that won / are newer.
      for (final pl in _playlists) {
        await uploadPlaylist(pl);
      }
    } catch (e) {
      _lastSyncError = e.toString();
      notifyListeners();
    }
  }

  Future<void> uploadPlaylist(Playlist pl) async {
    if (!_syncEnabled || !_webDav.isConnected) return;
    pl.remoteFileName ??= M3u8PlaylistCodec.safeFileName(pl.name, pl.id);
    await _webDav.ensureDirectory(_remotePath);
    final body = M3u8PlaylistCodec.encode(pl);
    await _webDav.writeBytes(_remoteFilePath(pl), Uint8List.fromList(utf8.encode(body)));
    await _store.upsert(pl);
  }

  void unawaitedSyncUpload(Playlist pl) {
    if (!_syncEnabled || !_webDav.isConnected) return;
    // Fire-and-forget; errors stored on service.
    Future(() async {
      try {
        await uploadPlaylist(pl);
        _lastSyncError = null;
      } catch (e) {
        _lastSyncError = e.toString();
        notifyListeners();
      }
    });
  }

  String _remoteFilePath(Playlist pl) {
    final file = pl.remoteFileName ?? M3u8PlaylistCodec.safeFileName(pl.name, pl.id);
    final base = _remotePath.endsWith('/') ? _remotePath : '$_remotePath/';
    return '$base$file';
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


  /// Playlists that reference [accountId] (any entry). Entries keep their accountId labels.
  List<Map<String, dynamic>> exportJsonForAccount(String accountId) {
    return _playlists
        .where((p) => p.entries.any((e) => e.accountId == accountId))
        .map((p) => p.toJson())
        .toList();
  }

  /// Merge playlists from backup/sync JSON without wiping unrelated local lists.
  Future<void> mergeFromJson(List<dynamic> list) async {
    for (final raw in list) {
      final incoming = Playlist.fromJson(Map<String, dynamic>.from(raw as Map));
      final local = findById(incoming.id);
      if (local == null) {
        await _store.upsert(incoming);
      } else {
        final winner = mergePlaylistsLastWriteWins(local, incoming);
        await _store.upsert(winner);
      }
    }
    await refresh();
  }

  /// Export all playlists as JSON (for backup).
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
