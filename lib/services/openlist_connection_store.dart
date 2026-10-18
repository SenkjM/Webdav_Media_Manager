// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/openlist_connection.dart';

// ─── secure-storage key prefixes ───────────────────────────────────────────
const String _kJwtPrefix = 'openlist_jwt_';
const String _kPasswordPrefix = 'openlist_password_';
const String _kSiteTokenPrefix = 'openlist_sitetoken_';

// ─── DDL ───────────────────────────────────────────────────────────────────
const String _kCreateTable = '''
CREATE TABLE IF NOT EXISTS openlist_connections (
  id             TEXT PRIMARY KEY,
  label          TEXT NOT NULL,
  base_url       TEXT NOT NULL,
  auth_mode      TEXT NOT NULL DEFAULT 'guest',
  username       TEXT NOT NULL DEFAULT '',
  use_hash_login INTEGER NOT NULL DEFAULT 0,
  sort_order     INTEGER NOT NULL DEFAULT 0
)
''';

/// 连接列表持久化 + secrets 管理。
///
/// 使用独立 SQLite 库 `openlist_connections.db`，与现有 `library.db` /
/// `accounts` 完全隔离；secrets 存入 `flutter_secure_storage`。
class OpenListConnectionStore extends ChangeNotifier {
  OpenListConnectionStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  Database? _db;
  List<OpenListConnection> _connections = const [];

  List<OpenListConnection> get connections =>
      List.unmodifiable(_connections);

  bool get isEmpty => _connections.isEmpty;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'openlist_connections.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(_kCreateTable),
    );
    await _reload();
  }

  Future<void> _reload() async {
    final rows = await _db!.query(
      'openlist_connections',
      orderBy: 'sort_order ASC, label ASC',
    );
    _connections = rows.map(OpenListConnection.fromMap).toList();
    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  /// 新增连接；[password] / [siteToken] 存入 secure storage（空值忽略）。
  Future<void> addConnection(
    OpenListConnection conn, {
    String? password,
    String? siteToken,
  }) async {
    await _db!.insert(
      'openlist_connections',
      conn.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (password != null && password.isNotEmpty) {
      await _writeSecret(_kPasswordPrefix, conn.id, password);
    }
    if (siteToken != null && siteToken.isNotEmpty) {
      await _writeSecret(_kSiteTokenPrefix, conn.id, siteToken);
    }
    await _reload();
  }

  /// 更新连接；传入非 null 的 [password] / [siteToken] 覆盖旧值
  /// （传入空字符串则删除）；同时清除缓存的 JWT。
  Future<void> updateConnection(
    OpenListConnection conn, {
    String? password,
    String? siteToken,
  }) async {
    await _db!.update(
      'openlist_connections',
      conn.toMap(),
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
    if (siteToken != null) {
      if (siteToken.isEmpty) {
        await _deleteSecret(_kSiteTokenPrefix, conn.id);
      } else {
        await _writeSecret(_kSiteTokenPrefix, conn.id, siteToken);
      }
    }
    // 凭证变更时清除缓存令牌，下次访问重新登录。
    await _deleteSecret(_kJwtPrefix, conn.id);
    await _reload();
  }

  Future<void> deleteConnection(String id) async {
    await _db!.delete(
      'openlist_connections',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _deleteSecret(_kJwtPrefix, id);
    await _deleteSecret(_kPasswordPrefix, id);
    await _deleteSecret(_kSiteTokenPrefix, id);
    await _reload();
  }

  // ── secret accessors ──────────────────────────────────────────────────────

  /// 读取缓存的 JWT（可能为 null 或已过期）。
  Future<String?> readJwt(String id) =>
      _secure.read(key: '$_kJwtPrefix$id');

  /// 持久化登录后获取的 JWT。
  Future<void> writeJwt(String id, String token) =>
      _secure.write(key: '$_kJwtPrefix$id', value: token);

  /// 清除缓存的 JWT（令牌失效时调用）。
  Future<void> invalidateJwt(String id) =>
      _secure.delete(key: '$_kJwtPrefix$id');

  /// 读取明文密码（JWT 模式静默重登用）。
  Future<String?> readPassword(String id) =>
      _secure.read(key: '$_kPasswordPrefix$id');

  /// 读取站点令牌（site_token 模式）。
  Future<String?> readSiteToken(String id) =>
      _secure.read(key: '$_kSiteTokenPrefix$id');

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
