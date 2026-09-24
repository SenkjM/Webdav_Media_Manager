import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/account_capabilities.dart';
import '../models/file_type_config.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import 'accounts_service.dart';
import 'cloud_driver.dart';
import 'cloud_drivers/driver_registry.dart';

/// 云盘 provider 的应用内入口（99 §7）。
///
/// 阶段 1（首个驱动 `baidu_netdisk`）：
/// - [registerAccounts] 按 providerType 实例化驱动（凭证 / 配置走
///   AccountsService 的 secure storage 通道）；
/// - 下载 / 流式走「直链 + 必需头」（worker 的 raw_url + raw_url_headers 语义）；
/// - 上传 / 云端写同步按 99 §7.2.1 **永久禁用**（显式报语义，不是静默失败）；
/// - 未接入驱动的类型在注册时跳过（启动不崩），对应方法抛 [UnsupportedError]。
///
/// [WebDavItem] 保留为网络库展示模型：驱动返回的 [CloudFileItem] 由
/// [_toWebDavItem] 适配，UI 层无感知。
class CloudDriveService extends ChangeNotifier {
  CloudDriveService({required AccountsService accounts}) : _accounts = accounts;

  final AccountsService _accounts;

  /// accountId → 驱动实例。只含云盘账号。
  final Map<String, CloudDriver> _drivers = {};

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
      followRedirects: true,
      validateStatus: (s) => s != null && s < 400,
    ),
  );

  /// 'webdav' 之外的一切类型都算云盘 provider。
  static bool isCloudType(String providerType) => providerType != 'webdav';

  /// 该账号是否由本服务接管（WebDavService 分流缝调用）。
  bool handles(String accountId) {
    final a = _accounts.accountById(accountId);
    return a != null && isCloudType(a.providerType);
  }

  /// 账号能力遮罩：WebDAV 用账号里用户配置的位，云盘按类型静态表。
  int capabilitiesFor(String accountId) {
    final a = _accounts.accountById(accountId);
    if (a == null) return AccountCaps.list;
    if (a.providerType == 'webdav') {
      return AccountCaps.forWebdav(a.capabilities);
    }
    // 云盘：能力位是驱动自描述（99 §7.2.10）；未注册类型保守只给列出。
    return cloudDriverSpec(a.providerType)?.capabilities ?? AccountCaps.list;
  }

  /// 账号是否具备某能力位（UI 按钮遮罩用，99 §7.2.3 / §7.2.6）。
  bool can(String accountId, int cap) =>
      AccountCaps.has(capabilitiesFor(accountId), cap);

  /// 启动 / 账号变更时登记云盘账号（AppState.registerAllAccounts 调用）。
  /// 总是按最新配置重建驱动实例——access_token 缓存存在配置里，重建不丢登录态。
  /// 配置缺失或类型未接入时跳过该账号（启动不崩），表单保存后会重新注册。
  Future<void> registerAccounts(Iterable<WebDavAccount> accounts) async {
    final wanted = <String>{};
    for (final a in accounts) {
      if (!isCloudType(a.providerType)) continue;
      wanted.add(a.id);
      try {
        _drivers[a.id] = _createDriver(a, await _accounts.loadDriverConfig(a.id));
      } on CloudDriverException catch (e) {
        _drivers.remove(a.id);
        if (kDebugMode) debugPrint('[cloud] 跳过账号 ${a.name}：$e');
      }
    }
    _drivers.removeWhere((id, _) => !wanted.contains(id));
    notifyListeners();
  }

  CloudDriver _createDriver(WebDavAccount a, Map<String, dynamic>? cfg) {
    final spec = cloudDriverSpec(a.providerType);
    if (spec == null) {
      throw CloudDriverException('未知云盘类型：${a.providerType}');
    }
    // 驱动的全部知识都在其 spec（99 §7.2.10）；兼容层只管查表与持久化。
    return spec.create(
      cfg ?? const <String, dynamic>{},
      onTokenUpdate: (patch) => _persistTokens(a.id, patch),
    );
  }

  /// 令牌轮换持久化（驱动回调）：patch 原样合并进存储的配置。
  Future<void> _persistTokens(String accountId, Map<String, dynamic> patch) async {
    final cfg = await _accounts.loadDriverConfig(accountId) ??
        <String, dynamic>{};
    cfg.addAll(patch);
    await _accounts.saveDriverConfig(accountId, cfg);
  }

  /// 表单保存前的真连校验（99 §7.3.1：能换到 access_token 才保存）。
  /// 失败原样抛 [CloudDriverException]，由表单展示给用户。
  Future<void> verifyNewAccount(
    WebDavAccount account,
    Map<String, dynamic> config,
  ) async {
    final spec = cloudDriverSpec(account.providerType);
    if (spec == null) {
      throw CloudDriverException('未知云盘类型：${account.providerType}');
    }
    await spec.verify(config);
  }

  /// 该账号的驱动；未接入返回 null。
  CloudDriver? driverFor(String accountId) => _drivers[accountId];

  /// 远程路径（浏览根）拼接：account.remotePath + path。
  /// 空根视为 `/`；两侧各留一个 `/`。
  static String joinRemotePath(WebDavAccount account, String path) {
    final root = WebDavAccount.normalizeRemotePath(account.remotePath);
    final p = path.startsWith('/') ? path : '/$path';
    if (root == '/') return p;
    return '$root$p';
  }

  // --- 对外方法（与 WebDavService 同形，分流缝的接对面） ---

  /// WebDAV 的 ping / readDir 探活：云盘侧等价于驱动登录态校验。
  Future<bool> testConnection(String accountId) async {
    final driver = _drivers[accountId];
    if (driver == null) return false;
    try {
      await driver.init();
      return true;
    } on CloudDriverException {
      return false;
    }
  }

  Future<List<WebDavItem>> listDirectory(
    String accountId,
    String path, {
    FileTypeConfig? fileTypes,
  }) async {
    final driver = _requireDriver(accountId);
    final types = fileTypes ?? FileTypeConfig();
    final account = _requireAccount(accountId);
    final remote = joinRemotePath(account, path);
    final files = await driver.list(remote);
    final items = <WebDavItem>[
      for (final f in files) _toWebDavItem(f, remote, types),
    ];
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// 直链下载：driver.get() → rawUrl + 必需头 → dio 流式落盘。
  Future<void> downloadToFile(
    String accountId,
    String remotePath,
    File localFile, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final item = await _fileWithLink(accountId, remotePath);
    await localFile.parent.create(recursive: true);
    await _dio.download(
      item.rawUrl!,
      localFile.path,
      options: Options(headers: item.rawHeaders),
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> readAsBytes(String accountId, String remotePath) async {
    final item = await _fileWithLink(accountId, remotePath);
    final res = await _dio.get<List<int>>(
      item.rawUrl!,
      options: Options(
        responseType: ResponseType.bytes,
        headers: item.rawHeaders,
      ),
    );
    return Uint8List.fromList(res.data ?? <int>[]);
  }

  /// 云端写路径**永久禁用**（99 §7.2.1：上传砍掉）。这个错误是语义，不是未完成。
  Future<void> writeBytes(String accountId, String remotePath, Uint8List data) {
    throw UnsupportedError(_writeDisabled);
  }

  /// 同上：建目录归「写入」，云盘账号一律禁用（99 §7.2.3 的枚举语义）。
  Future<void> ensureDirectory(String accountId, String path) {
    throw UnsupportedError(_writeDisabled);
  }

  /// 新建文件夹：mkdir 已从「写入」拆为独立能力位（99 §7.2.3 / §7.3.2）。
  /// 已落地驱动（baidu）真实现；UI 按能力位遮罩，无该位的驱动在驱动层抛错。
  Future<void> createFolder(String accountId, String path) async {
    final driver = _requireDriver(accountId);
    await driver.mkdir(_remote(accountId, path));
  }

  Future<void> deletePath(String accountId, String path) async {
    final driver = _requireDriver(accountId);
    await driver.remove(_remote(accountId, path));
  }

  Future<void> renamePath(
    String accountId,
    String oldPath,
    String newPath, {
    bool overwrite = false,
  }) async {
    final driver = _requireDriver(accountId);
    await driver.rename(_remote(accountId, oldPath), _remote(accountId, newPath));
  }

  Future<void> copyPath(String accountId, String oldPath, String newPath) async {
    final driver = _requireDriver(accountId);
    final dst = _remote(accountId, newPath);
    await driver.copy(
      _remote(accountId, oldPath),
      cloudDirname(dst),
      cloudBasename(dst),
    );
  }

  Future<void> movePath(String accountId, String oldPath, String newPath) async {
    final driver = _requireDriver(accountId);
    final dst = _remote(accountId, newPath);
    await driver.move(
      _remote(accountId, oldPath),
      cloudDirname(dst),
      cloudBasename(dst),
    );
  }

  /// 与 WebDavService 同构的递归收集（走 [listDirectory]，自动继承分流与分类）。
  Future<List<WebDavItem>> collectFilesRecursive(
    String accountId,
    String folderPath, {
    FileTypeConfig? fileTypes,
    bool onlyAudio = false,
  }) async {
    final result = <WebDavItem>[];
    final queue = <String>[folderPath];
    while (queue.isNotEmpty) {
      final dir = queue.removeAt(0);
      final items = await listDirectory(accountId, dir, fileTypes: fileTypes);
      for (final item in items) {
        if (item.isDirectory) {
          queue.add(item.path);
        } else if (!onlyAudio || item.isAudio) {
          result.add(item);
        }
      }
    }
    return result;
  }

  /// 异步流式源：driver.get() → 直链 + 头；后缀判定与 WebDAV 版一致。
  Future<WebDavStreamSource?> resolveStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
    StreamKind? kind,
  }) async {
    final streamKind = kind ??
        (FileTypeConfig().categoryFor(name) == FileCategory.music
            ? StreamKind.music
            : StreamKind.video);
    final item = await _fileWithLink(accountId, remotePath);
    return WebDavStreamSource(
      uri: item.rawUrl!,
      headers: item.rawHeaders ?? const {},
      name: name,
      remotePath: remotePath,
      accountId: accountId,
      kind: streamKind,
    );
  }

  // --- 内部 ---

  static const String _writeDisabled =
      '云盘账号不支持上传与云端写同步（上传功能已砍，见 99 §7.2.1）';

  String _notReady(String accountId) {
    final a = _accounts.accountById(accountId);
    return '云盘驱动尚未接入：${a?.providerType ?? accountId}';
  }

  String _remote(String accountId, String path) {
    return joinRemotePath(_requireAccount(accountId), path);
  }

  /// 取文件条目并校验直链存在。
  Future<CloudFileItem> _fileWithLink(
    String accountId,
    String remotePath,
  ) async {
    final driver = _requireDriver(accountId);
    final item = await driver.get(_remote(accountId, remotePath));
    if (item.rawUrl == null || item.rawUrl!.isEmpty) {
      throw CloudDriverException('该驱动未返回下载直链：${item.name}');
    }
    return item;
  }

  WebDavAccount _requireAccount(String accountId) {
    final a = _accounts.accountById(accountId);
    if (a == null) {
      throw StateError('云盘账号不存在：$accountId');
    }
    return a;
  }

  CloudDriver _requireDriver(String accountId) {
    final driver = _drivers[accountId];
    if (driver == null) {
      throw UnsupportedError(_notReady(accountId));
    }
    return driver;
  }

  /// worker FileItem → 网络库展示模型。目录条目永远没有 rawUrl。
  WebDavItem _toWebDavItem(
    CloudFileItem f,
    String parentPath,
    FileTypeConfig types,
  ) {
    var itemPath = parentPath.endsWith('/')
        ? '$parentPath${f.name}'
        : '$parentPath/${f.name}';
    if (!itemPath.startsWith('/')) itemPath = '/$itemPath';
    return WebDavItem(
      name: f.name,
      path: f.isDir && !itemPath.endsWith('/') ? '$itemPath/' : itemPath,
      isDirectory: f.isDir,
      size: f.size,
      modified: f.modified,
      category: f.isDir ? FileCategory.other : types.categoryFor(f.name),
    );
  }
}
