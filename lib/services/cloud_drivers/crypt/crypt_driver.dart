import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:openlist_crypt/openlist_crypt.dart';

import '../../../models/account_capabilities.dart';
import '../../cloud_driver.dart';

/// crypt 驱动（99 §7.5）：包一层源账号，名字 / 内容按 rclone crypt 格式
/// 加解密。只读链路 + 目录名加密（建目录 / 改名 / 移动 / 复制），无内容上传。
///
/// 性能取向（真机反馈「浏览加密目录卡顿」后的优化）：
/// * **scrypt 走 isolate + 进程内复用**：多花 0.1~1s 在 UI 线程上就是一次
///   明显掉帧；密钥材料是 (密码, 盐) 的纯函数，进程内缓存不改变任何映射。
/// * **网络按批**：一次 Range 取 [_blocksPerBatch] 个块（约 1MiB），不是一块
///   一个请求；开头把文件头和首块并在同一个请求里。
/// * **解析结果短时缓存**：同一文件的直链 / 文件头在 [_targetTtl] 内复用，
///   播放器反复拖动进度条不会每次都重新解析直链。
/// * **名字解密大目录整批丢 isolate**，小目录就地做且定期让出事件循环。
///
/// 分层纪律：`openlist_crypt` 的异常在这里全部翻译成 [CloudDriverException] /
/// [CloudDriverDataException]，密码学细节不越过本文件。
class CryptDriver extends CloudDriver {
  CryptDriver({
    required Map<String, dynamic> config,
    CloudDriverEnv? env,
  }) : _env = env,
       _password = (config['password'] as String?) ?? '',
       _salt = (config['salt'] as String?) ?? '',
       _nameEncoding = (config['filename_encoding'] as String?) ?? 'base64',
       _encryptedSuffix =
           (config['encrypted_suffix'] as String?) ?? kDefaultEncryptedSuffix,
       _dirNameEncrypt =
           (config['directory_name_encryption'] as bool?) ?? false {
    try {
      _nameMode = nameModeFromConfig(
        (config['filename_encryption'] as String?) ?? 'off',
      );
    } on RcloneCipherException catch (e) {
      throw CloudDriverDataException('crypt 配置无效：${e.message}', e);
    }
    _sourceAccountId = (config['source_account_id'] as String?) ?? '';
    _sourceAccountName = (config['source_account_id_name'] as String?) ?? '';
    _sourceDir = (config['source_dir'] as String?) ?? '/';
    // 后台先把 scrypt 跑起来（在 isolate 里）：用户真正浏览时通常已经就绪。
    // 派生失败不在这里报——真正要用密码的那一刻会原样抛出。
    unawaited(_materialFuture.then((_) {}, onError: (Object _) {}));
  }

  final CloudDriverEnv? _env;
  final String _password;
  final String _salt;
  final String _nameEncoding;
  final String _encryptedSuffix;
  final bool _dirNameEncrypt;
  late final NameEncryptionMode _nameMode;
  late String _sourceAccountId;

  /// 保存时的源账号名快照：源被删后重添**同名**账号可按名恢复
  /// （真机反馈：报错显示一长串源 id，重加源也接不上）。
  late String _sourceAccountName;
  late String _sourceDir;
  CloudSource? _source;

  // ── 密钥：isolate 派生 + 进程内复用 ──

  /// 进程内密钥材料缓存上限（条 = 一份 (密码, 盐)）。
  static const int _keyCacheLimit = 4;
  static final Map<String, Future<Uint8List>> _keyCache =
      <String, Future<Uint8List>>{};
  static final Queue<String> _keyCacheOrder = Queue<String>();

  /// scrypt 是 (密码, 盐) 的纯函数 → 同一份配置派生一次就够。驱动实例在每次
  /// `registerAccounts` 都会被重建，不缓存就要反复付这笔钱。
  ///
  /// **只在内存里**：密钥材料不落盘（用户明确否决落盘缓存）。
  static Future<Uint8List> _keyMaterial(String password, String salt) {
    final cacheKey = '$password\u0000$salt';
    final cached = _keyCache[cacheKey];
    if (cached != null) return cached;
    final future = deriveKeyMaterial(password: password, salt: salt);
    _keyCache[cacheKey] = future;
    _keyCacheOrder.add(cacheKey);
    while (_keyCacheOrder.length > _keyCacheLimit) {
      _keyCache.remove(_keyCacheOrder.removeFirst());
    }
    // 派生失败不要留在缓存里（否则这个配置永远起不来），失败本身交给调用方。
    unawaited(
      future.then(
        (_) {},
        onError: (Object _) {
          _keyCache.remove(cacheKey);
          _keyCacheOrder.remove(cacheKey);
        },
      ),
    );
    return future;
  }

  late final Future<Uint8List> _materialFuture =
      _keyMaterial(_password, _salt);

  /// 懒构造：构造时**不做**任何 scrypt（那会把注册流程卡住），第一次真正
  /// 用到密钥时才 await；构造器已把派生提前踢出去了。
  late final Future<RcloneCipher> _cipherFuture = _materialFuture.then(
    (material) => RcloneCipher.fromKeyMaterial(
      material,
      mode: _nameMode,
      dirNameEncrypt: _dirNameEncrypt,
      nameEncoding: _nameEncoding,
      encryptedSuffix: _encryptedSuffix,
    ),
  );

  @override
  Future<void> init() async {
    _requireSource();
  }

  /// 懒解析：源账号被删后再次访问会在这里报错（浏览界面可见），
  /// 不影响兼容层注册流程。
  CloudSource _requireSource() {
    final cached = _source;
    if (cached != null) return cached;
    var s = _env?.resolveSource(_sourceAccountId);
    if (s == null && _sourceAccountName.isNotEmpty) {
      // id 找不到（源被删）→ 按名字找回：重添同名账号即恢复。
      s = _env?.resolveSourceByName?.call(_sourceAccountName);
    }
    if (s == null) {
      final whom = _sourceAccountName.isNotEmpty
          ? '「$_sourceAccountName」'
          : '（源 id：$_sourceAccountId）';
      throw CloudDriverException('crypt 源账号不存在或已删除$whom；重新添加同名源账号即可恢复');
    }
    _source = s;
    return s;
  }

  /// 外层明文路径 → 内层密文路径：源浏览根 + 源目录 + 逐段加密。
  Future<String> _mapToInner(String outerPath, {required bool lastIsFile}) async {
    final src = _requireSource();
    final cipher = await _cipherFuture;
    final segs = outerPath.split('/').where((s) => s.isNotEmpty).toList();
    final parts = <String>[src.basePath];
    parts.addAll(_sourceDir.split('/'));
    for (var i = 0; i < segs.length; i++) {
      final last = i == segs.length - 1;
      parts.add((!last || !lastIsFile)
          ? cipher.encryptDirName(segs[i])
          : cipher.encryptFileName(segs[i]));
    }
    return cloudJoinPath(parts);
  }

  // ── 名字解密（列表路径）──

  /// 估算一条名字的解密代价（相对单位，约为「等价字符数」）：定长开销约
  /// 15µs（AES 密钥调度 + EME 一趟），每个字符约 0.05µs。
  static int _nameCost(String name) => 300 + name.length;

  /// 超过这个总代价就把整批名字丢给 isolate。
  ///
  /// 门槛不能低：起一个 isolate 要 3~10ms，比小目录就地做完还贵。这里取
  /// ≈1.5ms 的桌面工作量（约 100 条短名），慢机上收益更大。
  static const int _nameIsolateCost = 40000;

  /// 就地解密时每处理这么多条让出一次事件循环：解密是同步 CPU 活，
  /// 一口气做完会顶掉一帧以上（真机反馈的「浏览加密目录卡顿」）。
  static const int _yieldEvery = 64;

  /// 诊断计数：名字解密整批走 isolate 的次数（测试断言「真的走了哪条路」）。
  static int nameIsolateRuns = 0;

  /// 整目录名字解密。[entries] 顺序原样保留；解不开的名字按原名列出
  /// （只读取、不改动远端，也不做二次加密，99 §7.5）。
  Future<List<String?>> _decryptNames(List<CloudFileItem> entries) async {
    var cost = 0;
    for (final e in entries) {
      cost += _nameCost(e.name);
    }
    if (cost >= _nameIsolateCost) {
      nameIsolateRuns++;
      final material = await _materialFuture;
      // 注意：闭包只捕获局部变量——不能碰 this，否则整个驱动实例（Dio、
      // 源适配器……）都会被搬进 isolate。
      final mode = _nameMode;
      final dirNameEncrypt = _dirNameEncrypt;
      final nameEncoding = _nameEncoding;
      final encryptedSuffix = _encryptedSuffix;
      final names = <String>[for (final e in entries) e.name];
      final dirs = <bool>[for (final e in entries) e.isDir];
      return Isolate.run(() {
        final cipher = RcloneCipher.fromKeyMaterial(
          material,
          mode: mode,
          dirNameEncrypt: dirNameEncrypt,
          nameEncoding: nameEncoding,
          encryptedSuffix: encryptedSuffix,
        );
        return <String?>[
          for (var i = 0; i < names.length; i++)
            _tryDecrypt(cipher, names[i], dirs[i]),
        ];
      });
    }
    final cipher = await _cipherFuture;
    final out = <String?>[];
    for (var i = 0; i < entries.length; i++) {
      out.add(_tryDecrypt(cipher, entries[i].name, entries[i].isDir));
      if (i % _yieldEvery == _yieldEvery - 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }

  /// 解不开返回 null（就地也用它，能进 isolate）。
  static String? _tryDecrypt(RcloneCipher cipher, String name, bool isDir) {
    try {
      return isDir ? cipher.decryptDirName(name) : cipher.decryptFileName(name);
    } catch (_) {
      return null;
    }
  }

  /// 内层条目 → 外层视角：解密名字（失败原名透传）、换算明文大小、
  /// 抹掉密文直链（MustProxy，内容走 [openContent]）。
  CloudFileItem _reveal(CloudFileItem e, String? decryptedName) {
    var size = e.size;
    if (!e.isDir) {
      try {
        size = RcloneCipher.decryptedSize(e.size);
      } on RcloneCipherException {
        // 大小换算失败用内层原值（OpenList 同款告警语义）。
      }
    }
    return CloudFileItem(
      name: decryptedName ?? e.name,
      isDir: e.isDir,
      size: size,
      modified: e.modified,
      rawUrl: null,
    );
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final src = _requireSource();
    final inner = await src.list(await _mapToInner(path, lastIsFile: false));
    if (inner.isEmpty) return const <CloudFileItem>[];
    final names = await _decryptNames(inner);
    return [
      for (var i = 0; i < inner.length; i++) _reveal(inner[i], names[i]),
    ];
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final src = _requireSource();
    final e = await src.get(await _mapToInner(path, lastIsFile: true));
    final cipher = await _cipherFuture;
    final name = _tryDecrypt(cipher, e.name, false);
    final revealed = _reveal(
      CloudFileItem(
        name: e.name,
        isDir: false,
        size: e.size,
        modified: e.modified,
      ),
      name,
    );
    return CloudFileItem(
      name: revealed.name,
      isDir: false,
      size: revealed.size,
      modified: revealed.modified,
      rawUrl: null,
    );
  }

  @override
  Future<void> mkdir(String path) async {
    final src = _requireSource();
    await src.mkdir(await _mapToInner(path, lastIsFile: false));
    _invalidateTargets();
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final src = _requireSource();
    try {
      await src.rename(
        await _mapToInner(path, lastIsFile: true),
        await _mapToInner(newPath, lastIsFile: true),
      );
    } on CloudDriverException {
      // 末段可能是目录：按目录映射重试。
      await src.rename(
        await _mapToInner(path, lastIsFile: false),
        await _mapToInner(newPath, lastIsFile: false),
      );
    }
    _invalidateTargets();
  }

  @override
  Future<void> remove(String path) async {
    final src = _requireSource();
    try {
      await src.remove(await _mapToInner(path, lastIsFile: true));
    } on CloudDriverException {
      await src.remove(await _mapToInner(path, lastIsFile: false));
    }
    _invalidateTargets();
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final src = _requireSource();
    final cipher = await _cipherFuture;
    try {
      await src.move(
        await _mapToInner(srcPath, lastIsFile: true),
        await _mapToInner(dstDir, lastIsFile: false),
        cipher.encryptFileName(newName),
      );
    } on CloudDriverException {
      await src.move(
        await _mapToInner(srcPath, lastIsFile: false),
        await _mapToInner(dstDir, lastIsFile: false),
        cipher.encryptDirName(newName),
      );
    }
    _invalidateTargets();
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final src = _requireSource();
    final cipher = await _cipherFuture;
    try {
      await src.copy(
        await _mapToInner(srcPath, lastIsFile: true),
        await _mapToInner(dstDir, lastIsFile: false),
        cipher.encryptFileName(newName),
      );
    } on CloudDriverException {
      await src.copy(
        await _mapToInner(srcPath, lastIsFile: false),
        await _mapToInner(dstDir, lastIsFile: false),
        cipher.encryptDirName(newName),
      );
    }
    _invalidateTargets();
  }

  // ── 内容读取 ──

  /// 每批取多少个块（16 × 64KiB ≈ 1MiB）。
  ///
  /// 一块一个请求会把大文件拆成上万个往返（700MB ≈ 10700 次），这正是真机
  /// 上「播放 / 下载加密文件一直转圈」的主因；一次 1MiB 是往返与内存 /
  /// 突发的折中。每批之间让出一次事件循环，避免整批解密顶掉 UI 帧。
  static const int _blocksPerBatch = 16;

  /// 解密后的内容流（下载 / 缓存的内存流路径，99 §7.5）。
  /// 取内层密文直链 → 分批 Range → 逐块认证解密；块失败即抛，不落坏数据。
  @override
  Stream<List<int>> openContent(String path) async* {
    final t = await _openTarget(path, prefetchFirstBlock: true);
    try {
      switch (t.shape) {
        case _CryptTarget.shapeWholeBody:
          // 源不支持 Range（一次回整包）：整包解密。
          yield _decryptAll(t);
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
      // 开头的请求里通常已经带回了第 0 块（少一次往返）。
      var pending = t.firstBlock;
      while (offset < t.cipherSize) {
        Uint8List chunk;
        final bool fromNetwork;
        if (pending != null) {
          chunk = pending;
          pending = null;
          fromNetwork = false;
        } else {
          fromNetwork = true;
          final remaining = t.cipherSize - offset;
          final want = remaining < _blocksPerBatch * kBlockSize
              ? remaining
              : _blocksPerBatch * kBlockSize;
          chunk = await _fetchRange(t, offset, offset + want - 1);
          if (chunk.length < want) {
            throw CloudDriverException(
                'crypt 内容提前结束（第 $block 块起，期望 $want 字节，收到 ${chunk.length} 字节）');
          }
        }
        var p = 0;
        while (p < chunk.length) {
          final remaining = chunk.length - p;
          final take = remaining < kBlockSize ? remaining : kBlockSize;
          yield _decryptBlock(t, block, Uint8List.sublistView(chunk, p, p + take));
          p += take;
          block++;
        }
        offset += chunk.length;
        // 每批网络解密之间让出一次事件循环，别让整批 CPU 活顶掉 UI 帧。
        if (fromNetwork && offset < t.cipherSize) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } on CloudDriverDataException {
      _dropTarget(t); // 内容本身坏了：别让缓存的解析结果继续骗下一个人。
      rethrow;
    }
  }

  /// 明文区间 [start, end]（含端点）→ 只拉取覆盖它的密文块并解密，
  /// 首尾块按需裁剪。ffmpeg 拖动进度条时靠它（99 §7.5 本地流桥）。
  @override
  Stream<List<int>> openContentRange(String path, int start, int end) async* {
    if (start < 0 || end < start) return;
    // 只要区间从第 0 块开始，就把首块并进解析请求里（播放器开场那一下
    // 因此少一个往返）；远离开头的 seek 不预取，免得每次拖动都多下 64KiB。
    final t = await _openTarget(
      path,
      prefetchFirstBlock: start < kBlockDataSize,
    );
    try {
      switch (t.shape) {
        case _CryptTarget.shapeWholeBody:
          final plain = _decryptAll(t);
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
      final plainSize = _decryptedSize(t.cipherSize);
      if (start >= plainSize) return;
      final last = end < plainSize - 1 ? end : plainSize - 1;
      final firstBlock = start ~/ kBlockDataSize;
      final lastBlock = last ~/ kBlockDataSize;
      var b = firstBlock;
      // 解析请求可能已经把第 0 块顺手带回来了（区间从文件头开始时才会预取）：
      // 先把这一块消化掉，剩下的块再按批取。
      if (firstBlock == 0 && t.firstBlock != null) {
        final plain = _decryptBlock(t, 0, t.firstBlock!);
        final to = lastBlock == 0 ? last + 1 : plain.length;
        if (start <= 0 && to >= plain.length) {
          yield plain;
        } else {
          yield Uint8List.sublistView(plain, start, to);
        }
        if (lastBlock == 0) return; // 整个区间就在首块里。
        b = 1;
      }
      while (b <= lastBlock) {
        final batchLast = (b + _blocksPerBatch - 1) < lastBlock
            ? (b + _blocksPerBatch - 1)
            : lastBlock;
        final cipherStart = kFileHeaderSize + b * kBlockSize;
        var cipherEnd = kFileHeaderSize + (batchLast + 1) * kBlockSize - 1;
        if (cipherEnd > t.cipherSize - 1) cipherEnd = t.cipherSize - 1;
        final chunk = await _fetchRange(t, cipherStart, cipherEnd);
        final expected = cipherEnd - cipherStart + 1;
        if (chunk.length < expected) {
          throw CloudDriverException(
              'crypt 内容提前结束（第 $b 块起，期望 $expected 字节，收到 ${chunk.length} 字节）');
        }
        var p = 0;
        for (var i = b; i <= batchLast && p < chunk.length; i++) {
          final remaining = chunk.length - p;
          final take = remaining < kBlockSize ? remaining : kBlockSize;
          final plain =
              _decryptBlock(t, i, Uint8List.sublistView(chunk, p, p + take));
          p += take;
          final from = i == firstBlock ? start - i * kBlockDataSize : 0;
          final to = i == lastBlock ? last - i * kBlockDataSize + 1 : plain.length;
          if (from <= 0 && to >= plain.length) {
            yield plain;
          } else {
            yield Uint8List.sublistView(plain, from, to);
          }
        }
        b = batchLast + 1;
        if (b <= lastBlock) await Future<void>.delayed(Duration.zero);
      }
    } on CloudDriverDataException {
      _dropTarget(t);
      rethrow;
    }
  }

  /// 解密单个块并把密码学异常翻译成分层后的错误（不越过本文件）。
  Uint8List _decryptBlock(_CryptTarget t, int block, Uint8List cipherBlock) {
    try {
      return t.cipher.decryptBlock(t.nonce, block, cipherBlock);
    } on RcloneCipherException catch (e) {
      throw CloudDriverDataException(
          'crypt 第 $block 块解密失败（内容损坏或密钥不匹配）：${e.message}', e);
    }
  }

  /// 整包解密（源不支持 Range 时）。
  Uint8List _decryptAll(_CryptTarget t) {
    try {
      return t.cipher.decrypt(t.body);
    } on RcloneCipherException catch (e) {
      throw CloudDriverDataException('crypt 内容解密失败（内容损坏或密钥不匹配）：${e.message}', e);
    }
  }

  static int _decryptedSize(int cipherSize) {
    try {
      return RcloneCipher.decryptedSize(cipherSize);
    } on RcloneCipherException catch (e) {
      throw CloudDriverDataException('crypt 密文长度不合法：${e.message}', e);
    }
  }

  static Uint8List _fileNonce(Uint8List header) {
    try {
      return RcloneCipher.fileNonceOf(header);
    } on RcloneCipherException catch (e) {
      throw CloudDriverDataException('不是有效的 rclone 加密文件：${e.message}', e);
    }
  }

  // ── 解析缓存 ──

  /// 一次解析（直链 + 文件头）的复用窗口。真机直链有 TTL，取短不取长。
  static const Duration _targetTtl = Duration(seconds: 45);
  static const int _targetCacheLimit = 8;

  final LinkedHashMap<String, _CryptTarget> _targets =
      LinkedHashMap<String, _CryptTarget>();

  /// 目录被改动过 → 缓存的直链可能已经指向不存在的东西，整批丢掉。
  void _invalidateTargets() {
    for (final t in _targets.values) {
      t.dio.close();
    }
    _targets.clear();
  }

  void _dropTarget(_CryptTarget t) {
    _targets.removeWhere((_, x) {
      if (!identical(x, t)) return false;
      x.dio.close();
      return true;
    });
  }

  /// 解析一次目标：密文直链 + 请求头 + 文件 nonce + 密文长度。
  ///
  /// [prefetchFirstBlock] 为真时把文件头和第 0 块并在**同一个** Range 请求里
  /// 取回（少一个往返；顺序读 / 从头播放都吃这一下）。
  ///
  /// 密文总长的取值优先级：响应 `Content-Range` 的总长（与内容**同请求**，
  /// 不会与实际内容错位）> 源元数据给的 [CloudFileItem.size]；服务器无视
  /// Range 一次回了整包时，整包长度就是总长。三者都拿不到（0）才算
  /// 「大小未知」——用元数据校对内容，防二者错位的竞态。
  Future<_CryptTarget> _openTarget(
    String path, {
    bool prefetchFirstBlock = false,
  }) async {
    final now = DateTime.now();
    _targets.removeWhere((_, t) {
      if (!t.isExpired(now)) return false;
      t.dio.close();
      return true;
    });
    final cached = _targets.remove(path);
    if (cached != null) {
      _targets[path] = cached; // LRU 触碰：刚用过的排到最后。
      return cached;
    }
    final src = _requireSource();
    final cipher = await _cipherFuture;
    final innerPath = await _mapToInner(path, lastIsFile: true);
    final inner = await src.get(innerPath);
    final url = inner.rawUrl;
    if (url == null || url.isEmpty) {
      throw const CloudDriverException('crypt 源不提供直链，无法解密内容');
    }
    final dio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 20)),
    );
    try {
      var wantEnd = kFileHeaderSize - 1;
      if (prefetchFirstBlock) {
        wantEnd = kFileHeaderSize + kBlockSize - 1;
        if (inner.size > 0 && wantEnd > inner.size - 1) wantEnd = inner.size - 1;
      }
      final res =
          await _fetchRangeWithMeta(dio, url, inner.rawHeaders, 0, wantEnd);
      final body = res.$1;
      if (body.length < kFileHeaderSize) {
        throw const CloudDriverException('crypt 内容不完整（读不到文件头）');
      }
      // 回了比请求更多的字节 = 服务器无视 Range，手上就是整包。
      final rangeIgnored = body.length > wantEnd + 1;
      var cipherSize = inner.size > 0 ? inner.size : 0;
      final rangeTotal = res.$2;
      if (rangeTotal != null && rangeTotal > cipherSize) cipherSize = rangeTotal;
      if (rangeIgnored) cipherSize = body.length;
      // 首块只有在**完整**时才留用：整块（kBlockSize）或它就是整个文件尾。
      // 元数据 size 可能过期（比真实小）——那时请求区间被裁短，手上这半块
      // 不能当块 0 用，否则解出来的是错位数据（宁可多一个请求）。
      final firstBlock = (!rangeIgnored &&
              body.length > kFileHeaderSize &&
              (body.length - kFileHeaderSize == kBlockSize ||
                  body.length == cipherSize))
          ? Uint8List.sublistView(body, kFileHeaderSize)
          : null;
      final target = _CryptTarget(
        dio: dio,
        url: url,
        headers: inner.rawHeaders,
        body: body,
        nonce: _fileNonce(body),
        cipherSize: cipherSize,
        rangeIgnored: rangeIgnored,
        firstBlock: firstBlock,
        cipher: cipher,
        expiresAt: now.add(_targetTtl),
        refresh: () => src.get(innerPath),
      );
      _targets[path] = target;
      while (_targets.length > _targetCacheLimit) {
        _targets.remove(_targets.keys.first)?.dio.close();
      }
      return target;
    } catch (_) {
      dio.close();
      rethrow;
    }
  }

  /// 取源的 `[start, end]` 字节区间；直链过期时重新解析一次再试
  /// （真机反馈：百度 / 123 的直链有 TTL，长下载中途会 403）。
  Future<Uint8List> _fetchRange(_CryptTarget t, int start, int end) async {
    try {
      return (await _fetchRangeWithMeta(t.dio, t.url, t.headers, start, end)).$1;
    } on DioException catch (e) {
      if (!_isStaleLink(e)) rethrow;
      await _refreshTarget(t);
      return (await _fetchRangeWithMeta(t.dio, t.url, t.headers, start, end)).$1;
    }
  }

  /// 重新解析直链（同一个文件：nonce / 长度都不变，只有 URL 和头会换）。
  Future<void> _refreshTarget(_CryptTarget t) async {
    final inner = await t.refresh();
    final url = inner.rawUrl;
    if (url == null || url.isEmpty) {
      throw const CloudDriverException('crypt 源不再提供直链，无法继续解密内容');
    }
    t.url = url;
    t.headers = inner.rawHeaders;
    t.expiresAt = DateTime.now().add(_targetTtl);
  }

  static bool _isStaleLink(DioException e) {
    final code = e.response?.statusCode ?? 0;
    return code == 401 || code == 403 || code == 404 || code == 410;
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

  @override
  Future<void> dispose() async {
    _invalidateTargets();
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

  /// 「<源类型> Crypt」；源缺失 / 源没报类型名时退化成「Crypt」
  /// （真机反馈：源被删后重加同名账号即恢复，类型名也别显示成空白）。
  @override
  String? get runtimeTypeLabel {
    try {
      final name = _requireSource().displayName;
      if (name.isEmpty) return 'Crypt';
      return '$name Crypt';
    } catch (_) {
      return 'Crypt';
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

  /// 包装驱动：自己包住另一个账号当源，因此不出现在「源账号」下拉里。
  @override
  bool get isWrapper => true;

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

/// 一次解析的结果：密文直链、请求头、文件 nonce、密文长度与（可选的）
/// 首块密文。
///
/// 形态（互斥，判定必须按此顺序，见 [shape]）：
/// - [shapeWholeBody]：服务器**无视 Range** 一次回了整包 → [body] 即整包密文；
/// - [shapeEmptyFile]：密文恰好只有文件头（rclone 空文件的合法格式）→ 空明文；
/// - 其余按分块 Range 解密。
/// 「cipherSize 未知」**不**折叠进 wholeBody：大小未知且手上没有整包，
/// 说明既拿不到总长也拿不到内容，只能明确报错（静默返回空内容 =
/// 下载出 0 字节损坏文件，真机踩过）。
class _CryptTarget {
  _CryptTarget({
    required this.dio,
    required this.url,
    required this.headers,
    required this.body,
    required this.nonce,
    required this.cipherSize,
    required this.rangeIgnored,
    required this.firstBlock,
    required this.cipher,
    required this.expiresAt,
    required this.refresh,
  });

  /// 复用中的连接池；生命周期归 [CryptDriver] 的解析缓存（过期 / 淘汰 /
  /// 弃用 / 驱动 dispose 时关闭），**不**在流结束时关。
  final Dio dio;

  /// 直链与必需头会过期 → 可换（见 CryptDriver._refreshTarget）。
  String url;
  Map<String, String>? headers;

  /// 首次响应收到的字节（正常 = 文件头 [+ 首块]；无视 Range 时 = 整包）。
  final Uint8List body;
  final Uint8List nonce;
  final int cipherSize;

  /// 服务器是否无视了 Range（响应比请求多）。
  final bool rangeIgnored;

  /// 首块密文（解析时一并取回）；null = 需要时单独取。
  final Uint8List? firstBlock;

  final RcloneCipher cipher;

  DateTime expiresAt;

  /// 重新解析内层条目（拿新的直链 / 头），nonce 与长度理论上不变。
  final Future<CloudFileItem> Function() refresh;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  static const int shapeWholeBody = 0;
  static const int shapeEmptyFile = 1;
  static const int shapeRanged = 2;
  static const int shapeUnknownSize = 3;

  int get shape {
    if (rangeIgnored) return shapeWholeBody;
    if (cipherSize == kFileHeaderSize) return shapeEmptyFile;
    if (cipherSize > kFileHeaderSize) return shapeRanged;
    return shapeUnknownSize;
  }
}
