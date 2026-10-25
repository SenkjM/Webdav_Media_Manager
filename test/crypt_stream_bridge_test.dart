import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_driver.dart';

import 'crypt_driver_test.dart' show FakeCloudSource;

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

void main() {
  // R12: LocalStreamBridge deleted — the local HTTP-bridge semantics test that
  // used it is removed (the bridge now lives in Rust via wdmm_proxy_register_stream
  // + wdmm_proxy_stream_set_result, which requires libwdmm_ffi.so and cannot run
  // in a pure Dart test). This file now only covers CryptDriver decryption.

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
    final driver = CryptDriver(
      config: {
        'source_account_id': 'src1',
        'source_account_id_name': 'src1',
        'source_dir': '',
        'password': 'testpass',
        'salt': 'testsalt',
        'filename_encryption': 'off',
        'directory_name_encryption': false,
        'filename_encoding': 'base32',
      },
      env: CloudDriverEnv(
        resolveSource: (_) => source,
        resolveSourceByName: (_) => source,
      ),
    );
    await driver.init();

    final whole = BytesBuilder();
    await for (final chunk in driver.openContent('/movie.mp4')) {
      whole.add(chunk);
    }
    expect(whole.toBytes(), plain);

    // 65000..132000 跨第 0/1/2 块，首尾块都要裁剪。
    final part = BytesBuilder();
    await for (final chunk in driver.openContentRange(
      '/movie.mp4',
      65000,
      132000,
    )) {
      part.add(chunk);
    }
    expect(part.toBytes(), plain.sublist(65000, 132001));

    await server.stop();
  });
}
