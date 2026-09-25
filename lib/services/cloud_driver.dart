/// 云盘驱动的统一接口（99 §7 / 7.1）。
///
/// 语义对齐 OpenList worker 的 `StorageDriver`
/// （localdev/OpenList-Worker/src/backend/internal/driver/base.ts）：
/// [get] 返回直链 + 必需请求头，下载与流式都走「直链 + 头」。
/// **没有 put / 上传**——上传已按 99 §7.2.1 砍掉。
abstract class CloudDriver {
  /// 建立登录态（校验凭证、换 / 校验 token）。失败抛 [CloudDriverException]。
  Future<void> init();

  /// 运行时能力位（包装驱动随源映射）；null = 用 spec 的静态表。
  int? get runtimeCapabilities => null;

  /// 运行时类型名（账号列表 / 下拉显示用）。
  ///
  /// 包装驱动的类型名取决于它包住的源（如「百度网盘 Crypt」），静态的
  /// [CloudDriverSpec.displayName] 表达不了。返回 null = 用静态表。
  /// 兼容层只读这个字符串，不知道也不需要知道它是怎么拼出来的。
  String? get runtimeTypeLabel => null;

  /// 释放驱动持有的资源（临时连接、缓存等）。
  ///
  /// 兼容层重建 / 移除驱动实例时调用。默认无操作——**新增驱动不必实现它**，
  /// 只有真的持有跨请求资源的驱动才覆写。
  Future<void> dispose() async {}

  /// MustProxy 驱动覆写：产出解密后的内容流（下载内存流路径）。
  Stream<List<int>> openContent(String path) =>
      throw UnsupportedError('该驱动不支持内容流读取');

  /// MustProxy 驱动的区间读取（含端点，语义同 HTTP `Range: bytes=start-end`）。
  /// 本地流桥按播放器/ffmpeg 的 Range 请求调用它（99 §7.5）。
  Stream<List<int>> openContentRange(String path, int start, int end) =>
      throw UnsupportedError('该驱动不支持区间读取');

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

/// 内容本身不可用——解密 / 认证失败、数据损坏、密钥不匹配。
///
/// **重试没有意义**（同一份字节再拉一次还是坏的），下载队列据此直接判失败，
/// 而不再退避重试。驱动负责把底层密码学库 / 传输层的这类失败翻译成它，
/// 于是上层不必认识任何具体实现（分层：兼容层之上看不到驱动内部用什么）。
class CloudDriverDataException extends CloudDriverException {
  const CloudDriverDataException(super.message, [super.cause]);
}

/// 路径工具（与 worker driver 的 basename / dirname 同语义）。
String cloudBasename(String p) {
  final segs = p.split('/');
  return segs.isEmpty ? '' : segs.last;
}

/// 路径合并：各段去首尾斜杠后单斜杠连接；空段忽略；结果以 / 开头。
String cloudJoinPath(List<String> parts) {
  final segs = parts
      .expand((p) => p.split('/'))
      .where((s) => s.isNotEmpty)
      .toList();
  return '/${segs.join('/')}';
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
    this.disabledWhenSwitch,
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

  /// 依赖开关：开关打开才**可编辑**。
  final String? enabledWhenSwitch;

  /// 依赖开关：开关打开则**停用**（如百度「在本地处理令牌刷新」开启后的
  /// 在线续期地址——99 §7.3.1：一旦打开就不使用 online api 逻辑）。
  ///
  /// 与 [enabledWhenSwitch] 极性相反：那个是「开了才可用」，这个是
  /// 「开了就停用」。两个字段互斥声明，同时声明视为未声明。
  final String? disabledWhenSwitch;

  /// 因 [enabledWhenSwitch] / [disabledWhenSwitch] 停用时替代 [hint] 的提示。
  final String? disabledHint;
}

/// 下拉选择字段（如 crypt 的 filename_encryption）。
class CloudDriverSelectField extends CloudDriverFormItem {
  const CloudDriverSelectField({
    required this.key,
    required this.label,
    required this.options,
    this.defaultValue = '',
    this.required = false,
    this.hint,
  });

  final String key;
  final String label;

  /// (存库值, 显示名) 列表。
  final List<(String, String)> options;
  final String defaultValue;
  final bool required;
  final String? hint;
}

/// 账号引用字段（包装驱动的源账号）：渲染为现有账号下拉（WebDAV + 云盘，
/// 排除声明了 [CloudDriverSpec.isWrapper] 的类型防套娃），值为账号 id。
/// 选项来自运行时账号列表，由表单渲染器解析，spec 只声明占位。
class CloudDriverAccountField extends CloudDriverFormItem {
  const CloudDriverAccountField({
    required this.key,
    required this.label,
    this.required = false,
    this.hint,
  });

  final String key;
  final String label;
  final bool required;
  final String? hint;
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

/// 包装驱动的「内容源」契约：内层账号的能力视图。
abstract class CloudSource {
  /// 源账号浏览根（含远程路径），路径映射的基座。
  String get basePath;

  /// 源的显示名（包装驱动拼运行时类型名用，如「<源类型> Crypt」）。
  /// 未知 / 不适用时返回空串，包装驱动自行退化。
  String get displayName => '';

  /// 源账号的生效能力位。
  int get capabilities;

  Future<List<CloudFileItem>> list(String path);

  /// 返回密文直链 + 必需头（包装驱动的解密层自用）。
  Future<CloudFileItem> get(String path);

  Future<void> mkdir(String path);
  Future<void> rename(String path, String newPath);
  Future<void> remove(String path);
  Future<void> move(String srcPath, String dstDir, String newName);
  Future<void> copy(String srcPath, String dstDir, String newName);
}

/// 兼容层注入给驱动的运行环境。
class CloudDriverEnv {
  const CloudDriverEnv({
    required this.resolveSource,
    this.resolveSourceByName,
  });

  /// 按账号 id 解析内容源（WebDAV 或云盘适配器）；源不存在返回 null。
  final CloudSource? Function(String accountId) resolveSource;

  /// 按**账号名**解析内容源（源被删后重添同名账号可恢复，真机反馈）。
  /// 精确匹配账号显示名，找不到返回 null；未注入时只认 id。
  final CloudSource? Function(String accountName)? resolveSourceByName;
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

  /// 是否为**包装驱动**（自己包住另一个账号当内容源）。
  ///
  /// 只影响账号表单的「账号引用字段」候选列表：包装驱动不出现在源下拉里
  /// （防止套娃）。UI 只问这个布尔值，不认识任何具体类型。
  bool get isWrapper => false;

  /// 动态表单项（顺序即界面顺序）。远程路径是通用字段，不在这里。
  List<CloudDriverFormItem> get form;

  /// 解析某个开关字段的当前值，供渲染与保存共用（单一事实来源）。
  ///
  /// 优先级：[values] 里的实时值 → 该开关声明的 [CloudDriverSwitchField.defaultValue]
  /// → false。中间这一步不能省：表单控件重建时 [values] 可能缺键，此时若写死
  /// false，「默认开」的开关就会被当成关，联动字段被错误隐藏 / 停用，
  /// 且保存下来的值与界面显示相反（开关联动回退的根因）。
  ///
  /// [key] 不是本 spec 声明的开关时返回 false。
  bool switchValue(String key, Map<String, bool> values) {
    final live = values[key];
    if (live != null) return live;
    for (final item in form) {
      if (item is CloudDriverSwitchField && item.key == key) {
        return item.defaultValue;
      }
    }
    return false;
  }

  /// 用表单值构造驱动实例。[onTokenUpdate] 收令牌轮换 patch（键值对），
  /// 兼容层负责持久化；[env] 供包装驱动做源解析用。
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  });

  /// 表单保存前的真连校验：默认构造实例并 init()（99 §7.3.1）。
  Future<void> verify(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) async {
    await create(config, onTokenUpdate: onTokenUpdate, env: env).init();
  }
}

/// 云盘账号 → [CloudSource]：包已注册的内层驱动，路径挂到浏览根。
/// （WebDAV 账号的适配在 cloud_drivers/webdav_source.dart——那里才需要
/// 依赖 WebDavService，接口层保持零反向依赖。）
class CloudAccountSource implements CloudSource {
  CloudAccountSource({
    required CloudDriver driver,
    required String basePath,
    required int capabilities,
    String displayName = '',
  })  : _driver = driver,
        basePath = basePath,
        _capabilities = capabilities,
        displayName = displayName;

  final CloudDriver _driver;

  @override
  final String basePath;

  @override
  final String displayName;

  final int _capabilities;

  String _join(String path) => cloudJoinPath([basePath, path]);

  @override
  int get capabilities => _capabilities;

  @override
  Future<List<CloudFileItem>> list(String path) => _driver.list(_join(path));

  @override
  Future<CloudFileItem> get(String path) => _driver.get(_join(path));

  @override
  Future<void> mkdir(String path) => _driver.mkdir(_join(path));

  @override
  Future<void> rename(String path, String newPath) =>
      _driver.rename(_join(path), _join(newPath));

  @override
  Future<void> remove(String path) => _driver.remove(_join(path));

  @override
  Future<void> move(String srcPath, String dstDir, String newName) =>
      _driver.move(_join(srcPath), _join(dstDir), newName);

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) =>
      _driver.copy(_join(srcPath), _join(dstDir), newName);
}
