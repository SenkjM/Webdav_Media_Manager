// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:uuid/uuid.dart';

/// OpenList 连接认证模式（只读/浏览侧，与网盘账号无关）。
enum OpenListAuthMode {
  /// 访客模式：不发送 Authorization 头，由服务端决定是否允许。
  guest,

  /// JWT 模式：用户名 + 密码换 JWT，缓存在 secure storage。
  jwt,

  /// 站点令牌：直接使用管理员 Token（存入 secure storage）。
  siteToken,
}

extension OpenListAuthModeX on OpenListAuthMode {
  String get storageKey => switch (this) {
        OpenListAuthMode.guest => 'guest',
        OpenListAuthMode.jwt => 'jwt',
        OpenListAuthMode.siteToken => 'site_token',
      };

  static OpenListAuthMode fromKey(String? key) => switch (key) {
        'jwt' => OpenListAuthMode.jwt,
        'site_token' => OpenListAuthMode.siteToken,
        _ => OpenListAuthMode.guest,
      };
}

/// 一条 OpenList 连接配置（只读/浏览侧，与 WebDAV 账号完全隔离）。
///
/// secrets 存放规则（均在 `flutter_secure_storage`）：
/// - 密码：`openlist_password_<id>`
/// - 缓存的 JWT：`openlist_jwt_<id>`
/// - 站点令牌：`openlist_sitetoken_<id>`
class OpenListConnection {
  OpenListConnection({
    String? id,
    required this.label,
    required this.baseUrl,
    this.authMode = OpenListAuthMode.guest,
    this.username = '',
    this.useHashLogin = false,
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  /// 稳定的唯一标识符（UUID v4）。
  final String id;

  /// 用户自定义显示名称。
  final String label;

  /// 服务器根地址，不含结尾 `/`，如 `http://192.168.1.100:5244`。
  final String baseUrl;

  /// 认证模式。
  final OpenListAuthMode authMode;

  /// JWT 模式下的用户名；密码在 secure storage 中。
  final String username;

  /// 是否使用 `/api/auth/login/hash`（客户端预先 SHA-256 散列密码后发送）。
  /// false 时使用 `/api/auth/login`（服务端散列）。
  final bool useHashLogin;

  /// 抽屉/下拉列表排序权重，小值靠前。
  final int sortOrder;

  OpenListConnection copyWith({
    String? label,
    String? baseUrl,
    OpenListAuthMode? authMode,
    String? username,
    bool? useHashLogin,
    int? sortOrder,
  }) =>
      OpenListConnection(
        id: id,
        label: label ?? this.label,
        baseUrl: baseUrl ?? this.baseUrl,
        authMode: authMode ?? this.authMode,
        username: username ?? this.username,
        useHashLogin: useHashLogin ?? this.useHashLogin,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'base_url': baseUrl,
        'auth_mode': authMode.storageKey,
        'username': username,
        'use_hash_login': useHashLogin ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory OpenListConnection.fromMap(Map<String, dynamic> m) =>
      OpenListConnection(
        id: m['id'] as String,
        label: m['label'] as String,
        baseUrl: m['base_url'] as String,
        authMode: OpenListAuthModeX.fromKey(m['auth_mode'] as String?),
        username: (m['username'] as String?) ?? '',
        useHashLogin: (m['use_hash_login'] as int? ?? 0) != 0,
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is OpenListConnection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
