# 云盘驱动支撑层功能实现清单（已作废 · 重写参考）

> **状态声明**：本支撑层已随整批云盘驱动一并作废、待重写。本文档记录该支撑层的完整功能面供重写参考；全部事实来自下列源文件（截至本文写作时），未掺杂臆测。
>
> **来源与版权声明**：本文档为独立整理的功能性规格，仅描述本项目自有实现的可观察行为与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker 的任何源码或其衍生内容**。
>
> 注：crypt 驱动已通过外部包与调用实现版权隔离，不属于本文档的重写范围；正文中残余的 crypt 条目按「已外部化的包装能力」理解，仅为保持支撑层契约完整而保留。

覆盖源文件：
- `lib/services/cloud_driver.dart`（基类契约、数据与异常、路径工具、表单系统、spec 自描述层、CloudSource / CloudDriverEnv / CloudAccountSource）
- `lib/services/cloud_drivers/driver_registry.dart`（注册表）
- `lib/services/cloud_drivers/stream_bridge.dart`（MustProxy 本地流桥）
- `lib/services/cloud_drivers/webdav_source.dart`（WebDAV 账号 → CloudSource 适配）
- `test/cloud_registration_signature_test.dart`、`test/driver_secret_scope_test.dart`、`test/driver_switch_value_test.dart`、`test/crypt_stream_bridge_test.dart`（共享测试）

## 1. CloudDriver 基类契约

`abstract class CloudDriver`（lib/services/cloud_driver.dart:11）。核心语义：`get` 返回直链 + 必需请求头，下载与流式统一走「直链 + 头」。

**没有 put / 上传**——上传已按 99 §7.2.1 砍掉；`CloudDriverSpec.capabilities` 的静态能力位同样一律不含 write。

同文件顶部还导出 `enum CloudDownloadMode { cryptSequential, direct, cryptRange }`，供上层区分三种下载模式。

| 方法 | 语义 | 默认行为 | 哪类驱动覆写 |
|---|---|---|---|
| `init()` | 初始化（含真连） | 无默认（abstract） | 所有驱动必须实现 |
| `runtimeCapabilities` | 运行时能力位 | `null` = 用 spec 的静态表 | 包装驱动随源映射 |
| `runtimeTypeLabel` | 运行时类型名（账号列表 / 下拉显示） | `null` = 用静态 `displayName` | 包装驱动——类型名取决于包住的源，静态表表达不了；兼容层只读这个字符串 |
| `dispose()` | 释放跨请求资源（临时连接、缓存等）；兼容层重建 / 移除驱动实例时调用 | 空操作 | 只有真的持有跨请求资源的驱动；**新增驱动不必实现** |
| `openContent(String path)` | 产出解密后的内容流（下载内存流路径） | throw `UnsupportedError('该驱动不支持内容流读取')` | MustProxy 驱动 |
| `openDownloadContent(String path, {CancelToken? cancelToken})` | 优化的顺序下载流（可取消） | 委托 `openContent(path)` | 有优化顺序下载路径的驱动 |
| `openContentRange(String path, int start, int end)` | 区间读取，**含端点**，语义同 HTTP `Range: bytes=start-end`；本地流桥按播放器 / ffmpeg 的 Range 请求调它（99 §7.5） | throw `UnsupportedError('该驱动不支持区间读取')` | MustProxy 驱动，按块边界精确解密 |
| `list(String path)` | 列目录；`path` 是账号内绝对路径（浏览根拼接归 CloudDriveService，不归驱动） | abstract | 所有驱动 |
| `get(String path)` | 取单个条目；文件必须带 `CloudFileItem.rawUrl`；拿不到直链时抛 `CloudDriverException`，上层把真实原因透给用户 | abstract | 所有驱动 |
| `mkdir(String path)` | 建目录 | abstract | 所有驱动 |
| `rename(String path, String newPath)` | 改名 / 改路径；`newPath` 是**完整目标路径**；跨目录时由实现降级为「移动 + 改名」（百度 filemanager 的 move 自带 newname） | abstract | 所有驱动 |
| `remove(String path)` | 删除单个路径（目录 / 文件均可） | abstract | 所有驱动 |
| `move(String srcPath, String dstDir, String newName)` | 移动到 `dstDir`、名字 `newName`（调用方按目标全路径拆出） | abstract | 所有驱动 |
| `copy(String srcPath, String dstDir, String newName)` | 复制到 `dstDir`、名字 `newName` | abstract | 所有驱动 |

方法细节补充：

- `openDownloadContent` 是后来加的分层：驱动可以为下载场景提供优化的顺序读取路径（带 `CancelToken?` 取消），**默认实现直接委托 `openContent(path)`**，保持既有流路径不变——新驱动无优化需求时无需覆写。
- 三个流方法（`openContent` / `openDownloadContent` / `openContentRange`）默认全部抛 `UnsupportedError`：只有 MustProxy（拿不到公开直链、需要本地解密）的驱动才有内容流语义；能产 `rawUrl` 的驱动走「直链 + 头」，完全不碰这三个方法。
- `runtimeCapabilities` 与 `runtimeTypeLabel` 是「运行时视图」对「spec 静态表」的覆盖通道：返回 null 即回落静态表。兼容层只读这两个值，不知道也不需要知道包装驱动怎么算出来的（拼接规则在驱动内部）。
- `list` 的 `path` 是**账号内绝对路径**，浏览根（remotePath）的拼接归 `CloudDriveService`，驱动不做根路径拼接——这就是 `CloudAccountSource._join` 存在的原因（适配层补根，见 §6）。
- `rename` 的 `newPath` 是完整目标路径，跨目录场景由实现自行降级为「移动 + 改名」（如百度 filemanager 的 move 自带 newname 参数，一次调用完成）。
- `move` / `copy` 的 `newName` 由调用方从目标全路径拆出——「拆路径」的责任在兼容层，驱动只收目录 + 名字。

## 2. 数据与异常

### CloudDownloadMode

`enum CloudDownloadMode { cryptSequential, direct, cryptRange }`（与 `CloudDriver` 同文件导出）：上层区分三种下载路径——加密驱动顺序解密流、直链直接下载、加密驱动区间解密流。哪个账号走哪种由上层按 spec / 驱动特征决定，基类本身不持有该状态。

### CloudFileItem 字段

| 字段 | 类型 | 语义 |
|---|---|---|
| `name` | `String`（必填） | 条目名 |
| `isDir` | `bool`（必填） | 是否目录 |
| `size` | `int`（默认 0） | 字节数 |
| `modified` | `DateTime?` | 修改时间 |
| `rawUrl` | `String?` | 直链；`null` 表示该驱动拿不到公开直链（MustProxy，99 §7.5 的本地流桥议题） |
| `rawHeaders` | `Map<String, String>?` | 直链必需的请求头（Cookie / Referer / UA 等，多个网盘都需要） |

条目即「字段子集 + 直链」模型。下载与流式统一走「`rawUrl` + `rawHeaders`」。

### 两个异常类

- `CloudDriverException(message, [cause])`：通用驱动异常；`toString()` 在有 cause 时格式为 `message（cause）`。
- `CloudDriverDataException extends CloudDriverException`：**内容本身不可用**——解密 / 认证失败、数据损坏、密钥不匹配。**重试没有意义**（同一份字节再拉一次还是坏的），下载队列据此**直接判失败而不退避重试**。驱动负责把底层密码学库 / 传输层的这类失败翻译成它，上层（兼容层之上）不必认识任何具体实现。

## 3. 路径工具

- `cloudBasename(String p)`：按 `/` 切分取最后一段（空路径返回 `''`）。
- `cloudJoinPath(List<String> parts)`：各段再按 `/` 切开、去空段，单斜杠连接，结果以 `/` 开头（如 `['/a/', 'b'] → '/a/b'`；空段全部忽略）。
- `cloudDirname(String p)`：去掉空段后，若只剩 ≤1 段返回 `'/'`，否则返回 `'/' + 前 n-1 段`。

行为示例（按实现逐步推得，重写可直接当验收用例）：

| 调用 | 结果 |
|---|---|
| `cloudBasename('/a/b/c.txt')` | `'c.txt'` |
| `cloudBasename('/')` | `''`（切分出空段，last 也是空段） |
| `cloudJoinPath(['/a/', 'b', '', 'c'])` | `'/a/b/c'` |
| `cloudJoinPath([])` | `'/'` |
| `cloudDirname('/a/b/c')` | `'/a/b'` |
| `cloudDirname('/a')` / `cloudDirname('/')` | `'/'` |

## 4. 表单系统

`sealed class CloudDriverFormItem`：表单项按**声明顺序**渲染。四种具体字段：

| 字段类 | 参数 | 语义 |
|---|---|---|
| `CloudDriverField` | `key`、`label`、`hint`、`required`、`obscure`、`defaultValue`、`visibleWhenSwitch`、`enabledWhenSwitch`、`disabledWhenSwitch`、`disabledHint` | 文本字段（粘贴令牌 / 地址 / 密钥类）。`key` 是写入驱动配置 JSON 的键（与 Addition 序列化键一致）；`hint` 作 helperText；`required` 缺省时表单报「请填写 [label]」；`obscure` 为密文输入（带明暗切换），并自动进入 `secretFieldKeys`；`defaultValue` 如百度在线续期地址的公共服务 |
| `CloudDriverSelectField` | `key`、`label`、`options`、`defaultValue`、`required`、`hint` | 下拉选择（如 aliyundrive_open 的 drive_type）；`options` 是 `(存库值, 显示名)` 列表 |
| `CloudDriverAccountField` | `key`、`label`、`required`、`hint` | 账号引用字段（包装驱动的源账号）：渲染为现有账号下拉（WebDAV + 云盘，**排除声明了 `isWrapper` 的类型防套娃**），值为账号 id；选项来自运行时账号列表，由表单渲染器解析，spec 只声明占位 |
| `CloudDriverSwitchField` | `key`、`label`、`subtitle`、`defaultValue`（默认 false） | 开关字段 |

### 开关联动三种极性（均只作用于 `CloudDriverField`）

- `visibleWhenSwitch`：开关打开才**显示**该字段（如百度本地刷新的 Client ID / Secret）。
- `enabledWhenSwitch`：开关打开才**可编辑**。
- `disabledWhenSwitch`：开关打开则**停用**（如百度「在本地处理令牌刷新」开启后的在线续期地址——99 §7.3.1：一旦打开就不走 online api）。与 `enabledWhenSwitch` 极性相反；**两个字段互斥声明，同时声明视为未声明**（渲染层同一规则）。
- `disabledHint`：因 `enabledWhenSwitch` / `disabledWhenSwitch` 停用时替代 `hint` 的提示。

### 渲染层的双极性判定（accounts_screen 实际行为，被测试复刻锁定）

`driver_switch_value_test.dart` 复刻了 `accounts_screen` 渲染层对每个 `CloudDriverField` 的判定函数，作为「界面实际行为」的契约：

- `enabledWhenSwitch != null && disabledWhenSwitch == null` → 依赖「开了才可用」：字段可用 ⇔ `switchValue(enabledWhenSwitch)`。
- `disabledWhenSwitch != null && enabledWhenSwitch == null` → 依赖「开了就停用」：字段可用 ⇔ `!switchValue(disabledWhenSwitch)`。
- 两者同声明（或都不声明）→ 视为无依赖，恒可用。
- 可见性：`visibleWhenSwitch == null` 恒可见，否则可见 ⇔ `switchValue(visibleWhenSwitch)`。

重写若把联动下沉为数据模型内置规则，上述「同声明视为无依赖」与两种极性的真值表必须原样保持或显式报错。

### `CloudDriverSpec.switchValue(key, values)` 的三级回退

优先级：`values` 里的实时值 → 该开关声明的 `CloudDriverSwitchField.defaultValue` → `false`。

中间一步不能省的原因（默认开开关的回退坑）：表单控件重建时 `values` 可能缺键，此时若写死 false，「默认开」的开关就会被当成关——联动字段被错误隐藏 / 停用，且保存下来的值与界面显示相反。这是历史上「开关联动回退」bug 的根因（渲染 / 联动路径写死 `?? false`、初始化与保存路径用 `?? item.defaultValue`，两条路径不一致）；修复后渲染、联动、保存统一走 `switchValue` 单一事实来源。

实际行为细节：`values` 命中即返回（即使该键未被本 spec 声明为开关——测试锁定此行为）；未声明且 `values` 缺键才落到 `false`。

## 5. CloudDriverSpec 自描述层

每个驱动文件导出一个 `CloudDriverSpec` 常量：类型、显示名、能力遮罩、表单参数、构造与校验收在驱动文件里，注册表只认这个形状。账号表单按 spec 通用渲染，兼容层只查表。

| 成员 | 语义 |
|---|---|
| `typeId` | provider_type 存库值（如 `'baidu_netdisk'`） |
| `displayName` | 界面显示名（类型下拉） |
| `capabilities` | 静态能力位（AccountCaps 位或）；write 一律不给（99 §7.2.1） |
| `isWrapper` | 是否为包装驱动（自己包住另一个账号当内容源）；默认 false。**只影响**账号表单「账号引用字段」的候选列表——包装驱动不出现在源下拉里（防套娃）；UI 只问这个布尔值，不认识任何具体类型 |
| `form` | 动态表单项（顺序即界面顺序）；远程路径是通用字段，不在这里 |
| `secretFieldKeys` | 驱动配置 JSON 里的密文字段键集合（账号凭证同步 / 备份的加密范围）。组成规则：`{form 里 `CloudDriverField.obscure` 为 true 的 key}` ∪ `runtimeSecretKeys`。新驱动加 obscure 字段自动纳入 |
| `runtimeSecretKeys` | 运行时经 `onTokenUpdate` 写回驱动配置的**凭证缓存键**（令牌轮换类驱动必须声明），默认空集。目的：表单 obscure 只覆盖「用户粘贴进表单」的密文；驱动运行时把轮换后的令牌（如百度 / 123 的 `access_token` 缓存）写回驱动配置，这些键不在表单里、`secretFieldKeys` 看不见——**不声明就会明文进凭证库与备份**。无令牌轮换的驱动（netease / terabox 等）保持默认空集 |
| `create(config, {onTokenUpdate, env})` | 用表单值构造驱动实例；`onTokenUpdate` 收令牌轮换 patch（键值对），兼容层负责持久化；`env` 供包装驱动做源解析 |
| `verify(config, {onTokenUpdate, env})` | 表单保存前的真连校验；**默认实现 = `create(...).init()`**（99 §7.3.1），驱动一般不覆写 |

## 6. 包装驱动机制

### CloudSource 契约（包装驱动的「内容源」= 内层账号的能力视图）

| 成员 | 语义 |
|---|---|
| `basePath` | 源账号浏览根（含远程路径），路径映射的基座 |
| `displayName` | 源显示名（包装驱动拼运行时类型名用）；默认 `''`，未知 / 不适用时包装驱动自行退化 |
| `capabilities` | 源账号的生效能力位 |
| `list / get / mkdir / rename / remove / move / copy` | 与 `CloudDriver` 同名方法同构；`get` 返回**密文**直链 + 必需头（包装驱动的解密层自用） |

### CloudDriverEnv（兼容层注入给驱动的运行环境）

`class CloudDriverEnv` 构造参数即两个解析回调；是「装配层 → 兼容层 → 驱动」的依赖方向载体：驱动（包装层）通过它拿到内层账号的 `CloudSource`，而不 import 任何服务层。

- `resolveSource(String accountId)`：按账号 id 解析内容源（WebDAV 或云盘适配器）；源不存在返回 null。
- `resolveSourceByName(String accountName)`：按**账号名**解析（精确匹配账号显示名，找不到返回 null；未注入时只认 id）。存在原因：源账号被删后重添同名账号可恢复绑定（真机反馈）。

### CloudAccountSource（云盘账号 → CloudSource）

包住已注册的内层驱动，路径挂到浏览根：

- 路径拼接：`_join(path) = cloudJoinPath([basePath, path])`；`list / get / mkdir / remove` 单路径直接拼；`rename` 两个路径都拼；`move / copy` 拼接 `srcPath` 与 `dstDir`，`newName` 原样透传给内层驱动。
- 能力透传：`capabilities` 由构造函数注入（装配层传入），不从 driver 读取；`displayName` 同样构造注入（默认 `''`）。
- 所有方法直接转调内层驱动对应方法。

## 7. 注册表（driver_registry.dart）

- `const List<CloudDriverSpec> kCloudDriverSpecs`：已落地驱动列表，**顺序即账号表单类型下拉的显示顺序**。当前顺序：`BaiduNetdiskSpec`、`Driver123OpenSpec`、`Open115Spec`、`AliyundriveOpenSpec`、`TeraboxSpec`、`NeteaseMusicSpec`。crypt 原注册在最后（包装层），现已通过外部包实现版权隔离，不再作为内置 spec；netease_music 放最后一个独立位（用户决定）；其余按落地时间序。
- `CloudDriverSpec? cloudDriverSpec(String typeId)`：按存库的 provider_type 查描述符，未注册返回 null。
- 机制：**新增一个网盘 = 新增驱动文件（驱动 + Addition + 能力遮罩 + 表单参数全在里头）+ 在 `kCloudDriverSpecs` 加一行**；账号表单与兼容层零改动。包装类驱动同样在这里注册，`spec.create()` 包住内层驱动。

## 8. stream_bridge.dart：本地流桥（LocalStreamBridge）

**用途**：MustProxy 驱动的本地流桥（99 §7.5）。media_kit / ffmpeg 只认 URL 或本地路径，不认 Dart 字节流，所以把 `CloudDriver.openContentRange` 包成一个**只监听回环地址**（`InternetAddress.loopbackIPv4`，端口 0 随机）的 HTTP 端点：播放器发 Range 请求，桥转调驱动的 `ranges` 回调（按驱动的块边界精确解密）并回 206。

**通用设施定位**：不含任何驱动 / 密码学知识——字节流由调用方以 `expose` 的 `ranges` 回调传入，哪个驱动需要它、怎么解密都与本文件无关。

**实现要点**：

- `expose({accountId, remotePath, size, ranges, name})` → `http://127.0.0.1:{port}/s/{token}`。内部 key 为 `'$accountId\u0000$remotePath`；**同一路径复用同一 token**（重复播放不积累条目），复用时仅替换 `ranges` 回调；`size` 变化则换新 token（旧的从 token 表移除）。
- `name`（解密后的文件名）按扩展名给 ffmpeg 一个像样的 Content-Type（猜不中回 `application/octet-stream`），免得它把未知二进制当成不可播放的流。映射：mp4/m4v→`video/mp4`、mkv→`video/x-matroska`、webm→`video/webm`、avi→`video/x-msvideo`、mov→`video/quicktime`、ts→`video/mp2t`、mp3→`audio/mpeg`、flac→`audio/flac`、m4a→`audio/mp4`、aac→`audio/aac`、wav→`audio/wav`、ogg/opus→`audio/ogg`。
- token = 16 字节 `Random.secure()` 十六进制；URL 里不含账号凭证；只接受 GET / HEAD（其余 405），未知 token / 路径不符 404。
- 请求处理：始终设 `Accept-Ranges: bytes`；HEAD → 200 + `Content-Length = size`；无 Range 头 → 200 + 全量流（`0..size-1`）；合法 Range → 206 + `Content-Range` + 区间流。`_parseRange` 支持 `bytes=a-b` / `bytes=a-`（end 补 size-1）/ `bytes=-n`（后缀：start = size-n）；越界按 HTTP 语义裁剪（end ≥ size 收到 size-1）；无法解析或区间无效返回 null——调用方按 200 回整份内容，**不报错**。
- 空闲 `idleTimeout`（默认 10 分钟）后自动 `dispose`（关服务器 + 清 token）；播放中每个请求都刷新计时。
- 由兼容层持有（跨驱动重建存活）：驱动实例被重建后，兼容层重新 `expose` 换新 `ranges` 回调，正在播放的流不被掐断。
- 流中途出错：响应头可能已发出，只能尝试置 500 并断开连接，让播放器自己重试。

## 9. webdav_source.dart：WebDavAccountSource

**适配方式**：WebDAV 账号 → `CloudSource`，转调 `WebDavService` 同名方法（`listDirectory / buildStreamSource / statPath / createFolder / renamePath / deletePath / movePath / copyPath`）。

- `basePath` = `WebDavAccount.normalizeRemotePath(account.remotePath)`；`displayName` 固定 `'WebDAV'`；`capabilities` = `AccountCaps.forWebdav(account.capabilities)`。
- `list`：把 WebDAV 条目映射为 `CloudFileItem`（`rawUrl: null`——列表不产直链）。
- `get`：`buildStreamSource(accountId, remotePath, name)` 为 null 时抛 `CloudDriverException('WebDAV 未连接，无法取源内容')`；随后单独 `statPath`（PROPFIND）补 size / modified——**单文件大小列表接口拿不到**，而流式回 Content-Length、下载进度、Range 分块判断全依赖它；stat 失败**不阻断**（size 留 0，由上层「无法确定大小」明确报错，而不是这里抛含糊的网络错误）。返回 `rawUrl = s.uri`、`rawHeaders = s.headers`。
- `move / copy` 的目标路径拼法与 `CloudAccountSource` 不同：这里直接 `cloudJoinPath([dstDir, newName])` 成完整路径传给 WebDavService。

**为什么独立于 CloudAccountSource**（代码注释所述的分层理由）：WebDAV 不走 `CloudDriver` 兼容层（`WebDavService` 是单列的），而包装驱动只认 `CloudSource` 抽象。装配层把「怎么把一个 WebDAV 账号包成 CloudSource」注入给兼容层（`CloudDriveService.attachWebDavSourceFactory`），于是**兼容层不必反向依赖 WebDavService**；`cloud_driver.dart` 接口层因此保持零反向依赖（那里才需要 import WebDavService）。

## 10. 共享测试（重写必须保持的契约）

### test/cloud_registration_signature_test.dart —— 登记指纹

背景：启动、每次进出账号页 / 网络库 / 同步页都会调 `CloudDriveService.registerAccounts`，而重建驱动会丢掉驱动内部的 path→id 缓存、直链解析缓存与连接池（真机表现为深层目录重复解析、播放中途重新解析直链）。判据必须**不放过任何真实的配置变更**，也**不能把驱动写回的令牌当作用户改配置**（否则一次令牌轮换就白重建一遍）。

- `cloudAccountSignature`：同账号 + 同配置 → 指纹相同；配置键写入顺序不影响；任何一个配置值变化（含**少一个键**——外部写坏配置也算）→ 指纹不同；账号侧字段（名字 / providerType / 浏览根）变化 → 指纹不同；配置 null ≡ 空配置。
- `cloudRegistrationSignature`：账号遍历顺序不影响整批指纹；新增 / 删除账号 → 整批指纹变化（删除的驱动被回收）；令牌轮换（驱动写回配置）后，`_persistTokens` 就地更新该账号指纹并重算整批指纹，结果必须等于「下次 registerAccounts 从存储重读配置」算出的值（否则白重建）。

### test/driver_secret_scope_test.dart —— 加密范围

规则（08 §2）：`secretFieldKeys` = 表单 obscure 字段 ∪ `runtimeSecretKeys`。加密范围自动推导，但**令牌缓存键是否已声明要人工确认**——新驱动落地必须补一条实测。

- 逐驱动断言：baidu_netdisk / 123_open / aliyundrive_open 含 `refresh_token / client_secret / access_token` 且不含 `client_id` 等非密文键；115open 含 `refresh_token + access_token`、`runtimeSecretKeys == {'access_token'}`；netease_music / terabox 仅 `['cookie']` 且 `runtimeSecretKeys` 为空。crypt 已通过外部包实现版权隔离，其凭证键断言随外部化移出内置断言范围。
- 结构性断言：所有已注册 spec 的 `secretFieldKeys` 非空——空集说明「无凭证也无令牌」，需要确认是事实而不是漏声明。
- 隐式键清点（11 §6.2）：每个 typeId 必须进 `audited` 清单，且 `secretFieldKeys ⊆ audited[typeId]`（密文键必须落在已定性键里）；新驱动 / 新键落地要对照 `Addition.fromJson/toJson` 与 `onTokenUpdate` 写回的键更新清单，漏登记从断言失败暴露。

### test/driver_switch_value_test.dart —— 开关取值与联动

锁死 `CloudDriverSpec.switchValue` 语义（见 §4）：实时值优先于 spec 默认值；缺键回落到 spec 默认值而不是 false（bug 核心断言：默认开 + 缺键 → 开）；只缺被依赖键时其余键仍按实时值；`values` 命中即使未声明也返回实时值、缺键且未声明才 false。

锁死百度 `local_refresh` 联动极性（99 §7.3.1）：默认关；`client_id / client_secret` 的 `visibleWhenSwitch == 'local_refresh'`（开才显示）；`api_url_address` 的 `disabledWhenSwitch == 'local_refresh'` 且 `enabledWhenSwitch` 为 null（**开了就停用**，不是开了才可用）；关闭＝在线续期地址可编辑，打开＝地址停用。另断言所有联动引用（visibleWhenSwitch / enabledWhenSwitch / disabledWhenSwitch）指向 form 里真实存在的开关键（防拼写错导致永远 false）。

### test/crypt_stream_bridge_test.dart —— 桥与包装源端到端

测试夹具结构（重写时可直接借鉴分层）：

- `_SliceDriver extends CloudDriver`：区间读取直接切内存字节（`Uint8List.sublistView`），并记录每次调用的 `(start, end)`，用来单独验证桥的 HTTP 语义（不掺任何解密逻辑）。
- `_RangeServer`：本地 `HttpServer`，像真实网盘直链那样支持 `bytes=a-b` Range（含越界裁剪到 `body.length - 1`），回 206 + `Content-Range`，并计数请求数——模拟 MustProxy 依赖的密文直链源。
- `_LinkSource extends FakeCloudSource`（复用 crypt 测试的假源，该源现属外部包集成测试范围）：`get()` 返回指向 `_RangeServer` 的 `rawUrl`。

断言内容：

- 桥的 HTTP 语义（用 `_SliceDriver`）：HEAD → 200 + Content-Length；全量 GET → 200 + 完整字节；`bytes=10-19` → 206 + `Content-Range: bytes 10-19/1000` + 正确切片且驱动收到 `(10, 19)`；后缀 `bytes=-5` → 末 5 字节；未知 token → 404。
- 外部 crypt 包端到端（经外部包 + 调用实现版权隔离，细节归外部包文档，本文档不展开）：覆盖 `openContent` 全量解密、`openContentRange` 跨块区间（含首尾块裁剪）与桥端到端 Range → 206 三类契约，作为包装接口的行为基准保留。

## 11. 重写注意事项（从实现中提炼的陷阱）

1. **switchValue 三级回退不能简化**：渲染、联动、保存必须共用同一取值函数；任何路径写死 `?? false` 都会复发「默认开开关被当成关 → 联动字段错隐藏 / 停用、保存值与界面相反」的回退 bug。
2. **enabledWhenSwitch / disabledWhenSwitch 互斥**：同时声明视为未声明（渲染层与测试同规则）；重写若改成类型安全的多选一，需保持「同声明 = 无依赖」的兼容语义或显式报错。
3. **令牌轮换驱动必须声明 runtimeSecretKeys**：运行时 `onTokenUpdate` 写回的键不在表单里，`secretFieldKeys` 的 obscure 推导看不见它们；漏声明 = 轮换后的令牌明文进凭证库与备份。测试只能人工逐驱动确认，重写应考虑结构性手段（如写回通道强制带密文标记）。
4. **登记指纹的双重要求**：不漏任何真实配置变更（含「少键」），同时令牌写回必须**就地同步整批指纹**，使其等于下次从存储重算的值——否则每次轮换白重建一遍驱动（丢 path→id 缓存、直链缓存、连接池）。
5. **WebDAV 单文件 size 需单独 PROPFIND**：列表接口对单文件拿不到 size，而流式 Content-Length / 下载进度 / Range 分块全依赖它；stat 失败应留 size=0 交给上层明确报错，不要在适配层抛含糊网络错误。
6. **两个 CloudSource 适配器的 move/copy 拼法不一致**：`CloudAccountSource` 透传 `newName` 给内层驱动；`WebDavAccountSource` 自己拼 `cloudJoinPath([dstDir, newName])`。重写统一契约时应显式定义「目标路径由谁拼」。
7. **流桥的 token 生命周期**：同路径复用同 token、size 变化换 token、驱动重建只换 `ranges` 回调（播放不断流）、空闲关服（默认 10 分钟）。桥由兼容层持有而非驱动持有，这是「驱动重建不掐断播放」的前提。
8. **Range 解析失败回 200 全量，不报错**：桥的 `_parseRange` 无法解析 / 区间无效一律返回 null → 200 整份内容，这是与播放器兼容的宽松语义，不是疏漏。
9. **Content-Type 影响可播性**：按解密后文件名的扩展名给 Content-Type 是必须的——ffmpeg 拿到 `application/octet-stream` 会当成不可播放流。
10. **隐式键清点清单与注释存在不一致**：`driver_secret_scope_test.dart` 的 `audited` 声称「当前全量清点」，但 baidu_netdisk（注释 6 键，集合缺 `local_refresh`）、netease_music（注释 2 键，集合仅 `cookie`）的集合比注释少（crypt 相关断言已随外部化移出，历史版本同样存在注释 9 键、集合仅 `{password, salt}` 的不一致）；断言只检查 `secretFieldKeys ⊆ audited` 单方向，故仍通过。重写时应让清点真正双向完整（明文键也要进清单），否则漏登记的明文键不会暴露。
11. **isWrapper 只防账号下拉套娃**：它不影响能力位或运行时行为，UI 只用它过滤账号引用字段候选；重写不要赋予它更多语义。
12. **dispose 默认空操作是有意设计**：新增驱动不必实现；只有持有跨请求资源（连接池 / 缓存）的驱动才覆写，避免样板代码。
13. **verify 默认 = create + init**：真连校验是表单保存前的统一行为（99 §7.3.1）；个别驱动覆写时应保持「失败即不准保存」的外部语义。
