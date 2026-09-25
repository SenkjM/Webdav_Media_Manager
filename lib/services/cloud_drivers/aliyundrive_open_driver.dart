/// 阿里云盘开放平台驱动（OpenList `aliyundrive_open` 移植）。
///
/// 移植自 `localdev/OpenList-Worker/src/backend/drivers/aliyundrive_open`
/// （driver.ts + util.ts + types.ts，移植底稿）与
/// `localdev/OpenList/drivers/aliyundrive_open`（Go 版 driver.go / util.go /
/// meta.go / types.go，语义兜底）。
///
/// **API 形态**：基址 `https://openapi.aliyundrive.com/adrive/v1.0`，
/// 所有请求都是 `POST` + JSON body，头带 `Authorization: Bearer <access_token>`
/// （util.ts `openApiRequest`）。非 2xx 不是异常——本驱动 `validateStatus`
/// 全放行，读 body 拿**上游原文**再包成 [CloudDriverException]（12 §2 第 2 步）。
///
/// **不移植**（12 §2 字段裁剪规则 / 99 §7.2.1 上传已砍）：
/// - `putFile`（`/openFile/create` 传 content 那一段）与秒传相关字段；
/// - `order_by` / `order_direction`：表单不暴露，列表固定
///   `updated_at` + `DESC`（与上游 util.ts 的缺省一致）；
/// - `use_online_api` 开关：被「在本地处理令牌刷新」开关取代，默认走在线续期；
/// - `alipan_type`（`driver_txt` 固定取 QR 分支 `alicloud_qr`）；
/// - `chunk_size` / `rapid_upload` / `internal_upload` / `livp_download_format`
///   等上传与代理下载字段。
///
/// **与 worker 底稿的有意差异**（对齐 `CloudDriver.get` 的契约，11 §10）：
/// worker 的 `get()` 拿不到直链时静默返回 `raw_url: ""`，本驱动让直链失败
/// **自然抛出真实原因**——客户端里没有直链的下游必然失败，不如直说。
/// 目录探测分支（`getFile` 为空 → 列一次目录判断是不是文件夹）照抄保留。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/account_capabilities.dart';
import '../cloud_driver.dart';

/// 驱动配置（对齐上游 `AliyundriveOpenAddition`）。
///
/// 键名与上游一致，便于对照排错。**只保留表单暴露的字段**：
/// `access_token` 只作缓存（经 `onTokenUpdate` 持久化），不进表单。
class AliyundriveOpenAddition {
  AliyundriveOpenAddition({
    required this.refreshToken,
    this.driveType = AliyundriveOpenClient.defaultDriveType,
    this.driveId = '',
    this.rootFolderId = AliyundriveOpenClient.defaultRoot,
    this.removeWay = AliyundriveOpenClient.defaultRemoveWay,
    this.apiUrlAddress = AliyundriveOpenClient.defaultRenewApi,
    this.localRefresh = false,
    this.clientId = '',
    this.clientSecret = '',
    this.accessToken = '',
  });

  factory AliyundriveOpenAddition.fromJson(Map<String, dynamic> json) =>
      AliyundriveOpenAddition(
        refreshToken: json['refresh_token'] as String? ?? '',
        driveType:
            json['drive_type'] as String? ?? AliyundriveOpenClient.defaultDriveType,
        driveId: json['drive_id'] as String? ?? '',
        rootFolderId:
            json['root_folder_id'] as String? ?? AliyundriveOpenClient.defaultRoot,
        removeWay:
            json['remove_way'] as String? ?? AliyundriveOpenClient.defaultRemoveWay,
        apiUrlAddress: json['api_url_address'] as String? ??
            AliyundriveOpenClient.defaultRenewApi,
        localRefresh: json['local_refresh'] as bool? ?? false,
        clientId: json['client_id'] as String? ?? '',
        clientSecret: json['client_secret'] as String? ?? '',
        accessToken: json['access_token'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
        'drive_type': driveType,
        'drive_id': driveId,
        'root_folder_id': rootFolderId,
        'remove_way': removeWay,
        'api_url_address': apiUrlAddress,
        'local_refresh': localRefresh,
        'client_id': clientId,
        'client_secret': clientSecret,
        'access_token': accessToken,
      };

  /// 刷新令牌（表单必填）。在线续期会轮换它，轮换结果经 `onTokenUpdate` 持久化。
  String refreshToken;

  /// 网盘类型：`resource`（资源盘）/ `default`（默认盘）/ `backup`（备份盘）。
  ///
  /// 默认值照抄 Go `meta.go`（`drive_type` default `resource`；
  /// `driver.go Init` 里空值兜底成 `default`，表单已给默认值故不会走到）。
  String driveType;

  /// 显式 drive_id；非空时**直接使用**，不再调 `/user/getDriveInfo`
  /// （对齐 worker `resolveDriveId` 的首个分支）。
  String driveId;

  /// 浏览根目录 id（上游 `root_folder_id`，Go `driver.Config.DefaultRoot`）。
  ///
  /// 不透明 id，默认 `root`。注意它与账号的「远程路径」**叠加**：
  /// 远程路径是虚拟前缀，由 `CloudDriveService.joinRemotePath` 拼在驱动路径前
  /// （12 §6.3）。
  String rootFolderId;

  /// 删除方式：`trash`（移入回收站，默认）/ `delete`（彻底删除）。
  String removeWay;

  /// 在线续期地址；空串回落到 [AliyundriveOpenClient.defaultRenewApi]。
  String apiUrlAddress;

  /// 「在本地处理令牌刷新」开关：true = 用自建应用的 client 凭证直连 OAuth；
  /// false = 先试在线续期地址（对应上游 `use_online_api` 的反相）。
  bool localRefresh;

  /// 自建阿里云应用的 ClientID / ClientSecret（仅本地刷新时需要）。
  String clientId;
  String clientSecret;

  /// access_token 缓存（自动持久化，不进表单、不进备份明文）。
  String accessToken;
}

/// 阿里云盘文件条目（上游 `AliyunFileItem` / Go `File`）。
class AliyundriveOpenFile {
  AliyundriveOpenFile({
    required this.fileId,
    required this.name,
    required this.type,
    this.size = 0,
    this.parentFileId = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  static AliyundriveOpenFile fromMap(Map<String, dynamic> m) =>
      AliyundriveOpenFile(
        fileId: m['file_id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        type: m['type'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        parentFileId: m['parent_file_id'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
      );

  final String fileId;
  final String name;

  /// `folder` = 目录，其余（`file`）当作文件（上游 `f.type === "folder"`）。
  final String type;
  final int size;
  final String parentFileId;

  /// ISO8601 字符串（含 `Z` / 偏移），直接 `DateTime.tryParse`。
  final String createdAt;
  final String updatedAt;

  bool get isDir => type == 'folder';

  /// 上游 `f.updated_at || f.created_at`（都没有则按契约给 null，不伪造时间）。
  DateTime? get modified => parseAliyundriveOpenTime(updatedAt) ??
      parseAliyundriveOpenTime(createdAt);
}

/// 阿里云盘开放平台 API 客户端。
///
/// 认证：`Authorization: Bearer <access_token>`；`access_token` 过期时
/// 在线续期 / OAuth 刷新会自动轮换。
class AliyundriveOpenClient {
  /// API 基址（上游 util.ts `ALI_OPEN_API`）。
  static const String api = 'https://openapi.aliyundrive.com/adrive/v1.0';

  /// 直连 OAuth 的令牌端点（worker 用 `openapi.aliyundrive.com`；
  /// Go 版用 `openapi.alipan.com`，两者同服务，这里照抄 worker 底稿）。
  static const String oauthApi =
      'https://openapi.aliyundrive.com/oauth/access_token';

  /// 在线续期地址默认值（照抄 Go `meta.go` 的 `api_url_address` default）。
  static const String defaultRenewApi =
      'https://api.oplist.org/alicloud/renewapi';

  /// 在线续期**逐级轮询**的内置候选地址（顺序照抄 worker util.ts）。
  ///
  /// 自定义 [AliyundriveOpenAddition.apiUrlAddress] 排在最前，但本地刷新
  /// 开关打开时整个在线分支都不走（见 [refreshAccessToken]）。
  static const List<String> builtinRenewApis = <String>[
    'https://api.oplist.org/alicloud/renewapi',
    'https://api.oplist.org/ali_open/token',
    'https://api.oplist.org/aliyundrive/token',
    'https://api.alist.nn.ci/alist/ali_open/token',
    'https://api.alist.nn.ci/aliyundrive/token',
    'https://api-sam.oplist.org/aliyundrive/token',
  ];

  /// 在线续期的 `driver_txt`（`alipan_type` 固定走 QR 分支）。
  static const String driverTxt = 'alicloud_qr';

  /// 直连 OAuth 的缺省 client_id（worker util.ts 内置的公开应用）。
  static const String defaultClientId = '25ab4837190e48718a28f80073574a4d';

  /// 网盘类型默认值（Go `meta.go` `drive_type` default）。
  static const String defaultDriveType = 'resource';

  /// 浏览根默认值（Go `driver.Config.DefaultRoot`）。
  static const String defaultRoot = 'root';

  /// 删除方式默认值（Go `meta.go` `remove_way` 首个 option）。
  static const String defaultRemoveWay = 'trash';

  /// 列表分页大小（上游固定 100）。
  static const int pageSize = 100;

  /// 列表排序字段。表单不暴露排序（12 §2），固定上游缺省值。
  static const String listOrderBy = 'updated_at';

  /// 列表排序方向，同上。
  static const String listOrderDirection = 'DESC';

  /// 直链有效期（上游 `expire_sec` 固定 14400 秒 = 4 小时）。
  static const int linkExpireSec = 14400;

  AliyundriveOpenClient(this.addition, {this.onTokenUpdate, Dio? dio})
      : accessToken = addition.accessToken,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'Accept': 'application/json'},
                // 非 2xx 也回来走原文解析：「原样传递报错」需要读到 body。
                validateStatus: (_) => true,
              ),
            );

  final AliyundriveOpenAddition addition;
  String accessToken;

  /// 令牌轮换回调（在线续期 / OAuth 都会轮换 refresh_token，两个都要存）。
  final void Function(Map<String, dynamic> patch)? onTokenUpdate;

  final Dio _dio;

  /// 解析出来的 drive_id（`resource` / `default` / `backup` 之一）。
  String driveId = '';

  /// 无缓存 access_token 就先换一次（对齐 worker `ensureToken` 的首跳）。
  Future<void> login() async {
    if (accessToken.isEmpty) await refreshAccessToken();
  }

  /// 刷新令牌，三条路（对齐 worker `refreshAccessToken`）：
  ///
  /// 1. **在线 API 中转**（默认）：把候选地址**逐个试**，第一个成功的就用，
  ///    全失败才往下走。参数 `refresh_ui` + `refresh_token`（都是令牌值）+
  ///    `server_use=true` + `driver_txt`；`access_token` / `refresh_token`
  ///    顶层和 `data` 里**两处都看**。
  /// 2. **直连 OAuth**：`POST /oauth/access_token`，
  ///    `{grant_type:'refresh_token', refresh_token, client_id[, client_secret]}`。
  /// 3. 都失败才抛错，错误信息带「检查 refresh_token / api_url_address /
  ///    client 凭证」的指引。
  ///
  /// 注意 `localRefresh` 的语义是**跳过第 1 步**（而不是「只做第 2 步」）：
  /// 用户填了 client 凭证却填错时，仍能靠在线续期拿到令牌；两处凭证都没填时
  /// 才会拿到那条包含全部排查指引的聚合错误（对齐 worker 的策略 1 → 策略 2）。
  Future<void> refreshAccessToken() async {
    final token = addition.refreshToken.trim();
    if (token.isEmpty) {
      throw const CloudDriverException(
        '阿里云盘缺少 refresh_token：请在账号表单填写 refresh_token'
        '（获取方法见 OpenList 官方文档 aliyundrive_open 驱动页）。',
      );
    }

    final failures = <String>[];

    if (!addition.localRefresh) {
      for (final url in _renewApiCandidates()) {
        try {
          final tokens = await _renewViaOnlineApi(url, token);
          _applyTokens(tokens.access, tokens.refresh);
          return; // 第一个成功的就用（worker：Success!）。
        } on CloudDriverException catch (e) {
          failures.add('$url → ${e.message}');
        } catch (e) {
          failures.add('$url → $e');
        }
      }
    }

    try {
      final tokens = await _renewViaOAuth(token);
      _applyTokens(tokens.access, tokens.refresh);
      return;
    } on CloudDriverException catch (e) {
      failures.add('${AliyundriveOpenClient.oauthApi} → ${e.message}');
    } catch (e) {
      failures.add('${AliyundriveOpenClient.oauthApi} → $e');
    }

    throw CloudDriverException(
      '[AliyundriveOpen] All token refresh strategies failed. '
      '请依次检查：1) refresh_token 是否有效且未过期；'
      '2) api_url_address 是否可访问；'
      '3) 若使用直连 OAuth，client_id / client_secret 是否正确。'
      '${failures.isEmpty ? '' : '尝试记录：${failures.join(' | ')}'}',
    );
  }

  /// 在线续期候选地址：自定义地址优先，其后是内置公共服务（worker 顺序）。
  List<String> _renewApiCandidates() {
    final custom = addition.apiUrlAddress.trim();
    return <String>[
      if (custom.isNotEmpty) custom,
      ...AliyundriveOpenClient.builtinRenewApis,
    ];
  }

  /// 走一次在线续期地址；拿不到 access_token 时抛错（由调用方继续轮询）。
  Future<({String access, String refresh})> _renewViaOnlineApi(
    String url,
    String token,
  ) async {
    final Response<String> res;
    try {
      res = await _dio.get<String>(
        url,
        queryParameters: {
          // 上游两个参数都传令牌值（`refresh_ui` 是 alist 续期服务的字段名）。
          'refresh_ui': token,
          'refresh_token': token,
          'server_use': 'true',
          'driver_txt': AliyundriveOpenClient.driverTxt,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Content-Type': 'application/json'},
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException('[Status ${e.response?.statusCode ?? '-'}] '
          '${e.message ?? e}');
    }

    final raw = res.data ?? '';
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      body = null;
    }
    if (body == null) {
      throw CloudDriverException(
        '[Status ${res.statusCode}] 非 JSON 响应：'
        '${raw.isEmpty ? '(空响应)' : _clip(raw)}',
      );
    }

    // access_token / refresh_token 可能在顶层，也可能裹在 data 里。
    final nested = body['data'];
    final data = nested is Map ? nested : const <String, dynamic>{};
    final access = _firstNonEmpty([
      body['access_token'] as String?,
      data['access_token'] as String?,
    ]);
    if (access == null) {
      throw CloudDriverException(
        '[Status ${res.statusCode}] Empty access_token from online API: '
        '${_clip(raw)}',
      );
    }
    final refresh = _firstNonEmpty([
      body['refresh_token'] as String?,
      data['refresh_token'] as String?,
    ]);
    // 续期服务没轮换 refresh_token 时保留原值（上游：if (newToken) this.refreshTokenVal = newToken）。
    return (access: access, refresh: refresh ?? token);
  }

  /// 直连 OAuth 刷新（worker 策略 2）。
  Future<({String access, String refresh})> _renewViaOAuth(String token) async {
    final clientId = addition.clientId.trim().isNotEmpty
        ? addition.clientId.trim()
        : AliyundriveOpenClient.defaultClientId;
    final clientSecret = addition.clientSecret.trim();

    final payload = <String, dynamic>{
      'grant_type': 'refresh_token',
      'refresh_token': token,
      'client_id': clientId,
      // 空 client_secret 不进 body（worker：if (clientSecret) payload.client_secret = ...）。
      if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
    };

    final Response<String> res;
    try {
      res = await _dio.post<String>(
        AliyundriveOpenClient.oauthApi,
        data: payload,
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException('[Status ${e.response?.statusCode ?? '-'}] '
          '${e.message ?? e}');
    }

    final raw = res.data ?? '';
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      body = null;
    }
    if (body == null) {
      throw CloudDriverException(
        '[Status ${res.statusCode}] 非 JSON 响应：'
        '${raw.isEmpty ? '(空响应)' : _clip(raw)}',
      );
    }

    final access = body['access_token'] as String?;
    if (access == null || access.isEmpty) {
      throw CloudDriverException(
        '[Status ${res.statusCode}] Invalid response: ${_clip(raw)}',
      );
    }
    final refresh = body['refresh_token'] as String?;
    return (
      access: access,
      refresh: (refresh == null || refresh.isEmpty) ? token : refresh,
    );
  }

  void _applyTokens(String access, String refresh) {
    accessToken = access;
    addition.accessToken = access;
    addition.refreshToken = refresh;
    onTokenUpdate?.call(<String, dynamic>{
      'access_token': access,
      'refresh_token': refresh,
    });
  }

  /// OpenAPI 请求：`POST {api}{path}` + JSON body + Bearer 认证。
  ///
  /// 返回 401 时刷新令牌并**重试一次**（对齐 worker `openApiRequest` 的
  /// `retry` 参数；只重试一次，防死循环）。
  Future<Map<String, dynamic>> openApiRequest(
    String path,
    Map<String, dynamic> body, {
    bool retry = true,
  }) async {
    if (accessToken.isEmpty) await refreshAccessToken();

    final Response<String> res;
    try {
      res = await _dio.post<String>(
        '${AliyundriveOpenClient.api}$path',
        data: body,
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException(
        '[AliyundriveOpen] 网络请求失败 $path：${e.message ?? e}',
      );
    }

    if (res.statusCode == 401 && retry) {
      await refreshAccessToken();
      return openApiRequest(path, body, retry: false);
    }

    final text = res.data ?? '';
    if (res.statusCode != 200) {
      // 原样带上端点与上游返回体（12 §2 第 2 步 / 11 §10 保存语义）。
      throw CloudDriverException(
        '[AliyundriveOpen] API error [${res.statusCode}] $path: ${_clip(text)}',
      );
    }

    Map<String, dynamic> decoded;
    try {
      final json = jsonDecode(text);
      decoded = json is Map<String, dynamic> ? json : <String, dynamic>{};
    } catch (_) {
      throw CloudDriverException(
        '[AliyundriveOpen] API error [${res.statusCode}] $path: '
        'invalid JSON response: ${_clip(text)}',
      );
    }
    return decoded;
  }

  /// 解析 drive_id（对齐 worker `resolveDriveId`）。
  ///
  /// 配置里有 `drive_id` 就直接用（[forceResource] 为真时忽略，供列表接口
  /// 报 `UserNotAllowedAccessDrive` 后**以 resource 类型重新解析**的自愈逻辑用）。
  /// 否则调 `/user/getDriveInfo`，按 `drive_type` 取对应的 drive_id；
  /// 取不到再按 resource → default → backup 顺序兜底。
  Future<String> resolveDriveId({bool forceResource = false}) async {
    if (!forceResource && addition.driveId.trim().isNotEmpty) {
      driveId = addition.driveId.trim();
      return driveId;
    }

    final res = await openApiRequest('/user/getDriveInfo', const <String, dynamic>{});
    final driveType = forceResource
        ? 'resource'
        : (addition.driveType.trim().isEmpty
            ? AliyundriveOpenClient.defaultDriveType
            : addition.driveType.trim());

    String pick(String type) {
      switch (type) {
        case 'resource':
          return res['resource_drive_id'] as String? ?? '';
        case 'backup':
          return res['backup_drive_id'] as String? ?? '';
        case 'default':
          return res['default_drive_id'] as String? ?? '';
        default:
          return '';
      }
    }

    var picked = pick(driveType);
    if (picked.isEmpty) {
      picked = _firstNonEmpty([
        res['resource_drive_id'] as String?,
        res['default_drive_id'] as String?,
        res['backup_drive_id'] as String?,
      ]) ??
          '';
    }
    if (picked.isEmpty) {
      throw const CloudDriverException(
        '[AliyundriveOpen] getDriveInfo 未返回任何 drive_id'
        '（resource / default / backup 都为空）：请确认账号已开通阿里云盘。',
      );
    }
    driveId = picked;
    return driveId;
  }

  /// drive_id 未解析时先解析（对齐 worker 各方法的 `if (!this.driveId)` 前置）。
  Future<String> _requireDriveId() async {
    if (driveId.isNotEmpty) return driveId;
    return resolveDriveId();
  }

  /// 列目录，`next_marker` 分页**翻完**（worker `listFiles` 的 do/while）。
  ///
  /// 列表接口报 `UserNotAllowedAccessDrive` 时，**以 resource 类型重新解析
  /// drive_id 再重试一次**（上游的自愈逻辑）。
  Future<List<AliyundriveOpenFile>> listFiles(String parentFileId) async {
    final items = <AliyundriveOpenFile>[];
    String? marker;
    var guard = 0;

    while (true) {
      final body = <String, dynamic>{
        'drive_id': await _requireDriveId(),
        'parent_file_id': parentFileId,
        'limit': AliyundriveOpenClient.pageSize,
        'order_by': AliyundriveOpenClient.listOrderBy,
        'order_direction': AliyundriveOpenClient.listOrderDirection,
        if (marker != null && marker.isNotEmpty) 'marker': marker,
      };

      Map<String, dynamic> resp;
      try {
        resp = await openApiRequest('/openFile/list', body);
      } on CloudDriverException catch (e) {
        if (!e.message.contains('UserNotAllowedAccessDrive')) rethrow;
        // 自愈：按 resource 类型重新解析 drive_id 后用新 id 重试一次。
        await resolveDriveId(forceResource: true);
        body['drive_id'] = driveId;
        resp = await openApiRequest('/openFile/list', body);
      }

      final list = resp['items'];
      if (list is List) {
        for (final e in list) {
          if (e is Map) {
            items.add(AliyundriveOpenFile.fromMap(Map<String, dynamic>.from(e)));
          }
        }
      }

      final next = resp['next_marker'] as String?;
      if (next == null || next.isEmpty) break;
      marker = next;
      // 防御：对端若一直回同一个游标（异常响应），别死循环。
      guard++;
      if (guard > 1000) break;
    }
    return items;
  }

  /// 单个文件元信息（`/openFile/get`）。
  Future<AliyundriveOpenFile> getFile(String fileId) async {
    final resp = await openApiRequest('/openFile/get', {
      'drive_id': await _requireDriveId(),
      'file_id': fileId,
    });
    return AliyundriveOpenFile.fromMap(resp);
  }

  /// 直链（`/openFile/getDownloadUrl`）→ `url || download_url`。
  ///
  /// **空直链抛错**（worker 返回空串），对齐 [CloudDriver.get] 的契约（11 §10）。
  Future<String> getDownloadUrl(String fileId) async {
    final resp = await openApiRequest('/openFile/getDownloadUrl', {
      'drive_id': await _requireDriveId(),
      'file_id': fileId,
      'expire_sec': AliyundriveOpenClient.linkExpireSec,
    });
    final url = _firstNonEmpty([
      resp['url'] as String?,
      resp['download_url'] as String?,
    ]);
    if (url == null) {
      throw const CloudDriverException(
        '[AliyundriveOpen] getDownloadUrl 未返回直链（url / download_url 都为空）',
      );
    }
    return url;
  }

  /// 新建目录（`/openFile/create`，`type: folder`）。
  Future<void> mkdir(String parentFileId, String name) async {
    await openApiRequest('/openFile/create', {
      'drive_id': await _requireDriveId(),
      'parent_file_id': parentFileId,
      'name': name,
      'type': 'folder',
      'check_name_mode': 'refuse',
    });
  }

  /// 重命名（`/openFile/update`）。
  Future<void> rename(String fileId, String newName) async {
    await openApiRequest('/openFile/update', {
      'drive_id': await _requireDriveId(),
      'file_id': fileId,
      'name': newName,
      'check_name_mode': 'refuse',
    });
  }

  /// 删除：`trash` → `/openFile/recyclebin`，`delete` → `/openFile/delete`。
  Future<void> remove(String fileId) async {
    final way = addition.removeWay.trim();
    final path = way == 'trash' || way.isEmpty
        ? '/openFile/recyclebin'
        : '/openFile/delete';
    await openApiRequest(path, {
      'drive_id': await _requireDriveId(),
      'file_id': fileId,
    });
  }

  /// 移动（`/openFile/move`）。
  Future<void> move(String fileId, String toParentFileId) async {
    await openApiRequest('/openFile/move', {
      'drive_id': await _requireDriveId(),
      'file_id': fileId,
      'to_parent_file_id': toParentFileId,
      'check_name_mode': 'refuse',
    });
  }

  /// 复制（`/openFile/copy`，`auto_rename: true`）。
  Future<void> copy(String fileId, String toParentFileId) async {
    await openApiRequest('/openFile/copy', {
      'drive_id': await _requireDriveId(),
      'file_id': fileId,
      'to_parent_file_id': toParentFileId,
      'auto_rename': true,
    });
  }

  /// 真连校验：强制走一次 `/user/getDriveInfo`，能解析出 drive_id 即说明
  /// access_token 与账号都可用（对齐 Go `Init` 用 getDriveInfo 做首连的做法）。
  ///
  /// 与 [resolveDriveId] 的差别：**忽略配置里的 drive_id**，因此即便用户
  /// 填了 drive_id 也能起到「令牌真的可用」的校验作用。
  Future<String> getDriveInfo() async {
    driveId = '';
    return resolveDriveId();
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// 错误原文截断（避免整页 HTML 灌进异常信息）。
  static String _clip(String s, [int max = 300]) =>
      s.length > max ? s.substring(0, max) : s;
}

/// 阿里云盘开放平台驱动（[CloudDriver] 实现）。
///
/// 上游用**文件 id** 操作，本应用给的是**绝对路径**，因此在实例内维护
/// path→id 缓存（对齐 worker 的 `pathFileIdCache`）；写操作后整表 clear。
/// 缓存随驱动重建失效（12 §3 注记 / 99 §4.6）。
class AliyundriveOpenDriver extends CloudDriver {
  AliyundriveOpenDriver({
    required AliyundriveOpenAddition addition,
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    Dio? dio,
  }) : _client = AliyundriveOpenClient(
          addition,
          onTokenUpdate: onTokenUpdate,
          dio: dio,
        );

  final AliyundriveOpenClient _client;

  /// path → fileId。键是「去掉首尾斜杠的规范路径」，根为空串。
  final Map<String, String> _pathCache = <String, String>{};

  AliyundriveOpenAddition get addition => _client.addition;

  /// 测试用：直接拿 API 客户端。
  AliyundriveOpenClient get client => _client;

  @override
  Future<void> init() async {
    // 换 / 校验令牌，再真连一次 getDriveInfo 确认令牌真的可用
    //（对齐百度 uinfo 的等价语义，12 §2 第 3 步；保存账号时也走这条）。
    await _client.login();
    await _client.getDriveInfo();
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final id = await _resolveFileId(path);
    final files = await _client.listFiles(id);
    return [for (final f in files) _toItem(f)];
  }

  /// 取单个条目（对齐 worker `get` 的探测顺序）。
  ///
  /// **有意差异**：worker 拿不到直链时把 `raw_url` 留空返回，
  /// 本实现让 [AliyundriveOpenClient.getDownloadUrl] 的异常**自然抛出**
  /// —— [CloudDriver.get] 的契约要求文件必须带 `rawUrl`（11 §10）。
  @override
  Future<CloudFileItem> get(String path) async {
    final clean = _clean(path);
    if (clean.isEmpty) {
      // 浏览根：不透明 id，没有目录条目，返回一个目录占位。
      return const CloudFileItem(name: '/', isDir: true);
    }

    final fileId = await _resolveFileId(clean);

    // 1. 先拿元信息（worker `getFile(fileId).catch(() => null)`）。
    AliyundriveOpenFile? file;
    try {
      file = await _client.getFile(fileId);
    } on CloudDriverException {
      file = null;
    }

    if (file != null) {
      final item = _toItem(file);
      if (item.isDir) return item;
      // 直链失败要抛出真实原因（网络 / 业务码都已被包成 CloudDriverException）。
      final url = await _client.getDownloadUrl(fileId);
      return CloudFileItem(
        name: item.name,
        isDir: false,
        size: item.size,
        modified: item.modified,
        rawUrl: url,
        // 阿里云盘直链是带签名的公开 URL，上游 / Go 版都没有声明必需请求头。
        rawHeaders: const <String, String>{},
      );
    }

    // 2. 元信息拿不到 → 探测它是不是目录（列一次；能列就是目录）。
    try {
      await _client.listFiles(fileId);
      return CloudFileItem(name: cloudBasename(clean), isDir: true);
    } on CloudDriverException {
      // 3. 两者都不是：报真实原因（worker 在这里返回一个 is_dir:false 的
      //    无直链条目，本应用按契约直说）。
      throw CloudDriverException(
        '[AliyundriveOpen] 无法获取条目或直链：$clean（file_id=$fileId）',
      );
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final clean = _clean(path);
    final name = cloudBasename(clean);
    if (name.isEmpty) {
      throw const CloudDriverException('[AliyundriveOpen] 不能创建根目录');
    }
    final parentId = await _resolveFileId(cloudDirname(clean));
    await _client.mkdir(parentId, name);
    _pathCache.clear();
  }

  /// 改名 / 改路径。同目录 → `/openFile/update`；
  /// 跨目录 → 降级为「移动 + 改名」（接口契约，12 §2 第 3 步）。
  @override
  Future<void> rename(String path, String newPath) async {
    final src = _clean(path);
    final dst = _clean(newPath);
    if (src == dst) return;
    final entry = await _resolveEntry(src);
    final newName = cloudBasename(dst);
    if (cloudDirname(src) == cloudDirname(dst)) {
      await _client.rename(entry.fileId, newName);
    } else {
      final dstId = await _resolveFileId(cloudDirname(dst));
      await _client.move(entry.fileId, dstId);
      if (newName.isNotEmpty && newName != entry.name) {
        await _client.rename(entry.fileId, newName);
      }
    }
    _pathCache.clear();
  }

  @override
  Future<void> remove(String path) async {
    final entry = await _resolveEntry(_clean(path));
    await _client.remove(entry.fileId);
    _pathCache.clear();
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final entry = await _resolveEntry(_clean(srcPath));
    final dstId = await _resolveFileId(dstDir);
    await _client.move(entry.fileId, dstId);
    if (newName.isNotEmpty && newName != entry.name) {
      await _client.rename(entry.fileId, newName);
    }
    _pathCache.clear();
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final entry = await _resolveEntry(_clean(srcPath));
    final dstId = await _resolveFileId(dstDir);
    // 上游 copy 没有 new_name 参数，只能复制后改名（auto_rename: true
    // 让上游先给个不冲突的名字）。
    await _client.copy(entry.fileId, dstId);
    if (newName.isNotEmpty && newName != entry.name) {
      // 复制出来的新 file_id 上游才回传，这里重新列一次目标目录定位它。
      final copied = await _findInDir(dstId, entry.name);
      if (copied != null) await _client.rename(copied.fileId, newName);
    }
    _pathCache.clear();
  }

  /// 逐层列目录把路径解析成 file_id（对齐 worker `resolveFileId`）。
  ///
  /// 每一层先吃缓存；匹配顺序是「原始段名 → `Uri.decodeComponent` 后的名字
  /// → 段名本身就是 file_id」（上游 `resolveFileId` 的三段匹配）。
  Future<String> _resolveFileId(String path) async {
    final clean = _clean(path);
    if (clean.isEmpty) return _rootId();

    final cached = _pathCache[clean];
    if (cached != null && cached.isNotEmpty) return cached;

    final parts = clean.split('/');
    var currentId = _rootId();
    for (var i = 0; i < parts.length; i++) {
      final rawPart = parts[i];
      final subPath = parts.sublist(0, i + 1).join('/');
      final subCached = _pathCache[subPath];
      if (subCached != null && subCached.isNotEmpty) {
        currentId = subCached;
        continue;
      }

      final decodedPart = _tryDecode(rawPart);
      final items = await _client.listFiles(currentId);
      AliyundriveOpenFile? target;
      for (final f in items) {
        if (f.name == rawPart ||
            f.name == decodedPart ||
            f.fileId == rawPart) {
          target = f;
          break;
        }
      }
      if (target == null) {
        throw CloudDriverException(
          "[AliyundriveOpen] Path '$rawPart' not found",
        );
      }
      currentId = target.fileId;
      _pathCache[subPath] = currentId;
    }
    return currentId;
  }

  /// 列父目录找条目（写操作用）。
  Future<AliyundriveOpenFile> _resolveEntry(String path) async {
    final clean = _clean(path);
    final name = cloudBasename(clean);
    if (name.isEmpty) {
      throw const CloudDriverException('[AliyundriveOpen] 不能对根目录执行该操作');
    }
    final parentId = await _resolveFileId(cloudDirname(clean));
    final found = await _findInDir(parentId, name);
    if (found == null) {
      throw CloudDriverException("[AliyundriveOpen] '$name' not found");
    }
    return found;
  }

  /// 在目录里按名字找条目（原始名 → 解码名的顺序）。
  Future<AliyundriveOpenFile?> _findInDir(String dirId, String name) async {
    final decoded = _tryDecode(name);
    final items = await _client.listFiles(dirId);
    for (final f in items) {
      if (f.name == name || f.name == decoded) return f;
    }
    return null;
  }

  String _rootId() {
    final id = addition.rootFolderId.trim();
    return id.isEmpty ? AliyundriveOpenClient.defaultRoot : id;
  }

  /// 规范化路径：折叠重复斜杠、去掉首尾斜杠（根 → 空串）。
  String _clean(String p) {
    final segs = p.split('/').where((s) => s.isNotEmpty).toList();
    return segs.join('/');
  }

  String _tryDecode(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  CloudFileItem _toItem(AliyundriveOpenFile f) => CloudFileItem(
        name: f.name,
        isDir: f.isDir,
        size: f.size,
        modified: f.modified,
      );
}

/// 解析阿里云盘的时间戳。
///
/// 上游 `updated_at` / `created_at` 是 **ISO8601 字符串**
/// （如 `2024-01-02T03:04:05.000Z`，Go 版直接 `time.Time` 反序列化），
/// 交给 [DateTime.tryParse] 即可；解析失败返回 null，不伪造时间。
DateTime? parseAliyundriveOpenTime(String? s) {
  if (s == null) return null;
  final v = s.trim();
  if (v.isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

/// 驱动自描述（99 §7.2.10）：类型、显示名、能力遮罩、表单参数、构造
/// 全部收在本文件；`driver_registry.dart` 加一行即接入账号表单。
class AliyundriveOpenSpec extends CloudDriverSpec {
  const AliyundriveOpenSpec();

  /// 与 OpenList 驱动目录名一致。
  @override
  String get typeId => 'aliyundrive_open';

  @override
  String get displayName => '阿里云盘开放平台';

  /// 列出 / 读取 / 创建文件夹 / 移动 / 复制 / 删除；write 一律不给
  /// （上传已砍，99 §7.2.1）。
  @override
  int get capabilities => AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  List<CloudDriverFormItem> get form => const [
        CloudDriverField(
          key: 'refresh_token',
          label: 'refresh_token',
          hint: '必填；获取方法见 OpenList 官方文档（aliyundrive_open 驱动页）',
          required: true,
          obscure: true,
        ),
        CloudDriverSelectField(
          key: 'drive_type',
          label: '网盘类型',
          hint: '资源盘 / 默认盘 / 备份盘，对应同一个账号下的不同 drive_id',
          options: [
            ('resource', '资源盘'),
            ('default', '默认盘'),
            ('backup', '备份盘'),
          ],
          defaultValue: AliyundriveOpenClient.defaultDriveType,
          required: true,
        ),
        CloudDriverField(
          key: 'api_url_address',
          label: '在线续期地址',
          hint: '默认用 OpenList 维护的公共服务',
          defaultValue: AliyundriveOpenClient.defaultRenewApi,
          disabledWhenSwitch: 'local_refresh',
          disabledHint: '已开启本地刷新（在线续期分支停用），关闭开关后可编辑',
        ),
        CloudDriverSwitchField(
          key: 'local_refresh',
          label: '在本地处理令牌刷新',
          subtitle: '关闭＝用在线续期地址轮询；开启＝用自建阿里云应用直接刷新（需 Client ID / Secret）',
        ),
        CloudDriverField(
          key: 'client_id',
          label: 'Client ID',
          visibleWhenSwitch: 'local_refresh',
        ),
        CloudDriverField(
          key: 'client_secret',
          label: 'Client Secret',
          obscure: true,
          visibleWhenSwitch: 'local_refresh',
        ),
        CloudDriverSelectField(
          key: 'remove_way',
          label: '删除方式',
          hint: '移入回收站可在阿里云盘里找回；彻底删除不可恢复',
          options: [
            ('trash', '移入回收站'),
            ('delete', '彻底删除'),
          ],
          defaultValue: AliyundriveOpenClient.defaultRemoveWay,
        ),
        CloudDriverField(
          key: 'root_folder_id',
          label: '根目录 ID',
          hint: '不透明 id，默认 root（网盘根目录）；与账号的远程路径叠加生效',
          defaultValue: AliyundriveOpenClient.defaultRoot,
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    return AliyundriveOpenDriver(
      addition: AliyundriveOpenAddition.fromJson(config),
      onTokenUpdate: onTokenUpdate,
    );
  }
}
