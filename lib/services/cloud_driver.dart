/// 云盘驱动的统一接口（99 §7 / 7.1）。
///
/// 语义对齐 OpenList worker 的 `StorageDriver`
/// （localdev/OpenList-Worker/src/backend/internal/driver/base.ts）：
/// [get] 返回直链 + 必需请求头，下载与流式都走「直链 + 头」。
/// **没有 put / 上传**——上传已按 99 §7.2.1 砍掉。
abstract class CloudDriver {
  /// 建立登录态（校验凭证、换 / 校验 token）。失败抛 [CloudDriverException]。
  Future<void> init();

  /// 运行时能力位（crypt 随源映射）；null = 用 spec 的静态表。
  int? get runtimeCapabilities => null;

  /// MustProxy 驱动（crypt）覆写：产出解密后的内容流（下载内存流路径）。
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

/// 账号引用字段（crypt 的源账号）：渲染为现有账号下拉（WebDAV + 云盘，
/// 排除 crypt 自身防套娃），值为账号 id。选项来自运行时账号列表，
/// 由表单渲染器解析，spec 只声明占位。
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

/// crypt 等包装驱动的「内容源」契约：内层账号的能力视图。
abstract class CloudSource {
  /// 源账号浏览根（含远程路径），路径映射的基座。
  String get basePath;

  /// 源账号的生效能力位。
  int get capabilities;

  Future<List<CloudFileItem>> list(String path);

  /// 返回密文直链 + 必需头（crypt 解密层自用）。
  Future<CloudFileItem> get(String path);

  Future<void> mkdir(String path);
  Future<void> rename(String path, String newPath);
  Future<void> remove(String path);
  Future<void> move(String srcPath, String dstDir, String newName);
  Future<void> copy(String srcPath, String dstDir, String newName);
}

/// 兼容层注入给驱动的运行环境。
class CloudDriverEnv {
  const CloudDriverEnv({required this.resolveSource});

  /// 按账号 id 解析内容源（WebDAV 或云盘适配器）；源不存在返回 null。
  final CloudSource? Function(String accountId) resolveSource;
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
  /// 兼容层负责持久化；[env] 供 crypt 等需要源解析的驱动使用。
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
/// （WebDAV 账号的适配在 crypt/crypt_adapters.dart——那里才需要
/// 依赖 WebDavService，接口层保持零反向依赖。）
class CloudAccountSource implements CloudSource {
  CloudAccountSource({
    required CloudDriver driver,
    required String basePath,
    required int capabilities,
  })  : _driver = driver,
        basePath = basePath,
        _capabilities = capabilities;

  final CloudDriver _driver;

  @override
  final String basePath;

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
