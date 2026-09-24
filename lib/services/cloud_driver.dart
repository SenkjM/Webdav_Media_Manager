/// 云盘驱动的统一接口（99 §7 / 7.1）。
///
/// 语义对齐 OpenList worker 的 `StorageDriver`
/// （localdev/OpenList-Worker/src/backend/internal/driver/base.ts）：
/// [get] 返回直链 + 必需请求头，下载与流式都走「直链 + 头」。
/// **没有 put / 上传**——上传已按 99 §7.2.1 砍掉。
abstract class CloudDriver {
  /// 建立登录态（校验凭证、预取 / 刷新 token）。失败抛 [CloudDriverException]。
  Future<void> init();

  /// 列出目录。路径是**账号内**路径（不含远程路径拼接，拼接归
  /// CloudDriveService），即浏览根之下的相对绝对路径。
  Future<List<CloudFileItem>> list(String path);

  /// 取单个条目；文件必须带 [CloudFileItem.rawUrl]（无直链的驱动抛
  /// [CloudDriverException]，由上层决定走本地流桥还是报错）。
  Future<CloudFileItem> get(String path);

  Future<void> mkdir(String path);
  Future<void> rename(String path, String newName);
  Future<void> remove(String dir, List<String> names);
  Future<void> move(String srcDir, String dstDir, List<String> names);
  Future<void> copy(String srcDir, String dstDir, List<String> names);
}

/// 目录条目（对齐 worker `FileItem` 的字段子集 + 直链）。
class CloudFileItem {
  const CloudFileItem({
    required this.name,
    required this.isDir,
    this.size = 0,
    this.modified,
    this.rawUrl,
    this.rawHeaders,
  });

  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;

  /// 直链；null 表示该驱动拿不到公开直链（MustProxy，99 §7.5 的本地流桥议题）。
  final String? rawUrl;

  /// 直链必需的请求头（Cookie / Referer / UA 等，worker 证实多个网盘都需要）。
  final Map<String, String>? rawHeaders;
}

class CloudDriverException implements Exception {
  const CloudDriverException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}
