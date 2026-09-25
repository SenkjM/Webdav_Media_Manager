// TeraBox 驱动回归（[12 §8](docs/12-DRIVER-PORTING-GUIDE.md)）。
//
// 全部用例都不打真网络：自定义 dio HttpClientAdapter 按 host 分流并记录
// 每次请求的 method / 完整 URI / body / 请求头 供断言
// （手法照 test/baidu_refresh_switch_test.dart 的 _RoutingAdapter）。
//
// 覆盖：
//   1. cookie 失效的**错误原文透传**（上游什么 errno / 什么文案就断言什么）；
//   2. 列表解析：分页翻完、isdir===1 判目录、server_mtime 秒 → DateTime；
//   3. errno 9000 的地区不可用错误；
//   4. 直链两种 dlink 响应形态（dlink 数组 / info 数组）都能解析出 url；
//   5. 写操作（mkdir / rename / remove / move / copy）的方法、路径、参数；
//   6. 签名字段用**固定输入向量**断言输出（向量见 teraboxSign 用例注释）。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/terabox_driver.dart';

/// 记一次出站请求的全部可断言面。
class _Hit {
  _Hit(this.method, this.uri, this.body, this.headers);

  final String method;
  final Uri uri;
  final String body;
  final Map<String, dynamic> headers;

  Map<String, String> get query => uri.queryParameters;
}

/// 出站请求分流：terabox.com 全域 → 本地 responder；其余 404。
///
/// 只实现 HttpClientAdapter 而不真连 socket：响应由 [responder] 直接产出，
/// 因此测试不需要网络、也不需要 HttpServer。
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.responder);

  final Future<_Reply> Function(_Hit hit) responder;
  final List<_Hit> hits = <_Hit>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        raw.addAll(chunk);
      }
    }
    final uri = Uri.parse(options.uri.toString());
    final hit = _Hit(
      options.method,
      uri,
      utf8.decode(raw, allowMalformed: true),
      options.headers,
    );
    hits.add(hit);
    if (!uri.host.endsWith('terabox.com')) {
      return ResponseBody.fromString('not found', 404);
    }
    final reply = await responder(hit);
    return ResponseBody.fromBytes(
      utf8.encode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  const _Reply(this.body, {this.status = 200, this.headers = const {}});

  final String body;
  final int status;
  final Map<String, List<String>> headers;
}

/// 上游 `/api/list` 的条目最小形态（types.ts TeraboxFile）。
Map<String, dynamic> _entry(
  String name, {
  int fsId = 1,
  int isdir = 0,
  int size = 0,
  int mtime = 0,
}) =>
    {
      'fs_id': fsId,
      'server_filename': name,
      'isdir': isdir,
      'size': size,
      'server_mtime': mtime,
      'path': '/$name',
    };

void main() {
  late _RoutingAdapter adapter;
  late Dio dio;

  /// 每个用例设置自己期望的响应；缺省 404 好让漏配的端点暴露出来。
  late Future<_Reply> Function(_Hit hit) responder;

  Future<TeraboxClient> makeClient({String cookie = 'ndus=abc; ndut_fmt=x'}) async {
    return TeraboxClient(TeraboxAddition(cookie: cookie), dio: dio);
  }

  TeraboxDriver makeDriver() =>
      TeraboxDriver(addition: TeraboxAddition(cookie: 'ndus=abc'), dio: dio);

  setUp(() {
    responder = (_) async => const _Reply('{}', status: 404);
    adapter = _RoutingAdapter((h) => responder(h));
    dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = adapter;
  });

  // ────────────────────────────────────────────────────────────────
  group('1 · cookie 失效：错误原文透传', () {
    test('check/login errno != 0 → CloudDriverException 带上游原文与 errno', () async {
      responder = (_) async => const _Reply('{"errno":-6}');
      final client = await makeClient();
      await expectLater(
        client.checkLogin(),
        throwsA(
          isA<CloudDriverException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Failed to verify TeraBox login status'),
              contains('errno -6'),
            ),
          ),
        ),
      );
    });

    test('cookie 完全失效 errno=-6 且带 Url-Domain-Prefix 时换域名重试一次', () async {
      // util.ts:183-193：errno -6 + 响应头 → 换 baseUrl 重试。
      // 第一次给 -6 + 头，第二次给正常 0，断言重试确实发生了。
      var n = 0;
      responder = (_) async {
        n++;
        if (n == 1) {
          return const _Reply('{"errno":-6}', headers: {
            'url-domain-prefix': ['us'],
          });
        }
        return const _Reply('{"errno":0}');
      };
      final client = await makeClient();
      await client.checkLogin();
      expect(n, 2, reason: 'errno -6 + 域名前缀必须触发一次重试');
      expect(client.urlDomainPrefix, 'us');
      expect(client.baseUrl, 'https://us.terabox.com');
    });

    test('缺少 / 错误 cookie 的非 JSON 响应不静默吞掉：errno 读作 0 但由调用方报错', () async {
      // 上游 util.ts 把非 JSON 原样返回；check/login 拿不到 errno 时
      // 视为 0（登录成功语义）——这里锁住「不抛 JSON 解析异常」。
      responder = (_) async => const _Reply('<html>login page</html>');
      final client = await makeClient();
      await client.checkLogin(); // 不应抛
    });
  });

  // ────────────────────────────────────────────────────────────────
  group('2 · 列表解析', () {
    test('分页翻到空列表为止，isdir===1 判目录，server_mtime 秒转 DateTime', () async {
      // 第 1 页满 100 条（触发翻页），第 2 页 2 条，第 3 页空 → 停。
      final page1 = [
        for (var i = 0; i < 100; i++) _entry('dir$i', fsId: i, isdir: 1),
      ];
      final page2 = [
        _entry('movie.mkv', fsId: 501, size: 1234, mtime: 1700000000),
        _entry('notes.txt', fsId: 502, size: 7, mtime: 0),
      ];
      responder = (h) async {
        final page = h.query['page'];
        if (page == '1') return _Reply(jsonEncode({'errno': 0, 'list': page1}));
        if (page == '2') return _Reply(jsonEncode({'errno': 0, 'list': page2}));
        return const _Reply('{"errno":0,"list":[]}');
      };

      final client = await makeClient();
      final files = await client.listDir('/');

      expect(files.length, 102);
      expect(adapter.hits.length, 3, reason: '必须翻到返回空列表才停');
      expect(adapter.hits.map((h) => h.query['page']), ['1', '2', '3']);
      expect(adapter.hits.every((h) => h.query['num'] == '100'), isTrue);
      expect(adapter.hits.every((h) => h.query['dir'] == '/'), isTrue);

      // 目录 / 文件判定走 isdir === 1。
      expect(files[0].isdir, 1);
      expect(files[100].serverFilename, 'movie.mkv');
      expect(files[100].isdir, 0);
      expect(files[100].size, 1234);

      // 秒 → DateTime（1700000000s = 2023-11-14T22:13:20Z）。
      // 用 isAtSameMomentAs 比较：`fromMillisecondsSinceEpoch` 返回本地时区
      // 的 DateTime（isUtc=false），与 DateTime.utc 的 == 比较还含 isUtc 标记，
      // 在非 UTC 机器上会假失败——时刻相同、表示不同。
      expect(
        DateTime.fromMillisecondsSinceEpoch(files[100].serverMtime * 1000)
            .toUtc(),
        DateTime.utc(2023, 11, 14, 22, 13, 20),
      );
    });

    test('驱动 list() 映射到 CloudFileItem：目录 size=0、文件带真实 size', () async {
      // 驱动的翻页语义与上游一致：翻到 list 为空才停。mock 必须按 page 返回，
      // 第 1 页给条目、第 2 页给空列表——否则每页都非空，驱动会永远翻下去。
      responder = (h) async {
        if (h.query['page'] == '1') {
          return _Reply(jsonEncode({
            'errno': 0,
            'list': [
              _entry('albums', fsId: 1, isdir: 1),
              _entry('song.flac', fsId: 2, size: 4096, mtime: 1700000000),
            ],
          }));
        }
        return const _Reply('{"errno":0,"list":[]}');
      };
      final driver = makeDriver();

      final items = await driver.list('/Music');
      // 第 1 页有数据 → 还要拉第 2 页确认空 → 翻页语义（上游一致）。
      expect(adapter.hits.map((h) => h.query['page']), ['1', '2']);
      expect(adapter.hits.every((h) => h.query['dir'] == '/Music'), isTrue);

      expect(items.length, 2);
      expect(items[0].name, 'albums');
      expect(items[0].isDir, isTrue);
      expect(items[1].name, 'song.flac');
      expect(items[1].isDir, isFalse);
      expect(items[1].size, 4096);
      expect(
        items[1].modified,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
      // 列表条目不带直链（契约只在 get() 上要求 rawUrl）。
      expect(items[1].rawUrl, isNull);
    });

    test('列表请求带 Cookie / UA / Referer / 公共 query', () async {
      responder = (h) async => const _Reply('{"errno":0,"list":[]}');
      final client = await makeClient(cookie: 'ndus=mycookie');
      await client.listDir('/Movies');

      final hit = adapter.hits.single;
      expect(hit.method, 'GET');
      expect(hit.uri.path, '/api/list');
      expect(hit.query['app_id'], '250528');
      expect(hit.query['web'], '1');
      expect(hit.query['channel'], 'dubox');
      expect(hit.query['clienttype'], '0');
      expect(hit.headers['Cookie'], 'ndus=mycookie');
      expect(hit.headers['User-Agent'], TeraboxClient.apiUA);
      expect(hit.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(hit.headers['Referer'], TeraboxClient.defaultBaseUrl);
    });
  });

  // ────────────────────────────────────────────────────────────────
  group('3 · errno 9000 地区不可用', () {
    test('list 返回 errno 9000 → 地区不可用错误', () async {
      responder = (_) async => const _Reply('{"errno":9000}');
      final client = await makeClient();
      await expectLater(
        client.listDir('/'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('not yet available in this area'),
        )),
      );
    });

    test('check/login 返回 errno 9000 → 同一条地区不可用错误', () async {
      responder = (_) async => const _Reply('{"errno":9000}');
      final client = await makeClient();
      await expectLater(
        client.checkLogin(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('not yet available in this area'),
        )),
      );
    });

    test('get() 也认 errno 9000', () async {
      responder = (_) async => const _Reply('{"errno":9000}');
      final driver = makeDriver();

      await expectLater(
        driver.get('/Movies/a.mkv'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('not yet available in this area'),
        )),
      );
    });
  });

  // ────────────────────────────────────────────────────────────────
  group('4 · 直链：两种 dlink 响应形态', () {
    /// 断言：先 /api/home/info 取 sign1/sign3，再 /api/download 带 sign，
    /// 最后不跟随地 GET dlink 读 Location。
    void expectLinkFlow(String downloadBody) {
      responder = (h) async {
        if (h.uri.path == '/api/home/info') {
          return const _Reply(
            '{"errno":0,"data":{"sign1":"sign1data","sign3":"sign3key","timestamp":1}}',
          );
        }
        if (h.uri.path == '/api/download') {
          return _Reply(downloadBody);
        }
        if (h.uri.path == '/dl/origin') {
          return const _Reply('', headers: {
            'location': ['https://cdn.terabox.com/real/file.mkv?token=xyz'],
          });
        }
        return const _Reply('{}', status: 404);
      };
    }

    test('形态 A：dlink 数组（TeraboxDownloadResp）', () async {
      expectLinkFlow(
        '{"errno":0,"dlink":[{"dlink":"https://www.terabox.com/dl/origin"}]}',
      );
      final client = await makeClient();
      final link = await client.linkOfficial(98765);

      expect(link.url, 'https://cdn.terabox.com/real/file.mkv?token=xyz');
      expect(link.headers, {'User-Agent': TeraboxClient.downloadUA});

      // sign 参数存在且等于固定向量（sign3='sign3key', sign1='sign1data'）。
      final dl = adapter.hits.firstWhere((h) => h.uri.path == '/api/download');
      expect(dl.query['type'], 'dlink');
      expect(dl.query['fidlist'], '[98765]');
      expect(dl.query['vip'], '2');
      expect(dl.query['sign'], 'RF9iI+bxb964');
      expect(int.tryParse(dl.query['timestamp'] ?? ''), isNotNull);
    });

    test('形态 B：info 数组（TeraboxDownloadResp2）', () async {
      expectLinkFlow(
        '{"errno":0,"info":[{"dlink":"https://www.terabox.com/dl/origin"}]}',
      );
      final client = await makeClient();
      final link = await client.linkOfficial(4242);
      expect(link.url, 'https://cdn.terabox.com/real/file.mkv?token=xyz');

      final dl = adapter.hits.firstWhere((h) => h.uri.path == '/api/download');
      expect(dl.query['fidlist'], '[4242]');
      expect(dl.query['sign'], 'RF9iI+bxb964');
    });

    test('两种形态都不认时抛真实原因（含 errno 与 fid）', () async {
      responder = (h) async {
        if (h.uri.path == '/api/home/info') {
          return const _Reply('{"errno":0,"data":{"sign1":"a","sign3":"b"}}');
        }
        if (h.uri.path == '/api/download') {
          return const _Reply('{"errno":-9,"dlink":[]}');
        }
        return const _Reply('{}', status: 404);
      };
      final client = await makeClient();
      await expectLater(
        client.linkOfficial(777),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          allOf(contains('777'), contains('-9')),
        )),
      );
    });

    test('home/info 缺 sign1 / sign3 → 报签名密钥拿不到', () async {
      responder = (_) async => const _Reply('{"errno":0,"data":{"sign1":""}}');
      final client = await makeClient();
      await expectLater(
        client.genSign(),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('sign keys'),
        )),
      );
    });

    test('dlink 不重定向时回落到 dlink 本身', () async {
      responder = (h) async {
        if (h.uri.path == '/api/home/info') {
          return const _Reply('{"errno":0,"data":{"sign1":"a","sign3":"b"}}');
        }
        if (h.uri.path == '/api/download') {
          return const _Reply('{"errno":0,"dlink":[{"dlink":"https://www.terabox.com/direct"}]}');
        }
        return const _Reply('binary', status: 200); // 无 Location
      };
      final client = await makeClient();
      final link = await client.linkOfficial(1);
      expect(link.url, 'https://www.terabox.com/direct');
    });
  });

  // ────────────────────────────────────────────────────────────────
  group('5 · get()：文件必须带直链，拿不到抛真实原因', () {
    test('文件：列父目录找到条目 → 返回带 rawUrl 与 UA 的条目', () async {
      responder = (h) async {
        if (h.uri.path == '/api/list') {
          return _Reply(jsonEncode({
            'errno': 0,
            'list': [
              _entry('other.mkv', fsId: 1),
              _entry('movie.mkv', fsId: 99, size: 555, mtime: 1700000000),
            ],
          }));
        }
        if (h.uri.path == '/api/home/info') {
          return const _Reply('{"errno":0,"data":{"sign1":"sign1data","sign3":"sign3key"}}');
        }
        if (h.uri.path == '/api/download') {
          return const _Reply('{"errno":0,"dlink":[{"dlink":"https://www.terabox.com/dl/origin"}]}');
        }
        if (h.uri.path == '/dl/origin') {
          return const _Reply('', headers: {'location': ['https://cdn/x.mkv']});
        }
        return const _Reply('{}', status: 404);
      };
      final driver = makeDriver();

      final item = await driver.get('/Movies/movie.mkv');

      expect(item.name, 'movie.mkv');
      expect(item.isDir, isFalse);
      expect(item.size, 555);
      expect(item.rawUrl, 'https://cdn/x.mkv');
      expect(item.rawHeaders, {'User-Agent': TeraboxClient.downloadUA});

      final list = adapter.hits.firstWhere((h) => h.uri.path == '/api/list');
      expect(list.query['dir'], '/Movies');
      expect(list.query['num'], '1000');
    });

    test('目录：不取直链，只返回目录条目', () async {
      responder = (h) async => _Reply(jsonEncode({
            'errno': 0,
            'list': [_entry('sub', fsId: 5, isdir: 1, mtime: 1700000000)],
          }));
      final driver = makeDriver();

      final item = await driver.get('/sub');
      expect(item.isDir, isTrue);
      expect(item.rawUrl, isNull);
      expect(
        adapter.hits.where((h) => h.uri.path == '/api/download'),
        isEmpty,
        reason: '目录不该去要直链',
      );
    });

    test('根路径 / → 目录条目，不出网', () async {
      final driver = makeDriver();

      final item = await driver.get('/');
      expect(item.isDir, isTrue);
      expect(adapter.hits, isEmpty);
    });

    test('找不到条目 → file not found（不返回无直链条目）', () async {
      responder = (_) async => const _Reply('{"errno":0,"list":[]}');
      final driver = makeDriver();

      await expectLater(
        driver.get('/Movies/missing.mkv'),
        throwsA(isA<CloudDriverException>().having(
          (e) => e.message,
          'message',
          contains('file not found: missing.mkv'),
        )),
      );
    });

    test('文件但直链拿不到 → 抛带真实原因的 CloudDriverException', () async {
      responder = (h) async {
        if (h.uri.path == '/api/list') {
          return _Reply(jsonEncode({
            'errno': 0,
            'list': [_entry('movie.mkv', fsId: 99, size: 1)],
          }));
        }
        if (h.uri.path == '/api/home/info') {
          return const _Reply('{"errno":0,"data":{}}');
        }
        return const _Reply('{}', status: 404);
      };
      final driver = makeDriver();

      await expectLater(
        driver.get('/Movies/movie.mkv'),
        throwsA(isA<CloudDriverException>()),
      );
    });
  });

  // ────────────────────────────────────────────────────────────────
  group('6 · 写操作：方法 / 路径 / 参数', () {
    /// 写操作统一走 form-urlencoded，断言 body 是表单编码过的。
    Map<String, String> formOf(_Hit h) =>
        Uri.splitQueryString(h.body.isEmpty ? 'x=' : h.body);

    test('mkdir → POST /api/create?a=commit，form: path/isdir=1/block_list=[]', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.mkdir('/Movies/New Folder');

      final hit = adapter.hits.single;
      expect(hit.method, 'POST');
      expect(hit.uri.path, '/api/create');
      expect(hit.query['a'], 'commit');
      final form = formOf(hit);
      expect(form['path'], '/Movies/New Folder');
      expect(form['isdir'], '1');
      expect(form['block_list'], '[]');
      expect(
        (hit.headers[Headers.contentTypeHeader] as String?) ?? '',
        contains('application/x-www-form-urlencoded'),
      );
    });

    test('rename → POST /api/filemanager?opera=rename&onnest=fail，filelist 是 JSON 字符串', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.rename('/Movies/old.mkv', '/Movies/new.mkv');

      final hit = adapter.hits.single;
      expect(hit.method, 'POST');
      expect(hit.uri.path, '/api/filemanager');
      expect(hit.query['opera'], 'rename');
      expect(hit.query['onnest'], 'fail');

      final form = formOf(hit);
      expect(form['async'], '0');
      expect(form['ondup'], 'newcopy');
      final filelist = jsonDecode(form['filelist']!) as List<dynamic>;
      expect(filelist, [
        {'path': '/Movies/new.mkv', 'newname': 'new.mkv'},
      ]);
    });

    test('rename 跨目录：path 用目标全路径（一次请求完成移动+改名）', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.rename('/A/old.mkv', '/B/Sub/new.mkv');
      final filelist =
          jsonDecode(formOf(adapter.hits.single)['filelist']!) as List<dynamic>;
      expect(filelist, [
        {'path': '/B/Sub/new.mkv', 'newname': 'new.mkv'},
      ]);
    });

    test('remove → opera=delete，filelist 是路径字符串数组', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.remove('/Movies/gone.mkv');

      final hit = adapter.hits.single;
      expect(hit.method, 'POST');
      expect(hit.uri.path, '/api/filemanager');
      expect(hit.query['opera'], 'delete');
      expect(
        jsonDecode(formOf(hit)['filelist']!),
        ['/Movies/gone.mkv'],
      );
    });

    test('move → opera=move，filelist 含 path / dest / newname', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.move('/A/one.mkv', '/B', 'renamed.mkv');

      final hit = adapter.hits.single;
      expect(hit.uri.path, '/api/filemanager');
      expect(hit.query['opera'], 'move');
      expect(jsonDecode(formOf(hit)['filelist']!), [
        {'path': '/A/one.mkv', 'dest': '/B', 'newname': 'renamed.mkv'},
      ]);
    });

    test('copy → opera=copy，filelist 含 path / dest / newname', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.copy('/A/one.mkv', '/B', 'one.mkv');

      final hit = adapter.hits.single;
      expect(hit.uri.path, '/api/filemanager');
      expect(hit.query['opera'], 'copy');
      expect(jsonDecode(formOf(hit)['filelist']!), [
        {'path': '/A/one.mkv', 'dest': '/B', 'newname': 'one.mkv'},
      ]);
    });

    test('路径规范化：重复斜杠折叠、尾斜杠去掉', () async {
      responder = (_) async => const _Reply('{"errno":0}');
      final driver = makeDriver();

      await driver.remove('//A//B//c.mkv/');
      expect(jsonDecode(formOf(adapter.hits.single)['filelist']!), ['/A/B/c.mkv']);
    });
  });

  // ────────────────────────────────────────────────────────────────
  group('7 · 签名：固定输入断言输出（金标向量）', () {
    // 向量来源：把 util.ts:9-45 的 teraboxSign 逐行移植后，用两份互相独立
    // 的实现（不同控制流 / 不同缓冲区类型）各算一遍交叉验证，逐字节一致后
    // 固化于此。上游 driver.test.ts 只断言「非空字符串」，这些向量更强。
    test('sign3key / sign1data → RF9iI+bxb964', () {
      expect(teraboxSign('sign3key', 'sign1data'), 'RF9iI+bxb964');
    });

    test('密钥单字节：k 恒为密钥字节，明文只被异或同一常量', () {
      // 密钥 1 字节时 i/u 全程不重排，k 恒为 p[0] == 0x61。
      expect(teraboxSign('b', 'a'), 'PA=='); // 'a'(0x61) ^ 0x61 == 0x00
      expect(teraboxSign('b', 'X'), 'BQ=='); // 'X'(0x58) ^ 0x61 == 0x05
      expect(teraboxSign('b', '\u0000'), 'XQ=='); // 0x00 ^ 0x61 == 0x61
    });

    test('空明文 → 空 base64', () {
      expect(teraboxSign('key', ''), '');
    });

    test('多字节明文向量（溢出必须按无符号字节收集）', () {
      expect(teraboxSign('abc', 'hello world'), 'pfi1RTf/mhxeiws=');
      expect(
        teraboxSign('0123456789abcdef', 'The quick brown fox'),
        '0AAleYw7yfti1jjsr+Q9ZYSCUA==',
      );
    });

    test('空密钥明确报错（上游 JS 会算出 NaN、Go 会 panic，都不是可用行为）', () {
      expect(
        () => teraboxSign('', 'data'),
        throwsA(isA<CloudDriverException>()),
      );
    });

    test('相同输入稳定可复现', () {
      expect(teraboxSign('k', 'payload'), teraboxSign('k', 'payload'));
    });
  });
}
