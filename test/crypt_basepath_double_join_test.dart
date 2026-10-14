// crypt basePath 双拼 bug 坐实（纯路径断言，不走网络）。
//
// bug 本质：crypt_driver._mapToInner 在返回路径里**已经拼了 src.basePath**
// （crypt_driver.dart:176 `parts = <String>[src.basePath]`），而
// WebDavAccountSource 的 `_join` 又会**再拼一次 basePath**
// （webdav_source.dart:31）。于是 WebDavService 收到的最终路径里 basePath
// 出现两次：/vault/vault/<加密段>。
//
// 为什么现有测试全绿、真机默认配置也不炸：
//   1. FakeCloudSource 的 list/writeFile 不调 _join，直接拿传入路径查表
//      （crypt_driver_test.dart 的 writes 断言看到的就是单拼路径）；
//   2. basePath 为根 `/` 时 cloudJoinPath 归一后 `/` 等于没拼，双拼无害。
//
// 真机触发条件：WebDAV 源账号 remotePath 设为非根（如 /vault），再套 crypt，
// 浏览或上传即打到 /vault/vault/... → 404。
//
// 断言策略：截获 WebDavService 收到的最终 path（listDirectory / writeStream
// 都是在 _join 之后才被调用的出口），直接数 basePath 段出现次数。
// 预期：修复后这两个测试应该失败（次数 == 1）；当前 bug 下通过（次数 >= 2）。

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/webdav_source.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';

/// 截获最终请求路径的假 WebDavService：只记录，不发任何请求。
class _RecordingWebDavService extends WebDavService {
  final List<String> listPaths = [];
  final List<String> writePaths = [];

  @override
  Future<List<WebDavItem>> listDirectory(
    String accountId,
    String path, {
    FileTypeConfig? fileTypes,
  }) async {
    listPaths.add(path);
    return const <WebDavItem>[];
  }

  @override
  Future<void> writeStream(
    String accountId,
    String remotePath,
    Stream<List<int>> data,
    int length, {
    void Function(int count, int total)? onProgress,
    dynamic cancelToken,
  }) async {
    writePaths.add(remotePath);
    await data.drain<void>();
  }
}

void main() {
  late _RecordingWebDavService webDav;
  late WebDavAccountSource source;
  late CryptDriver driver;

  setUp(() {
    webDav = _RecordingWebDavService();
    // remotePath = /vault（非根）——双拼只在非根 basePath 下可见。
    source = WebDavAccountSource(
      webDav: webDav,
      account: WebDavAccount(
        id: 'src1',
        name: '源',
        url: 'http://example.test/dav',
        username: 'u',
        remotePath: '/vault',
      ),
    );
    driver = CryptDriver(
      config: {
        'source_account_id_name': '源',
        'source_dir': '/',
        'password': 'testpass',
        'salt': 'testsalt',
        'filename_encryption': 'standard',
        'directory_name_encryption': true,
        'filename_encoding': 'base32',
      },
      env: CloudDriverEnv(
        resolveSource: (_) => null,
        resolveSourceByName: (name) => name == '源' ? source : null,
      ),
    );
  });

  test('坐实双拼：crypt.list 时 WebDavService 收到的路径 basePath 出现两次',
      () async {
    await driver.init();
    await driver.list('/');

    expect(webDav.listPaths, hasLength(1));
    final requested = webDav.listPaths.single;

    // 双拼已修：_mapToInner 不再拼 src.basePath，路径中 /vault 应恰好出现 1 次。
    final occurrences = '/vault'.allMatches(requested).length;
    expect(
      occurrences,
      equals(1),
      reason: '双拼已修：路径中 /vault 应恰好出现一次。实际路径：$requested',
    );
    expect(requested, isNot(startsWith('/vault/vault/')));
  });

  test('修复验证：crypt.uploadStream 时 writeStream 收到的路径 basePath 只出现一次',
      () async {
    await driver.init();
    await driver.uploadStream(
      '/dir/track.bin',
      Stream<List<int>>.value(const [1, 2, 3]),
      3,
    );

    expect(webDav.writePaths, hasLength(1));
    final requested = webDav.writePaths.single;

    final occurrences = '/vault'.allMatches(requested).length;
    expect(
      occurrences,
      equals(1),
      reason: '双拼已修：路径中 /vault 应恰好出现一次。实际路径：$requested',
    );
    expect(requested, isNot(startsWith('/vault/vault/')));
  });
}