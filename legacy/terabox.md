# terabox 驱动功能规格（已作废 · 重写参考）

> **状态声明**：本驱动的既有实现已按维护者决定整体作废、待重写。本文档是该实现的
> 功能性规格档案，记录完整功能面供重写时对照；不代表仍受支持的行为，也不构成使用建议。
>
> **来源与版权声明**：本文档为独立整理的功能性规格，仅描述本项目自有实现的可观察行为
> 与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker 的任何源码或其
> 衍生内容**。

## 1. 标识

| 项 | 值 |
| --- | --- |
| typeId（provider_type 存库值） | `terabox` |
| displayName | `TeraBox` |
| Spec 类名 | `TeraboxSpec`（`const TeraboxSpec()`，extends `CloudDriverSpec`） |
| 驱动类名 | `TeraboxDriver`（extends `CloudDriver`） |
| 主文件 | `lib/services/cloud_drivers/terabox_driver.dart` |
| 测试文件 | `test/terabox_driver_test.dart` |
| 注册位置 | `lib/services/cloud_drivers/driver_registry.dart`（`TeraboxSpec()`） |

主文件内附属类与顶层函数（重写时的拆分参考）：

- `TeraboxAddition`：驱动配置（`cookie` / `rootFolderPath`），带 `fromJson` / `toJson`。
- `TeraboxFile`：`/api/list` 条目模型，`fromMap` 工厂。
- `TeraboxClient`：HTTP 客户端，持有 `baseUrl` / `urlDomainPrefix` / `jsToken`。
- `teraboxSign(String s1, String s2)`：签名函数（顶层）。
- `teraboxMtime(int serverMtime)`：秒 → `DateTime?`（顶层）。
- `teraboxPath(String p)`：路径规范化（顶层）。

## 2. 能力位

`TeraboxSpec.capabilities` = `AccountCaps.list | AccountCaps.read | AccountCaps.mkdir | AccountCaps.move | AccountCaps.copy | AccountCaps.delete`（六项全给）。

各位含义（`lib/models/account_capabilities.dart`）：`list = 1<<0`、`read = 1<<1`、`write = 1<<2`、`mkdir = 1<<3`、`move = 1<<4`（含改名）、`copy = 1<<5`、`delete = 1<<6`。`write` 一律不给（上传能力整体砍掉，产品决策）。

给满六项的依据：mkdir / move / rename / copy / remove 均为可用的真实实现，签名与请求构造没有加密卡点。

`runtimeCapabilities`：**无覆写**（继承基类默认 `null` → 用 spec 静态表）；`runtimeTypeLabel`、`isWrapper`、`dispose` 均用默认（非包装驱动、不持有跨请求资源）。

## 3. 表单字段

| key | 组件 | label | required | obscure | defaultValue | hint | 开关联动 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cookie` | `CloudDriverField` | Cookie | true | true | `''`（缺省） | 必填；从浏览器复制 TeraBox 的 Cookie；过期后需重新粘贴 | 无 |
| `root_folder_path` | `CloudDriverField` | 根目录路径 | false | false | `/` | 无 | 无 |

- 无开关字段、无 select / account 字段；表单仅这两项，顺序即界面顺序。
- `TeraboxAddition.fromJson`：`cookie` 缺省 `''`，`root_folder_path` 缺省 `/`（空串按 `/` 处理）。
- `secretFieldKeys` = `{cookie}`：由基类公式「obscure 字段键 ∪ runtimeSecretKeys」自动得出——本驱动唯一的密文就是 cookie。
- `runtimeSecretKeys` = **空集**（无覆写）：没有令牌轮换，驱动不通过 `onTokenUpdate` 写回任何凭证缓存键。`create()` 的 `onTokenUpdate` / `env`（`CloudDriverEnv`）参数均被接受但忽略（非包装驱动）。
- `root_folder_path` 仅为配置键名兼容而保留：实际「远程路径」挂在账号层（`CloudDriveService.joinRemotePath`），**驱动自身不消费该字段**——`TeraboxClient` / `TeraboxDriver` 全程不读 `rootFolderPath`。

## 4. 认证与令牌生命周期

**认证模型**：cookie 粘贴式。用户从浏览器复制 TeraBox Cookie（含 `ndus` 等会话字段）整体粘进表单；驱动原样放进 `Cookie` 请求头。无 OAuth、无刷新流程、无凭证写回。

- **init()**：`TeraboxDriver.init()` 仅调 `_client.checkLogin()`——`GET /api/check_login`（经 `request()` 自动带公共 query 与公共头）。`errno != 0` 抛错：`errno == 9000` → `'TeraBox is not yet available in this area (errno 9000)'`；其余 → `'Failed to verify TeraBox login status according to cookie (errno $errno)'`。错误文案为英文原文（语义如此，测试锁住原文透传）。
- **cookie 校验方式**：即 checkLogin 的 errno 判定。已知边界：非 JSON 响应（如失效 cookie 被重定向到登录页 HTML）不抛解析异常——`_decodeBody` 对非 JSON 返回空 map，errno 读作 0，checkLogin 视为通过；错误推迟到后续 list / get 暴露（测试锁定「不抛 JSON 解析异常」）。
- **无 token 轮换**：`ndus` 等凭证都在 cookie 字符串里，驱动不解析、不刷新、不持久化；cookie 过期 → 用户重新粘贴（表单 hint 明示）。
- **jsToken（进程内存态）**：`TeraboxClient.jsToken` 初始空串；`resetJsToken()` GET `baseUrl` 首页 HTML，两个正则依次尝试——① URL 编码字面量 ``function%20fn%28a%29%7Bwindow\.jsToken%20%3D%20a%7D%3Bfn%28%22([^"]+?)%22%29``（页面里这段被编码过）；② 宽松兜底 `jsToken\s*=\s*["']([^"']+)["']`。都拿不到留空串继续跑。errno ∈ `jsTokenErrors = {4000023, 450016}` 时重取 jsToken 并重试原请求，`retryLimit = 2`。
- **域名切换（进程内存态）**：默认 `baseUrl = 'https://www.terabox.com'`（`defaultBaseUrl`）、`urlDomainPrefix = 'jp'`。errno == -6 且响应头带 `url-domain-prefix`（Dio 头名小写）时改为 `baseUrl = 'https://$prefix.terabox.com'` 并重试，同样受 retryLimit 约束。切换结果不写回配置，实例重建即丢。
- **Dio 注入**：`TeraboxClient(this.addition, {Dio? dio})` 与 `TeraboxDriver({required addition, Dio? dio})` 都接受可选 Dio（测试注入 mock adapter 用）；缺省自建：

  ```dart
  Dio(BaseOptions(
    connectTimeout: Duration(seconds: 15),
    receiveTimeout: Duration(seconds: 60),
    headers: {'User-Agent': apiUA, 'Accept': acceptHeader,
              'Referer': defaultBaseUrl, 'X-Requested-With': xRequestedWith},
    validateStatus: (_) => true,   // 非 2xx 也读 body（errno / 原文都在 body）
    followRedirects: false,        // 直链那跳要自己读 Location
  ))
  ```

### 4.1 常量速查（重写直接照抄的值）

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `defaultBaseUrl` | `https://www.terabox.com` | 默认站点；errno -6 + `Url-Domain-Prefix` 响应头会改它 |
| `apiUA`（= `downloadUA`） | `terabox;1.37.0.7;PC;PC-Windows;10.0.22631;WindowsTeraBox` | API 请求与直链下载共用 |
| `jsTokenErrors` | `{4000023, 450016}` | jsToken 失效 / 需重取的错误码 |
| `retryLimit` | `2` | 重取 jsToken / 换域名的最大重试次数 |
| `acceptHeader` | `application/json, text/plain, */*` | 每个请求的 `Accept` |
| `xRequestedWith` | `XMLHttpRequest` | 每个请求的 `X-Requested-With` |
| `pageSize` | `100` | 列表分页页大小 |
| `statPageSize` | `1000` | `get()` 找单文件的页大小（单页） |
| 公共 query | `app_id=250528`、`web=1`、`channel=dubox`、`clienttype=0` | 所有 `/api/*` 请求都拼 |
| Dio 超时 | 连接 15s / 接收 60s | 仅缺省自建 Dio 时生效；注入 Dio 时由调用方负责 |

## 5. 接口实现逐条

### 5.0 通用请求构造（`TeraboxClient.request`）

- Query 公共参数：`app_id=250528`、`web=1`、`channel=dubox`、`clienttype=0` + 业务 `params`；`jsToken` 非空时附加。
- Headers：`Cookie`（addition.cookie）、`Accept`、`Referer: baseUrl`（随域名切换变化）、`User-Agent: apiUA`、`X-Requested-With: XMLHttpRequest`；`form` → `Content-Type: application/x-www-form-urlencoded`，`jsonBody` → `application/json`。
- `responseType: ResponseType.plain`，body 由 `_decodeBody` 手工 jsonDecode。
- `DioException` → `CloudDriverException('TeraBox 请求失败 [$method ${Uri.parse(full).path}]：${e.message ?? e.type.name}', e)`。
- 重试：errno ∈ jsTokenErrors → `resetJsToken()` 后重试；errno == -6 且有域名前缀头 → 换域重试；各最多 `retryLimit = 2` 次（`retryCount` 递归传递）。

### 5.1 list(path)

- 端点：`GET /api/list`，params `dir=<规范化路径>` / `page=<1..>` / `num=100`（`pageSize`）。
- 分页：`for (var page = 1;; page++)`，`body['list']` 非 List 或为空即停——**必须翻到空页**，不按 total 判断。
- `errno == 9000` → `CloudDriverException('TeraBox is not yet available in this area')`。
- 解析：每项 `Map` → `TeraboxFile.fromMap`：`fs_id`（num→int，缺省 0）、`path`、`server_filename`、`size`、`isdir`（1=目录 0=文件）、`server_mtime`（Unix **秒**）。
- 映射 `CloudFileItem`：`name` = `serverFilename` 非空则用之、否则 `cloudBasename(path)`（`_nameOf`）；`isDir` = `isdir == 1`；`size`；`modified` = `teraboxMtime(serverMtime)`（秒×1000，`<= 0` 回落 `DateTime.now()`）。**列表条目不带 rawUrl / rawHeaders**。

### 5.2 get(path)

- `teraboxPath(path) == '/'` → 直接返回 `CloudFileItem(name: '/', isDir: true)`，**不出网**。
- `cloudDirname` / `cloudBasename` 拆出父目录与文件名 → `GET /api/list`，params `dir=parent` / `page=1` / `num=1000`（`statPageSize`，**只拉单页**）。
- `errno == 9000` → 同 list 的地区不可用错误。
- 在返回 list 中按 `serverFilename == fileName` 线性匹配；找不到 → `CloudDriverException('file not found: $fileName')`。
- 命中目录 → 直接 `_toItem`（无直链，不出 `/api/download`）。
- 命中文件 → `linkOfficial(fsId)` → `CloudFileItem(name, isDir: false, size, modified, rawUrl: link.url, rawHeaders: link.headers)`。拿不到直链时由 linkOfficial 抛带真实原因的 `CloudDriverException`（契约：文件条目必须带 rawUrl）。

### 5.3 mkdir(path)

- `POST /api/create`，query `a=commit`；form：`path=<规范化路径>` / `isdir=1` / `block_list=[]`（createDir）。

### 5.4 rename(path, newPath)

- `manage('rename', [{'path': teraboxPath(newPath), 'newname': cloudBasename(dst)}])`。
- TeraBox 的 rename opera 自带 `path`，**跨目录移动+改名一次请求完成**（目标目录体现在 path 上）——与百度 filemanager 的 `move`+`newname` 模式不同，别误拆成两次请求。

### 5.5 remove(path)

- `manage('delete', [teraboxPath(path)])`——filelist 是**路径字符串数组**（不是对象数组）。

### 5.6 move(srcPath, dstDir, newName) / copy(srcPath, dstDir, newName)

- `manage('move'|'copy', [{'path': teraboxPath(srcPath), 'dest': teraboxPath(dstDir), 'newname': newName}])`。

### 5.7 manage()（写操作共用）

- `POST /api/filemanager`；query：`onnest=fail`、`opera=<opera>`；form-urlencoded body：`async=0`、`filelist=<jsonEncode(filelist)>`、`ondup=newcopy`。
- **filelist 是 JSON 字符串再被表单编码一次（双重编码）**。

### 5.8 签名与直链（`genSign` / `linkOfficial` / `teraboxSign`）

1. `genSign()`：`GET /api/home/info` → `data.sign1` / `data.sign3`；`data` 非 Map 或任一为空 → `CloudDriverException('Failed to get TeraBox sign keys from home/info')`。`data.timestamp` 在响应里但**不参与签名**。返回 `teraboxSign(sign3, sign1)`（sign3 当密钥、sign1 当明文）。
2. `GET /api/download`，params：`type=dlink`、`fidlist=[$fsId]`、`sign=<genSign()>`、`vip=2`、`timestamp=<当前 Unix 秒>`。三者都只是普通查询参数，无加密。
3. `_firstDlink(body)`：依次尝试 `body['dlink'][0]['dlink']` 与 `body['info'][0]['dlink']` 两种响应形态；两种都无 → `CloudDriverException('TeraBox fid $fsId no dlink found (errno: ${_errnoOf(body)})')`。
4. dlink → `_dio.get<List<int>>` **不跟随**请求一次（`followRedirects: false`、`validateStatus: (_) => true`、`responseType: ResponseType.bytes`，headers 仅 `Cookie` + `User-Agent: downloadUA`），读响应头 `location`；非空用 Location，否则**回落 dlink 本身**；`DioException` → `CloudDriverException('TeraBox 直链重定向失败（fid $fsId）：…', e)`。
5. 返回 `(url, headers: {'User-Agent': downloadUA})`。

**`teraboxSign` 算法**：RC4 式——`s1`（sign3）做 KSA（`a[q] = s1.codeUnitAt(q % v)` 填 256 项，再 256 轮交换置换 `p`），`s2`（sign1）做 PRGA 异或（`o.add((s2.codeUnitAt(q) ^ k) & 0xFF)`），输出 base64。**没有 MD5 / SHA1 / AES**。`codeUnitAt` 按 UTF-16 码元取值（输入 sign1/sign3 均为 ASCII，与字节语义等价）；异或结果按无符号字节（`& 0xFF`）收集。`s1` 空串 → `CloudDriverException('TeraBox 签名失败：sign3 密钥为空（服务端 /api/home/info 未返回 sign3）')`（空密钥无法产出有效签名，直接报错）。

> **勘误（对历史任务描述）**：历史任务描述曾称本驱动「有 MD5 签名」——实际签名即上述 RC4 式 KSA+PRGA 异或 + base64，全程不需要 MD5（旧描述有误，勿据此实现）。

### 5.9 错误翻译汇总

- 全部失败路径抛 `CloudDriverException`（网络、签名密钥缺失、file not found、无 dlink、9000 地区不可用、直链重定向失败）。
- **本驱动不使用 `CloudDriverDataException`**（无解密 / 内容损坏类失败，该异常只在密钥学/数据损坏语义下使用）。

## 6. 直链与请求头

- **rawUrl 来源**：`/api/download` 的 dlink → 不跟随 GET 的 `Location` 响应头（无 Location 时回落 dlink 本身）。
- **有效期 / 缓存**：实现未记录直链有效期；**不做任何直链缓存、也不缓存 sign**——每次 `get()` 都完整走「home/info 取 sign → /api/download → dlink 重定向」三跳。`dispose()` 未覆写（无资源可释放）。
- **rawHeaders（交给下载器的头）**：仅 `{'User-Agent': downloadUA}`——**不带 Cookie / Referer**。
- **UA 常量**：`apiUA = downloadUA = 'terabox;1.37.0.7;PC;PC-Windows;10.0.22631;WindowsTeraBox'`（直链下载也必须带）。
- dlink 那一跳（取 Location 时）请求头：`Cookie` + `User-Agent: downloadUA`，`ResponseType.bytes`（避免把整包内容读进内存）。

## 7. 特殊机制与取舍（设计决策）

1. **砍掉全部上传逻辑**：`put` / precreate / superfile2 分片 / `/api/precreate`、`/api/create` 的上传形态——上传能力整体砍掉（产品决策）。
2. **crack 下载 API 整个砍掉**：`download_api` 类配置不进表单；`linkCrack` / `/api/filemetas` 不实现；**恒走官方 dlink 通路**（`linkOfficial`）。
3. **`/api/download` 响应两种形态都认**（`dlink` 数组 / `info` 数组，`_firstDlink`）——线上不同区域两种都出现过。
4. **get() 拿不到直链抛异常而非返回无直链条目**：`CloudDriver.get` 契约要求文件条目必须带 `CloudFileItem.rawUrl`，故抛带真实原因的 `CloudDriverException`。
5. **`order_by` / `order_direction` / `only_list_video_file` 不进表单**（客户端自己排序）。
6. **签名无标准加密原语**：RC4 式算法纯 Dart 实现，无 MD5 / SHA / AES 依赖（历史任务描述曾误称「MD5 签名」，见 §5.8 勘误）。
7. **mtime 回落当前时间**：`server_mtime` 为 0 / 缺失时给 `DateTime.now()` 而非 null——产品观感：列表里时间永不为空。
8. **非 JSON body 不抛**：`_decodeBody` 解析失败返回空 map，errno 读作 0，错误由调用方按各自语义抛。
9. **空密钥签名明确报错**（数学上无法产出有效输出，静默继续没有意义）。
10. **`root_folder_path` 仅键名兼容**：实际远程路径在账号层；驱动不消费（§3）。
11. **jsToken 双正则抓取**：第一个匹配 URL 编码字面量，第二个宽松兜底；抓不到留空继续跑。
12. **errno -6 域名切换**：读 `url-domain-prefix` 响应头换 `baseUrl` 重试，进程内存态。
13. **timestamp 不参与签名**：签名只用 sign3（密钥）+ sign1（明文）。

## 8. 行为契约（既有测试套件锁定，重写必须保持）

测试手法：全部不打真网络——自定义 `HttpClientAdapter`（`_RoutingAdapter`）按 host 分流（`terabox.com` 全域 → 本地 responder，其余 404），记录每次请求的 method / 完整 URI / body / headers（`_Hit`）。缺省 responder 404 以暴露漏配端点。

**group 1 · cookie 失效错误原文透传**

- `check/login` errno != 0 → `CloudDriverException`，message 同时含 `'Failed to verify TeraBox login status'` 与 `'errno -6'`。
- errno -6 + 响应头 `url-domain-prefix: us` → 换域名重试一次（共 2 次请求）；重试后 `urlDomainPrefix == 'us'`、`baseUrl == 'https://us.terabox.com'`。
- 非 JSON 响应（`<html>login page</html>`）→ `checkLogin()` **不抛**（errno 读作 0）。

**group 2 · 列表解析**

- 分页：第 1 页满 100 条（触发翻页）、第 2 页 2 条、第 3 页空 → 共 3 次请求、102 条；`page` 序列 `['1','2','3']`、每页 `num=100`、`dir` 透传。`isdir === 1` 判目录；`1700000000` 秒 → 对应 DateTime（用 `toUtc` 比较，避开本地时区 isUtc 标记假失败）。
- 驱动 `list('/Music')` → `page` 序列 `['1','2']`（有数据必须再拉一页确认空）；映射 `CloudFileItem`（albums 目录 / song.flac size=4096 / modified）；**列表条目 `rawUrl` 为 null**。
- 公共 query 与头：`app_id=250528`、`web=1`、`channel=dubox`、`clienttype=0`、`Cookie`、`User-Agent == apiUA`、`X-Requested-With: XMLHttpRequest`、`Referer == defaultBaseUrl`。

**group 3 · errno 9000 地区不可用**

- `listDir` / `checkLogin` / `driver.get('/Movies/a.mkv')` 三处均抛 message 含 `'not yet available in this area'` 的 `CloudDriverException`。

**group 4 · 直链两种 dlink 形态**

- 形态 A（`dlink` 数组）/ 形态 B（`info` 数组）都能解析出 Location 直链；返回 headers `{'User-Agent': downloadUA}`。
- `/api/download` query 断言：`type=dlink`、`fidlist=[98765]`、`vip=2`、`sign == 'RF9iI+bxb964'`（固定向量：sign3=`sign3key`、sign1=`sign1data`）、`timestamp` 可 `int.tryParse`。
- 两种形态都不认（`errno:-9, dlink:[]`）→ 抛含 fid（`777`）与 errno（`-9`）的异常。
- `home/info` 缺 sign1/sign3 → message 含 `'sign keys'`。
- dlink 不重定向（无 Location）→ 回落 dlink 本身。

**group 5 · get()：文件必须带直链**

- 文件：`/api/list` 断言 `dir == '/Movies'`（父目录）、`num == '1000'`（statPageSize 单页）；返回 `rawUrl`（Location 值）+ `rawHeaders == {'User-Agent': downloadUA}` + name/size。
- 目录：不出任何 `/api/download` 请求，`rawUrl` 为 null。
- 根路径 `/`：**零网络请求**，返回目录条目。
- 找不到条目 → `'file not found: missing.mkv'`（不返回无直链条目）。
- 文件但直链拿不到（home/info data 空 → 签名失败）→ `CloudDriverException`。

**group 6 · 写操作方法 / 路径 / 参数**

- mkdir → `POST /api/create`，query `a=commit`，form `path='/Movies/New Folder'` / `isdir='1'` / `block_list='[]'`，Content-Type 含 `application/x-www-form-urlencoded`。
- rename → `/api/filemanager`，query `opera=rename`、`onnest=fail`，form `async='0'`、`ondup='newcopy'`，`filelist` JSON 为 `[{'path': '/Movies/new.mkv', 'newname': 'new.mkv'}]`。
- rename 跨目录（`/A/old.mkv` → `/B/Sub/new.mkv`）→ 一次请求，filelist 的 `path` 用**目标全路径**。
- remove → `opera=delete`，filelist 为路径字符串数组 `['/Movies/gone.mkv']`。
- move / copy → filelist 为 `[{'path', 'dest', 'newname'}]`。
- 路径规范化：`'//A//B//c.mkv/'` → `'/A/B/c.mkv'`。

**group 7 · 签名金标向量**（两份独立实现交叉验证逐字节一致后固化）

- `teraboxSign('sign3key', 'sign1data') == 'RF9iI+bxb964'`。
- 单字节密钥（k 恒为 0x61）：`('b','a') == 'PA=='`、`('b','X') == 'BQ=='`、`('b','\u0000') == 'XQ=='`。
- 空明文 → `''`。
- 多字节向量（锁「无符号字节收集」）：`('abc','hello world') == 'pfi1RTf/mhxeiws='`；`('0123456789abcdef','The quick brown fox') == '0AAleYw7yfti1jjsr+Q9ZYSCUA=='`。
- 空密钥 → 抛 `CloudDriverException`。
- 相同输入稳定可复现。

## 9. 重写注意事项（从实现提炼的陷阱）

1. **签名不是 MD5**：是 RC4 式 KSA+PRGA 异或 + base64；勿引入 crypto 依赖，也勿照「MD5 签名」的旧描述实现。
2. **UTF-16 码元语义**：`codeUnitAt` 按 UTF-16 码元取值（ASCII 输入下与字节语义等价）；异或结果必须 `& 0xFF` 无符号收集再 base64（group 7 多字节向量专门锁此点）。
3. **get() 单页 num=1000 的查找上限**：父目录超过 1000 条时目标文件找不到（当前为单页查找，无翻页兜底）——重写可考虑翻页。
4. **列表翻页必须翻到「list 为空」才停**：不是按 total；mock 测试必须按 page 返回，否则驱动永远翻下去。
5. **filelist 双重编码**：JSON 字符串作为 form 字段值再被表单编码一次；断言时先 `Uri.splitQueryString` 再 `jsonDecode`。
6. **直链三跳零缓存**：每次 get() = home/info（取 sign）+ /api/download + dlink 重定向；sign 也不缓存。频繁 get 同一文件的场景重写应考虑缓存（注意直链有效期未记录）。
7. **域名切换 / jsToken 均为进程内存态**：多实例不共享、重启即丢；重试上限 2 次。
8. **非 JSON 响应 errno=0 的「假成功」**：checkLogin 对 HTML 登录页会通过，错误延迟到 list/get 才暴露——重写需权衡是否在 init 就校验 body 形态。
9. **errno 9000 必须三处都认**：listDir、checkLogin、get 的 /api/list 调用各自独立判断。
10. **`validateStatus: (_) => true` + `followRedirects: false` 是硬需求**：errno 在 body 里；直链靠手动读 Location；dlink 跳用 `ResponseType.bytes` 防止整包读入内存。
11. **Referer 用当前 baseUrl**（域名切换后随之变化），不是固定 `www.terabox.com`。
12. **mtime 0 → `DateTime.now()`**（非 null）：对 mtime 断言具体值的测试会 flaky；跨时区比较用 `toUtc`。
13. **列表条目永不带直链**（`rawUrl == null`）；只有 `get()` 的文件条目带 `rawUrl + rawHeaders`。
14. **rawHeaders 只有 User-Agent**；Cookie 只在「dlink → Location」那一跳需要，不在最终下载头里。
15. **`teraboxPath` 规范化**：折叠重复斜杠、去尾斜杠、根为 `/`；写操作路径（含 rename 的目标全路径）都要先过它。
16. **rename 跨目录一次请求完成**：TeraBox rename 自带 `path`，与百度 filemanager 的 `move`+`newname` 两段式不同；跨目录语义别误拆成两次请求。
17. **cookie 是整串粘贴**：驱动不解析 `ndus` 等字段、无刷新；过期处理 = 用户重贴（UI hint 已说明），重写若做 cookie 健康检查需自行加。
