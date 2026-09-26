// crypt 读取路径的性能 / 健壮性回归（真机「浏览加密目录卡顿」后的优化）。
//
// 锁死四件事：
//   1. 按批 Range：2MiB 文件只发 3 个请求（头 + 首块、再两批），不是一块一个；
//   2. 解析缓存：同一文件的连续区间读取不重复解析直链，也不重复取首块；
//   3. 直链过期（401/403/404/410）自动重解析一次，长下载不半途而废；
//   4. 内容损坏 → CloudDriverDataException（重试无用），下载队列不再退避重试。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_driver.dart';
import 'package:webdav_media_manager/services/download_queue_service.dart';

/// 计数版密文服务器：记录每个 Range 请求、并发度，并可按 URL 里的 `v` 模拟
/// 直链过期、按请求序号模拟限流。
class CountingCipherServer {
  CountingCipherServer(this.body);

  final Uint8List body;
  late HttpServer server;

  /// 收到的 Range 头（按顺序）。
  final List<String> rangeHeaders = [];

  /// 拒绝 `staleV` 版本的**数据块**请求（start > 0），模拟直链 TTL 到期。
  String? staleV;
  int denied = 0;

  /// 每个请求的响应延迟（让并发真的能叠起来 / 让窗口可观测）。
  Duration delay = Duration.zero;

  /// 第 N 个请求回 429（只回一次），模拟源限流。
  int? rateLimitRequest;
  int rateLimited = 0;

  int inflight = 0;
  int maxInflight = 0;

  int get requestCount => rangeHeaders.length;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value('range');
      rangeHeaders.add(range ?? '(none)');
      inflight++;
      if (inflight > maxInflight) maxInflight = inflight;
      try {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        final m = range == null
            ? null
            : RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
        final start = m == null ? 0 : int.parse(m.group(1)!);
        final v = req.uri.queryParameters['v'];
        if (staleV != null && v == staleV && start > 0) {
          denied++;
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }
        if (rateLimitRequest != null &&
            rangeHeaders.length == rateLimitRequest) {
          rateLimitRequest = null;
          rateLimited++;
          req.response.statusCode = HttpStatus.tooManyRequests;
          await req.response.close();
          return;
        }
        if (m != null) {
          final s = start;
          var e = int.parse(m.group(2)!);
          if (e >= body.length) e = body.length - 1;
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            'content-range',
            'bytes $s-$e/${body.length}',
          );
          req.response.contentLength = e - s + 1;
          req.response.add(body.sublist(s, e + 1));
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.contentLength = body.length;
          req.response.add(body);
        }
        await req.response.close();
      } finally {
        inflight--;
      }
    });
  }

  Future<void> close() => server.close(force: true);
}

/// 内容源：直链带 `v=<解析次数>`（模拟每次解析拿到的都是新的临时直链）。
class _LinkSource implements CloudSource {
  _LinkSource({
    required this.server,
    this.cipherSize = 0,
    this.entries = const [],
  });

  final CountingCipherServer server;
  final int cipherSize;

  /// (名字, 是否目录, 大小)——目录列表用（名字已按当前 cipher 加密）。
  final List<(String, bool, int)> entries;

  int getCalls = 0;

  @override
  String get basePath => '';

  @override
  String get displayName => 'Fake';

  @override
  int get capabilities => 0xFFFF;

  @override
  Future<List<CloudFileItem>> list(String path) async => [
    for (final (name, isDir, size) in entries)
      CloudFileItem(name: name, isDir: isDir, size: size),
  ];

  @override
  Future<CloudFileItem> get(String path) async {
    getCalls++;
    return CloudFileItem(
      name: path.split('/').last,
      isDir: false,
      size: cipherSize,
      rawUrl: 'http://127.0.0.1:${server.server.port}/f?v=$getCalls',
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

  setUpAll(() {
    cipher = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.off,
    );
  });

  CryptDriver buildDriver(CloudSource source) => CryptDriver(
    config: {
      'source_account_id_name': '源A',
      'password': 'testpass',
      'salt': 'testsalt',
      'filename_encryption': 'off',
    },
    env: CloudDriverEnv(
      resolveSource: (_) => null,
      resolveSourceByName: (name) => name == '源A' ? source : null,
    ),
  );

  Future<Uint8List> drain(Stream<List<int>> stream) async {
    final out = BytesBuilder();
    await for (final c in stream) {
      out.add(c);
    }
    return out.toBytes();
  }

  test('按批 Range：2MiB + 尾巴只发 3 个请求（头/首块合并 + 两批）', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(2 * 1024 * 1024 + 100, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      expect(await drain(driver.openContent('/big.bin')), plain);
      // 33 个块：1 个请求带回头 + 首块，剩下 32 块分 2 批。
      expect(srv.requestCount, 3, reason: '一块一个请求会把大文件拆成上万个往返');
      expect(
        srv.rangeHeaders.first,
        'bytes=0-65583',
        reason: '文件头与首块必须在同一个请求里取回',
      );
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('区间读取跨多块也只发一个请求', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(10 * 65536, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      // 从第 1 块拖到第 9 块：8 个块必须在同一个 Range 里取。
      final got = await drain(
        driver.openContentRange('/big.bin', 65536, 9 * 65536),
      );
      expect(got, plain.sublist(65536, 9 * 65536 + 1));
      expect(srv.requestCount, 2, reason: '头 + 首块一个请求，其余块一个批量请求');
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('解析缓存：连续读同一文件不重复解析直链 / 不重复取首块', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(3 * 65536, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      final first = await drain(driver.openContentRange('/v.mp4', 0, 100));
      expect(source.getCalls, 1);
      final requestsAfterFirst = srv.requestCount;
      final second = await drain(driver.openContentRange('/v.mp4', 200, 300));
      expect(second, plain.sublist(200, 301));
      expect(first, plain.sublist(0, 101));
      expect(source.getCalls, 1, reason: '45s 内直链复用，不再解析');
      expect(
        srv.requestCount,
        requestsAfterFirst,
        reason: '首块已随解析请求带回，第二次读取不再打源站',
      );

      // 目录被改动过 → 缓存的直链可能已失效，整批丢掉重新解析。
      await driver.mkdir('/newdir');
      await drain(driver.openContentRange('/v.mp4', 0, 10));
      expect(source.getCalls, 2, reason: '改动目录后必须重新解析直链');
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('直链过期（403）：自动重解析一次后继续，不半途而废', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(2 * 65536 + 10, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    await srv.start();
    srv.staleV = '1'; // 第一次解析拿到的直链：数据块一律 403
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      expect(await drain(driver.openContent('/expired.bin')), plain);
      expect(srv.denied, greaterThan(0), reason: '确实撞上了过期直链');
      expect(source.getCalls, 2, reason: '撞上过期直链后重新解析了一次');
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('内容损坏 → CloudDriverDataException，且下载队列判定为不可重试', () async {
    final plain = Uint8List.fromList(List<int>.generate(1000, (i) => i % 251));
    final enc = cipher.encrypt(plain);
    enc[40] ^= 0xFF; // 破坏第 0 块的密文
    final srv = CountingCipherServer(enc);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      await expectLater(
        drain(driver.openContent('/broken.bin')),
        throwsA(isA<CloudDriverDataException>()),
      );
      expect(
        DownloadQueueService.isRetryable(const CloudDriverDataException('坏块')),
        isFalse,
        reason: '同一份字节再拉一次还是坏的，重试没有意义',
      );
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('预取窗口：多批同时在途（并发 > 1），内容仍逐字节正确', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(4 * 1024 * 1024, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    // 每个请求 150ms：网络时延远大于 CPU（解密 4MiB 约 55ms），因此「有没有
    // 真并发」能被墙钟时间区分开。
    srv.delay = const Duration(milliseconds: 150);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      final sw = Stopwatch()..start();
      expect(await drain(driver.openContent('/big.bin')), plain);
      sw.stop();
      expect(
        srv.maxInflight,
        greaterThan(1),
        reason: '多批必须同时在途：Dart 单线程下「提前发下一个」无法与同步解密重叠',
      );
      expect(
        srv.maxInflight,
        greaterThanOrEqualTo(3),
        reason: '预取窗口要真的用满（实测 5 个请求里 4 个同时在途）',
      );
      expect(
        srv.maxInflight,
        lessThanOrEqualTo(4),
        reason: '预取窗口是有上限的（内存 / 风控），不能无限并',
      );
      expect(srv.requestCount, 5, reason: '4MiB = 64 块：头+首块一个请求，其余 63 块分 4 批');
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('区间预取窗口：多批同时在途，seek 区间内容正确', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(4 * 1024 * 1024, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    srv.delay = const Duration(milliseconds: 150);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      expect(
        await drain(driver.openContentRange('/seek.bin', 0, plain.length - 1)),
        plain,
      );
      expect(srv.maxInflight, greaterThanOrEqualTo(3));
      expect(srv.maxInflight, lessThanOrEqualTo(4));
      expect(srv.requestCount, 5);
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('活动区间流在缓存失效后仍可完成', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(2 * 1024 * 1024, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    srv.delay = const Duration(milliseconds: 100);
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    final out = BytesBuilder();
    try {
      final subscription = driver
          .openContentRange('/active.bin', 0, plain.length - 1)
          .listen(out.add);
      for (var i = 0; i < 100 && srv.inflight == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(srv.inflight, greaterThan(0));
      await driver.mkdir('/invalidate');
      await subscription.asFuture<void>();
      expect(out.takeBytes(), plain);
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('源限流 429：退掉并发并重试同一区间，内容完整', () async {
    final plain = Uint8List.fromList(
      List<int>.generate(3 * 65536, (i) => i % 251),
    );
    final enc = cipher.encrypt(plain);
    final srv = CountingCipherServer(enc);
    srv.rateLimitRequest = 2; // 第 2 个请求（第一个数据批）被限流一次
    await srv.start();
    final source = _LinkSource(server: srv, cipherSize: enc.length);
    final driver = buildDriver(source);
    try {
      expect(await drain(driver.openContent('/limited.bin')), plain);
      expect(srv.rateLimited, 1, reason: '确实撞上限流');
      expect(srv.requestCount, greaterThan(0));
    } finally {
      await driver.dispose();
      await srv.close();
    }
  });

  test('大目录名字解密走 isolate，结果与小目录就地解密一致', () async {
    final srv = CountingCipherServer(Uint8List(0));
    await srv.start();
    try {
      // 小目录：就地做。
      final small = <(String, bool, int)>[
        (cipher.encryptFileName('hello.txt'), false, 100),
        (cipher.encryptDirName('sub'), true, 0),
      ];
      final smallSrc = _LinkSource(server: srv, entries: small);
      CryptDriver.nameIsolateRuns = 0;
      final smallItems = await buildDriver(smallSrc).list('/');
      expect(CryptDriver.nameIsolateRuns, 0, reason: '小目录不值得起 isolate');

      // 大目录：整批丢 isolate（门槛按实测定在约 1900 条短名，这里留够余量）。
      final big = <(String, bool, int)>[
        for (var i = 0; i < 2500; i++)
          (
            cipher.encryptFileName(
              'track-${i.toString().padLeft(4, '0')}.flac',
            ),
            false,
            1000,
          ),
        (cipher.encryptDirName('album'), true, 0),
      ];
      final bigSrc = _LinkSource(server: srv, entries: big);
      CryptDriver.nameIsolateRuns = 0;
      final bigItems = await buildDriver(bigSrc).list('/');
      expect(CryptDriver.nameIsolateRuns, 1, reason: '超大目录整批丢 isolate');
      expect(bigItems.length, big.length);
      expect(bigItems.first.name, 'track-0000.flac');
      expect(bigItems.last.name, 'album');
      expect(bigItems.last.isDir, isTrue);
      expect(smallItems.first.name, 'hello.txt');
      expect(smallItems[1].name, 'sub');
    } finally {
      await srv.close();
    }
  });

  test('解不开的名字按原名列出（只读取，不改动远端）', () async {
    final srv = CountingCipherServer(Uint8List(0));
    await srv.start();
    try {
      final src = _LinkSource(
        server: srv,
        entries: [
          ('not-encrypted-at-all.txt', false, 10),
          (cipher.encryptFileName('ok.txt'), false, 20),
        ],
      );
      final items = await buildDriver(src).list('/');
      expect(items.first.name, 'not-encrypted-at-all.txt');
      expect(items[1].name, 'ok.txt');
    } finally {
      await srv.close();
    }
  });

  test('运行时类型名：跟着源走，源缺失退化成 Crypt', () async {
    final srv = CountingCipherServer(Uint8List(0));
    await srv.start();
    try {
      final src = _LinkSource(server: srv);
      expect(buildDriver(src).runtimeTypeLabel, 'Fake Crypt');
      final orphan = CryptDriver(
        config: const {'source_account_id_name': 'missing'},
        env: CloudDriverEnv(
          resolveSource: (_) => null,
          resolveSourceByName: (_) => null,
        ),
      );
      expect(orphan.runtimeTypeLabel, 'Crypt');
    } finally {
      await srv.close();
    }
  });
}
