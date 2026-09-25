// crypt 大小判定竞态回归：元数据 size 与内容实际长度错位时的行为。
//
// 真机反馈（源 = WebDAV）：源适配层拿不到 size → crypt 把「大小未知」
// 误判成「源回了整包」→ 静默解出空内容（下载 0B 文件 / 流式报错）。
// 修复后四条铁律：
//   1. 密文恰 32B = 合法空文件（0B 明文），不是「未知」；
//   2. Content-Range 总长与内容同请求，优先于可能过期的元数据 size；
//   3. 两者都没有 → 明确报错，绝不静默返回空内容；
//   4. 元数据 size 比真实小时按 Content-Range 纠正，不产出截断文件。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_driver.dart';

/// 密文内容服务器：Range 语义可配置，用于模拟各种源行为。
class CipherServer {
  CipherServer(this.body);

  final Uint8List body;
  late HttpServer server;
  /// false = 忽略 Range（一次回整包 200）；true = 标准 206 + Content-Range。
  bool supportsRange = true;
  /// 是否回 Content-Range 头（「未知大小」模拟：回 206 但不给总长）。
  bool sendContentRange = true;
  /// 元数据侧谎报的 size（CloudFileItem.size）。
  int reportedSize = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value('range');
      final m = range == null ? null : RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      if (supportsRange && m != null) {
        final s = int.parse(m.group(1)!);
        var e = int.parse(m.group(2)!);
        if (e >= body.length) e = body.length - 1;
        req.response.statusCode = HttpStatus.partialContent;
        if (sendContentRange) {
          req.response.headers.set('content-range',
              'bytes $s-$e/${body.length}');
        }
        req.response.contentLength = e - s + 1;
        req.response.add(body.sublist(s, e + 1));
      } else {
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = body.length;
        req.response.add(body);
      }
      await req.response.close();
    });
  }

  Future<void> close() => server.close(force: true);
}

/// 指向 [CipherServer] 的内容源：CloudFileItem.size 可配置（模拟元数据竞态）。
class _FakeSource implements CloudSource {
  _FakeSource(this.srv, {required this.cipherSizeOf});

  final CipherServer srv;
  final int cipherSizeOf;

  @override
  String get basePath => '/src456';

  @override
  int get capabilities => 0xFFFF;

  @override
  Future<List<CloudFileItem>> list(String path) async => const [];

  @override
  Future<CloudFileItem> get(String path) async {
    return CloudFileItem(
      name: path.split('/').last,
      isDir: false,
      size: cipherSizeOf,
      rawUrl: 'http://127.0.0.1:${srv.server.port}/f',
    );
  }

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> rename(String path, String newPath) async {}

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {}

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {}
}

void main() {
  late RcloneCipher cipher;
  late CipherServer srv;

  setUp(() async {
    cipher = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.off,
    );
  });

  tearDown(() async {
    await srv.close();
  });

  CryptDriver buildDriver(_FakeSource source) {
    final env = CloudDriverEnv(resolveSource: (id) => id == 'src1' ? source : null);
    final driver = CryptDriver(config: {
      'source_account_id': 'src1',
      'source_dir': '/789',
      'password': 'testpass',
      'salt': 'testsalt',
      'filename_encryption': 'off',
    }, env: env);
    return driver;
  }

  test('空文件（密文恰 32B）→ openContent 返回空流，不误解为整包', () async {
    final enc = cipher.encrypt(Uint8List(0));
    expect(enc.length, 32, reason: 'rclone 空文件密文 = 32B 文件头');
    srv = CipherServer(enc);
    await srv.start();
    srv.supportsRange = true;
    srv.reportedSize = 32;
    final source = _FakeSource(srv, cipherSizeOf: 32);
    final driver = buildDriver(source);
    final out = <int>[];
    await for (final c in driver.openContent('/empty.flac')) {
      out.addAll(c);
    }
    expect(out, isEmpty, reason: '空文件的明文就是空');
  });

  test('元数据 size=0 但源支持 Range：Content-Range 纠正总长，正常分块解密', () async {
    final plain = Uint8List.fromList(utf8.encode('hello world 你好'));
    final enc = cipher.encrypt(plain);
    srv = CipherServer(enc);
    await srv.start();
    srv.supportsRange = true;
    srv.reportedSize = 0; // 源适配层没拿到 size——正是真机踩的场景
    final source = _FakeSource(srv, cipherSizeOf: 0);
    final driver = buildDriver(source);
    final out = BytesBuilder();
    await for (final c in driver.openContent('/a.flac')) {
      out.add(c);
    }
    expect(out.toBytes(), plain,
        reason: 'Content-Range 总长与内容同请求，能纠正过期的元数据');
  });

  test('元数据 size=0 且源不回 Content-Range：明确报错，不产出空内容', () async {
    final enc = cipher.encrypt(Uint8List.fromList(utf8.encode('data')));
    srv = CipherServer(enc);
    await srv.start();
    srv.supportsRange = true;
    srv.sendContentRange = false; // 拿不到总长
    final source = _FakeSource(srv, cipherSizeOf: 0);
    final driver = buildDriver(source);
    await expectLater(
      driver.openContent('/a.flac').drain<void>(),
      throwsA(isA<CloudDriverException>()),
    );
  });

  test('元数据 size 过期（比真实小）：按 Content-Range 纠正，内容完整', () async {
    final plain = Uint8List.fromList(List.generate(70000, (i) => i % 251));
    final enc = cipher.encrypt(plain);
    srv = CipherServer(enc);
    await srv.start();
    srv.supportsRange = true;
    srv.reportedSize = 100; // 谎报的小 size
    final source = _FakeSource(srv, cipherSizeOf: 100);
    final driver = buildDriver(source);
    final out = BytesBuilder();
    await for (final c in driver.openContent('/big.flac')) {
      out.add(c);
    }
    expect(out.toBytes(), plain,
        reason: 'Content-Range 优先于过期元数据，不产出截断文件');
  });
}
