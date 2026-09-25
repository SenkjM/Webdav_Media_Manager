// 网易云音乐驱动（netease_music）的行为回归。
//
// 上游参照：`localdev/OpenList-Worker/.../netease_music/driver.ts` +
// `util.ts`（移植底稿）、`localdev/OpenList/drivers/netease_music`（语义兜底）。
//
// 锁定的事实：
//   - 能力面只有 list | read | delete（上游 mkdir / rename / move / copy
//     全是 errs.NotSupport 桩，99 §7.3.2）；
//   - 列表端点与请求形状（weapi + `os=pc` Cookie + Referer）；
//   - 直链端点走 linuxapi，实际打到 `/api/linux/forward` 且带 Linux UA；
//   - 删除按文件名定位后按 songId 删（weapi/cloud/del）；
//   - Cookie 缺 `__csrf` / `MUSIC_U` 时保存即失败；
//   - 拿不到直链时抛可读错误，而不是产出空 URL；
//   - 响应 code 非 200（登录态失效）会被识别成可读错误。
//
// 实现方式：自定义 dio HttpClientAdapter 直接按闭包产出响应（不出真网络），
// 记录 method / path / headers / body 供断言。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/driver_registry.dart';
import 'package:webdav_media_manager/services/cloud_drivers/netease_music_driver.dart';

/// 记录一次出站请求。
class _Hit {
  _Hit(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  /// 该请求的表单体（application/x-www-form-urlencoded）。
  Map<String, String> get form => Uri.splitQueryString(body);
}

/// 拦截全部出站请求，记录细节并由 [respond] 决定响应。
///
/// 不经过真实网络：直接把闭包产出的 JSON 包装成 ResponseBody，
/// 否则每个用例都要起 HttpServer，既慢又易受端口/连接复用影响。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  /// 响应工厂：按请求 URI 与表单体产出 JSON 对象（或抛错）。
  Map<String, dynamic> Function(Uri uri, Map<String, String> form) respond;

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
    final hit = _Hit(options.method, uri, {
      for (final e in options.headers.entries)
        if (e.value != null) e.key.toLowerCase(): '${e.value}',
    }, body);
    hits.add(hit);

    final json = jsonEncode(respond(uri, hit.form));
    return ResponseBody.fromString(json, 200, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeAdapter adapter;
  late Dio dio;

  /// 一份典型的云盘列表响应。
  Map<String, dynamic> songList(List<Map<String, dynamic>> songs) => {
        'size': songs.length,
        'maxSize': 100000,
        'data': songs,
        'code': 200,
      };

  Map<String, dynamic> song(
    int id,
    String name, {
    int size = 1024,
    int addTime = 1700000000000,
  }) =>
      {
        'songId': id,
        'fileName': name,
        'fileSize': size,
        'addTime': addTime,
        'simpleSong': {
          'al': {'picUrl': 'https://p1.music.126.net/x.jpg'},
        },
      };

  setUp(() {
    adapter = _FakeAdapter((uri, form) => <String, dynamic>{'code': 200});
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.httpClientAdapter = adapter;
  });

  NeteaseMusicDriver driverWith({String? cookie, int? limit}) =>
      NeteaseMusicDriver(
        addition: NeteaseMusicAddition(
          cookie: cookie ?? '__csrf=abc; MUSIC_U=xyz',
          songLimit: limit ?? 200,
        ),
        dio: dio,
      );

  group('spec 与能力遮罩', () {
    test('类型 id / 显示名 / 注册表登记', () {
      const spec = NeteaseMusicSpec();
      expect(spec.typeId, 'netease_music');
      expect(spec.displayName, '网易云音乐');
      expect(cloudDriverSpec('netease_music'), isA<NeteaseMusicSpec>());
    });

    test('能力位 = 列出 | 读取 | 删除，且没有 mkdir / move / copy / write', () {
      const spec = NeteaseMusicSpec();
      final caps = spec.capabilities;
      expect(AccountCaps.has(caps, AccountCaps.list), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.read), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.delete), isTrue);
      // 上游是 errs.NotSupport 桩 → 不给位（99 §7.3.2）
      expect(AccountCaps.has(caps, AccountCaps.mkdir), isFalse);
      expect(AccountCaps.has(caps, AccountCaps.move), isFalse);
      expect(AccountCaps.has(caps, AccountCaps.copy), isFalse);
      // 上传已砍（99 §7.2.1）
      expect(AccountCaps.has(caps, AccountCaps.write), isFalse);
    });

    test('表单：cookie 必填且密文，song_limit 默认 200', () {
      const spec = NeteaseMusicSpec();
      final fields = spec.form.whereType<CloudDriverField>().toList();
      expect(fields.length, 2);

      final cookie = fields.firstWhere((f) => f.key == 'cookie');
      expect(cookie.required, isTrue);
      expect(cookie.obscure, isTrue);

      final limit = fields.firstWhere((f) => f.key == 'song_limit');
      expect(limit.required, isFalse);
      expect(limit.defaultValue, '200');
    });
  });

  group('登录态（init）', () {
    test('Cookie 含 __csrf 与 MUSIC_U → 通过', () async {
      final d = driverWith(cookie: '__csrf=tok; MUSIC_U=mu; other=1');
      await d.init();
      expect(d.client.csrfToken, 'tok');
      expect(d.client.musicU, 'mu');
    });

    test('缺 MUSIC_U → 报可读错误，且不发任何请求', () async {
      final d = driverWith(cookie: '__csrf=tok');
      await expectLater(
        d.init(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('__csrf'),
        )),
      );
      expect(adapter.hits, isEmpty);
    });

    test('缺 __csrf → 报错', () async {
      final d = driverWith(cookie: 'MUSIC_U=mu');
      await expectLater(d.init(), throwsA(isA<CloudDriverException>()));
      expect(adapter.hits, isEmpty);
    });

    test('空 Cookie → 报错', () async {
      final d = driverWith(cookie: '');
      await expectLater(d.init(), throwsA(isA<CloudDriverException>()));
    });

    test('Cookie 值里带 = 也能正确取出（正则语义）', () async {
      final d = driverWith(cookie: 'MUSIC_U=a=b=c; __csrf=x');
      await d.init();
      expect(d.client.musicU, 'a=b=c');
      expect(d.client.csrfToken, 'x');
    });
  });

  group('列表（weapi/v1/cloud/get）', () {
    test('请求形状：weapi 端点 + os=pc Cookie + Referer + 表单体', () async {
      adapter.respond = (uri, form) => songList([song(1, 'a.mp3')]);
      final d = driverWith(limit: 200);
      final items = await d.list('/');

      expect(adapter.hits.length, 1);
      final hit = adapter.hits.single;
      expect(hit.method, 'POST');
      expect(hit.uri.path, '/weapi/v1/cloud/get');
      expect(hit.uri.host, 'music.163.com');
      // Cookie：配置值 + 追加的 os=pc
      expect(hit.headers['cookie'], contains('MUSIC_U=xyz'));
      expect(hit.headers['cookie'], contains('os=pc'));
      expect(hit.headers['referer'], 'https://music.163.com');
      // weapi 表单体：params + encSecKey
      final form = Uri.splitQueryString(hit.body);
      expect(form.keys.toSet(), {'params', 'encSecKey'});
      expect(form['encSecKey']!.length, 256);
      expect(() => base64.decode(form['params']!), returnsNormally);

      expect(items.length, 1);
      expect(items.single.name, 'a.mp3');
      expect(items.single.isDir, isFalse);
      expect(items.single.size, 1024);
      expect(items.single.modified,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('limit 写进请求体（表单上限生效）', () async {
      adapter.respond = (uri, form) => songList([]);
      await driverWith(limit: 50).list('/');
      // params 是密文，无法直接断言明文；改为断言「不同 limit 产出不同密文」
      final hit50 = adapter.hits.single.body;
      adapter.hits.clear();
      await driverWith(limit: 51).list('/');
      expect(adapter.hits.single.body, isNot(hit50));
    });

    test('list 是平铺的：忽略路径，永远返回全部歌曲', () async {
      adapter.respond = (uri, form) =>
          songList([song(1, 'a.mp3'), song(2, 'b.flac')]);
      final d = driverWith();
      final atRoot = await d.list('/');
      final atSub = await d.list('/whatever/deep');
      expect(atRoot.map((e) => e.name), ['a.mp3', 'b.flac']);
      expect(atSub.map((e) => e.name), ['a.mp3', 'b.flac']);
    });

    test('空列表 → 空数组（不报错）', () async {
      adapter.respond = (uri, form) => songList([]);
      expect(await driverWith().list('/'), isEmpty);
    });

    test('缺 data 字段 → 空数组', () async {
      adapter.respond = (uri, form) => {'code': 200};
      expect(await driverWith().list('/'), isEmpty);
    });

    test('条目缺 fileName / songId → 跳过该条，不整体失败', () async {
      adapter.respond = (uri, form) => {
            'code': 200,
            'data': [
              {'songId': 1}, // 无 fileName
              {'fileName': 'ok.mp3', 'songId': 2, 'fileSize': 5},
              {'fileName': 'noid.mp3'}, // 无 songId
            ],
          };
      final items = await driverWith().list('/');
      expect(items.map((e) => e.name), ['ok.mp3']);
      expect(items.single.size, 5);
    });

    test('addTime 为 0 → modified 为 null（不伪造时间）', () async {
      adapter.respond = (uri, form) =>
          songList([song(1, 'a.mp3', addTime: 0)]);
      final items = await driverWith().list('/');
      expect(items.single.modified, isNull);
    });
  });

  group('取单条与直链（linuxapi / player/url）', () {
    test('get 按文件名定位，直链请求打到 linux/forward 且带 Linux UA', () async {
      adapter.respond = (uri, form) {
        if (uri.path.contains('cloud/get')) {
          return songList([song(7, 'target.mp3', size: 2048)]);
        }
        if (uri.path.contains('linux/forward')) {
          return {
            'code': 200,
            'data': [
              {'url': 'http://m801.music.126.net/target.mp3'},
            ],
          };
        }
        return {'code': 200};
      };
      final d = driverWith();
      final item = await d.get('/target.mp3');

      expect(item.name, 'target.mp3');
      expect(item.isDir, isFalse);
      expect(item.size, 2048);
      expect(item.rawUrl, 'http://m801.music.126.net/target.mp3');
      expect(item.rawHeaders?['User-Agent'], isNotNull);

      expect(adapter.hits.length, 2);
      final linkHit = adapter.hits.last;
      expect(linkHit.uri.path, '/api/linux/forward');
      expect(linkHit.headers['user-agent'], NeteaseMusicClient.linuxApiUA);
      expect(linkHit.headers['referer'], 'https://music.163.com');
      // linuxapi 表单体：只有 eparams，且是大写 hex
      final form = Uri.splitQueryString(linkHit.body);
      expect(form.keys.toSet(), {'eparams'});
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(form['eparams']!), isTrue);
    });

    test('远程路径只会当虚拟前缀：按 basename 定位', () async {
      adapter.respond = (uri, form) {
        if (uri.path.contains('cloud/get')) {
          return songList([song(7, 'target.mp3')]);
        }
        return {
          'code': 200,
          'data': [
            {'url': 'http://cdn/t.mp3'},
          ],
        };
      };
      final item = await driverWith().get('/netease/prefix/target.mp3');
      expect(item.name, 'target.mp3');
      expect(item.rawUrl, 'http://cdn/t.mp3');
    });

    test('根路径 get → 目录占位（上游 get 的 root 分支）', () async {
      final item = await driverWith().get('/');
      expect(item.isDir, isTrue);
      expect(adapter.hits, isEmpty, reason: '根目录不需要出网');
    });

    test('文件不存在 → 可读错误（不发直链请求）', () async {
      adapter.respond = (uri, form) => songList([song(1, 'other.mp3')]);
      await expectLater(
        driverWith().get('/missing.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('missing.mp3'),
        )),
      );
      expect(adapter.hits.length, 1, reason: '只应发列表请求');
    });

    test('data 为空 → 抛「未返回播放链接」而不是产出空 URL', () async {
      adapter.respond = (uri, form) {
        if (uri.path.contains('cloud/get')) {
          return songList([song(7, 'vip.mp3')]);
        }
        return {'code': 200, 'data': <dynamic>[]};
      };
      await expectLater(
        driverWith().get('/vip.mp3'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('未返回播放链接'),
        )),
      );
    });

    test('url 为 null → 同样抛可读错误（VIP / 版权受限）', () async {
      adapter.respond = (uri, form) {
        if (uri.path.contains('cloud/get')) {
          return songList([song(7, 'vip.mp3')]);
        }
        return {
          'code': 200,
          'data': [
            {'url': null},
          ],
        };
      };
      await expectLater(
        driverWith().get('/vip.mp3'),
        throwsA(isA<CloudDriverException>()),
      );
    });
  });

  group('删除（weapi/cloud/del）', () {
    test('按名字找到 songId 后用 weapi 删除', () async {
      adapter.respond = (uri, form) {
        if (uri.path.contains('cloud/get')) {
          return songList([song(1, 'a.mp3'), song(42, 'doomed.mp3')]);
        }
        return {'code': 200};
      };
      final d = driverWith();
      await d.remove('/doomed.mp3');

      expect(adapter.hits.length, 2);
      final del = adapter.hits.last;
      expect(del.method, 'POST');
      expect(del.uri.path, '/weapi/cloud/del');
      final form = Uri.splitQueryString(del.body);
      expect(form.keys.toSet(), {'params', 'encSecKey'});
      // 删除时上游**不**追加 os=pc（只有列表与直链加）
      expect(del.headers['cookie'], isNot(contains('os=pc')));
    });

    test('删除不存在的名字 → 报错，不发删除请求', () async {
      adapter.respond = (uri, form) => songList([song(1, 'a.mp3')]);
      await expectLater(
        driverWith().remove('/nope.mp3'),
        throwsA(isA<CloudDriverException>()),
      );
      expect(adapter.hits.length, 1);
    });

    test('根路径删除 → 明确拒绝', () async {
      await expectLater(
        driverWith().remove('/'),
        throwsA(isA<CloudDriverException>()),
      );
      expect(adapter.hits, isEmpty);
    });
  });

  group('未实现的操作显式抛错（上游 NotSupport 桩）', () {
    test('mkdir / rename / move / copy 全部抛可读错误', () async {
      final d = driverWith();
      await expectLater(d.mkdir('/x'), throwsA(isA<CloudDriverException>()));
      await expectLater(
          d.rename('/a', '/b'), throwsA(isA<CloudDriverException>()));
      await expectLater(
          d.move('/a', '/d', 'b'), throwsA(isA<CloudDriverException>()));
      await expectLater(
          d.copy('/a', '/d', 'b'), throwsA(isA<CloudDriverException>()));
      expect(adapter.hits, isEmpty, reason: '不支持的写操作不应出网');
    });
  });

  group('错误原文透传', () {
    test('登录态失效（code 301）→ 提示 Cookie 过期', () async {
      adapter.respond = (uri, form) => {'code': 301, 'message': 'need login'};
      await expectLater(
        driverWith().list('/'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('301'), contains('Cookie')),
        )),
      );
    });

    test('其它非 200 code → 带 code 与 message', () async {
      adapter.respond = (uri, form) => {'code': -460, 'message': 'Cheating'};
      await expectLater(
        driverWith().list('/'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('-460'), contains('Cheating')),
        )),
      );
    });

    test('非 JSON 响应 → 报 HTTP 状态与片段', () async {
      final plainDio = Dio(BaseOptions(validateStatus: (_) => true));
      plainDio.httpClientAdapter = _PlainAdapter();
      final d = NeteaseMusicDriver(
        addition: NeteaseMusicAddition(cookie: '__csrf=a; MUSIC_U=b'),
        dio: plainDio,
      );
      await expectLater(
        d.list('/'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('非 JSON'),
        )),
      );
    });
  });

  group('保存前真连校验', () {
    // spec.verify 内部自建驱动（不出网即无法注入假适配器），因此在等价
    // 路径上验证行为：init（Cookie 形态）+ 一次真实列表请求。
    test('真连校验：拉一次列表确认 Cookie 可用', () async {
      adapter.respond = (uri, form) => songList([song(1, 'a.mp3')]);
      await driverWith(cookie: '__csrf=a; MUSIC_U=b').client.verifyLogin();
      expect(adapter.hits.length, 1);
      expect(adapter.hits.single.uri.path, '/weapi/v1/cloud/get');
    });

    test('真连校验：服务端报 301 → 抛出可读错误（不落库）', () async {
      adapter.respond = (uri, form) => {'code': 301, 'message': 'need login'};
      await expectLater(
        driverWith(cookie: '__csrf=a; MUSIC_U=b').client.verifyLogin(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('Cookie'),
        )),
      );
    });

    test('格式不对 → 不发请求即失败', () async {
      await expectLater(
        driverWith(cookie: 'nope=1').client.verifyLogin(),
        throwsA(isA<CloudDriverException>()),
      );
      expect(adapter.hits, isEmpty);
    });

    test('spec.verify 覆写为真连校验：形态不对时失败', () async {
      // 默认实现 create().init() 也是先抛，这里锁「会抛且是可读错误」，
      // 真连语义由上面两个用例覆盖。
      const spec = NeteaseMusicSpec();
      await expectLater(
        spec.verify(const {'cookie': 'bad=1'}),
        throwsA(isA<CloudDriverException>()),
      );
    });
  });

  group('配置解析（Addition）', () {
    test('fromJson 默认值与容错', () {
      expect(NeteaseMusicAddition.fromJson(const {}).songLimit, 200);
      expect(
          NeteaseMusicAddition.fromJson(const {'song_limit': '50'}).songLimit, 50);
      expect(
          NeteaseMusicAddition.fromJson(const {'song_limit': 50}).songLimit, 50);
      // 非法值回默认
      expect(
          NeteaseMusicAddition.fromJson(const {'song_limit': 'abc'}).songLimit, 200);
      expect(
          NeteaseMusicAddition.fromJson(const {'song_limit': '0'}).songLimit, 200);
      expect(NeteaseMusicAddition.fromJson(const {'song_limit': -5}).songLimit,
          200);
      expect(NeteaseMusicAddition.fromJson(const {'song_limit': null}).songLimit,
          200);
    });

    test('toJson 往返一致', () {
      final a = NeteaseMusicAddition(cookie: 'c=1', songLimit: 30);
      final back = NeteaseMusicAddition.fromJson(a.toJson());
      expect(back.cookie, 'c=1');
      expect(back.songLimit, 30);
    });
  });
}

/// 返回非 JSON 体的适配器（测非 JSON 分支）。
class _PlainAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('<html>502 bad gateway</html>', 502,
        headers: {'content-type': ['text/html']});
  }

  @override
  void close({bool force = false}) {}
}
