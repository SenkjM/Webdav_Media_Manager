// WebDAV 源的 crypt 适配层回归：get() 必须带回密文条目大小。
//
// 真机反馈（源 = WebDAV 时）：流式报「无法确定大小」、下载秒「完成」产出 0B
// 文件——同根因：WebDavAccountSource.get() 返回的 CloudFileItem 没带 size，
// crypt 层把「大小未知」误判成「源回了整包」。
// 本文件锁死：get() 走单文件 PROPFIND（statPath）补 size / modified。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_adapters.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';

void main() {
  late HttpServer server;
  late WebDavService webDav;
  var propfindHits = 0;
  const cipherSize = 123456;

  setUp(() async {
    propfindHits = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.method == 'PROPFIND') {
        propfindHits++;
        final body = '<?xml version="1.0" encoding="utf-8"?>'
            '<D:multistatus xmlns:D="DAV:"><D:response>'
            '<D:href>/dav/enc.bin</D:href>'
            '<D:propstat><D:prop>'
            '<D:getcontentlength>$cipherSize</D:getcontentlength>'
            '<D:getlastmodified>Mon, 01 Jan 2026 00:00:00 GMT</D:getlastmodified>'
            '<D:resourcetype/></D:prop><D:status>HTTP/1.1 200 OK</D:status>'
            '</D:propstat></D:response></D:multistatus>';
        req.response.statusCode = HttpStatus.multiStatus;
        req.response.headers.set('Content-Type', 'application/xml; charset=utf-8');
        req.response.add(utf8.encode(body));
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
    });
    webDav = WebDavService();
    webDav.configure(
      accountId: 'src1',
      url: 'http://127.0.0.1:${server.port}/dav',
      username: 'u',
      password: 'p',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('WebDavAccountSource.get() 带回密文条目大小与修改时间', () async {
    final account = WebDavAccount(
      id: 'src1',
      name: '源',
      url: 'http://127.0.0.1/dav',
      username: 'u',
    );
    final src = WebDavAccountSource(webDav: webDav, account: account);
    final item = await src.get('/enc.bin');
    expect(item.size, cipherSize,
        reason: 'get() 必须带回密文大小——流式 Content-Length、下载进度、'
            'crypt wholeBody 判定都依赖它');
    expect(item.modified, isNotNull);
    expect(item.rawUrl, isNotNull, reason: '直链仍要带回（crypt 拉密文用）');
    expect(propfindHits, greaterThanOrEqualTo(1),
        reason: '必须单独 PROPFIND 一次拿元数据');
  });

  test('statPath 正常返回单文件元数据', () async {
    final stat = await webDav.statPath('src1', '/enc.bin');
    expect(stat, isNotNull);
    expect(stat!.size, cipherSize);
    expect(stat.isDirectory, isFalse);
  });
}
