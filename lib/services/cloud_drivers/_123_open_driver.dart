/// 123 云盘开放平台驱动（OpenList `123_open` 移植）。
///
/// 移植自 `localdev/OpenList-Worker/src/backend/drivers/123_open`
/// （driver.ts + util.ts + types.ts，移植底稿）与
/// `localdev/OpenList/drivers/123_open`（Go 版，语义兜底）。
///
/// **文件名用下划线前缀**只是为了让 Dart 的 import 标识符不以数字开头；
/// [spec] 的 typeId 仍是上游目录名 `123_open`（存库值）。
///
/// **能力面**：`list | read | mkdir | move | delete`。**不给 copy**：
/// worker 的 `copy()` 直接抛 `[123Open] copy not supported`，Go 版
/// `Copy` 依赖上传秒传（上传已砍，99 §7.2.1），两版都没有可移植的实现。
/// 上传 / put 同样不移植。
///
/// 与 worker 底稿的有意差异（对齐 [CloudDriver.get] 的契约，见 11 §10）：
/// - [Driver123Open.get] 文件拿不到直链时**抛真实原因**，而不是像 worker
///   那样把 `raw_url_error` 记在条目上返回无直链的条目——客户端里下游
///   必然失败，不如直说。
///
/// **不移植**：`order_by` / `order_direction`（客户端自己排序）、
/// `use_online_api` 开关（被「在本地处理令牌刷新」开关取代，默认走在线续期）、
/// Go 版的 `DirectLink` / 直链签名（本应用只走 `download_info`）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/account_capabilities.dart';
import '../cloud_driver.dart';

/// 驱动配置（对齐上游 `Driver123OpenAddition`；键名与上游一致，便于对照排错）。
class Driver123OpenAddition {
  Driver123OpenAddition({
    required this.refreshToken,
    this.clientId = '',
    this.clientSecret = '',
    this.apiUrlAddress = Driver123OpenClient.defaultRenewApi,
    this.localRefresh = false,
    this.rootFolderId = Driver123OpenClient.defaultRoot,
    this.accessToken = '',
  });

  factory Driver123OpenAddition.fromJson(Map<String, dynamic> json) =>
      Driver123OpenAddition(
        refreshToken: json['refresh_token'] as String? ?? '',
        clientId: json['client_id'] as String? ?? '',
        clientSecret: json['client_secret'] as String? ?? '',
        apiUrlAddress:
            json['api_url_address'] as String? ?? Driver123OpenClient.defaultRenewApi,
        localRefresh: json['local_refresh'] as bool? ?? false,
        rootFolderId:
            json['root_folder_id'] as String? ?? Driver123OpenClient.defaultRoot,
        accessToken: json['access_token'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
        'api_url_address': apiUrlAddress,
        'local_refresh': localRefresh,
        'root_folder_id': rootFolderId,
        'access_token': accessToken,
      };

  /// 刷新令牌（表单必填）。在线续期会轮换它，轮换结果经 onTokenUpdate 持久化。
  String refreshToken;

  /// 自建 123 开放平台应用的 ClientID / ClientSecret（仅本地刷新时需要）。
  String clientId;
  String clientSecret;

  /// 在线续期地址；空串回落到 [Driver123OpenClient.defaultRenewApi]。
  ///
  /// 默认值照抄 Go `meta.go`（`use_online_api` 默认 true → 默认走在线续期）。
  String apiUrlAddress;

  /// 「在本地处理令牌刷新」开关：true = 用 client_id / client_secret 刷新；
  /// false = 走在线续期地址。对应上游 `use_online_api` 的反相
  /// （`use_online_api !== false` ↔ `!localRefresh`）。
  bool localRefresh;

  /// 浏览根目录 id（上游 `root_folder_id`；不透明 id，默认 `0`）。
  ///
  /// 注意它与账号的「远程路径」**叠加**：远程路径是虚拟前缀，由
  /// `CloudDriveService.joinRemotePath` 拼在驱动路径前（12 §6.3）。
  String rootFolderId;

  /// access_token 缓存（自动持久化，不进表单、不进备份明文）。
  String accessToken;
}

/// 123 云盘文件条目（上游 `File123` / Go `File`）。
class Driver123OpenFile {
  Driver123OpenFile({
    required this.fileId,
    required this.filename,
    required this.size,
    required this.type,
    this.updateAt = '',
  });

  static Driver123OpenFile fromMap(Map<String, dynamic> m) => Driver123OpenFile(
        fileId: (m['fileId'] as num?)?.toInt() ?? 0,
        filename: m['filename'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        type: (m['type'] as num?)?.toInt() ?? 0,
        updateAt: m['update_at'] as String? ?? '',
      );

  final int fileId;
  final String filename;
  final int size;

  /// 1 = 目录，2 = 文件（上游 `type`）。
  final int type;

  /// `"2006-01-02 15:04:05"` 形式的 **UTC+8** 字符串（无时区信息）。
  final String updateAt;

  bool get isDir => type == 1;
}

/// 123 云盘开放平台 API 客户端。
///
/// 认证：`Authorization: Bearer <access_token>` + header `platform: open_platform`。
/// 响应包裹：`{code, message, data}`；`code !== 0` 即错误，**`code === 401`
/// 表示令牌失效 → 刷新后重试一次**（只重试一次，防死循环）。
class Driver123OpenClient {
  /// API 基址。
  static const String api = 'https://open-api.123pan.com';

  /// 在线续期地址默认值（照抄 Go `meta.go` 的 `api_url_address` default）。
  static const String defaultRenewApi = 'https://api.oplist.org/123cloud/renewapi';

  /// 默认浏览根 id（Go `driver.Config.DefaultRoot`）。
  static const String defaultRoot = '0';

  /// 在线续期的 `driver_txt`（上游 util.ts 写死）。
  static const String driverTxt = '123cloud_oa';

  /// 文件列表分页大小（上游固定 100）。
  static const int pageSize = 100;

  /// 令牌失效的业务码（上游 util.ts / Go util.go 一致）。
  static const int codeUnauthorized = 401;

  /// 响应里 `last_file_id` 表示「没有下一页」的哨兵值。
  static const int lastPageSentinel = -1;

  Driver123OpenClient(this.addition, {this.onTokenUpdate, Dio? dio})
      : accessToken = addition.accessToken,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'Accept': 'application/json'},
                // 非 2xx 也回来走 code / 原文解析：「原样传递报错」需要读到 body。
                validateStatus: (_) => true,
              ),
            );

  final Driver123OpenAddition addition;
  String accessToken;

  /// 令牌轮换回调（Online API 会同时轮换 refresh_token，两个都要存）。
  final void Function(Map<String, dynamic> patch)? onTokenUpdate;

  final Dio _dio;

  /// 无缓存 access_token 就先换一次（对齐 worker `init()`）。
  Future<void> login() async {
    if (accessToken.isEmpty) await getAccessToken();
  }

  /// 取 access_token，两条路（对齐 worker `getAccessToken` 的两个分支）：
  ///
  /// 1. **在线续期**（`!localRefresh` 且有 refresh_token + api_url_address）：
  ///    `GET {api_url_address}?refresh_ui=<rt>&server_use=true&driver_txt=123cloud_oa`
  ///    → `{access_token, refresh_token}`，**两个都要存**。
  /// 2. **本地刷新**（`localRefresh`）：`POST /api/v1/access_token`，
  ///    body `{clientID, clientSecret}` → `data.access_token`
  ///    （不轮换 refresh_token）。
  ///
  /// 两条路互斥：走了在线续期失败就抛错，绝不拿 client 凭证兜底
  /// （与 worker 的短路 `return` 语义一致）。
  Future<void> getAccessToken() async {
    final a = addition;

    // 1. 在线续期地址（默认路径）。
    //
    // `apiUrlAddress` 为空**不是**「不走在线续期」——[defaultRenewApi] 是它的
    // 默认值（照 Go meta.go 的 default），空串要回落到默认公共服务地址。
    // 早先这里多加了 `isNotEmpty` 守卫，导致「表单留空 → 两条路都不走 → 报
    // no valid authentication method」，与百度同款行为不一致（百度空串回落）。
    if (!a.localRefresh && a.refreshToken.isNotEmpty) {
      await _renewOnline();
      return;
    }

    // 2. 自建应用的 client 凭证。
    if (a.clientId.isNotEmpty && a.clientSecret.isNotEmpty) {
      await _renewByClientCredentials();
      return;
    }

    // 缺必填 refresh_token 时给出可读原因（表单已标必填，这是后端兜底）。
    if (a.refreshToken.trim().isEmpty) {
      throw const CloudDriverException(
        '123 云盘缺少 refresh_token：请填写 refresh_token（获取方法见 OpenList 官方文档 123_open 驱动页）',
      );
    }
    throw const CloudDriverException(
      '[123Open] no valid authentication method '
      '(access_token / refresh_token / client_id+client_secret)',
    );
  }

  /// 在线续期 API 刷新（上游分支 1）。
  Future<void> _renewOnline() async {
    final a = addition;
    final u = a.apiUrlAddress.trim().isNotEmpty
        ? a.apiUrlAddress.trim()
        : defaultRenewApi;
    final res = await _dio.get<String>(
      u,
      queryParameters: {
        'refresh_ui': a.refreshToken,
        'server_use': 'true',
        'driver_txt': driverTxt,
      },
      options: Options(responseType: ResponseType.plain),
    );
    final raw = res.data ?? '';
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      data = null;
    }
    final access = data?['access_token'] as String?;
    final refresh = data?['refresh_token'] as String?;
    if (access != null && access.isNotEmpty && refresh != null && refresh.isNotEmpty) {
      _applyTokens(access, refresh);
      return;
    }
    // 续期服务把原因放在这些字段里（顺序对齐上游）。
    final err = (data?['error_description'] ??
            data?['text'] ??
            data?['message'] ??
            data?['error']) as String?;
    if (err != null && err.isNotEmpty) {
      throw CloudDriverException('[123Open] $err');
    }
    throw CloudDriverException(
      '在线 API 刷新失败 (HTTP ${res.statusCode})：'
      '${raw.isEmpty ? '非 JSON 响应' : (raw.length > 300 ? raw.substring(0, 300) : raw)}。'
      '请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。',
    );
  }

  /// client_id + client_secret 刷新（上游分支 2）。
  Future<void> _renewByClientCredentials() async {
    final a = addition;
    // 令牌端点走**裸请求**，不经 401 重试的 `request()`：否则
    // 「401 → 刷新 → 打令牌端点 → 又 401 → 再刷新」会无限递归
    // （上游 worker 这里也是直接 fetch，不套 request）。
    final resp = await _send(
      '/api/v1/access_token',
      method: 'POST',
      body: {'clientID': a.clientId, 'clientSecret': a.clientSecret},
    );
    final code = (resp['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final message = resp['message'] as String? ?? '';
      throw CloudDriverException(
        '[123Open] ${message.isEmpty ? 'code $code' : message}',
      );
    }
    final data = resp['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final access = map['access_token'] as String?;
    if (access == null || access.isEmpty) {
      throw const CloudDriverException('[123Open] empty access token');
    }
    // 自建应用刷新只换 access_token，refresh_token 不动。
    _applyTokens(access, a.refreshToken);
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

  /// 带钱包的请求：`code !== 0` 抛 [CloudDriverException]；
  /// `code === 401` 强制刷新一次后**重试一次**（对齐 worker `request`）。
  ///
  /// [pathname] 只用于错误原文，让报错带上端点。
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, String>? query,
    Object? body,
    String? pathname,
  }) async {
    if (accessToken.isEmpty) await getAccessToken();

    Map<String, dynamic> data;
    try {
      data = await _send(path, method: method, query: query, body: body);
    } on CloudDriverException {
      rethrow; // 业务错误不重试。
    } catch (e) {
      throw CloudDriverException(
        '123 云盘请求失败：${pathname ?? path}',
        e,
      );
    }

    if (data['code'] == codeUnauthorized) {
      await getAccessToken();
      data = await _send(path, method: method, query: query, body: body);
    }

    final code = (data['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final message = data['message'] as String? ?? '';
      throw CloudDriverException(
        '[123Open] ${message.isEmpty ? 'code $code' : message}',
      );
    }
    return data;
  }

  /// 发一次请求并解析 JSON 包裹，不做业务码判定。
  Future<Map<String, dynamic>> _send(
    String path, {
    required String method,
    Map<String, String>? query,
    Object? body,
  }) async {
    final Response<String> res;
    try {
      res = await _dio.request<String>(
        '$api$path',
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'platform': 'open_platform',
          },
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException('[123Open] 网络请求失败：${e.message ?? e}');
    }
    final text = res.data ?? '';
    Map<String, dynamic> decoded;
    try {
      final json = jsonDecode(text);
      decoded = json is Map<String, dynamic> ? json : <String, dynamic>{};
    } catch (_) {
      throw CloudDriverException(
        '[123Open] invalid JSON response, status ${res.statusCode}',
      );
    }
    return decoded;
  }

  /// 取 `data` 段并做类型收窄（`data` 缺失时返回空 map）。
  Future<Map<String, dynamic>> _request(
    String path, {
    required String method,
    required String pathname,
    Map<String, String>? query,
    Object? body,
  }) async {
    final resp = await request(
      path,
      method: method,
      query: query,
      body: body,
      pathname: pathname,
    );
    final data = resp['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// 列目录：100 一页翻完，过滤掉 `trashed !== 0` 的条目
  /// （对齐 worker `getFiles`；Go 版注释：trashed 参数失效只能遍历过滤）。
  Future<List<Driver123OpenFile>> getFiles(String parentFileId) async {
    final all = <Driver123OpenFile>[];
    var lastFileId = 0;
    var guard = 0;
    while (lastFileId != lastPageSentinel) {
      final data = await _request(
        '/api/v2/file/list',
        method: 'GET',
        pathname: 'file/list',
        query: {
          'parentFileId': parentFileId,
          'limit': '$pageSize',
          'lastFileId': '$lastFileId',
          'trashed': 'false',
          'searchMode': '',
          'searchData': '',
        },
      );
      final list = data['file_list'];
      if (list is List) {
        for (final e in list) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          if (((m['trashed'] as num?)?.toInt() ?? 0) != 0) continue;
          all.add(Driver123OpenFile.fromMap(m));
        }
      }
      lastFileId = (data['last_file_id'] as num?)?.toInt() ?? lastPageSentinel;
      // 防御：对端若一直回同一个游标（异常响应），别死循环。
      guard++;
      if (guard > 1000) break;
    }
    return all;
  }

  /// 文件直链：`/api/v1/file/download_info?fileId=..` → `data.download_url`。
  Future<String> getDownloadUrl(int fileId) async {
    final data = await _request(
      '/api/v1/file/download_info',
      method: 'GET',
      pathname: 'file/download_info',
      query: {'fileId': '$fileId'},
    );
    final url = data['download_url'] as String?;
    if (url == null || url.isEmpty) {
      throw const CloudDriverException('[123Open] empty download url');
    }
    return url;
  }

  /// 新建目录（上游 `mkdir`）。
  Future<void> mkdir(String parentId, String name) async {
    await _request(
      '/upload/v1/file/mkdir',
      method: 'POST',
      pathname: 'file/mkdir',
      body: {'parentID': parentId, 'name': name},
    );
  }

  /// 移动（上游 `move`）。
  Future<void> move(int fileId, String toParentFileId) async {
    await _request(
      '/api/v1/file/move',
      method: 'POST',
      pathname: 'file/move',
      body: {
        'fileIDs': [fileId],
        'toParentFileID': toParentFileId,
      },
    );
  }

  /// 重命名（上游 `rename`；HTTP 动词是 PUT）。
  Future<void> rename(int fileId, String fileName) async {
    await _request(
      '/api/v1/file/name',
      method: 'PUT',
      pathname: 'file/name',
      body: {'fileId': fileId, 'fileName': fileName},
    );
  }

  /// 删除（上游 `remove`，实为移入回收站 `/api/v1/file/trash`）。
  Future<void> remove(int fileId) async {
    await _request(
      '/api/v1/file/trash',
      method: 'POST',
      pathname: 'file/trash',
      body: {
        'fileIDs': [fileId],
      },
    );
  }

  /// 真连校验：`/api/v1/user/info`（Go 版 `GetDetails` 用的端点）。
  /// 令牌失效 / 无权限在此抛出可读原因。
  Future<void> userInfo() async {
    await _request(
      '/api/v1/user/info',
      method: 'GET',
      pathname: 'user/info',
    );
  }
}

/// 123 云盘驱动（[CloudDriver] 实现）。
///
/// 上游用**文件 id** 操作，本应用给的是**绝对路径**，因此在实例内维护
/// path→id 缓存（对齐 worker 的 `pathCache`；写操作后整表 clear）。
/// 缓存随驱动重建失效（99 §4.6）。
class Driver123Open extends CloudDriver {
  Driver123Open({
    required Driver123OpenAddition addition,
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    Dio? dio,
  }) : _client = Driver123OpenClient(
          addition,
          onTokenUpdate: onTokenUpdate,
          dio: dio,
        );

  final Driver123OpenClient _client;

  /// path → fileId（目录）。键是「去掉前导斜杠的规范路径」，根为空串。
  final Map<String, String> _pathCache = <String, String>{};

  Driver123OpenAddition get addition => _client.addition;

  /// 测试用：直接拿 API 客户端。
  Driver123OpenClient get client => _client;

  @override
  Future<void> init() async {
    // 换 / 校验令牌，再真连一次 user/info 确认令牌真的可用
    //（对齐百度 uinfo 的等价语义，12 §2 第 3 步）。
    await _client.login();
    await _client.userInfo();
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final id = await _resolveDirId(path);
    final files = await _client.getFiles(id);
    return [for (final f in files) _toItem(f)];
  }

  /// 取单个条目（对齐 worker `get` 的探测顺序）。
  ///
  /// **有意差异**：worker 拿不到直链时把 `raw_url_error` 记在条目上返回，
  /// 本实现按 [CloudDriver.get] 的契约**抛真实原因**——文件必须带 `rawUrl`
  /// （11 §10）。
  @override
  Future<CloudFileItem> get(String path) async {
    final clean = _clean(path);
    final rawName = cloudBasename(clean);
    if (clean.isEmpty) {
      // 浏览根：不透明 id，没有目录条目，返回一个目录占位。
      return const CloudFileItem(name: '/', isDir: true);
    }

    // 1. 先列父目录找条目（对齐 worker）。try 只罩「找条目」这一段：
    //    直链失败必须抛出真实原因，不能被兜底分支吃掉。
    Driver123OpenFile? file;
    try {
      final parentId = await _resolveDirId(cloudDirname(clean));
      final files = await _client.getFiles(parentId);
      for (final f in files) {
        if (f.filename == rawName) {
          file = f;
          break;
        }
      }
    } on CloudDriverException {
      // 父目录解析 / 列表失败 → 落到目录探测分支（同 worker 的 try/catch 包裹）。
      file = null;
    }

    if (file != null) {
      final item = _toItem(file);
      if (!item.isDir) {
        // 直链失败要抛出真实原因（网络 / 业务码都已被包成 CloudDriverException）。
        final url = await _client.getDownloadUrl(file.fileId);
        return CloudFileItem(
          name: item.name,
          isDir: false,
          size: item.size,
          modified: item.modified,
          rawUrl: url,
          // 123 直链是公开 URL，上游未声明必需请求头（worker / Go 同）。
          rawHeaders: const {},
        );
      }
      return item;
    }

    // 2. 探测它是不是目录。
    try {
      await _resolveDirId(clean);
      return CloudFileItem(name: rawName, isDir: true);
    } on CloudDriverException {
      throw CloudDriverException('123 云盘文件不存在：$rawName');
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final clean = _clean(path);
    final name = cloudBasename(clean);
    if (name.isEmpty) {
      throw const CloudDriverException('[123Open] 不能创建根目录');
    }
    final parentId = await _resolveDirId(cloudDirname(clean));
    await _client.mkdir(parentId, name);
    _pathCache.clear();
  }

  /// 改名 / 改路径。同目录 → `/api/v1/file/name`；
  /// 跨目录 → 降级为「移动 + 改名」（对齐上游 Go 的 Move + Rename 组合）。
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
      final dstId = await _resolveDirId(cloudDirname(dst));
      await _client.move(entry.fileId, dstId);
      if (newName.isNotEmpty && newName != entry.filename) {
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
    final dstId = await _resolveDirId(dstDir);
    await _client.move(entry.fileId, dstId);
    if (newName.isNotEmpty && newName != entry.filename) {
      await _client.rename(entry.fileId, newName);
    }
    _pathCache.clear();
  }

  /// 上游 `copy()` 抛 `[123Open] copy not supported`（Go 版依赖上传秒传），
  /// 能力位不给 `copy`，这里兜底报错（正常不会被调用）。
  @override
  Future<void> copy(String srcPath, String dstDir, String newName) =>
      throw const CloudDriverException('[123Open] copy not supported');

  /// 逐层列目录把路径解析成目录 id（对齐 worker `resolveDirId`）。
  Future<String> _resolveDirId(String path) async {
    final clean = _clean(path);
    if (clean.isEmpty) return _rootId();

    final cached = _pathCache[clean];
    if (cached != null && cached.isNotEmpty) return cached;

    final parts = clean.split('/');
    var currentId = _rootId();
    for (var i = 0; i < parts.length; i++) {
      final files = await _client.getFiles(currentId);
      String? next;
      for (final f in files) {
        if (f.isDir && f.filename == parts[i]) {
          next = '${f.fileId}';
          break;
        }
      }
      if (next == null) {
        throw CloudDriverException("[123Open] Directory '${parts[i]}' not found");
      }
      currentId = next;
      // 缓存键必须与上面的查表键同形：[clean] 已去掉前导斜杠（`_clean`），
      // 这里早先写成 `/${...}`（带前导斜杠）导致**永远查不中**，缓存形同虚设、
      // 每次 list 都要逐层重新解析（还被「写操作后清缓存」的用例逮到）。
      _pathCache[parts.sublist(0, i + 1).join('/')] = currentId;
    }
    return currentId;
  }

  /// 列父目录找条目（对齐 worker `resolveEntry`）。
  Future<Driver123OpenFile> _resolveEntry(String path) async {
    final clean = _clean(path);
    final name = cloudBasename(clean);
    if (name.isEmpty) {
      throw const CloudDriverException('[123Open] 不能对根目录执行该操作');
    }
    final parentId = await _resolveDirId(cloudDirname(clean));
    final files = await _client.getFiles(parentId);
    for (final f in files) {
      if (f.filename == name) return f;
    }
    throw CloudDriverException("[123Open] '$name' not found");
  }

  String _rootId() {
    final id = addition.rootFolderId.trim();
    return id.isEmpty ? Driver123OpenClient.defaultRoot : id;
  }

  /// 规范化路径：折叠重复斜杠、去掉首尾斜杠（根 → 空串）。
  String _clean(String p) {
    final segs = p.split('/').where((s) => s.isNotEmpty).toList();
    return segs.join('/');
  }

  CloudFileItem _toItem(Driver123OpenFile f) => CloudFileItem(
        name: f.filename,
        isDir: f.isDir,
        size: f.size,
        modified: parse123OpenTime(f.updateAt),
      );
}

/// 解析 123 云盘的 `update_at` / `create_at` 时间串。
///
/// 格式 `"2006-01-02 15:04:05"`（上游 `parseTime` / Go `ModTime` 一致），
/// **没有时区信息，默认 UTC+8**——必须显式减 8 小时，不能当本地时间解析。
/// 解析失败返回 null（worker 回落到 `now()`，本应用宁可给 null，不伪造时间）。
DateTime? parse123OpenTime(String? s) {
  if (s == null) return null;
  final v = s.trim();
  if (v.isEmpty) return null;
  // 带 T 的形态也走同一个解析器（把 T 归一成空格）；只有带显式时区偏移
  // 的 ISO 串才交给 DateTime.parse 自己处理。
  final normalized = v.contains(' ') || !v.contains('T') ? v : v.replaceFirst('T', ' ');
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ ](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(normalized);
  if (m == null) {
    // 不是已知格式时兜底交给 DateTime.parse（失败给 null）。
    return DateTime.tryParse(v)?.toLocal();
  }
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final d = int.tryParse(m.group(3)!);
  final h = int.tryParse(m.group(4)!);
  final mi = int.tryParse(m.group(5)!);
  final sec = int.tryParse(m.group(6)!);
  if (y == null || mo == null || d == null || h == null || mi == null || sec == null) {
    return null;
  }
  final utc = DateTime.utc(y, mo, d, h, mi, sec);
  final zone = m.group(7);
  if (zone == null) {
    // 无时区信息：上游语义是 UTC+8 墙钟时间。
    return utc.subtract(const Duration(hours: 8)).toLocal();
  }
  // 带时区：交给 DateTime.parse 处理偏移。
  return DateTime.tryParse(v)?.toLocal() ?? utc.toLocal();
}

/// 驱动自描述（99 §7.2.10）：类型、显示名、能力遮罩、表单参数、构造
/// 全部收在本文件；`driver_registry.dart` 加一行即接入账号表单。
class Driver123OpenSpec extends CloudDriverSpec {
  const Driver123OpenSpec();

  /// 与 OpenList 驱动目录名一致（文件名带下划线前缀只是 Dart 标识符限制）。
  @override
  String get typeId => '123_open';

  @override
  String get displayName => '123 云盘开放平台';

  /// 列出 / 读取 / 创建文件夹 / 移动 / 删除。
  /// **没有 copy**：worker `copy()` 抛 not supported，Go 版依赖上传秒传
  /// （上传已砍，99 §7.2.1）。write 一律不给。
  @override
  int get capabilities => AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.delete;

  @override
  List<CloudDriverFormItem> get form => const [
        CloudDriverField(
          key: 'refresh_token',
          label: 'refresh_token',
          hint: '必填；获取方法见 OpenList 官方文档（123_open 驱动页）',
          required: true,
          obscure: true,
        ),
        CloudDriverField(
          key: 'api_url_address',
          label: '在线续期地址',
          hint: '默认用 OpenList 维护的公共服务',
          defaultValue: Driver123OpenClient.defaultRenewApi,
          disabledWhenSwitch: 'local_refresh',
          disabledHint: '已开启本地刷新（在线续期停用），关闭开关后可编辑',
        ),
        CloudDriverSwitchField(
          key: 'local_refresh',
          label: '在本地处理令牌刷新',
          subtitle: '关闭＝在线续期；开启＝用自建 123 应用刷新（需 Client ID / Secret），在线续期停用',
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
        CloudDriverField(
          key: 'root_folder_id',
          label: '根目录 ID',
          hint: '不透明 id，默认 0（网盘根目录）；与账号的远程路径叠加生效',
          defaultValue: Driver123OpenClient.defaultRoot,
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    return Driver123Open(
      addition: Driver123OpenAddition.fromJson(config),
      onTokenUpdate: onTokenUpdate,
    );
  }
}
