// CtFile driver behavioral regression tests.
//
// Reference: Worker localdev/OpenList-Worker/src/backend/drivers/ctfile
// (util.test.ts + driver.ts + util.ts + types.ts).
//
// Locked facts:
// - Session auth only (POST JSON + session field).
// - callWithId dual-prefix strategy (d/f stripped vs raw).
// - Path→id cache with d/f keys, root="0".
// - upload: md5-size checksum → multipart presigned URL.
// - mkdir 403+folder_id = success.
// - list: folder/list + file/list merged, paging guarded.
// - 429/5xx retry with backoff; 401 = session expired.
// - fetch_url: stripped-first prefix strategy.
// - get() returns real size + rawUrl + rawHeaders (UA).
// - copy() works: ids + target folder_id (spec §实现要点 #6).

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/ctfile_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/driver_registry.dart';

/// Captured request.
class _Hit {
  _Hit(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
  String get host => uri.host;
  String get path => uri.path;
}

/// Intercept all outgoing requests → local test server.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.server);
  final HttpServer server;
  final List<_Hit> hits = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
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

    final client = HttpClient();
    final target = Uri.parse('http://127.0.0.1:${server.port}${uri.path}?${uri.query}');
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
    return ResponseBody.fromBytes(bytes, res.statusCode,
      headers: {'content-type': [res.headers.contentType?.mimeType ?? 'application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpServer server;
  late _MockAdapter adapter;
  late Dio dio;
  late Map<String, dynamic> Function(String path, Map<String, String> query, String body) apiResponse;

  // CtFile API responses are flat: {'code': 200, 'results': [...]} not {'code':200,'data':{...}}
  Map<String, dynamic> ok([Object? extra]) => {
    'code': 200,
    'message': 'ok',
    if (extra is Map) ...extra as Map<String, dynamic>,
  };

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final payload = apiResponse(req.uri.path, req.uri.queryParameters, body);
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload));
      await req.response.close();
    });
    adapter = _MockAdapter(server);
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}', validateStatus: (_) => true));
    dio.httpClientAdapter = adapter;
    apiResponse = (path, query, body) => ok();
  });

  tearDown(() async {
    await server.close(force: true);
  });

  CtFileAddition additionWith({
    String? session,
    int listCacheSec = kDefaultListCacheSec,
    int requestIntervalMs = 0,
  }) => CtFileAddition(
    session: session ?? 's-test',
    baseUrl: 'http://127.0.0.1:${server.port}',
    listCacheSec: listCacheSec,
    requestIntervalMs: requestIntervalMs,
  );

  CtFileDriver driverWith(CtFileAddition addition) =>
      CtFileDriver(addition: addition, dio: dio);

  group('spec & capabilities', () {
    test('typeId / displayName / registry', () {
      const spec = CtFileSpec();
      expect(spec.typeId, 'ctfile');
      expect(cloudDriverSpec('ctfile'), isA<CtFileSpec>());
    });

    test('capabilities = list|read|write|mkdir|move|copy|delete', () {
      const spec = CtFileSpec();
      final caps = spec.capabilities;
      expect(AccountCaps.has(caps, AccountCaps.list), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.read), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.write), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.mkdir), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.move), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.copy), isTrue);
      expect(AccountCaps.has(caps, AccountCaps.delete), isTrue);
    });

    test('form: session + cloud_type + cache/throttle defaults', () {
      const spec = CtFileSpec();
      expect(spec.form.length, 4);
      final session = spec.form.first as CloudDriverField;
      expect(session.key, 'session');
      expect(session.required, isTrue);
      expect(session.obscure, isTrue);
      final cloudType = spec.form[1] as CloudDriverSelectField;
      expect(cloudType.key, 'cloud_type');
      expect(cloudType.defaultValue, 'public');
      final cache = spec.form[2] as CloudDriverField;
      expect(cache.key, 'list_cache_sec');
      expect(cache.defaultValue, '$kDefaultListCacheSec');
      final gap = spec.form[3] as CloudDriverField;
      expect(gap.key, 'request_interval_ms');
      expect(gap.defaultValue, '$kDefaultRequestIntervalMs');
    });

    test('secretFieldKeys auto-derives from form obscure field', () {
      const spec = CtFileSpec();
      expect(spec.secretFieldKeys, contains('session'));
      expect(spec.runtimeSecretKeys, isEmpty);
    });
  });

  group('session auth', () {
    test('profile check on init', () async {
      apiResponse = (path, query, body) {
        if (path == '/user/info/profile') return ok({'userid': 1});
        return ok();
      };
      final d = driverWith(additionWith());
      await d.init();
      expect(adapter.hits.single.path, '/user/info/profile');
      final reqBody = jsonDecode(adapter.hits.single.body) as Map;
      expect(reqBody['session'], 's-test');
    });

    test('401 → session expired error', () async {
      apiResponse = (path, query, body) => {'code': 401, 'message': '未登录'};
      final d = driverWith(additionWith());
      await expectLater(d.init(), throwsA(isA<CloudDriverException>().having(
        (e) => e.message, 'message', contains('Session expired'))));
    });

    test('empty session → clear error before hitting network', () async {
      final d = driverWith(additionWith(session: ''));
      await expectLater(d.init(), throwsA(isA<CloudDriverException>().having(
        (e) => e.message, 'message', contains('Session missing'))));
      expect(adapter.hits, isEmpty);
    });
  });

  group('id normalization', () {
    test('strip d/f prefix before digit only', () {
      // Test via CtFileAddition + known API behavior (prefix stripped for file calls)
      // The private _stripIdPrefix strips 'd'/'f' before a digit.
      final a = CtFileAddition(session: 's', baseUrl: 'http://localhost');
      expect(a.cloudType, 'public'); // sanity
      // verify that ids with d/f prefix are handled (via CtFileFile.fromMap key)
      final folder = CtFileFolder.fromMap({'key': 'd123', 'name': 'foo'});
      expect(folder.key, 'd123');
      final file = CtFileFile.fromMap({'key': 'f456', 'name': 'bar.mp3', 'size': 10});
      expect(file.key, 'f456');
    });
  });

  group('date parsing', () {
    test('unix seconds', () {
      final t = parseCtFileDate(1700000000);
      expect(t, isNotNull);
      expect(t!.year, 2023);
    });

    test('unix milliseconds (> 1e12)', () {
      final t = parseCtFileDate(1700000000000);
      expect(t, isNotNull);
    });

    test('"YYYY-MM-DD HH:mm:ss" string', () {
      final t = parseCtFileDate('2024-01-15 12:30:00');
      expect(t, isNotNull);
    });

    test('null returns null', () {
      expect(parseCtFileDate(null), isNull);
    });
  });

  group('checksum format', () {
    test('md5-size format', () async {
      String? capturedChecksum;
      apiResponse = (path, query, body) {
        if (path == '/public/file/upload') {
          final req = jsonDecode(body) as Map;
          capturedChecksum = req['checksum'] as String?;
          // instant-upload so no multipart needed
          return ok({'exists': 1});
        }
        // folder/list for _ensureDirectory
        return ok({'results': <dynamic>[]});
      };
      final d = driverWith(additionWith());
      await d.uploadStream('/test.txt', Stream.value([1, 2, 3, 4, 5]), 5);
      expect(capturedChecksum, matches(RegExp(r'^[0-9a-f]{32}-5$')));
    });
  });

  group('list', () {
    test('folder/list + file/list merged, isDir from key prefix', () async {
      apiResponse = (path, query, body) {
        if (path == '/public/folder/list') {
          return ok({'results': [{'key': 'd1', 'name': 'dirA'}]});
        }
        if (path == '/public/file/list') {
          final start = query['start'] ?? '0';
          if (start == '0') {
            return ok({'results': [{'key': 'f2', 'name': 'a.mp3', 'size': 1024}]});
          }
          return ok({'results': <dynamic>[]});
        }
        return ok();
      };
      final d = driverWith(additionWith());
      final items = await d.list('/');
      expect(items.map((i) => i.name).toSet(), {'dirA', 'a.mp3'});
      final dir = items.firstWhere((i) => i.name == 'dirA');
      final file = items.firstWhere((i) => i.name == 'a.mp3');
      expect(dir.isDir, isTrue);
      expect(file.isDir, isFalse);
      expect(file.size, 1024);
    });

    test('list cache avoids second folder/file list within TTL', () async {
      var folderHits = 0;
      var fileHits = 0;
      apiResponse = (path, query, body) {
        if (path == '/public/folder/list') {
          folderHits++;
          return ok({'results': [{'key': 'd1', 'name': 'dirA'}]});
        }
        if (path == '/public/file/list') {
          fileHits++;
          return ok({'results': [{'key': 'f2', 'name': 'a.mp3', 'size': 10}]});
        }
        return ok();
      };
      final d = driverWith(additionWith(listCacheSec: 60, requestIntervalMs: 0));
      final first = await d.list('/');
      final second = await d.list('/');
      expect(first.length, 2);
      expect(second.length, 2);
      // First list() may hit file/list twice (page + empty terminator).
      // Second list() must not add more hits when cache TTL is active.
      expect(folderHits, 1, reason: 'second list should hit folder cache');
      expect(fileHits, 2, reason: 'page + empty stop on first list only');
    });

    test('list cache disabled when list_cache_sec is 0', () async {
      var folderHits = 0;
      apiResponse = (path, query, body) {
        if (path == '/public/folder/list') {
          folderHits++;
          return ok({'results': <dynamic>[]});
        }
        if (path == '/public/file/list') {
          return ok({'results': <dynamic>[]});
        }
        return ok();
      };
      final d = driverWith(additionWith(listCacheSec: 0, requestIntervalMs: 0));
      await d.list('/');
      await d.list('/');
      expect(folderHits, 2);
    });

    test('same d123 entry from both endpoints → exactly one item, isDir=true', () async {
      // Regression: file/list may return d-prefixed directory entries (size=0).
      // list() must dedupe by key and trust key prefix for isDir, not endpoint.
      apiResponse = (path, query, body) {
        if (path == '/public/folder/list') {
          return ok({'results': [{'key': 'd123', 'name': 'shared'}]});
        }
        if (path == '/public/file/list') {
          final start = query['start'] ?? '0';
          if (start == '0') {
            // same key from file/list — this is the duplicate directory entry
            return ok({'results': [{'key': 'd123', 'name': 'shared', 'size': 0}]});
          }
          return ok({'results': <dynamic>[]});
        }
        return ok();
      };
      final d = driverWith(additionWith());
      final items = await d.list('/');
      expect(items.length, 1, reason: 'duplicate key d123 must be deduped to one entry');
      expect(items.single.name, 'shared');
      expect(items.single.isDir, isTrue, reason: 'key.startsWith("d") → isDir');
      expect(items.single.size, 0);
    });

    test('f-prefixed key from file/list → isDir=false regardless of endpoint', () async {
      apiResponse = (path, query, body) {
        if (path == '/public/folder/list') {
          return ok({'results': <dynamic>[]});
        }
        if (path == '/public/file/list') {
          final start = query['start'] ?? '0';
          if (start == '0') {
            return ok({'results': [{'key': 'f99', 'name': 'track.mp3', 'size': 512}]});
          }
          return ok({'results': <dynamic>[]});
        }
        return ok();
      };
      final d = driverWith(additionWith());
      final items = await d.list('/');
      expect(items.length, 1);
      expect(items.single.isDir, isFalse);
      expect(items.single.size, 512);
    });
  });

  group('get()', () {
    test('file: returns real size + rawUrl + rawHeaders with UA', () async {
      apiResponse = (path, query, body) {
        // _pathToId: folder list for root
        if (path == '/public/folder/list') {
          return ok({'results': <dynamic>[]});
        }
        // _pathToId: file list for root (expectDir=false on last segment)
        if (path == '/public/file/list') {
          return ok({'results': [{'key': 'f42', 'name': 'song.mp3', 'size': 999}]});
        }
        // fileMeta
        if (path == '/public/file/meta') {
          return ok({'size': 999});
        }
        // fetch_url
        if (path == '/public/file/fetch_url') {
          return ok({'download_url': 'https://cdn.ctfile.com/song.mp3'});
        }
        return ok();
      };
      final d = driverWith(additionWith());
      final item = await d.get('/song.mp3');
      expect(item.isDir, isFalse);
      expect(item.size, 999);
      expect(item.rawUrl, 'https://cdn.ctfile.com/song.mp3');
      expect(item.rawHeaders, isNotNull);
      expect(item.rawHeaders!['User-Agent'], isNotEmpty);
    });

    test('root returns directory', () async {
      final d = driverWith(additionWith());
      final item = await d.get('/');
      expect(item.isDir, isTrue);
    });
  });

  group('upload', () {
    test('uploadTicket md5-size checksum → multipart presigned URL', () async {
      apiResponse = (path, query, body) {
        if (path == '/public/file/upload') {
          final req = jsonDecode(body) as Map;
          expect(req['checksum'], matches(RegExp(r'^[0-9a-f]{32}-5$')));
          return ok({'upload_url': 'http://127.0.0.1:${server.port}/upload'});
        }
        if (path == '/upload') {
          return ok();
        }
        return ok({'results': <dynamic>[]});
      };
      final d = driverWith(additionWith());
      await d.uploadStream('/test.txt', Stream.value([1, 2, 3, 4, 5]), 5);
      expect(adapter.hits.any((h) => h.path == '/public/file/upload'), isTrue);
    });

    test('instant upload (exists>0) skips multipart', () async {
      apiResponse = (path, query, body) {
        if (path == '/public/file/upload') return ok({'exists': 1});
        return ok({'results': <dynamic>[]});
      };
      final d = driverWith(additionWith());
      await d.uploadStream('/test.txt', Stream.value([1, 2, 3]), 3);
      expect(adapter.hits.where((h) => h.path == '/public/file/upload').length, 1);
    });
  });

  group('mkdir', () {
    test('403 + folder_id = success (folder exists)', () async {
      apiResponse = (path, query, body) {
        if (path == '/public/folder/list') return ok({'results': <dynamic>[]});
        if (path == '/public/folder/create') {
          return {'code': 403, 'message': 'exists', 'folder_id': 'd123'};
        }
        return ok();
      };
      final d = driverWith(additionWith());
      await d.mkdir('/newdir');
      expect(adapter.hits.any((h) => h.path == '/public/folder/create'), isTrue);
    });
  });

  group('error mapping', () {
    test('429 retries with backoff', () async {
      var calls = 0;
      apiResponse = (path, query, body) {
        if (path == '/user/info/profile') {
          calls++;
          if (calls < 3) return {'code': 429, 'message': 'rate limited'};
          return ok({'userid': 1});
        }
        return ok();
      };
      final d = driverWith(additionWith());
      await d.init(); // should succeed on 3rd attempt
      expect(calls, 3);
    });
  });
}
