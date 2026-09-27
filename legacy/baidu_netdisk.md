# baidu_netdisk 驱动功能实现清单（已作废 · 重写参考）

> **状态声明**：本驱动已按维护者决定作废、待重写。本文档记录当前实现的完整功能面，供将来重写参考。全部事实来自源码，主要出处：
>
> - 主实现：`lib/services/cloud_drivers/baidu_netdisk_driver.dart`（604 行，下文引用时记作 `driver.dart`）
> - 测试：`test/baidu_refresh_switch_test.dart`（210 行，下文记作 `test.dart`）
> - 基类契约：`lib/services/cloud_driver.dart`（414 行，下文记作 `base.dart`）
> - 能力位定义：`lib/models/account_capabilities.dart`（35 行，下文记作 `caps.dart`）
>
> 与上游 OpenList 的差异仅记录代码注释明确提到的内容，并注明出处行号。

## 1. 标识

| 项 | 值 |
|---|---|
| typeId（provider_type 存库值） | `baidu_netdisk` |
| displayName | `百度网盘` |
| spec 类 | `BaiduNetdiskSpec extends CloudDriverSpec`（const 构造，driver.dart:534-535） |
| 驱动类 | `BaiduNetdiskDriver extends CloudDriver`（driver.dart:384） |
| 辅助类 | `BaiduAddition`（配置模型，driver.dart:23）/ `BaiduFile`（列表条目，driver.dart:68）/ `BaiduClient`（HTTP 客户端，driver.dart:85），全部同文件 |
| 文件路径 | `lib/services/cloud_drivers/baidu_netdisk_driver.dart` |
| 上游 TS 版 | `localdev/OpenList-Worker/src/backend/drivers/baidu_netdisk`（driver.ts / util.ts / types.ts） |
| 上游 Go 版 | `localdev/OpenList/drivers/baidu_netdisk`（driver.go / meta.go / types.go / util.go） |

补充说明：

- 文件头注释（driver.dart:9-22）声明来源：「移植自 localdev/OpenList-Worker/src/backend/drivers/baidu_netdisk（driver.ts + util.ts，Go 版语义兜底）」，并列出裁剪与差异决策（详见第 7 章）。
- 注册方式（driver.dart:531-533 尾注）：spec 自描述收在驱动文件内，「register 表：cloud_drivers/driver_registry.dart 里加一行即接入」。
- `BaiduNetdiskDriver` 构造参数：`{required BaiduAddition addition, void Function(Map<String, dynamic> patch)? onTokenUpdate}`（driver.dart:385-388）；内部直接构造 `BaiduClient`，不透传 Dio。

## 2. 能力位

`BaiduNetdiskSpec.capabilities`（driver.dart:548-556）：

```dart
int get capabilities => AccountCaps.list |
    AccountCaps.read |
    AccountCaps.mkdir |
    AccountCaps.move |
    AccountCaps.copy |
    AccountCaps.delete;
```

位定义（caps.dart:12-18）：

| 位 | 值 | 含义 |
|---|---|---|
| `list` | `1 << 0` | 列出目录 |
| `read` | `1 << 1` | 读取（缓存音乐、下载、浏览、播放、流式） |
| `write` | `1 << 2` | 写入（上传——**本驱动不声明**） |
| `mkdir` | `1 << 3` | 创建文件夹（用户决定：从「写入」拆出独立位） |
| `move` | `1 << 4` | 移动（含改名） |
| `copy` | `1 << 5` | 复制 |
| `delete` | `1 << 6` | 删除 |

- 合计掩码值 = `123`（0b1111011）。**`write` 一律不给**——上传已砍（99 §7.2.1；driver.dart:548-549 注释，另注「mkdir 逐盘核查见 99 §7.3.2」）。
- `runtimeCapabilities`：**未覆写**（base.dart:14-15 默认 null = 用 spec 静态表）。
- `runtimeTypeLabel`：未覆写（base.dart:22 默认 null）。
- `dispose()` / `openContent()` / `openContentRange()` / `openDownloadContent()` 均未覆写：非 MustProxy 驱动、无跨请求资源、无本地流桥需求。
- `isWrapper` 保持默认 false（base.dart:298）：非包装驱动；`create()` 收下 `env` 参数但不使用。
- `verify()` 用基类默认实现（base.dart:352-359）= `create() + init()`，即表单保存前的真连校验就是 login + uinfo。

## 3. 表单字段

`BaiduNetdiskSpec.form`（driver.dart:559-591），声明顺序即界面渲染顺序（base.dart:139 注释）：

| # | key | 类型 | label | required | obscure | 默认值 | 开关联动 |
|---|-----|------|-------|:---:|:---:|--------|----------|
| 1 | `refresh_token` | CloudDriverField | `refresh_token` | ✔ | ✔ | `''` | 无 |
| 2 | `api_url_address` | CloudDriverField | 在线续期地址 | ✗ | ✗ | `BaiduClient.defaultRenewApi` | `disabledWhenSwitch: 'local_refresh'` |
| 3 | `local_refresh` | CloudDriverSwitchField | 在本地处理令牌刷新 | — | — | `false` | （本字段是其他字段联动的开关源） |
| 4 | `client_id` | CloudDriverField | Client ID | ✗ | ✗ | `''` | `visibleWhenSwitch: 'local_refresh'` |
| 5 | `client_secret` | CloudDriverField | Client Secret | ✗ | ✔ | `''` | `visibleWhenSwitch: 'local_refresh'` |

hint / subtitle 原文（driver.dart:563、570、573、578）：

- `refresh_token`：「必填；获取方法见 OpenList 官方文档（baidu_netdisk 驱动页）」
- `api_url_address`：「默认用 OpenList 维护的公共服务」
- `api_url_address` disabledHint：「已开启本地刷新（online api 停用），关闭开关后可编辑」
- `local_refresh` subtitle：「关闭＝在线续期地址刷新；开启＝用自建百度应用刷新（需 Client ID / Secret），在线续期停用」

开关联动语义（base.dart:177-191）：

- `visibleWhenSwitch`：开关打开才**显示**该字段。
- `disabledWhenSwitch`：开关打开则**停用**该字段（极性与 `enabledWhenSwitch` 相反；两者互斥，同时声明视为未声明）。本驱动用它在「本地刷新」开启后停用在线续期地址输入——对应 99 §7.3.1「一旦打开就不使用 online api 逻辑」。
- 联动开关值解析由基类 `switchValue(key, values)` 统一处理（base.dart:333-342）：实时值 → 开关 defaultValue → false。

**runtimeSecretKeys** = `const {'access_token'}`（driver.dart:540-543；注释引「§4 令牌轮换」「11 §6」）：`access_token` 缓存运行时经 `onTokenUpdate` 写回驱动配置、**不在表单里**——凭证加密范围靠它补全，不声明就会明文进凭证库与备份（base.dart:316-323 注释）。

**secretFieldKeys**（基类派生规则：obscure 表单字段 ∪ runtimeSecretKeys，base.dart:310-314）= `{ refresh_token, client_secret, access_token }`。

序列化（`BaiduAddition.fromJson` / `toJson`，driver.dart:33-49）：

- JSON 键与表单一致，外加 `access_token`：`refresh_token` / `client_id` / `client_secret` / `api_url_address` / `local_refresh` / `access_token`。
- fromJson 对缺键全部容忍（`?? ''` / `?? false`）。
- 注意：`api_url_address` 反序列化缺省是 `''` 而非 defaultRenewApi——空值回落发生在 `refreshToken()` 内（见第 9 章陷阱 2）。
- `BaiduAddition` 构造器默认值（driver.dart:24-31）：`apiUrlAddress = BaiduClient.defaultRenewApi`、`localRefresh = false`、其余空串——与 fromJson 的缺省行为**不同**。

## 4. 认证与令牌生命周期

### 4.1 init()（driver.dart:392-397）

1. `_client.login()`（driver.dart:121-123）：`accessToken` 为空才调 `refreshToken()`；**有缓存 access_token 就直接用，不主动刷新**。
2. `_client.uinfo()`（driver.dart:377-380）：`GET /xpan/nas`，params `{'method': 'uinfo'}`；注释「校验令牌（无效 / 风控在此抛出）」；返回 `vip_type`（init 不使用返回值）。令牌无效（errno 111/-6/20016）在这一步走 request() 管线的刷新逻辑后抛错。

### 4.2 令牌刷新 refreshToken()（driver.dart:126-192）

每次刷新都会检查 `localRefresh` 开关（文件头注释 driver.dart:21-22：「后端每次刷新都会检查该开关」）。

**分支 A：在线续期（localRefresh = false）**

1. URL：`apiUrlAddress.trim()` 非空则用之；空串回落 `defaultRenewApi = https://api.oplist.org/baiduyun/renewapi`。
2. 请求构造（driver.dart:133-141）：

```dart
_dio.get<String>(u, queryParameters: {
  'refresh_ui': a.refreshToken,
  'server_use': 'true',
  'driver_txt': 'baiduyun_go',
}, options: Options(responseType: ResponseType.plain));
```

3. 响应用 `ResponseType.plain` 手动 `jsonDecode`（错误响应可能是非 JSON 文本）；decode 失败或非 Map → data 为 null。
4. 错误翻译（driver.dart:148-161）：
   - 非 JSON → `CloudDriverException('在线 API 刷新失败 (HTTP <code>)：<原文，超 300 字截断；空则「非 JSON 响应」>。请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。')`
   - 响应缺 `refresh_token` 或 `access_token` 键 → `CloudDriverException(data['text'] ?? (statusCode != 200 ? '在线 API 返回 HTTP <code>' : 'empty token returned from official API, a wrong refresh token may have been used'))`
5. 成功 → `_applyTokens(data['access_token'], data['refresh_token'])`。

**分支 B：本地刷新（localRefresh = true，自建百度应用 OAuth）**

1. `clientId` / `clientSecret` 任一为空 → `CloudDriverException('empty ClientID or ClientSecret')`，**不出网**。
2. 请求构造（driver.dart:170-178）：

```dart
_dio.get<dynamic>(oauthApi, queryParameters: {
  'grant_type': 'refresh_token',
  'refresh_token': a.refreshToken,
  'client_id': a.clientId,
  'client_secret': a.clientSecret,
});
```

3. 错误翻译（driver.dart:179-187）：`data['error']` 非空 → `CloudDriverException('<error>: <error_description>')`；缺 `refresh_token` → `'empty refresh token returned from OAuth'`（`access_token` 缺失容忍为 `''`）。

**_applyTokens(access, refresh)**（driver.dart:194-202）：

- 依次更新 `BaiduClient.accessToken` → `addition.accessToken` → `addition.refreshToken`，再 `onTokenUpdate?.call({'access_token': access, 'refresh_token': refresh})`。
- **onTokenUpdate 写回两个键：`access_token` 与 `refresh_token`**。
- `BaiduAddition.refreshToken` 字段注释（driver.dart:51）：「刷新令牌（必填）。在线续期会轮换它，轮换结果经 onTokenUpdate 持久化」——refresh_token 是轮换型凭证，必须及时持久化。

### 4.3 pan API 请求管线 request() / _doRequest()（driver.dart:204-283）

- 入口先判 `accessToken.isEmpty` → `refreshToken()`（driver.dart:212）。
- 重试策略（driver.dart:214-228）：`retryCount = 3`、`retryWaitMs = 1000`，退避 `retryWaitMs << attempt`（1s / 2s）：
  - **`CloudDriverException` 直接 rethrow、不重试**（注释：业务错误——errno / 风控 / 非 JSON）；
  - 仅传输层异常（非 CloudDriverException 的 catch）重试；
  - 3 次全失败 → `CloudDriverException('百度网盘请求失败', lastErr)`。
- `_doRequest`（driver.dart:231-283）请求构造：
  - query = `{'access_token': accessToken, ...?params}`；
  - POST：`$panApi$pathname` + form（`contentType: Headers.formUrlEncodedContentType`、`responseType: ResponseType.plain`）；
  - GET：`$panApi$pathname` + query（`ResponseType.plain`）。
- 响应解析与错误翻译：
  - 非 JSON → `CloudDriverException('req: [<pathname>] invalid JSON response, status <code>')`；
  - `errno = body['errno'] ?? 0`；`errno != 0` 时按表翻译：

| 条件 | 行为 |
|---|---|
| `errno ∈ tokenErrors = {111, -6, 20016}` | 先 `await refreshToken()`，随后仍走下方的 errno 报错（见第 9 章陷阱 1） |
| `errno == 31023` | `CloudDriverException('<base> 百度网盘风控（触发安全策略，通常数分钟至数小时后自动解除）。refresh_token 无效或非官方渠道获取也可能触发；请确认通过 https://api.oplist.org/ 获取。')` |
| 其余 errno | `CloudDriverException('req: [<pathname>] ,errno: <errno>, refer to https://pan.baidu.com/union/doc/')` |

其中 `<base>` = `'req: [<pathname>] ,errno: <errno>, refer to https://pan.baidu.com/union/doc/'`（driver.dart:272-273）。tokenErrors 注释（driver.dart:97）：「worker 实测：111 文档标准、-6 与 20016 实测」。

### 4.4 Dio 注入方式

- `BaiduClient(this.addition, {this.onTokenUpdate, Dio? dio})`（driver.dart:103-114）：可选 `dio` 参数是**测试注入点**（测试用自定义 `HttpClientAdapter` 拦截全部出站请求）。
- 默认 Dio 配置（driver.dart:105-113）：

```dart
Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 60),
  headers: {'User-Agent': apiUA, 'Accept': 'application/json'},
  // 非 2xx 也回来走 errno / 原文解析：「原样传递报错」需要读到 body。
  validateStatus: (_) => true,
))
```

- `BaiduNetdiskDriver` 构造器**不暴露** dio 注入——测试因此直接测 `BaiduClient` 而非驱动层。

### 4.5 常量表（driver.dart:86-101）

| 常量 | 值 | 备注 |
|---|---|---|
| `oauthApi` | `https://openapi.baidu.com/oauth/2.0/token` | 本地刷新端点 |
| `panApi` | `https://pan.baidu.com/rest/2.0` | pan API 前缀 |
| `defaultRenewApi` | `https://api.oplist.org/baiduyun/renewapi` | OpenList 公共续期服务 |
| `apiUA` | `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/142.0.0.0 OpenList/425.6.30` | 普通 API UA；注释：对齐 Go 版 drivers/base/client.go UserAgentNT |
| `downloadUA` | `pan.baidu.com` | 下载直链必需 UA；注释：worker getOfficialLink 证实 |
| `tokenErrors` | `{111, -6, 20016}` | token 失效 errno 集合 |
| `retryCount` / `retryWaitMs` | `3` / `1000` | 重试次数与基础退避 |

## 5. 接口实现逐条

公共前置（适用于全部接口）：

- **路径归一化** `_baiduPath()`（driver.dart:501-505）：`'/' + p.replaceAll(RegExp(r'/+'), '/')` 折叠连续斜杠 → 尾部 `/` 去掉（根 `'/'` 保持原样）。
- 所有 pan API 调用走第 4.3 章 `request()` 管线（自动带 access_token query、errno 解析、token 错误刷新、传输层 3 次退避重试）。
- **没有请求签名**——鉴权全部靠 query 里的 `access_token`。

### 5.1 list(path)（driver.dart:399-403 → getFiles 285-306）

- 端点与方法：`GET /xpan/file`。
- 请求构造（driver.dart:290-296）：

```dart
params: {
  'method': 'list',
  'dir': dir,
  'web': 'web',
  'start': '$start',   // 从 0 起，每轮 +1000
  'limit': '$limit',   // 固定 1000
}
```

- 分页（driver.dart:287-304）：`limit = 1000`；`body['list']` 非 List 或为空、或长度 < limit 即终止——一页不满就停（两个终止条件并存，防死循环）。
- 响应解析：`list` 逐项（仅取 `Map<String, dynamic>` 项）`BaiduFile.fromMap`（driver.dart:76-82）：

| BaiduFile 字段 | JSON 键 | 容错 |
|---|---|---|
| `fsId` | `fs_id` | num→toInt，缺省 0 |
| `path` | `path` | 缺省 `''` |
| `serverFilename` | `server_filename` | 缺省 `''` |
| `size` | `size` | num→toInt，缺省 0 |
| `isdir` | `isdir` | num→toInt，缺省 0 |
| `serverMtime` | `server_mtime` | num→toInt，缺省 0 |

- 映射到 CloudFileItem（`_toItem`，driver.dart:507-520）：
  - `name` = `server_filename`（空串回退 `cloudBasename(path)`）；
  - `isDir` = `isdir == 1`；
  - `size` 原样；
  - `modified` = `serverMtime > 0 ? DateTime.fromMillisecondsSinceEpoch(serverMtime * 1000) : null`（**秒 → 毫秒换算**）；
  - 不带 rawUrl / rawHeaders。
- 缓存：无——每次全量翻页现拉。
- 错误翻译：request() 管线统一处理（errno / 非 JSON / 传输失败均为 `CloudDriverException`）。

### 5.2 get(path)（driver.dart:405-448）

- 根路径：直接返回 `const CloudFileItem(name: '/', isDir: true)`（无 rawUrl）。
- 注释（driver.dart:411）：「百度没有按路径查单文件的 API：列父目录找到目标（对齐 worker）」→
  - `parent = cloudDirname(bp)`、`rawName = cloudBasename(bp)`；
  - `decoded = _tryDecode(rawName)`（`Uri.decodeComponent`，异常回退原文——处理百分号编码路径，driver.dart:522-528）；
  - `files = await _client.getFiles(parent)`（复用 5.1 的分页列表）。
- 匹配（首个命中即选中，driver.dart:417-425），四条件任一满足：

```dart
f.serverFilename == rawName ||
f.serverFilename == decoded ||
f.path == bp ||
f.fsId.toString() == rawName
```

- 未命中 → `CloudDriverException('file not found: <rawName>')`。
- 命中且是目录 → 返回 `_toItem`（无 rawUrl）。
- 命中且是文件 → `_client.getOfficialLink(file.fsId)`：
  - `CloudDriverException` 原样 rethrow（**与 worker 的有意差异**：直说真实原因，见第 7 章第 4 条）；
  - 其他异常包装为 `CloudDriverException('获取下载直链失败：$e')`；
  - 返回的 `CloudFileItem` 带 `rawUrl` + `rawHeaders`，其余字段沿用 `_toItem`。

### 5.3 mkdir(path)（driver.dart:450-453 → createDir 366-374）

- 端点与方法：`POST /xpan/file`，params `{'method': 'create'}`。
- form（driver.dart:372）：`{'path': path, 'size': '0', 'isdir': '1', 'rtype': '3'}`。
- 注释（driver.dart:366）：「create（mkdir 用 isdir=1；上传相关参数一并不移植）」。

### 5.4 rename(path, newPath)（driver.dart:455-472）

- 归一化两侧路径后分支：
  - **同目录**（`cloudDirname(bp) == cloudDirname(dst)`）→ `manage('rename', [{'path': bp, 'newname': cloudBasename(dst)}])`；
  - **跨目录** → `manage('move', [{'path': bp, 'dest': cloudDirname(dst), 'newname': cloudBasename(dst)}])`。
- 基类注释（base.dart:55-57）：跨目录时由实现降级为「移动 + 改名」，百度 filemanager 的 move 自带 newname。

### 5.5 remove(path)（driver.dart:474-477）

- `manage('delete', [_baiduPath(path)])`——**filelist 元素是纯路径字符串**（其余操作都是对象形式，一个容易踩的不对称）。

### 5.6 move(srcPath, dstDir, newName)（driver.dart:479-488）

- `manage('move', [{'path': _baiduPath(srcPath), 'dest': _baiduPath(dstDir), 'newname': newName}])`。

### 5.7 copy(srcPath, dstDir, newName)（driver.dart:490-498）

- `manage('copy', [{'path': _baiduPath(srcPath), 'dest': _baiduPath(dstDir), 'newname': newName}])`——与 move 完全同构，仅 opera 不同。

### 5.8 manage() 公共形态（driver.dart:352-364）

- 注释：「filemanager（rename / move / copy / delete 共用）」。
- 端点与方法：`POST /xpan/file`，params `{'method': 'filemanager', 'opera': <rename|move|copy|delete>}`。
- form：`{'async': '0'（同步执行）, 'filelist': jsonEncode(filelist), 'ondup': 'fail'（目标重名不覆盖、直接失败）}`。

### 5.9 错误翻译汇总

- 所有失败路径产出 `CloudDriverException`。
- **本驱动从不抛 `CloudDriverDataException`**——无解密 / 内容完整性校验场景；该异常在基类语义里（base.dart:102-106）表示「内容本身不可用、重试没有意义」，对纯网盘直链驱动不适用。

## 6. 直链与请求头

**rawUrl 来源**（`getOfficialLink(fsId)`，driver.dart:308-338；仅 `get()` 的文件分支调用）：

1. `GET /xpan/multimedia`，params（driver.dart:312-316）：

```dart
{'method': 'filemetas', 'fsids': '[$fsId]', 'dlink': '1'}
// fsids 是 JSON 数组字符串，如 "[123456789]"
```

2. 取 `body['list'][0]['dlink']`（list 非 List / 空 / dlink null 或空串）→ `CloudDriverException('no dlink returned from filemetas')`。
3. `u = '$dlink&access_token=$accessToken'`（dlink 自带 query 串，故用 `&` 续接 token）。
4. `HEAD u`（driver.dart:325-332）：`followRedirects: false`、`validateStatus: (_) => true`、headers `{'User-Agent': downloadUA}`——手动跟 302，**不走 request() 管线**（无重试、无 errno 解析）。
5. `location = head.headers.value('location') ?? u`（无 Location 头则回落 u 本身——该回落的可用性存疑，见第 9 章陷阱 4）。
6. 返回 `(url: _sanitizeDlink(location), headers: {'User-Agent': downloadUA})`。

**_sanitizeDlink**（driver.dart:340-350）：

- `Uri.parse` → 复制 queryParameters → **`remove('access_token')`** → `uri.replace` 重组；
- 解析异常原样返回（不 throw）。
- 目的：直链不携带 access_token（防凭证泄漏进播放器 / 日志）。

**有效期与缓存**：

- 实现内**没有任何直链缓存，也没有有效期管理**——每次 `get()` 重新走 filemetas + HEAD 全流程；
- dlink 时效完全由百度侧决定，源码未记录具体时长。

**rawHeaders 具体值**：

- 仅 `{'User-Agent': 'pan.baidu.com'}`。
- **没有 Referer、没有 Cookie**（base.dart:88 注释提到网盘直链可能需要 Cookie/Referer/UA，本驱动实测只需 UA——driver.dart:94-95 注释「下载直链必需的 UA（worker getOfficialLink 证实）」）。

## 7. 特殊机制与取舍（与上游差异 · 全部出自代码注释并注明出处）

**裁剪（不实现）**：

1. **砍掉 crack 下载 API**：`download_api` / `custom_crack_ua` / getCrackLink / getCrackVideoLink，只走官方 dlink——文件头注释（driver.dart:13），「按用户决策」。
2. **砍掉全部上传字段与逻辑**（99 §7.2.1，上传整体已砍）——文件头注释（driver.dart:14）。
3. **`order_by` / `order_direction` / `only_list_video_file` 不暴露**：客户端自己排序 / 分类——文件头注释（driver.dart:15）。
4. **create 的上传相关参数一并不实现**——createDir 注释（driver.dart:366）。

**与 worker 的有意行为差异**：

5. **get 拿不到直链时抛出真实原因（风控 / 无权限）**：worker 只记 warning 返回无直链条目；「客户端里下游必然失败，不如直说」——文件头注释（driver.dart:18-19）。
6. **表单开关「在本地处理令牌刷新」双分支**：开启走自建百度应用 OAuth 刷新（client_id + client_secret），关闭走续期地址（默认 OpenList 公共服务）；「后端每次刷新都会检查该开关」——文件头注释（driver.dart:20-22）；用户决策原话另见 test.dart:3-4。

**实现注记**：

7. **apiUA 对齐 Go 版** `drivers/base/client.go` 的 `UserAgentNT`——注释（driver.dart:90-92）。
8. **tokenErrors 集合来自 worker 实测**：111 文档标准、-6 与 20016 实测——注释（driver.dart:97）。
9. **filemanager 四操作共用一条通路**（rename / move / copy / delete）——manage 注释（driver.dart:352）。
10. **uinfo 作为令牌校验探针**（无效 / 风控在此抛出）——uinfo 注释（driver.dart:376）。

（小计：特殊机制 / 取舍共 **10 条**——1-4 为裁剪、5-6 为与 worker 的有意行为差异、7-10 为实现注记。）

## 8. 测试覆盖（test/baidu_refresh_switch_test.dart，210 行）

**测试基建**（test.dart:25-71）：

- 自定义 `HttpClientAdapter`（`_RoutingAdapter`）拦截**全部出站请求**按 host 分流：`api.oplist.org` → 本地续期 HttpServer；`openapi.baidu.com` → 本地 OAuth HttpServer；其余 → 404。
- `hits` 列表记录每次请求的完整 URL 供断言。
- 注入方式：`BaiduClient(addition, dio: dio)` + `dio.httpClientAdapter = adapter`（test.dart:122-124）。
- 续期服务器（test.dart:87-103）：只在 `GET /baiduyun/renewapi` 且 `refresh_ui` 非空时返回 `{"access_token":"online-access","refresh_token":"online-refresh"}`，否则 400（非 JSON 响应）。
- OAuth 服务器（test.dart:104-121）：只在 `GET /oauth/2.0/token` 且 `grant_type=refresh_token` 时返回 `{"access_token":"local-access","refresh_token":"local-refresh"}`，否则 400。

**group「local_refresh = false（开关关闭）→ 走 online api」**（test.dart:132-173）：

1. *请求打到在线续期地址，绝不带 client 凭证*（test.dart:133-147）：
   - `renewHits == 1`（必须打在线续期端点）；
   - `oauthHits == 0`（开关关闭时绝不走自建 OAuth）；
   - 刷新后 `client.accessToken == 'online-access'` 且 `addition.refreshToken == 'online-refresh'`（**令牌轮换必须回写**）；
   - 出站 query **不含 `client_id` / `client_secret`**；
   - `query['refresh_ui'] == 'rt-1'`。
2. *空 apiUrlAddress 回落到默认公共服务地址*（test.dart:149-159）：请求 host == `api.oplist.org`、path == `/baiduyun/renewapi`。
3. *在线 API 失败：错误原文透传，不落 OAuth 兜底*（test.dart:161-172）：`refreshToken: ''` → 续期服务器 400 → `refreshToken()` 抛 `CloudDriverException`；且 `oauthHits == 0`（**失败时不得静默切到本地 OAuth**）。

**group「local_refresh = true（开关打开）→ 走自建应用 OAuth」**（test.dart:175-209）：

4. *请求打到百度 OAuth 端点，带 client 凭证，不碰续期地址*（test.dart:176-196）：
   - `oauthHits == 1`（必须打 OAuth 端点）；
   - `renewHits == 0`（开关打开时绝不使用 online api）；
   - `accessToken == 'local-access'`、`addition.refreshToken == 'local-refresh'`；
   - query 断言：`grant_type == 'refresh_token'`、`refresh_token == 'rt-3'`、`client_id == 'my-cid'`、`client_secret == 'my-secret'`。
5. *缺 ClientID / ClientSecret：直接报错，不出网*（test.dart:198-208）：抛 `CloudDriverException`；`adapter.hits` 为空（**缺凭证时不得发出任何网络请求**）。

**重写必须保持的契约**（测试文件头注释 test.dart:1-9 锁死）：

- 用户决策原话（test.dart:3-4）：「后端时也需要检查该开关，一旦打开就不使用online api逻辑而使用自建百度应用的刷新逻辑。」
- 开关关闭：只打在线续期地址；绝不携带 client 凭证；失败时绝不切 OAuth 兜底。
- 开关打开：只打 OAuth 端点；必须带 `grant_type=refresh_token` + 三凭证；绝不碰续期地址；缺凭证先本地报错、零出网。
- 空续期地址 → 回落 `https://api.oplist.org/baiduyun/renewapi`。
- 刷新成功后新 access_token / refresh_token 必须同时回写 `BaiduClient.accessToken` 与 `BaiduAddition`（onTokenUpdate 持久化路径的前半段）。

**测试未覆盖**（该文件只锁令牌刷新分支，以下行为在旧实现中无回归保护，重写时需要新测试兜住）：

- `init()` / `uinfo()` 真连校验流程，以及 `login()` 有缓存 access_token 时不刷新的短路。
- `getFiles` 的 1000/页翻页与两个终止条件；`get()` 的四重匹配、`file not found`、根路径短路。
- `getOfficialLink`（filemetas → HEAD 302 → location 回落）与 `_sanitizeDlink` 的去 token 行为。
- `manage` / `createDir` 的 form 形态（delete 的字符串数组 vs 其余的对象数组、`ondup: fail`）。
- errno 令牌刷新路径（`tokenErrors` 刷新后当前请求仍抛错）与 31023 风控文案。
- `onTokenUpdate` patch 形状与持久化（测试构造 `BaiduClient` 时未传回调，只断言了 `addition` 的内存回写）。

## 9. 重写注意事项（从实现中提炼的陷阱）

1. **令牌错误「刷新但不重试」**：`_doRequest` 遇 `errno ∈ {111, -6, 20016}` 先 `refreshToken()`，随后**仍抛 errno 错误**；外层 `request()` 对 `CloudDriverException` 一律 rethrow——本次调用不会用新令牌重跑，只有下一次请求受益。注释（driver.dart:269「Go：先刷新令牌，外层重试再跑一次」）与实际控制流不符。重写时明确语义：要么刷新后真正重试一次，要么文档化「只刷新不重试」。
2. **api_url_address 默认值三处不一致**：表单 defaultValue = defaultRenewApi（driver.dart:571）；`BaiduAddition` 构造器默认 = defaultRenewApi（driver.dart:28）；`fromJson` 缺省 = `''`（driver.dart:37）。空值回落靠 `refreshToken()` 里 `trim().isNotEmpty` 判断兜底。重写应收敛为单一默认值来源。
3. **refresh_token 是轮换型凭证**：在线续期成功会换新 refresh_token（字段注释 driver.dart:51），旧的可能作废。onTokenUpdate 必须同时持久化 `access_token` + `refresh_token`；持久化失败应视为登录失败，否则下次启动账号失效。
4. **直链必须去 token，且 HEAD 回落路径可疑**：Location 头缺失时 `location = u`（`dlink&access_token=…`），经 `_sanitizeDlink` 后变成**无 token 的 dlink**——该回落的可用性实现未验证。重写时要么显式报错，要么验证无 token dlink 可下载。
5. **无直链缓存**：每次 `get()` 现取（filemetas + HEAD 两次网络往返）。媒体客户端反复取流的场景，重写应加带 TTL 的直链缓存与失效重取。
6. **`validateStatus: (_) => true` 是错误透传的前提**：非 2xx 必须读到 body 才能解析 errno / `data['text']` / 非 JSON 原文。换默认配置会把 4xx/5xx 变成 DioException，丢失百度侧错误细节。
7. **重试只覆盖传输层**：`CloudDriverException`（errno / 风控 / 非 JSON）绝不重试，网络异常才 1s/2s 退避、共 3 次尝试。保持这个二分，否则风控（errno 31023）会被反复触发加重。
8. **`ondup: 'fail'`**：filemanager 重名一律失败不覆盖——move / copy / rename 到已存在名字报 errno；上层 UI 应提示「目标已存在」而非笼统失败。
9. **get() 匹配的四个分支是隐藏能力**：`fsId.toString() == rawName` 意味着**路径末段可直接传 fs_id**；`decoded` 分支处理百分号编码文件名。重写时要么保留（并写进文档），要么明确删除，别无意识丢失。
10. **路径归一化别漏**：`_baiduPath` 折叠连续斜杠、去尾斜杠、保根 `'/'`；全部接口都先过它。`dir` 查询带尾斜杠 / 双斜杠会 errno。
11. **list 分页终止条件**：`list` 缺键按空处理（`is! List || isEmpty` → break），加上「长度 < 1000 即停」——两个条件防死循环。目录条数恰为 1000 整数倍时会多请求一次空页（正确但多一跳）。
12. **`server_mtime` 是秒**：`_toItem` 里 `* 1000` 换毫秒。重写时用错单位会得到 1970 年附近的时间。
13. **测试注入点在 `BaiduClient` 的 `dio` 参数**，驱动构造器不透传——重写时把 HTTP 注入抬到 `spec.create` / 驱动构造层，测试才能覆盖驱动层逻辑。
14. **本驱动无 `CloudDriverDataException`**：全部失败都是普通 `CloudDriverException`。若重写引入「内容不可用」判定（如直链 403 判死），需自行决定是否启用 DataException（base.dart:102-106：DataException = 重试无意义）。
15. **get() 对根路径返回无直链条目**：`get('/')` 直接返回 `CloudFileItem(name: '/', isDir: true)`——不触网。重写时别在根路径上尝试取直链。
