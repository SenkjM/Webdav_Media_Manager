import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';

import '../models/account_capabilities.dart';
import '../models/file_type_config.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import 'accounts_service.dart';
import 'cloud_driver.dart';

/// 云盘 provider 的应用内入口（99 §7）。
///
/// 阶段 0 骨架：
/// - 账号类型判定（[handles]，WebDavService 分流缝的另一半）与能力解析
///   （[capabilitiesFor]，能力遮罩 UI 在阶段 2 接线）；
/// - 驱动注册位（[_drivers]，阶段 1 起逐盘落地，首个 `baidu_netdisk`）；
/// - 上传 / 云端写同步按 99 §7.2.1 **永久禁用**（显式报语义，不是静默失败）；
/// - 其余方法在对应驱动落地前抛 [UnsupportedError]。
///
/// [WebDavItem] 会被保留为网络库的展示模型：云盘驱动返回的
/// [CloudFileItem] 由 [_toWebDavItem] 适配，UI 层无感知。
class CloudDriveService extends ChangeNotifier {
  CloudDriveService({required AccountsService accounts}) : _accounts = accounts;

  final AccountsService _accounts;

  /// accountId → 驱动实例。只含云盘账号。
  final Map<String, CloudDriver> _drivers = {};

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
    return AccountCaps.forAccountValues(a.providerType, a.capabilities);
  }

  /// 启动 / 账号变更时登记云盘账号（AppState.registerAllAccounts 调用）。
  /// 阶段 0 只维持集合语义；驱动实例化与登录态由阶段 1 逐盘接入。
  void registerAccounts(Iterable<WebDavAccount> accounts) {
    final wanted = <String>{};
    for (final a in accounts) {
      if (!isCloudType(a.providerType)) continue;
      wanted.add(a.id);
      // TODO(99 §7 阶段 1): 按 providerType 实例化驱动，如
      // _drivers[a.id] = BaiduNetdiskDriver(addition: ...) 并 init()。
      _drivers.remove(a.id);
    }
    _drivers.removeWhere((id, _) => !wanted.contains(id));
  }

  /// 该账号的驱动；未落地返回 null（上层抛「尚未接入」）。
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
  /// 未接入驱动的类型一律 false（阶段 2 的 UI 会按类型给出文案）。
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
      for (final f in files)
        _toWebDavItem(f, remote, types),
    ];
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  Future<void> downloadToFile(
    String accountId,
    String remotePath,
    File localFile, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    throw UnsupportedError(_notReady(accountId));
  }

  Future<Uint8List> readAsBytes(String accountId, String remotePath) async {
    throw UnsupportedError(_notReady(accountId));
  }

  /// 云端写路径**永久禁用**（99 §7.2.1：上传砍掉）。这个错误是语义，不是未完成。
  Future<void> writeBytes(String accountId, String remotePath, Uint8List data) {
    throw UnsupportedError(_writeDisabled);
  }

  /// 同上：建目录归「写入」，云盘账号一律禁用（99 §7.2.3 的枚举语义）。
  Future<void> ensureDirectory(String accountId, String path) {
    throw UnsupportedError(_writeDisabled);
  }

  Future<void> createFolder(String accountId, String path) {
    throw UnsupportedError(_writeDisabled);
  }

  Future<void> deletePath(String accountId, String path) async {
    throw UnsupportedError(_notReady(accountId));
  }

  Future<void> renamePath(
    String accountId,
    String oldPath,
    String newPath, {
    bool overwrite = false,
  }) async {
    throw UnsupportedError(_notReady(accountId));
  }

  Future<void> copyPath(String accountId, String oldPath, String newPath) async {
    throw UnsupportedError(_notReady(accountId));
  }

  Future<void> movePath(String accountId, String oldPath, String newPath) async {
    throw UnsupportedError(_notReady(accountId));
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

  /// 流式源：直链 + 必需头（99 §7.1 的契合点）。驱动未接入前抛错；
  /// 接入后由 driver.get() 的 rawUrl / rawHeaders 组装。
  WebDavStreamSource? buildStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
    StreamKind? kind,
  }) {
    throw UnsupportedError(_notReady(accountId));
  }

  // --- 内部 ---

  static const String _writeDisabled =
      '云盘账号不支持上传与云端写同步（上传功能已砍，见 99 §7.2.1）';

  String _notReady(String accountId) {
    final a = _accounts.accountById(accountId);
    return '云盘驱动尚未接入：${a?.providerType ?? accountId}';
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
