import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../models/webdav_account.dart';
import 'accounts_service.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// Bidirectional 「歌曲库同步」 for one WebDAV account/site.
///
/// Syncs (Option B — metadata-first, no audio upload):
/// - library index JSON for that accountId
/// - cover thumbs for those tracks
/// - playlists (via [PlaylistService.pullAndMergeFromWebDav])
///
/// Identity remains `accountId + remotePath`. Remote layout under
/// [SettingsService.librarySyncRemotePath] (default `/WebDAVMusicPlayer/library/`):
/// - `library_index.json`
/// - `covers/<coverFileName>`
class LibrarySyncService extends ChangeNotifier {
  LibrarySyncService({
    required LibraryService library,
    required AccountsService accounts,
    required SettingsService settings,
    required PlaylistService playlists,
    required WebDavService webDav,
  })  : _library = library,
        _accounts = accounts,
        _settings = settings,
        _playlists = playlists,
        _webDav = webDav;

  final LibraryService _library;
  final AccountsService _accounts;
  final SettingsService _settings;
  final PlaylistService _playlists;
  final WebDavService _webDav;

  static const indexFileName = 'library_index.json';
  static const coversSubdir = 'covers';
  static const formatVersion = 1;

  bool busy = false;
  String? lastError;
  String? lastMessage;
  double? progress; // 0..1
  String? progressLabel;

  void _progress(String label, [double? value]) {
    progressLabel = label;
    progress = value;
    notifyListeners();
  }

  String _rootFor(WebDavAccount account) {
    // Path is on the selected site; accountId is recorded inside the JSON.
    var root = _settings.librarySyncRemotePath.trim();
    if (root.isEmpty) root = SettingsService.defaultLibrarySyncRemotePath;
    if (!root.startsWith('/')) root = '/$root';
    if (!root.endsWith('/')) root = '$root/';
    // Namespace by account id so one WebDAV host with multiple app accounts
    // (rare) still stays isolated if they share a URL tree.
    final safeId = account.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final short = safeId.length <= 12 ? safeId : safeId.substring(0, 12);
    return '$root$short/';
  }

  /// Full bidirectional sync for [account] (must be the connected WebDAV).
  Future<void> syncLibrary({WebDavAccount? account}) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    _progress('准备同步…', 0.05);
    try {
      final target = account ?? _accounts.activeAccount;
      if (target == null) {
        throw StateError('请先选择 WebDAV 账号');
      }
      if (!_webDav.isConnected) {
        throw StateError('请先连接 WebDAV 账号');
      }
      if (_webDav.accountId != null && _webDav.accountId != target.id) {
        throw StateError(
          '当前连接的 WebDAV 与所选账号不一致。请切换到该账号后再同步歌曲库。',
        );
      }

      final root = _rootFor(target);
      await _webDav.ensureDirectory(root);
      await _webDav.ensureDirectory('$root$coversSubdir/');

      _progress('拉取远程歌曲索引…', 0.15);
      final remoteTracks = await _pullRemoteIndex(root, target.id);

      _progress('合并本地与远程索引…', 0.35);
      final merged = _mergeTracks(
        local: _library.tracksForAccount(target.id),
        remote: remoteTracks,
        accountId: target.id,
      );
      await _library.replaceTracksForAccount(target.id, merged);

      _progress('同步封面缩略图…', 0.5);
      final coverStats = await _syncCovers(
        account: target,
        tracks: merged,
        root: root,
      );

      _progress('推送歌曲索引…', 0.7);
      await _pushIndex(root: root, account: target, tracks: merged);

      _progress('同步歌单 M3U8…', 0.85);
      await _playlists.pullAndMergeFromWebDav();

      await _library.refresh();
      lastMessage =
          '歌曲库同步完成（站点「${target.name}」）：'
          '${merged.length} 首；封面 ↑${coverStats.$1} ↓${coverStats.$2}；'
          '歌单已刷新。';
      _progress('完成', 1);
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<LibraryTrack>> _pullRemoteIndex(
    String root,
    String accountId,
  ) async {
    final remote = '$root$indexFileName';
    try {
      final bytes = await _webDav.readAsBytes(remote);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final id = json['accountId'] as String?;
      if (id != null && id != accountId) {
        throw StateError(
          '远程 library_index.json 的 accountId=$id 与当前账号 $accountId 不一致，已中止以免串站',
        );
      }
      final list = json['tracks'] as List<dynamic>? ?? [];
      final out = <LibraryTrack>[];
      for (final e in list) {
        final t = LibraryTrack.fromMap(Map<String, dynamic>.from(e as Map));
        if (t.accountId != accountId) {
          throw StateError(
            '远程曲目 accountId=${t.accountId} 与站点 $accountId 不一致',
          );
        }
        out.add(t);
      }
      return out;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('404') ||
          msg.contains('not found') ||
          msg.contains('does not exist')) {
        return [];
      }
      // Missing file is fine; other errors propagate.
      if (e is StateError) rethrow;
      // Some WebDAV servers throw generic errors for missing files — treat as empty
      // only when message looks like not-found; otherwise rethrow.
      rethrow;
    }
  }

  List<LibraryTrack> _mergeTracks({
    required List<LibraryTrack> local,
    required List<LibraryTrack> remote,
    required String accountId,
  }) {
    final map = <String, LibraryTrack>{};
    for (final t in local) {
      if (t.accountId != accountId) continue;
      map[t.remotePath] = t;
    }
    for (final r in remote) {
      if (r.accountId != accountId) continue;
      final l = map[r.remotePath];
      if (l == null) {
        map[r.remotePath] = r;
      } else if (r.lastTagReadAt.isAfter(l.lastTagReadAt)) {
        // Keep newer metadata; prefer local coverPath if remote has none usable.
        final cover = (r.coverPath != null && r.coverPath!.isNotEmpty)
            ? r.coverPath
            : l.coverPath;
        map[r.remotePath] = LibraryTrack.fromMap({
          ...r.toMap(),
          'cover_path': cover,
        });
      } else {
        // local wins or equal — keep local, but fill cover from remote if missing
        if ((l.coverPath == null || l.coverPath!.isEmpty) &&
            r.coverPath != null &&
            r.coverPath!.isNotEmpty) {
          map[r.remotePath] = LibraryTrack.fromMap({
            ...l.toMap(),
            'cover_path': r.coverPath,
          });
        }
      }
    }
    return map.values.toList();
  }

  Future<void> _pushIndex({
    required String root,
    required WebDavAccount account,
    required List<LibraryTrack> tracks,
  }) async {
    // Strip absolute local cover paths for portability; remote covers use file names.
    final portable = tracks.map((t) {
      final m = Map<String, dynamic>.from(t.toMap());
      final cover = t.coverPath;
      if (cover != null && cover.isNotEmpty) {
        m['cover_path'] = p.basename(cover);
      }
      return m;
    }).toList();
    final payload = {
      'format': 'webdav_music_player_library_index',
      'formatVersion': formatVersion,
      'accountId': account.id,
      'accountUrl': account.url,
      'accountName': account.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'trackCount': portable.length,
      'tracks': portable,
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
    await _webDav.writeBytes('$root$indexFileName', bytes);
  }

  /// Returns (uploaded, downloaded) cover counts.
  Future<(int, int)> _syncCovers({
    required WebDavAccount account,
    required List<LibraryTrack> tracks,
    required String root,
  }) async {
    var uploaded = 0;
    var downloaded = 0;
    final docs = await getApplicationDocumentsDirectory();
    final localCovers = Directory(p.join(docs.path, 'covers'));
    if (!await localCovers.exists()) {
      await localCovers.create(recursive: true);
    }

    for (final t in tracks) {
      final fileName = _library.covers.coverFileName(account.id, t.remotePath);
      final localFile = File(p.join(localCovers.path, fileName));
      final remotePath = '$root$coversSubdir/$fileName';

      final localExists = await localFile.exists();
      if (localExists) {
        try {
          final bytes = await localFile.readAsBytes();
          await _webDav.writeBytes(remotePath, bytes);
          uploaded++;
        } catch (_) {
          // best-effort upload
        }
      } else {
        try {
          final bytes = await _webDav.readAsBytes(remotePath);
          await localFile.writeAsBytes(bytes, flush: true);
          // Update track coverPath to local absolute path
          final updated = LibraryTrack.fromMap({
            ...t.toMap(),
            'cover_path': localFile.path,
          });
          await _library.upsertTracks([updated]);
          downloaded++;
        } catch (_) {
          // remote cover missing — skip
        }
      }
    }
    return (uploaded, downloaded);
  }
}
