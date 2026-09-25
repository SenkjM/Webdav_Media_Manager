# 12 · 云盘驱动移植指南

新盘落地的**操作手册**：照着做就能从 0 到 1 加一个 OpenList 驱动。
上游语义、格式对齐、踩过的坑写在 [11 §2/§3](11-CLOUD-DRIVER-PORTING.md)；本文件只讲**工序**。

- 事实基线：`baidu_netdisk`（首个端到端驱动，见 [11 §10](11-CLOUD-DRIVER-PORTING.md)）。
- 参照源码：`localdev/OpenList-Worker/src/backend/drivers/<name>/`（移植底稿，TS）、
  `localdev/OpenList/drivers/<name>/`（语义兜底，Go）。
- 与源码冲突时**以源码和测试为准**。

---

## 1. 解耦检查：移植一个驱动到底要碰哪些文件

新盘落地**只应该动两个文件**（一个新增、一个加一行）；其余全是「零改动」。
这张表是判断「这次改动是否漏了解耦」的基准。

| 层 | 文件 | 新盘落地是否需要改 |
|---|---|---|
| 接口 + spec 基类 | `lib/services/cloud_driver.dart` | **否**（除非要新增字段类型，见 §4） |
| 驱动本体 + spec | `lib/services/cloud_drivers/<name>_driver.dart` | **是**（新增） |
| 注册表 | `lib/services/cloud_drivers/driver_registry.dart` | **是**（加一行） |
| 驱动测试 | `test/<name>_driver_test.dart` | **是**（新增） |
| 兼容层 | `lib/services/cloud_drive_service.dart` | 否（只查表；crypt 类是例外，见 §7） |
| 账号表单 | `lib/screens/accounts_screen.dart` | 否（按 `spec.form` 通用渲染） |
| 凭证存储 | `lib/services/accounts_service.dart` | 否（`loadDriverConfig` / `saveDriverConfig` 通用通道） |
| 能力模型 | `lib/models/account_capabilities.dart` | 否（位定义早已定型） |
| 网络库 UI / 分流缝 | `lib/services/webdav_service.dart`、`lib/screens/network_library_screen.dart` | 否（按能力位遮罩，不认具体盘） |
| 下载 / 流式 | `lib/services/resumable_download.dart`、`WebDavStreamSource` | 否（`rawUrl` + `rawHeaders` 已贯穿） |

**结论**：地基（99 §4.7 阶段 0 与 4.2.10 的驱动自描述）是干净的。
`baidu_netdisk` 之后**没有为新盘改过任何公共层**——这是移植能流水线化的前提。

### 1.1 解耦的四条边界（违反任一即为「耦合漏进来了」）

1. **驱动不认账号 / 存储**：`cloud_driver.dart` 不 import `accounts_service` / `webdav_account`；
   驱动构造只吃 `Map<String, dynamic> config`。
2. **UI 不认具体盘**：`accounts_screen.dart` 里不该出现任何 `'baidu'` / `'quark'` 字面量（除测试）。
   类型下拉读 `kCloudDriverSpecs`。
3. **兼容层只查表**：`cloud_drive_service.dart` 里不该有 `if (type == 'xxx')` 的分支；
   它只做 `cloudDriverSpec(type).create(...)` / `.verify(...)` / `.capabilities`。
4. **公共层不改**：新增一个盘时 `git diff --stat` 应该只有两个文件（驱动 + 注册表）+ 一个测试。

> 检查方法：`git diff --stat main -- lib/` —— 除驱动文件与注册表外出现任何 lib/ 文件，
> 说明这次移植把盘的私有知识漏进了公共层，应当先收回到 spec 里。

---

## 2. 移植工序（固定六步）

### 第 1 步 · 读上游，列字段清单

读三份文件：

| 文件 | 取什么 |
|---|---|
| `localdev/OpenList-Worker/src/backend/drivers/<name>/types.ts` | `Addition` 有哪些字段（表单的候选） |
| `localdev/OpenList/drivers/<name>/meta.go` | **默认值**（照抄！）、`driver.Config`（`DefaultRoot` / `PreferProxy` / `NoOverwriteUpload`） |
| `localdev/OpenList-Worker/src/backend/drivers/<name>/driver.ts` | `init` / `list` / `get` / `mkdir` / `rename` / `move` / `copy` / `remove` |

**先报字段清单给用户确认**（99 §4.8 第 3 条）——不要闷头把 13 个字段全铺出来。

**字段裁剪规则**（照 [11 §10](11-CLOUD-DRIVER-PORTING.md) 百度先例）：

| 类别 | 处理 |
|---|---|
| 上传相关（`UploadThread` / 分片 / OSS 直传参数） | **砍掉**（上传已砍，99 §4.2.1） |
| `order_by` / `order_direction` / `only_list_video_file` | 不进表单（客户端自己排序 / 分类） |
| `use_online_api` 开关 | 用「在本地处理令牌刷新」开关取代（默认走在线续期） |
| `api_url_address` | 保留，默认值照抄 `meta.go`（多为 OpenList 公共服务） |
| `client_id` / `client_secret` | 保留，与 `local_refresh` 开关联动 |
| `root_folder_id` / `root_id` | 保留为表单字段（映射到账号远程路径语义时注意，见 §6.3） |
| `access_token` | **不进表单**，只做缓存（`onTokenUpdate` 持久化） |
| cookie 类字段 | 保留 + 表单里带「打开网页复制」教程链接（99 §4.9 注记） |

### 第 2 步 · 写 Addition + Client

- `XxxAddition`：`fromJson` / `toJson`，键名**与上游 Addition 一致**（便于对照排错）。
- `XxxClient`：持有 `Dio`、`accessToken`、`onTokenUpdate`；**构造可注入 Dio**（测试要用，
  见 §8.1 的 `_RoutingAdapter` 手法）。
- `validateStatus: (_) => true`——非 2xx 也要读到 body 才能「原样传递报错」（[11 §10](11-CLOUD-DRIVER-PORTING.md) 保存语义）。

### 第 3 步 · 写驱动（`extends CloudDriver`）

八个方法，逐一对应上游。**没有 `put`**（接口层就没有）。

- `init()`：登录 + **真连校验**（上游的 `uinfo` / `userInfo` 之类）。失败抛 `CloudDriverException`。
- `list(path)`：目录列表 → `CloudFileItem`。分页要翻完（百度 1000/页、123 100/页）。
- `get(path)`：**文件必须带 `rawUrl`**。拿不到时**抛真实原因**，不要返回无直链的条目
  （与 worker 的有意差异，[11 §10](11-CLOUD-DRIVER-PORTING.md)）。
- `mkdir` / `rename` / `remove` / `move` / `copy`：`rename` 跨目录时**降级为 move + newname**（接口契约）。

> **路径形态**：本应用给驱动的是**绝对路径**（浏览根由 `CloudDriveService.joinRemotePath` 拼好）。
> 上游若用 id（`resolveDirId` / `resolveFileId`），在驱动内维护 path→id 缓存（实例级即可，随重建失效，99 §4.6）。

### 第 4 步 · 写 spec

```dart
class XxxSpec extends CloudDriverSpec {
  const XxxSpec();

  @override
  String get typeId => 'xxx';              // 与 OpenList 驱动目录名一致

  @override
  String get displayName => 'XXX网盘';

  @override
  int get capabilities => AccountCaps.list | AccountCaps.read | ... ;  // 见 99 §4.3.2 表

  @override
  List<CloudDriverFormItem> get form => const [ ... ];

  @override
  CloudDriver create(Map<String, dynamic> config, {onTokenUpdate, env}) =>
      XxxDriver(addition: XxxAddition.fromJson(config), onTokenUpdate: onTokenUpdate);
}
```

**能力位**：`write` 一律不给。mkdir 逐盘核查表见 [99 §4.3.2](99-IN-PROGRESS.md)；
只读家族给 `list | read`。

### 第 5 步 · 注册

`driver_registry.dart` 加 import + 一行。位置即账号表单类型下拉的顺序。

### 第 6 步 · 测试

一盘一测试文件（§8）。**cookie / token 类必须带「过期报错原文透传」用例**。

---

## 3. 表单字段类型的四种用法

对照 `cloud_driver.dart` 的四个类：

| 类 | 用途 | 关键参数 |
|---|---|---|
| `CloudDriverField` | 文本 / 令牌 / 地址 / 密钥 | `required` / `obscure` / `defaultValue` |
| `CloudDriverSelectField` | 枚举（`drive_type` / `remove_way` / 编码） | `options: [(存库值, 显示名)]` / `required` / `defaultValue` |
| `CloudDriverAccountField` | 引用已有账号（crypt 的源） | 渲染器自动排除包装类自身 |
| `CloudDriverSwitchField` | 布尔开关 | `defaultValue`（**默认为真时要留意**，见 §5） |

### 3.1 开关联动：两种极性，别弄反（[11 §6](11-CLOUD-DRIVER-PORTING.md)）

| 参数 | 语义 | 典型用途 |
|---|---|---|
| `visibleWhenSwitch: 'k'` | k **打开才显示** | Client ID / Secret（仅本地刷新时需要） |
| `enabledWhenSwitch: 'k'` | k **打开才可编辑** | —— |
| `disabledWhenSwitch: 'k'` | k **打开则停用**（与上者极性相反） | 在线续期地址（本地刷新开启后应停用） |

- 两者**互斥声明**；同时声明视为未声明。
- 百度曾把极性接反：`local_refresh` 关掉时 online_api 反而变灰。
  回归测试 `test/baidu_refresh_switch_test.dart` 锁的是**后端分支**，
  极性本身由 `test/driver_switch_value_test.dart` 锁。**两个都要覆盖**。
- 停用时给 `disabledHint` 说明原因，别只变灰不解释。

---

## 4. 什么时候才允许改公共层

只有一种情况：**出现了现有四种字段类型表达不了的表单需求**。

先问三个问题：

1. 能不能用现有类型的组合表达？（多数情况可以）
2. 是不是「一个开关 + 两个可见字段」的变形？（那就是 §3.1 的极性）
3. 是不是只有这一个盘需要？

三个都是「否 / 是」才动 `cloud_driver.dart`；动了要同步改三处：
`accounts_screen.dart` 的 `ensureSpecControls`（建控件）、保存路径（组装 cfg）、渲染分支（画控件）。
**漏掉保存路径的症状**：开关保存后又自己关掉（[11 §6](11-CLOUD-DRIVER-PORTING.md) 实现坑）。

---

## 5. 默认值的坑

`CloudDriverSpec.switchValue()` 的优先级是
**实时值 → 该开关的 `defaultValue` → `false`**。中间一步**不能省**：
表单控件重建时 `values` 可能缺键，写死 `false` 会让「默认开」的开关被当成关，
联动字段被错误隐藏 / 停用，**且保存下来的值与界面显示相反**。

所以：
- 新增「默认开」的开关时（如 123_open 的 `use_online_api` 默认 `true`），
  必须确认 `switchValue` 走通，不要在任何地方写 `?? false`。
- 文本 / 下拉字段同理：`defaultValue` 在 `ensureSpecControls` 与保存路径里都要生效。

---

## 6. 各驱动形态的适配要点

### 6.1 登录形态（决定表单长什么样）

| 形态 | 特征 | 表单 | 例子 |
|---|---|---|---|
| **粘贴 refresh_token** | 最简 | `refresh_token`（必填、obscure）+ 在线续期地址 + 本地刷新开关 | baidu / 123_open / 115open |
| **粘贴 cookie** | 会过期，要重贴 | `cookie`（必填）+ 教程链接 | quark / terabox |
| **签名凭证** | 额外要 `app_id` + `sign_key` | 三项全必填；签名算法在 util | quark_open |
| **OAuth 回调** | 需要 client_id/secret + 回调页 | 复用 baidu 的 `local_refresh` 开关模式 | onedrive / google_drive |

### 6.2 直链形态（决定要不要流桥）

- **有直链**（多数）：`get()` 返回 `rawUrl` + `rawHeaders`，下载 / 流式直接走。
- **MustProxy**（`quark_open` / `google_drive`）：拿不到公开直链 →
  必须接本地流桥（范例 `crypt/crypt_stream_bridge.dart`，[11 §5](11-CLOUD-DRIVER-PORTING.md)）。
  `rawUrl` 留 null → `CloudDriveService` 自动走 `openContent` / 流桥分支。
- **POST 流**（`dropbox`）：下载不是 GET 直链，流桥要单独处理。

**必需请求头**（UA / Cookie / Referer）必须进 `rawHeaders` 并贯穿下载与流式，否则 403。

### 6.3 远程路径 vs root_folder_id

本应用有**通用**的「远程路径」字段（表单第一段，类型之后），映射到账号 `remotePath`，
由 `CloudDriveService.joinRemotePath` 拼在驱动路径前。

- 上游的 `root_folder_id` 若表达的是**路径**语义 → 优先用通用远程路径，不重复开字段。
- 若是**不透明 id**（123_open 的 `0`、115 的 `0`、aliyun 的 `root`）→ 保留为表单字段，
  且注意它和远程路径会**叠加**（如源账号根 `/456` + 源目录 `/789`）。

---

## 7. 包装类驱动（crypt 形态）

不走「新增一个盘」的流程，多两件事：

1. **`CloudDriverEnv.resolveSource`**：由兼容层注入，驱动不反向依赖 `WebDavService`。
2. **`runtimeCapabilities`**：随源映射并**剥掉 write**（防上传权限泄漏进 UI）。

源解析必须是「**id 优先、名字兜底**」，且表单保存时落一份源名快照 `<key>_name`
（[11 §4](11-CLOUD-DRIVER-PORTING.md)：源被删后重添同名账号即可恢复）。

---

## 8. 测试策略（[11 §7](11-CLOUD-DRIVER-PORTING.md)）

### 8.1 出站请求拦截手法（百度测试的范式）

驱动测试**不打真网络**。用自定义 `HttpClientAdapter` 按 host 分流到本地 `HttpServer`，
并记录每次请求的完整 URL 供断言（见 `test/baidu_refresh_switch_test.dart` 的 `_RoutingAdapter`）：

```dart
class _RoutingAdapter implements HttpClientAdapter {
  final List<Uri> hits = <Uri>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, ...) async {
    final uri = Uri.parse(options.uri.toString());
    hits.add(uri);
    // 按 uri.host / uri.path 分流到本地 server
  }
}
```

所以**驱动构造必须可注入 Dio**——这是可测性的前提。

### 8.2 一个盘至少覆盖

| 用例 | 断言 |
|---|---|
| 令牌刷新分支 | 请求打到哪个端点、带没带 client 凭证（百度已有两个分支各一条） |
| 列表解析 | 分页翻完、字段映射正确（含目录 / 文件判定） |
| 直链必需头 | `rawHeaders` 内容正确 |
| **错误原文透传** | 上游错误码 → `CloudDriverException` 且 message 含原文 |
| 开关极性 | 前端 `switchValue` + 后端分支**两边都锁** |
| 默认值 | 「默认开」的开关在缺键时仍为开（§5） |

### 8.3 金标向量优先（[11 §7](11-CLOUD-DRIVER-PORTING.md)）

有格式 / 算法要逐字节对齐时（crypt），编译上游工具生成向量固化进 `test/`，
**不要**「两边同时跑起来比对」。

---

## 9. 验收清单（代码完成 ≠ 可用）

自动化门槛：`flutter analyze` 干净 + `flutter test` 全过。**真机行为另算**（99 前言）。

- [ ] 添加账号：能换到 token 才保存；错误 token 原文报错且不落库
- [ ] 表单：动态字段顺序对、开关联动极性对、保存后值不回退
- [ ] 浏览：远程路径生效、分页正确、名字解码正确
- [ ] 下载 / 缓存音乐 / 本地播放
- [ ] 视频与音乐流式（直链 302 + 必需头；MustProxy 走流桥）
- [ ] 写操作四件套：重命名 / 删除 / 移动 / 复制
- [ ] 新建文件夹按钮按「创建文件夹」位遮罩
- [ ] 能力遮罩：无写权限的盘看不到写入口（隐藏而非置灰）
- [ ] token 过期 / cookie 过期的报错可读

---

## 10. 常见错误对照表

| 症状 | 根因 |
|---|---|
| 开关保存后又自己关掉 | 保存路径漏了该字段（§3 末尾） |
| 默认开的开关显示为关 | `switchValue` 回落写死 `false`（§5） |
| 该灰的不灰、不该灰的灰了 | 联动极性选错（§3.1） |
| 长标签右溢出 | 下拉漏了 `isExpanded`（[11 §6](11-CLOUD-DRIVER-PORTING.md)） |
| 上传入口凭空出现 | 能力位没收敛 / 包装类没剥 write（§7） |
| 下载 0B 文件 | `get()` 没带回真实 size（[11 §5](11-CLOUD-DRIVER-PORTING.md)） |
| 直链 403 | 必需请求头没进 `rawHeaders`（§6.2） |
| 校验失败按钮默默恢复 | 异常没转成人话（[11 §6](11-CLOUD-DRIVER-PORTING.md)） |
| 新增盘时改动了公共层 | 解耦漏了，按 §1.1 收回到 spec |

---

## 11. 多盘并行移植的工序（多子代理协作）

一批移植多个盘时，**绝不能共享同一个工作目录**。首批并行就踩过：
四个子代理共用一份 checkout，互相 `git checkout` 切走对方的 HEAD、
`driver_registry.dart`（唯一注册点）被反复覆盖、`git add -A` 把别人的半成品暂存进提交。
**修正后的固定工序**：

1. **每个驱动一个独立 `git worktree`**：
   `git worktree add D:\Code\wmm-wt-<name> driver/<name>`——
   分支、文件、`HEAD` 完全隔离，注册表不再打架。
2. **每个 worktree 单独 `flutter pub get`**（复制 `pubspec.lock` 保持依赖一致）。
   不要用 junction 复用主仓库的 `.dart_tool`——`package_config.json` 的相对
   `rootUri` 解析会歧义，可能静默测到主仓库的代码。
3. 子代理在自己目录里干活，**只 add 自己的文件**（禁 `git add -A`）、
   不切分支、不合并、不 push。
4. 合并由主会话统一做：每个分支测过（`flutter test test/<name>_driver_test.dart`
   全过）才进 feature，一次合一个，合一个测一次。
5. `driver_registry.dart` 的冲突是**预期内**的（所有分支都改同一行）——
   逐个合并时 ort 策略能自动处理（各分支基于同一基线），最后人工核对
   spec 列表顺序即可。

> 教训：注册表是单点，但**逐个合并**（而非同时合并）就没有冲突；
> 真正不能共享的是工作目录本身。

---

## 12. 边界（不要把计划当现状）

- **上传已砍**（99 §4.2.1）：不要移植 `Put` 与上传相关代码。
- 未落地的盘**先只进文档**，不要写影响运行的代码（99 §4.2.3 的静态表登记原则）。
- P0–P5 的批次判定与逐盘参数见 [99 §4.9](99-IN-PROGRESS.md)。
- 文档收口按 [00 §1](00-INDEX.md)：开发中写 [99](99-IN-PROGRESS.md)，
  完成后把语义搬进对应功能块，去掉占位。
