// 123 云盘开放平台驱动（123_open）的行为回归。
//
// 上游参照：`localdev/OpenList-Worker/src/backend/drivers/123_open`
// （driver.ts + util.ts + types.ts，移植底稿）、
// `localdev/OpenList/drivers/123_open`（Go 版，语义兜底）。
//
// 锁定的事实：
//   - 令牌刷新两条分支：在线续期地址（`api_url_address`）vs
//     自建应用 client 凭证（`POST /api/v1/access_token`），两者互斥；
//   - 请求头 `Authorization: Bearer <token>` + `platform: open_platform`；
//   - 列表分页：`last_file_id !== -1` 才继续，`trashed !== 0` 过滤；
//   - `type === 1` 判目录；
//   - `update_at` 是 UTC+8 墙钟串，转出来的 DateTime 必须减 8 小时；
//   - `download_info.download_url` 落到 `rawUrl`；
//   - `code !== 0` 时错误原文透传；
//   - `code === 401` 触发一次刷新并重试一次；
//   - 缺必填 refresh_token 时报可读错误且不出网。
//
// 实现方式：自定义 dio HttpClientAdapter 拦截全部出站请求，按 host 分流到
// 本地 HttpServer，记录 method / url / headers / body 供断言。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/_123_open_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/driver_registry.dart';

/// 表单条目的 key（`CloudDriverFormItem` 是 sealed 基类，key 在具体子类上）。
String _formKey(CloudDriverFormItem item) => switch (item) {
      CloudDriverField(:final key) => key,
      CloudDriverSelectField(:final key) => key,
      CloudDriverAccountField(:final key) => key,
      CloudDriverSwitchField(:final key) => key,
    };

/// 记录一次出站请求。
class _Hit {
  _Hit(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  /// 便捷访问：断言里直接写 `hit.host` / `hit.path`。
  String get host => uri.host;
  String get path => uri.path;
}

/// 把出站请求按 host 分流：api.oplist.org → 本地续期服务器；
/// open-api.123pan.com → 本地 API 服务器；其余 → 404。
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.renewServer, this.apiServer);

  final HttpServer renewServer;
  final HttpServer apiServer;
  final List<_Hit> hits = <_Hit>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var body = '';
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      body = utf8.decode(bytes, allowMalformed: true);
    }
    final uri = Uri.parse(options.uri.toString());
    hits.add(_Hit(options.method, uri, {
      for (final e in options.headers.entries)
        if (e.value != null) e.key.toLowerCase(): '${e.value}',
    }, body));

    if (uri.host == 'api.oplist.org') return _forward(renewServer, options, body);
    if (uri.host == 'open-api.123pan.com') {
      return _forward(apiServer, options, body);
    }
    return ResponseBody.fromString('not found', 404);
  }

  Future<ResponseBody> _forward(
    HttpServer server,
    RequestOptions options,
    String body,
  ) async {
    final client = HttpClient();
    final target = Uri.parse(
        'http://127.0.0.1:${server.port}${options.uri.path}?${options.uri.query}');
    final req = await client.openUrl(options.method, target);
    if (body.isNotEmpty) {
      req.headers.contentType = ContentType.json;
      req.write(body);
    }
    final res = await req.close();
    final bytes = <int>[];
    await for (final c in res) {
      bytes.addAll(c);
    }
    client.close(force: true);
    final ct = res.headers.contentType?.mimeType ?? 'application/json';
    return ResponseBody.fromBytes(bytes, res.statusCode, headers: {
      'content-type': [ct],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpServer renewServer;
  late HttpServer apiServer;
  late _RoutingAdapter adapter;
  late Dio dio;

  /// 续期服务器收到的 refresh_ui 列表。
  late List<String> renewRefreshes;

  /// 每个 API 用例可覆写的响应工厂：(path, query, body) → JSON 对象。
  late Map<String, dynamic> Function(
    String path,
    Map<String, String> query,
    String body,
  ) apiResponse;

  /// API 服务器收到的请求（path → 次数），断言端点用。
  late List<String> apiPaths;

  /// API 用例里观察到的请求体（最近一次）。
  late String lastApiBody;

  Map<String, dynamic> envelope(Object? data) =>
      <String, dynamic>{'code': 0, 'message': 'ok', 'data': data};

  Map<String, dynamic> fileMap(
    int id,
    String name, {
    int type = 2,
    int size = 1024,
    String? updateAt,
  }) =>
      <String, dynamic>{
        'fileId': id,
        'filename': name,
        'size': size,
        'type': type,
        'update_at': updateAt ?? '2024-01-02 03:04:05',
        'trashed': 0,
      };

  setUp(() async {
    renewRefreshes = <String>[];
    apiPaths = <String>[];
    lastApiBody = '';

    renewServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    renewServer.listen((req) {
      final refresh = req.uri.queryParameters['refresh_ui'] ?? '';
      renewRefreshes.add(refresh);
      // 只认 'rejected-rt' 之外的令牌（未登记令牌走失败分支）。
      if (req.method == 'GET' &&
          req.uri.path == '/123cloud/renewapi' &&
          refresh.isNotEmpty &&
          refresh != 'rejected-rt') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"access_token":"online-access","refresh_token":"online-refresh"}');
      } else {
        req.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write('{"error_description":"bad refresh token"}');
      }
      req.response.close();
    });

    apiServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    apiServer.listen((req) async {
      apiPaths.add(req.uri.path);
      final body = await utf8.decoder.bind(req).join();
      lastApiBody = body;
      final payload = apiResponse(
        req.uri.path,
        req.uri.queryParameters,
        body,
      );
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload));
      await req.response.close();
    });

    adapter = _RoutingAdapter(renewServer, apiServer);
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.httpClientAdapter = adapter;

    // 默认：access_token 换得到，其余端点回空 data。
    apiResponse = (path, query, body) {
      if (path == '/api/v1/access_token') {
        return envelope(<String, dynamic>{'access_token': 'client-access'});
      }
      return envelope(<String, dynamic>{});
    };
  });

  tearDown(() async {
    await renewServer.close(force: true);
    await apiServer.close(force: true);
  });

  Driver123OpenAddition additionWith({
    String? refreshToken,
    String? clientId,
    String? clientSecret,
    String? apiUrlAddress,
    bool localRefresh = false,
    String? rootFolderId,
    String? accessToken,
  }) =>
      Driver123OpenAddition(
        refreshToken: refreshToken ?? 'rt-1',
        clientId: clientId ?? '',
        clientSecret: clientSecret ?? '',
        apiUrlAddress: apiUrlAddress ?? Driver123OpenClient.defaultRenewApi,
        localRefresh: localRefresh,
        rootFolderId: rootFolderId ?? '0',
        accessToken: accessToken ?? '',
      );

  Driver123Open driverWith(Driver123OpenAddition addition) =>
      Driver123Open(addition: addition, dio: dio);

  group('spec 与能力遮罩', () {
    test('类型 id / 显示名 / 注册表登记', () {
      const spec = Driver123OpenSpec();
      expect(spec.typeId, '123_open');
      expect(spec.displayName, '123 云盘开放平台');
      expect(cloudDriverSpec('123_open'), isA<Driver123OpenSpec>());
    });

    test('能力位 = 列出 | 读取 | mkdir | move | delete，没有 copy / write', () {
      const spec = Driver123OpenSpec();
      final caps = spec.capabilities;
      expect(AccountCaps.has(caps, AccountCaps.list), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.read), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.mkdir), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.move), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.delete), isTrue);
      // worker copy() 抛 not supported；Go 版依赖上传秒传 → 不给位。
      expect(AccountCaps.has(caps, AccountCaps.copy), isFalse);
      // 上传已砍（99 §7.2.1）。
      expect(AccountCaps.has(caps, AccountCaps.write), isFalse);
    });

    test('表单六项：refresh_token 必填密文、续期地址默认值、开关联动、根目录默认 0', () {
      const spec = Driver123OpenSpec();
      expect(
        spec.form.map(_formKey).toList(),
        ['refresh_token', 'api_url_address', 'local_refresh', 'client_id',
          'client_secret', 'root_folder_id'],
      );

      final rt = spec.form.first as CloudDriverField;
      expect(rt.required, isTrue);
      expect(rt.obscure, isTrue);

      final fields = spec.form.whereType<CloudDriverField>().toList();
      final api = fields.firstWhere((f) => f.key == 'api_url_address');
      expect(api.defaultValue, 'https://api.oplist.org/123cloud/renewapi');
      // 99 §7.3.1：「开了就停用」，不是「开了才可用」。
      expect(api.disabledWhenSwitch, 'local_refresh');
      expect(api.enabledWhenSwitch, isNull);
      expect(api.disabledHint, isNotNull);

      final cid = fields.firstWhere((f) => f.key == 'client_id');
      final secret = fields.firstWhere((f) => f.key == 'client_secret');
      expect(cid.visibleWhenSwitch, 'local_refresh');
      expect(secret.visibleWhenSwitch, 'local_refresh');
      expect(secret.obscure, isTrue);

      final root = fields.firstWhere((f) => f.key == 'root_folder_id');
      expect(root.defaultValue, '0');

      // access_token 不进表单，只作缓存。
      expect(fields.any((f) => f.key == 'access_token'), isFalse);

      // 开关默认关（＝走在线续期，对齐 Go 的 use_online_api 默认 true）。
      final sw = spec.form.whereType<CloudDriverSwitchField>().single;
      expect(sw.key, 'local_refresh');
      expect(sw.defaultValue, isFalse);
      expect(spec.switchValue('local_refresh', const {}), isFalse);
    });
  });

  group('令牌刷新分支 1：在线续期（local_refresh = false）', () {
    test('请求打到续期地址，带对参数，两个令牌都存下来', () async {
      final addition = additionWith(refreshToken: 'rt-online');
      final client = Driver123OpenClient(addition, dio: dio);
      await client.getAccessToken();

      expect(renewRefreshes, ['rt-online']);
      expect(apiPaths, isEmpty, reason: '在线分支不该打到 123 开放平台');
      expect(client.accessToken, 'online-access');
      expect(addition.accessToken, 'online-access');
      expect(addition.refreshToken, 'online-refresh', reason: '轮换后的 refresh_token 必须存下来');

      final hit = adapter.hits.single;
      expect(hit.method, 'GET');
      expect(hit.uri.host, 'api.oplist.org');
      expect(hit.uri.path, '/123cloud/renewapi');
      expect(hit.uri.queryParameters['refresh_ui'], 'rt-online');
      expect(hit.uri.queryParameters['server_use'], 'true');
      expect(hit.uri.queryParameters['driver_txt'], '123cloud_oa');
      // 在线分支绝不带 client 凭证。
      expect(hit.uri.queryParameters.containsKey('client_id'), isFalse);
      expect(hit.uri.queryParameters.containsKey('client_secret'), isFalse);
    });

    test('空 apiUrlAddress 回落到默认公共服务地址', () async {
      final addition = additionWith(refreshToken: 'rt-2', apiUrlAddress: '');
      final client = Driver123OpenClient(addition, dio: dio);
      await client.getAccessToken();
      expect(adapter.hits.single.host, 'api.oplist.org');
      expect(adapter.hits.single.path, '/123cloud/renewapi');
      expect(client.accessToken, 'online-access');
    });

    test('onTokenUpdate 收到两个令牌的 patch', () async {
      final patches = <Map<String, dynamic>>[];
      final client = Driver123OpenClient(
        additionWith(refreshToken: 'rt-3'),
        dio: dio,
        onTokenUpdate: patches.add,
      );
      await client.getAccessToken();
      expect(patches.single['access_token'], 'online-access');
      expect(patches.single['refresh_token'], 'online-refresh');
    });

    test('续期服务报错：错误原文透传，不落 client 凭证分支', () async {
      // 续期服务器只在 refresh_ui 命中已知令牌时成功；用未登记的值触发
      // 400 + {"error_description": ...} 分支。
      final addition = additionWith(
        refreshToken: 'rejected-rt',
        clientId: 'cid',
        clientSecret: 'secret',
      );
      final client = Driver123OpenClient(addition, dio: dio);
      await expectLater(
        client.getAccessToken(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('bad refresh token'),
        )),
      );
      // 在线续期失败绝不再拿 client 凭证兜底（两条路互斥）。
      expect(apiPaths, isEmpty);
    });
  });

  group('令牌刷新分支 2：本地 client 凭证（local_refresh = true）', () {
    test('POST /api/v1/access_token，带 clientID / clientSecret', () async {
      final addition = additionWith(
        refreshToken: 'rt-local',
        clientId: 'my-cid',
        clientSecret: 'my-secret',
        localRefresh: true,
      );
      final client = Driver123OpenClient(addition, dio: dio);
      await client.getAccessToken();

      expect(renewRefreshes, isEmpty, reason: '开关打开时绝不使用在线续期');
      expect(client.accessToken, 'client-access');
      expect(addition.accessToken, 'client-access');
      // 自建应用刷新不轮换 refresh_token。
      expect(addition.refreshToken, 'rt-local');

      final hit = adapter.hits.single;
      expect(hit.method, 'POST');
      expect(hit.uri.host, 'open-api.123pan.com');
      expect(hit.uri.path, '/api/v1/access_token');
      expect(hit.headers['platform'], 'open_platform');
      final body = jsonDecode(hit.body) as Map<String, dynamic>;
      expect(body['clientID'], 'my-cid');
      expect(body['clientSecret'], 'my-secret');
    });

    test('缺 ClientID / Secret：报错且不出网', () async {
      final client = Driver123OpenClient(
        additionWith(refreshToken: 'rt-4', localRefresh: true),
        dio: dio,
      );
      await expectLater(
        client.getAccessToken(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(adapter.hits, isEmpty);
    });

    test('令牌端点自身报 401 时直接抛错，不递归重试', () async {
      var tokenCalls = 0;
      apiResponse = (path, query, body) {
        if (path == '/api/v1/access_token') {
          tokenCalls++;
          return <String, dynamic>{'code': 401, 'message': 'client invalid'};
        }
        return envelope(null);
      };
      final client = Driver123OpenClient(
        additionWith(
          refreshToken: 'rt-r',
          clientId: 'cid',
          clientSecret: 'secret',
          localRefresh: true,
        ),
        dio: dio,
      );
      await expectLater(
        client.getAccessToken(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('client invalid'),
        )),
      );
      expect(tokenCalls, 1, reason: '令牌端点不能被 401 重试包装（会无限递归）');
    });
  });

  group('缺必填 refresh_token', () {
    test('默认配置（无 client 凭证）报可读错误且不出网', () async {
      final client = Driver123OpenClient(additionWith(refreshToken: ''), dio: dio);
      await expectLater(
        client.getAccessToken(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('refresh_token'),
        )),
      );
      expect(adapter.hits, isEmpty);
    });

    test('init() 也报同样的错', () async {
      final d = driverWith(additionWith(refreshToken: ''));
      await expectLater(
        d.init(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('refresh_token'),
        )),
      );
      expect(adapter.hits, isEmpty);
    });

    test('带缓存 access_token 时不刷新，直接 user/info 校验', () async {
      apiResponse = (path, query, body) =>
          path == '/api/v1/user/info' ? envelope(<String, dynamic>{'uid': 1}) : envelope(null);
      final d = driverWith(additionWith(refreshToken: '', accessToken: 'cached'));
      await d.init();
      expect(renewRefreshes, isEmpty);
      expect(apiPaths, ['/api/v1/user/info']);
      expect(adapter.hits.single.headers['authorization'], 'Bearer cached');
      expect(adapter.hits.single.headers['platform'], 'open_platform');
    });
  });

  group('列表解析', () {
    test('分页翻完 + type===1 判目录 + UTC+8 时间解析', () async {
      apiResponse = (path, query, body) {
        if (path != '/api/v2/file/list') return envelope(null);
        final last = query['lastFileId'];
        if (last == '0') {
          return envelope(<String, dynamic>{
            'last_file_id': 42,
            'file_list': [
              fileMap(1, 'dirA', type: 1),
              fileMap(2, 'a.mp3', size: 4096, updateAt: '2024-01-02 03:04:05'),
            ],
          });
        }
        return envelope(<String, dynamic>{
          'last_file_id': -1,
          'file_list': [fileMap(3, 'b.mp4', size: 8192)],
        });
      };

      final d = driverWith(additionWith());
      final items = await d.list('/');

      // 两页都翻了。
      final listHits =
          adapter.hits.where((h) => h.uri.path == '/api/v2/file/list').toList();
      expect(listHits.length, 2);
      expect(listHits[0].uri.queryParameters['lastFileId'], '0');
      expect(listHits[0].uri.queryParameters['limit'], '100');
      expect(listHits[0].uri.queryParameters['parentFileId'], '0');
      expect(listHits[0].uri.queryParameters['trashed'], 'false');
      expect(listHits[1].uri.queryParameters['lastFileId'], '42');
      // 必需请求头。
      expect(listHits[0].headers['authorization'], 'Bearer online-access');
      expect(listHits[0].headers['platform'], 'open_platform');

      expect(items.map((i) => i.name).toList(), ['dirA', 'a.mp3', 'b.mp4']);
      expect(items[0].isDir, isTrue, reason: 'type===1 是目录');
      expect(items[1].isDir, isFalse);
      expect(items[1].size, 4096);

      // UTC+8 墙钟 2024-01-02 03:04:05 → UTC 2024-01-01 19:04:05。
      expect(
        items[1].modified!.toUtc(),
        DateTime.utc(2024, 1, 1, 19, 4, 5),
      );
    });

    test('trashed !== 0 的条目被过滤掉', () async {
      apiResponse = (path, query, body) => envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [
              fileMap(1, 'keep.mp3'),
              <String, dynamic>{
                'fileId': 2,
                'filename': 'gone.mp3',
                'size': 1,
                'type': 2,
                'update_at': '2024-01-02 03:04:05',
                'trashed': 1,
              },
            ],
          });
      final items = await driverWith(additionWith()).list('/');
      expect(items.map((i) => i.name).toList(), ['keep.mp3']);
    });

    test('list 按路径逐层解析目录 id，根目录用 parentFileId=0', () async {
      final calls = <String>[];
      apiResponse = (path, query, body) {
        if (path != '/api/v2/file/list') return envelope(null);
        calls.add(query['parentFileId'] ?? '');
        if (query['parentFileId'] == '0') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(77, 'sub', type: 1)],
          });
        }
        return envelope(<String, dynamic>{
          'last_file_id': -1,
          'file_list': [fileMap(88, 'c.mp3')],
        });
      };
      final items = await driverWith(additionWith()).list('/sub');
      expect(calls, ['0', '77'], reason: '逐层解析：根 → sub');
      expect(items.single.name, 'c.mp3');
    });

    test('root_folder_id 作为起点 id', () async {
      final parents = <String>[];
      apiResponse = (path, query, body) {
        if (path != '/api/v2/file/list') return envelope(null);
        parents.add(query['parentFileId'] ?? '');
        return envelope(<String, dynamic>{'last_file_id': -1, 'file_list': <dynamic>[]});
      };
      await driverWith(additionWith(rootFolderId: '999')).list('/');
      expect(parents, ['999']);
    });
  });

  group('直链（get）', () {
    test('download_info 的 url 落到 rawUrl，size / modified 带上', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(555, 'a.mp3', size: 4096, updateAt: '2024-01-02 03:04:05')],
          });
        }
        if (path == '/api/v1/file/download_info') {
          return envelope(<String, dynamic>{
            'download_url': 'https://cdn.123pan.com/dl/a.mp3?auth=1',
          });
        }
        return envelope(null);
      };

      final item = await driverWith(additionWith()).get('/a.mp3');
      expect(item.isDir, isFalse);
      expect(item.name, 'a.mp3');
      expect(item.size, 4096);
      expect(item.rawUrl, 'https://cdn.123pan.com/dl/a.mp3?auth=1');
      expect(item.modified!.toUtc(), DateTime.utc(2024, 1, 1, 19, 4, 5));

      final dl = adapter.hits
          .firstWhere((h) => h.uri.path == '/api/v1/file/download_info');
      expect(dl.uri.queryParameters['fileId'], '555');
      expect(dl.headers['authorization'], 'Bearer online-access');
    });

    test('拿不到直链时抛真实原因，不返回无直链条目', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(555, 'a.mp3')],
          });
        }
        if (path == '/api/v1/file/download_info') {
          return <String, dynamic>{
            'code': 403,
            'message': '该文件无下载权限',
          };
        }
        return envelope(null);
      };
      await expectLater(
        driverWith(additionWith()).get('/a.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('该文件无下载权限'),
        )),
      );
    });

    test('目录走列表条目，不打 download_info', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(7, 'dirA', type: 1)],
          });
        }
        return envelope(null);
      };
      final item = await driverWith(additionWith()).get('/dirA');
      expect(item.isDir, isTrue);
      expect(item.rawUrl, isNull);
      expect(adapter.hits.any((h) => h.uri.path == '/api/v1/file/download_info'),
          isFalse);
    });
  });

  group('错误原文透传', () {
    test('code !== 0 时 message 含上游原文', () async {
      apiResponse = (path, query, body) => <String, dynamic>{
            'code': 1001,
            'message': '参数错误：parentFileId 非法',
          };
      final d = driverWith(additionWith());
      await expectLater(
        d.list('/'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('参数错误：parentFileId 非法'),
        )),
      );
    });

    test('mkdir / move / rename / remove 的错误原文同样透传', () async {
      apiResponse = (path, query, body) => <String, dynamic>{
            'code': 500,
            'message': '服务端拒绝',
          };
      final d = driverWith(additionWith());
      // 先让路径解析能成功，才能走到写端点。
      for (final f in <Future<void> Function()>[
        () => d.mkdir('/newdir'),
        () => d.move('/x', '/', 'x'),
        () => d.rename('/x', '/y'),
        () => d.remove('/x'),
      ]) {
        apiResponse = (path, query, body) {
          if (path == '/api/v2/file/list') {
            return envelope(<String, dynamic>{
              'last_file_id': -1,
              'file_list': [fileMap(9, 'x')],
            });
          }
          return <String, dynamic>{'code': 500, 'message': '服务端拒绝'};
        };
        await expectLater(
          f(),
          throwsA(isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            contains('服务端拒绝'),
          )),
        );
      }
    });
  });

  group('code === 401', () {
    test('刷新一次并重试一次，之后成功', () async {
      var listCalls = 0;
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          listCalls++;
          if (listCalls == 1) {
            return <String, dynamic>{'code': 401, 'message': 'token expired'};
          }
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(1, 'a.mp3')],
          });
        }
        return envelope(null);
      };

      final addition = additionWith(refreshToken: 'rt-x', accessToken: 'stale');
      final d = driverWith(addition);
      final items = await d.list('/');

      expect(items.single.name, 'a.mp3');
      expect(renewRefreshes, ['rt-x'], reason: '401 应触发一次刷新');
      expect(listCalls, 2, reason: '应重试一次');
      // 重试带上新令牌。
      final listHits =
          adapter.hits.where((h) => h.uri.path == '/api/v2/file/list').toList();
      expect(listHits[0].headers['authorization'], 'Bearer stale');
      expect(listHits[1].headers['authorization'], 'Bearer online-access');
    });

    test('重试后仍 401 → 只刷新一次，不无限循环', () async {
      var listCalls = 0;
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          listCalls++;
          return <String, dynamic>{'code': 401, 'message': 'token expired'};
        }
        return envelope(null);
      };
      await expectLater(
        driverWith(additionWith(refreshToken: 'rt-y', accessToken: 'stale')).list('/'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('token expired'),
        )),
      );
      expect(listCalls, 2, reason: '只重试一次');
      expect(renewRefreshes, ['rt-y'], reason: '只刷新一次');
    });
  });

  group('写操作请求形状', () {
    test('mkdir：POST /upload/v1/file/mkdir {parentID, name}', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(3, 'sub', type: 1)],
          });
        }
        return envelope(null);
      };
      await driverWith(additionWith()).mkdir('/sub/newdir');

      final hit = adapter.hits.last;
      expect(hit.method, 'POST');
      expect(hit.uri.path, '/upload/v1/file/mkdir');
      final body = jsonDecode(hit.body) as Map<String, dynamic>;
      expect(body['parentID'], '3');
      expect(body['name'], 'newdir');
    });

    test('rename 同目录：PUT /api/v1/file/name {fileId, fileName}', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(7, 'old.mp3')],
          });
        }
        return envelope(null);
      };
      await driverWith(additionWith()).rename('/old.mp3', '/new.mp3');

      final hit = adapter.hits.last;
      expect(hit.method, 'PUT');
      expect(hit.uri.path, '/api/v1/file/name');
      final body = jsonDecode(hit.body) as Map<String, dynamic>;
      expect(body['fileId'], 7);
      expect(body['fileName'], 'new.mp3');
    });

    test('rename 跨目录：降级为 move（改名时补一次 rename）', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          final parent = query['parentFileId'];
          if (parent == '0') {
            return envelope(<String, dynamic>{
              'last_file_id': -1,
              'file_list': [
                fileMap(7, 'old.mp3'),
                fileMap(9, 'dst', type: 1),
              ],
            });
          }
          return envelope(<String, dynamic>{'last_file_id': -1, 'file_list': <dynamic>[]});
        }
        return envelope(null);
      };
      await driverWith(additionWith()).rename('/old.mp3', '/dst/new.mp3');

      final move = adapter.hits
          .firstWhere((h) => h.uri.path == '/api/v1/file/move');
      expect(move.method, 'POST');
      final moveBody = jsonDecode(move.body) as Map<String, dynamic>;
      expect(moveBody['fileIDs'], [7]);
      expect(moveBody['toParentFileID'], '9');

      final name =
          adapter.hits.firstWhere((h) => h.uri.path == '/api/v1/file/name');
      expect((jsonDecode(name.body) as Map<String, dynamic>)['fileName'], 'new.mp3');
    });

    test('move：POST /api/v1/file/move {fileIDs:[id], toParentFileID}', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          final parent = query['parentFileId'];
          if (parent == '0') {
            return envelope(<String, dynamic>{
              'last_file_id': -1,
              'file_list': [fileMap(7, 'a.mp3'), fileMap(9, 'dst', type: 1)],
            });
          }
          return envelope(<String, dynamic>{'last_file_id': -1, 'file_list': <dynamic>[]});
        }
        return envelope(null);
      };
      await driverWith(additionWith()).move('/a.mp3', '/dst', 'a.mp3');

      final hit = adapter.hits.firstWhere((h) => h.uri.path == '/api/v1/file/move');
      final body = jsonDecode(hit.body) as Map<String, dynamic>;
      expect(body['fileIDs'], [7]);
      expect(body['toParentFileID'], '9');
      // 同名移动不该多发一次 rename。
      expect(adapter.hits.any((h) => h.uri.path == '/api/v1/file/name'), isFalse);
    });

    test('remove：POST /api/v1/file/trash {fileIDs:[id]}', () async {
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(7, 'a.mp3')],
          });
        }
        return envelope(null);
      };
      await driverWith(additionWith()).remove('/a.mp3');

      final hit = adapter.hits.last;
      expect(hit.method, 'POST');
      expect(hit.uri.path, '/api/v1/file/trash');
      expect((jsonDecode(hit.body) as Map<String, dynamic>)['fileIDs'], [7]);
    });

    test('copy 未实现 → 抛 not supported', () async {
      // 驱动里 copy 是 `=> throw`（同步抛出，不是返回失败的 Future），
      // 所以必须用 expect(() => ..., throwsA(...))；expectLater 会先求值
      // 表达式，同步异常会直接逃逸出去、把断言变成「未捕获异常」。
      expect(
        () => driverWith(additionWith()).copy('/a.mp3', '/dst', 'a.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('copy not supported'),
        )),
      );
      expect(adapter.hits, isEmpty);
    });

    test('写操作后清 path→id 缓存（重新解析目录）', () async {
      // 只数「解析路径」产生的列目录请求（parentFileId=0），
      // 列目录内容本身每次都会打，不参与缓存断言。
      var rootResolves = 0;
      apiResponse = (path, query, body) {
        if (path == '/api/v2/file/list') {
          if (query['parentFileId'] == '0') rootResolves++;
          return envelope(<String, dynamic>{
            'last_file_id': -1,
            'file_list': [fileMap(3, 'sub', type: 1)],
          });
        }
        return envelope(null);
      };
      final d = driverWith(additionWith());
      await d.list('/sub');
      final afterFirst = rootResolves;
      expect(afterFirst, 1, reason: '首次解析 /sub 需列一次根目录');

      await d.list('/sub');
      expect(rootResolves, afterFirst, reason: '缓存命中，第二次不再解析路径');

      await d.mkdir('/sub/newdir');
      await d.list('/sub');
      expect(rootResolves, greaterThan(afterFirst), reason: '写操作后缓存应被清空');
    });
  });

  group('时间解析（UTC+8）', () {
    test('"2006-01-02 15:04:05" 形式减 8 小时', () {
      expect(
        parse123OpenTime('2024-01-02 03:04:05')!.toUtc(),
        DateTime.utc(2024, 1, 1, 19, 4, 5),
      );
    });

    test('跨日边界', () {
      expect(
        parse123OpenTime('2024-03-01 00:00:00')!.toUtc(),
        DateTime.utc(2024, 2, 29, 16, 0, 0),
      );
    });

    test('带 T 但无时区的形态同样按 UTC+8 解释', () {
      expect(
        parse123OpenTime('2024-01-02T03:04:05')!.toUtc(),
        DateTime.utc(2024, 1, 1, 19, 4, 5),
      );
    });

    test('带显式时区偏移时按偏移解释', () {
      expect(
        parse123OpenTime('2024-01-02T03:04:05Z')!.toUtc(),
        DateTime.utc(2024, 1, 2, 3, 4, 5),
      );
      expect(
        parse123OpenTime('2024-01-02T03:04:05+08:00')!.toUtc(),
        DateTime.utc(2024, 1, 1, 19, 4, 5),
      );
    });

    test('空串 / 非法串返回 null', () {
      expect(parse123OpenTime(null), isNull);
      expect(parse123OpenTime(''), isNull);
      expect(parse123OpenTime('   '), isNull);
      expect(parse123OpenTime('not a date'), isNull);
    });
  });
}
