// 115 网盘开放平台驱动（115open）的行为回归。
//
// 上游参照：`localdev/OpenList-Worker/src/backend/drivers/115open`
// （driver.ts + util.ts + types.ts，移植底稿）、
// `localdev/OpenList/drivers/115_open`（Go 版，语义兜底）。
//
// 锁定的事实：
//   - 令牌刷新打 `passportapi.115.com/open/refreshToken`，form-urlencoded 带
//     refresh_token（**不是 JSON**），access / refresh 两个 token 都落库；
//   - 空 refresh_token 直接报「缺少 refresh_token（必填）」，不出网；
//   - 鉴权错误（state=false 且 code 99 / 401xx）→ 刷新后重试**一次**（防死循环）；
//   - 列表 `GET /open/ufile/files` 翻完分页，`fc === '0'` 判目录，
//     `upt`（Unix 秒）→ DateTime；
//   - 直链走 `POST /open/ufile/downurl`，取 `[fid].url.url` 落 `rawUrl`，
//     `rawHeaders` 带 115 的 UA；
//   - **链接缓存**：同一 fid 第二次取直链不再打 downurl（省 406 配额）；
//   - 错误原文（含 code 430004 对象不存在）透传成 CloudDriverException；
//   - 路径解析：folder/get_info 报 430004 / 990002 时回退逐层列目录。
//
// 实现方式：自定义 dio HttpClientAdapter 拦住全部出站请求（不连本地
// HttpServer，直接由 `handler` 返回响应体），并记录 method / 完整 URL /
// headers / body 供断言；出站 host（proapi / passportapi）保持原样可见。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/open115_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/driver_registry.dart';

/// 一次出站请求的完整记录（host / path 都是**折叠前的真实值**）。
class _Hit {
  _Hit(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  String get host => uri.host;
  String get path => uri.path;
  Map<String, String> get form => Uri.splitQueryString(body);

  @override
  String toString() => '$method $uri [body=$body]';
}

/// 拦截全部出站请求：不真的连服务器，[handler] 直接给出响应体。
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.handler);

  /// 响应工厂：一次出站请求 → (状态码, 响应体)。
  final (int, String) Function(_Hit hit) handler;

  final List<_Hit> hits = <_Hit>[];

  /// 设为非空则所有请求都抛连接错误（模拟 proapi.115.com 不可达）。
  String? failWith;

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
    final hit = _Hit(options.method, uri, <String, String>{
      for (final e in options.headers.entries)
        if (e.value != null) e.key.toLowerCase(): '${e.value}',
    }, body);
    hits.add(hit);

    final reason = failWith;
    if (reason != null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: reason,
      );
    }

    final (status, payload) = _handler!(hit);
    return ResponseBody.fromString(payload, status, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// 当前用例的响应工厂（真实请求 → (状态码, JSON 体)）。
late (int, String) Function(_Hit hit)? _handler;

/// 成功包裹：`{state: true, code: 0, message: 'ok', data: ...}`。
String _okJson(Object? data, {int code = 0}) => jsonEncode(<String, dynamic>{
      'state': true,
      'code': code,
      'message': 'ok',
      'data': data,
    });

/// 失败包裹（鉴权错误 / 上游业务错误）。
String _errJson(Object code, String message) => jsonEncode(<String, dynamic>{
      'state': false,
      'code': code,
      'message': message,
      'data': null,
    });

/// 列表响应（data + count）。
String _listJson(List<Map<String, dynamic>> files, int count) =>
    jsonEncode(<String, dynamic>{
      'state': true,
      'code': 0,
      'message': 'ok',
      'data': files,
      'count': count,
    });

/// 令牌刷新响应。
String _refreshJson(String access, String refresh) =>
    _okJson({'access_token': access, 'refresh_token': refresh});

/// 列表条目（`fc: '0'` = 目录，`'1'` = 文件）。
Map<String, dynamic> _entry({
  required String fid,
  required String fn,
  String fc = '1',
  String? pc,
  int upt = 1700000000,
  int fs = 1024,
  String pid = '0',
}) =>
    <String, dynamic>{
      'fid': fid,
      'pid': pid,
      'fc': fc,
      'fn': fn,
      'pc': pc ?? 'pc-$fid',
      'upt': upt,
      'fs': fs,
    };

void main() {
  late _RoutingAdapter adapter;
  late Dio dio;
  late List<Map<String, dynamic>> tokenUpdates;

  setUp(() {
    _handler = (hit) => (200, _okJson(<String, dynamic>{}));
    adapter = _RoutingAdapter((hit) => _handler!(hit));
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.httpClientAdapter = adapter;
    tokenUpdates = <Map<String, dynamic>>[];
  });

  Open115Driver driverWith({
    String refreshToken = 'rt-1',
    String accessToken = '',
    String rootId = '0',
    int pageSize = 200,
    double limitRate = 0,
  }) =>
      Open115Driver(
        addition: Open115Addition(
          refreshToken: refreshToken,
          accessToken: accessToken,
          rootId: rootId,
          pageSize: pageSize,
          limitRate: limitRate,
        ),
        onTokenUpdate: (patch) => tokenUpdates.add(patch),
        dio: dio,
      );

  List<_Hit> hitsFor(String host) =>
      adapter.hits.where((h) => h.host == host).toList();

  group('spec 与能力遮罩', () {
    test('typeId 是 115open / 显示名 / 注册表登记', () {
      const spec = Open115Spec();
      expect(spec.typeId, '115open');
      expect(spec.displayName, '115网盘');
      expect(cloudDriverSpec('115open'), isA<Open115Spec>());
    });

    test('能力位 = list|read|mkdir|move|copy|delete，且不给 write', () {
      const spec = Open115Spec();
      final caps = spec.capabilities;
      expect(AccountCaps.has(caps, AccountCaps.list), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.read), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.mkdir), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.move), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.copy), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.delete), isTrue);
      // 上传已砍（99 §4.2.1）
      expect(AccountCaps.has(caps, AccountCaps.write), isFalse);
    });

    test('表单：refresh_token 必填密文；root_id / page_size / limit_rate 带默认值', () {
      const spec = Open115Spec();
      final fields = spec.form.whereType<CloudDriverField>().toList();
      expect(fields.map((f) => f.key).toList(),
          <String>['refresh_token', 'root_id', 'page_size', 'limit_rate']);

      final refresh = fields.firstWhere((f) => f.key == 'refresh_token');
      expect(refresh.required, isTrue);
      expect(refresh.obscure, isTrue);

      expect(fields.firstWhere((f) => f.key == 'root_id').defaultValue, '0');
      expect(fields.firstWhere((f) => f.key == 'page_size').defaultValue, '200');
      expect(fields.firstWhere((f) => f.key == 'limit_rate').defaultValue, '0');

      // access_token 只作缓存，不进表单。
      expect(fields.map((f) => f.key), isNot(contains('access_token')));
      // 排序字段不进表单（客户端自己排序）
      expect(fields.map((f) => f.key), isNot(contains('order_by')));
      expect(fields.map((f) => f.key), isNot(contains('order_direction')));
    });

    test('表单只有文本字段，没有开关（无联动极性风险）', () {
      const spec = Open115Spec();
      expect(spec.form.whereType<CloudDriverSwitchField>(), isEmpty);
    });
  });

  group('令牌刷新', () {
    test('打 passportapi 端点、form-urlencoded 带 refresh_token，两个 token 都更新', () async {
      _handler = (hit) => hit.path == '/open/refreshToken'
          ? (200, _refreshJson('at-new', 'rt-new'))
          : (200, _okJson(<String, dynamic>{}));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-old'),
        onTokenUpdate: (patch) => tokenUpdates.add(patch),
        dio: dio,
      );
      await client.refreshToken();

      expect(adapter.hits.length, 1);
      final hit = adapter.hits.single;
      expect(hit.host, 'passportapi.115.com');
      expect(hit.path, '/open/refreshToken');
      expect(hit.method, 'POST');
      expect(hit.headers['content-type'], contains('application/x-www-form-urlencoded'));
      // **form-urlencoded，不是 JSON**：JSON 解析必然失败（body 不是合法 JSON
      // 才对），refresh_token 以 form 字段出现、而不是 JSON 键。
      expect(() => jsonDecode(hit.body), throwsFormatException,
          reason: 'body 不应是 JSON（form-urlencoded 才对）');
      expect(hit.form['refresh_token'], 'rt-old');

      expect(client.accessToken, 'at-new');
      expect(client.refreshTokenValue, 'rt-new');
      // 两个 token 都经 onTokenUpdate 持久化
      expect(tokenUpdates, hasLength(1));
      expect(tokenUpdates.single,
          {'access_token': 'at-new', 'refresh_token': 'rt-new'});
    });

    test('空 refresh_token → 抛「115 网盘缺少 refresh_token（必填）」且不出网', () async {
      final client = Open115Client(
        Open115Addition(refreshToken: ''),
        onTokenUpdate: (patch) => tokenUpdates.add(patch),
        dio: dio,
      );
      await expectLater(
        client.refreshToken(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('115 网盘缺少 refresh_token（必填）'),
        )),
      );
      expect(adapter.hits, isEmpty, reason: '缺必填项时不应发出任何请求');
    });

    test('刷新失败：错误原文（code + message + 提示）透传', () async {
      _handler = (hit) => (200, _errJson(4010101, 'refresh token 无效'));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-bad'),
        dio: dio,
      );
      await expectLater(
        client.refreshToken(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('4010101'), contains('refresh token 无效')),
        )),
      );
    });

    test('响应缺 refresh_token（只回 access_token）也算失败', () async {
      _handler = (hit) => (200, jsonEncode(<String, dynamic>{
            'state': true,
            'code': 0,
            'message': 'ok',
            'data': {'access_token': 'at-only'},
          }));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1'),
        dio: dio,
      );
      await expectLater(
        client.refreshToken(),
        throwsA(isA<CloudDriverException>()),
      );
    });
  });

  group('鉴权错误 → 刷新后重试一次', () {
    test('code 99 且 state=false：先刷新，再用新 token 重打一次原请求', () async {
      var listCalls = 0;
      _handler = (hit) {
        if (hit.path == '/open/refreshToken') {
          return (200, _refreshJson('at-fresh', 'rt-fresh'));
        }
        if (hit.path == '/open/ufile/files') {
          listCalls++;
          if (listCalls == 1) return (200, _errJson(99, '登录失效，请重新登录'));
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-stale'),
        onTokenUpdate: (patch) => tokenUpdates.add(patch),
        dio: dio,
      );
      final page = await client.getFiles(cid: '0', limit: 200, offset: 0);

      expect(page.files.single.fn, 'a.mp3');
      expect(listCalls, 2, reason: '鉴权失败必须重试一次');
      expect(hitsFor('passportapi.115.com'), hasLength(1));
      // 重试用的是新 access_token
      final retry = adapter.hits.last;
      expect(retry.headers['authorization'], 'Bearer at-fresh');
      expect(tokenUpdates.single['access_token'], 'at-fresh');
    });

    test('code 401xxx 同样触发刷新重试', () async {
      var calls = 0;
      _handler = (hit) {
        if (hit.path == '/open/refreshToken') {
          return (200, _refreshJson('at2', 'rt2'));
        }
        calls++;
        return calls == 1
            ? (200, _errJson(4010102, 'token 过期'))
            : (200, _okJson({'ok': true}));
      };
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-stale'),
        dio: dio,
      );
      await client.request('${Open115Client.apiBase}/open/user/info');
      expect(calls, 2);
    });

    test('刷新后仍失败 → 抛错且**不再**刷新（防死循环）', () async {
      _handler = (hit) {
        if (hit.path == '/open/refreshToken') {
          return (200, _refreshJson('at2', 'rt2'));
        }
        return (200, _errJson(99, '登录失效'));
      };
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-stale'),
        dio: dio,
      );
      await expectLater(
        client.userInfo(),
        throwsA(isA<CloudDriverException>()),
      );
      // 只刷了一次：若无限递归会打很多次
      expect(hitsFor('passportapi.115.com'), hasLength(1));
      expect(hitsFor('proapi.115.com'), hasLength(2));
    });

    test('非鉴权错误（如 430004）不触发刷新', () async {
      _handler = (hit) =>
          (200, _errJson(open115ErrObjectNotFound, '对象不存在'));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-1'),
        dio: dio,
      );
      await expectLater(
        client.userInfo(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(hitsFor('passportapi.115.com'), isEmpty);
    });

    test('鉴权失败时 Authorization 头带 Bearer access_token', () async {
      _handler = (hit) => (200, _okJson({'user_id': 1}));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-abc'),
        dio: dio,
      );
      await client.userInfo();
      expect(adapter.hits.single.headers['authorization'], 'Bearer at-abc');
    });
  });

  group('列表解析', () {
    test('分页翻完：按 count 推进，直到取满', () async {
      const pageSize = 2;
      final offsets = <String>[];
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          final offset = int.parse(hit.uri.queryParameters['offset'] ?? '0');
          offsets.add('$offset');
          // offset 0: [dir, a] count 3；offset 2: [b] count 3
          if (offset == 0) {
            return (
              200,
              _listJson([
                _entry(fid: 'd1', fn: '目录', fc: '0', pc: ''),
                _entry(fid: 'f1', fn: 'a.mp3'),
              ], 3)
            );
          }
          return (200, _listJson([_entry(fid: 'f2', fn: 'b.mp3')], 3));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final d = driverWith(pageSize: pageSize);
      final items = await d.list('/');

      expect(offsets, <String>['0', '2']);
      expect(items.map((i) => i.name).toList(), <String>['目录', 'a.mp3', 'b.mp3']);
    });

    test('请求参数：cid / limit / offset / asc=1 / o=file_name / showDir=1', () async {
      _handler = (hit) => (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3')], 1));
      final d = driverWith(pageSize: 200, rootId: '7');
      await d.list('/');

      final q = adapter.hits.single.uri.queryParameters;
      expect(adapter.hits.single.path, '/open/ufile/files');
      expect(q['cid'], '7', reason: '根路径用 root_id');
      expect(q['limit'], '200');
      expect(q['offset'], '0');
      expect(q['asc'], '1');
      expect(q['o'], 'file_name');
      expect(q['showDir'], '1');
    });

    test("fc === '0' 是目录（字符串判定），其余是文件", () async {
      _handler = (hit) => (200, _listJson([
            _entry(fid: 'd1', fn: 'dir', fc: '0', pc: ''),
            _entry(fid: 'f1', fn: 'file.mp4', fc: '1'),
          ], 2));
      final items = await driverWith().list('/');
      expect(items[0].isDir, isTrue);
      expect(items[1].isDir, isFalse);
    });

    test('upt（Unix 秒）→ DateTime 正确；fs → size', () async {
      _handler = (hit) => (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', upt: 1700000000, fs: 4096)], 1));
      final item = (await driverWith().list('/')).single;
      expect(item.size, 4096);
      expect(item.modified,
          DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('upt 为 0 / 缺失 → modified 为 null（不造出 1970 年时间）', () async {
      _handler = (hit) => (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', upt: 0)], 1));
      final item = (await driverWith().list('/')).single;
      expect(item.modified, isNull);
    });

    test('目录列表条目不带直链（rawUrl 为 null，直链只在 get 里取）', () async {
      _handler = (hit) => (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3')], 1));
      final item = (await driverWith().list('/')).single;
      expect(item.rawUrl, isNull);
    });

    test('返回空页立即结束（不空转）', () async {
      var calls = 0;
      _handler = (hit) {
        calls++;
        return (200, _listJson(<Map<String, dynamic>>[], 0));
      };
      final items = await driverWith().list('/');
      expect(items, isEmpty);
      expect(calls, 1);
    });
  });

  group('直链', () {
    test('downurl 的 url.url 落到 rawUrl，rawHeaders 含 115 的 UA', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pc: 'pick-1')], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          return (200, _okJson({
            'f1': {
              'file_name': 'a.mp3',
              'file_size': 1024,
              'pick_code': 'pick-1',
              'url': {'url': 'https://cdn.115.com/a.mp3?sig=1'},
            }
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final item = await driverWith().get('/a.mp3');

      expect(item.rawUrl, 'https://cdn.115.com/a.mp3?sig=1');
      expect(item.rawHeaders,
          {'User-Agent': Open115Client.open115UserAgent});
      expect(item.rawHeaders!['User-Agent'], contains('OpenList/425.6.30'));
      expect(item.isDir, isFalse);
      expect(item.size, 1024);
    });

    test('downurl 请求形状：POST + form 带 pick_code + UA 头', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pc: 'pick-9')], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          return (200, _okJson({
            'f1': {'url': {'url': 'https://cdn.115.com/a.mp3'}}
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().get('/a.mp3');

      final hit = adapter.hits.firstWhere((h) => h.path == '/open/ufile/downurl');
      expect(hit.method, 'POST');
      expect(hit.host, 'proapi.115.com');
      expect(hit.form['pick_code'], 'pick-9');
      expect(hit.headers['user-agent'], Open115Client.open115UserAgent);
    });

    test('直链在「文件不存在」时不静默：抛真实原因', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson(<Map<String, dynamic>>[], 0));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await expectLater(
        driverWith().get('/missing.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('115 网盘文件不存在'),
        )),
      );
    });

    test('downurl 返回空 url.url → 抛可读错误，不产出空直链条目', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pc: 'pick-1')], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          return (200, _okJson({
            'f1': {'url': {'url': ''}}
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await expectLater(
        driverWith().get('/a.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('直链'),
        )),
      );
    });

    test('406 配额用尽：原文透传（不吞掉、不返回无直链条目）', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pc: 'pick-1')], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          return (200, _errJson(406, '请求过于频繁，请稍后再试'));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await expectLater(
        driverWith().get('/a.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('406'), contains('请求过于频繁')),
        )),
      );
    });

    test('根路径 get 返回目录条目', () async {
      final item = await driverWith().get('/');
      expect(item.isDir, isTrue);
      expect(adapter.hits, isEmpty, reason: '根路径不该发请求');
    });
  });

  group('链接缓存（省 115 的 downurl 每日配额）', () {
    test('同一 fid 第二次取直链不再请求 downurl', () async {
      var downCalls = 0;
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pc: 'pick-1')], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          downCalls++;
          return (200, _okJson({
            'f1': {
              'url': {'url': 'https://cdn.115.com/a.mp3?sig=$downCalls'}
            }
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final d = driverWith();
      final first = await d.get('/a.mp3');
      final second = await d.get('/a.mp3');

      expect(downCalls, 1, reason: '同一 文件+UA 必须复用链接');
      expect(first.rawUrl, second.rawUrl);
      expect(second.rawUrl, 'https://cdn.115.com/a.mp3?sig=1');
    });

    test('缓存 key 带 UA：换 UA 会重新取（Go LinkCacheMode=UA 语义）', () async {
      var downCalls = 0;
      _handler = (hit) {
        if (hit.path == '/open/ufile/downurl') {
          downCalls++;
          return (200, _okJson({
            'f1': {
              'url': {'url': 'https://cdn.115.com/a.mp3?sig=$downCalls'}
            }
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final client = Open115Client(Open115Addition(refreshToken: 'rt-1'), dio: dio);
      final file = Open115File(
        fid: 'f1',
        pid: '0',
        fc: '1',
        fn: 'a.mp3',
        pc: 'pick-1',
        upt: 1700000000,
        fs: 1024,
      );
      await client.linkFor(file, ua: 'UA-A');
      await client.linkFor(file, ua: 'UA-B');
      expect(downCalls, 2, reason: 'UA 不同 → 不同缓存槽');
    });

    test('默认 TTL 是 30 分钟；过期后重新请求 downurl', () async {
      expect(Open115Client.defaultLinkTtl, const Duration(minutes: 30));

      var downCalls = 0;
      _handler = (hit) {
        if (hit.path == '/open/ufile/downurl') {
          downCalls++;
          return (200, _okJson({
            'f1': {
              'url': {'url': 'https://cdn.115.com/a.mp3?sig=$downCalls'}
            }
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      // 注入极短 TTL，避免测试里真的等 30 分钟。
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1'),
        dio: dio,
        linkTtl: const Duration(milliseconds: 1),
      );
      final file = Open115File(
        fid: 'f1',
        pid: '0',
        fc: '1',
        fn: 'a.mp3',
        pc: 'pick-1',
        upt: 1700000000,
        fs: 1024,
      );
      final first = await client.linkFor(file);
      expect(downCalls, 1);
      // TTL 已过 → 缓存失效，重新请求
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = await client.linkFor(file);
      expect(downCalls, 2, reason: '过期后必须重新取直链');
      expect(first, isNot(second));
      expect(second, endsWith('sig=2'));
    });

    test('未过期的缓存不被清掉（cachedLink 命中同一值）', () async {
      _handler = (hit) => (200, _okJson({
            'f1': {
              'url': {'url': 'https://cdn.115.com/a.mp3'}
            }
          }));
      final client = Open115Client(Open115Addition(refreshToken: 'rt-1'), dio: dio);
      client.cacheLink('f1', Open115Client.open115UserAgent, 'https://cdn.115.com/a.mp3');
      expect(client.cachedLink('f1', Open115Client.open115UserAgent),
          'https://cdn.115.com/a.mp3');
      // 没缓存的 key 返回 null，不发请求。
      expect(client.cachedLink('nope', Open115Client.open115UserAgent), isNull);
      expect(adapter.hits, isEmpty);
    });
  });

  group('错误原文透传', () {
    test('430004 对象不存在：code 与 message 都在异常里', () async {
      _handler = (hit) => (200, _errJson(open115ErrObjectNotFound, '文件不存在'));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-1'),
        dio: dio,
      );
      await expectLater(
        client.userInfo(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('430004'), contains('文件不存在')),
        )),
      );
    });

    test('上游把错误包在 JSON 里（HTTP 500 + 业务 message）：原文透传', () async {
      _handler = (hit) => (200, _errJson(500, '<html>gateway error</html>'));
      final client = Open115Client(
        Open115Addition(refreshToken: 'rt-1', accessToken: 'at-1'),
        dio: dio,
      );
      await expectLater(
        client.userInfo(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('500'), contains('gateway error')),
        )),
      );
    });
  });

  group('路径解析', () {
    test('folder/get_info 报 430004 → 回退逐层列目录', () async {
      final calls = <String>[];
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          calls.add('get_info');
          return (200, _errJson(open115ErrObjectNotFound, '文件不存在'));
        }
        if (hit.path == '/open/ufile/files') {
          calls.add('files:${hit.uri.queryParameters['cid']}');
          final cid = hit.uri.queryParameters['cid'];
          if (cid == '0') {
            return (200, _listJson([
              _entry(fid: 'd1', fn: 'Movies', fc: '0', pc: ''),
            ], 1));
          }
          if (cid == 'd1') {
            return (200, _listJson([
              _entry(fid: 'd2', fn: '2024', fc: '0', pc: ''),
            ], 1));
          }
          if (cid == 'd2') {
            // /Movies/2024 的内容：最终 list() 应返回这里的东西。
            return (200, _listJson([
              _entry(fid: 'f-1', fn: 'a.mp4', fc: '1', pc: 'pc-1'),
            ], 1));
          }
          return (200, _listJson(<Map<String, dynamic>>[], 0));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final d = driverWith();
      final items = await d.list('/Movies/2024');
      // 逐层解析：/Movies → d1，再列 d1 定位 2024 → d2，最后列 d2 的内容
      expect(calls,
          containsAllInOrder(<String>['get_info', 'files:0', 'files:d1']));
      expect(items.single.name, 'a.mp4');
    });

    test('folder/get_info 报 990002（参数错误）→ 同样回退', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _errJson(open115ErrInvalidParams, '参数错误'));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([
            _entry(fid: 'd1', fn: 'Movies', fc: '0', pc: ''),
          ], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final items = await driverWith().list('/Movies');
      expect(items.single.name, 'Movies');
    });

    test('folder/get_info 成功时一次性解析，不再逐层列目录', () async {
      var listCalls = 0;
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _okJson({'file_id': 'd9', 'file_name': 'Movies'}));
        }
        if (hit.path == '/open/ufile/files') {
          listCalls++;
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp4')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final items = await driverWith().list('/Movies');
      expect(listCalls, 1, reason: '只列一次目标目录');
      expect(adapter.hits.first.path, '/open/folder/get_info');
      expect(adapter.hits.first.form['path'], '/Movies');
      expect(adapter.hits.first.method, 'POST');
      expect(items.single.name, 'a.mp4');
    });

    test('其余错误（如 500）不透传成「回退」——原样抛出', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') return (200, _errJson(500, '服务器错误'));
        return (200, _listJson(<Map<String, dynamic>>[], 0));
      };
      await expectLater(
        driverWith().list('/Movies'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('服务器错误'),
        )),
      );
    });

    test('目录不存在 → 可读错误', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _errJson(open115ErrObjectNotFound, '文件不存在'));
        }
        return (200, _listJson(<Map<String, dynamic>>[], 0));
      };
      await expectLater(
        driverWith().list('/Nope'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('115 网盘目录不存在'),
        )),
      );
    });

    test('resolveFile 列父目录按 fn 匹配（列表接口才给 pick_code）', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _okJson({'file_id': 'd1', 'file_name': 'Movies'}));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([
            _entry(fid: 'f1', fn: 'a.mp4', pc: 'pick-a'),
          ], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          return (200, _okJson({
            'f1': {'url': {'url': 'https://cdn.115.com/a.mp4'}}
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final item = await driverWith().get('/Movies/a.mp4');
      expect(item.name, 'a.mp4');
      expect(item.rawUrl, 'https://cdn.115.com/a.mp4');
    });

    test('uri 编码的名字也能匹配（decoded 名兜底）', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _errJson(open115ErrObjectNotFound, '文件不存在'));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([
            _entry(fid: 'f1', fn: '中文 名.mp4', pc: 'pick-c'),
          ], 1));
        }
        if (hit.path == '/open/ufile/downurl') {
          return (200, _okJson({
            'f1': {'url': {'url': 'https://cdn.115.com/c.mp4'}}
          }));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final item = await driverWith().get('/%E4%B8%AD%E6%96%87%20%E5%90%8D.mp4');
      expect(item.name, '中文 名.mp4');
      expect(item.rawUrl, 'https://cdn.115.com/c.mp4');
    });

    test('路径 → fid 缓存：同一目录第二次解析不再打 get_info', () async {
      var getInfoCalls = 0;
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          getInfoCalls++;
          return (200, _okJson({'file_id': 'd1', 'file_name': 'Movies'}));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson(<Map<String, dynamic>>[], 0));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      final d = driverWith();
      await d.list('/Movies');
      await d.list('/Movies');
      expect(getInfoCalls, 1);
    });
  });

  group('写操作', () {
    test('mkdir：解析父目录 + POST /open/folder/add {pid, file_name}', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _okJson({'file_id': 'd1', 'file_name': 'Movies'}));
        }
        if (hit.path == '/open/folder/add') {
          return (200, _okJson({'file_id': 'dnew', 'file_name': 'NewDir'}));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().mkdir('/Movies/NewDir');
      final hit = adapter.hits
          .firstWhere((h) => h.path == '/open/folder/add');
      expect(hit.method, 'POST');
      expect(hit.form['pid'], 'd1');
      expect(hit.form['file_name'], 'NewDir');
    });

    test('rename 同目录：POST /open/ufile/update {file_id, file_name}', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'old.mp3', pc: 'p1')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().rename('/old.mp3', '/new.mp3');
      final hit = adapter.hits.firstWhere((h) => h.path == '/open/ufile/update');
      expect(hit.form['file_id'], 'f1');
      expect(hit.form['file_name'], 'new.mp3');
    });

    test('rename 跨目录：降级为 move + rename', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _okJson({'file_id': 'd2', 'file_name': 'Other'}));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'old.mp3', pc: 'p1')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().rename('/old.mp3', '/Other/new.mp3');
      final move = adapter.hits.firstWhere((h) => h.path == '/open/ufile/move');
      expect(move.form['file_ids'], 'f1');
      expect(move.form['to_cid'], 'd2');
      final update =
          adapter.hits.firstWhere((h) => h.path == '/open/ufile/update');
      expect(update.form['file_id'], 'f1');
      expect(update.form['file_name'], 'new.mp3');
    });

    test('remove：POST /open/ufile/delete {file_ids, parent_id}', () async {
      _handler = (hit) {
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pid: 'd1', pc: 'p1')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().remove('/a.mp3');
      final hit = adapter.hits.firstWhere((h) => h.path == '/open/ufile/delete');
      expect(hit.form['file_ids'], 'f1');
      expect(hit.form['parent_id'], 'd1');
    });

    test('move：POST /open/ufile/move {file_ids, to_cid}', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _okJson({'file_id': 'd9', 'file_name': 'Dest'}));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f1', fn: 'a.mp3', pc: 'p1')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().move('/a.mp3', '/Dest', 'a.mp3');
      final hit = adapter.hits.firstWhere((h) => h.path == '/open/ufile/move');
      expect(hit.form['file_ids'], 'f1');
      expect(hit.form['to_cid'], 'd9');
    });

    test('copy：参数顺序是 (目标 pid, 源 fileId) —— 上游顺序，别接反', () async {
      _handler = (hit) {
        if (hit.path == '/open/folder/get_info') {
          return (200, _okJson({'file_id': 'd9', 'file_name': 'Dest'}));
        }
        if (hit.path == '/open/ufile/files') {
          return (200, _listJson([_entry(fid: 'f-src', fn: 'a.mp3', pc: 'p1')], 1));
        }
        return (200, _okJson(<String, dynamic>{}));
      };
      await driverWith().copy('/a.mp3', '/Dest', 'a.mp3');
      final hit = adapter.hits.firstWhere((h) => h.path == '/open/ufile/copy');
      expect(hit.form['pid'], 'd9', reason: '第一个参数是目标目录 id');
      expect(hit.form['file_id'], 'f-src', reason: '第二个参数是源文件 id');
      expect(hit.form['no_dupli'], '1');
    });
  });

  group('init 与令牌校验', () {
    test('有缓存 access_token：先 user/info 校验；page_size 夹到 1150', () async {
      final seen = <String>[];
      _handler = (hit) {
        seen.add(hit.path);
        return (200, _okJson({'user_id': 1}));
      };
      final d = driverWith(accessToken: 'at-cached', pageSize: 99999);
      await d.init();
      expect(seen, <String>['/open/user/info']);
      expect(d.client.addition.pageSize, 1150);
      // 校验用缓存 token，不刷新
      expect(hitsFor('passportapi.115.com'), isEmpty);
    });

    test('无 access_token：先刷新再校验', () async {
      final seen = <String>[];
      _handler = (hit) {
        seen.add(hit.uri.host + hit.path);
        if (hit.path == '/open/refreshToken') return (200, _refreshJson('at-new', 'rt-new'));
        return (200, _okJson({'user_id': 1}));
      };
      await driverWith().init();
      expect(seen.first, 'passportapi.115.com/open/refreshToken');
      expect(seen.last, 'proapi.115.com/open/user/info');
    });

    test('page_size 越小越界 → 回落到 200（Go Init 语义）', () async {
      _handler = (hit) => (200, _okJson({'user_id': 1}));
      final d = driverWith(accessToken: 'at-1', pageSize: 0);
      await d.init();
      expect(d.client.addition.pageSize, 200);
    });

    test('令牌无效：错误里带 115 的原文与可读提示', () async {
      _handler = (hit) => (200, _errJson(4010101, 'access_token 无效'));
      await expectLater(
        driverWith(accessToken: 'at-bad').init(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('4010101'),
            contains('access_token 无效'),
            contains('access_token / refresh_token 有效'),
          ),
        )),
      );
    });

    test('网络不通：提示 proapi.115.com 可能无法从当前部署环境访问', () async {
      // 让 adapter 对所有出站请求抛连接错误。
      adapter.failWith = 'Connection refused';
      await expectLater(
        driverWith(accessToken: 'at-1').init(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('proapi.115.com 可能无法从当前部署环境访问'),
        )),
      );
    });
  });

  group('解析边界', () {
    test('open115IsAuthError：99 / 401xx 为真，其余为假', () {
      expect(open115IsAuthError(99), isTrue);
      expect(open115IsAuthError(401), isTrue);
      expect(open115IsAuthError(4010101), isTrue);
      expect(open115IsAuthError('4010101'), isTrue);
      expect(open115IsAuthError('99'), isTrue);
      expect(open115IsAuthError(0), isFalse);
      expect(open115IsAuthError(430004), isFalse);
      expect(open115IsAuthError(990002), isFalse);
      expect(open115IsAuthError(null), isFalse);
      expect(open115IsAuthError(''), isFalse);
    });

    test('Addition 序列化键名与上游一致', () {
      final a = Open115Addition(
        refreshToken: 'rt',
        rootId: '7',
        pageSize: 500,
        limitRate: 2,
        accessToken: 'at',
      );
      expect(a.toJson(), {
        'refresh_token': 'rt',
        'root_id': '7',
        'page_size': 500,
        'limit_rate': 2,
        'access_token': 'at',
      });
      // 表单里是文本字段：数字型配置也要能读进来。
      final b = Open115Addition.fromJson({
        'refresh_token': 'rt',
        'root_id': 7,
        'page_size': '500',
        'limit_rate': '2',
      });
      expect(b.rootId, '7');
      expect(b.pageSize, 500);
      expect(b.limitRate, 2);
    });

    test('root_id 空串回落到 0', () {
      final a = Open115Addition.fromJson({'refresh_token': 'rt', 'root_id': ''});
      expect(a.rootId, '0');
    });

    test('create() 从配置构造驱动（含注入的 onTokenUpdate）', () {
      const spec = Open115Spec();
      final d = spec.create({
        'refresh_token': 'rt-1',
        'root_id': '0',
        'page_size': '200',
      }) as Open115Driver;
      expect(d.client.addition.refreshToken, 'rt-1');
      expect(d.client.accessToken, '');
    });
  });
}
