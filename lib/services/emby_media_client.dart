// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';

import '../models/emby_connection.dart';
import 'emby_connection_store.dart';

// ─── Capabilities ──────────────────────────────────────────────────────────

/// Emby 客户端能力位。UI 按能力位分支，不做类型字符串比较。
enum EmbyCapability { browse, musicLibrary, stream, download, images }

/// 从 CollectionType 映射能力集（纯函数，可测试）。
Set<EmbyCapability> capabilitiesForCollectionType(String? type) {
  const base = {EmbyCapability.browse, EmbyCapability.images};
  switch (type) {
    case 'music':
      return {...base, EmbyCapability.musicLibrary, EmbyCapability.stream};
    case 'movies':
    case 'tvshows':
    case 'homevideos':
      return {...base, EmbyCapability.stream};
    case 'books':
      return {...base, EmbyCapability.download};
    default:
      return base;
  }
}

// ─── Auth result ───────────────────────────────────────────────────────────

/// 登录成功返回的信息。
class EmbyAuthResult {
  const EmbyAuthResult({
    required this.accessToken,
    required this.userId,
    required this.userName,
    required this.serverId,
  });

  final String accessToken;
  final String userId;
  final String userName;
  final String serverId;
}

// ─── View ──────────────────────────────────────────────────────────────────

/// Emby 媒体库视图（来自 GET /Users/{id}/Views）。
class EmbyView {
  const EmbyView({
    required this.id,
    required this.name,
    this.collectionType,
  });

  final String id;
  final String name;

  /// 如 'music', 'movies', 'tvshows', 'books', 'homevideos', 'playlists', null=混合。
  final String? collectionType;

  Set<EmbyCapability> get capabilities =>
      capabilitiesForCollectionType(collectionType);

  factory EmbyView.fromJson(Map<String, dynamic> j) => EmbyView(
        id: (j['Id'] as String?) ?? '',
        name: (j['Name'] as String?) ?? '',
        collectionType: j['CollectionType'] as String?,
      );
}

// ─── Item ──────────────────────────────────────────────────────────────────

/// Emby 媒体条目（来自 GET /Users/{id}/Items 等）。
class EmbyItem {
  EmbyItem({
    required this.id,
    required this.name,
    this.type = '',
    this.collectionType,
    this.isFolder = false,
    this.parentId,
    this.overview = '',
    this.productionYear,
    this.runTimeDuration,
    this.album = '',
    this.albumId,
    this.albumArtist = '',
    this.artists = const [],
    this.indexNumber,
    this.parentIndexNumber,
    this.imageTags = const {},
    this.played = false,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String type;
  final String? collectionType;
  final bool isFolder;
  final String? parentId;
  final String overview;
  final int? productionYear;

  /// RunTimeTicks ÷ 10 000 = ms → Duration.
  final Duration? runTimeDuration;

  final String album;
  final String? albumId;
  final String albumArtist;
  final List<String> artists;
  final int? indexNumber;
  final int? parentIndexNumber;

  /// ImageTags map (e.g. {'Primary': 'abc123'}).
  final Map<String, String> imageTags;

  final bool played;
  final bool isFavorite;

  /// 主封面 tag（来自 ImageTags['Primary']）。
  String? get primaryImageTag => imageTags['Primary'];

  /// 显示名称。
  String get displayName => name;

  /// 副标题（专辑 / 艺术家 / 年份）。
  String get subtitle {
    if (album.isNotEmpty) return album;
    if (albumArtist.isNotEmpty) return albumArtist;
    if (artists.isNotEmpty) return artists.join(', ');
    if (productionYear != null) return productionYear.toString();
    return '';
  }

  factory EmbyItem.fromJson(Map<String, dynamic> j) {
    // RunTimeTicks → Duration (ticks / 10_000 = ms)
    final ticks = (j['RunTimeTicks'] as num?)?.toInt();
    final duration =
        ticks != null ? Duration(milliseconds: ticks ~/ 10000) : null;

    // ImageTags
    final rawTags = j['ImageTags'];
    final imageTags = <String, String>{};
    if (rawTags is Map) {
      rawTags.forEach((k, v) {
        if (k is String && v is String) imageTags[k] = v;
      });
    }

    // Artists
    final rawArtists = j['Artists'];
    final artists = rawArtists is List
        ? rawArtists.whereType<String>().toList()
        : <String>[];

    // UserData
    final userData = j['UserData'];
    final played = (userData is Map ? userData['Played'] : null) == true;
    final isFavorite =
        (userData is Map ? userData['IsFavorite'] : null) == true;

    return EmbyItem(
      id: (j['Id'] as String?) ?? '',
      name: (j['Name'] as String?) ?? '',
      type: (j['Type'] as String?) ?? '',
      collectionType: j['CollectionType'] as String?,
      isFolder: (j['IsFolder'] as bool?) ?? false,
      parentId: j['ParentId'] as String?,
      overview: (j['Overview'] as String?) ?? '',
      productionYear: (j['ProductionYear'] as num?)?.toInt(),
      runTimeDuration: duration,
      album: (j['Album'] as String?) ?? '',
      albumId: j['AlbumId'] as String?,
      albumArtist: (j['AlbumArtist'] as String?) ?? '',
      artists: artists,
      indexNumber: (j['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (j['ParentIndexNumber'] as num?)?.toInt(),
      imageTags: imageTags,
      played: played,
      isFavorite: isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'Id': id,
        'Name': name,
        'Type': type,
        if (collectionType != null) 'CollectionType': collectionType,
        'IsFolder': isFolder,
        if (parentId != null) 'ParentId': parentId,
        'Overview': overview,
        if (productionYear != null) 'ProductionYear': productionYear,
        if (runTimeDuration != null)
          'RunTimeTicks': runTimeDuration!.inMilliseconds * 10000,
        'Album': album,
        if (albumId != null) 'AlbumId': albumId,
        'AlbumArtist': albumArtist,
        'Artists': artists,
        if (indexNumber != null) 'IndexNumber': indexNumber,
        if (parentIndexNumber != null) 'ParentIndexNumber': parentIndexNumber,
        'ImageTags': imageTags,
        'UserData': {'Played': played, 'IsFavorite': isFavorite},
      };
}

// ─── Items page ────────────────────────────────────────────────────────────

/// 分页结果（对应 Emby Items 响应）。
class EmbyItemsPage {
  const EmbyItemsPage({
    required this.items,
    required this.totalRecordCount,
    required this.startIndex,
  });

  final List<EmbyItem> items;
  final int totalRecordCount;
  final int startIndex;

  bool get hasMore => startIndex + items.length < totalRecordCount;
  bool get isEmpty => items.isEmpty;
}

// ─── Exception ─────────────────────────────────────────────────────────────

/// 请求失败时的可读错误。消息中不得包含 token / 密码 / api_key。
class EmbyApiException implements Exception {
  const EmbyApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'EmbyApiException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

// ─── Client ────────────────────────────────────────────────────────────────

/// 轻量 HTTP 客户端，对接 Emby / Jellyfin MediaBrowser REST API。
///
/// 每个请求自动附加 X-Emby-Authorization 头（见 [buildAuthorizationHeader]）
/// 以及认证后的 X-Emby-Token 头。不走 WebDAV / CloudDriver 层。
class EmbyMediaClient {
  EmbyMediaClient({required this.store, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
                headers: {'Accept': 'application/json'},
                responseType: ResponseType.json,
              ),
            );

  final EmbyConnectionStore store;
  final Dio _dio;

  static String get _platform {
    if (kIsWeb) return 'Web';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Unknown';
  }

  // ── Authorization header ──────────────────────────────────────────────────

  /// 构建 X-Emby-Authorization 头值（纯函数，无副作用，可直接单元测试）。
  ///
  /// 格式：`MediaBrowser Client="WDMM", Device="{platform}",
  ///         DeviceId="{deviceId}", Version="{version}"[, Token="{token}"]`
  static String buildAuthorizationHeader({
    required String deviceId,
    String? token,
    String platform = '',
    String version = '0.0.0',
  }) {
    final pl = platform.isEmpty ? _platform : platform;
    final buf = StringBuffer(
      'MediaBrowser Client="WDMM", Device="$pl"'
      ', DeviceId="$deviceId", Version="$version"',
    );
    if (token != null && token.isNotEmpty) {
      buf.write(', Token="$token"');
    }
    return buf.toString();
  }

  Map<String, dynamic> _authHeaders(EmbyConnection conn, String? token) {
    final authHeader = buildAuthorizationHeader(
      deviceId: conn.deviceId,
      token: token,
    );
    return {
      'X-Emby-Authorization': authHeader,
      if (token != null && token.isNotEmpty) 'X-Emby-Token': token,
      'Accept': 'application/json',
    };
  }

  // ── Authenticate ──────────────────────────────────────────────────────────

  /// 向 Emby/Jellyfin 登录，持久化 token + userId，返回 [EmbyAuthResult]。
  ///
  /// password 模式：POST /Users/AuthenticateByName。
  Future<EmbyAuthResult> authenticate(
    EmbyConnection conn, {
    required String password,
  }) async {
    final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
    final body = jsonEncode({'Username': conn.username, 'Pw': password});
    try {
      final resp = await _dio.post(
        '$base/Users/AuthenticateByName',
        data: body,
        options: Options(
          headers: {
            ..._authHeaders(conn, null),
            'Content-Type': 'application/json',
          },
        ),
      );
      final j = _asMap(resp.data);
      final token = (j['AccessToken'] as String?) ?? '';
      if (token.isEmpty) throw const EmbyApiException('登录响应中未找到 AccessToken');
      final userJ = j['User'] as Map<String, dynamic>? ?? {};
      final userId = (userJ['Id'] as String?) ?? '';
      final userName = (userJ['Name'] as String?) ?? '';
      final serverId = (j['ServerId'] as String?) ?? '';
      // Persist without leaking secrets into exceptions.
      await store.writeToken(conn.id, token);
      if (userId.isNotEmpty) await store.updateUserId(conn.id, userId);
      return EmbyAuthResult(
        accessToken: token,
        userId: userId,
        userName: userName,
        serverId: serverId,
      );
    } on DioException catch (e) {
      throw EmbyApiException('登录失败：${_dioMessage(e)}',
          statusCode: e.response?.statusCode);
    }
  }

  // ── Token + userId resolution ─────────────────────────────────────────────

  /// Re-reads userId for [conn] from the in-memory store list (updated after login).
  String _freshUserId(EmbyConnection conn) {
    try {
      return store.connections.firstWhere((c) => c.id == conn.id).userId;
    } catch (_) {
      return conn.userId;
    }
  }

  /// GET /Users → pick first non-disabled user (prefer username match, then admin).
  /// Persists userId to the store. Returns empty string on any failure.
  Future<String> _resolveApiKeyUserId(
      EmbyConnection conn, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) return '';
    final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
    try {
      final resp = await _dio.get(
        '$base/Users',
        options: Options(headers: _authHeaders(conn, apiKey)),
      );
      final list = resp.data;
      if (list is! List || list.isEmpty) return '';
      Map<String, dynamic>? picked;
      // Try case-insensitive username match first.
      if (conn.username.isNotEmpty) {
        for (final u in list) {
          if (u is Map<String, dynamic>) {
            final name = (u['Name'] as String?) ?? '';
            if (name.toLowerCase() == conn.username.toLowerCase()) {
              picked = u;
              break;
            }
          }
        }
      }
      if (picked == null) {
        // Fall back: first non-disabled user, prefer administrator.
        Map<String, dynamic>? firstEnabled;
        Map<String, dynamic>? firstAdmin;
        for (final u in list) {
          if (u is! Map<String, dynamic>) continue;
          final policy = u['Policy'];
          final disabled =
              (policy is Map ? policy['IsDisabled'] : null) == true;
          if (disabled) continue;
          firstEnabled ??= u;
          final isAdmin =
              (policy is Map ? policy['IsAdministrator'] : null) == true;
          if (isAdmin) firstAdmin ??= u;
        }
        picked = firstAdmin ?? firstEnabled;
      }
      if (picked == null) return '';
      final uid = (picked['Id'] as String?) ?? '';
      if (uid.isNotEmpty) await store.updateUserId(conn.id, uid);
      return uid;
    } on DioException catch (_) {
      return '';
    }
  }

  /// 解析本次请求所需的 token 与 userId。
  ///
  /// 与 [_resolveToken] 不同，此方法还处理 apiKey 模式下 userId 为空时的
  /// GET /Users 查询，并在登录后从 store 重读最新 userId。
  Future<({String? token, String userId})> _resolveSession(
      EmbyConnection conn) async {
    switch (conn.authMode) {
      case EmbyAuthMode.password:
        final cached = await store.readToken(conn.id);
        if (cached != null && cached.isNotEmpty) {
          final uid = _freshUserId(conn);
          return (token: cached, userId: uid);
        }
        final pw = await store.readPassword(conn.id);
        if (pw != null && pw.isNotEmpty) {
          final result = await authenticate(conn, password: pw);
          final uid = result.userId.isNotEmpty
              ? result.userId
              : _freshUserId(conn);
          return (token: result.accessToken, userId: uid);
        }
        return (token: null, userId: _freshUserId(conn));
      case EmbyAuthMode.apiKey:
        final key = await store.readApiKey(conn.id);
        var uid = _freshUserId(conn);
        if (uid.isEmpty) {
          uid = await _resolveApiKeyUserId(conn, key);
        }
        return (token: key, userId: uid);
    }
  }

  Future<T> _withTokenRetry<T>(
    EmbyConnection conn,
    Future<T> Function(String? token, String userId) fn,
  ) async {
    final session = await _resolveSession(conn);
    try {
      return await fn(session.token, session.userId);
    } on EmbyApiException catch (e) {
      if (e.statusCode == 401 && conn.authMode == EmbyAuthMode.password) {
        // Invalidate and re-auth once.
        await store.invalidateToken(conn.id);
        final pw = await store.readPassword(conn.id);
        if (pw != null && pw.isNotEmpty) {
          final result = await authenticate(conn, password: pw);
          final uid = result.userId.isNotEmpty
              ? result.userId
              : _freshUserId(conn);
          return await fn(result.accessToken, uid);
        }
      }
      rethrow;
    }
  }

  // ── Views ─────────────────────────────────────────────────────────────────

  /// GET /Users/{UserId}/Views → 库列表。
  Future<List<EmbyView>> getViews(EmbyConnection conn) async {
    return _withTokenRetry(conn, (token, userId) async {
      final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
      if (userId.isEmpty) throw const EmbyApiException('userId 为空，请先登录');
      try {
        final resp = await _dio.get(
          '$base/Users/$userId/Views',
          options: Options(headers: _authHeaders(conn, token)),
        );
        final j = _asMap(resp.data);
        final items = (j['Items'] as List?) ?? [];
        return items
            .whereType<Map<String, dynamic>>()
            .map(EmbyView.fromJson)
            .toList();
      } on DioException catch (e) {
        throw EmbyApiException('获取视图失败：${_dioMessage(e)}',
            statusCode: e.response?.statusCode);
      }
    });
  }

  // ── Items ─────────────────────────────────────────────────────────────────

  /// GET /Users/{UserId}/Items → 条目分页。
  Future<EmbyItemsPage> getItems(
    EmbyConnection conn, {
    String? parentId,
    List<String>? includeItemTypes,
    bool? recursive,
    int startIndex = 0,
    int limit = 50,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? searchTerm,
    String? artistIds,
    String? albumIds,
    String fields =
        'PrimaryImageAspectRatio,Overview,Genres,DateCreated,MediaSources',
  }) async {
    return _withTokenRetry(conn, (token, userId) async {
      final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
      if (userId.isEmpty) throw const EmbyApiException('userId 为空，请先登录');
      final params = <String, dynamic>{
        'StartIndex': startIndex,
        'Limit': limit,
        'SortBy': sortBy,
        'SortOrder': sortOrder,
        'Fields': fields,
        // ignore: use_null_aware_elements
        if (parentId != null) 'ParentId': parentId,
        if (includeItemTypes != null && includeItemTypes.isNotEmpty)
          'IncludeItemTypes': includeItemTypes.join(','),
        // ignore: use_null_aware_elements
        if (recursive != null) 'Recursive': recursive,
        if (searchTerm != null && searchTerm.isNotEmpty)
          'SearchTerm': searchTerm,
        if (artistIds != null && artistIds.isNotEmpty) 'ArtistIds': artistIds,
        if (albumIds != null && albumIds.isNotEmpty) 'AlbumIds': albumIds,
      };
      try {
        final resp = await _dio.get(
          '$base/Users/$userId/Items',
          queryParameters: params,
          options: Options(headers: _authHeaders(conn, token)),
        );
        final j = _asMap(resp.data);
        final items = (j['Items'] as List?) ?? [];
        final total = (j['TotalRecordCount'] as num?)?.toInt() ?? items.length;
        return EmbyItemsPage(
          items: items
              .whereType<Map<String, dynamic>>()
              .map(EmbyItem.fromJson)
              .toList(),
          totalRecordCount: total,
          startIndex: startIndex,
        );
      } on DioException catch (e) {
        throw EmbyApiException('获取条目失败：${_dioMessage(e)}',
            statusCode: e.response?.statusCode);
      }
    });
  }

  // ── Music helpers ─────────────────────────────────────────────────────────

  Future<EmbyItemsPage> getMusicAlbums(
    EmbyConnection conn,
    String viewId, {
    int startIndex = 0,
    int limit = 50,
  }) =>
      getItems(
        conn,
        parentId: viewId,
        includeItemTypes: ['MusicAlbum'],
        recursive: true,
        startIndex: startIndex,
        limit: limit,
      );

  Future<EmbyItemsPage> getAlbumTracks(
    EmbyConnection conn,
    String albumId, {
    int startIndex = 0,
    int limit = 200,
  }) =>
      getItems(
        conn,
        parentId: albumId,
        includeItemTypes: ['Audio'],
        recursive: false,
        startIndex: startIndex,
        limit: limit,
        sortBy: 'ParentIndexNumber,IndexNumber,SortName',
      );

  /// GET /Artists/AlbumArtists → 艺术家分页。
  Future<EmbyItemsPage> getArtists(
    EmbyConnection conn,
    String viewId, {
    int startIndex = 0,
    int limit = 50,
  }) async {
    return _withTokenRetry(conn, (token, userId) async {
      final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
      if (userId.isEmpty) throw const EmbyApiException('userId 为空，请先登录');
      try {
        final resp = await _dio.get(
          '$base/Artists/AlbumArtists',
          queryParameters: {
            'ParentId': viewId,
            'UserId': userId,
            'StartIndex': startIndex,
            'Limit': limit,
          },
          options: Options(headers: _authHeaders(conn, token)),
        );
        final j = _asMap(resp.data);
        final items = (j['Items'] as List?) ?? [];
        final total =
            (j['TotalRecordCount'] as num?)?.toInt() ?? items.length;
        return EmbyItemsPage(
          items: items
              .whereType<Map<String, dynamic>>()
              .map(EmbyItem.fromJson)
              .toList(),
          totalRecordCount: total,
          startIndex: startIndex,
        );
      } on DioException catch (e) {
        throw EmbyApiException('获取艺术家失败：${_dioMessage(e)}',
            statusCode: e.response?.statusCode);
      }
    });
  }

  // ── URL builders (pure, no network) ──────────────────────────────────────

  /// 封面图 URL（不含 token；使用 X-Emby-Token 头加载图片）。
  /// 仅用于展示；不要在日志中输出此 URL（如需 api_key 嵌入，不要记录）。
  static String imageUrl(
    EmbyConnection conn,
    String itemId, {
    String type = 'Primary',
    int? maxWidth,
    String? tag,
  }) {
    final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
    final buf = StringBuffer('$base/Items/$itemId/Images/$type');
    final params = <String>[];
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    if (tag != null && tag.isNotEmpty) params.add('tag=$tag');
    if (params.isNotEmpty) buf.write('?${params.join('&')}');
    return buf.toString();
  }

  /// 音频流 URL（含 api_key；不得记录日志）。
  static String audioStreamUrl(
    EmbyConnection conn,
    String itemId,
    String token,
  ) {
    final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
    // Intentionally omit token from logs — do not log this URL.
    return '$base/Audio/$itemId/stream?static=true&api_key=$token';
  }

  /// 视频流 URL（含 api_key；不得记录日志）。
  static String videoStreamUrl(
    EmbyConnection conn,
    String itemId,
    String token, {
    String? container,
  }) {
    final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
    final extra = container != null ? '&Container=$container' : '';
    // Intentionally omit token from logs — do not log this URL.
    return '$base/Videos/$itemId/stream?static=true&api_key=$token$extra';
  }

  /// 下载 URL（含 api_key；不得记录日志）。
  static String downloadUrl(
    EmbyConnection conn,
    String itemId,
    String token,
  ) {
    final base = conn.baseUrl.replaceAll(RegExp(r'/$'), '');
    // Intentionally omit token from logs — do not log this URL.
    return '$base/Items/$itemId/Download?api_key=$token';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _asMap(dynamic body) {
    if (body is Map<String, dynamic>) return body;
    if (body is String) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    throw const EmbyApiException('响应格式错误');
  }

  String _dioMessage(DioException e) {
    if (e.response != null) {
      final sc = e.response!.statusCode;
      if (sc == 401) return '认证失败，请检查凭证';
      if (sc == 403) return '权限不足';
      if (sc == 404) return '接口不存在，请检查服务器地址';
      return 'HTTP $sc';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时';
      case DioExceptionType.connectionError:
        return '无法连接到服务器，请检查地址与网络';
      default:
        return '网络错误（${e.type.name}）';
    }
  }
}
