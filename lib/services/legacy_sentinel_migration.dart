import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/account_sentinels.dart';
import '../models/playlist_sentinels.dart';
import '../utils/cache_group_codec.dart';
import '../utils/track_identity.dart';

/// 这份兼容是给正式版 0.2.2 的，会在 0.2.4 删掉。
/// 0.2.4 之后，旧数据库不再支持。
///
/// One-version startup rewrite. Delete this file by 0.2.4.
/// After the rewrite, the rest of the app must not match the Chinese literals.
///
/// Converted keys:
/// - playlist name `未命名` -> [kUnnamedPlaylistName]
/// - account name and every bound `source_name` / playlist entry `sourceName`
///   that is exactly `默认服务器` -> [kDefaultServerName]
///
/// Not converted: `新歌单`, `服务器`, real genre tag `未分类`, `未知艺术家`,
/// `未知专辑`, `新文件夹`, `系统相册`, `下载目录`, subtitle `默认`.
const _legacyUnnamedPlaylist = '未命名';
const _legacyDefaultServer = '默认服务器';

Future<void> migrateLegacySentinelsOnce({
  required Database libraryDb,
  required Database playlistDb,
  required Database downloadDb,
  Directory? cacheDir,
  Directory? coversDir,
  Directory? coversFullDir,
}) async {
  final paths = await _pathsBoundToLegacyServer(libraryDb, downloadDb);
  final stemMap = <String, String>{
    for (final path in paths)
      identityHashStem(_legacyDefaultServer, path): identityHashStem(
        kDefaultServerName,
        path,
      ),
  };
  await _renameStemFiles(cacheDir, stemMap, separator: '_');
  await _renameStemFiles(coversDir, stemMap, separator: '.');
  await _renameStemFiles(coversFullDir, stemMap, separator: '.');

  await libraryDb.transaction((txn) async {
    await txn.update(
      'accounts',
      {'name': kDefaultServerName},
      where: 'name = ?',
      whereArgs: const [_legacyDefaultServer],
    );
    for (final table in const [
      'tracks',
      'cue_albums',
      'cue_slices',
      'cache_access',
      'deleted_tracks',
    ]) {
      await txn.update(
        table,
        {'source_name': kDefaultServerName},
        where: 'source_name = ?',
        whereArgs: const [_legacyDefaultServer],
      );
    }
    await _rewriteCoverPaths(txn, 'tracks', stemMap);
    await _rewriteCoverPaths(txn, 'cue_slices', stemMap);
    // `tracks` has no cache_group_id column. Membership for ordinary
    // rows lives in `cache_groups`; only CUE tables store the column.
    await _rewriteCacheGroupColumn(txn, 'cue_slices', 'music_id');
    await _rewriteCacheGroupColumn(txn, 'cue_albums', 'cue_id');
    await _rewriteCacheGroupRows(txn);
  });

  await downloadDb.transaction((txn) async {
    await txn.update(
      'download_tasks',
      {'source_name': kDefaultServerName},
      where: 'source_name = ?',
      whereArgs: const [_legacyDefaultServer],
    );
    await _rewriteCacheGroupColumn(txn, 'download_tasks', 'id');
  });

  await _rewritePlaylists(playlistDb);
}

Future<Set<String>> _pathsBoundToLegacyServer(
  Database libraryDb,
  Database downloadDb,
) async {
  final paths = <String>{};
  Future<void> take(Database db, String sql) async {
    final rows = await db.rawQuery(sql, const [_legacyDefaultServer]);
    for (final row in rows) {
      final path = row.values.first;
      if (path is String && path.isNotEmpty) paths.add(path);
    }
  }

  await take(
    libraryDb,
    'SELECT remote_path FROM tracks WHERE source_name = ?',
  );
  await take(
    libraryDb,
    'SELECT remote_path FROM cue_slices WHERE source_name = ?',
  );
  await take(
    libraryDb,
    'SELECT audio_remote_path FROM cue_slices WHERE source_name = ? '
    'AND audio_remote_path IS NOT NULL',
  );
  await take(
    libraryDb,
    'SELECT remote_path FROM cache_access WHERE source_name = ?',
  );
  await take(
    downloadDb,
    'SELECT remote_path FROM download_tasks WHERE source_name = ?',
  );
  return paths;
}

Future<void> _renameStemFiles(
  Directory? dir,
  Map<String, String> stemMap, {
  required String separator,
}) async {
  if (dir == null || stemMap.isEmpty || !await dir.exists()) return;
  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    final sep = name.indexOf(separator);
    if (sep <= 0) continue;
    final stem = name.substring(0, sep);
    final next = stemMap[stem];
    if (next == null || next == stem) continue;
    final dest = File(p.join(dir.path, '$next${name.substring(sep)}'));
    if (await dest.exists()) continue;
    try {
      await entity.rename(dest.path);
    } catch (_) {
      // A locked file stays under the old stem. The name rewrite still runs.
    }
  }
}

Future<void> _rewriteCoverPaths(
  DatabaseExecutor txn,
  String table,
  Map<String, String> stemMap,
) async {
  if (stemMap.isEmpty) return;
  final rows = await txn.query(
    table,
    columns: ['cover_path'],
    where: 'cover_path IS NOT NULL',
  );
  for (final row in rows) {
    final path = row['cover_path'];
    if (path is! String || path.isEmpty) continue;
    final name = p.basename(path);
    final dot = name.indexOf('.');
    if (dot <= 0) continue;
    final next = stemMap[name.substring(0, dot)];
    if (next == null) continue;
    final rewritten = p.join(p.dirname(path), '$next${name.substring(dot)}');
    if (rewritten == path) continue;
    await txn.update(
      table,
      {'cover_path': rewritten},
      where: 'cover_path = ?',
      whereArgs: [path],
    );
  }
}

String? _rewriteBoundValue(String value) {
  if (value == _legacyDefaultServer) return kDefaultServerName;
  const cuePrefix = 'cue\u0000$_legacyDefaultServer\u0000';
  if (value.startsWith(cuePrefix)) {
    return 'cue\u0000$kDefaultServerName\u0000${value.substring(cuePrefix.length)}';
  }
  const idPrefix = '$_legacyDefaultServer\u0000';
  if (value.startsWith(idPrefix)) {
    return '$kDefaultServerName\u0000${value.substring(idPrefix.length)}';
  }
  return null;
}

Future<void> _rewriteCacheGroupColumn(
  DatabaseExecutor txn,
  String table,
  String idColumn,
) async {
  final rows = await txn.query(
    table,
    columns: [idColumn, 'cache_group_id'],
    where: 'cache_group_id IS NOT NULL',
  );
  for (final row in rows) {
    final current = row['cache_group_id'];
    if (current is! String) continue;
    final next = _rewriteBoundValue(current);
    if (next == null) continue;
    await txn.update(
      table,
      {'cache_group_id': next},
      where: '$idColumn = ?',
      whereArgs: [row[idColumn]],
    );
  }
}

Future<void> _rewriteCacheGroupRows(DatabaseExecutor txn) async {
  final rows = await txn.query('cache_groups');
  for (final row in rows) {
    final id = row['group_id'];
    if (id is! String) continue;
    final members = decodeCacheGroupMembers(row['members'] as String?);
    var changed = false;
    final nextMembers = [
      for (final member in members)
        () {
          final next = _rewriteBoundValue(member);
          if (next == null) return member;
          changed = true;
          return next;
        }(),
    ];
    final nextId = _rewriteBoundValue(id);
    if (nextId != null) changed = true;
    if (!changed) continue;
    final storedId = nextId ?? id;
    await txn.delete(
      'cache_groups',
      where: 'group_id = ?',
      whereArgs: [id],
    );
    final existing = decodeCacheGroupMembers(
      (await txn.query(
        'cache_groups',
        columns: ['members'],
        where: 'group_id = ?',
        whereArgs: [storedId],
        limit: 1,
      )).firstOrNull?['members'] as String?,
    );
    await txn.insert('cache_groups', {
      'group_id': storedId,
      'members': encodeCacheGroupMembers({...existing, ...nextMembers}),
      'updated_at':
          row['updated_at'] as String? ?? DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> _rewritePlaylists(Database db) async {
  final rows = await db.query('playlists');
  final now = DateTime.now().toUtc().toIso8601String();
  for (final row in rows) {
    final id = row['id'];
    if (id is! String) continue;
    var changed = false;
    var name = row['name'] as String? ?? '';
    if (name == _legacyUnnamedPlaylist) {
      name = kUnnamedPlaylistName;
      changed = true;
    }
    final raw = row['entries_json'] as String? ?? '[]';
    final decoded = jsonDecode(raw);
    if (decoded is! List) continue;
    final entries = <dynamic>[];
    for (final item in decoded) {
      if (item is! Map) {
        entries.add(item);
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final source = map['sourceName'] ?? map['accountId'];
      if (source == _legacyDefaultServer) {
        map['sourceName'] = kDefaultServerName;
        if (map.containsKey('accountId')) map['accountId'] = kDefaultServerName;
        changed = true;
      }
      entries.add(map);
    }
    if (!changed) continue;
    await db.update(
      'playlists',
      {
        'name': name,
        'entries_json': jsonEncode(entries),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
