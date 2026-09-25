# 11 · 从 OpenList / rclone 移植云盘驱动

把上游驱动搬进本应用时的现场笔记：架构怎么映射、哪些字节必须一模一样、哪里踩过坑。
**写的是现状与已验证的事实**；与源码冲突时以源码和测试为准。

参照物（`localdev/`，已 gitignore，只读参考）：

- `localdev/OpenList/` —— OpenList 源码（驱动接口 `driver/driver.go`，各驱动的 `driver.go` / `meta.go` / `util.go`）。
- `localdev/rclone/` 与 `localdev/rclone.exe` —— rclone v1.75.1，crypt 格式的权威实现，用来生成金标向量。
- 本应用侧：`lib/services/cloud_driver.dart`（驱动接口 + spec）、`lib/services/cloud_drivers/`。

## 1. 架构映射

| OpenList | 本应用 | 说明 |
|---|---|---|
| `driver.Driver`（Init / List / Link / Mkdir / Rename / Move / Copy / Remove / Put） | `CloudDriver`（init / list / get / mkdir / rename / move / copy / remove） | `Link` 合并进 `get()`：`CloudFileItem.rawUrl` + `rawHeaders`；**没有 put** |
| `model.Obj`（Name / Size / Modified / Path / IsFolder） | `CloudFileItem` | 名字一律用**解密 / 展示后**的名字 |
| `driver.Addition`（驱动表单 JSON） | `CloudDriverSpec.form` | 见 §6 |
| 各驱动的实际能力（靠人读源码判断） | 能力位 `AccountCaps` | 上游没有能力表，移植时逐个核对 |
| `Link{URL, Header}` | `rawUrl` / `rawHeaders` | `rawUrl == null` 表示 MustProxy，见 §5 |

**铁律**：驱动只描述自己（`CloudDriverSpec`）——表单渲染、校验、持久化、能力遮罩全由 spec 驱动，上游知识不要漏进界面层。

## 2. 必须逐字节对齐的部分

- **crypt 内容格式**：魔数 `RCLONE\0\0`(8B) + 随机 nonce(24B)；64KiB 明文一块，每块 secretbox（XSalsa20-Poly1305，**MAC 在前 16B**），块 nonce = 文件 nonce + 块号（小端 64 位加法）；整文件头 32B。
- **KDF**：scrypt(N=16384, r=8, p=1, dkLen=80) → dataKey(32) / nameKey(32) / nameTweak(16)。
- **名字**：PKCS7 补齐到 16B → AES-256-**EME**（≤128 块，超长名字必须拒绝）→ 编码三选一：Base32（Hex 表小写去填充）/ Base64（URL 安全去填充）/ Base32768。
- **base32768**：1028 个码点（都是 32 的倍数、升序，前 4 个给尾部 / 7 位块用）、15 位一块、末块 7 位、缺位补 1；字母表由上游生成（`cipher/base32768_table.dart`）。
- **默认值照抄 OpenList `meta.go`**：`filename_encryption` 默认 `off`、`filename_encoding` 默认 `base64`、`encrypted_suffix` 默认 `.bin`、`directory_name_encryption` 默认 `false`。

## 3. 踩过的坑

1. **UTF-8 vs UTF-16**：Go 的 `[]byte(s)` 是 UTF-8，Dart 的 `String.codeUnits` 是 UTF-16 码元。密码与盐必须走 `utf8.encode`，否则非 ASCII 密码会静默算错。
2. **空密码不是「不加密」**：rclone 的空密码 = 全零密钥，是格式的一部分，必须照算。
3. **盐为空 = 用 rclone 内置 `defaultSalt`**（16B `A8 0D F4 3A 8F BD 03 08 A7 CA B8 3E 58 1F 86 B1`），不是「无盐」。OpenList 把 salt 去掉 obfuscated 前缀后当作 rclone 的 `password2` 传入，语义相同。
4. **secretbox 布局是 `tag(16) || ciphertext`**；认证失败必须抛错，绝不写出半截文件。
5. **坏名字的兜底行为**（OpenList `driver.go` 202-219）：解密失败时用**原名原大小透传**，不写入、不二次加密。本应用照抄——不能因为名字解密不了就丢文件。
6. **拿不到直链的驱动是 MustProxy**：不要给用户密文直链。下载走 `openContent`，播放走本地流桥（§5）。
7. **`size` 的语义**：上游条目里是**密文**字节数，crypt 必须用 `decryptedSize` 换算成明文字节数再交给上层（进度条、Content-Length 都依赖它）。
8. **能力位要显式收敛**：只读家族给 `list|read`；`legacyAll=63` 会被归一化成能力位；包装类驱动（crypt）随源映射并**剥掉 write**，否则加密目录里会凭空出现上传入口。

## 4. 令牌、缓存与生命周期

- `access_token` / cookie 缓存写进驱动配置（`onTokenUpdate` → `AccountsService.saveDriverConfig`），重建驱动不丢登录态。
- 驱动实例由 `CloudDriveService.registerAccounts` 管：账号变更即重建；配置缺失或类型未接入时**跳过而不是崩**。
- 上游驱动内部的 path→id 缓存：本应用实例级持有即可，随实例重建失效。跨会话缓存没做。
- 凭证、token 一律不进日志、不进提交（`00 §3.6`）。
- **包装驱动（crypt）的源解析必须是「id 优先、名字兜底」**：源账号 id 是主键，但表单保存时同时落一份**源账号名快照**（`<key>_name`）。源账号被删除后 id 永远找不到，此时按名字精确匹配（忽略首尾空白）找回——用户**重新添加一个同名源账号即可恢复 crypt**，不必重建 crypt 账号（真机反馈：报错只显示一长串源 id，重加源也接不上）。名字也对不上才报错，且错误信息用**源名字**表达而非裸 id，并直接告知「重新添加同名源账号即可恢复」。

## 5. 直链、Range 与本地流桥

- 直链必需请求头（Cookie / Referer / UA）要贯穿下载与流式播放：`CloudFileItem.rawHeaders` → `WebDavStreamSource.headers`。
- **源可能忽略 Range**：请求 `bytes=0-31` 却回 200 + 整包是常见行为。此时只能整包处理（crypt 的 `shape == wholeBody` 分支），不要假设一定拿到 206。
- **源适配层必须给 size**：`WebDavAccountSource.get()` 一度漏掉 size（真机反馈：流式报「无法确定大小」、下载产出 0B 文件），后来用单文件 PROPFIND（`statPath`）补上。任何新源的 `get()` 都要带回真实条目大小；拿不到就明说，交给上层报错。
- **crypt 的大小判定是四态 `shape`**（`crypt_driver.dart` 的 `_CryptTarget`）：整包（响应体 > 32B）/ 空文件（密文恰 32B，明文 0B，合法）/ Range 分块 / 大小未知。**未知必须显式报错，绝不静默产出空内容**——这是竞态防线：元数据 size 与内容错位时，`Content-Range` 总长（与内容同请求）优先纠正元数据；两者都没有就报错。
- 后缀区间 `bytes=-n`、开放区间 `bytes=a-` 都要按 HTTP 语义处理，越界要裁剪。
- **播放器只认 URL 或本地路径**（media_kit / ffmpeg），不认 Dart 的 `Stream`。MustProxy 驱动要播放就必须有本地流桥，范例是 `crypt/crypt_stream_bridge.dart`：只监听 `127.0.0.1`、token 一次性映射 (accountId, path) 且 URL 不含凭证、HEAD 给 Content-Length、无 Range 回 200、有 Range 回 206 + Content-Range、按扩展名给 Content-Type、空闲自动关服务器。
- 桥接之后**播放入口不需要任何分支**：`resolveStreamSource` 统一返回「URL + 请求头」，调用方无感。

## 6. 表单与 spec

- 字段类型：`CloudDriverField`（文本）/ `CloudDriverSelectField` / `CloudDriverAccountField`（引用已有账号）/ `CloudDriverSwitchField`。
- 字段联动有**两种极性**，别弄反：`visibleWhenSwitch` / `enabledWhenSwitch` = 开关打开才显示 / 可编辑；`disabledWhenSwitch` = 开关打开则**停用**（百度「在本地处理令牌刷新」开启后在线续期地址变灰就是它，实例见 [§10](#10-已落地驱动实录baidu_netdisk)，验收项见 [99 §4.3.1](99-IN-PROGRESS.md)）。选错极性的症状：该灰的不灰、不该灰的灰了。
- 「源账号」下拉必须排除包装类账号自身（crypt 不能以 crypt 为源），否则会自引用。
- 实现坑：SelectField / SwitchField 的值必须真正写进 `cfg`（漏了会表现为「开关保存后又自己关掉」）；文本字段的 controller 要由表单统一创建复用；下拉加 `isExpanded`，否则长标签右溢出。
- 校验失败必须有**看得见的提示**：弹窗内联 + 最顶层横幅双通道；驱动的真连验证（`spec.verify`）抛什么异常都要转成人话，不能让异常冒泡后按钮默默恢复。

## 7. 测试策略

- **优先用上游生成金标向量**，而不是「两边同时跑起来比对」：编译上游工具生成向量并固化进 `test/`。crypt 就是这么做的（名字 ×4、内容 ×2、混淆 ×1 + NaCl 官方向量）。
- 上游自带测试用例可以直接搬：`base32768` 用的是 rclone `TestEncodeFileNameBase32768` 的 17 条向量 + 非法输入位置 + 0..200 全长度往返。
- 分块 / 区间类逻辑要有**等价性测试**：「逐块解密结果 == 整包解密结果」；桥要有 HTTP 语义测试（HEAD / 200 / 206 / 后缀区间 / 未知 token 404）。
- 端到端可以自己架一个支持 Range 的本地密文服务当「源」，验证 Range → 块解密 → 内容逐字节一致。

## 8. 工程约定

- 一个驱动 = 一个文件（`cloud_drivers/<name>_driver.dart`）+ 在 `driver_registry.dart` 注册 spec + 一份测试。
- 上游源码放 `localdev/`（gitignored），只读参考，不进构建。
- **上传已砍**（[99 §4.2](99-IN-PROGRESS.md) 取舍 1）：不要移植 `Put` 与上传相关代码。
- 文档收口按 `00 §1`：开发中写 [99](99-IN-PROGRESS.md)，完成后把语义搬进对应功能块，去掉占位。

## 9. 还没做的（不要把计划当现状）

- libsodium FFI 引擎，以及与纯 Dart 实现的手动切换（两套实现同格式，可随时互切）。
- OpenList 驱动清单里其余条目：批次方案与逐盘评估见 [99 §4.9](99-IN-PROGRESS.md) 与 [13](13-DRIVER-BATCH-PLAN.md)（只读家族 = 能力遮罩，不单独实现写路径）。
- 下沉到后续批次的 P1 盘：`quark_open`（MustProxy，要通用流桥）、`139`（5 种账号形态 + 编码待验）、`quark`(cookie)（等 quark_open 的流桥形态一起做）——判定见 [13 §2.2](13-DRIVER-BATCH-PLAN.md)。
- 跨会话的 path→id 缓存与离线可用性策略。
- 云盘账号的其它播放形态（后台播放、投屏等）未评估。

## 10. 已落地驱动实录：baidu_netdisk

第一个走完「spec 自描述 → 表单通用渲染 → 能力遮罩 → 真连验证」全链路的驱动（已实现，真机验收清单在 [99 §4.3.1](99-IN-PROGRESS.md)）。后续驱动照这套模式铺（[99 §4.9](99-IN-PROGRESS.md) 的移植模板）。

- **动态区顺序**：refresh_token（必填，粘贴，可切换明文）→ 远程路径（默认 `/`，空置视为 `/`）→ 在线续期地址（默认 OpenList 公共服务 `api.oplist.org/baiduyun/renewapi`，常驻可编辑）→ 开关「在本地处理令牌刷新」→ Client ID / Secret（仅开关开启时显示）。
- **开关语义（用户原话）**：「加一个开关：在本地处理令牌刷新，开启后显示Client ID和 Client Secret同时online_api变灰不可用，后端时也需要检查该开关，一旦打开就不使用online api逻辑而使用自建百度应用的刷新逻辑。」实现为 `BaiduAddition.localRefresh`，`BaiduClient.refreshToken()` 每次都检查。
- **保存语义（用户原话）**：「能获取到access_token即保存，不能获取到的话则原样传递报错。」保存前 `verifyNewAccount` 真连一次（换 token + uinfo 校验），失败把 `CloudDriverException` 原文弹给用户、不落库、表单内容保留。
- **存储映射**：refresh_token / client_id / client_secret / api_url_address / local_refresh / access_token 缓存 → `AccountsService.saveDriverConfig`（secure storage JSON，按账号隔离，删号即清）；remote_path / provider_type → accounts 表。
- **不进表单**：crack 全部、上传 6 字段、order_by / only_list_video_file（客户端自己排序 / 分类）、use_online_api 开关（被本地刷新开关取代，默认走在线续期）。
- **开关极性缺陷记录**（真机反馈后修正）：`localRefresh` 开关的联动极性曾接反——关掉开关时 online_api 变灰，正确语义是**开启**时才禁用 online_api、显示自建凭证输入。联动判定与 `disabledWhenSwitch` 的取值见 `baidu_netdisk_driver.dart` 的 spec 与 `test/baidu_refresh_switch_test.dart`。
- **落点**：`lib/services/cloud_drivers/baidu_netdisk_driver.dart`（BaiduClient + 驱动 + spec 自描述：能力遮罩 / 表单参数 / 构造，见 §6）、`cloud_drive_service.dart`（查表工厂 / 直链下载 / resolveStreamSource / 五个文件操作）、`accounts_screen.dart`（表单按 spec 通用渲染）、`accounts_service.dart`（驱动配置通道）、`webdav_service.dart`（`resolveStreamSource` 异步统一入口，四个调用点已切换）。

## 11. 已落地驱动实录：粘贴凭证直连盘批次（123_open / aliyundrive_open / 115open / terabox）

第二批驱动的共同形态：**粘贴式凭证 + 有公开直链 + 无重加密 + 单账号形态**（筛选标准与下沉判定见 [13 §1/§2](13-DRIVER-BATCH-PLAN.md)）。全部照 [12](12-DRIVER-PORTING-GUIDE.md) 的六步工序移植，`lib/` 只动驱动文件 + 注册表两个文件；每盘一个测试文件（出站请求全拦截，不真连网络）。**真机验收已按通过处理（用户确认 2026-09-25；123_open 打开目录曾报一次 invalid_grant，用户决定不排查，现象留档 99 §4.3.4）。**

| 驱动 | typeId | 能力位 | 登录 | 直链必需头 | 特殊机制 |
|---|---|---|---|---|---|
| 123_open | `123_open` | list/read/mkdir/move/delete（**无 copy**） | refresh_token + 在线续期 / 自建应用 | 无（公开 URL） | `code===401` 刷新重试一次；`update_at` 是 UTC+8 字符串 |
| aliyundrive_open | `aliyundrive_open` | list/read/mkdir/move/copy/delete | refresh_token + 在线续期轮询 / OAuth | 无（带签名 URL） | 6 个续期地址**去重**轮询；drive_id 按 drive_type 三级选盘 + `UserNotAllowedAccessDrive` 自愈 |
| 115open | `115open` | list/read/mkdir/move/copy/delete | refresh_token | **OpenList UA**（防盗链校验） | fid+UA 直链缓存 30 分钟（免费盘 downurl 有配额，406）；`state=false && code∈{99,401xx}` 判鉴权失败；`folder/get_info` 一次性解析、失败回退逐层 |
| terabox | `terabox` | list/read/mkdir/move/copy/delete | **cookie 粘贴**（过期重贴） | **UA** | 官方下载 API 直链 + UA；签名（sign1/sign3）纯 Dart 复现并有金标向量；`errno===9000` 地区不可用 |

批次共性与值得记的坑：

- **`api_url_address` 空串 = 回落默认续期地址**，不是「不走在线续期」（与百度同款语义；123_open 曾在这里栽过——守卫多判了一个 `isNotEmpty`，表单留空直接报 no valid authentication method）。
- **续期候选地址要去重**：aliyundrive_open 的表单默认值就是内置候选表的第一个地址，不去重会把同一地址打两遍（多耗一次请求，还让「全失败」用例的候选数对不上）。
- **path→id 缓存的键形必须一致**：123_open 曾出现写入带前导斜杠、查询不带，缓存形同虚设、每次 list 都逐层重解析。写操作后整表 clear（照 worker）。
- **`rename` 跨目录统一降级 move + rename**（接口契约，四盘一致）；115 的 copy 参数顺序是**目标 pid 在前**（上游如此，别按直觉接反）。
- **worker 底稿的三类偷懒都按本项目契约修正**：拿不到直链时抛真实原因（不返回无直链条目）；`get()` 的 try 作用域收窄到「找条目」，直链异常原样上抛；时间解析失败返回 null 而不是伪造 `now()`。
- **terabox 的签名**：上游 js sha1/aes 变体在纯 Dart 下可复现（`pointycastle` 原语 + 上游逐行对照），金标向量固化在测试里；若上游签名实现与真机不符，第一嫌疑是**明文收集时的符号溢出**（必须按无符号字节）。
- 文件名带数字开头的驱动（`115open`）在 Dart 里类名/文件名不能以数字开头，用 `Open115*` + `open115_driver.dart`，**typeId 仍存 `'115open'`**（存库值与上游目录名一致）。
