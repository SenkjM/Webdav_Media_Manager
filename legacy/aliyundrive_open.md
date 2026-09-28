# aliyundrive_open 驱动功能规格（已作废 · 重写参考）

> **状态声明**：本驱动的既有实现已按维护者决定整体作废、待重写。本文档是该实现
> 的功能性规格档案，记录完整功能面供重写时对照；不代表仍受支持的行为，也不构成
> 使用建议。全部事实来自本项目源码（截至本文写作时），行号引用对应下列文件。
>
> **来源与版权声明**：本文档为独立整理的功能性规格，仅描述本项目自有实现的
> 可观察行为与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker
> 的任何源码或其衍生内容**。

- 主文件：`lib/services/cloud_drivers/aliyundrive_open_driver.dart`（1090 行）
- 测试：`test/aliyundrive_open_driver_test.dart`（1236 行）
- 基类契约：`lib/services/cloud_driver.dart`
- 能力位定义：`lib/models/account_capabilities.dart`

---

## 1. 标识

| 项 | 值 |
|---|---|
| typeId | `aliyundrive_open`（`AliyundriveOpenSpec.typeId`） |
| displayName | `阿里云盘开放平台` |
| spec 类 | `AliyundriveOpenSpec extends CloudDriverSpec` |
| 驱动类 | `AliyundriveOpenDriver extends CloudDriver` |
| 协作类 | `AliyundriveOpenAddition`（配置）、`AliyundriveOpenClient`（API 客户端）、`AliyundriveOpenFile`（条目） |
| 注册 | `driver_registry.dart` 中按 typeId 注册；测试用 `cloudDriverSpec('aliyundrive_open')` 验证接入点 |

## 2. 能力位

`AliyundriveOpenSpec.capabilities`（`aliyundrive_open_driver.dart:1003-1008`）：

```
AccountCaps.list | AccountCaps.read | AccountCaps.mkdir
| AccountCaps.move | AccountCaps.copy | AccountCaps.delete
```

- 各位含义（`account_capabilities.dart:12-18`）：`list = 1<<0` 列目录、`read = 1<<1` 读取、`write = 1<<2` 写入、`mkdir = 1<<3` 创建文件夹（用户决定从「写入」拆出的独立位）、`move = 1<<4` 移动（含改名）、`copy = 1<<5`、`delete = 1<<6`。
- **`write` 一律不给**——上传已按设计文档砍掉（源码注释引用「99 §7.2.1」）。
- `runtimeCapabilities`：**未覆写**，走基类默认 `null`（用 spec 静态表）。本驱动不是包装驱动（`isWrapper` 未覆写，默认 `false`），无 `runtimeTypeLabel`。

## 3. 表单字段

`AliyundriveOpenSpec.form`（`aliyundrive_open_driver.dart:1017-1077`），顺序即界面顺序，测试锁定了完整 key 顺序：

| key | 控件类型 | label | required | obscure | 默认值 | 开关联动 |
|---|---|---|---|---|---|---|
| `refresh_token` | CloudDriverField | `refresh_token` | ✔ | ✔ | — | —（hint：必填；在线续期模式下需为通过 https://api.oplist.org/ 签发的有效 refresh_token；本地刷新模式下用自建阿里云盘开放平台应用授权获得的 refresh_token） |
| `drive_type` | CloudDriverSelectField | 网盘类型 | ✔ | — | `resource` | —（选项：`resource` 资源盘 / `default` 默认盘 / `backup` 备份盘；hint：对应同一账号下的不同 drive_id） |
| `api_url_address` | CloudDriverField | 在线续期地址 | — | — | `https://api.oplist.org/alicloud/renewapi` | `disabledWhenSwitch: local_refresh`（开启本地刷新后停用，disabledHint 提示关闭开关后可编辑） |
| `local_refresh` | CloudDriverSwitchField | 在本地处理令牌刷新 | — | — | `false` | —（subtitle：关闭＝用在线续期地址轮询；开启＝用自建阿里云应用直接刷新，需 Client ID / Secret） |
| `client_id` | CloudDriverField | Client ID | — | — | 空 | `visibleWhenSwitch: local_refresh` |
| `client_secret` | CloudDriverField | Client Secret | — | ✔ | 空 | `visibleWhenSwitch: local_refresh` |
| `remove_way` | CloudDriverSelectField | 删除方式 | — | — | `trash` | —（选项：`trash` 移入回收站 / `delete` 彻底删除；hint：移入回收站可在阿里云盘里找回） |
| `root_folder_id` | CloudDriverField | 根目录 ID | — | — | `root` | —（hint：不透明 id，默认 root 即网盘根目录；与账号的远程路径叠加生效） |

- **`access_token` 绝不进表单**：只作运行时缓存，经 `onTokenUpdate` 持久化（`aliyundrive_open_driver.dart:37-38`、测试 ：1111-1112）。
- **隐藏键 `drive_id`**：不在表单里；注释说明由「表单通用迁移」把它当解析结果快照写入配置，**非凭证、明文**，不进 `runtimeSecretKeys`（`aliyundrive_open_driver.dart:93-98`，引用「11 §6.2」）。
- **`secretFieldKeys`**：本 spec 未覆写，用基类推导 = 表单 obscure 字段 `{refresh_token, client_secret}` ∪ `runtimeSecretKeys`。
- **`runtimeSecretKeys`**：覆写为 `const {'access_token'}`（`aliyundrive_open_driver.dart:1013-1014`）。注释理由：`access_token` 经 `onTokenUpdate` 写回驱动配置、不在表单里，不声明就会明文进凭证库与备份；`refresh_token` 也会被轮换写回，但已在表单里 obscure，无需重复声明。
- 测试断言 `order_by` / `order_direction` / `chunk_size` 不在表单（`:1114-1116`）。

## 4. 认证与令牌生命周期

### 4.1 init()（`aliyundrive_open_driver.dart:747-753`）

1. `_client.login()`：缓存的 `access_token` 为空才刷新一次（有缓存则零网络请求）。
2. `_client.getDriveInfo()`：**强制真连** `/user/getDriveInfo`（内部先清空 `driveId` 再走 `resolveDriveId()`，因此即使配置里填了 drive_id 也能起到「令牌真的可用」的校验作用）。保存账号时的表单校验走的就是这条（默认 `CloudDriverSpec.verify` → `create().init()`）。

### 4.2 drive_id 解析（`resolveDriveId`，`aliyundrive_open_driver.dart:516-559`）

- 配置 `drive_id` 非空且 `forceResource == false` → 直接使用，不出网。
- 否则 `POST /user/getDriveInfo`，按 `drive_type`（空则回落 `resource`）取 `resource_drive_id` / `default_drive_id` / `backup_drive_id`；所选类型为空时按 **resource → default → backup** 顺序兜底。
- 三个 id 都空 → `CloudDriverException`「getDriveInfo 未返回任何 drive_id（resource / default / backup 都为空）：请确认账号已开通阿里云盘」。
- `forceResource: true` 时忽略配置 drive_id、按 `resource` 类型解析——供 `UserNotAllowedAccessDrive` 自愈用（见 §5/§7）。
- 各操作方法前置 `_requireDriveId()`：字段已解析直接用，否则触发解析。

### 4.3 令牌刷新（`refreshAccessToken`，`aliyundrive_open_driver.dart:268-310`）

- `refresh_token`（trim 后）为空 → 直接抛 `CloudDriverException`，**不发任何请求**。
- **`localRefresh` 关（默认）— 在线 API 中转分支**：候选地址逐个试（`_renewApiCandidates()`），第一个成功即用；全失败后落到直连 OAuth 兜底。
  - 候选顺序：自定义 `api_url_address`（非空时排最前）→ `builtinRenewApis` 6 个内置地址（`aliyundrive_open_driver.dart:188-195`）：`https://api.oplist.org/alicloud/renewapi`、`https://api.oplist.org/ali_open/token`、`https://api.oplist.org/aliyundrive/token`、`https://api.alist.nn.ci/alist/ali_open/token`、`https://api.alist.nn.ci/aliyundrive/token`、`https://api-sam.oplist.org/aliyundrive/token`。
  - 自定义地址与内置首地址相同时**去重**（表单默认值就是内置第一个；不去重会在全失败路径上把同一地址打两遍——注释指出回归用例「在线全失败 → 落到直连 OAuth」按内置表长度断言）。
  - 请求形态：`GET <url>?refresh_ui=<token>&refresh_token=<token>&server_use=true&driver_txt=alicloud_qr`（注释：`refresh_ui` 为续期服务侧定义的字段名，`refresh_ui` 与 `refresh_token` 两参数均传令牌值）。
  - 响应解析：顶层 `access_token` / `refresh_token` 与 `data` 包裹形态**两处都看**；`access_token` 缺失抛错由调用方继续轮询；续期服务不轮换 `refresh_token` 时保留原值。
- **`localRefresh` 开 — 直连 OAuth 分支**：只走 `POST https://openapi.aliyundrive.com/oauth/access_token`，body `{grant_type: 'refresh_token', refresh_token, client_id[, client_secret]}`；空 `client_secret` 不进 body；`client_id` 为空用内置 `defaultClientId = '25ab4837190e48718a28f80073574a4d'`。**在线续期地址完全不用**——失败也绝不回落在线分支（注释：与百度 `local_refresh` 语义一致，一旦打开就不使用 online api 逻辑，引用「12 §3.1」）。
- OAuth 域名注释（`:175-178`）：本实现使用 `openapi.aliyundrive.com`（`openapi.alipan.com` 为同一服务的另一域名，本实现未采用）。
- 两条路都失败 → 聚合 `CloudDriverException`：固定指引文案「请依次检查：1) refresh_token … 2) api_url_address … 3) client_id / client_secret …」+ 逐地址尝试记录（`url → 错误信息 | …`）。

### 4.4 onTokenUpdate 写回（`_applyTokens`，`aliyundrive_open_driver.dart:446-454`）

刷新成功后写 `{'access_token': <new>, 'refresh_token': <new>}` 两个键（在线续期与 OAuth 都会轮换 refresh_token，两个都要存）；同时同步内存字段 `accessToken`、`addition.accessToken`、`addition.refreshToken`。

### 4.5 Dio 注入

- 构造函数接受可选 `Dio`（测试注入自定义 `HttpClientAdapter`，生产留空走默认）。
- 默认 `BaseOptions`（`:226-235`）：`connectTimeout` 15s、`receiveTimeout` 60s、头 `Accept: application/json`、**`validateStatus: (_) => true`**——非 2xx 不是异常，回来看 body 拿服务端原文再包异常（注释引用「12 §2 第 2 步」）。

## 5. 接口实现逐条

所有 OpenAPI 请求统一走 `openApiRequest(path, body)`（`:460-508`）：`POST https://openapi.aliyundrive.com/adrive/v1.0<path>` + JSON body + 头 `Authorization: Bearer <access_token>`；`access_token` 为空先刷新；**401 时刷新令牌并重试一次**（`retry` 参数，只一次防死循环）；非 200 抛 `CloudDriverException('[AliyundriveOpen] API error [<status>] <path>: <原文截断300字>')`；200 但 body 非 JSON 对象同样抛错。网络层 `DioException` 翻译为 `[AliyundriveOpen] 网络请求失败 <path>：…`。

端点总览（全部 POST + JSON，基址 `https://openapi.aliyundrive.com/adrive/v1.0`）：

| 端点 | 用途 | 关键请求参数 |
|---|---|---|
| `/user/getDriveInfo` | 解析 drive_id / init 校验 | 空 body（仅 Bearer 头） |
| `/openFile/list` | 列目录 | `drive_id` / `parent_file_id` / `limit` / `order_by` / `order_direction` / `marker` |
| `/openFile/get` | 单条目元信息 | `drive_id` / `file_id` |
| `/openFile/getDownloadUrl` | 直链 | `drive_id` / `file_id` / `expire_sec=14400` |
| `/openFile/create` | mkdir | `drive_id` / `parent_file_id` / `name` / `type=folder` / `check_name_mode=refuse` |
| `/openFile/update` | rename | `drive_id` / `file_id` / `name` / `check_name_mode=refuse` |
| `/openFile/recyclebin` | 删除（trash） | `drive_id` / `file_id` |
| `/openFile/delete` | 删除（delete） | `drive_id` / `file_id` |
| `/openFile/move` | 移动 | `drive_id` / `file_id` / `to_parent_file_id` / `check_name_mode=refuse` |
| `/openFile/copy` | 复制 | `drive_id` / `file_id` / `to_parent_file_id` / `auto_rename=true` |

### 5.1 list（`AliyundriveOpenDriver.list`，`:756-760` + `client.listFiles` `:571-614`）

- 端点：`POST /openFile/list`。body：`drive_id`、`parent_file_id`、`limit=100`（`pageSize`）、`order_by='updated_at'`、`order_direction='DESC'`（表单不暴露排序，固定缺省值）、有游标时 `marker`。
- 分页：`next_marker` 非空就继续翻，**翻完为止**（do/while）；异常防御：对端一直回同一游标时 `guard > 1000` 强制退出。
- 响应映射：`resp['items']` 逐条 `AliyundriveOpenFile.fromMap`（`file_id`/`name`/`type`/`size`/`parent_file_id`/`created_at`/`updated_at`）；`type == 'folder'` 判目录，其余当文件；`modified` 取 `updated_at`，缺则回落 `created_at`，都缺为 `null`（不伪造时间；ISO8601 交给 `DateTime.tryParse` 后 `toLocal()`）。
- 驱动层先 `_resolveFileId(path)` 把绝对路径逐层解析成 file_id（见 §7 缓存与三段匹配），失败抛 `[AliyundriveOpen] Path '<段名>' not found`。
- **`UserNotAllowedAccessDrive` 自愈**：列表请求抛出的异常消息包含该字符串时，`resolveDriveId(forceResource: true)` 以 resource 类型重新解析 drive_id，用新 id **重试一次**；其他错误原样 rethrow。

### 5.2 get（`:767-812`）

- 空（根）路径 → 直接返回目录占位 `CloudFileItem(name: '/', isDir: true)`，不出网。
- `_resolveFileId` 后先 `POST /openFile/get`（body：`drive_id`、`file_id`）拿元信息；异常吞掉当 null（`getFile(fileId).catch(() => null)` 等价语义）。
- 元信息是目录 → 直接返回 `isDir: true` 条目（无 rawUrl）；是文件 → `POST /openFile/getDownloadUrl`（body：`drive_id`、`file_id`、`expire_sec=14400`），取 `url || download_url`，**空直链抛错**（有意差异，见 §7 第 1 条）；组装 `CloudFileItem` 带 `rawUrl` 与空 `rawHeaders`。
- 元信息拿不到 → 探测是否目录：列一次 `listFiles(fileId)`，能列就是目录（返回 `isDir: true` 占位）；也失败 → `CloudDriverException('[AliyundriveOpen] 无法获取条目或直链：<path>（file_id=<id>）')`。

### 5.3 mkdir（`:814-824`）

- 端点：`POST /openFile/create`。body：`drive_id`、`parent_file_id`（父路径解析出的 id）、`name`（`cloudBasename`）、`type: 'folder'`、`check_name_mode: 'refuse'`。
- 根目录名（空 basename）→ 抛「不能创建根目录」。成功后 `_pathCache.clear()`。

### 5.4 rename（`:828-845`）

- `src == dst` 直接返回。`_resolveEntry` 列父目录按名找条目（找不到抛 `'[AliyundriveOpen] '<名>' not found'`）。
- 同目录（`cloudDirname` 相等）→ `POST /openFile/update`，body：`drive_id`、`file_id`、`name`、`check_name_mode: 'refuse'`。
- 跨目录 → 降级「移动 + 改名」：先 `/openFile/move`（`to_parent_file_id`、`check_name_mode: 'refuse'`），新名非空且不同再 `/openFile/update`。
- 成功后 `_pathCache.clear()`。

### 5.5 remove（`:847-852` + `client.remove` `:667-677`）

- `remove_way` 为 `trash` 或空 → `POST /openFile/recyclebin`（移入回收站）；否则（`delete`）→ `POST /openFile/delete`（彻底删除）。body：`drive_id`、`file_id`。

### 5.6 move（`:854-863`）

- `POST /openFile/move`：`drive_id`、`file_id`、`to_parent_file_id`（目标目录 id）、`check_name_mode: 'refuse'`；`newName` 非空且与原名不同时追加一次 `/openFile/update` 改名。

### 5.7 copy（`:865-878`）

- `POST /openFile/copy`：`drive_id`、`file_id`、`to_parent_file_id`、`auto_rename: true`。
- copy 接口**没有 new_name 参数**：需要改名时复制完成后重新列目标目录、按原名 `_findInDir` 定位新 file_id 再 `/openFile/update`（注释：复制响应不回传新 file_id，本实现靠重列定位）。

### 5.8 错误翻译总结

- 本驱动**从不抛 `CloudDriverDataException`**——所有失败都翻成 `CloudDriverException`（内容不可用类异常是给解密层用的；本驱动无解密语义）。
- 错误信息一律带服务端原文（截断 300 字）与端点路径，满足「原样传递报错」的契约（注释引用「12 §2 第 2 步 / 11 §10」）。

## 6. 直链与请求头

- **rawUrl 来源**：`/openFile/getDownloadUrl` 响应的 `url`，缺则 `download_url`（`_firstNonEmpty` 兜底）；两者都空抛「未返回直链（url / download_url 都为空）」。
- **有效期**：请求参数 `expire_sec` 固定 `14400`（`linkExpireSec`，4 小时；注释：`expire_sec` 固定值）。直链本身是**带签名的公开 URL**。
- **缓存**：驱动层**不缓存直链**——每次 `get()` 现场请求；直链仅在 `CloudFileItem.rawUrl` 上随条目返回，有效期管理交给消费方。
- **rawHeaders**：恒为 `const <String, String>{}`——注释（`:796-797`）：「阿里云盘直链是带签名的公开 URL，无需必需请求头」。即无 UA / Referer / Cookie 要求。

## 7. 特殊机制与取舍（设计决策）

1. **直链失败抛真实原因（有意差异，唯一被注释明确标注的行为差异）**：备选方案是拿不到直链时静默返回 `raw_url: ""` 的无直链条目；本驱动让 `getDownloadUrl` 的异常自然抛出（`aliyundrive_open_driver.dart:22-25`、`:762-766`；理由：对齐 `CloudDriver.get` 的契约，引用「11 §10」）。目录探测分支（`getFile` 为空 → 列一次目录判断是不是文件夹）**保留**。
2. **字段/功能裁剪**（文件头注释 `:13-20`，引用「12 §2 字段裁剪规则 / 99 §7.2.1」）：
   - `putFile`（`/openFile/create` 传 content 的上传段）与秒传相关字段——上传整体砍掉；
   - `order_by` / `order_direction` 不进表单，列表固定 `updated_at` + `DESC`（服务端缺省值）；
   - `use_online_api` 开关被「在本地处理令牌刷新」（`local_refresh`）**反相取代**，默认走在线续期；
   - 在线续期请求的 `driver_txt` 固定为 `alicloud_qr`（常量；`drive_type` 不影响该值）；
   - `chunk_size` / `rapid_upload` / `internal_upload` / `livp_download_format` 等上传与代理下载字段全不实现。
3. **path→id 缓存**：OpenAPI 以 file_id 为寻址单位、本应用给驱动绝对路径，实例内维护 `_pathCache`（键为去首尾斜杠的规范路径，根为空串）。**任何写操作（mkdir/rename/remove/move/copy）成功后整表 clear**；缓存随驱动实例重建失效（注释引用「12 §3 注记 / 99 §4.6」）。`_resolveFileId` 逐层解析，**每一段单独吃缓存**；段名匹配三段式：原始段名 → `Uri.decodeComponent` 解码名 → 段名本身就是 file_id。
4. **`UserNotAllowedAccessDrive` 自愈**：配置的 drive_type 对应盘无权访问（如 backup 盘被拒）时，以 resource 类型强制重解析 drive_id 并重试一次（`:587-595`）。
5. **续期候选去重**：自定义地址与内置表首地址相同时去重，避免全失败路径重复请求同一地址（`:312-324` 注释）。
6. **在线续期双参数**：`refresh_ui` 与 `refresh_token` 都传令牌值（`:336` 注释）。
7. **分页死循环防御**：`next_marker` 持续相同/非空时 `guard > 1000` 退出（`:609-611`）。
8. **401 重试恰一次**：`openApiRequest` 的 `retry` 参数防死循环（`:484-487`）。
9. **错误原文截断**：`_clip` 300 字，避免整页 HTML 灌进异常信息（`:716-718`）。
10. **copy 无 new_name**：`/openFile/copy` 无改名参数，本实现 `auto_rename: true` 后重列目标目录按原名定位再改名（`:869-876` 注释）。
11. **不伪造时间**：`updated_at`/`created_at` 都缺失时 `modified` 为 null（`:162-164` 注释「按契约给 null，不伪造时间」）。
12. **rootFolderId 与远程路径叠加**：`root_folder_id` 是不透明 id（默认 `root`），账号的「远程路径」是虚拟前缀，由 `CloudDriveService.joinRemotePath` 拼在驱动路径前（`:100-105` 注释，引用「12 §6.3」）——重写时需保持两层路径模型的边界。
13. 本驱动未覆写 `dispose` / `openContent` / `openContentRange` / `openDownloadContent`：无本地流桥，下载全部走「直链 + 头」路径。

## 8. 行为契约（既有测试套件锁定，重写必须保持）

测试手法：自定义 `HttpClientAdapter`（`_RoutingAdapter`）拦截全部出站请求，按还原后的真实 URL 决定响应并记录 method/path/headers/body，不真连网络（`aliyundrive_open_driver_test.dart:17-22`）。

**令牌刷新 · 在线 API**（:154-297）：
1. 顶层 `access_token`/`refresh_token` 直接用；首个地址成功即停，不再轮询；请求参数四键齐（`refresh_ui`/`refresh_token`/`server_use=true`/`driver_txt=alicloud_qr`）。
2. 令牌裹在 `data` 里能取到；顶层缺 `access_token` 但 `data` 有也成功。
3. 续期服务不轮换 `refresh_token` 时保留原值。
4. 自定义地址失败 → 按顺序轮询内置地址并成功（命中顺序、次数、每次参数完整）。
5. `drive_type=backup` 不影响 `driver_txt`（固定 `alicloud_qr`）。
6. 在线全失败 → 落到直连 OAuth（6 个候选全试后第 7 次打 OAuth；带内置 `client_id`；空 `client_secret` 不进 body）。
7. 全部失败 → 聚合错误含 `All token refresh strategies failed` + `refresh_token`/`api_url_address`/`client_id` 指引词。
8. `refresh_token` 为空（含纯空白）→ 直接报错且零网络请求。

**令牌刷新 · 本地直连 OAuth**（:301-402）：
9. 打 `/oauth/access_token`，POST JSON，带 `grant_type`/`refresh_token`/`client_id`/`client_secret`。
10. 本地刷新不给 `api_url_address` 发请求（开关停用语义）。
11. 缺 `client_id` 用内置缺省值；本地刷新只试 OAuth 一次。
12. 本地刷新失败**绝不回落**在线续期地址（任何非 OAuth host 的请求都 fail）。
13. OAuth 报错原文被带进最终异常。

**drive_id 解析**（:406-482）：
14. 配置有 `drive_id` → 直接用，零网络请求。
15. 无值 → `POST /user/getDriveInfo`（带 `Bearer` 头），按 `drive_type` 选 resource/default/backup 对应 id。
16. 所选类型缺 id → 按 resource → default → backup 兜底；三个都空 → 可读错误。

**列表解析**（:486-588）：
17. `next_marker` 分页翻完；`type === 'folder'` 判目录；`size` 映射；请求 body 断言 `drive_id`/`limit=100`/`order_by='updated_at'`/`order_direction='DESC'`，首页不带 `marker`。
18. ISO8601 时间解析；缺 `updated_at` 回落 `created_at`；两者都缺 `modified` 为 null。
19. 列表报 `UserNotAllowedAccessDrive` → 以 resource 重解析 drive_id 再重试一次（自愈后必须用 resource id）。

**直链**（:592-691）：
20. `url` 落到 `rawUrl`；请求断言 `expire_sec=14400` 且不含 `driver_id` 键。
21. `url` 缺失回落 `download_url`。
22. 拿不到直链 → 抛 `CloudDriverException`（消息含「未返回直链」），不返回无直链条目。
23. 目录条目不带直链、不请求 getDownloadUrl，直接 `isDir: true` 返回。

**错误透传与 401 重试**（:695-792）：
24. 非 2xx 服务端原文（code + message）连同端点路径进 `CloudDriverException`。
25. 401 → 刷新令牌并重试一次，重试必须用刷新后的令牌。
26. 持续 401 → 只重试一次不死循环，原文抛出；只刷新一次令牌。
27. 令牌轮换经 `onTokenUpdate` 透出 `access_token` + `refresh_token` 两键。

**驱动层**（:796-1072）：
28. `init()` 有缓存令牌 → 只打 getDriveInfo；无缓存 → 先刷新再解析；令牌无效 → 抛真实原因（保存时据此拒绝落库）。
29. `list()` 逐层路径解析（父目录 file_id 列子目录）；路径缓存生效（第二次同路径不再列父目录，但列目录本身不可省）；路径不存在报可读错误（`'nope' not found`）。
30. `remove()`：`trash` → `/openFile/recyclebin`；`delete` → `/openFile/delete`。
31. `mkdir()` body 断言 `parent_file_id`/`name`/`type=folder`/`check_name_mode=refuse`。
32. `rename()` 同目录走 `/openFile/update`；跨目录降级 move + update。
33. `move()` 名字不变时不多发 rename。
34. `copy()` 带 `auto_rename: true`。
35. `get('/')` 返回目录占位且不出网。

**spec 自描述**（:1076-1235）：
36. typeId / displayName；能力位 = list|read|mkdir|move|copy|delete 且不含 write。
37. 表单 key 顺序完整断言；`access_token`、`order_by`、`order_direction`、`chunk_size` 不在表单。
38. `refresh_token` 必填且密文；`drive_type` 选项/默认/必填；`remove_way` 选项/默认。
39. 开关极性：`api_url_address.disabledWhenSwitch == 'local_refresh'`、client 字段 `visibleWhenSwitch == 'local_refresh'`、`client_secret.obscure`；`local_refresh` 默认 false。
40. 联动引用的开关必须真实存在于 form（防拼写错导致永远 false）。
41. 默认值：`api_url_address` = `https://api.oplist.org/alicloud/renewapi`、`root_folder_id` = `root`。
42. `create()` 把 config 还原成 `AliyundriveOpenAddition`（全字段）；`fromJson`/`toJson` 往返含缺键默认值。
43. 注册表 `cloudDriverSpec('aliyundrive_open')` 可查到。

## 9. 重写注意事项

1. **两条路径模型的边界**：OpenAPI 全用 file_id，本应用给绝对路径——重写必须保留 path→id 解析层，并决定缓存失效粒度（现实现是写后整表 clear，粗但安全；逐层缓存使 `/a/b/c` 与 `/a/b` 共享解析前缀）。
2. **三段名字匹配**（原始名 / URL 解码名 / file_id）：测试未直接覆盖但实现保留——重写若丢弃某一段，编码过的文件名路径会失配。
3. **直链失败必须抛真实原因**，不得返回无直链条目（契约 + 测试 22 锁定）。
4. **401 只重试一次**；**marker 分页加 guard**；**续期候选去重**——三处都是防死循环/重复请求的防御，注释各有回归理由。
5. **`local_refresh` 的极性**：开关打开即完全绕开在线续期分支（连兜底都不许），与百度驱动同语义；表单上 `api_url_address` 由 `disabledWhenSwitch` 停用。重写改动极性会同时破坏语义与测试 10/12。
6. **`access_token` 的敏感键治理**：不在表单、但必须进 `runtimeSecretKeys`，否则明文进凭证库与备份；`drive_id` 恰恰相反（明文快照，不进敏感键）。
7. **`validateStatus` 全放行**是错误透传设计的前提——非 2xx 必须读到 body 原文再包异常；重写若恢复 dio 默认抛错行为，会丢失原文并破坏测试 24。
8. **自愈重试只一层**：`UserNotAllowedAccessDrive` 仅在列表接口处理，重解析 + 重试各恰一次；其他接口遇同错误不触发自愈。
9. **copy 的改名定位**依赖「重列目标目录按原名找新条目」，目录内有同名旧文件时会定位错——服务端接口限制，重写时若无新 file_id 回传仍是坑。
10. **时间戳不做格式假设**：直接 `DateTime.tryParse`，解析失败返回 null；不要自造时区转换逻辑。
11. 扫码回调、上传、限流等功能本驱动均未实现；重写若要引入这些功能需另行设计与评审，本文档不覆盖。
