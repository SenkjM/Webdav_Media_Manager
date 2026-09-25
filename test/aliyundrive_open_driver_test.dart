// 阿里云盘开放平台驱动（aliyundrive_open）的行为回归。
//
// 上游参照：`localdev/OpenList-Worker/src/backend/drivers/aliyundrive_open/`
// （driver.ts + util.ts + types.ts，移植底稿）、
// `localdev/OpenList/drivers/aliyundrive_open/`（Go 版，语义兜底）。
//
// 锁定的事实（对齐任务书的六个覆盖点）：
//   1. 令牌刷新：在线 API 成功（含 `data` 包裹形态）；自定义地址失败后
//      **自动轮询到内置地址**；
//   2. 本地刷新分支：打 OAuth 端点、带 client_id / client_secret；
//   3. drive_id 解析：配置有值时直接用；无值时调 getDriveInfo 并按
//      drive_type 选对（含 resource → default → backup 兜底）；
//   4. 列表解析：`next_marker` 分页翻完、`type === 'folder'` 判目录；
//   5. 直链：getDownloadUrl 的 `url` 正确落到 `rawUrl`（含 `download_url` 兜底）；
//   6. 错误原文透传 + 401 刷新后重试一次（只一次，防死循环）。
//
// 实现方式：自定义 dio HttpClientAdapter 拦截全部出站请求，按**还原后的
// 真实 URL**决定响应，并记录 method / path / headers / body 供断言
// （12 §8.1 手法；不真连网络）。
//
// 出站域名不逐 host 分流：内置续期地址有 6 个，API 与 OAuth 又是两个
// host，用「handler 按 URL 决策」更直白。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/aliyundrive_open_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/driver_registry.dart';

/// 表单条目的 key（`CloudDriverFormItem` 是 sealed 基类，key 在具体子类上）。
String _formKey(CloudDriverFormItem item) => switch (item) {
      CloudDriverField(:final key) => key,
      CloudDriverSelectField(:final key) => key,
      CloudDriverAccountField(:final key) => key,
      CloudDriverSwitchField(:final key) => key,
    };

/// 一次出站请求的完整记录。
class _Hit {
  _Hit(this.method, this.url, this.headers, this.body);

  /// 原始的出站 URL（还原后的真实目标）。
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final String body;

  /// 折叠前的 host（`api.oplist.org` / `openapi.aliyundrive.com` ...）。
  String get host => url.host;

  /// 折叠前的 path。
  String get path => url.path;

  Map<String, dynamic> get json =>
      body.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(body) as Map);
}

/// 拦截全部出站请求，按**还原后的真实 URL**交给 [handler] 决定响应。
///
/// 不真的连本地 HttpServer：`handler` 直接返回 (状态码, 响应体)，
/// 出站域名（内置续期地址有 6 个，API 与 OAuth 又是两个 host）不必逐个分流。
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.handler);

  /// 响应工厂：真实出站请求 → (状态码, 响应体)。
  final (int, String) Function(_Hit hit) handler;

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
    final hit = _Hit(
      options.method,
      uri,
      <String, String>{
        for (final e in options.headers.entries)
          if (e.value != null) e.key.toLowerCase(): '${e.value}',
      },
      body,
    );
    hits.add(hit);

    final (status, payload) = handler(hit);
    return ResponseBody.fromString(payload, status, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RoutingAdapter adapter;
  late Dio dio;
  late List<_Hit> hits;

  /// 每个用例覆写它：真实出站请求 → (状态码, 响应体)。
  late (int, String) Function(_Hit hit) handler;

  AliyundriveOpenAddition addition({
    String refreshToken = 'rt-1',
    String driveType = 'resource',
    String driveId = '',
    String rootFolderId = 'root',
    String removeWay = 'trash',
    String apiUrlAddress = AliyundriveOpenClient.defaultRenewApi,
    bool localRefresh = false,
    String clientId = '',
    String clientSecret = '',
    String accessToken = '',
  }) =>
      AliyundriveOpenAddition(
        refreshToken: refreshToken,
        driveType: driveType,
        driveId: driveId,
        rootFolderId: rootFolderId,
        removeWay: removeWay,
        apiUrlAddress: apiUrlAddress,
        localRefresh: localRefresh,
        clientId: clientId,
        clientSecret: clientSecret,
        accessToken: accessToken,
      );

  setUp(() {
    handler = (hit) => (200, '{}');
    adapter = _RoutingAdapter((hit) => handler(hit));
    hits = adapter.hits;
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.httpClientAdapter = adapter;
  });

  // ─── 1. 令牌刷新：在线 API ─────────────────────────────────────

  group('令牌刷新 · 在线 API 中转', () {
    test('顶层 access_token / refresh_token 直接用', () async {
      handler = (hit) => (200, '{"access_token":"at-1","refresh_token":"rt-2"}');
      final client = AliyundriveOpenClient(addition(), dio: dio);
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-1');
      expect(client.addition.refreshToken, 'rt-2');
      expect(hits, hasLength(1), reason: '第一个地址就成功，不应继续轮询');
      final hit = hits.single;
      expect(hit.host, 'api.oplist.org');
      expect(hit.path, '/alicloud/renewapi');
      expect(hit.method, 'GET');
      final q = hit.url.queryParameters;
      expect(q['refresh_ui'], 'rt-1');
      expect(q['refresh_token'], 'rt-1');
      expect(q['server_use'], 'true');
      expect(q['driver_txt'], 'alicloud_qr');
    });

    test('令牌裹在 data 里也能取到', () async {
      handler = (hit) =>
          (200, '{"data":{"access_token":"at-data","refresh_token":"rt-data"}}');
      final client = AliyundriveOpenClient(addition(), dio: dio);
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-data');
      expect(client.addition.refreshToken, 'rt-data');
    });

    test('顶层缺 access_token 但 data 里有，照样成功', () async {
      handler = (hit) =>
          (200, '{"refresh_token":"rt-top","data":{"access_token":"at-nested"}}');
      final client = AliyundriveOpenClient(addition(), dio: dio);
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-nested');
      expect(client.addition.refreshToken, 'rt-top');
    });

    test('续期服务不轮换 refresh_token 时保留原值', () async {
      handler = (hit) => (200, '{"access_token":"at-only"}');
      final client = AliyundriveOpenClient(addition(refreshToken: 'rt-keep'), dio: dio);
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-only');
      expect(client.addition.refreshToken, 'rt-keep');
    });

    test('自定义地址失败 → 自动轮询到内置地址并成功', () async {
      const custom = 'https://my-renew.example.com/api';
      handler = (hit) {
        if (hit.host == 'my-renew.example.com') {
          return (500, '{"text":"custom endpoint down"}');
        }
        if (hit.host == 'api.oplist.org' && hit.path == '/alicloud/renewapi') {
          return (500, '{"text":"first builtin down"}');
        }
        if (hit.host == 'api.oplist.org' && hit.path == '/ali_open/token') {
          return (200, '{"data":{"access_token":"at-fallback","refresh_token":"rt-fallback"}}');
        }
        return (404, 'not found');
      };

      final client = AliyundriveOpenClient(
        addition(apiUrlAddress: custom),
        dio: dio,
      );
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-fallback');
      expect(client.addition.refreshToken, 'rt-fallback');
      expect(hits, hasLength(3), reason: '自定义 → 内置 1 → 内置 2，第三个成功');
      expect(hits[0].host, 'my-renew.example.com');
      expect(hits[1].path, '/alicloud/renewapi');
      expect(hits[2].path, '/ali_open/token');
      // 每一次都必须带上同样的参数（逐地址重试不丢参数）。
      for (final hit in hits) {
        expect(hit.url.queryParameters['refresh_ui'], 'rt-1');
        expect(hit.url.queryParameters['driver_txt'], 'alicloud_qr');
      }
    });

    test('自定义地址与自定义 drive_type 一样不影响 driver_txt（固定 QR 分支）', () async {
      handler = (hit) => (200, '{"access_token":"at-qr"}');
      final client = AliyundriveOpenClient(addition(driveType: 'backup'), dio: dio);
      await client.refreshAccessToken();
      expect(hits.single.url.queryParameters['driver_txt'], 'alicloud_qr');
    });

    test('在线全失败 → 落到直连 OAuth（带内置 client_id）', () async {
      handler = (hit) {
        if (hit.host == 'openapi.aliyundrive.com') {
          expect(hit.path, '/oauth/access_token');
          return (200, '{"access_token":"at-oauth","refresh_token":"rt-oauth"}');
        }
        return (500, '{"text":"online down"}');
      };
      final client = AliyundriveOpenClient(addition(), dio: dio);
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-oauth');
      expect(client.addition.refreshToken, 'rt-oauth');
      // 6 个在线候选全试过，第 7 次才打 OAuth。
      final onlineHits = hits.where((h) => h.host != 'openapi.aliyundrive.com');
      expect(onlineHits, hasLength(AliyundriveOpenClient.builtinRenewApis.length));
      final oauth = hits.last;
      expect(oauth.method, 'POST');
      expect(oauth.json['grant_type'], 'refresh_token');
      expect(oauth.json['client_id'], AliyundriveOpenClient.defaultClientId);
      expect(oauth.json.containsKey('client_secret'), isFalse,
          reason: '空 client_secret 不进 body');
    });

    test('全部失败 → 抛出带排查指引的聚合错误', () async {
      handler = (hit) => (500, '{"text":"boom"}');
      final client = AliyundriveOpenClient(addition(), dio: dio);

      await expectLater(
        client.refreshAccessToken(),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('All token refresh strategies failed'),
              contains('refresh_token'),
              contains('api_url_address'),
              contains('client_id'),
            ),
          ),
        ),
      );
    });

    test('refresh_token 为空 → 直接报错，不出网', () async {
      final client = AliyundriveOpenClient(addition(refreshToken: '  '), dio: dio);
      await expectLater(
        client.refreshAccessToken(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(hits, isEmpty, reason: '缺令牌时不应发出任何请求');
    });
  });

  // ─── 2. 令牌刷新：本地（直连 OAuth）────────────────────────────

  group('令牌刷新 · 本地直连 OAuth', () {
    test('打 OAuth 端点，带 grant_type / client_id / client_secret', () async {
      handler = (hit) => (200, '{"access_token":"at-local","refresh_token":"rt-local"}');
      final client = AliyundriveOpenClient(
        addition(
          refreshToken: 'rt-3',
          localRefresh: true,
          clientId: 'my-cid',
          clientSecret: 'my-secret',
        ),
        dio: dio,
      );
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-local');
      expect(client.addition.refreshToken, 'rt-local');
      expect(hits, hasLength(1), reason: '本地刷新不应碰在线续期地址');
      final hit = hits.single;
      expect(hit.host, 'openapi.aliyundrive.com');
      expect(hit.path, '/oauth/access_token');
      expect(hit.method, 'POST');
      expect(hit.headers['content-type'], contains('application/json'));
      final body = hit.json;
      expect(body['grant_type'], 'refresh_token');
      expect(body['refresh_token'], 'rt-3');
      expect(body['client_id'], 'my-cid');
      expect(body['client_secret'], 'my-secret');
    });

    test('本地刷新不给驱动配置里的 api_url_address 发请求（开关停用语义）', () async {
      handler = (hit) => (200, '{"access_token":"at-local"}');
      final client = AliyundriveOpenClient(
        addition(
          localRefresh: true,
          clientId: 'cid',
          clientSecret: 'sec',
          apiUrlAddress: 'https://my-renew.example.com/api',
        ),
        dio: dio,
      );
      await client.refreshAccessToken();

      expect(hits, hasLength(1));
      expect(hits.single.host, 'openapi.aliyundrive.com');
    });

    test('本地刷新缺 client_id → 用内置缺省值，成功即返回', () async {
      handler = (hit) => (200, '{"access_token":"at-default-cid"}');
      final client = AliyundriveOpenClient(
        addition(localRefresh: true, clientSecret: 'sec'),
        dio: dio,
      );
      await client.refreshAccessToken();

      expect(client.accessToken, 'at-default-cid');
      expect(hits, hasLength(1), reason: '本地刷新只试 OAuth 一次');
      expect(hits.single.json['client_id'], AliyundriveOpenClient.defaultClientId);
    });

    test('本地刷新失败 → 绝不回落到在线续期地址（开关打开即不用 online api）', () async {
      handler = (hit) {
        if (hit.host == 'openapi.aliyundrive.com') {
          return (400, '{"code":"InvalidParameter","message":"bad client"}');
        }
        fail('本地刷新开启时不得请求在线续期地址：${hit.url}');
      };
      final client = AliyundriveOpenClient(
        addition(localRefresh: true, clientId: 'cid', clientSecret: 'sec'),
        dio: dio,
      );

      await expectLater(
        client.refreshAccessToken(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(hits.every((h) => h.host == 'openapi.aliyundrive.com'), isTrue);
    });

    test('OAuth 报错原文被带进最终异常', () async {
      handler = (hit) {
        if (hit.host == 'openapi.aliyundrive.com') {
          return (400, '{"code":"InvalidParameter","message":"refresh token expired"}');
        }
        return (500, '{"text":"online down"}');
      };
      final client = AliyundriveOpenClient(
        addition(localRefresh: true, clientId: 'cid', clientSecret: 'sec'),
        dio: dio,
      );

      await expectLater(
        client.refreshAccessToken(),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            contains('refresh_token'),
          ),
        ),
      );
    });
  });

  // ─── 3. drive_id 解析 ────────────────────────────────────────

  group('drive_id 解析', () {
    test('配置里有 drive_id → 直接用，不调 getDriveInfo', () async {
      handler = (hit) => fail('不应发出请求，实际打到 ${hit.url}');
      final client = AliyundriveOpenClient(
        addition(driveId: 'cfg-drive', accessToken: 'at'),
        dio: dio,
      );
      expect(await client.resolveDriveId(), 'cfg-drive');
      expect(hits, isEmpty);
    });

    test('无 drive_id → 调 getDriveInfo，按 drive_type=resource 选 resource_drive_id', () async {
      handler = (hit) {
        expect(hit.path, '/adrive/v1.0/user/getDriveInfo');
        expect(hit.method, 'POST');
        expect(hit.headers['authorization'], 'Bearer at-1');
        return (
          200,
          '{"default_drive_id":"d-default","resource_drive_id":"d-resource",'
              '"backup_drive_id":"d-backup"}'
        );
      };
      final client = AliyundriveOpenClient(
        addition(driveType: 'resource', accessToken: 'at-1'),
        dio: dio,
      );
      expect(await client.resolveDriveId(), 'd-resource');
    });

    test('drive_type=default 选 default_drive_id', () async {
      handler = (hit) => (
        200,
        '{"default_drive_id":"d-default","resource_drive_id":"d-resource",'
            '"backup_drive_id":"d-backup"}'
      );
      final client = AliyundriveOpenClient(
        addition(driveType: 'default', accessToken: 'at-1'),
        dio: dio,
      );
      expect(await client.resolveDriveId(), 'd-default');
    });

    test('drive_type=backup 选 backup_drive_id', () async {
      handler = (hit) => (
        200,
        '{"default_drive_id":"d-default","resource_drive_id":"d-resource",'
            '"backup_drive_id":"d-backup"}'
      );
      final client = AliyundriveOpenClient(
        addition(driveType: 'backup', accessToken: 'at-1'),
        dio: dio,
      );
      expect(await client.resolveDriveId(), 'd-backup');
    });

    test('所选类型缺 id → 按 resource → default → backup 顺序兜底', () async {
      handler = (hit) => (200, '{"default_drive_id":"d-default"}');
      final client = AliyundriveOpenClient(
        // 要 backup，但响应里没有 backup_drive_id → 兜底到 default。
        addition(driveType: 'backup', accessToken: 'at-1'),
        dio: dio,
      );
      expect(await client.resolveDriveId(), 'd-default');
    });

    test('三个 drive_id 都为空 → 报可读错误', () async {
      handler = (hit) => (200, '{}');
      final client = AliyundriveOpenClient(
        addition(accessToken: 'at-1'),
        dio: dio,
      );
      await expectLater(
        client.resolveDriveId(),
        throwsA(isA<CloudDriverException>()),
      );
    });
  });

  // ─── 4. 列表解析 ─────────────────────────────────────────────

  group('列表解析', () {
    /// 组织分页响应：第 1 页给 next_marker，第 2 页不给。
    (int, String) paged(_Hit hit) {
      final body = hit.json;
      expect(hit.path, '/adrive/v1.0/openFile/list');
      expect(hit.method, 'POST');
      expect(body['drive_id'], 'd-1');
      expect(body['limit'], 100);
      expect(body['order_by'], 'updated_at');
      expect(body['order_direction'], 'DESC');
      if (body['parent_file_id'] != 'root') {
        return (200, '{"items":[]}');
      }
      if (body['marker'] == null) {
        return (
          200,
          '{"items":[{"file_id":"f-1","name":"movies","type":"folder"},'
              '{"file_id":"f-2","name":"a.mp4","type":"file","size":1234}],'
              '"next_marker":"m-2"}'
        );
      }
      expect(body['marker'], 'm-2');
      return (
        200,
        '{"items":[{"file_id":"f-3","name":"b.mkv","type":"file","size":5678}]}'
      );
    }

    test('next_marker 分页翻完，folder 判目录 / 时间与大小映射正确', () async {
      handler = paged;
      final client = AliyundriveOpenClient(
        addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      final files = await client.listFiles('root');

      expect(files.map((f) => f.name), ['movies', 'a.mp4', 'b.mkv']);
      expect(files[0].isDir, isTrue);
      expect(files[1].isDir, isFalse);
      expect(files[2].isDir, isFalse);
      expect(files[1].size, 1234);
      // 第 1 次是根目录（触发分页），第 2 次带 marker。
      final listHits = hits.where((h) => h.path.endsWith('/openFile/list')).toList();
      expect(listHits, hasLength(2));
      expect(listHits[0].json.containsKey('marker'), isFalse,
          reason: '首页不带 marker');
      expect(listHits[1].json['marker'], 'm-2');
    });

    test('ISO8601 updated_at / created_at 解析成时间，缺 updated_at 回落到 created_at', () async {
      handler = (hit) => (
        200,
        '{"items":['
            '{"file_id":"f-1","name":"x","type":"folder",'
            '"updated_at":"2024-01-02T03:04:05.000Z","created_at":"2020-01-01T00:00:00.000Z"},'
            '{"file_id":"f-2","name":"y","type":"file","created_at":"2021-06-07T08:09:10.000Z"},'
            '{"file_id":"f-3","name":"z","type":"file"}'
            ']}'
      );
      final client = AliyundriveOpenClient(
        addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      final files = await client.listFiles('root');

      expect(files[0].modified!.toUtc(),
          DateTime.utc(2024, 1, 2, 3, 4, 5));
      // 没有 updated_at → 回落 created_at。
      expect(files[1].modified!.toUtc(),
          DateTime.utc(2021, 6, 7, 8, 9, 10));
      // 两个都没有 → null（不伪造时间）。
      expect(files[2].modified, isNull);
    });

    test('列表报 UserNotAllowedAccessDrive → 以 resource 重新解析 drive_id 再重试一次', () async {
      var listCalls = 0;
      handler = (hit) {
        if (hit.path.endsWith('/user/getDriveInfo')) {
          return (
            200,
            '{"default_drive_id":"d-default","resource_drive_id":"d-resource"}'
          );
        }
        listCalls++;
        if (listCalls == 1) {
          // 首次用的是配置里的 backup 盘 id → 被拒。
          expect(hit.json['drive_id'], 'd-backup');
          return (403, '{"code":"UserNotAllowedAccessDrive","message":"no access"}');
        }
        expect(hit.json['drive_id'], 'd-resource',
            reason: '自愈后必须用 resource 类型的 drive_id 重试');
        return (200, '{"items":[{"file_id":"f-1","name":"ok","type":"file"}]}');
      };
      final client = AliyundriveOpenClient(
        addition(driveType: 'backup', driveId: 'd-backup', accessToken: 'at-1'),
        dio: dio,
      );
      final files = await client.listFiles('root');

      expect(files.single.name, 'ok');
      expect(listCalls, 2, reason: '只重试一次');
    });
  });

  // ─── 5. 直链 ─────────────────────────────────────────────────

  group('直链', () {
    test('getDownloadUrl 的 url 落到 rawUrl', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/get')) {
          return (
            200,
            '{"file_id":"f-1","name":"a.mp4","type":"file","size":4096,'
                '"updated_at":"2024-01-02T03:04:05.000Z"}'
          );
        }
        if (hit.path.endsWith('/openFile/getDownloadUrl')) {
          expect(hit.json['driver_id'], isNull);
          expect(hit.json['expire_sec'], 14400);
          return (200, '{"url":"https://cdn.example.com/a.mp4?sig=1"}');
        }
        if (hit.path.endsWith('/openFile/list')) {
          return (
            200,
            '{"items":[{"file_id":"f-1","name":"a.mp4","type":"file","size":4096}]}'
          );
        }
        return (404, 'not found');
      };

      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      final item = await driver.get('/a.mp4');

      expect(item.name, 'a.mp4');
      expect(item.isDir, isFalse);
      expect(item.size, 4096);
      expect(item.rawUrl, 'https://cdn.example.com/a.mp4?sig=1');
      expect(item.modified!.toUtc(), DateTime.utc(2024, 1, 2, 3, 4, 5));
    });

    test('url 缺失时回落到 download_url', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/get')) {
          return (200, '{"file_id":"f-1","name":"a.mp4","type":"file"}');
        }
        if (hit.path.endsWith('/openFile/getDownloadUrl')) {
          return (200, '{"download_url":"https://cdn.example.com/alt.mp4"}');
        }
        return (200, '{"items":[{"file_id":"f-1","name":"a.mp4","type":"file"}]}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      expect((await driver.get('/a.mp4')).rawUrl,
          'https://cdn.example.com/alt.mp4');
    });

    test('拿不到直链 → 抛 CloudDriverException（不返回无直链条目）', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/get')) {
          return (200, '{"file_id":"f-1","name":"a.mp4","type":"file"}');
        }
        if (hit.path.endsWith('/openFile/getDownloadUrl')) {
          return (200, '{}');
        }
        return (200, '{"items":[{"file_id":"f-1","name":"a.mp4","type":"file"}]}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await expectLater(
        driver.get('/a.mp4'),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            contains('未返回直链'),
          ),
        ),
      );
    });

    test('目录条目不带直链，直接返回 isDir', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/get')) {
          return (200, '{"file_id":"f-9","name":"movies","type":"folder"}');
        }
        if (hit.path.endsWith('/openFile/getDownloadUrl')) {
          fail('目录不该请求直链');
        }
        return (200, '{"items":[{"file_id":"f-9","name":"movies","type":"folder"}]}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      final item = await driver.get('/movies');
      expect(item.isDir, isTrue);
      expect(item.rawUrl, isNull);
    });
  });

  // ─── 6. 错误原文透传 + 401 重试一次 ───────────────────────────

  group('错误透传与 401 重试', () {
    test('非 2xx 的上游原文被带进 CloudDriverException（含端点）', () async {
      handler = (hit) => (
        400,
        '{"code":"InvalidParameter","message":"The resource drive_id is invalid."}'
      );
      final client = AliyundriveOpenClient(
        addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );

      await expectLater(
        client.listFiles('root'),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('InvalidParameter'),
              contains('The resource drive_id is invalid.'),
              contains('/openFile/list'),
            ),
          ),
        ),
      );
    });

    test('401 → 刷新令牌并重试一次（成功后返回结果）', () async {
      var listCalls = 0;
      handler = (hit) {
        if (hit.host == 'api.oplist.org') {
          return (200, '{"access_token":"at-2","refresh_token":"rt-2"}');
        }
        listCalls++;
        if (listCalls == 1) {
          expect(hit.headers['authorization'], 'Bearer at-1');
          return (401, '{"code":"AccessTokenExpired","message":"expired"}');
        }
        expect(hit.headers['authorization'], 'Bearer at-2',
            reason: '重试必须用刷新后的令牌');
        return (200, '{"items":[{"file_id":"f-1","name":"ok","type":"file"}]}');
      };
      final client = AliyundriveOpenClient(
        addition(driveId: 'd-1', refreshToken: 'rt-1', accessToken: 'at-1'),
        dio: dio,
      );
      final files = await client.listFiles('root');

      expect(files.single.name, 'ok');
      expect(listCalls, 2);
      expect(client.accessToken, 'at-2');
      expect(hits.where((h) => h.host == 'api.oplist.org'), hasLength(1));
    });

    test('持续 401 只重试一次，不死循环，且把原文抛出', () async {
      var listCalls = 0;
      handler = (hit) {
        if (hit.host == 'api.oplist.org') {
          return (200, '{"access_token":"at-2","refresh_token":"rt-2"}');
        }
        listCalls++;
        return (401, '{"code":"AccessTokenExpired","message":"still expired"}');
      };
      final client = AliyundriveOpenClient(
        addition(driveId: 'd-1', refreshToken: 'rt-1', accessToken: 'at-1'),
        dio: dio,
      );

      await expectLater(
        client.listFiles('root'),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            contains('still expired'),
          ),
        ),
      );
      expect(listCalls, 2, reason: '只重试一次（防死循环）');
      expect(hits.where((h) => h.host == 'api.oplist.org'), hasLength(1),
          reason: '只刷新一次令牌');
    });

    test('令牌轮换经 onTokenUpdate 透出（access_token + refresh_token 两个都存）', () async {
      Map<String, dynamic>? patch;
      handler = (hit) => (200, '{"access_token":"at-new","refresh_token":"rt-new"}');
      final client = AliyundriveOpenClient(
        addition(),
        onTokenUpdate: (p) => patch = p,
        dio: dio,
      );
      await client.refreshAccessToken();

      expect(patch, isNotNull);
      expect(patch!['access_token'], 'at-new');
      expect(patch!['refresh_token'], 'rt-new');
    });
  });

  // ─── 驱动层：init / 路径解析 / 写操作 ─────────────────────────

  group('驱动层', () {
    /// 一份「根目录里有 movies 目录，movies 里有 a.mp4」的目录树响应。
    (int, String) tree(_Hit hit) {
      final body = hit.json;
      switch (hit.path) {
        case '/adrive/v1.0/user/getDriveInfo':
          return (200, '{"resource_drive_id":"d-1"}');
        case '/adrive/v1.0/openFile/list':
          if (body['parent_file_id'] == 'root') {
            return (
              200,
              '{"items":[{"file_id":"dir-movies","name":"movies","type":"folder"},'
                  '{"file_id":"f-top","name":"top.mp4","type":"file","size":10}]}'
            );
          }
          if (body['parent_file_id'] == 'dir-movies') {
            return (
              200,
              '{"items":[{"file_id":"f-a","name":"a.mp4","type":"file","size":20}]}'
            );
          }
          return (200, '{"items":[]}');
        case '/adrive/v1.0/openFile/get':
          return (
            200,
            '{"file_id":"f-a","name":"a.mp4","type":"file","size":20}'
          );
        case '/adrive/v1.0/openFile/getDownloadUrl':
          return (200, '{"url":"https://cdn.example.com/a.mp4"}');
        default:
          return (200, '{}');
      }
    }

    test('init() 校验令牌并解析出 drive_id', () async {
      handler = tree;
      final driver = AliyundriveOpenDriver(
        addition: addition(refreshToken: 'rt-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.init();

      expect(driver.client.driveId, 'd-1');
      // 有缓存的 access_token 就不刷新；只打 getDriveInfo。
      expect(hits.map((h) => h.path), ['/adrive/v1.0/user/getDriveInfo']);
    });

    test('init() 无缓存令牌 → 先刷新再解析 drive_id', () async {
      handler = (hit) {
        if (hit.host == 'api.oplist.org') {
          return (200, '{"access_token":"at-new","refresh_token":"rt-new"}');
        }
        return (200, '{"resource_drive_id":"d-1"}');
      };
      final driver = AliyundriveOpenDriver(addition: addition(), dio: dio);
      await driver.init();

      expect(hits.first.host, 'api.oplist.org');
      expect(hits.last.path, '/adrive/v1.0/user/getDriveInfo');
      expect(driver.addition.accessToken, 'at-new');
    });

    test('init() 令牌无效 → 抛出真实原因（保存时据此拒绝落库）', () async {
      handler = (hit) {
        if (hit.host == 'api.oplist.org') {
          return (200, '{"access_token":"at-bad","refresh_token":"rt-bad"}');
        }
        return (401, '{"code":"AccessTokenInvalid","message":"token is invalid"}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(refreshToken: 'rt-1', accessToken: 'at-bad'),
        dio: dio,
      );
      await expectLater(driver.init(), throwsA(isA<CloudDriverException>()));
    });

    test('list() 逐层解析路径：/movies 用父目录里的 file_id 列子目录', () async {
      handler = tree;
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      final items = await driver.list('/movies');

      expect(items.single.name, 'a.mp4');
      expect(items.single.size, 20);
      // 第一次列 root（解析 movies），第二次列 dir-movies。
      final listHits = hits.where((h) => h.path.endsWith('/openFile/list')).toList();
      expect(listHits, hasLength(2));
      expect(listHits[0].json['parent_file_id'], 'root');
      expect(listHits[1].json['parent_file_id'], 'dir-movies');
    });

    test('list() 路径缓存生效：第二次同路径不重复解析', () async {
      handler = tree;
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.list('/movies');
      final afterFirst = hits.length;
      await driver.list('/movies');
      // 第二次仍要列一次 dir-movies（列目录本身不可省），但不再列 root 解析。
      final second = hits.sublist(afterFirst);
      expect(second, hasLength(1));
      expect(second.single.json['parent_file_id'], 'dir-movies');
    });

    test('list() 路径不存在 → 报可读错误', () async {
      handler = tree;
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await expectLater(
        driver.list('/nope'),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            contains("'nope' not found"),
          ),
        ),
      );
    });

    test('remove() 默认走回收站 /openFile/recyclebin', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        if (hit.path.endsWith('/openFile/recyclebin')) {
          expect(hit.json['drive_id'], 'd-1');
          expect(hit.json['file_id'], 'f-a');
          return (200, '{}');
        }
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1', removeWay: 'trash'),
        dio: dio,
      );
      await driver.remove('/movies/a.mp4');
      expect(
        hits.map((h) => h.path),
        contains('/adrive/v1.0/openFile/recyclebin'),
      );
    });

    test('remove() remove_way=delete 走 /openFile/delete', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1', removeWay: 'delete'),
        dio: dio,
      );
      await driver.remove('/movies/a.mp4');
      expect(
        hits.map((h) => h.path),
        contains('/adrive/v1.0/openFile/delete'),
      );
      expect(
        hits.map((h) => h.path),
        isNot(contains('/adrive/v1.0/openFile/recyclebin')),
      );
    });

    test('mkdir() 用父目录 id + type folder', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        if (hit.path.endsWith('/openFile/create')) {
          final b = hit.json;
          expect(b['parent_file_id'], 'dir-movies');
          expect(b['name'], 'newdir');
          expect(b['type'], 'folder');
          expect(b['check_name_mode'], 'refuse');
          return (200, '{}');
        }
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.mkdir('/movies/newdir');
    });

    test('rename() 同目录走 /openFile/update(name)', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        if (hit.path.endsWith('/openFile/update')) {
          expect(hit.json['file_id'], 'f-a');
          expect(hit.json['name'], 'b.mp4');
          expect(hit.json['check_name_mode'], 'refuse');
          return (200, '{}');
        }
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.rename('/movies/a.mp4', '/movies/b.mp4');
      expect(hits.map((h) => h.path), contains('/adrive/v1.0/openFile/update'));
    });

    test('rename() 跨目录降级为 move + rename', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        if (hit.path.endsWith('/openFile/move')) {
          expect(hit.json['file_id'], 'f-a');
          expect(hit.json['to_parent_file_id'], 'root');
          expect(hit.json['check_name_mode'], 'refuse');
          return (200, '{}');
        }
        if (hit.path.endsWith('/openFile/update')) {
          expect(hit.json['name'], 'b.mp4');
          return (200, '{}');
        }
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.rename('/movies/a.mp4', '/b.mp4');
      final paths = hits.map((h) => h.path).toList();
      expect(paths, contains('/adrive/v1.0/openFile/move'));
      expect(paths, contains('/adrive/v1.0/openFile/update'));
    });

    test('move() 不改名时只调 /openFile/move', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.move('/movies/a.mp4', '/', 'a.mp4');
      final paths = hits.map((h) => h.path).toList();
      expect(paths, contains('/adrive/v1.0/openFile/move'));
      expect(paths, isNot(contains('/adrive/v1.0/openFile/update')),
          reason: '名字没变就不该多发一次 rename');
    });

    test('copy() 用 auto_rename: true', () async {
      handler = (hit) {
        if (hit.path.endsWith('/openFile/list')) return tree(hit);
        if (hit.path.endsWith('/openFile/copy')) {
          expect(hit.json['file_id'], 'f-a');
          expect(hit.json['to_parent_file_id'], 'root');
          expect(hit.json['auto_rename'], isTrue);
          return (200, '{}');
        }
        return (200, '{}');
      };
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      await driver.copy('/movies/a.mp4', '/', 'a.mp4');
      expect(hits.map((h) => h.path), contains('/adrive/v1.0/openFile/copy'));
    });

    test('get("/") 返回目录占位，不出网', () async {
      handler = (hit) => fail('根目录不该发出请求，实际打到 ${hit.url}');
      final driver = AliyundriveOpenDriver(
        addition: addition(driveId: 'd-1', accessToken: 'at-1'),
        dio: dio,
      );
      final item = await driver.get('/');
      expect(item.isDir, isTrue);
      expect(hits, isEmpty);
    });
  });

  // ─── spec 自描述 ─────────────────────────────────────────────

  group('spec 自描述', () {
    const spec = AliyundriveOpenSpec();

    test('typeId / 显示名', () {
      expect(spec.typeId, 'aliyundrive_open');
      expect(spec.displayName, '阿里云盘开放平台');
    });

    test('能力位：list | read | mkdir | move | copy | delete，不给 write', () {
      expect(
        spec.capabilities,
        AccountCaps.list |
            AccountCaps.read |
            AccountCaps.mkdir |
            AccountCaps.move |
            AccountCaps.copy |
            AccountCaps.delete,
      );
      expect(AccountCaps.has(spec.capabilities, AccountCaps.write), isFalse);
    });

    test('表单字段齐全且顺序正确', () {
      expect(
        spec.form.map(_formKey).toList(),
        [
          'refresh_token',
          'drive_type',
          'api_url_address',
          'local_refresh',
          'client_id',
          'client_secret',
          'remove_way',
          'root_folder_id',
        ],
      );
      // access_token 只作缓存，绝不进表单。
      expect(spec.form.map(_formKey), isNot(contains('access_token')));
      // 排序与上传相关字段不进表单。
      for (final key in const ['order_by', 'order_direction', 'chunk_size']) {
        expect(spec.form.map(_formKey), isNot(contains(key)));
      }
    });

    test('refresh_token 必填且密文', () {
      final f = spec.form.whereType<CloudDriverField>()
          .firstWhere((f) => f.key == 'refresh_token');
      expect(f.required, isTrue);
      expect(f.obscure, isTrue);
    });

    test('drive_type 下拉选项与默认值', () {
      final f = spec.form.whereType<CloudDriverSelectField>()
          .firstWhere((f) => f.key == 'drive_type');
      expect(f.options, [
        ('resource', '资源盘'),
        ('default', '默认盘'),
        ('backup', '备份盘'),
      ]);
      expect(f.defaultValue, 'resource');
      expect(f.required, isTrue);
    });

    test('remove_way 下拉选项与默认值', () {
      final f = spec.form.whereType<CloudDriverSelectField>()
          .firstWhere((f) => f.key == 'remove_way');
      expect(f.options, [
        ('trash', '移入回收站'),
        ('delete', '彻底删除'),
      ]);
      expect(f.defaultValue, 'trash');
    });

    test('开关极性：api_url_address 开了本地刷新就停用，client 字段开了才显示', () {
      final fields = spec.form.whereType<CloudDriverField>().toList();
      final api = fields.firstWhere((f) => f.key == 'api_url_address');
      final cid = fields.firstWhere((f) => f.key == 'client_id');
      final secret = fields.firstWhere((f) => f.key == 'client_secret');

      expect(api.disabledWhenSwitch, 'local_refresh');
      expect(api.enabledWhenSwitch, isNull);
      expect(cid.visibleWhenSwitch, 'local_refresh');
      expect(secret.visibleWhenSwitch, 'local_refresh');
      expect(secret.obscure, isTrue);
      // 关（默认）→ 续期地址可用；开 → 停用。
      expect(spec.switchValue('local_refresh', const {}), isFalse);
    });

    test('联动引用的开关确实存在于 form 里（防拼写错导致永远 false）', () {
      final switchKeys =
          spec.form.whereType<CloudDriverSwitchField>().map((s) => s.key).toSet();
      expect(switchKeys, contains('local_refresh'));
      for (final f in spec.form.whereType<CloudDriverField>()) {
        for (final ref in [
          f.visibleWhenSwitch,
          f.enabledWhenSwitch,
          f.disabledWhenSwitch,
        ]) {
          if (ref != null) expect(switchKeys, contains(ref));
        }
      }
    });

    test('默认值：api_url_address / root_folder_id', () {
      final fields = spec.form.whereType<CloudDriverField>().toList();
      expect(
        fields.firstWhere((f) => f.key == 'api_url_address').defaultValue,
        'https://api.oplist.org/alicloud/renewapi',
      );
      expect(
        fields.firstWhere((f) => f.key == 'root_folder_id').defaultValue,
        'root',
      );
    });

    test('create() 把 config 还原成 Addition', () {
      final driver = spec.create(<String, dynamic>{
        'refresh_token': 'rt',
        'drive_type': 'backup',
        'drive_id': 'd-9',
        'root_folder_id': 'rid',
        'remove_way': 'delete',
        'api_url_address': 'https://x.example.com',
        'local_refresh': true,
        'client_id': 'cid',
        'client_secret': 'sec',
        'access_token': 'at',
      });
      expect(driver, isA<AliyundriveOpenDriver>());
      final a = (driver as AliyundriveOpenDriver).addition;
      expect(a.refreshToken, 'rt');
      expect(a.driveType, 'backup');
      expect(a.driveId, 'd-9');
      expect(a.rootFolderId, 'rid');
      expect(a.removeWay, 'delete');
      expect(a.apiUrlAddress, 'https://x.example.com');
      expect(a.localRefresh, isTrue);
      expect(a.clientId, 'cid');
      expect(a.clientSecret, 'sec');
      expect(a.accessToken, 'at');
    });

    test('Addition.fromJson / toJson 往返（含缺键默认值）', () {
      final a = AliyundriveOpenAddition.fromJson(<String, dynamic>{});
      expect(a.refreshToken, '');
      expect(a.driveType, 'resource');
      expect(a.driveId, '');
      expect(a.rootFolderId, 'root');
      expect(a.removeWay, 'trash');
      expect(a.apiUrlAddress, 'https://api.oplist.org/alicloud/renewapi');
      expect(a.localRefresh, isFalse);
      expect(a.accessToken, '');

      final round = AliyundriveOpenAddition.fromJson(a.toJson());
      expect(round.toJson(), a.toJson());
    });

    test('注册表里能按 typeId 查到（账号表单类型下拉接入点）', () {
      expect(cloudDriverSpec('aliyundrive_open'), isA<AliyundriveOpenSpec>());
    });
  });
}
