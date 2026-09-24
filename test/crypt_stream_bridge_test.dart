import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/cipher/rclone_cipher.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_stream_bridge.dart';

import 'crypt_driver_test.dart' show FakeCloudSource;

/// 假驱动：区间读取直接切内存字节，用来单独验证桥的 HTTP 语义。
class _SliceDriver extends CloudDriver {
  _SliceDriver(this.bytes);

  final Uint8List bytes;
  final List<(int, int)> calls = [];

  @override
  Stream<List<int>> openContentRange(String path, int start, int end) async* {
    calls.add((start, end));
    yield Uint8List.sublistView(bytes, start, end + 1);
  }

  @override
  Future<void> init() async {}

  @override
  Future<List<CloudFileItem>> list(String path) async => const <CloudFileItem>[];

  @override
  Future<CloudFileItem> get(String path) => throw UnimplementedError();

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

/// 密文源服务：像真实网盘直链那样支持 Range。
class _RangeServer {
  _RangeServer(this.body);

  final Uint8List body;
  late final HttpServer server;
  int requests = 0;

  Future<Uri> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests++;
      final resp = req.response;
      var start = 0;
      var end = body.length - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      resp.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (range != null && range.startsWith('bytes=')) {
        final spec = range.substring(6).split(',').first;
        final dash = spec.indexOf('-');
        start = int.parse(spec.substring(0, dash));
        final endRaw = spec.substring(dash + 1);
        if (endRaw.isNotEmpty) end = int.parse(endRaw);
        if (end > body.length - 1) end = body.length - 1;
        resp.statusCode = HttpStatus.partialContent;
        resp.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${body.length}',
        );
      }
      resp.headers.contentLength = end - start + 1;
      resp.add(Uint8List.sublistView(body, start, end + 1));
      await resp.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/f');
  }

  Future<void> stop() => server.close(force: true);
}

/// 直链源：get() 给出指向本地密文服务的 URL（crypt 靠它拉密文）。
class _LinkSource extends FakeCloudSource {
  _LinkSource(super.cipher, this.url);

  final Uri url;

  @override
  Future<CloudFileItem> get(String path) async {
    final bytes = contents[path] ?? contents.values.first;
    return CloudFileItem(
      name: path.split('/').last,
      isDir: false,
      size: bytes.length,
      rawUrl: url.toString(),
    );
  }
}

Future<Uint8List> collect(HttpClientResponse response) async {
  final builder = BytesBuilder();
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.toBytes();
}

void main() {
  test('桥：HEAD / 全量 / Range / 后缀 Range / 未知 token', () async {
    final bytes = Uint8List.fromList(List<int>.generate(1000, (i) => i & 0xFF));
    final driver = _SliceDriver(bytes);
    final bridge = CryptStreamBridge((_) => driver);
    final uri = await bridge.expose(
      accountId: 'a1',
      remotePath: '/f.bin',
      size: bytes.length,
    );
    expect(uri.host, '127.0.0.1');
    final client = HttpClient();

    final head = await (await client.headUrl(uri)).close();
    expect(head.statusCode, HttpStatus.ok);
    expect(head.headers.contentLength, bytes.length);
    await head.drain<void>();

    final full = await (await client.getUrl(uri)).close();
    expect(full.statusCode, HttpStatus.ok);
    expect(await collect(full), bytes);

    final rangeReq = await client.getUrl(uri);
    rangeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
    final part = await rangeReq.close();
    expect(part.statusCode, HttpStatus.partialContent);
    expect(part.headers.value(HttpHeaders.contentRangeHeader), 'bytes 10-19/1000');
    expect(await collect(part), bytes.sublist(10, 20));
    expect(driver.calls.last, (10, 19));

    final suffixReq = await client.getUrl(uri);
    suffixReq.headers.set(HttpHeaders.rangeHeader, 'bytes=-5');
    final suffix = await suffixReq.close();
    expect(await collect(suffix), bytes.sublist(995));

    final missing = await client
        .getUrl(Uri.parse('http://127.0.0.1:${uri.port}/s/deadbeef'))
        .then((r) => r.close());
    expect(missing.statusCode, HttpStatus.notFound);
    await missing.drain<void>();

    client.close();
    await bridge.dispose();
  });

  test('crypt：区间读取按块解密，数字与明文切片一致', () async {
    final cipher = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
    );
    final plain = Uint8List.fromList(
      List<int>.generate(200000, (i) => (i * 31 + 7) & 0xFF),
    );
    final enc = cipher.encrypt(plain);
    final server = _RangeServer(enc);
    final url = await server.start();
    final source = _LinkSource(cipher, url);
    source.entries['/x'] = (false, enc.length);
    source.contents['/x'] = enc;
    final driver = CryptDriver(config: {
      'source_account_id': 'src1',
      'source_dir': '',
      'password': 'testpass',
      'salt': 'testsalt',
      'filename_encryption': 'off',
      'directory_name_encryption': false,
      'filename_encoding': 'base32',
    }, env: CloudDriverEnv(resolveSource: (_) => source));
    await driver.init();

    final whole = BytesBuilder();
    await for (final chunk in driver.openContent('/movie.mp4')) {
      whole.add(chunk);
    }
    expect(whole.toBytes(), plain);

    // 65000..132000 跨第 0/1/2 块，首尾块都要裁剪。
    final part = BytesBuilder();
    await for (final chunk in driver
        .openContentRange('/movie.mp4', 65000, 132000)) {
      part.add(chunk);
    }
    expect(part.toBytes(), plain.sublist(65000, 132001));

    // 桥端到端：播放器式 Range 请求拿到解密后的字节。
    final bridge = CryptStreamBridge((_) => driver);
    final uri = await bridge.expose(
      accountId: 'a1',
      remotePath: '/movie.mp4',
      size: plain.length,
    );
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=65530-65600');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.partialContent);
    expect(await collect(response), plain.sublist(65530, 65601));
    client.close();
    await bridge.dispose();
    await server.stop();
  });
}
