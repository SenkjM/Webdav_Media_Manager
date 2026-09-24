/// 云盘驱动的统一接口（99 §7 / 7.1）。
///
/// 语义对齐 OpenList worker 的 `StorageDriver`
/// （localdev/OpenList-Worker/src/backend/internal/driver/base.ts）：
/// [get] 返回直链 + 必需请求头，下载与流式都走「直链 + 头」。
/// **没有 put / 上传**——上传已按 99 §7.2.1 砍掉。
abstract class CloudDriver {
  /// 建立登录态（校验凭证、换 / 校验 token）。失败抛 [CloudDriverException]。
  Future<void> init();

  /// 列出目录。[path] 是账号内绝对路径（浏览根拼接归 CloudDriveService）。
  Future<List<CloudFileItem>> list(String path);

  /// 取单个条目；文件必须带 [CloudFileItem.rawUrl]（拿不到直链时抛
  /// [CloudDriverException]，上层把真实原因透给用户）。
  Future<CloudFileItem> get(String path);

  Future<void> mkdir(String path);

  /// 改名 / 改路径。[newPath] 是完整目标路径；跨目录时由实现降级为
  /// 「移动 + 改名」（百度 filemanager 的 move 自带 newname）。
  Future<void> rename(String path, String newPath);

  /// 删除单个路径（目录 / 文件均可）。
  Future<void> remove(String path);

  /// 移动到 [dstDir]，名字 [newName]（调用方按目标全路径拆出）。
  Future<void> move(String srcPath, String dstDir, String newName);

  /// 复制到 [dstDir]，名字 [newName]。
  Future<void> copy(String srcPath, String dstDir, String newName);
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

/// 路径工具（与 worker driver 的 basename / dirname 同语义）。
String cloudBasename(String p) {
  final segs = p.split('/');
  return segs.isEmpty ? '' : segs.last;
}

String cloudDirname(String p) {
  final segs = p.split('/')..removeWhere((s) => s.isEmpty);
  if (segs.length <= 1) return '/';
  return '/${segs.sublist(0, segs.length - 1).join('/')}';
}
