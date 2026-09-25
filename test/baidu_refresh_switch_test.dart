// 百度网盘令牌刷新开关的后端分支回归（99 §7.3.1）。
//
// 用户决策原话：「后端时也需要检查该开关，一旦打开就不使用online api逻辑
// 而使用自建百度应用的刷新逻辑。」本文件锁死该分支：
//   - local_refresh = false → 请求打到「在线续期地址」（online api），
//     绝不带 client_id / client_secret；
//   - local_refresh = true  → 请求打到百度 OAuth 端点（自建应用），
//     带 grant_type=refresh_token + client_id + client_secret，
//     绝不碰在线续期地址。
//
// 实现方式：自定义 dio HttpClientAdapter 拦截全部出站请求，按 host 分流到
// 本地 HttpServer；记录每次请求的完整 URL 供断言。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/baidu_netdisk_driver.dart';

/// 把出站请求按 host 分流：api.oplist.org → 本地续期服务器；
/// openapi.baidu.com → 本地 OAuth 服务器；其余 → 404。
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.renewServer, this.oauthServer);

  final HttpServer renewServer;
  final HttpServer oauthServer;
  final List<Uri> hits = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = Uri.parse(options.uri.toString());
    hits.add(uri);
    if (uri.host == 'api.oplist.org') {
      return _respond(renewServer, options);
    }
    if (uri.host == 'openapi.baidu.com') {
      return _respond(oauthServer, options);
    }
    return ResponseBody.fromString('not found', 404);
  }

  Future<ResponseBody> _respond(
    HttpServer server,
    RequestOptions options,
  ) async {
    final client = HttpClient();
    final target = Uri.parse(
        'http://127.0.0.1:${server.port}${options.uri.path}?${options.uri.query}');
    final req = await client.getUrl(target);
    final res = await req.close();
    final bytes = <int>[];
    await for (final c in res) {
      bytes.addAll(c);
    }
    client.close(force: true);
    final ct = res.headers.contentType?.mimeType ?? 'text/plain';
    return ResponseBody.fromBytes(bytes, res.statusCode, headers: {
      'content-type': [ct],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpServer renewServer;
  late HttpServer oauthServer;
  late _RoutingAdapter adapter;
  late Dio dio;
  var renewHits = 0;
  var oauthHits = 0;
  Map<String, String>? lastOauthQuery;

  setUp(() async {
    renewHits = 0;
    oauthHits = 0;
    lastOauthQuery = null;
    renewServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    renewServer.listen((req) {
      renewHits++;
      final refreshUi = req.uri.queryParameters['refresh_ui'] ?? '';
      if (req.method == 'GET' &&
          req.uri.path == '/baiduyun/renewapi' &&
          refreshUi.isNotEmpty) {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"access_token":"online-access","refresh_token":"online-refresh"}');
      } else {
        req.response
          ..statusCode = HttpStatus.badRequest
          ..write('bad renew request');
      }
      req.response.close();
    });
    oauthServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    oauthServer.listen((req) {
      oauthHits++;
      lastOauthQuery = req.uri.queryParameters;
      if (req.method == 'GET' &&
          req.uri.path == '/oauth/2.0/token' &&
          req.uri.queryParameters['grant_type'] == 'refresh_token') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"access_token":"local-access","refresh_token":"local-refresh"}');
      } else {
        req.response
          ..statusCode = HttpStatus.badRequest
          ..write('bad oauth request');
      }
      req.response.close();
    });
    adapter = _RoutingAdapter(renewServer, oauthServer);
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.httpClientAdapter = adapter;
  });

  tearDown(() async {
    await renewServer.close(force: true);
    await oauthServer.close(force: true);
  });

  group('local_refresh = false（开关关闭）→ 走 online api', () {
    test('请求打到在线续期地址，绝不带 client 凭证', () async {
      final client = BaiduClient(
        BaiduAddition(refreshToken: 'rt-1', clientId: 'cid', clientSecret: 'csecret'),
        dio: dio,
      );
      await client.refreshToken();
      expect(renewHits, 1, reason: '必须打在线续期端点');
      expect(oauthHits, 0, reason: '开关关闭时绝不走自建 OAuth');
      expect(client.accessToken, 'online-access');
      expect(client.addition.refreshToken, 'online-refresh');
      final q = adapter.hits.single.queryParameters;
      expect(q.containsKey('client_id'), isFalse);
      expect(q.containsKey('client_secret'), isFalse);
      expect(q['refresh_ui'], 'rt-1');
    });

    test('空 apiUrlAddress 回落到默认公共服务地址', () async {
      final client = BaiduClient(
        BaiduAddition(refreshToken: 'rt-2', apiUrlAddress: ''),
        dio: dio,
      );
      await client.refreshToken();
      expect(renewHits, 1);
      final hit = adapter.hits.single;
      expect(hit.host, 'api.oplist.org');
      expect(hit.path, '/baiduyun/renewapi');
    });

    test('在线 API 失败：错误原文透传，不落 OAuth 兜底', () async {
      // 续期服务器只认 refresh_ui 非空；给它一个空值触发 400 分支。
      final client = BaiduClient(
        BaiduAddition(refreshToken: ''),
        dio: dio,
      );
      await expectLater(
        client.refreshToken(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(oauthHits, 0, reason: '失败也不得切到本地 OAuth');
    });
  });

  group('local_refresh = true（开关打开）→ 走自建应用 OAuth', () {
    test('请求打到百度 OAuth 端点，带 client 凭证，不碰续期地址', () async {
      final client = BaiduClient(
        BaiduAddition(
          refreshToken: 'rt-3',
          clientId: 'my-cid',
          clientSecret: 'my-secret',
          localRefresh: true,
        ),
        dio: dio,
      );
      await client.refreshToken();
      expect(oauthHits, 1, reason: '必须打 OAuth 端点');
      expect(renewHits, 0, reason: '开关打开时绝不使用 online api');
      expect(client.accessToken, 'local-access');
      expect(client.addition.refreshToken, 'local-refresh');
      final q = lastOauthQuery!;
      expect(q['grant_type'], 'refresh_token');
      expect(q['refresh_token'], 'rt-3');
      expect(q['client_id'], 'my-cid');
      expect(q['client_secret'], 'my-secret');
    });

    test('缺 ClientID / ClientSecret：直接报错，不出网', () async {
      final client = BaiduClient(
        BaiduAddition(refreshToken: 'rt-4', localRefresh: true),
        dio: dio,
      );
      await expectLater(
        client.refreshToken(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(adapter.hits, isEmpty, reason: '缺凭证时不应发出任何请求');
    });
  });
}
