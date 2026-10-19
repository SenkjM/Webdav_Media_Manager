// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/emby_connection.dart';

// ─── secure-storage key prefixes ───────────────────────────────────────────
const String _kTokenPrefix = 'emby_token_';
const String _kPasswordPrefix = 'emby_password_';
const String _kApiKeyPrefix = 'emby_apikey_';

// ─── DDL ───────────────────────────────────────────────────────────────────
const String _kCreateTable = '''
CREATE TABLE IF NOT EXISTS emby_connections (
  id          TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  base_url    TEXT NOT NULL,
  auth_mode   TEXT NOT NULL DEFAULT 'password',
  username    TEXT NOT NULL DEFAULT '',
  user_id     TEXT NOT NULL DEFAULT '',
  device_id   TEXT NOT NULL DEFAULT '',
  sort_order  INTEGER NOT NULL DEFAULT 0
)
''';

/// 连接列表持久化 + secrets 管理（99 §21 Emby 媒体库）。
///
/// 使用独立 SQLite 库 `emby_connections.db`，与现有 `library.db` /
/// `accounts` 完全隔离；secrets 存入 `flutter_secure_storage`。
class EmbyConnectionStore extends ChangeNotifier {
  EmbyConnectionStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  Database? _db;
  List<EmbyConnection> _connections = const [];

  List<EmbyConnection> get connections => List.unmodifiable(_connections);

  bool get isEmpty => _connections.isEmpty;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'emby_connections.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(_kCreateTable),
    );
    await _reload();
  }

  Future<void> _reload() async {
    final rows = await _db!.query(
      'emby_connections',
      orderBy: 'sort_order ASC, label ASC',
    );
    _connections = rows.map(EmbyConnection.fromMap).toList();
    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  /// 新增连接；[password] / [apiKey] 存入 secure storage（空值忽略）。
  Future<void> addConnection(
    EmbyConnection conn, {
    String? password,
    String? apiKey,
  }) async {
    await _db!.insert(
      'emby_connections',
      conn.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (password != null && password.isNotEmpty) {
      await _writeSecret(_kPasswordPrefix, conn.id, password);
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      await _writeSecret(_kApiKeyPrefix, conn.id, apiKey);
    }
    await _reload();
  }

  /// 更新连接；传入非 null 的 [password] / [apiKey] 覆盖旧值
  /// （传入空字符串则删除）；同时清除缓存的 token。
  Future<void> updateConnection(
    EmbyConnection conn, {
    String? password,
    String? apiKey,
  }) async {
    // Clear userId on every credential update so the next request re-resolves it.
    final row = {...conn.toMap(), 'user_id': ''};
    await _db!.update(
      'emby_connections',
      row,
      where: 'id = ?',
      whereArgs: [conn.id],
    );
    if (password != null) {
      if (password.isEmpty) {
        await _deleteSecret(_kPasswordPrefix, conn.id);
      } else {
        await _writeSecret(_kPasswordPrefix, conn.id, password);
      }
    }
    if (apiKey != null) {
      if (apiKey.isEmpty) {
        await _deleteSecret(_kApiKeyPrefix, conn.id);
      } else {
        await _writeSecret(_kApiKeyPrefix, conn.id, apiKey);
      }
    }
    // 凭证变更时清除缓存 token，下次访问重新登录。
    await _deleteSecret(_kTokenPrefix, conn.id);
    await _reload();
  }

  /// 更新 userId（首次登录后由服务端返回，不属于 secret）。
  Future<void> updateUserId(String id, String userId) async {
    await _db!.update(
      'emby_connections',
      {'user_id': userId},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _reload();
  }

  Future<void> deleteConnection(String id) async {
    await _db!.delete(
      'emby_connections',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _deleteSecret(_kTokenPrefix, id);
    await _deleteSecret(_kPasswordPrefix, id);
    await _deleteSecret(_kApiKeyPrefix, id);
    await _reload();
  }

  // ── secret accessors ──────────────────────────────────────────────────────

  /// 读取缓存的 AccessToken（可能为 null 或已失效）。
  Future<String?> readToken(String id) =>
      _secure.read(key: '$_kTokenPrefix$id');

  /// 持久化登录后获取的 AccessToken。
  Future<void> writeToken(String id, String token) =>
      _secure.write(key: '$_kTokenPrefix$id', value: token);

  /// 清除缓存的 token（令牌失效时调用）。
  Future<void> invalidateToken(String id) =>
      _secure.delete(key: '$_kTokenPrefix$id');

  /// 读取明文密码（password 模式静默重登用）。
  Future<String?> readPassword(String id) =>
      _secure.read(key: '$_kPasswordPrefix$id');

  /// 读取 API Key（apiKey 模式）。
  Future<String?> readApiKey(String id) =>
      _secure.read(key: '$_kApiKeyPrefix$id');

  // ── internal ──────────────────────────────────────────────────────────────

  Future<void> _writeSecret(String prefix, String id, String value) =>
      _secure.write(key: '$prefix$id', value: value);

  Future<void> _deleteSecret(String prefix, String id) =>
      _secure.delete(key: '$prefix$id');

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }
}
