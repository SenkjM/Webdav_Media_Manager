import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/account_capabilities.dart';
import '../cloud_driver.dart';

/// TeraBox（terabox）驱动。
///
/// 移植自 localdev/OpenList-Worker/src/backend/drivers/terabox
/// （util.ts + driver.ts + types.ts，Go 版 drivers/terabox 语义兜底）。
///
/// 按项目决策砍掉的部分：
/// - 全部上传逻辑（`put` / precreate / superfile2 分片 / `/api/precreate`、
///   `/api/create` 的上传形态）——上传已砍（99 §4.2.1）；
/// - **crack 下载 API 整个砍掉**：`TeraboxAddition.download_api` 不进表单
///   （与百度 §10 先例一致，官方 dlink 足够），因此
///   `linkCrack` / `/api/filemetas` 不移植。Go 版 `Link` 会按
///   `DownloadAPI == "crack"` 分叉，本驱动恒走 `linkOfficial`
///   （worker util.ts `TeraboxApiClient.linkOfficial`）。
///   但 `/api/download` 的**响应形态两种都认**（`dlink` 数组 /
///   `info` 数组，见 [_firstDlink]），线上两种都出现过。
/// - `order_by` / `order_direction` / `only_list_video_file` 不进表单
///   （客户端自己排序）。
///
/// 与 worker 的有意差异：worker 的 `get()` 在拿不到直链时只
/// `console.warn` 并返回 `raw_url: ""`；本应用契约要求文件条目**必须**带
/// [CloudFileItem.rawUrl]，所以这里改为抛出带真实原因的
/// [CloudDriverException]（下游必然失败，不如直说）。
///
/// ## 签名（上游 util.ts，逐行核对后确认**无任何加密原语依赖**）
///
/// `teraboxSign(s1, s2)`（util.ts:9-45 / Go util.go:189-210）是一个
/// **RC4 式 KSA + PRGA 字节流异或**后 base64 的自定义算法，**没有**用到
/// MD5 / SHA1 / AES——见 [teraboxSign] 的实现注释。
/// 上游 `driver.ts:7` 确实 import 了 `pkg/crypto` 的 `md5`，但唯一使用点是
/// `driver.ts:261`（`put()` 内算分片 `block_list`），而 `put` 不移植，
/// 所以本文件连 MD5 都不需要。
///
/// `genSign()` = `teraboxSign(HomeInfoResp.data.sign3, data.sign1)`。
/// `/api/download` 的 `sign` 参数就是它；另有 `vip: "2"` 与 Unix 秒
/// `timestamp`，三者都不是加密，只是普通查询参数。
class TeraboxAddition {
  TeraboxAddition({
    required this.cookie,
    this.rootFolderPath = '/',
  });

  factory TeraboxAddition.fromJson(Map<String, dynamic> json) =>
      TeraboxAddition(
        cookie: json['cookie'] as String? ?? '',
        rootFolderPath: json['root_folder_path'] as String? ?? '/',
      );

  Map<String, dynamic> toJson() => {
        'cookie': cookie,
        'root_folder_path': rootFolderPath,
      };

  /// TeraBox 的 Cookie（必填，会过期，过期后需重新粘贴）。
  String cookie;

  /// 根目录路径；空串按 `/` 处理。
  ///
  /// 上游 meta.go 用 `driver.RootPath`（`DefaultRoot: "/"`）。本应用的通用
  /// 「远程路径」已挂在账号层（CloudDriveService.joinRemotePath），这里保留
  /// 字段只为与上游 Addition 键名对齐 + 兼容 `root_folder_path` 语义。
  String rootFolderPath;
}

/// `/api/list` 的条目（types.ts `TeraboxFile` 的字段子集）。
class TeraboxFile {
  TeraboxFile({
    this.fsId = 0,
    this.path = '',
    this.serverFilename = '',
    this.size = 0,
    this.isdir = 0,
    this.serverMtime = 0,
  });

  factory TeraboxFile.fromMap(Map<String, dynamic> m) => TeraboxFile(
        fsId: (m['fs_id'] as num?)?.toInt() ?? 0,
        path: m['path'] as String? ?? '',
        serverFilename: m['server_filename'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        isdir: (m['isdir'] as num?)?.toInt() ?? 0,
        serverMtime: (m['server_mtime'] as num?)?.toInt() ?? 0,
      );

  /// 文件 id：`/api/download` 的 `fidlist` 要它。
  final int fsId;

  final String path;
  final String serverFilename;
  final int size;

  /// 1 = 目录，0 = 文件。
  final int isdir;

  /// Unix **秒**。
  final int serverMtime;
}

/// TeraBox 自定义签名（util.ts:9-45 / Go util.go:189-210 逐行对齐）。
///
/// 算法本身叫 RC4：`s1` 是密钥做 KSA（256 轮），`s2` 是明文做 PRGA 异或，
/// 输出 base64。**没有任何摘要 / 分组加密**，纯 Dart 可逐字节等价实现。
///
/// 逐字节对齐要点（[11 §3](docs/11-CLOUD-DRIVER-PORTING.md) 第 1 条的同类坑）：
/// 上游两侧都是 UTF-16 码元（JS `charCodeAt` / Go `byte`——Go 侧按 UTF-8
/// 字节索引但两边都只用于 ASCII 的 sign1/sign3，等价）；
/// Dart 用 `codeUnitAt` 与之同语义。异或结果按 **无符号字节** 收集后
/// base64，所以这里显式 `& 0xFF`。
String teraboxSign(String s1, String s2) {
  if (s1.isEmpty) {
    // 上游 JS：v = 0 → `q % v` = NaN → charCodeAt(NaN) = NaN → a[q]=NaN，
    // 后续算术全 NaN。Go：s1 空时 `q % v` 除零 panic。两边都不是可用行为，
    // 这里明确报错而不是产出一个「看起来能跑」的签名。
    throw const CloudDriverException(
      'TeraBox 签名失败：sign3 密钥为空（上游 /api/home/info 未返回 sign3）',
    );
  }
  final a = List<int>.filled(256, 0);
  final p = List<int>.generate(256, (i) => i);
  final o = <int>[];
  final v = s1.length;

  for (var q = 0; q < 256; q++) {
    a[q] = s1.codeUnitAt(q % v);
  }

  var u = 0;
  for (var q = 0; q < 256; q++) {
    u = (u + p[q] + a[q]) % 256;
    final tmp = p[q];
    p[q] = p[u];
    p[u] = tmp;
  }

  var i = 0;
  u = 0;
  for (var q = 0; q < s2.length; q++) {
    i = (i + 1) % 256;
    u = (u + p[i]) % 256;
    final tmp = p[i];
    p[i] = p[u];
    p[u] = tmp;
    final k = p[(p[i] + p[u]) % 256];
    o.add((s2.codeUnitAt(q) ^ k) & 0xFF);
  }

  return base64.encode(Uint8List.fromList(o));
}

class TeraboxClient {
  /// 默认站点；errno -6 + `Url-Domain-Prefix` 响应头会改它（util.ts:183-193）。
  static const defaultBaseUrl = 'https://www.terabox.com';

  /// util.ts:70 / util.go:43 的 UA（直链下载也必须带，见 [downloadUA]）。
  static const apiUA =
      'terabox;1.37.0.7;PC;PC-Windows;10.0.22631;WindowsTeraBox';

  /// 直链必需的 UA（Go linkOfficial 的 `Header` 只有一个 User-Agent）。
  static const downloadUA = apiUA;

  /// jsToken 失效 / 需要重取的错误码（util.ts:176）。
  static const Set<int> jsTokenErrors = {4000023, 450016};

  /// 重取 jsToken / 换域名的最大重试次数（util.ts 的 `retryCount < 2`）。
  static const retryLimit = 2;

  static const acceptHeader = 'application/json, text/plain, */*';
  static const xRequestedWith = 'XMLHttpRequest';

  /// 分页页大小（worker `num = 100`）。
  static const pageSize = 100;

  /// `get()` 找单文件时用的页大小（worker `num = "1000"`）。
  static const statPageSize = 1000;

  TeraboxClient(this.addition, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {
                  'User-Agent': apiUA,
                  'Accept': acceptHeader,
                  'Referer': defaultBaseUrl,
                  'X-Requested-With': xRequestedWith,
                },
                // 非 2xx 也回来读 body：errno 与「原文报错」都在 body 里。
                validateStatus: (_) => true,
                // 直链那一跳要自己读 Location（util.ts:249-260）。
                followRedirects: false,
              ),
            );

  final TeraboxAddition addition;
  final Dio _dio;

  String baseUrl = defaultBaseUrl;

  /// `https://<prefix>.terabox.com` 的 prefix（Go `url_domain_prefix`，默认 jp）。
  String urlDomainPrefix = 'jp';

  /// 首页正则抓出来的 jsToken；空串 = 还没抓或抓不到。
  String jsToken = '';

  /// 真连校验（util.ts `init` / Go `Init`）：
  /// `GET /api/check/login`，errno != 0 即报错，9000 是「该地区不可用」。
  Future<void> checkLogin() async {
    final body = await request('/api/check/login');
    final errno = _errnoOf(body);
    if (errno != 0) {
      if (errno == 9000) {
        throw const CloudDriverException(
          'TeraBox is not yet available in this area (errno 9000)',
        );
      }
      throw CloudDriverException(
        'Failed to verify TeraBox login status according to cookie '
        '(errno $errno)',
      );
    }
  }

  /// 通用请求：拼公共 query、带 Cookie / UA / Referer、
  /// errno 4000023|450016 重取 jsToken、errno -6 换域名。对齐 util.ts:98-197。
  Future<Map<String, dynamic>> request(
    String pathOrUrl, {
    String method = 'GET',
    Map<String, String>? params,
    Map<String, String>? form,
    Map<String, dynamic>? jsonBody,
    int retryCount = 0,
  }) async {
    final full = pathOrUrl.startsWith('http') ? pathOrUrl : '$baseUrl$pathOrUrl';

    final query = <String, String>{
      'app_id': '250528',
      'web': '1',
      'channel': 'dubox',
      'clienttype': '0',
      ...?params,
    };
    if (jsToken.isNotEmpty) query['jsToken'] = jsToken;

    final headers = <String, dynamic>{
      'Cookie': addition.cookie,
      'Accept': acceptHeader,
      'Referer': baseUrl,
      'User-Agent': apiUA,
      'X-Requested-With': xRequestedWith,
    };

    Object? data;
    if (form != null) {
      headers['Content-Type'] = Headers.formUrlEncodedContentType;
      data = form;
    } else if (jsonBody != null) {
      headers['Content-Type'] = 'application/json';
      data = jsonBody;
    }

    final Response<String> res;
    try {
      res = await _dio.request<String>(
        full,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException(
        'TeraBox 请求失败 [$method ${Uri.parse(full).path}]：${e.message ?? e.type.name}',
        e,
      );
    }

    final body = _decodeBody(res);

    if (body.isNotEmpty) {
      final errno = _errnoOf(body);
      if (jsTokenErrors.contains(errno) && retryCount < retryLimit) {
        await resetJsToken();
        return request(
          pathOrUrl,
          method: method,
          params: params,
          form: form,
          jsonBody: jsonBody,
          retryCount: retryCount + 1,
        );
      }
      if (errno == -6 && retryCount < retryLimit) {
        final prefix = res.headers.value('url-domain-prefix');
        if (prefix != null && prefix.isNotEmpty) {
          urlDomainPrefix = prefix;
          baseUrl = 'https://$prefix.terabox.com';
          return request(
            pathOrUrl,
            method: method,
            params: params,
            form: form,
            jsonBody: jsonBody,
            retryCount: retryCount + 1,
          );
        }
      }
    }

    return body;
  }

  /// 取首页并正则抓 jsToken（util.ts:62-96）。
  ///
  /// 上游第一个正则匹配的是 `function%20fn%28a%29%7Bwindow.jsToken%20%3D%20a%7D...`
  /// 这段 **URL 编码后**的字面量（页面里它被编码过）；第二个是宽松的
  /// `jsToken = "..."` 兜底。两个都拿不到就留空串（上游也是留空继续跑）。
  Future<void> resetJsToken() async {
    final Response<String> res;
    try {
      res = await _dio.get<String>(
        baseUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Cookie': addition.cookie,
            'Accept': acceptHeader,
            'Referer': baseUrl,
            'User-Agent': apiUA,
            'X-Requested-With': xRequestedWith,
          },
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException('Failed to fetch TeraBox home page: ${e.message}', e);
    }
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw CloudDriverException(
        'Failed to fetch TeraBox home page: HTTP ${res.statusCode}',
      );
    }
    final html = res.data ?? '';

    final encoded = RegExp(
      r'`function%20fn%28a%29%7Bwindow\.jsToken%20%3D%20a%7D%3Bfn%28%22([^"]+?)%22%29`',
    ).firstMatch(html);
    if (encoded != null && encoded.group(1)!.isNotEmpty) {
      jsToken = encoded.group(1)!;
      return;
    }
    final simple = RegExp(r'''jsToken\s*=\s*["']([^"']+)["']''').firstMatch(html);
    if (simple != null && simple.group(1)!.isNotEmpty) {
      jsToken = simple.group(1)!;
      return;
    }
    jsToken = '';
  }

  /// `/api/home/info` 取 sign1 / sign3 → 签名（util.ts:216-224）。
  ///
  /// `data.timestamp` 上游响应里有但**没参与签名**（签名只用 sign3 当密钥、
  /// sign1 当明文），所以不解析它。
  Future<String> genSign() async {
    final body = await request('/api/home/info');
    final data = body['data'];
    if (data is! Map) {
      throw const CloudDriverException(
        'Failed to get TeraBox sign keys from home/info',
      );
    }
    final m = Map<String, dynamic>.from(data);
    final sign1 = m['sign1'] as String? ?? '';
    final sign3 = m['sign3'] as String? ?? '';
    if (sign1.isEmpty || sign3.isEmpty) {
      throw const CloudDriverException(
        'Failed to get TeraBox sign keys from home/info',
      );
    }
    return teraboxSign(sign3, sign1);
  }

  /// 列目录：`GET /api/list`，100 一页翻到空（util.ts:38-95 /
  /// util.go:156-187）。`errno == 9000` 是地区不可用。
  Future<List<TeraboxFile>> listDir(String dir) async {
    final out = <TeraboxFile>[];
    for (var page = 1;; page++) {
      final body = await request('/api/list', params: {
        'dir': dir,
        'page': '$page',
        'num': '$pageSize',
      });
      if (_errnoOf(body) == 9000) {
        throw const CloudDriverException(
          'TeraBox is not yet available in this area',
        );
      }
      final list = body['list'];
      if (list is! List || list.isEmpty) break;
      for (final e in list) {
        if (e is Map) out.add(TeraboxFile.fromMap(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  /// 官方直链（util.ts:226-261 / Go util.go:221-254）：
  /// `/api/download` 拿 dlink → **不跟随**地 GET 一次读出 `Location`。
  ///
  /// 上游的响应解析只用 `resp.dlink[0].dlink`（types.ts `TeraboxDownloadResp`）；
  /// 本实现额外兼容 `info[0].dlink`（`TeraboxDownloadResp2` 的形态），
  /// 因为线上 / 不同区域两种形态都出现过——见测试的两种 dlink 用例。
  Future<({String url, Map<String, String> headers})> linkOfficial(
    int fsId,
  ) async {
    final sign = await genSign();
    final body = await request('/api/download', params: {
      'type': 'dlink',
      'fidlist': '[$fsId]',
      'sign': sign,
      'vip': '2',
      'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    });

    final dlink = _firstDlink(body);
    if (dlink == null || dlink.isEmpty) {
      throw CloudDriverException(
        'TeraBox fid $fsId no dlink found (errno: ${_errnoOf(body)})',
      );
    }

    // 跟一次重定向拿真正的直链（上游 redirect: "manual" / Go NoRedirectClient）。
    // 只用 headers 里的 Location，bytes 避免把整包内容读进内存。
    final String url;
    try {
      final res = await _dio.get<List<int>>(
        dlink,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.bytes,
          headers: {
            'Cookie': addition.cookie,
            'User-Agent': downloadUA,
          },
        ),
      );
      final loc = res.headers.value('location');
      url = (loc != null && loc.isNotEmpty) ? loc : dlink;
    } on DioException catch (e) {
      throw CloudDriverException(
        'TeraBox 直链重定向失败（fid $fsId）：${e.message ?? e.type.name}',
        e,
      );
    }

    return (url: url, headers: {'User-Agent': downloadUA});
  }

  /// `GET /api/filemanager`（rename / move / copy / delete 共用）。
  ///
  /// 上游 util.ts:282-301 的 `manage()`：`opera` 在 **query**，
  /// `onnest=fail` 也在 query；body 是 `async=0&filelist=<json>&ondup=newcopy`
  /// 的 **form-urlencoded**。注意 `filelist` 是 JSON 字符串再被表单编码一次。
  Future<void> manage(String opera, Object? filelist) async {
    await request(
      '/api/filemanager',
      method: 'POST',
      params: {'onnest': 'fail', 'opera': opera},
      form: {
        'async': '0',
        'filelist': jsonEncode(filelist),
        'ondup': 'newcopy',
      },
    );
  }

  /// `POST /api/create?a=commit` 建目录（util.ts:170-182 / Go MakeDir）。
  Future<void> createDir(String path) async {
    await request(
      '/api/create',
      method: 'POST',
      params: {'a': 'commit'},
      form: {
        'path': path,
        'isdir': '1',
        'block_list': '[]',
      },
    );
  }

  Map<String, dynamic> _decodeBody(Response<String> res) {
    final text = res.data ?? '';
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 上游把非 JSON 原样返回（`data = text`）；这里保持不抛，
      // errno 读不到就是 0，错误由调用方按各自语义抛。
    }
    return <String, dynamic>{};
  }

  int _errnoOf(Map<String, dynamic> body) =>
      (body['errno'] as num?)?.toInt() ?? 0;

  /// `dlink` 是 `[{dlink}]`（TeraboxDownloadResp），
  /// `info` 是 `[{dlink}]`（TeraboxDownloadResp2）——两种形态都认。
  String? _firstDlink(Map<String, dynamic> body) {
    for (final key in const ['dlink', 'info']) {
      final v = body[key];
      if (v is List && v.isNotEmpty) {
        final first = v.first;
        if (first is Map) {
          final d = first['dlink'];
          if (d is String && d.isNotEmpty) return d;
        }
      }
    }
    return null;
  }
}

/// TeraBox 驱动的 [CloudDriver] 实现。
class TeraboxDriver extends CloudDriver {
  TeraboxDriver({
    required TeraboxAddition addition,
    Dio? dio,
  }) : _client = TeraboxClient(addition, dio: dio);

  final TeraboxClient _client;

  /// 测试 / 上层需要直接摸 client 时用。
  TeraboxClient get client => _client;

  @override
  Future<void> init() async {
    await _client.checkLogin();
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final files = await _client.listDir(teraboxPath(path));
    return [for (final f in files) _toItem(f)];
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final clean = teraboxPath(path);
    if (clean == '/') {
      return const CloudFileItem(name: '/', isDir: true);
    }

    final parent = cloudDirname(clean);
    final fileName = cloudBasename(clean);

    final body = await _client.request('/api/list', params: {
      'dir': parent,
      'page': '1',
      'num': '${TeraboxClient.statPageSize}',
    });
    if ((body['errno'] as num?)?.toInt() == 9000) {
      throw const CloudDriverException(
        'TeraBox is not yet available in this area',
      );
    }
    final list = body['list'];
    TeraboxFile? found;
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final f = TeraboxFile.fromMap(Map<String, dynamic>.from(e));
        if (f.serverFilename == fileName) {
          found = f;
          break;
        }
      }
    }
    if (found == null) {
      throw CloudDriverException('file not found: $fileName');
    }

    if (found.isdir == 1) {
      return _toItem(found);
    }

    // 文件：契约要求必须带直链，拿不到就抛真实原因（worker 的 warn + 空
    // raw_url 在本应用会让下游必然失败）。
    final link = await _client.linkOfficial(found.fsId);
    return CloudFileItem(
      name: _nameOf(found),
      isDir: false,
      size: found.size,
      modified: teraboxMtime(found.serverMtime),
      rawUrl: link.url,
      rawHeaders: link.headers,
    );
  }

  @override
  Future<void> mkdir(String path) async {
    await _client.createDir(teraboxPath(path));
  }

  /// 改名 / 改路径。接口契约说「跨目录时降级为 move + newname」；
  /// TeraBox 的 `rename` opera **本身就带 `path`**，所以把目标目录
  /// 体现在 `path` 上即可，一次请求完成（与百度 filemanager 的
  /// `move` + `newname` 等价）。
  @override
  Future<void> rename(String path, String newPath) async {
    final dst = teraboxPath(newPath);
    await _client.manage('rename', [
      {'path': dst, 'newname': cloudBasename(dst)},
    ]);
  }

  @override
  Future<void> remove(String path) async {
    await _client.manage('delete', [teraboxPath(path)]);
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    await _client.manage('move', [
      {
        'path': teraboxPath(srcPath),
        'dest': teraboxPath(dstDir),
        'newname': newName,
      },
    ]);
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    await _client.manage('copy', [
      {
        'path': teraboxPath(srcPath),
        'dest': teraboxPath(dstDir),
        'newname': newName,
      },
    ]);
  }

  CloudFileItem _toItem(TeraboxFile f) => CloudFileItem(
        name: _nameOf(f),
        isDir: f.isdir == 1,
        size: f.size,
        modified: teraboxMtime(f.serverMtime),
      );

  String _nameOf(TeraboxFile f) =>
      f.serverFilename.isNotEmpty ? f.serverFilename : cloudBasename(f.path);
}

/// `server_mtime` 是 Unix **秒**，且上游对 0 / 缺失回落「当前时间」而不是
/// null（driver.ts:80-82）。本应用 [CloudFileItem.modified] 可空，
/// 但为对齐上游「列表里时间永不为空」的观感，0 时也给当前时间。
DateTime? teraboxMtime(int serverMtime) => serverMtime > 0
    ? DateTime.fromMillisecondsSinceEpoch(serverMtime * 1000)
    : DateTime.now();

/// 规范化为 TeraBox 的绝对路径：折叠重复斜杠、去掉尾斜杠
/// （worker driver.ts `cleanPath`：首尾处理成 `/` + 段连接）。
String teraboxPath(String p) {
  final clean = '/${p.split('/').where((s) => s.isNotEmpty).join('/')}';
  return clean;
}

/// 驱动自描述：类型、显示名、能力遮罩、表单参数、构造全在本文件
/// （[12 §2 第 4 步](docs/12-DRIVER-PORTING-GUIDE.md)）。
class TeraboxSpec extends CloudDriverSpec {
  const TeraboxSpec();

  @override
  String get typeId => 'terabox';

  @override
  String get displayName => 'TeraBox';

  /// 六项全给：worker / Go 两版的 mkdir / move / rename / copy / remove
  /// **都是真实现**（driver.ts:170-244、driver.go:78-131），
  /// 且签名 / 请求构造没有加密卡点（见 [teraboxSign] 注释）。
  /// `write` 一律不给（上传已砍）。
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
          key: 'cookie',
          label: 'Cookie',
          hint: '必填；从浏览器复制 TeraBox 的 Cookie；过期后需重新粘贴',
          required: true,
          obscure: true,
        ),
        CloudDriverField(
          key: 'root_folder_path',
          label: '根目录路径',
          defaultValue: '/',
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    return TeraboxDriver(addition: TeraboxAddition.fromJson(config));
  }
}
