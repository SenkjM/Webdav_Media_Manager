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

// ─── 驱动自描述层（99 §7.2.10）───────────────────────────────────
// 每个驱动文件导出一个 CloudDriverSpec 常量：类型、显示名、能力遮罩、
// 表单参数、构造与校验全部收在驱动文件里；注册表（cloud_drivers/
// driver_registry.dart）只认这个形状。账号表单按 spec 通用渲染，兼容层
// 只查表——新增一个盘 = 新增一个文件 + 注册表加一行（OpenList 同款）。
// crypt 这类中间处理层以后同样实现 spec：create() 里把内层驱动包起来。

/// 表单项基类：字段与开关按声明顺序渲染。
sealed class CloudDriverFormItem {
  const CloudDriverFormItem();
}

/// 文本字段（粘贴令牌 / 地址 / 密钥类）。
class CloudDriverField extends CloudDriverFormItem {
  const CloudDriverField({
    required this.key,
    required this.label,
    this.hint,
    this.required = false,
    this.obscure = false,
    this.defaultValue = '',
    this.visibleWhenSwitch,
    this.enabledWhenSwitch,
    this.disabledHint,
  });

  /// 写入驱动配置 JSON 的键（与 Addition 序列化键一致）。
  final String key;

  /// 界面显示名。
  final String label;

  /// 辅助说明（helperText）。
  final String? hint;

  /// 必填校验由表单按此标记执行（缺省时报「请填写 [label]」）。
  final bool required;

  /// 密文输入（粘贴令牌 / 密钥），带明暗切换。
  final bool obscure;

  /// 默认值（如百度在线续期地址的公共服务）。
  final String defaultValue;

  /// 依赖开关：开关打开才**显示**该字段（如本地刷新的 Client ID / Secret）。
  final String? visibleWhenSwitch;

  /// 依赖开关：开关打开才**可编辑**（如本地刷新时的在线续期地址）。
  final String? enabledWhenSwitch;

  /// 因 [enabledWhenSwitch] 停用时替代 [hint] 的提示。
  final String? disabledHint;
}

/// 开关字段。
class CloudDriverSwitchField extends CloudDriverFormItem {
  const CloudDriverSwitchField({
    required this.key,
    required this.label,
    required this.subtitle,
    this.defaultValue = false,
  });

  final String key;
  final String label;
  final String subtitle;
  final bool defaultValue;
}

/// 驱动注册描述符：驱动的全部「对外知识」收在这里。
abstract class CloudDriverSpec {
  const CloudDriverSpec();

  /// provider_type 存库值（如 'baidu_netdisk'）。
  String get typeId;

  /// 界面显示名（类型下拉）。
  String get displayName;

  /// 静态能力位（AccountCaps 位或）。write 一律不给（99 §7.2.1）。
  int get capabilities;

  /// 动态表单项（顺序即界面顺序）。远程路径是通用字段，不在这里。
  List<CloudDriverFormItem> get form;

  /// 用表单值构造驱动实例。[onTokenUpdate] 收令牌轮换 patch（键值对），
  /// 兼容层负责持久化；中间件类驱动可转发给内层驱动。
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
  });

  /// 表单保存前的真连校验：默认构造实例并 init()（99 §7.3.1）。
  Future<void> verify(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
  }) async {
    await create(config, onTokenUpdate: onTokenUpdate).init();
  }
}
