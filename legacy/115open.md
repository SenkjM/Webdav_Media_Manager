# 115open 驱动功能规格（已作废 · 重写参考）

> **状态声明**：本驱动的既有实现已按维护者决定整体作废、待重写。本文档是该
> 实现的功能性规格档案，基于本项目源码（`lib/services/cloud_drivers/open115_driver.dart`
> 主实现 + `test/open115_driver_test.dart` 行为回归）记录完整功能面供重写对照；
> 不代表仍受支持的行为，也不构成使用建议。
>
> **来源与版权声明**：本文档为独立整理的功能性规格，仅描述本项目自有实现的
> 可观察行为与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker
> 的任何源码或其衍生内容**。

全部事实来自本项目源码，主要出处：

- 主实现：`lib/services/cloud_drivers/open115_driver.dart`（下文引用时记作 `open115_driver.dart`）
- 测试：`test/open115_driver_test.dart`
- 基类契约：`lib/services/cloud_driver.dart`（下文记作 `base.dart`）

## 1. 标识

| 项 | 值 | 出处 |
|---|---|---|
| typeId | `115open` | open115_driver.dart:970 |
| displayName | `115网盘` | open115_driver.dart:973 |
| spec 类名 | `Open115Spec extends CloudDriverSpec` | open115_driver.dart:965 |
| 驱动类名 | `Open115Driver extends CloudDriver` | open115_driver.dart:606 |
| API 客户端 | `Open115Client` | open115_driver.dart:178 |
| 配置类 | `Open115Addition` | open115_driver.dart:62 |
| 主文件 | `lib/services/cloud_drivers/open115_driver.dart` | — |
| 测试 | `test/open115_driver_test.dart` | — |

两套基址（open115_driver.dart:201-204）：

- 文件 API：`https://proapi.115.com`（`Open115Client.apiBase`）
- 认证：`https://passportapi.115.com`（`Open115Client.authBase`，刷新端点
  `POST {authBase}/open/refreshToken`）

## 2. 能力位

`Open115Spec.capabilities`（open115_driver.dart:978-983）：

```
AccountCaps.list | AccountCaps.read | AccountCaps.mkdir |
AccountCaps.move | AccountCaps.copy | AccountCaps.delete
```

- **write 一律不给**——上传已按 99 §4.2.1 砍掉；`mkdir` 是真实现（99 §4.3.2 核查）。
- `runtimeCapabilities`：**无覆写**（用 `CloudDriver` 默认 null → 静态表）。
- `isWrapper`：默认 false（非包装驱动）。
- `dispose()`：无覆写（不持有需释放的跨请求资源；直链缓存与 fid 缓存随实例 GC）。

## 3. 表单字段

`Open115Spec.form`（open115_driver.dart:992-1019），全部为 `CloudDriverField`
文本字段，**无开关 / 下拉 / 开关联动**（测试断言 `form.whereType<CloudDriverSwitchField>()` 为空）：

| key | 类型 | label | required | obscure | 默认值 | hint 要点 |
|---|---|---|---|---|---|---|
| `refresh_token` | 文本 | `refresh_token` | ✅ | ✅ | `''` | 必填；115 每次刷新都会轮换它，轮换结果自动保存 |
| `root_id` | 文本 | 根目录 ID | ❌ | ❌ | `'0'` | 默认 0（整体根目录）；填非 0 目录 ID 可把账号挂到该目录下 |
| `page_size` | 文本 | 分页大小 | ❌ | ❌ | `'200'` | 范围 1~1150，默认 200（超出夹到边界；115 单次上限 1150） |
| `limit_rate` | 文本 | 限速（次/秒） | ❌ | ❌ | `'0'` | 默认 0 = 不限速；正数则两次 API 请求间隔至少 1/该值 秒 |

密钥覆盖（open115_driver.dart:988-989）：

- `runtimeSecretKeys` = `{'access_token'}`——运行时经 `onTokenUpdate` 写回的令牌缓存键，
  **不在表单里**；不声明就会明文进凭证库与备份（注释引 11 §6.2）。
- `secretFieldKeys`（基类默认合成）= 表单 obscure 字段 ∪ runtimeSecretKeys
  = `{'refresh_token', 'access_token'}`。`refresh_token` 也会被轮换写回，
  但已在表单里 obscure，无需重复声明。
- 明确**不进表单**的键（测试断言）：`access_token`、`order_by`、`order_direction`。

`Open115Addition.fromJson` 容错（open115_driver.dart:71-79）：`root_id` / `page_size` /
`limit_rate` 兼容数字型配置（表单是文本字段）；`root_id` 空串回落 `'0'`；
`page_size` 解析失败回落 200；`limit_rate` 解析失败回落 0。`toJson` 键名固定
（`refresh_token` / `root_id` / `page_size` / `limit_rate` / `access_token`）。

## 4. 认证与令牌生命周期

### init()（open115_driver.dart:634-671）

1. `page_size` 夹进 1..1150：`<=0 → 200`，`>1150 → 1150`（init 内夹紧），写回 addition。
2. `_client.login()`：缓存 `access_token` 为空则先 `refreshToken()` 刷新一次。
3. `_client.userInfo()` 真连校验（`GET /open/user/info`）：
   - `_Open115ApiException` 且 `isObjectNotFound`（430004）→ rethrow 原样透传；
   - 其余 API 异常 → 包成 `115 网盘 token 验证失败：<msg>。请确认 access_token / refresh_token 有效。`；
   - `CloudDriverException` 且 cause 是 `DioException` 或消息含「网络」/「SocketException」
     → 包成 `115 网盘网络连接失败（<msg>）：proapi.115.com 可能无法从当前部署环境访问（数据中心 IP 可能被 115 拦截），请稍后重试或更换部署环境。`。

### 令牌刷新（open115_driver.dart:257-293）

- `POST https://passportapi.115.com/open/refreshToken`，**form-urlencoded，不是 JSON**，
  只带 `refresh_token` 字段；该请求本身不带 Bearer（`withAuth: false`，access_token 正是在换它）。
- 空 `refresh_token` → 直接抛 `115 网盘缺少 refresh_token（必填）`，**不出网**。
- 判定成功：`body['code'] == 0` 且 `access_token` / `refresh_token` 均非空；
  否则抛 `115 网盘 token 刷新失败（code <code> <message>）：请确认 refresh_token 有效。`
  （响应只回 access_token 缺 refresh_token 也算失败——115 每次刷新都轮换 refresh_token，
  不存下去下次就刷不动了）。
- 成功后 `_applyTokens`：更新内存态（`accessToken`、`addition.accessToken`、
  `addition.refreshToken`）并调 `onTokenUpdate({'access_token': ..., 'refresh_token': ...})`
  ——**两个键都写回**，由兼容层持久化。

### 鉴权失败重试（open115_driver.dart:300-323）

`request()` 收到 `state == false` 且 `open115IsAuthError(code)`（code 为 `99` 或以
`401` 开头，open115_driver.dart:51-59）→ `refreshToken()` 后
**重试原请求一次**；重试仍失败或 `skipAuthRetry: true` 时不再刷新（防死循环）。
非鉴权错误不触发刷新（测试：430004 时 passportapi 零请求）。

### Dio 注入（open115_driver.dart:179-198）

- 构造函数可选 `dio` 参数（测试注入 mock adapter 用）；默认自建
  `Dio(BaseOptions(connectTimeout: 15s, receiveTimeout: 60s,
  headers: {User-Agent: open115UserAgent, Accept: application/json},
  validateStatus: (_) => true))`——**非 2xx 也回来读 body**（「原样传递报错」需要读到 115 的 code）。
- 单次出网 `_send`（open115_driver.dart:354-400）：限速等待 → 请求 → 网络层
  （`DioException`）重试 3 次（退避 500ms / 1000ms，`networkRetries = 3`）；最终失败抛
  `115 网盘网络请求失败（<url>）`。
- query / form 的空字符串值会被移除。
- 非 JSON 响应体：合成 `{state: false, code: <statusCode>, message: <截断 200 字>}`（open115_driver.dart:411-424）。

## 5. 接口实现逐条

错误翻译总规则：API 业务错误统一抛 `_Open115ApiException extends CloudDriverException`
（message 格式 `115 网盘 API 错误（code <code> <message>）`，附 `code` / `url` 字段）；
调用方按 code 区分语义。**本驱动不产生 `CloudDriverDataException`**（无解密语义）。

### list(path)（open115_driver.dart:674-698）

- `resolveFolderId(path)` 拿目录 cid（根路径直接用 `rootId`）。
- 循环 `GET /open/ufile/files`，query：`cid` / `limit=_pageSize` / `offset` /
  `asc=1` / `o=file_name` / `showDir=1`（排序固定，见 §7）。
- 分页推进：`offset += page.files.length`，直到 `page.files.isEmpty` 或
  `items.length >= page.count`（`count` 是当前目录条目总数）；空页立即结束不空转。
- 响应映射（`Open115File.fromMap` + `_toItem`）：
  `fn → name`；`fc == '0' → isDir`（**fc 是字符串**）；`fs → size`；
  `upt`（Unix **秒**）`> 0 → DateTime.fromMillisecondsSinceEpoch(upt * 1000)`，
  否则 `modified = null`（不造 1970 年）。列表条目**不带 rawUrl**（直链只在 get 取）。
- 缓存副作用：目录条目顺手写 `_fidCache[_joinPath(path, f.fn)] = f.fid`，
  后续路径解析少一轮列目录。
- `_pageSize` 默认 200（init 里夹过）；`resolveFolderId` 逐层解析、`resolveFile`、
  `_findInDir` 的列目录请求用 `limit = 1150`（上限拉满减少翻页）。

### get(path)（open115_driver.dart:701-728）

- 根路径（`'/'` 或 `'/<rootId>'`）→ 返回 `CloudFileItem(name: rootId, isDir: true)`，
  **不发任何请求**。
- `resolveFile(path)` 列父目录定位条目（**必须列父目录**：只有列表接口返回完整
  `pick_code`，`folder/get_info` 对文件路径不可用）。
- 目录条目 → 直接返回（无直链）。
- 文件 → `_client.linkFor(file)`（先查缓存，miss 才打 downurl，见 §6），返回
  `CloudFileItem(rawUrl: <url>, rawHeaders: {'User-Agent': open115UserAgent})`。
- 拿不到直链**抛真实原因**（本项目 `CloudDriver.get` 契约，见 §7 第 5 条）：消息含
  `downurl` / `pick_code` 的异常 rethrow；其余包成 `获取 115 网盘直链失败：<msg>`。

### mkdir(path)（open115_driver.dart:731-739）

- 拆出父路径与目录名（空段时目录名兜底 `'新文件夹'`）→ `resolveFolderId(父)`
  → `POST /open/folder/add`，form：`pid` / `file_name`。
- 完成后 `_fidCache.remove(clean)`。

### rename(path, newPath)（open115_driver.dart:742-755）

- 同目录（dirname 相等）→ `POST /open/ufile/update`，form：`file_id` / `file_name`。
- 跨目录 → 先 `POST /open/ufile/move`（`file_ids: fid` / `to_cid: 目标目录 id`），
  再 `update` 改名（接口契约：跨目录降级为移动 + 改名）。
- 两个路径（旧 / 新）的 fid 缓存都失效。

### remove(path)（open115_driver.dart:758-764）

- `resolveFile` → `POST /open/ufile/delete`，form：`file_ids: fid` /
  `parent_id: pid`（条目 `pid` 为空时退回 `rootId`）。

### move(srcPath, dstDir, newName)（open115_driver.dart:767-777）

- `resolveFile(srcPath)` + `resolveFolderId(dstDir)` → `POST /open/ufile/move`
  （`file_ids` / `to_cid`；接口的 `file_ids` 支持逗号分隔多 id，本驱动只传单个）。
- `newName` 非空且与当前名不同 → 追加 `update` 改名。
- 失效源路径与目标路径缓存。

### copy(srcPath, dstDir, newName)（open115_driver.dart:780-796）

- `POST /open/ufile/copy`，form：`pid: <目标目录 id>` / `file_id: <源 fid>` /
  `no_dupli: '1'`。**参数顺序是 (目标 pid, 源 fileId)**，与直觉相反——
  `pid` 是目标目录 id、`file_id` 是源文件 id（open115_driver.dart:558-560 注释）。
- 需要改名时：副本 fid 未知 → `_findInDir(dstDir, 当前名)` 列目标目录找出副本再
  `update` 改名；找不到抛 `115 网盘复制完成但未找到副本，无法改名为 <newName>`。

### 路径 → id 解析（open115_driver.dart:805-924）

- `resolveFolderId(path)`：`'/'` → `rootId`；先查 `_fidCache`；miss 时先
  `folder/get_info`（按 `path` 走 POST form `path=<干净路径>`，**只支持目录**）；
  报 430004（对象不存在）或 990002（参数错误，也是「该端点只支持目录路径」的
  判定依据）→ 回退**逐层列目录**（每层列 `cid` 下目录，按 `fn == 原名 / 解码名 /
  fid == 原名` 匹配，中途命中缓存段直接跳过）；其余错误原样抛（不吞真错误）；
  `get_info` 返回空 data 也回退。
- 逐层解析中目录不存在 → `115 网盘目录不存在：<prefix>`。
- `resolveFile(path)`：列父目录分页翻完，按 `fn == 原名 / 解码名 / fid == 原名 / fid == 解码名`
  匹配；找不到 → `115 网盘文件不存在：<rawName>`。
- `_tryDecode`：`Uri.decodeComponent` 失败时用原名——
  uri 编码的中文文件名也能匹配。

## 6. 直链与请求头

- **来源**：`POST /open/ufile/downurl`（proapi），form `pick_code`；响应形状
  `{ [fid]: { url: { url: '...' }, ... } }`，遍历 `data.values` 取第一个非空
  `url.url`（open115_driver.dart:488-506）。data 非对象 → `115 网盘 downurl 未返回直链数据`；
  无可用链接 → `115 网盘 downurl 未返回可用直链（url.url 为空）`。
- **条目缺 pick_code**（`pc` 为空）→ `115 网盘条目缺少 pick_code，无法获取直链：<fn>`
  （这就是 get 必须列父目录的原因）。
- **缓存**：`_linkCache` key = `fid|UA`（同一文件对不同 UA 分开缓存）；
  TTL 默认 **30 分钟**（`defaultLinkTtl`，open115_driver.dart:217，测试可注入更短的
  `linkTtl`）；过期即删、下次重取；**缓存命中不发出任何请求**。
- **406 配额**：代码注释明确「115 免费用户 downurl 有每日配额（配额用尽返回 406），
  缓存显著省调用」。406 错误原文透传（测试断言消息含 `406` 与服务端 message 原文）。
- **rawHeaders**：仅 `{'User-Agent': open115UserAgent}`，**无 Referer / 无 Cookie**。
  直链必须带 115 的 UA，否则 403。
- **UA 值**（open115_driver.dart:212-213）：
  `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/142.0.0.0 OpenList/425.6.30`
  ——既有实现的既定值（含 `OpenList/425.6.30` 版本后缀，实测行为依赖，逐字节保留）；
  API 请求与直链请求 / rawHeaders 用同一个字符串（115 有防盗链校验）。
- 直链本身的有效期：源码未记录具体值，仅靠 30 分钟缓存近似（重写时勿臆造更长 TTL）。

## 7. 特殊机制与取舍（设计决策）

代码注释明确记录的裁剪与设计决策（均在 open115_driver.dart 文件头与行内注释）：

1. **砍掉全部上传**（99 §4.2.1）：上传的秒传 / 二次校验 / OSS 直传 /
   HMAC-SHA1 签名全不实现，`sha1` 等 crypto 依赖因此不需要。
2. **`order_by` / `order_direction` 不进表单**（客户端自己排序），请求固定
   `o=file_name` + `asc=1`。
3. **`root_folder_id` 兼容别名不实现**（历史配置键兼容层，本应用无此存量配置）。
4. **`SUBREQUEST_LIMIT` 子请求预算不实现**：子请求预算是边缘无服务器
   运行时的配额限制，本应用没有该约束。
5. **get 拿不到直链时抛真实原因**（有意行为差异，含 406 配额用尽），
   而非记 warning 返回无直链条目——客户端里下游必然失败，不如直说
   （`CloudDriver.get` 契约，同百度 / 网易云驱动）。
6. **`limit_rate` 语义**：「请求间隔节流」
   （`_rateLimitMs = 1000 / limitRate`，`Stopwatch` 计时避免 `DateTime.now()` 时钟跳变），
   表单默认 `'0'` = 不限速——固定 1 次/秒会让浏览与播放首帧明显变慢。
7. **网络层重试**：3 次、退避 0.5s / 1s。

其他机制：

8. **fid 路径解析缓存**：本应用给驱动的是绝对路径而 115 API 只认 id，故维护实例级
   `path → id` 缓存（`_fidCache`，随驱动重建失效，99 §4.6）；缓存 key 是正斜杠开头的
   干净路径。写操作后按路径失效。
9. **root_id 挂载语义**：`'0'` = 整体根目录；非 0 目录 ID 把账号挂到该目录下
   （列表根、get 根分支、remove 的 parent_id 兜底都用它）；空串回落 `'0'`。
10. **响应包裹**：`{state: bool, code: number, message: string, data: T}`；
    `code === 430004` 是「对象不存在」（`open115ErrObjectNotFound`）；
    `990002` 是参数错误（`open115ErrInvalidParams`，folder/get_info 只支持目录的判定）；
    报错一律带服务端返回的 code 与 message 原文。
11. **非 JSON 响应**：合成 `state:false` 的 body（code = HTTP 状态码，message 截断 200 字）。

## 8. 行为契约（既有测试套件锁定，重写必须保持）

test/open115_driver_test.dart，自定义 dio `HttpClientAdapter` 拦截全部出站请求
（host / path / headers / body 可断言），逐条：

**spec 与能力**
- typeId = `115open`、displayName = `115网盘`、`cloudDriverSpec('115open')` 注册表登记。
- 能力位含 list / read / mkdir / move / copy / delete，**不含 write**。
- 表单 key 顺序 = `['refresh_token', 'root_id', 'page_size', 'limit_rate']`；
  `refresh_token` required + obscure；默认值 `'0'` / `'200'` / `'0'`；
  `access_token` / `order_by` / `order_direction` 不在表单；无开关字段。

**令牌刷新**
- 打 `passportapi.115.com/open/refreshToken`，POST，content-type 含
  `application/x-www-form-urlencoded`，**body 不是 JSON**（jsonDecode 必须抛异常），
  form 带 `refresh_token`；成功后两个 token 都经 onTokenUpdate 落库
  （`{'access_token': ..., 'refresh_token': ...}`）。
- 空 refresh_token → 抛「115 网盘缺少 refresh_token（必填）」且零出站请求。
- 刷新失败 → 错误消息含服务端 code（如 4010101）与 message 原文。
- 响应缺 `refresh_token`（只回 access_token）也算失败。

**鉴权重试**
- code 99 / 401xxx 且 state=false → 刷新一次再用**新** access_token 重打原请求
  （重试请求 `Authorization: Bearer at-fresh`）。
- 刷新后仍失败 → 抛错且不再刷新（passportapi 恰好 1 次、proapi 恰好 2 次，防死循环）。
- 非鉴权错误（430004）不触发刷新（passportapi 零请求）。
- 鉴权请求带 `Authorization: Bearer <access_token>` 头。

**列表**
- 分页按 count 推进（offset 0 → 2，取满即停）。
- 请求参数：`cid`（根路径用 root_id）/ `limit` / `offset` / `asc=1` / `o=file_name` / `showDir=1`。
- `fc === '0'`（字符串）判目录，其余是文件。
- `upt`（Unix 秒）→ DateTime、`fs` → size；`upt = 0` → `modified == null`。
- 列表条目 `rawUrl == null`（直链只在 get 取）；空页立即结束（只调一次）。

**直链**
- downurl 响应 `[fid].url.url` 落 `rawUrl`；`rawHeaders` = `{'User-Agent': <115 UA>}`
  （UA 含 `OpenList/425.6.30`，逐字节保留）。
- downurl 请求形状：POST + form `pick_code` + UA 头。
- 文件不存在 → 抛「115 网盘文件不存在」不静默。
- `url.url` 为空 → 抛含「直链」的可读错误，不产出空直链条目。
- **406 配额用尽** → 原文透传（消息含 `406` 与「请求过于频繁」），不吞掉。
- 根路径 `get('/')` 返回目录条目且零请求。

**链接缓存**
- 同一 fid 第二次取直链不再打 downurl（downCalls == 1，rawUrl 复用）。
- 缓存 key 带 UA：换 UA 重新取。
- `defaultLinkTtl == Duration(minutes: 30)`；过期后重新请求 downurl。
- `cachedLink` 未命中 key 返回 null 且不发请求。

**错误透传**
- 430004：code 与 message 原文都在异常消息里。
- HTTP 500 + HTML body 的业务错误同样原文透传。

**路径解析**
- `folder/get_info` 报 430004 / 990002 → 回退逐层列目录（calls 顺序
  `get_info → files:0 → files:d1`）。
- `get_info` 成功 → 一次性解析，只列一次目标目录（POST form `path`）。
- 其余错误（500）不回退、原样抛。
- 目录不存在 → 「115 网盘目录不存在」。
- `resolveFile` 列父目录按 fn 匹配（拿 pick_code）；uri 编码的名字（`%E4%B8%AD...`）
  也能通过解码兜底匹配。
- 路径 → fid 缓存：同一目录第二次解析不再打 get_info。

**写操作**
- mkdir：`POST /open/folder/add` form `{pid, file_name}`（pid 来自父目录解析）。
- rename 同目录：`POST /open/ufile/update` form `{file_id, file_name}`。
- rename 跨目录：降级 move（`file_ids` / `to_cid`）+ update。
- remove：`POST /open/ufile/delete` form `{file_ids, parent_id}`（parent_id 取条目 pid）。
- move：`POST /open/ufile/move` form `{file_ids, to_cid}`。
- copy：`POST /open/ufile/copy` form `{pid: <目标>, file_id: <源>, no_dupli: '1'}`
  ——**参数顺序是 (目标 pid, 源 fileId)，别接反**。

**init 与令牌校验**
- 有缓存 access_token → 只打 `/open/user/info` 校验（不刷新）；`page_size = 99999` 夹到 1150。
- 无 access_token → 先 refreshToken 再 user/info。
- `page_size = 0` → 回落 200。
- 令牌无效 → 错误含服务端 code / message / 「access_token / refresh_token 有效」提示。
- 网络不通 → 提示「proapi.115.com 可能无法从当前部署环境访问」。

**解析边界**
- `open115IsAuthError`：`99` / `401` / `4010101` / `'4010101'` / `'99'` 为真；
  `0` / `430004` / `990002` / `null` / `''` 为假。
- `Open115Addition.toJson` 键名固定；数字型配置（`root_id: 7`、
  `page_size: '500'`）能读进来；`root_id` 空串回落 `'0'`。
- `spec.create()` 从配置构造驱动（accessToken 初始为空串）。

## 9. 重写注意事项（从实现提炼的陷阱）

1. **刷新端点是 form-urlencoded 不是 JSON**——写成 JSON 会静默失败（服务端只回错误包裹）。
2. **两个 token 必须一起持久化**：115 每次刷新轮换 refresh_token，只存 access_token
   下次就刷不动了；`access_token` 不在表单，必须进 `runtimeSecretKeys` 否则明文进备份。
3. **copy 参数顺序反直觉**：`(pid=目标, file_id=源)`；且 `no_dupli: '1'`。副本 fid 未知，
   改名要先列目标目录找副本。
4. **`fc` 是字符串**：`'0'` = 目录、`'1'` = 文件，别用数字比较。
5. **`upt` 是 Unix 秒不是毫秒**（×1000 转 DateTime）；`upt = 0` → null 而不是 1970。
6. **`pick_code` 只有列表接口返回**：`folder/get_info` 对文件路径不可用（报 990002），
   所以 get / remove / rename 等都必须先列父目录。
7. **`folder/get_info` 只支持目录路径**：430004 / 990002 要回退逐层列目录，
   其余错误原样抛（不能一律回退吞掉真错误）。
8. **UA 是防盗链钥匙**：API 请求与直链下载必须用同一个 UA 字符串（含 `OpenList/425.6.30`
   后缀），rawHeaders 只带 User-Agent、无 Cookie / Referer；不带 UA 直链 403。
9. **406 = 免费号 downurl 每日配额**：直链缓存（key = `fid|UA`，TTL 30 分钟）是配额的
   主要节省手段；缓存命中不能发出任何请求。
10. **`validateStatus: (_) => true`**：115 把业务错误包在 HTTP 200（或非 2xx + JSON）里，
    不读 body 拿不到 code；非 JSON body 要合成 `state:false` 包裹。
11. **query / form 空字符串值要移除**，否则可能触发参数错误。
12. **路径缓存失效时机**：mkdir / rename / move / copy 后要失效对应路径的 fid 缓存，
    否则后续解析拿到旧 id。
13. **`page_size` 要夹 1..1150**（`<=0 → 200`，`>1150 → 1150`）；逐层解析列目录可用
    limit 1150 减少翻页。
14. **数据中心 IP 可能被 115 拦截**：init 的网络失败提示要引导用户换部署环境，
    这是真机反馈过的场景（错误文案已含该提示）。
15. **鉴权重试只做一次**：`skipAuthRetry` 防死循环；非鉴权错误（如 430004）不触发刷新。
16. **上传整体不存在**：重写时不要补 `put()` / `order_by` /
    `root_folder_id` 别名 / `SUBREQUEST_LIMIT`——这些是按用户决策明确裁剪的。
