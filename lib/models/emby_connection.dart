// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:uuid/uuid.dart';

/// Emby / Jellyfin 连接认证模式（只读/浏览侧，与网盘账号无关）。
enum EmbyAuthMode {
  /// 用户名 + 密码模式：调 POST /Users/AuthenticateByName 换 AccessToken。
  password,

  /// API Key 模式：直接使用管理员生成的 API Key 作为 token；
  /// 通过 GET /Users 解析 userId（取第一个非禁用用户，或按 username 匹配）。
  apiKey,
}

extension EmbyAuthModeX on EmbyAuthMode {
  String get storageKey => switch (this) {
        EmbyAuthMode.password => 'password',
        EmbyAuthMode.apiKey => 'api_key',
      };

  static EmbyAuthMode fromKey(String? key) => switch (key) {
        'api_key' => EmbyAuthMode.apiKey,
        _ => EmbyAuthMode.password, // 未知 key 回退到 password
      };
}

/// 一条 Emby / Jellyfin 连接配置（只读/浏览侧，与 WebDAV 账号完全隔离）。
///
/// secrets 存放规则（均在 `flutter_secure_storage`）：
/// - 密码（password 模式）：`emby_password_<id>`
/// - 缓存的 AccessToken：`emby_token_<id>`
/// - API Key（apiKey 模式）：`emby_apikey_<id>`
class EmbyConnection {
  EmbyConnection({
    String? id,
    required this.label,
    required this.baseUrl,
    this.authMode = EmbyAuthMode.password,
    this.username = '',
    this.userId = '',
    String? deviceId,
    this.sortOrder = 0,
  })  : id = id ?? const Uuid().v4(),
        deviceId = deviceId ?? const Uuid().v4();

  /// 稳定的唯一标识符（UUID v4）。
  final String id;

  /// 用户自定义显示名称。
  final String label;

  /// 服务器根地址，不含结尾 `/`，如 `http://192.168.1.100:8096`。
  /// 用户可包含子路径如 `/emby`。
  final String baseUrl;

  /// 认证模式。
  final EmbyAuthMode authMode;

  /// 用户名（password 模式）或 apiKey 模式下用于 userId 查找的提示。
  final String username;

  /// Emby 用户 ID（非秘密，持久化在连接表中；首次登录后由服务端返回）。
  final String userId;

  /// 每条连接独立的稳定 DeviceId（UUID v4，生成后不变）。
  final String deviceId;

  /// 抽屉/下拉列表排序权重，小值靠前。
  final int sortOrder;

  EmbyConnection copyWith({
    String? label,
    String? baseUrl,
    EmbyAuthMode? authMode,
    String? username,
    String? userId,
    int? sortOrder,
  }) =>
      EmbyConnection(
        id: id,
        label: label ?? this.label,
        baseUrl: baseUrl ?? this.baseUrl,
        authMode: authMode ?? this.authMode,
        username: username ?? this.username,
        userId: userId ?? this.userId,
        deviceId: deviceId, // deviceId 稳定不变
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'base_url': baseUrl,
        'auth_mode': authMode.storageKey,
        'username': username,
        'user_id': userId,
        'device_id': deviceId,
        'sort_order': sortOrder,
      };

  factory EmbyConnection.fromMap(Map<String, dynamic> m) => EmbyConnection(
        id: m['id'] as String,
        label: m['label'] as String,
        baseUrl: m['base_url'] as String,
        authMode: EmbyAuthModeX.fromKey(m['auth_mode'] as String?),
        username: (m['username'] as String?) ?? '',
        userId: (m['user_id'] as String?) ?? '',
        deviceId: (m['device_id'] as String?) ?? const Uuid().v4(),
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is EmbyConnection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
