import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/resumable_download.dart';

const _body = '0123456789';

Future<HttpServer> _serve({required bool honourRange}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final range = req.headers.value('range');
    final match = range == null ? null : RegExp(r'bytes=(\d+)-').firstMatch(range);
    if (honourRange && match != null) {
      final start = int.parse(match.group(1)!);
      req.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          'Content-Range',
          'bytes $start-${_body.length - 1}/${_body.length}',
        )
        ..write(_body.substring(start));
    } else {
      req.response
        ..statusCode = HttpStatus.ok
        ..write(_body);
    }
    req.response.close();
  });
  return server;
}

Future<File> _halfFile(String content) async {
  final dir = await Directory.systemTemp.createTemp('wdmm_resume');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/a.bin');
  await file.writeAsString(content);
  return file;
}

void main() {
  test('parseContentRange 解析合法值、拒绝垃圾', () {
    final ok = parseContentRange('bytes 5-9/10')!;
    expect([ok.start, ok.end, ok.total], [5, 9, 10]);
    expect(parseContentRange(null), isNull);
    expect(parseContentRange('nonsense'), isNull);
  });

  test('源支持 Range：接在已下载的字节后面', () async {
    final server = await _serve(honourRange: true);
    addTearDown(() => server.close(force: true));
    final file = await _halfFile('01234');
    await downloadResumable(
      Dio(),
      'http://127.0.0.1:${server.port}/x',
      const {},
      file,
      resumeFrom: 5,
    );
    expect(await file.readAsString(), _body);
  });

  test('源忽略 Range 回了 200：截断重下，绝不拼接', () async {
    final server = await _serve(honourRange: false);
    addTearDown(() => server.close(force: true));
    final file = await _halfFile('01234');
    await downloadResumable(
      Dio(),
      'http://127.0.0.1:${server.port}/x',
      const {},
      file,
      resumeFrom: 5,
    );
    expect(await file.readAsString(), _body);
  });

  test('半截文件比记录的短：当作没续过，从头下载', () async {
    final server = await _serve(honourRange: false);
    addTearDown(() => server.close(force: true));
    final file = await _halfFile('01');
    await downloadResumable(
      Dio(),
      'http://127.0.0.1:${server.port}/x',
      const {},
      file,
      resumeFrom: 5,
    );
    expect(await file.readAsString(), _body);
  });
}
