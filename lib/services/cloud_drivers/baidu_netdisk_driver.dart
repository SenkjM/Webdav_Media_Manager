import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../cloud_driver.dart';

/// 百度网盘驱动（99 §7.3 首个端到端）。
///
/// 移植自 localdev/OpenList-Worker/src/backend/drivers/baidu_netdisk
/// （driver.ts + util.ts，Go 版语义兜底）。按用户决策砍掉：
/// - crack 下载 API（`download_api` / `custom_crack_ua` / getCrackLink / getCrackVideoLink），只走官方 dlink；
/// - 全部上传字段与逻辑（上传已砍，99 §7.2.1）；
/// - `order_by` / `order_direction` / `only_list_video_file` 不暴露（客户端自己排序 / 分类）。
///
/// 与 worker 的两处有意差异：
/// - [BaiduNetdiskDriver.get] 拿不到直链时**抛出真实原因**（风控 / 无权限），
///   worker 只记 warning 返回无直链条目——客户端里下游必然失败，不如直说；
/// - 表单开关「在本地处理令牌刷新」对应 [BaiduAddition.localRefresh]：开启后
///   走自建百度应用的 OAuth 刷新（client_id + client_secret），关闭走续期地址
///   （默认 OpenList 公共服务）。后端每次刷新都会检查该开关。
class BaiduAddition {
  BaiduAddition({
    required this.refreshToken,
    this.clientId = '',
    this.clientSecret = '',
    this.apiUrlAddress = BaiduClient.defaultRenewApi,
    this.localRefresh = false,
    this.accessToken = '',
  });

  factory BaiduAddition.fromJson(Map<String, dynamic> json) => BaiduAddition(
        refreshToken: json['refresh_token'] as String? ?? '',
        clientId: json['client_id'] as String? ?? '',
        clientSecret: json['client_secret'] as String? ?? '',
        apiUrlAddress: json['api_url_address'] as String? ?? '',
        localRefresh: json['local_refresh'] as bool? ?? false,
        accessToken: json['access_token'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
        'api_url_address': apiUrlAddress,
        'local_refresh': localRefresh,
        'access_token': accessToken,
      };

  /// 刷新令牌（必填）。在线续期会轮换它，轮换结果经 onTokenUpdate 持久化。
  String refreshToken;

  /// 自建百度应用的 ClientID / ClientSecret（仅本地刷新时需要）。
  String clientId;
  String clientSecret;

  /// 在线续期地址；空串回落到 [BaiduClient.defaultRenewApi]。
  String apiUrlAddress;

  /// 「在本地处理令牌刷新」开关：true = 自建应用 OAuth 刷新；false = 在线续期。
  bool localRefresh;

  /// access_token 缓存（自动持久化，不进表单、不进备份明文）。
  String accessToken;
}

class BaiduFile {
  int fsId = 0;
  String path = '';
  String serverFilename = '';
  int size = 0;
  int isdir = 0;
  int serverMtime = 0;

  static BaiduFile fromMap(Map<String, dynamic> m) => BaiduFile()
    ..fsId = (m['fs_id'] as num?)?.toInt() ?? 0
    ..path = m['path'] as String? ?? ''
    ..serverFilename = m['server_filename'] as String? ?? ''
    ..size = (m['size'] as num?)?.toInt() ?? 0
    ..isdir = (m['isdir'] as num?)?.toInt() ?? 0
    ..serverMtime = (m['server_mtime'] as num?)?.toInt() ?? 0;
}

class BaiduClient {
  static const oauthApi = 'https://openapi.baidu.com/oauth/2.0/token';
  static const panApi = 'https://pan.baidu.com/rest/2.0';
  static const defaultRenewApi = 'https://api.oplist.org/baiduyun/renewapi';

  /// 普通 API 的 UA，对齐 Go 版（drivers/base/client.go UserAgentNT）。
  static const apiUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/142.0.0.0 OpenList/425.6.30';

  /// 下载直链必需的 UA（worker getOfficialLink 证实）。
  static const downloadUA = 'pan.baidu.com';

  /// access_token 无效 / 过期的错误码（worker 实测：111 文档标准、-6 与 20016 实测）。
  static const Set<int> tokenErrors = {111, -6, 20016};

  static const retryCount = 3;
  static const retryWaitMs = 1000;

  BaiduClient(this.addition, {this.onTokenUpdate})
      : accessToken = addition.accessToken,
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
            headers: {'User-Agent': apiUA, 'Accept': 'application/json'},
            // 非 2xx 也回来走 errno / 原文解析：「原样传递报错」需要读到 body。
            validateStatus: (_) => true,
          ),
        );

  BaiduAddition addition;
  String accessToken;
  final void Function({required String accessToken, required String refreshToken})?
      onTokenUpdate;
  final Dio _dio;

  Future<void> login() async {
    if (accessToken.isEmpty) await refreshToken();
  }

  /// 刷新令牌。每次都会检查 [BaiduAddition.localRefresh]：
  /// false → 续期地址（默认 OpenList 公共服务）；true → 自建应用 OAuth。
  Future<void> refreshToken() async {
    final a = addition;
    if (!a.localRefresh) {
      final u = a.apiUrlAddress.trim().isNotEmpty
          ? a.apiUrlAddress.trim()
          : defaultRenewApi;
      final res = await _dio.get<String>(
        u,
        queryParameters: {
          'refresh_ui': a.refreshToken,
          'server_use': 'true',
          'driver_txt': 'baiduyun_go',
        },
        options: Options(responseType: ResponseType.plain),
      );
      final raw = res.data ?? '';
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      if (data == null) {
        throw CloudDriverException(
          '在线 API 刷新失败 (HTTP ${res.statusCode})：${raw.length > 300 ? raw.substring(0, 300) : (raw.isEmpty ? '非 JSON 响应' : raw)}。'
          '请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。',
        );
      }
      if (data['refresh_token'] == null || data['access_token'] == null) {
        throw CloudDriverException(
          (data['text'] as String?) ??
              (res.statusCode != 200
                  ? '在线 API 返回 HTTP ${res.statusCode}'
                  : 'empty token returned from official API, a wrong refresh token may have been used'),
        );
      }
      _applyTokens(data['access_token'] as String, data['refresh_token'] as String);
      return;
    }

    // 本地刷新：自建百度应用的 OAuth refresh。
    if (a.clientId.isEmpty || a.clientSecret.isEmpty) {
      throw CloudDriverException('empty ClientID or ClientSecret');
    }
    final res = await _dio.get<dynamic>(
      oauthApi,
      queryParameters: {
        'grant_type': 'refresh_token',
        'refresh_token': a.refreshToken,
        'client_id': a.clientId,
        'client_secret': a.clientSecret,
      },
    );
    final data = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    if (data['error'] != null) {
      throw CloudDriverException('${data['error']}: ${data['error_description'] ?? ''}');
    }
    if (data['refresh_token'] == null) {
      throw CloudDriverException('empty refresh token returned from OAuth');
    }
    _applyTokens(
      (data['access_token'] as String?) ?? '',
      data['refresh_token'] as String,
    );
  }

  void _applyTokens(String access, String refresh) {
    accessToken = access;
    addition.accessToken = access;
    addition.refreshToken = refresh;
    onTokenUpdate?.call(accessToken: access, refreshToken: refresh);
  }

  /// pan.baidu.com API 请求：带 token、errno 解析、令牌错误自动刷新、
  /// 3 次退避重试（1s / 2s），对齐 worker 的 request()。
  Future<Map<String, dynamic>> request(
    String pathname, {
    String method = 'GET',
    Map<String, String>? params,
    Map<String, String>? form,
  }) async {
    if (accessToken.isEmpty) await refreshToken();

    Object? lastErr;
    for (var attempt = 0; attempt < retryCount; attempt++) {
      try {
        return await _doRequest(pathname, method: method, params: params, form: form);
      } on CloudDriverException {
        rethrow; // 业务错误（errno / 风控 / 非 JSON）不重试
      } catch (e) {
        lastErr = e;
        if (attempt < retryCount - 1) {
          await Future<void>.delayed(
              Duration(milliseconds: retryWaitMs << attempt));
        }
      }
    }
    throw CloudDriverException('百度网盘请求失败', lastErr);
  }

  Future<Map<String, dynamic>> _doRequest(
    String pathname, {
    required String method,
    Map<String, String>? params,
    Map<String, String>? form,
  }) async {
    final query = <String, String>{'access_token': accessToken, ...?params};
    final Response<String> res;
    if (method == 'POST') {
      res = await _dio.post<String>(
        '$panApi$pathname',
        queryParameters: query,
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
    } else {
      res = await _dio.get<String>(
        '$panApi$pathname',
        queryParameters: query,
        options: Options(responseType: ResponseType.plain),
      );
    }
    final text = res.data ?? '';
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(text);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      throw CloudDriverException(
        'req: [$pathname] invalid JSON response, status ${res.statusCode}',
      );
    }
    final errno = (body['errno'] as num?)?.toInt() ?? 0;
    if (errno != 0) {
      if (tokenErrors.contains(errno)) {
        // Go：先刷新令牌，外层重试再跑一次。
        await refreshToken();
      }
      final base =
          'req: [$pathname] ,errno: $errno, refer to https://pan.baidu.com/union/doc/';
      if (errno == 31023) {
        throw CloudDriverException(
          '$base 百度网盘风控（触发安全策略，通常数分钟至数小时后自动解除）。'
          'refresh_token 无效或非官方渠道获取也可能触发；请确认通过 https://api.oplist.org/ 获取。',
        );
      }
      throw CloudDriverException(base);
    }
    return body;
  }

  /// 列目录（/xpan/file method=list），1000 一页翻完。
  Future<List<BaiduFile>> getFiles(String dir) async {
    final out = <BaiduFile>[];
    const limit = 1000;
    for (var start = 0;; start += limit) {
      final body = await request('/xpan/file', params: {
        'method': 'list',
        'dir': dir,
        'web': 'web',
        'start': '$start',
        'limit': '$limit',
      });
      final list = body['list'];
      if (list is! List || list.isEmpty) break;
      out.addAll([
        for (final e in list)
          if (e is Map<String, dynamic>) BaiduFile.fromMap(e),
      ]);
      if (list.length < limit) break;
    }
    return out;
  }

  /// 官方直链：filemetas 拿 dlink → HEAD 跟 302 → sanitize（去掉 access_token）。
  Future<({String url, Map<String, String> headers})> getOfficialLink(
    int fsId,
  ) async {
    final body = await request('/xpan/multimedia', params: {
      'method': 'filemetas',
      'fsids': '[$fsId]',
      'dlink': '1',
    });
    final list = body['list'];
    final dlink = (list is List && list.isNotEmpty)
        ? ((list.first as Map<String, dynamic>)['dlink'] as String?)
        : null;
    if (dlink == null || dlink.isEmpty) {
      throw CloudDriverException('no dlink returned from filemetas');
    }
    final u = '$dlink&access_token=$accessToken';
    final head = await _dio.head(
      u,
      options: Options(
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {'User-Agent': downloadUA},
      ),
    );
    final location = head.headers.value('location') ?? u;
    return (
      url: _sanitizeDlink(location),
      headers: {'User-Agent': downloadUA},
    );
  }

  String _sanitizeDlink(String dlink) {
    if (dlink.isEmpty) return dlink;
    try {
      final uri = Uri.parse(dlink);
      final params = Map<String, String>.from(uri.queryParameters)
        ..remove('access_token');
      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return dlink;
    }
  }

  /// filemanager（rename / move / copy / delete 共用）。
  Future<void> manage(String opera, List<Object?> filelist) async {
    await request(
      '/xpan/file',
      method: 'POST',
      params: {'method': 'filemanager', 'opera': opera},
      form: {
        'async': '0',
        'filelist': jsonEncode(filelist),
        'ondup': 'fail',
      },
    );
  }

  /// create（mkdir 用 isdir=1；上传相关参数一并不移植）。
  Future<void> createDir(String path) async {
    await request(
      '/xpan/file',
      method: 'POST',
      params: {'method': 'create'},
      form: {'path': path, 'size': '0', 'isdir': '1', 'rtype': '3'},
    );
  }

  /// uinfo：校验令牌（无效 / 风控在此抛出）。
  Future<int> uinfo() async {
    final body = await request('/xpan/nas', params: {'method': 'uinfo'});
    return (body['vip_type'] as num?)?.toInt() ?? 0;
  }
}

/// 百度网盘 CloudDriver 实现。
class BaiduNetdiskDriver implements CloudDriver {
  BaiduNetdiskDriver({
    required BaiduAddition addition,
    void Function({required String accessToken, required String refreshToken})?
        onTokenUpdate,
  }) : _client = BaiduClient(addition, onTokenUpdate: onTokenUpdate);

  final BaiduClient _client;

  @override
  Future<void> init() async {
    // login：无缓存 access_token 就刷新一次；uinfo 校验令牌是否真的可用。
    await _client.login();
    await _client.uinfo();
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final files = await _client.getFiles(_baiduPath(path));
    return [for (final f in files) _toItem(f)];
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final bp = _baiduPath(path);
    if (bp == '/') {
      return const CloudFileItem(name: '/', isDir: true);
    }
    // 百度没有按路径查单文件的 API：列父目录找到目标（对齐 worker）。
    final parent = cloudDirname(bp);
    final rawName = cloudBasename(bp);
    final decoded = _tryDecode(rawName);
    final files = await _client.getFiles(parent);
    BaiduFile? file;
    for (final f in files) {
      if (f.serverFilename == rawName ||
          f.serverFilename == decoded ||
          f.path == bp ||
          f.fsId.toString() == rawName) {
        file = f;
        break;
      }
    }
    if (file == null) {
      throw CloudDriverException('file not found: $rawName');
    }
    final item = _toItem(file);
    if (!item.isDir) {
      try {
        final link = await _client.getOfficialLink(file.fsId);
        return CloudFileItem(
          name: item.name,
          isDir: false,
          size: item.size,
          modified: item.modified,
          rawUrl: link.url,
          rawHeaders: link.headers,
        );
      } on CloudDriverException {
        rethrow;
      } catch (e) {
        throw CloudDriverException('获取下载直链失败：$e');
      }
    }
    return item;
  }

  @override
  Future<void> mkdir(String path) async {
    await _client.createDir(_baiduPath(path));
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final bp = _baiduPath(path);
    final dst = _baiduPath(newPath);
    if (cloudDirname(bp) == cloudDirname(dst)) {
      await _client.manage('rename', [
        {'path': bp, 'newname': cloudBasename(dst)},
      ]);
    } else {
      await _client.manage('move', [
        {
          'path': bp,
          'dest': cloudDirname(dst),
          'newname': cloudBasename(dst),
        },
      ]);
    }
  }

  @override
  Future<void> remove(String path) async {
    await _client.manage('delete', [_baiduPath(path)]);
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    await _client.manage('move', [
      {
        'path': _baiduPath(srcPath),
        'dest': _baiduPath(dstDir),
        'newname': newName,
      },
    ]);
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    await _client.manage('copy', [
      {
        'path': _baiduPath(srcPath),
        'dest': _baiduPath(dstDir),
        'newname': newName,
      },
    ]);
  }

  String _baiduPath(String p) {
    final clean = '/${p.replaceAll(RegExp(r'/+'), '/')}';
    if (clean == '/') return '/';
    return clean.replaceAll(RegExp(r'/$'), '');
  }

  CloudFileItem _toItem(BaiduFile f) {
    final name = f.serverFilename.isNotEmpty
        ? f.serverFilename
        : cloudBasename(f.path);
    final isDir = f.isdir == 1;
    return CloudFileItem(
      name: name,
      isDir: isDir,
      size: f.size,
      modified: f.serverMtime > 0
          ? DateTime.fromMillisecondsSinceEpoch(f.serverMtime * 1000)
          : null,
    );
  }

  String _tryDecode(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }
}
