# 99 §4.9 补充 · 可快速实现驱动的筛选与任务规划（**已完成**）

本文件是 [99 §4.9](99-IN-PROGRESS.md) 全量评估的**执行侧收敛**：
按「快速可实现」标准筛出本轮批次，给出统计与任务划分。
工序照 [12-驱动移植指南](12-DRIVER-PORTING-GUIDE.md)；批次背景见 [99 §4.9](99-IN-PROGRESS.md)。

> **执行结果（本轮收口）**：T1–T4 全部落地并已合并进
> `feature/openlist-driver-port-batch2`——`123_open` / `aliyundrive_open` /
> `115open`（文件名 `open115_*`，typeId 仍 `115open`）/ `terabox`，
> 四盘能力位与下表一致；`flutter analyze` 干净、`flutter test` 513 过
> （含四个新驱动 ~180 用例）。真机验收仍待（按 §6）。

## 1. 筛选标准

「快速可实现」= 下面六条**全部**满足。任一条不满足即下沉到后续批次。

| # | 标准 | 为什么 |
|---|---|---|
| S1 | **粘贴式凭证**（refresh_token / cookie / authorization），无 OAuth 回调页 | 回调页要动平台侧与深链，工程量与驱动本体无关 |
| S2 | **有公开直链**，`rawUrl` 可直接给（非 MustProxy） | MustProxy 要接本地流桥，先例只有 crypt，成本高 |
| S3 | **无重加密 / 无额外密码学**，或只需 pointycastle 已有原语（MD5/SHA1/AES/RSA） | 逐字节对齐格式是 crypt 级别的独立工程 |
| S4 | **写方法真实现**（mkdir / rename / move / copy / remove）或明确只读 | 桩实现会让能力位说一套做一套 |
| S5 | **单账号形态**（无 personal/family/group 多形态分支） | 多形态等于 N 个驱动的实现量 |
| S6 | **上游 worker 底稿完整**（driver.ts 非空壳，无 `console.warn` 占位） | 空壳要从 Go 版重写，语义风险高 |

## 2. 逐盘核查结果（本轮查证，源码级）

### 2.1 P1 粘贴凭证直连盘

| 驱动 | S1 | S2 | S3 | S4 | S5 | S6 | 判定 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| **`123_open`** | ✅ | ✅ PreferProxy（有直链） | ✅ 无 crypto | ✅ 五项真实现 | ✅ | ✅ | **入选** |
| **`terabox`** | ✅ cookie | ✅ 有直链 | ⚠️ MD5 + js sha1/aes 变体 | ✅ 五项真实现（Go 已核） | ✅ | ✅ | **入选** |
| **`115open`** | ✅ | ✅ 有直链 | ✅ 无 crypto（sha1 仅上传用） | ✅ 五项真实现 | ✅ | ✅ | **入选** |
| **`aliyundrive_open`** | ✅ | ✅ 有直链 | ✅ 无 crypto | ✅ 五项真实现 | ✅ | ✅ | **入选** |
| **`quark_open`** | ✅ | ❌ **MustProxy** | ✅ | ⚠️ copy 桩 | ✅ | ✅ | 下沉（要流桥） |
| **`139`** | ✅ | ✅ 有直链 | ✅ 无 crypto | ⚠️ worker move/copy 是 `console.warn` 桩 | ❌ **5 种账号形态**（personal_new/personal/family/group/share），util.go 66KB | ⚠️ | 下沉（多形态） |
| **`quark`**(cookie) | ✅ cookie | ✅ | ⚠️ | ✅ | ✅ | ✅ | 次批候选 |

**统计**：P1 共 7 盘 → **本轮入选 4 盘**，下沉 3 盘。

### 2.2 下沉原因（不是「不做」，是「不快速」）

- **`quark_open`**：MustProxy（`proxy.ts` 强制代理表 + Go `meta.go` `OnlyProxy`）。
  要接本地流桥才能播放。**流桥先例只有 crypt**——那是有状态的四态 `shape` 判定。
  下沉到「流桥复用」专题批（见 §5）。
- **`139`**：① worker 的 `move` / `copy` 直接 `console.warn` 不做事（假实现）；
  ② Go 版真实现但按 5 种账号形态分叉，`util.go` 66KB；
  ③ 带字符集标记（[99 §4.3](99-IN-PROGRESS.md) 早已提示「真机要先验编码」）。
  单盘工作量 ≈ 前四盘之和。下沉到独立批，且**先要真机验编码**。
- **`quark`**(cookie)：与 `quark_open` 同源但走 cookie + 另一套 API；等 `quark_open` 的流桥形态定了再一起做更省。

## 3. 本轮任务规划（4 盘并行）

| 任务 | 驱动 | 分支 | 形态 | 预期落点 |
|---|---|---|---|---|
| **T1** | `123_open` | `driver/123-open` | refresh_token + client_id/secret + 在线续期 | 最简，无 crypto，无分叉 |
| **T2** | `aliyundrive_open` | `driver/aliyundrive-open` | 在线 API 多端点轮询 + drive_id 解析 | 中等，有 drive_id 解析逻辑 |
| **T3** | `115open` | `driver/115open` | refresh_token + 直链带 UA + 链接缓存 | 中等，有 fid 路径解析与 30 分钟链接缓存 |
| **T4** | `terabox` | `driver/terabox` | cookie 粘贴 + UA 校验直链 | 中等，有 MD5 签名 |

**共同约定**（每盘都要遵守，来自 [12](12-DRIVER-PORTING-GUIDE.md)）：

1. **只动两个文件**：新增 `lib/services/cloud_drivers/<name>_driver.dart` +
   `driver_registry.dart` 加一行 + 新增 `test/<name>_driver_test.dart`。
2. **不移植 put / 上传**（99 §4.2.1）。上游的 OSS 直传、分片上传代码全部砍掉。
3. **不移植 `order_by` / `order_direction` / `only_list_video_file`**（客户端自己排序）。
4. **`api_url_address` / client 凭证 / access_token 缓存**照百度模式：
   `onTokenUpdate` 持久化、`access_token` 不进表单。
5. 能力位按各盘 `mkdir` 实情给（见 §4）；`write` 一律不给。
6. 驱动构造**必须可注入 Dio**（测试要拦出站请求，[12 §8.1](12-DRIVER-PORTING-GUIDE.md)）。
7. 错误原文必须透传成 `CloudDriverException`。

## 4. 各盘能力位与字段清单（待用户确认）

| 驱动 | 能力位 | 表单字段（裁剪后） |
|---|---|---|
| `123_open` | list/read/mkdir/move/copy/delete | refresh_token(必填,obscure)、在线续期地址(默认 `https://api.oplist.org/123cloud/renewapi`)、本地刷新开关、client_id、client_secret、root_folder_id |
| `aliyundrive_open` | list/read/mkdir/move/copy/delete | refresh_token(必填,obscure)、drive_type(下拉 default/resource/backup)、在线续期地址(默认 `https://api.oplist.org/alicloud/renewapi`)、本地刷新开关、client_id、client_secret、remove_way(下拉 trash/delete) |
| `115open` | list/read/mkdir/move/copy/delete | refresh_token(必填,obscure)、access_token 缓存(不进表单)、root_id、page_size(默认 200)、limit_rate |
| `terabox` | list/read/mkdir/move/copy/delete | cookie(必填,obscure)、root_folder_path |

> `copy` 支持核查（本轮源码级）：`123_open` worker `copy()` 抛「not supported」→
> **降级**：能力位**不给 copy**。`aliyundrive_open` / `115open` / `terabox` 三项真实现 copy。
> 这条要在实现时按各盘实际再核一次（[99 §4.3.2](99-IN-PROGRESS.md) 的登记原则）。

## 5. 后续批次（本轮不做，记录判定依据）

| 批次 | 驱动 | 卡点 |
|---|---|---|
| 流桥复用批 | `quark_open`、`quark`、`google_drive`、`google_photo`、`weiyun` | MustProxy；需把 crypt 的流桥抽成**通用 MustProxy 流桥**（一次投入、多盘复用）——这是解开整个 P1/P2 剩余项与 P3 部分项的关键 |
| 多形态批 | `139` | 5 种账号形态 + 编码验证 |
| 只读家族批（P2） | `openlist_share`、`github_releases`、`autoindex`… | 能力遮罩=只读；先接 API 形状差异最大的两个验证机制 |
| OAuth 回调批（P3） | `onedrive`、`dropbox`、`pikachu`… | 要 client_id/secret + 回调或设备码 |

**结论**：本轮 4 盘把「粘贴凭证 + 有直链 + 无 crypto + 单形态」这条最短路走完；
下一批的公共投入应当是**通用 MustProxy 流桥**，而不是继续堆单盘。

## 6. 验收

- 自动化：**已完成**——`flutter analyze` 无 issue + `flutter test` 全过
  （feature 分支 513 用例，其中四个新驱动测试见下）。
- 解耦回归：**已验证**——`git diff --stat main..HEAD -- lib/ test/`
  只有 4 个驱动文件 + 注册表（+8 行）+ 4 个测试文件，公共层零改动
  （[12 §1.1](12-DRIVER-PORTING-GUIDE.md) 的检查方法）。
- 真机：按 [12 §9](12-DRIVER-PORTING-GUIDE.md) 清单逐盘过；
  **A 类（有测试条件）先验，其余靠发布后用户反馈**（[99 §4.3](99-IN-PROGRESS.md) 的先例）。

### 6.1 各盘真机验收要点（合并后新增）

| 驱动 | 重点（除 [12 §9](12-DRIVER-PORTING-GUIDE.md) 通用清单外） |
|---|---|
| `123_open` | refresh_token 在线续期轮换后重进账号不失效；`root_folder_id` 与远程路径叠加语义 |
| `aliyundrive_open` | `drive_type` 三种取值的列表与直链；`UserNotAllowedAccessDrive` 自愈（换盘类型提示） |
| `115open` | 直链 UA 校验下的下载/流式；**链接缓存**是否显著减少 downurl 调用（免费号 406 配额）；`root_id` 挂载 |
| `terabox` | Cookie 过期的报错可读性；直链两种响应形态（`dlink` / `info`）；非国内区域的 9000 错误 |

### 6.2 过程记录（并行移植的教训，已固化进 [12 §11](12-DRIVER-PORTING-GUIDE.md)）

- 首轮四个子代理**共享同一工作目录**，互相切分支、注册表被覆盖、`git add -A`
  误暂存他人半成品——之后改为**每盘独立 `git worktree`**（`pub get` 单独跑，
  不用 junction 共享 `.dart_tool`），冲突只余注册表一处且逐个合并即自动解决。
- 测试侧两类系统性编译错误（sealed 基类取 `key`、构造参数标签），同一批出现两次；
  已按 `_formKey` 模式统一修法。
- 驱动实机的三处真实缺陷在跑测试时暴露并修复：
  `123_open` 的 path→id 缓存键不同形（缓存永失效）、
  `123_open` 续期地址空串不回落默认值、
  `aliyundrive_open` 在线续期候选不去重（custom 与 builtin 首项重复）。
