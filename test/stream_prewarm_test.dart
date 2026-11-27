import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/webdav_stream.dart';
import 'package:webdav_media_manager/utils/stream_prewarm.dart';

WebDavStreamSource _source(String uri, {int size = 0, bool viaProxy = true}) {
  return WebDavStreamSource(
    uri: uri,
    headers: const {},
    name: 'movie.mp4',
    remotePath: '/movie.mp4',
    accountId: 'account',
    size: size,
    viaProxy: viaProxy,
  );
}

void main() {
  test('prewarm reads the head and tail of a proxied stream', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ranges = <String>[];
    server.listen((request) async {
      ranges.add(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.write('x');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final source = _source(
      'http://127.0.0.1:${server.port}/s/token',
      size: 8 * 1024 * 1024,
    );
    await prewarmStream(source);
    // Tail warm-up is fire-and-forget; give it a moment to land.
    for (var i = 0; i < 50 && ranges.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(ranges, hasLength(2));
    expect(ranges[0], 'bytes=0-${prewarmHeadBytes - 1}');
    expect(
      ranges[1],
      'bytes=${8 * 1024 * 1024 - prewarmTailBytes}-${8 * 1024 * 1024 - 1}',
    );
  });

  test('prewarm skips direct upstream urls', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await prewarmStream(
      _source('http://127.0.0.1:${server.port}/direct', viaProxy: false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(requests, 0);
  });

  test('prewarm never throws when the proxy rejects the range', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await prewarmStream(_source('http://127.0.0.1:${server.port}/s/token'));
  });
}
