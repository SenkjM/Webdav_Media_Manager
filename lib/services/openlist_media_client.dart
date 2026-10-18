// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/openlist_connection.dart';
import 'openlist_connection_store.dart';

/// 媒体条目（来自 OpenList `/api/fs/media/list` 的 `MediaItem`）。
class OpenListMediaItem {
  OpenListMediaItem({
    required this.id,
    required this.mediaType,
    required this.fileName,
    this.scrapedName = '',
    this.cover = '',
    this.description = '',
    this.rating = 0.0,
    this.genre = '',
    this.authors = '',
    this.albumName = '',
    this.albumArtist = '',
    this.duration = 0,
    this.releaseDate = '',
    this.videoType = '',
  });

  final int id;
  final String mediaType;
  final String fileName;

  /// 刮削后的名称；为空时回退到文件名（去扩展名）。
  final String scrapedName;
  final String cover;
  final String description;
  final double rating;
  final String genre;
  final String authors;
  final String albumName;
  final String albumArtist;

  /// 时长（秒）。
  final int duration;
  final String releaseDate;
  final String videoType;

  /// 显示名称：优先 scraped_name，否则 file_name 去扩展名。
  String get displayName {
    if (scrapedName.isNotEmpty) return scrapedName;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// 副标题（音乐→专辑，视频→类型，书籍→出版信息等）。
  String get subtitle {
    if (albumName.isNotEmpty) return albumName;
    if (videoType.isNotEmpty) return videoType;
    if (releaseDate.isNotEmpty) return releaseDate;
    return '';
  }

  factory OpenListMediaItem.fromJson(Map<String, dynamic> j) =>
      OpenListMediaItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        mediaType: (j['media_type'] as String?) ?? '',
        fileName: (j['file_name'] as String?) ?? '',
        scrapedName: (j['scraped_name'] as String?) ?? '',
        cover: (j['cover'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        rating: ((j['rating'] as num?) ?? 0.0).toDouble(),
        genre: (j['genre'] as String?) ?? '',
        authors: (j['authors'] as String?) ?? '',
        albumName: (j['album_name'] as String?) ?? '',
        albumArtist: (j['album_artist'] as String?) ?? '',
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        releaseDate: (j['release_date'] as String?) ?? '',
        videoType: (j['video_type'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_type': mediaType,
        'file_name': fileName,
        'scraped_name': scrapedName,
        'cover': cover,
        'description': description,
        'rating': rating,
        'genre': genre,
        'authors': authors,
        'album_name': albumName,
        'album_artist': albumArtist,
        'duration': duration,
        'release_date': releaseDate,
        'video_type': videoType,
      };
}

/// 分页结果。
class OpenListMediaPage {
  const OpenListMediaPage({required this.items, required this.total});
  final List<OpenListMediaItem> items;
  final int total;

  bool get isEmpty => items.isEmpty;
}

/// 登录或列表请求失败时的可读错误（中文）。
class OpenListApiException implements Exception {
  const OpenListApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'OpenListApiException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

/// 轻量 HTTP 客户端（只读/浏览侧），对接 OpenList `/api/fs/media/*`。
///
/// Authorization 头传**原始** token（不加 `Bearer ` 前缀），与 OpenList
/// middleware 一致：`c.GetHeader("Authorization")` 直接比对。
/// 不走 WebDAV。
class OpenListMediaClient {
  OpenListMediaClient({required this.store, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                responseType: ResponseType.json,
              ),
            );

  final OpenListConnectionStore store;
  final Dio _dio;

  // ── Auth ──────────────────────────────────────────────────────────────────

  /// 向 OpenList 登录，返回 JWT 并持久化到 secure storage。
  ///
  /// - [OpenListConnection.useHashLogin] 为 true 时走 `/api/auth/login/hash`，
  ///   密码客户端预先 SHA-256（与 OpenList `LoginHash` 一致）。
  /// - 否则走 `/api/auth/login`，密码明文发送、服务端 SHA-256（OpenList `Login`）。
  Future<String> login(OpenListConnection conn) async {
    final password = await store.readPassword(conn.id) ?? '';
    final path =
        conn.useHashLogin ? '/api/auth/login/hash' : '/api/auth/login';
    final body = <String, dynamic>{
      'username': conn.username,
      'password': conn.useHashLogin ? sha256Hex(password) : password,
    };
    try {
      final resp = await _dio.post(
        '${conn.baseUrl}$path',
        data: jsonEncode(body),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = _parseResp(resp.data);
      final token = (data as Map<String, dynamic>?)?['token'] as String?;
      if (token == null || token.isEmpty) {
        throw const OpenListApiException('登录响应中未找到 token');
      }
      await store.writeJwt(conn.id, token);
      return token;
    } on DioException catch (e) {
      throw OpenListApiException(
        '登录失败：${_dioMessage(e)}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  // ── Media list ────────────────────────────────────────────────────────────

  /// 拉取分页媒体列表。自动处理认证头；JWT 过期（401）时静默重登一次。
  ///
  /// [mediaType] 取值：`video` / `music` / `image` / `book`
  /// （对齐 OpenList `model.MediaType`）。
  Future<OpenListMediaPage> listMedia(
    OpenListConnection conn,
    String mediaType, {
    int page = 1,
    int pageSize = 40,
  }) async {
    final token = await _resolveToken(conn);
    try {
      return await _doListMedia(conn, mediaType, page, pageSize, token);
    } on OpenListApiException catch (e) {
      if (e.statusCode == 401 && conn.authMode == OpenListAuthMode.jwt) {
        // JWT 过期：清缓存，若有密码则静默重登一次再重试。
        await store.invalidateJwt(conn.id);
        final password = await store.readPassword(conn.id);
        if (password != null && password.isNotEmpty) {
          final newToken = await login(conn);
          return await _doListMedia(
            conn, mediaType, page, pageSize, newToken,
          );
        }
      }
      rethrow;
    }
  }

  Future<OpenListMediaPage> _doListMedia(
    OpenListConnection conn,
    String mediaType,
    int page,
    int pageSize,
    String? token,
  ) async {
    final headers = <String, dynamic>{
      if (token != null && token.isNotEmpty) 'Authorization': token,
    };
    try {
      final resp = await _dio.get(
        '${conn.baseUrl}/api/fs/media/list',
        queryParameters: {
          'media_type': mediaType,
          'page': page,
          'page_size': pageSize,
        },
        options: Options(headers: headers),
      );
      final data = _parseResp(resp.data) as Map<String, dynamic>;
      final content = (data['content'] as List?) ?? const [];
      final total = (data['total'] as num?)?.toInt() ?? content.length;
      return OpenListMediaPage(
        items: content
            .whereType<Map<String, dynamic>>()
            .map(OpenListMediaItem.fromJson)
            .toList(growable: false),
        total: total,
      );
    } on DioException catch (e) {
      throw OpenListApiException(
        '加载列表失败：${_dioMessage(e)}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// 根据认证模式解析请求令牌（不触发网络请求，必要时静默登录）。
  Future<String?> _resolveToken(OpenListConnection conn) async {
    switch (conn.authMode) {
      case OpenListAuthMode.guest:
        return null;
      case OpenListAuthMode.jwt:
        final cached = await store.readJwt(conn.id);
        if (cached != null && cached.isNotEmpty) return cached;
        // 没有缓存且存了密码，则静默登录。
        final password = await store.readPassword(conn.id);
        if (password != null && password.isNotEmpty) {
          return await login(conn);
        }
        return null;
      case OpenListAuthMode.siteToken:
        return await store.readSiteToken(conn.id);
    }
  }

  /// 解析 OpenList 统一响应格式，返回 `data` 字段。
  ///
  /// 成功：`{code: 200, message: "success", data: ...}`。
  dynamic _parseResp(dynamic body) {
    Map<String, dynamic>? map;
    if (body is String) {
      try {
        map = jsonDecode(body) as Map<String, dynamic>?;
      } catch (_) {}
    } else if (body is Map<String, dynamic>) {
      map = body;
    }
    if (map == null) throw const OpenListApiException('响应格式错误');
    final code = (map['code'] as num?)?.toInt() ?? 0;
    if (code != 200) {
      throw OpenListApiException(
        map['message'] as String? ?? '未知错误（code: $code）',
        statusCode: code,
      );
    }
    return map['data'];
  }

  String _dioMessage(DioException e) {
    if (e.response != null) {
      final sc = e.response!.statusCode;
      if (sc == 401) return '认证失败，请检查用户名/密码';
      if (sc == 403) return '权限不足';
      if (sc == 404) return '接口不存在，请检查 OpenList 版本';
      return 'HTTP $sc';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时';
      case DioExceptionType.connectionError:
        return '无法连接到服务器，请检查地址与网络';
      default:
        return e.message ?? '网络错误';
    }
  }

  /// SHA-256 十六进制摘要（用于 `/api/auth/login/hash`）。
  static String sha256Hex(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}
