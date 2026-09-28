# 123_open 驱动功能规格（已作废 · 重写参考）

> **状态声明**：本驱动的既有实现已按维护者决定整体作废、待重写。本文档是该
> 实现的功能性规格档案，基于本项目源码（`lib/services/cloud_drivers/_123_open_driver.dart`
> 848 行 + `test/_123_open_driver_test.dart` 953 行）记录完整功能面供重写对照；
> 不代表仍受支持的行为，也不构成使用建议。
>
> **来源与版权声明**：本文档为独立整理的功能性规格，仅描述本项目自有实现的
> 可观察行为与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker
> 的任何源码或其衍生内容**。

全部事实来自本项目源码，主要出处：

- 主实现：`lib/services/cloud_drivers/_123_open_driver.dart`（848 行，下文记作 `driver.dart`）
- 测试：`test/_123_open_driver_test.dart`（953 行，下文记作 `test.dart`）
- 基类契约：`lib/services/cloud_driver.dart`（下文记作 `base.dart`）
- 能力位定义：`lib/models/account_capabilities.dart`（下文记作 `caps.dart`）

## 1. 标识

| 项 | 值 |
|---|---|
| typeId（provider_type 存库值） | `123_open` |
| displayName | `123 云盘开放平台` |
| Spec 类 | `Driver123OpenSpec`（extends `CloudDriverSpec`） |
| 驱动类 | `Driver123Open`（extends `CloudDriver`） |
| 配置类 | `Driver123OpenAddition` |
| API 客户端 | `Driver123OpenClient` |
| 文件路径 | `lib/services/cloud_drivers/_123_open_driver.dart` |
| 测试路径 | `test/_123_open_driver_test.dart` |
| 注册位置 | `lib/services/cloud_drivers/driver_registry.dart:22`（`Driver123OpenSpec()`） |

- 文件名带下划线前缀 `_123_open_driver.dart` 只是 Dart import 标识符不能以
  数字开头的限制，typeId 仍是 `123_open`（文件头注释，:7-8）。
- 非包装驱动：`isWrapper` 用默认 false；不覆写 `runtimeTypeLabel`；
  `create()` 不使用 `CloudDriverEnv` / `CloudSource`。

## 2. 能力位

```dart
int get capabilities => AccountCaps.list | AccountCaps.read |
    AccountCaps.mkdir | AccountCaps.move | AccountCaps.delete;
```

- 位定义（`lib/models/account_capabilities.dart:12-18`）：`list = 1 << 0`、
  `read = 1 << 1`、`write = 1 << 2`、`mkdir = 1 << 3`、`move = 1 << 4`、
  `copy = 1 << 5`、`delete = 1 << 6`。本驱动合计 91（0x5B，推导值）。
- **不给 `copy`**：`copy()` 直接抛 `[123Open] copy not supported`；可用的
  复制实现需要依赖上传通道（上传已整体砍掉，99 §7.2.1），因此能力位不声明
  （spec 注释，:787-788）。
- **不给 `write`**：write 一律不给（99 §7.2.1，spec 注释）。
- `runtimeCapabilities` 未覆写（基类默认 null → 用 spec 静态表）；
  `dispose`、`openContent` / `openDownloadContent` / `openContentRange`
  均未覆写（MustProxy 不适用：文件总能拿到直链）。

## 3. 表单字段

`Driver123OpenSpec.form` 共 6 项，按声明顺序渲染：

| # | key | 类型 | label | required | obscure | 默认值 | 开关联动 |
|---|-----|------|-------|:---:|:---:|--------|----------|
| 1 | `refresh_token` | CloudDriverField | `refresh_token` | 是 | 是 | `''` | 无；hint「必填；在线续期模式下需为通过 https://api.oplist.org/ 签发的有效 refresh_token；本地刷新模式下用自建 123 应用授权获得的 refresh_token」 |
| 2 | `api_url_address` | CloudDriverField | 在线续期地址 | 否 | 否 | `https://api.oplist.org/123cloud/renewapi` | `disabledWhenSwitch: 'local_refresh'`（开了就停用）；disabledHint「已开启本地刷新（在线续期停用），关闭开关后可编辑」 |
| 3 | `local_refresh` | CloudDriverSwitchField | 在本地处理令牌刷新 | — | — | `false` | 控制字段 4/5 的可见性与字段 2 的可用性；subtitle「关闭＝在线续期；开启＝用自建 123 应用刷新（需 Client ID / Secret），在线续期停用」 |
| 4 | `client_id` | CloudDriverField | Client ID | 否 | 否 | `''` | `visibleWhenSwitch: 'local_refresh'` |
| 5 | `client_secret` | CloudDriverField | Client Secret | 否 | 是 | `''` | `visibleWhenSwitch: 'local_refresh'` |
| 6 | `root_folder_id` | CloudDriverField | 根目录 ID | 否 | 否 | `0` | 无；hint「不透明 id，默认 0（网盘根目录）；与账号的远程路径叠加生效」 |

- `access_token` **不进表单**（缓存专用，:790 注释「不在表单里——凭证加密范围
  靠 runtimeSecretKeys 补全（11 §6）」）。
- `runtimeSecretKeys => const {'access_token'}`（:781）。
- `secretFieldKeys` = 表单 obscure 字段 ∪ runtimeSecretKeys =
  `{refresh_token, client_secret, access_token}`（基类默认实现推导）。

## 4. 认证与令牌生命周期

**init()**（`Driver123Open.init`，:537-542）：`_client.login()` —— `accessToken`
为空就先 `getAccessToken()` 换一次——随后真连 `GET /api/v1/user/info`
校验令牌可用（与百度驱动 uinfo 校验同等的语义，12 §2 第 3 步）。
表单保存前的 `verify()` 走基类默认：`create().init()`。

**getAccessToken() 两条互斥分支**（:189-219）：

1. **在线续期**（`!localRefresh && refreshToken.isNotEmpty`）：
   `GET {api_url_address|defaultRenewApi}?refresh_ui=<rt>&server_use=true&driver_txt=123cloud_oa`
   → JSON `{access_token, refresh_token}`，**两个都要存**（在线续期会轮换
   refresh_token）。响应按 `ResponseType.plain` 收原文再手动 jsonDecode；
   失败时错误原文按 `error_description` → `text` → `message` → `error`
   顺序取，抛 `[123Open] {err}`；都没有则抛
   `在线 API 刷新失败 (HTTP {status})：…请确认 refresh_token 是通过
   https://api.oplist.org/ 获取的有效令牌。`。
2. **client 凭证**（代码条件为 `clientId.isNotEmpty && clientSecret.isNotEmpty`，
   注意：**未**在代码里再判 `localRefresh`，doc 注释却称这是 localRefresh 分支
   ——实际效果是「refresh_token 为空时即使开关关闭也会走此分支」）：
   `POST /api/v1/access_token`，body `{clientID, clientSecret}` →
   `data.access_token`（**不轮换 refresh_token**）。走**裸 `_send()`**，
   不经 401 重试的 `request()`——否则「401 → 刷新 → 打令牌端点 → 又 401」
   无限递归（注释，:268-270）。

- 两条路互斥短路：在线续期失败直接抛，绝不拿 client 凭证兜底（:187-188）。
- 都不满足时：`refresh_token` trim 后为空 → 抛可读错误
  `123 云盘缺少 refresh_token：请填写 refresh_token`（后端兜底，不出网；
  现行错误串末尾另附令牌获取指引文字，重写时替换为自有文档指引）；否则抛
  `[123Open] no valid authentication method (access_token / refresh_token / client_id+client_secret)`。

**_applyTokens(access, refresh)**（:293-301）：写 client.accessToken、
addition.accessToken、addition.refreshToken，并 `onTokenUpdate` 发出
`{'access_token': …, 'refresh_token': …}` patch（兼容层负责持久化；
secretFieldKeys 保证其加密入库）。

**request() 带钱包语义**（:307-341）：`accessToken` 为空先换；`code === 401`
（`codeUnauthorized`）→ `getAccessToken()` 后**重试一次**（防死循环）；
`code !== 0` → `[123Open] {message | 'code $code'}`。
业务错误（CloudDriverException）不重试直接 rethrow；其他异常包成
`123 云盘请求失败：{pathname ?? path}`（cause 挂底层异常）。

**Dio 注入方式**：`Driver123OpenClient` / `Driver123Open` 构造器都收可选
`Dio? dio`（测试注入用）；`spec.create()` 不传 → 现场新建
`Dio(BaseOptions(connectTimeout: 15s, receiveTimeout: 60s,
headers: {'Accept': 'application/json'}, validateStatus: (_) => true))`
——非 2xx 也回来走 code / 原文解析（:160-162 注释）。无拦截器；认证头
在 `_send()` 每次请求时设置：`Authorization: Bearer {accessToken}` +
`platform: open_platform`。

## 5. 接口实现逐条

所有 API 请求公共形状：基址 `https://open-api.123pan.com`；JSON 包裹
`{code, message, data}`；`_send()` 解析失败抛
`[123Open] invalid JSON response, status {code}`，DioException 抛
`[123Open] 网络请求失败：{message}`。**本驱动从不抛
`CloudDriverDataException`**（无解密层，全部失败都是 `CloudDriverException`）。

### list(path)
- `_resolveDirId(path)` 解析目录 id → `getFiles(id)`。
- 端点：`GET /api/v2/file/list`（pathname `file/list`），query：
  `parentFileId={id}`、`limit=100`（固定值 `pageSize`）、
  `lastFileId={游标}`（首页 0）、`trashed=false`、`searchMode=''`、`searchData=''`。
- 分页：响应 `data.last_file_id`；`-1`（`lastPageSentinel`）为末页哨兵；
  guard 计数 > 1000 直接 break（防御对端一直回同一游标，:432-434）。
- 过滤：条目 `trashed !== 0` 丢弃（远端 trashed 参数失效，只能遍历过滤）。
- 条目解析 `Driver123OpenFile.fromMap`：`fileId` / `filename` / `size` /
  `type`（1=目录，2=文件）/ `update_at`（UTC+8 墙钟串，无时区）。
- 映射到 `CloudFileItem`：`name=filename`、`isDir=type===1`、
  `size`、`modified=parse123OpenTime(update_at)`；**不带 rawUrl**。
- 路径解析 `_resolveDirId`（:667-695）：逐层列目录、按 `isDir && filename`
  匹配段名；未命中抛 `[123Open] Directory '{seg}' not found`。`_pathCache`
  键是「去掉前导斜杠的规范路径」（根=空串），逐层前缀都入缓存；
  **写操作后整表 `_pathCache.clear()`**；缓存随驱动实例重建失效（99 §4.6）。

### get(path)
- 根路径（clean 为空）→ 占位 `CloudFileItem(name: '/', isDir: true)`。
- 先列父目录按 `filename == basename` 找条目；**此段 try/catch**——父目录
  解析 / 列表失败 → file=null 落到目录探测分支；但**直链失败在 try 之外**，
  必须抛真实原因（:566-567 注释）。
- 命中文件 → `getDownloadUrl(fileId)`：`GET /api/v1/file/download_info?fileId={id}`
  → `data.download_url`；null/空抛 `[123Open] empty download url`。
  返回条目带 `rawUrl` + `rawHeaders: const {}`。
- 命中目录 → 直接返回条目（无 rawUrl，不打 download_info）。
- 未命中 → 探测 `_resolveDirId(clean)` 是否目录；失败抛
  `123 云盘文件不存在：{rawName}`。

### mkdir(path)
- `cloudBasename` 为空 → `[123Open] 不能创建根目录`。
- 解析父目录 id → `POST /upload/v1/file/mkdir`，body `{parentID, name}`。
- 成功后 `_pathCache.clear()`。

### rename(path, newPath)
- `src == dst` → 直接返回（no-op）。
- 同目录 → `PUT /api/v1/file/name`，body `{fileId, fileName}`（HTTP 动词 PUT）。
- 跨目录 → 降级「先 move 到目标父目录、再（名字变化时）rename」
  （move + 条件 rename 组合，:622 注释）。
- 成功后 `_pathCache.clear()`。

### remove(path)
- `_resolveEntry` 找条目 → `POST /api/v1/file/trash`，body
  `{fileIDs: [fileId]}`——**实为移入回收站**（:487 注释）。
- 成功后 `_pathCache.clear()`。

### move(srcPath, dstDir, newName)
- `POST /api/v1/file/move`，body `{fileIDs: [fileId], toParentFileID: {dstDir id}}`。
- `newName` 非空且 ≠ 当前 `filename` 时补一次 rename（同名移动不发 rename）。
- 成功后 `_pathCache.clear()`。

### copy(srcPath, dstDir, newName)
- **同步** `throw const CloudDriverException('[123Open] copy not supported')`
  （`=> throw` 表达式体，不是返回失败 Future）；能力位不给 copy，正常
  不会被调用（:660-664）。

**辅助**：`_resolveEntry`（:698-710）列父目录按 filename 精确匹配，未命中抛
`[123Open] '{name}' not found`；对根抛
`[123Open] 不能对根目录执行该操作`。`_clean` 折叠重复斜杠、去首尾斜杠（根→空串）。
`_rootId()`：`root_folder_id.trim()`，空串回落 `'0'`（`defaultRoot`）。

**时间解析 `parse123OpenTime`**（:736-767）：格式
`"2006-01-02 15:04:05"`，**UTC+8 墙钟、无时区信息**——正则匹配后
`DateTime.utc(...).subtract(8h).toLocal()`；带 `T` 无时区同样按 UTC+8；
带显式偏移（`Z` / `±hh:mm`）交给 `DateTime.parse`；非已知格式兜底
`DateTime.tryParse(v)?.toLocal()`；解析失败返回 **null**（宁可 null
不伪造时间，:735 注释）。

## 6. 直链与请求头

- **rawUrl 来源**：仅 `get()` 文件命中后调
  `GET /api/v1/file/download_info?fileId={id}` 取 `data.download_url`。
  测试样例形态：`https://cdn.123pan.com/dl/a.mp3?auth=1`（带鉴权查询参数的
  CDN URL——仅测试夹具，源码未记录真实有效期）。
- **缓存**：无。每次 `get()` 都重新打 download_info；驱动不缓存直链、
  也没有有效期管理逻辑（源码无此内容）。
- **rawHeaders**：`const {}`——123 直链是公开 URL，无必需请求头
  （:593 注释）。`Authorization: Bearer …` /
  `platform: open_platform` 只用于 API 请求本身，不进 rawHeaders。
- 直链签名（`DirectLink`）机制不实现——本应用只走 `download_info`
  （文件头注释，:22）。

## 7. 特殊机制与取舍（设计决策）

以下各条均为源码注释明确记录的内容（出处附后）：

1. **get() 拿不到直链抛真实原因**（有意差异，:15-18 / :553-555）：相对
   「把 `raw_url_error` 记在条目上、返回无直链条目」的备选方案，本实现按
   `CloudDriver.get` 契约（11 §10）直说，因为客户端下游必然失败。
2. **不给 copy**（:10-13 / :660-664 / :787-788）：`copy()` 抛
   not supported；可用的复制实现依赖上传通道（上传已砍，99 §7.2.1）。
3. **不实现 `order_by` / `order_direction`**（:20-21）：客户端自己排序。
4. **「在本地处理令牌刷新」反相开关**（:21-22 / :79-82）：`local_refresh`
   默认 false＝走在线续期；开启＝用自建 123 应用凭证刷新、在线续期停用。
   开关在表单联动（字段 2 停用 / 字段 4、5 显隐）与 `getAccessToken`
   分支两处一致生效。
5. **直链签名（`DirectLink`）机制不实现**（:22）：只走 `download_info`。
6. **`root_folder_id` 与账号「远程路径」叠加**（:86-88）：远程路径是虚拟
   前缀，由 `CloudDriveService.joinRemotePath` 拼在驱动路径前（12 §6.3）；
   root_folder_id 本身是不透明 id，默认 `0`。
7. **在线续期轮换两个令牌**（:168 / :180-186）：access_token 与 refresh_token
   都要经 onTokenUpdate 持久化，否则下次续期断链。
8. **令牌端点裸请求防递归**（:268-270）：`_renewByClientCredentials` 直接
   `_send`，不套 401 重试的 `request()`。
9. **`apiUrlAddress` 空串 = 默认公共服务地址**（:193-197，留档 bug 记录）：
   空串**不是**「不走在线续期」——早先多加了 `isNotEmpty` 守卫，导致
   「表单留空 → 两条路都不走 → 报 no valid authentication method」，
   与百度驱动同款行为不一致（百度空串回落）；已改为回落
   `defaultRenewApi`。
10. **`_pathCache` 缓存键形 bug**（:689-692，留档记录）：缓存键必须与查表键
    同形（`_clean` 后无前导斜杠）；早先写成 `/${...}` 带前导斜杠导致
    **永远查不中**，缓存形同虚设、每次 list 都逐层重新解析，被
    「写操作后清缓存」的测试用例逮到。
11. **时间解析失败给 null 而非 now()**（:734-735）：相对「回落 `now()`」的
    备选方案，本实现宁可 null，不伪造时间。
12. **分页防御**（:432-434）：guard > 1000 break，防对端异常响应回同一游标
    死循环。
13. **trashed 客户端过滤**（:402-403）：远端 trashed 参数失效，只能遍历过滤。

## 8. 行为契约（既有测试套件锁定，重写必须保持）

测试基建：自定义 dio `HttpClientAdapter`（`_RoutingAdapter`）拦截全部出站
请求，按 host 分流——`api.oplist.org` → 本地续期 HttpServer，
`open-api.123pan.com` → 本地 API HttpServer，其余 404；记录
method / url / headers / body 供断言。`envelope(data)` = `{code:0, message:'ok', data}`；
`fileMap(id, name, {type, size, updateAt})` 造条目。

重写必须保持的契约（按 group；测试文件共 **10 个 group、36 个 test**）：

- **spec 与能力遮罩**：typeId `123_open`、displayName、注册表
  `cloudDriverSpec('123_open')` 返回 `Driver123OpenSpec`；能力位含
  list/read/mkdir/move/delete、不含 copy/write；表单恰好六项且顺序为
  `refresh_token, api_url_address, local_refresh, client_id, client_secret,
  root_folder_id`；`refresh_token` required+obscure；
  `api_url_address` defaultValue = `https://api.oplist.org/123cloud/renewapi`、
  `disabledWhenSwitch: 'local_refresh'` 且 **`enabledWhenSwitch` 为 null**
  （「开了就停用」，99 §7.3.1）、disabledHint 非空；`client_id` /
  `client_secret` `visibleWhenSwitch: 'local_refresh'`、secret obscure；
  `root_folder_id` defaultValue `'0'`；`access_token` 不在表单里；
  开关默认 false 且 `spec.switchValue('local_refresh', {})` 为 false。
- **在线续期**：GET 打到续期地址，query 带
  `refresh_ui` / `server_use=true` / `driver_txt=123cloud_oa` 且**不带**
  client 凭证；不打到 123 开放平台；两个令牌都写回（client + addition +
  onTokenUpdate patch 含两个键）；`apiUrlAddress` 空串回落默认公共服务；
  续期服务 400 + `{error_description}` 时错误原文透传且**绝不再走 client
  凭证分支**（apiPaths 为空）。
- **本地 client 凭证**：`POST /api/v1/access_token`，body
  `{clientID, clientSecret}`，头 `platform: open_platform`；不打续期地址；
  `refresh_token` 不轮换；缺 ClientID/Secret → 报错且**不出网**；
  令牌端点自身 401 → 直接抛错、令牌端点只被调 **1 次**（不能递归重试）。
- **缺必填 refresh_token**：默认配置报含 `refresh_token` 的可读错误且不出网
  （`init()` 同样）；带缓存 `access_token` 时不刷新，init 直接打
  `/api/v1/user/info`，头 `Authorization: Bearer cached` +
  `platform: open_platform`。
- **列表解析**：两页翻完（`lastFileId` 0 → 42 → -1，`limit=100`、
  `trashed=false`、`parentFileId`）；请求头 authorization/platform；
  `type===1` 判目录、size 映射；`update_at` `2024-01-02 03:04:05` →
  UTC `2024-01-01 19:04:05`（减 8 小时）；`trashed !== 0` 过滤；
  路径逐层解析（根 `parentFileId=0` → `sub` id 77）；`root_folder_id='999'`
  作为起点 parentFileId。
- **直链 get**：`download_url` 落 `rawUrl` 且 size/modified 带上、
  `fileId` 查询参数、authorization 头；`code=403 该文件无下载权限` →
  **抛含原文的异常，不返回无直链条目**；目录 get 不打 download_info、
  `rawUrl` 为 null。
- **错误原文透传**：`code=1001 参数错误：parentFileId 非法` 在 list 抛出；
  mkdir / move / rename / remove 的 `code=500 服务端拒绝` 同样透传。
- **code === 401**：刷新一次 + 重试一次后成功（重试带新令牌
  `Bearer online-access`）；重试仍 401 → 只刷新一次、只重试一次
  （listCalls=2、renewRefreshes 长度 1）。
- **写操作请求形状**：mkdir `POST /upload/v1/file/mkdir` body
  `{parentID:'3', name}`；rename 同目录 `PUT /api/v1/file/name` body
  `{fileId:7, fileName:'new.mp3'}`；rename 跨目录 = move
  `{fileIDs:[7], toParentFileID:'9'}` + 补 rename（`fileName='new.mp3'`）；
  move `{fileIDs:[7], toParentFileID:'9'}` 且**同名移动不发 rename**；
  remove `POST /api/v1/file/trash` body `{fileIDs:[7]}`；copy **同步抛**
  `copy not supported`（用 `expect(() => …)` 而非 expectLater——同步异常会
  逃逸，:871-873 注释）且不出网。
- **写操作后清缓存**（group「写操作请求形状」内的独立用例，非独立 group）：
  数 `parentFileId=0` 的列目录请求——首次解析 /sub 计 1 次；第二次 list 缓存
  命中不再解析；mkdir 后缓存清空、重新解析。
- **时间解析**：空格形式减 8 小时；跨日边界
  `2024-03-01 00:00:00` → UTC `2024-02-29 16:00:00`；`T` 无时区形式按
  UTC+8；显式时区 `Z` / `+08:00` 按偏移；null / 空串 / 非法串 → null。

## 9. 重写注意事项（从实现中提炼的陷阱）

从实现提炼的陷阱（源码可佐证）：

1. **时间串是 UTC+8 墙钟**：`update_at` 无时区信息，必须显式减 8 小时，
   不能当本地时间解析；跨日边界是回归点。
2. **path→id 缓存键形**：键 = 去前导斜杠的规范路径、根为空串；写操作后
   必须整表清空。键形不一致时缓存静默失效（历史 bug，见 §7.10）。
3. **`api_url_address` 空串语义**：回落默认公共服务，不是「跳过在线续期」
   （历史 bug，见 §7.9）。
4. **令牌端点防递归**：刷新端点必须走裸请求，绝不能套「401 → 刷新 →
   重试」的钱包逻辑。
5. **在线续期轮换 refresh_token**：两个令牌都要持久化（onTokenUpdate patch
   双键 + runtimeSecretKeys 含 `access_token`）；漏存 refresh_token 会让
   下次续期直接断链。
6. **分支 2 的注释与代码不一致**：doc 注释称 client 凭证分支是
   `localRefresh` 分支，代码实际只判 `clientId` / `clientSecret` 非空
   （refresh_token 为空且开关关闭时也会走本地刷新）。重写时要先定语义：
   是按开关硬门控还是按凭证存在软回退，并把注释改对。
7. **get() 失败要抛真实原因**：不要把 `raw_url_error` 记在条目上返回
   无直链条目——那是 `CloudDriver.get` 契约的明确反例（11 §10）。
8. **401 只重试一次**；业务错误（code!==0）不重试。
9. **copy 不给能力位**：抛错实现是同步 throw；测试断言须用同步 expect。
10. **分页**：`last_file_id === -1` 末页；保留防死循环 guard；`trashed`
    过滤必须在客户端做（远端参数失效）。
11. **validateStatus 全放行**：非 2xx 也要读 body 走 code / 原文解析，
    「原样传递报错」依赖这一点。
12. **root_folder_id 与远程路径叠加**：前者是不透明 id（默认 `0`），后者是
    虚拟路径前缀，两者叠加生效，别混为一谈。
13. **rename 跨目录 = move + rename**：move 后仅当名字变化才补 rename；
    同名移动不发多余请求。
14. **remove 是回收站**（`/api/v1/file/trash`），不是物理删除。
