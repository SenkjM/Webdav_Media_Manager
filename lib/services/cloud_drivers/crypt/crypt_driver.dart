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
      // 底线：解不开也原样列出，条目绝不丢（99 §7.5）。
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
  Stream<List<int>> openContent(String path) async* {
    final src = _requireSource();
    final inner = await src.get(_mapToInner(path, lastIsFile: true));
    final url = inner.rawUrl;
    if (url == null || url.isEmpty) {
      throw const CloudDriverException('crypt 源不提供直链，无法解密内容');
    }
    final dio = Dio();
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: inner.rawHeaders,
        ),
      );
      final cipherBytes = Uint8List.fromList(res.data ?? const <int>[]);
      yield _cipher.decrypt(cipherBytes);
    } finally {
      dio.close();
    }
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
            ('base64', 'Base64（OpenList 默认）'),
            ('base32', 'Base32（rclone 传统）'),
          ],
          hint: '与 rclone 的 filename_encoding 对应；base32768 暂不支持',
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
          hint: '留空用内置默认盐；与 rclone 相同密码 + 盐可互认',
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
