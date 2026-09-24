/// 账号能力遮罩（99 §7.2.3 / 7.2.5）。
///
/// 位枚举：列出 / 读取 / 写入 / 移动 / 复制 / 删除。
/// - 「列出」默认拥有、不在用户界面显示（没有对应按钮可关）。
/// - 云盘类型按驱动静态给定（[staticCaps]，上传已砍 → 一律没有 write）；
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

  /// 云盘类型的静态能力表（99 §7.3 首批；随驱动落地逐个登记）。
  /// write 一律不给：云盘账号不上传、不进同步 / 备份目标（7.2.1 / 7.2.8）。
  static const Map<String, int> staticCaps = <String, int>{
    'baidu_netdisk': list | read | mkdir | move | copy | delete,
  };

  /// WebDAV 账号：用户配置的位 + 强制「列出」。
  static int forWebdav(int stored) => (normalizeStored(stored) & all) | list;

  /// 云盘类型：静态表；未登记的类型只给「列出」（保守兜底）。
  static int forType(String providerType) =>
      staticCaps[providerType] ?? list;

  /// 账号行 → 生效能力掩码（按值传入，避免与 webdav_account.dart 循环依赖）。
  static int forAccountValues(String providerType, int storedCapabilities) =>
      providerType == 'webdav'
          ? forWebdav(storedCapabilities)
          : forType(providerType);

  static bool has(int mask, int cap) => (mask & cap) != 0;
}
