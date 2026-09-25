import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../models/account_capabilities.dart';
import '../../cloud_driver.dart';
import 'cipher/rclone_cipher.dart';

/// crypt 驱动（99 §7.5）：包一层源账号，名字 / 内容按 rclone crypt 格式
/// 加解密。只读链路 + 目录名加密（建目录 / 改名 / 移动 / 复制），无内容上传。
class CryptDriver extends CloudDriver {
  CryptDriver({
    required Map<String, dynamic> config,
    CloudDriverEnv? env,
  }) : _env = env {
    _cipher = RcloneCipher(
      password: (config['password'] as String?) ?? '',
      salt: (config['salt'] as String?) ?? '',
      mode: nameModeFromConfig((config['filename_encryption'] as String?) ?? 'off'),
      dirNameEncrypt: (config['directory_name_encryption'] as bool?) ?? false,
      nameEncoding: (config['filename_encoding'] as String?) ?? 'base64',
      encryptedSuffix: (config['encrypted_suffix'] as String?) ?? kDefaultEncryptedSuffix,
    );
    _sourceAccountId = (config['source_account_id'] as String?) ?? '';
    _sourceDir = (config['source_dir'] as String?) ?? '/';
  }

  final CloudDriverEnv? _env;
  late RcloneCipher _cipher;
  late String _sourceAccountId;
  late String _sourceDir;
  CloudSource? _source;

  @override
  Future<void> init() async {
    _requireSource();
  }

  /// 懒解析：源账号被删后再次访问会在这里报错（浏览界面可见），
  /// 不影响兼容层注册流程。
  CloudSource _requireSource() {
    final cached = _source;
    if (cached != null) return cached;
    final s = _env?.resolveSource(_sourceAccountId);
    if (s == null) {
      throw CloudDriverException('crypt 源账号不存在或已删除（源 id：$_sourceAccountId）');
    }
    _source = s;
    return s;
  }

  /// 外层明文路径 → 内层密文路径：源浏览根 + 源目录 + 逐段加密。
  String _mapToInner(String outerPath, {required bool lastIsFile}) {
    final src = _requireSource();
    final segs = outerPath.split('/').where((s) => s.isNotEmpty).toList();
    final parts = <String>[src.basePath];
    parts.addAll(_sourceDir.split('/'));
    for (var i = 0; i < segs.length; i++) {
      final last = i == segs.length - 1;
      parts.add((!last || !lastIsFile)
          ? _cipher.encryptDirName(segs[i])
          : _cipher.encryptFileName(segs[i]));
    }
    return cloudJoinPath(parts);
  }

  /// 内层条目 → 外层视角：解密名字（失败原名透传）、换算明文大小、
  /// 抹掉密文直链（MustProxy，内容走 [openContent]）。
  CloudFileItem _reveal(CloudFileItem e) {
    String name = e.name;
    try {
      name = e.isDir
          ? _cipher.decryptDirName(e.name)
          : _cipher.decryptFileName(e.name);
    } catch (_) {
      // 解不开的名字按原名列出：只读取、不改动远端，也不做二次加密（99 §7.5）。
    }
    var size = e.size;
    if (!e.isDir) {
      try {
        size = RcloneCipher.decryptedSize(e.size);
      } catch (_) {
        // 大小换算失败用内层原值（OpenList 同款告警语义）。
      }
    }
    return CloudFileItem(
      name: name,
      isDir: e.isDir,
      size: size,
      modified: e.modified,
      rawUrl: null,
    );
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final src = _requireSource();
    final inner = await src.list(_mapToInner(path, lastIsFile: false));
    return [for (final e in inner) _reveal(e)];
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final src = _requireSource();
    final e = await src.get(_mapToInner(path, lastIsFile: true));
    final revealed = _reveal(CloudFileItem(
      name: e.name,
      isDir: false,
      size: e.size,
      modified: e.modified,
    ));
    return CloudFileItem(
      name: revealed.name,
      isDir: false,
      size: revealed.size,
      modified: revealed.modified,
      rawUrl: null,
    );
  }

  @override
  Future<void> mkdir(String path) =>
      _requireSource().mkdir(_mapToInner(path, lastIsFile: false));

  @override
  Future<void> rename(String path, String newPath) async {
    final src = _requireSource();
    try {
      await src.rename(
        _mapToInner(path, lastIsFile: true),
        _mapToInner(newPath, lastIsFile: true),
      );
    } on CloudDriverException {
      // 末段可能是目录：按目录映射重试。
      await src.rename(
        _mapToInner(path, lastIsFile: false),
        _mapToInner(newPath, lastIsFile: false),
      );
    }
  }

  @override
  Future<void> remove(String path) async {
    final src = _requireSource();
    try {
      await src.remove(_mapToInner(path, lastIsFile: true));
    } on CloudDriverException {
      await src.remove(_mapToInner(path, lastIsFile: false));
    }
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final src = _requireSource();
    try {
      await src.move(
        _mapToInner(srcPath, lastIsFile: true),
        _mapToInner(dstDir, lastIsFile: false),
        _cipher.encryptFileName(newName),
      );
    } on CloudDriverException {
      await src.move(
        _mapToInner(srcPath, lastIsFile: false),
        _mapToInner(dstDir, lastIsFile: false),
        _cipher.encryptDirName(newName),
      );
    }
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final src = _requireSource();
    try {
      await src.copy(
        _mapToInner(srcPath, lastIsFile: true),
        _mapToInner(dstDir, lastIsFile: false),
        _cipher.encryptFileName(newName),
      );
    } on CloudDriverException {
      await src.copy(
        _mapToInner(srcPath, lastIsFile: false),
        _mapToInner(dstDir, lastIsFile: false),
        _cipher.encryptDirName(newName),
      );
    }
  }

  /// 解密后的内容流（下载 / 缓存的内存流路径，99 §7.5）。
  /// 取内层密文直链 → 拉全量 → 分块认证解密；块失败即抛，不落坏数据。
  @override
  /// 分段读取 + 逐块解密（99 §7.5）：
  /// * 先取 32 字节文件头拿到 nonce；
  /// * 再按 rclone 块（64KiB 明文 + 16B MAC）逐块 Range 拉取、逐块认证；
  /// * 每块立即 yield —— 下载队列的进度随块推进，内存占用只有一块；
  /// * 源忽略 Range（一次返回整包）或大小未知时，退回整包解密。
  Stream<List<int>> openContent(String path) async* {
    final t = await _openTarget(path);
    try {
      switch (t.shape) {
        case _CryptTarget.shapeWholeBody:
          // 源不支持 Range（一次回整包）：整包解密。
          yield _cipher.decrypt(t.header);
          return;
        case _CryptTarget.shapeEmptyFile:
          // 密文只有文件头：合法的 0 字节明文文件。
          return;
        case _CryptTarget.shapeUnknownSize:
          throw const CloudDriverException(
              '无法确定加密内容的大小（源未提供长度且不支持 Range）');
        default:
          break; // shapeRanged：走下方分块解密。
      }
      var offset = kFileHeaderSize;
      var block = 0;
      while (offset < t.cipherSize) {
        var end = offset + kBlockSize - 1;
        if (end > t.cipherSize - 1) end = t.cipherSize - 1;
        final chunk = await _fetchRange(t.dio, t.url, t.headers, offset, end);
        if (chunk.isEmpty) {
          throw CloudDriverException('crypt 内容在第 $block 块处中断');
        }
        yield _cipher.decryptBlock(t.nonce, block, chunk);
        offset = end + 1;
        block++;
      }
    } finally {
      t.dio.close();
    }
  }

  /// 明文区间 [start, end]（含端点）→ 只拉取覆盖它的密文块并解密，
  /// 首尾块按需裁剪。ffmpeg 拖动进度条时靠它（99 §7.5 本地流桥）。
  @override
  Stream<List<int>> openContentRange(String path, int start, int end) async* {
    if (start < 0 || end < start) return;
    final t = await _openTarget(path);
    try {
      switch (t.shape) {
        case _CryptTarget.shapeWholeBody:
          final plain = _cipher.decrypt(t.header);
          if (start >= plain.length) return;
          final last = end < plain.length - 1 ? end : plain.length - 1;
          yield Uint8List.sublistView(plain, start, last + 1);
          return;
        case _CryptTarget.shapeEmptyFile:
          return; // 0 字节明文，任何区间都是空。
        case _CryptTarget.shapeUnknownSize:
          throw const CloudDriverException(
              '无法确定加密内容的大小（源未提供长度且不支持 Range）');
        default:
          break; // shapeRanged：走下方分块解密。
      }
      final plainSize = RcloneCipher.decryptedSize(t.cipherSize);
      if (start >= plainSize) return;
      final last = end < plainSize - 1 ? end : plainSize - 1;
      final firstBlock = start ~/ kBlockDataSize;
      final lastBlock = last ~/ kBlockDataSize;
      for (var b = firstBlock; b <= lastBlock; b++) {
        final cipherStart = kFileHeaderSize + b * kBlockSize;
        var cipherEnd = cipherStart + kBlockSize - 1;
        if (cipherEnd > t.cipherSize - 1) cipherEnd = t.cipherSize - 1;
        final chunk =
            await _fetchRange(t.dio, t.url, t.headers, cipherStart, cipherEnd);
        if (chunk.isEmpty) {
          throw CloudDriverException('crypt 内容在第 $b 块处中断');
        }
        final plain = _cipher.decryptBlock(t.nonce, b, chunk);
        final from = b == firstBlock ? start - b * kBlockDataSize : 0;
        final to = b == lastBlock ? last - b * kBlockDataSize + 1 : plain.length;
        if (from <= 0 && to >= plain.length) {
          yield plain;
        } else {
          yield Uint8List.sublistView(plain, from, to);
        }
      }
    } finally {
      t.dio.close();
    }
  }

  /// 解析一次目标：密文直链 + 请求头 + 文件 nonce + 密文长度。
  /// 失败时关闭 Dio，成功时由调用方在 finally 关闭。
  ///
  /// 密文总长的取值优先级：响应 `Content-Range` 的总长（与内容**同请求**，
  /// 不会与实际内容错位）> 源元数据给的 [CloudFileItem.size]。只有两者都
  /// 拿不到（0）才算「大小未知」——用元数据校对内容，防二者错位的竞态。
  Future<_CryptTarget> _openTarget(String path) async {
    final src = _requireSource();
    final inner = await src.get(_mapToInner(path, lastIsFile: true));
    final url = inner.rawUrl;
    if (url == null || url.isEmpty) {
      throw const CloudDriverException('crypt 源不提供直链，无法解密内容');
    }
    final dio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 20)),
    );
    try {
      final head = await _fetchRangeWithMeta(
        dio,
        url,
        inner.rawHeaders,
        0,
        kFileHeaderSize - 1,
      );
      final header = head.$1;
      if (header.length < kFileHeaderSize) {
        throw const CloudDriverException('crypt 内容不完整（读不到文件头）');
      }
      var cipherSize = inner.size > 0 ? inner.size : 0;
      final rangeTotal = head.$2;
      if (rangeTotal != null && rangeTotal > cipherSize) {
        cipherSize = rangeTotal;
      }
      return _CryptTarget(
        dio: dio,
        url: url,
        headers: inner.rawHeaders,
        header: header,
        nonce: RcloneCipher.fileNonceOf(header),
        cipherSize: cipherSize,
      );
    } catch (_) {
      dio.close();
      rethrow;
    }
  }

  /// 取源的 `[start, end]` 字节区间（含端点，与 HTTP Range 语义一致）。
  /// 返回 `(内容, Content-Range 总长或 null)`。
  Future<(Uint8List, int?)> _fetchRangeWithMeta(
    Dio dio,
    String url,
    Map<String, String>? headers,
    int start,
    int end,
  ) async {
    final res = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: <String, String>{
          ...?headers,
          'Range': 'bytes=$start-$end',
        },
        validateStatus: (code) => code != null && code >= 200 && code < 400,
      ),
    );
    return (
      Uint8List.fromList(res.data ?? const <int>[]),
      _parseContentRangeTotal(res.headers.value('content-range')),
    );
  }

  /// 解析 `bytes a-b/total`（total 可为 `*`）→ 总长；无该头或格式不对返回 null。
  static int? _parseContentRangeTotal(String? value) {
    if (value == null) return null;
    final m = RegExp(r'bytes\s+\d+-\d+/(\d+|\*)').firstMatch(value.trim());
    if (m == null) return null;
    final total = m.group(1)!;
    if (total == '*') return null;
    return int.tryParse(total);
  }

  /// 取源的 `[start, end]` 字节区间（含端点，与 HTTP Range 语义一致）。
  Future<Uint8List> _fetchRange(
    Dio dio,
    String url,
    Map<String, String>? headers,
    int start,
    int end,
  ) async {
    return (await _fetchRangeWithMeta(dio, url, headers, start, end)).$1;
  }

  @override
  int? get runtimeCapabilities {
    try {
      final s = _requireSource();
      // 上传权限传递隔离：源即使有 write（WebDAV 配置），crypt 也绝不继承——
      // 内容上传不在 crypt 能力里（99 §7.5 用户决定）。
      return (s.capabilities | AccountCaps.list) & ~AccountCaps.write;
    } catch (_) {
      return null; // 源不存在：回落静态表（保守）。
    }
  }
}

/// crypt 驱动自描述（99 §7.2.10 / §7.5）：字段照 OpenList meta.go 子集 +
/// 源账号 / 源目录（用户决定：源 = 已有账号 id，WebDAV 亦可）。
class CryptSpec extends CloudDriverSpec {
  const CryptSpec();

  @override
  String get typeId => 'crypt';

  @override
  String get displayName => 'Crypt 加密目录';

  // 静态保守值（运行时随源映射并剥 write，见 CryptDriver.runtimeCapabilities）。
  @override
  int get capabilities => AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  List<CloudDriverFormItem> get form => const [
        CloudDriverAccountField(
          key: 'source_account_id',
          label: '源账号',
          required: true,
          hint: '选择现有 WebDAV 或网盘账号作为加密源',
        ),
        CloudDriverField(
          key: 'source_dir',
          label: '源目录',
          hint: '源账号浏览根下的目录，默认 /（加密文件就存在这里）',
        ),
        CloudDriverSelectField(
          key: 'filename_encoding',
          label: '文件名编码',
          required: true,
          defaultValue: 'base64',
          options: [
            ('base64', 'Base64'),
            ('base32', 'Base32'),
            ('base32768', 'Base32768'),
          ],
          hint: '与 rclone 的 filename_encoding 对应（base32 / base64 / base32768）',
        ),
        CloudDriverField(
          key: 'encrypted_suffix',
          label: '文件名后缀',
          defaultValue: '.bin',
          hint: '仅文件名加密=关闭时生效（OpenList encrypted_suffix）',
        ),
        CloudDriverField(
          key: 'password',
          label: '密码',
          required: true,
          obscure: true,
        ),
        CloudDriverField(
          key: 'salt',
          label: '盐值（可选）',
          obscure: true,
          hint: '留空用 rclone 内置默认盐；密码 + 盐相同即可与 rclone / OpenList 互认',
        ),
        CloudDriverSelectField(
          key: 'filename_encryption',
          label: '文件名加密',
          required: true,
          defaultValue: 'off',
          options: [
            ('standard', '标准 (EME)'),
            ('obfuscate', '混淆'),
            ('off', '关闭'),
          ],
        ),
        CloudDriverSwitchField(
          key: 'directory_name_encryption',
          label: '目录名加密',
          subtitle: 'OpenList 默认关闭；开启后目录名同样加密',
          defaultValue: false,
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    return CryptDriver(config: config, env: env);
  }
}
/// 一次解析的结果：密文直链、请求头、文件 nonce 与密文长度。
/// [wholeBody] 为真表示第一次请求就拿回了整包（源不支持 Range）或长度
/// 未知 —— 这时只能整包解密。
class _CryptTarget {
  _CryptTarget({
    required this.dio,
    required this.url,
    required this.headers,
    required this.header,
    required this.nonce,
    required this.cipherSize,
  });

  final Dio dio;
  final String url;
  final Map<String, String>? headers;
  final Uint8List header;
  final Uint8List nonce;
  final int cipherSize;

  /// 内容形态（互斥，判定必须按此顺序）：
  /// - [shapeWholeBody]：第一次请求就回了大头条（源不支持 Range）→ 整包解密；
  /// - [shapeEmptyFile]：密文恰好只有文件头（rclone 空文件的合法格式）→ 空明文；
  /// - 其余按分块 Range 解密。
  /// 「cipherSize 未知」**不再**折叠进 wholeBody：大小未知且头没有变大，
  /// 说明既拿不到总长也拿不到整包，只能明确报错（静默返回空内容 =
  /// 下载出 0 字节损坏文件，真机踩过）。判定见 [_openTarget]。
  static const int shapeWholeBody = 0;
  static const int shapeEmptyFile = 1;
  static const int shapeRanged = 2;
  static const int shapeUnknownSize = 3;

  int get shape {
    if (header.length > kFileHeaderSize) return shapeWholeBody;
    if (cipherSize == kFileHeaderSize) return shapeEmptyFile;
    if (cipherSize > kFileHeaderSize) return shapeRanged;
    return shapeUnknownSize;
  }

  @Deprecated('改用 shape 三态判定，见 [shape] 注释')
  bool get wholeBody => shape == shapeWholeBody || shape == shapeEmptyFile;
}
