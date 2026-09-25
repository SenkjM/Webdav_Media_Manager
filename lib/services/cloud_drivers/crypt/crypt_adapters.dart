import '../../../models/account_capabilities.dart';
import '../../../models/webdav_account.dart';
import '../../cloud_driver.dart';
import '../../webdav_service.dart';

/// WebDAV 账号 → [CloudSource]：转调 WebDavService 同名方法。
class WebDavAccountSource implements CloudSource {
  WebDavAccountSource({required WebDavService webDav, required WebDavAccount account})
      : _webDav = webDav,
        _account = account;

  final WebDavService _webDav;
  final WebDavAccount _account;

  @override
  String get basePath => WebDavAccount.normalizeRemotePath(_account.remotePath);

  @override
  int get capabilities => AccountCaps.forWebdav(_account.capabilities);

  String _join(String path) => cloudJoinPath([basePath, path]);

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final items = await _webDav.listDirectory(_account.id, _join(path));
    return [
      for (final e in items)
        CloudFileItem(
          name: e.name,
          isDir: e.isDirectory,
          size: e.size ?? 0,
          modified: e.modified,
          rawUrl: null,
        ),
    ];
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final p = _join(path);
    final s = _webDav.buildStreamSource(
      accountId: _account.id,
      remotePath: p,
      name: cloudBasename(p),
    );
    if (s == null) {
      throw const CloudDriverException('WebDAV 未连接，无法取源内容');
    }
    // 密文条目的大小必须带给 crypt 层：流式回 Content-Length、下载进度、
    // Range 分块判断（wholeBody）全依赖它。列表接口对单文件拿不到，
    // 单独 PROPFIND 一次（statPath）；失败不阻断——size 留 0 由上层
    // 的「无法确定大小」明确报错，而不是这里抛出含糊的网络错误。
    var size = 0;
    DateTime? modified;
    try {
      final stat = await _webDav.statPath(_account.id, p);
      size = stat?.size ?? 0;
      modified = stat?.modified;
    } catch (_) {}
    return CloudFileItem(
      name: cloudBasename(p),
      isDir: false,
      size: size,
      modified: modified,
      rawUrl: s.uri,
      rawHeaders: s.headers,
    );
  }

  @override
  Future<void> mkdir(String path) => _webDav.createFolder(_account.id, _join(path));

  @override
  Future<void> rename(String path, String newPath) =>
      _webDav.renamePath(_account.id, _join(path), _join(newPath));

  @override
  Future<void> remove(String path) => _webDav.deletePath(_account.id, _join(path));

  @override
  Future<void> move(String srcPath, String dstDir, String newName) =>
      _webDav.movePath(
          _account.id, _join(srcPath), cloudJoinPath([dstDir, newName]));

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) =>
      _webDav.copyPath(
          _account.id, _join(srcPath), cloudJoinPath([dstDir, newName]));
}
