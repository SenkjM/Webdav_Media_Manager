/// 账号能力遮罩（99 §7.2.3 / 7.2.5）。
///
/// 位枚举：列出 / 读取 / 写入 / 移动 / 复制 / 删除。
/// - 「列出」默认拥有、不在用户界面显示（没有对应按钮可关）。
/// - 云盘类型按驱动自描述给定（spec.capabilities，99 §7.2.10，
///   上传已砍 → 一律没有 write）；
///   WebDAV 账号由用户在表单里配置，位掩码存在账号行 capabilities 列。
/// - 读取能力的绑定（用户原话）：缓存音乐、下载文件、浏览、播放、流式传输。
class AccountCaps {
  AccountCaps._();

  static const int list = 1 << 0;
  static const int read = 1 << 1;
  static const int write = 1 << 2;
  static const int mkdir = 1 << 3; // 创建文件夹（用户决定：从「写入」拆出独立位）
  static const int move = 1 << 4; // 移动（含改名）
  static const int copy = 1 << 5;
  static const int delete = 1 << 6;

  static const int all = list | read | write | mkdir | move | copy | delete;

  /// 旧版全量掩码（六位时代）。能力勾选 UI 上线前所有账号行都是它，
  /// 读到时按当前全量处理，避免 mkdir 位缺失让 WebDAV 丢失建目录。
  static const int legacyAll = list | read | write | move | copy | delete;

  static int normalizeStored(int stored) => stored == legacyAll ? all : stored;

  /// WebDAV 账号：用户配置的位 + 强制「列出」。
  static int forWebdav(int stored) => (normalizeStored(stored) & all) | list;

  /// 云盘类型不在这里：能力位是驱动自描述的一部分（spec.capabilities，
  /// 99 §7.2.10），由驱动文件声明、兼容层查注册表取用。

  static bool has(int mask, int cap) => (mask & cap) != 0;
}
