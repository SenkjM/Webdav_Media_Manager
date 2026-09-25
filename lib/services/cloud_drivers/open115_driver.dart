/// 115 网盘开放平台驱动（OpenList `115open` 移植）。
///
/// 移植自 `localdev/OpenList-Worker/src/backend/drivers/115open`
/// （driver.ts + util.ts + types.ts，移植底稿）与
/// `localdev/OpenList/drivers/115_open`（Go 版，语义兜底）。
///
/// **两套基址**（上游 util.ts）：
/// - 文件 API `https://proapi.115.com`；
/// - 认证 `https://passportapi.115.com`（`/open/refreshToken`）。
///
/// **响应包裹**：`{state: bool, code: number, message: string, data: T}`。
/// 鉴权失败 = `state === false` 且 code 为 `99` 或以 `401` 开头（SDK 的
/// `Is401Started`）→ 刷新令牌后**重试一次**（`skipAuthRetry` 防死循环）；
/// `code === 430004` 是「对象不存在」（[open115ErrObjectNotFound]）。
/// 报错一律带上游的 `code` 与 `message` 原文。
///
/// **按用户决策砍掉**：
/// - **全部上传**（99 §4.2.1）：上游 `put()` 的秒传 / 二次校验 / OSS 直传 /
///   HMAC-SHA1 签名全不移植，`sha1` 等 crypto 依赖因此也不需要；
/// - `order_by` / `order_direction` 不进表单（客户端自己排序），请求固定
///   `o=file_name` + `asc=1`；
/// - `root_folder_id` 兼容别名（worker `normalizePan115Addition` 的兼容层）；
/// - **worker 的 `SUBREQUEST_LIMIT=45` 子请求预算**：那是 Cloudflare Workers
///   的运行时限制，本应用没有该约束，不移植。
///
/// **与 worker 的一处有意差异**：[Open115Driver.get] 拿不到直链时**抛出真实
/// 原因**（含 406 配额用尽），worker 只记 warning 返回无直链条目——客户端里
/// 下游必然失败，不如直说（[CloudDriver.get] 契约，同百度 / 网易云驱动）。
///
/// **`limit_rate`**：Go `meta.go` 默认 1（次/秒）。本实现做成「请求间隔节流」，
/// 并把默认值放到表单文本字段里（`'0'` = 不限速），因为固定 1 次/秒会让浏览
/// 与播放首帧明显变慢。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/account_capabilities.dart';
import '../cloud_driver.dart';

/// 上游 SDK 错误码：对象不存在（`ERR_OBJECT_NOT_FOUND`，util.ts）。
const int open115ErrObjectNotFound = 430004;

/// 上游 SDK 错误码：参数错误（`folder/get_info` 传目录以外的路径会返回它，
/// 也是「该端点只支持目录路径」的判定依据，driver.ts 的 resolveFolderId）。
const int open115ErrInvalidParams = 990002;

/// 令牌失效判定（SDK `Is401Started`）：`99`，或以 `401` 开头的整数码。
bool open115IsAuthError(Object? code) {
  if (code is num) {
    if (code == 99) return true;
    return code.toInt().toString().startsWith('401');
  }
  final s = '$code'.trim();
  if (s.isEmpty) return false;
  return s == '99' || s.startsWith('401');
}

/// 驱动配置（对齐上游 Addition；默认值照抄 Go `meta.go`）。
class Open115Addition {
  Open115Addition({
    required this.refreshToken,
    this.rootId = '0',
    this.pageSize = 200,
    this.limitRate = 0,
    this.accessToken = '',
  });

  factory Open115Addition.fromJson(Map<String, dynamic> json) =>
      Open115Addition(
        refreshToken: json['refresh_token'] as String? ?? '',
        // 表单里 root_id / page_size / limit_rate 都是文本字段，兼容数字型配置。
        rootId: _asText(json['root_id'], '0'),
        pageSize: _asInt(json['page_size'], 200),
        limitRate: _asRate(json['limit_rate'], 0),
        accessToken: json['access_token'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
        'root_id': rootId,
        'page_size': pageSize,
        'limit_rate': limitRate,
        'access_token': accessToken,
      };

  /// 刷新令牌（必填）。115 每次刷新都会轮换它，轮换结果经 `onTokenUpdate`
  /// 持久化（两个 token 都必须存）。
  String refreshToken;

  /// 根文件夹 ID，默认 `'0'`（整体根目录）。
  String rootId;

  /// 列表分页大小；`init()` 里夹进 1..1150（Go Init 的限制）。
  int pageSize;

  /// 所有 API 请求限速（次/秒）；`<= 0` 不限速。
  double limitRate;

  /// access_token 缓存（自动持久化，不进表单）。
  String accessToken;

  static String _asText(Object? raw, String fallback) {
    if (raw == null) return fallback;
    final s = '$raw'.trim();
    return s.isEmpty ? fallback : s;
  }

  static int _asInt(Object? raw, int fallback) {
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}'.trim()) ?? fallback;
  }

  static double _asRate(Object? raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}'.trim()) ?? fallback;
  }
}

/// 115 列表条目（上游 `Pan115File` 的字段子集 + 直链所需的 `pc`）。
class Open115File {
  Open115File({
    required this.fid,
    required this.pid,
    required this.fc,
    required this.fn,
    required this.pc,
    required this.upt,
    required this.fs,
  });

  static Open115File fromMap(Map<String, dynamic> m) => Open115File(
        fid: _text(m['fid']),
        pid: _text(m['pid']),
        // fc 是**字符串**：'0' = 目录，'1' = 文件（Go `IsDir: o.Fc == "0"`）。
        fc: _text(m['fc']),
        fn: m['fn'] as String? ?? '',
        pc: _text(m['pc']),
        upt: _num(m['upt']),
        fs: _num(m['fs']),
      );

  /// 文件 ID。
  final String fid;

  /// 父文件夹 ID。
  final String pid;

  /// 文件分类：`'0'` 目录，`'1'` 文件（字符串）。
  final String fc;

  /// 文件名。
  final String fn;

  /// 提取码（`pick_code`）：**只有列表接口才返回**，downurl 需要它。
  final String pc;

  /// 修改时间（Unix 秒）。
  final int upt;

  /// 文件大小（字节）。
  final int fs;

  bool get isDir => fc == '0';

  static String _text(Object? v) => v == null ? '' : '$v';

  static int _num(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }
}

/// 115 开放平台 API 客户端（上游 `Pan115Client`）。
class Open115Client {
  Open115Client(
    this.addition, {
    this.onTokenUpdate,
    Dio? dio,
    Duration? linkTtl,
  })  : linkTtl = linkTtl ?? defaultLinkTtl,
        accessToken = addition.accessToken,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'User-Agent': open115UserAgent, 'Accept': 'application/json'},
                // 非 2xx 也回来读 body：「原样传递报错」需要读到 115 的 code。
                validateStatus: (_) => true,
              ),
            ) {
    _rateLimitMs = addition.limitRate > 0 ? (1000 / addition.limitRate).round() : 0;
    _rateClock.start();
  }

  /// 文件 API 基址。
  static const String apiBase = 'https://proapi.115.com';

  /// 认证基址（令牌刷新在这里，不在 proapi）。
  static const String authBase = 'https://passportapi.115.com';

  /// 令牌刷新端点。
  static const String refreshTokenUrl = '$authBase/open/refreshToken';

  /// 115 有防盗链校验，API 与直链都用这个 UA（上游 `OPENLIST_UA`，
  /// 对齐 Go `base.UserAgent`；worker 在 request() 与 raw_url_headers 里
  /// 用的是同一个字符串）。
  static const String open115UserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/142.0.0.0 OpenList/425.6.30';

  /// 直链缓存 TTL 的默认值（Go `LinkCacheMode = LinkCacheUA` 的等价物）。
  /// 115 免费用户 downurl 有每日配额（配额用尽返回 406），缓存显著省调用。
  static const Duration defaultLinkTtl = Duration(minutes: 30);

  /// 本实例的直链缓存 TTL（测试可注入更短的值）。
  final Duration linkTtl;

  /// 网络层重试次数（上游 `fetchWithRetry` 是 3 次，退避 0.5s / 1s）。
  static const int networkRetries = 3;

  static const int _retryBaseMs = 500;

  final Open115Addition addition;
  String accessToken;
  final void Function(Map<String, dynamic> patch)? onTokenUpdate;
  final Dio _dio;

  /// 请求间隔节流（Go `rate.NewLimiter(limit, 1)` / worker `waitRateLimit`）。
  /// 用 `Stopwatch` 计时，避免 `DateTime.now()` 的时钟跳变影响节流。
  final Stopwatch _rateClock = Stopwatch();
  int _rateLimitMs = 0;
  int _lastRequestMs = 0;

  /// 下载链接缓存：key = `fid|UA`（Go `LinkCacheMode=UA`）。
  final Map<String, _Open115LinkEntry> _linkCache = {};

  String get refreshTokenValue => addition.refreshToken;

  /// 解析后的根目录 ID（空 → `'0'`）。
  String get rootId {
    final r = addition.rootId.trim();
    return r.isEmpty ? '0' : r;
  }

  Future<void> login() async {
    if (accessToken.isEmpty) await refreshToken();
  }

  /// 刷新令牌（`POST https://passportapi.115.com/open/refreshToken`）。
  ///
  /// **form-urlencoded，不是 JSON**；两个 token 都要存——115 每次刷新都会
  /// 轮换 refresh_token，不存下去下次就刷不动了。
  Future<void> refreshToken() async {
    if (refreshTokenValue.isEmpty) {
      throw const CloudDriverException('115 网盘缺少 refresh_token（必填）');
    }
    final res = await _send(
      refreshTokenUrl,
      method: 'POST',
      form: {'refresh_token': refreshTokenValue},
      // 刷新请求本身不带 Bearer（access_token 正是在换它）。
      withAuth: false,
    );
    final body = _decodeBody(res);
    final data = body['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    // 两个 token 都按文本取（上游只判空，不假设类型）。
    final access = _asToken(map['access_token']);
    final refresh = _asToken(map['refresh_token']);
    if (body['code'] != 0 || access.isEmpty || refresh.isEmpty) {
      throw CloudDriverException(
        '115 网盘 token 刷新失败（code ${body['code']} ${body['message'] ?? ''}）：'
        '请确认 refresh_token 有效。',
      );
    }
    _applyTokens(access, refresh);
  }

  static String _asToken(Object? v) => v == null ? '' : '$v'.trim();

  void _applyTokens(String access, String refresh) {
    accessToken = access;
    addition.accessToken = access;
    addition.refreshToken = refresh;
    onTokenUpdate?.call(<String, dynamic>{
      'access_token': access,
      'refresh_token': refresh,
    });
  }

  /// 鉴权请求（对应 SDK `authRequest`）。
  ///
  /// [method] 只区分 GET / POST；[query] 空串会被跳过（上游语义）。
  /// 失败时：鉴权错误 → 刷新令牌后重试**一次**（`skipAuthRetry` 防死循环）；
  /// 其余错误把它们包成带 `code` 的 [_Open115ApiException]。
  Future<Map<String, dynamic>> request(
    String url, {
    String method = 'GET',
    Map<String, String>? query,
    Map<String, String>? form,
    String? ua,
    bool skipAuthRetry = false,
  }) async {
    var body = await _doRequest(url,
        method: method, query: query, form: form, ua: ua);
    final state = body['state'];
    if (state != false) return body;

    final code = body['code'];
    if (open115IsAuthError(code) && !skipAuthRetry) {
      // 令牌失效：刷新一次再打一遍，且这一次不再刷新（防死循环）。
      await refreshToken();
      body = await _doRequest(url,
          method: method, query: query, form: form, ua: ua);
      if (body['state'] != false) return body;
      throw _apiException(url, body);
    }
    throw _apiException(url, body);
  }

  _Open115ApiException _apiException(String url, Map<String, dynamic> body) {
    final code = body['code'];
    // 上游错误原文：code 与 message 一起带上（430004 由调用方按 code 判定）。
    return _Open115ApiException(
      '115 网盘 API 错误（code $code ${body['message'] ?? ''}）',
      code: code,
      url: url,
    );
  }

  Future<Map<String, dynamic>> _doRequest(
    String url, {
    required String method,
    Map<String, String>? query,
    Map<String, String>? form,
    String? ua,
  }) async {
    final res = await _send(
      url,
      method: method,
      query: query,
      form: form,
      ua: ua,
      withAuth: true,
    );
    return _decodeBody(res);
  }

  /// 单次出网：限速 → 20s 超时 → 网络层重试 3 次（0.5s / 1s 退避）。
  Future<Response<String>> _send(
    String url, {
    required String method,
    Map<String, String>? query,
    Map<String, String>? form,
    String? ua,
    required bool withAuth,
  }) async {
    await _waitRateLimit();

    final headers = <String, String>{'User-Agent': ua ?? open115UserAgent};
    if (withAuth && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    // 空值跳过（上游 `if (v !== "")`）。
    final qp = <String, dynamic>{
      ...?query?.map((k, v) => MapEntry(k, v)),
    }..removeWhere((_, v) => v == '');
    final formData = form == null
        ? null
        : (Map<String, String>.from(form)..removeWhere((_, v) => v.isEmpty));

    Object? lastErr;
    for (var attempt = 0; attempt < networkRetries; attempt++) {
      try {
        return await _dio.request<String>(
          url,
          queryParameters: qp.isEmpty ? null : qp,
          data: formData,
          options: Options(
            method: method,
            responseType: ResponseType.plain,
            contentType:
                formData == null ? null : Headers.formUrlEncodedContentType,
            headers: headers,
          ),
        );
      } on DioException catch (e) {
        lastErr = e;
        if (attempt < networkRetries - 1) {
          await Future<void>.delayed(
              Duration(milliseconds: _retryBaseMs * (attempt + 1)));
        }
      }
    }
    throw CloudDriverException('115 网盘网络请求失败（$url）', lastErr);
  }

  Future<void> _waitRateLimit() async {
    if (_rateLimitMs <= 0) return;
    final now = _rateClock.elapsedMilliseconds;
    final wait = _lastRequestMs + _rateLimitMs - now;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    _lastRequestMs = _rateClock.elapsedMilliseconds;
  }

  /// 解析响应包裹；非 JSON 时按上游做法合成一个 `state:false` 的 body。
  Map<String, dynamic> _decodeBody(Response<String> res) {
    final text = res.data ?? '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 落到下面的合成分支。
    }
    return <String, dynamic>{
      'state': false,
      'code': res.statusCode,
      'message': text.length > 200 ? text.substring(0, 200) : text,
    };
  }

  // ---- 用户 ----

  /// `GET /open/user/info`：校验令牌（无效 / 网络不通都在这里暴露）。
  Future<Map<String, dynamic>> userInfo() async {
    final body = await request('$apiBase/open/user/info');
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  // ---- 文件 ----

  /// `GET /open/ufile/files`：列目录。返回 `(files, count)`，count 是当前
  /// 目录的条目总数（分页推进靠它）。
  Future<({List<Open115File> files, int count})> getFiles({
    required String cid,
    required int limit,
    required int offset,
    bool asc = true,
    String o = 'file_name',
    bool showDir = true,
  }) async {
    final body = await request('$apiBase/open/ufile/files', query: {
      'cid': cid,
      'limit': '$limit',
      'offset': '$offset',
      'asc': asc ? '1' : '0',
      'o': o,
      'showDir': showDir ? '1' : '0',
    });
    final data = body['data'];
    final files = <Open115File>[];
    if (data is List) {
      for (final e in data) {
        if (e is Map<String, dynamic>) files.add(Open115File.fromMap(e));
      }
    }
    final count = body['count'];
    return (
      files: files,
      count: count is num ? count.toInt() : (int.tryParse('${count ?? ''}') ?? 0),
    );
  }

  /// `GET /open/folder/get_info`（按 file_id 或 path，**只支持目录**）。
  Future<Map<String, dynamic>> getFolderInfo({
    String? fileId,
    String? path,
  }) async {
    final body = await request(
      '$apiBase/open/folder/get_info',
      method: path == null ? 'GET' : 'POST',
      query: path == null ? {'file_id': fileId ?? ''} : null,
      form: path == null ? null : {'path': path},
    );
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// `POST /open/ufile/downurl`：按 `pick_code` 取直链。
  ///
  /// 响应形状是 `{ [fid]: { url: { url: '...' }, ... } }`，按 fid 取。
  /// **带 UA**（115 防盗链）：同一个 UA 也进 `rawHeaders`。
  Future<String> downUrl(String pickCode, {String? ua}) async {
    final body = await request(
      '$apiBase/open/ufile/downurl',
      method: 'POST',
      form: {'pick_code': pickCode},
      ua: ua,
    );
    final data = body['data'];
    if (data is! Map) {
      throw const CloudDriverException('115 网盘 downurl 未返回直链数据（data 为空）');
    }
    for (final entry in data.values) {
      if (entry is! Map) continue;
      final url = entry['url'];
      final link = url is Map ? url['url'] as String? : null;
      if (link != null && link.isNotEmpty) return link;
    }
    throw const CloudDriverException('115 网盘 downurl 未返回可用直链（url.url 为空）');
  }

  /// 直链缓存查询（key = `fid|UA`）。过期返回 null。
  String? cachedLink(String fid, String ua) {
    final hit = _linkCache['$fid|$ua'];
    if (hit == null) return null;
    if (hit.expire.isBefore(DateTime.now())) {
      _linkCache.remove('$fid|$ua');
      return null;
    }
    return hit.url;
  }

  void cacheLink(String fid, String ua, String url) {
    _linkCache['$fid|$ua'] = _Open115LinkEntry(
      url: url,
      expire: DateTime.now().add(linkTtl),
    );
  }

  /// 取直链（带缓存）。缓存命中不发出任何请求。
  Future<String> linkFor(Open115File file, {String ua = open115UserAgent}) async {
    final cached = cachedLink(file.fid, ua);
    if (cached != null) return cached;
    if (file.pc.isEmpty) {
      throw CloudDriverException('115 网盘条目缺少 pick_code，无法获取直链：${file.fn}');
    }
    final url = await downUrl(file.pc, ua: ua);
    cacheLink(file.fid, ua, url);
    return url;
  }

  // ---- 写操作 ----

  /// `POST /open/folder/add`。
  Future<void> mkdir(String pid, String fileName) async {
    await request('$apiBase/open/folder/add',
        method: 'POST', form: {'pid': pid, 'file_name': fileName});
  }

  /// `POST /open/ufile/update`（改名）。
  Future<void> updateFile(String fileId, String fileName) async {
    await request('$apiBase/open/ufile/update',
        method: 'POST', form: {'file_id': fileId, 'file_name': fileName});
  }

  /// `POST /open/ufile/move`。[fileIds] 上游是逗号分隔的字符串。
  Future<void> move(String fileIds, String toCid) async {
    await request('$apiBase/open/ufile/move',
        method: 'POST', form: {'file_ids': fileIds, 'to_cid': toCid});
  }

  /// `POST /open/ufile/copy`。**参数顺序是 (目标 pid, 源 fileId)**，
  /// 与直觉相反——上游 `copy(srcObj, dstDir)` 里 `PID = dstDir.GetID()`。
  Future<void> copy(String pid, String fileId) async {
    await request('$apiBase/open/ufile/copy',
        method: 'POST', form: {'pid': pid, 'file_id': fileId, 'no_dupli': '1'});
  }

  /// `POST /open/ufile/delete`。[fileIds] 上游是逗号分隔的字符串。
  Future<void> delFile(String fileIds, String parentId) async {
    await request('$apiBase/open/ufile/delete',
        method: 'POST', form: {'file_ids': fileIds, 'parent_id': parentId});
  }
}

class _Open115LinkEntry {
  _Open115LinkEntry({required this.url, required this.expire});

  final String url;
  final DateTime expire;
}

/// 带上游 `code` 的 API 异常：调用方靠 [code] 区分 430004 / 990002 等语义。
class _Open115ApiException extends CloudDriverException {
  const _Open115ApiException(
    super.message, {
    required this.code,
    required this.url,
  });

  final Object? code;
  final String url;

  bool get isObjectNotFound => _codeInt == open115ErrObjectNotFound;

  bool get isInvalidParams => _codeInt == open115ErrInvalidParams;

  int? get _codeInt {
    final c = code;
    if (c is num) return c.toInt();
    return int.tryParse('${c ?? ''}'.trim());
  }
}

/// 115 网盘 CloudDriver 实现。
///
/// 路径形态：本应用给驱动的是**绝对路径**，115 的 API 只认 id，所以在驱动
/// 内维护实例级 `path → id` 缓存（随驱动重建失效，99 §4.6）。缓存 key 是
/// **正斜杠开头的干净路径**（上游 `clean`，与 115 的路径形态一致）。
class Open115Driver extends CloudDriver {
  Open115Driver({
    required Open115Addition addition,
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    Dio? dio,
  }) : _client = Open115Client(addition, onTokenUpdate: onTokenUpdate, dio: dio);

  factory Open115Driver.fromConfig(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    Dio? dio,
  }) =>
      Open115Driver(
        addition: Open115Addition.fromJson(config),
        onTokenUpdate: onTokenUpdate,
        dio: dio,
      );

  final Open115Client _client;

  /// 测试用：直接拿客户端。
  Open115Client get client => _client;

  /// 路径 → fid 缓存。
  final Map<String, String> _fidCache = <String, String>{};

  int _pageSize = 200;

  @override
  Future<void> init() async {
    final a = _client.addition;
    // page_size 夹进 1..1150（Go Init：`<=0 → 200`，`>1150 → 1150`）。
    final raw = a.pageSize;
    _pageSize = raw <= 0 ? 200 : (raw > 1150 ? 1150 : raw);
    a.pageSize = _pageSize;

    // login：无缓存 access_token 先刷新一次。
    await _client.login();

    // 真连校验（上游 `client.UserInfo`）：失败即挂载失败，给明确错误。
    try {
      await _client.userInfo();
    } on _Open115ApiException catch (e) {
      // 对象不存在这类上游错误原样透传。
      if (e.isObjectNotFound) rethrow;
      throw CloudDriverException(
        '115 网盘 token 验证失败：${e.message}。请确认 access_token / refresh_token 有效。',
        e.cause,
      );
    } on CloudDriverException catch (e) {
      final msg = e.message;
      if (e.cause is DioException ||
          msg.contains('网络') ||
          msg.contains('SocketException')) {
        throw CloudDriverException(
          '115 网盘网络连接失败（$msg）：proapi.115.com 可能无法从当前部署环境访问'
          '（数据中心 IP 可能被 115 拦截），请稍后重试或更换部署环境。',
          e.cause,
        );
      }
      throw CloudDriverException(
        '115 网盘 token 验证失败：$msg。请确认 access_token / refresh_token 有效。',
        e.cause,
      );
    }
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final cid = await resolveFolderId(path);
    final items = <CloudFileItem>[];
    var offset = 0;
    for (;;) {
      final page = await _client.getFiles(
        cid: cid,
        limit: _pageSize,
        offset: offset,
        asc: true,
        o: 'file_name',
        showDir: true,
      );
      for (final f in page.files) {
        items.add(_toItem(f));
        // 目录顺手进缓存，后续路径解析少一轮列目录。
        if (f.isDir && f.fn.isNotEmpty) {
          _fidCache[_joinPath(path, f.fn)] = f.fid;
        }
      }
      if (page.files.isEmpty || items.length >= page.count) break;
      offset += page.files.length;
    }
    return items;
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final clean = _clean(path);
    if (clean == '/' || clean == '/${_client.rootId}') {
      // 根路径：目录条目（同 worker 的 get 根分支）。
      return CloudFileItem(name: _client.rootId, isDir: true);
    }
    final file = await resolveFile(path);
    final item = _toItem(file);
    if (item.isDir) return item;
    try {
      final url = await _client.linkFor(file);
      return CloudFileItem(
        name: item.name,
        isDir: false,
        size: item.size,
        modified: item.modified,
        rawUrl: url,
        // 直链必须带 115 的 UA，否则 403（Go Link 的 Header）。
        rawHeaders: const {'User-Agent': Open115Client.open115UserAgent},
      );
    } on CloudDriverException catch (e) {
      // 本项目契约：拿不到直链就抛真实原因，不静默返回无直链条目。
      if (e.message.contains('downurl') || e.message.contains('pick_code')) {
        rethrow;
      }
      throw CloudDriverException('获取 115 网盘直链失败：${e.message}', e.cause);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final clean = _clean(path);
    final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
    final dirName = segs.isNotEmpty ? segs.removeLast() : '新文件夹';
    final parentPath = '/${segs.join('/')}';
    final parentId = await resolveFolderId(parentPath);
    await _client.mkdir(parentId, dirName);
    _fidCache.remove(clean);
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final dst = _clean(newPath);
    final file = await resolveFile(path);
    // 同目录 → update；跨目录 → move 到目标目录再改名（接口契约）。
    if (_clean(cloudDirname(_clean(path))) == _clean(cloudDirname(dst))) {
      await _client.updateFile(file.fid, cloudBasename(dst));
    } else {
      final dstId = await resolveFolderId(cloudDirname(dst));
      await _client.move(file.fid, dstId);
      await _client.updateFile(file.fid, cloudBasename(dst));
    }
    _invalidatePath(_clean(path));
    _invalidatePath(dst);
  }

  @override
  Future<void> remove(String path) async {
    final file = await resolveFile(path);
    // parent_id 取条目的 pid，缺失时退回根（同 worker）。
    final parentId = file.pid.isNotEmpty ? file.pid : _client.rootId;
    await _client.delFile(file.fid, parentId);
    _invalidatePath(_clean(path));
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final file = await resolveFile(srcPath);
    final dstId = await resolveFolderId(dstDir);
    await _client.move(file.fid, dstId);
    final currentName = _decodedName(srcPath);
    if (newName.isNotEmpty && newName != currentName) {
      await _client.updateFile(file.fid, newName);
    }
    _invalidatePath(_clean(srcPath));
    _invalidatePath(_joinPath(dstDir, newName.isEmpty ? currentName : newName));
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final file = await resolveFile(srcPath);
    final dstId = await resolveFolderId(dstDir);
    // 上游参数顺序：copy(目标 pid, 源 fileId)。
    await _client.copy(dstId, file.fid);
    final currentName = _decodedName(srcPath);
    if (newName.isNotEmpty && newName != currentName) {
      // 副本的 fid 未知：列一次目标目录把它找出来改名（rename 需要 fid）。
      final copied = await _findInDir(dstDir, currentName);
      if (copied == null || copied.fid.isEmpty) {
        throw CloudDriverException('115 网盘复制完成但未找到副本，无法改名为 $newName');
      }
      await _client.updateFile(copied.fid, newName);
    }
    _fidCache.remove(_joinPath(dstDir, currentName));
    _fidCache.remove(_joinPath(dstDir, newName));
  }

  // ---- 路径 → id ----

  /// 解析目录路径 → fid（上游 `resolveFolderId`）。
  ///
  /// 先用 `folder/get_info` 一次性解析（Go Get 逻辑）；该端点**只支持目录
  /// 路径**，报 430004（不存在）或 990002（参数错误）时回退**逐层列目录**。
  /// 其余错误原样抛出（上游不吞真错误）。
  Future<String> resolveFolderId(String path) async {
    final clean = _clean(path);
    if (clean == '/') return _client.rootId;

    final cached = _fidCache[clean];
    if (cached != null && cached.isNotEmpty) return cached;

    // 一次性解析（Go Get 逻辑）。
    try {
      final info = await _client.getFolderInfo(path: clean);
      final id = '${info['file_id'] ?? ''}';
      if (id.isNotEmpty) {
        _fidCache[clean] = id;
        return id;
      }
    } on _Open115ApiException catch (e) {
      // folder/get_info 只支持目录路径：不存在(430004) / 参数错误(990002)
      // → 回退逐层列目录；其余错误原样抛（上游不吞真错误）。
      if (!e.isObjectNotFound && !e.isInvalidParams) rethrow;
    }
    // 这里包含「get_info 返回空 data」的情形——一并回退逐层解析。

    final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
    var cid = _client.rootId;
    var prefix = '';
    for (final rawSeg in segs) {
      prefix = '$prefix/$rawSeg';
      final hit = _fidCache[prefix];
      if (hit != null && hit.isNotEmpty) {
        cid = hit;
        continue;
      }
      final decodedSeg = _tryDecode(rawSeg);
      final page = await _client.getFiles(
        cid: cid,
        limit: 1150,
        offset: 0,
        asc: true,
        o: 'file_name',
        showDir: true,
      );
      Open115File? folder;
      for (final f in page.files) {
        if (!f.isDir) continue;
        if (f.fn == rawSeg || f.fn == decodedSeg || f.fid == rawSeg) {
          folder = f;
          break;
        }
      }
      if (folder == null) {
        throw CloudDriverException('115 网盘目录不存在：$prefix');
      }
      cid = folder.fid;
      _fidCache[prefix] = cid;
    }
    return cid;
  }

  /// 解析文件路径 → 条目（上游 `resolveFile` / Go `getFromParent`）。
  ///
  /// **必须列父目录**：只有列表接口才返回完整的 `pick_code`，
  /// `folder/get_info` 对文件路径不可用。
  Future<Open115File> resolveFile(String path) async {
    final clean = _clean(path);
    final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) {
      throw CloudDriverException('115 网盘文件不存在：$clean');
    }
    final rawName = segs.removeLast();
    final decodedName = _tryDecode(rawName);
    final parentPath = '/${segs.join('/')}';
    final parentId = await resolveFolderId(parentPath);

    var offset = 0;
    final limit = _pageSize > 1150 ? _pageSize : 1150;
    for (;;) {
      final page = await _client.getFiles(
        cid: parentId,
        limit: limit,
        offset: offset,
        asc: true,
        o: 'file_name',
        showDir: true,
      );
      for (final f in page.files) {
        if (f.fn == rawName ||
            f.fn == decodedName ||
            f.fid == rawName ||
            f.fid == decodedName) {
          return f;
        }
      }
      if (page.files.isEmpty || offset + page.files.length >= page.count) break;
      offset += page.files.length;
    }
    throw CloudDriverException('115 网盘文件不存在：$rawName');
  }

  /// 在 [dir] 下按名字找一个条目（copy 改名用）。
  Future<Open115File?> _findInDir(String dir, String name) async {
    final cid = await resolveFolderId(dir);
    final decoded = _tryDecode(name);
    var offset = 0;
    for (;;) {
      final page = await _client.getFiles(
        cid: cid,
        limit: 1150,
        offset: offset,
        asc: true,
        o: 'file_name',
        showDir: true,
      );
      for (final f in page.files) {
        if (f.fn == name || f.fn == decoded) return f;
      }
      if (page.files.isEmpty || offset + page.files.length >= page.count) break;
      offset += page.files.length;
    }
    return null;
  }

  // ---- 工具 ----

  String _clean(String p) {
    final segs = p.split('/').where((s) => s.isNotEmpty).toList();
    return '/${segs.join('/')}';
  }

  String _joinPath(String dir, String name) =>
      _clean('${_clean(dir)}/$name');

  /// uri 解码失败时用原名（上游的 try/catch 语义）。
  String _tryDecode(String raw) {
    try {
      final decoded = Uri.decodeComponent(raw);
      return decoded.isEmpty ? raw : decoded;
    } catch (_) {
      return raw;
    }
  }

  String _decodedName(String path) => _tryDecode(cloudBasename(_clean(path)));

  void _invalidatePath(String clean) {
    _fidCache.remove(clean);
  }

  CloudFileItem _toItem(Open115File f) => CloudFileItem(
        name: f.fn,
        isDir: f.isDir,
        size: f.fs,
        // upt 是 Unix **秒**（Go `time.Unix(o.Upt, 0)`）。
        modified: f.upt > 0
            ? DateTime.fromMillisecondsSinceEpoch(f.upt * 1000)
            : null,
      );
}

/// 驱动自描述（99 §7.2.10）：类型、显示名、能力遮罩、表单参数、构造全部收在
/// 本文件；`driver_registry.dart` 加一行即接入账号表单。
class Open115Spec extends CloudDriverSpec {
  const Open115Spec();

  /// 与 OpenList 驱动目录名一致。
  @override
  String get typeId => '115open';

  @override
  String get displayName => '115网盘';

  // 列出 / 读取 / 创建文件夹 / 移动 / 复制 / 删除；**write 一律不给**
  //（上传已砍，99 §4.2.1；mkdir 核查见 99 §4.3.2——115open 是真实现）。
  @override
  int get capabilities => AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  /// 运行时令牌缓存：`access_token` 经 `onTokenUpdate` 写回驱动配置，
  /// 不在表单里；不声明就会明文进凭证库与备份（[11 §6.2]）。refresh_token
  /// 同样会被轮换写回，但它已在表单里 `obscure`，无需重复声明。
  @override
  Set<String> get runtimeSecretKeys => const {'access_token'};

  @override
  List<CloudDriverFormItem> get form => const [
        CloudDriverField(
          key: 'refresh_token',
          label: 'refresh_token',
          hint: '必填；获取方法见 OpenList 官方文档（115 Open 驱动页）。'
              '115 每次刷新都会轮换它，轮换结果会自动保存',
          required: true,
          obscure: true,
        ),
        CloudDriverField(
          key: 'root_id',
          label: '根目录 ID',
          hint: '默认 0（整体根目录）；填非 0 的目录 ID 可把账号挂到该目录下',
          defaultValue: '0',
        ),
        CloudDriverField(
          key: 'page_size',
          label: '分页大小',
          hint: '范围 1~1150，默认 200（超出会被夹到边界；115 单次上限 1150）',
          defaultValue: '200',
        ),
        CloudDriverField(
          key: 'limit_rate',
          label: '限速（次/秒）',
          hint: '默认 0 = 不限速；填正数则两次 API 请求之间至少间隔 1/该值 秒',
          defaultValue: '0',
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    return Open115Driver.fromConfig(
      config,
      onTokenUpdate: onTokenUpdate,
    );
  }
}
