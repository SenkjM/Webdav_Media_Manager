# netease_music 驱动功能规格（已作废 · 重写参考）

> **状态声明**：本驱动的既有实现已按维护者决定整体作废、待重写。本文档是该实现的
> 功能性规格档案，供重写时对照。全部事实来自本项目的驱动实现、加密模块与测试套件。
>
> **来源与版权声明**：本文档为独立整理的功能性规格，仅描述本项目自有实现的可观察行为
> 与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker 的任何源码或其
> 衍生内容**。

## 1. 标识

| 项 | 值 |
|---|---|
| typeId | `netease_music` |
| displayName | `网易云音乐` |
| Spec 类 | `NeteaseMusicSpec`（`const` 构造，`lib/services/cloud_drivers/netease_music_driver.dart`） |
| 驱动类 | `NeteaseMusicDriver`（同文件） |
| 配置类 | `NeteaseMusicAddition`（默认值沿用既有实现） |
| API 客户端 | `NeteaseMusicClient` |
| 条目模型 | `NeteaseSong` |
| 主文件 | `lib/services/cloud_drivers/netease_music_driver.dart` |
| 加密模块 | `lib/services/cloud_drivers/netease_music_crypto.dart` |
| 测试 | `test/netease_music_driver_test.dart`、`test/netease_music_crypto_test.dart` |
| 注册 | `lib/services/cloud_drivers/driver_registry.dart` 的 `kCloudDriverSpecs`，排在末位（用户决定：netease_music 为并行收编的独立驱动放最后；crypt 原在其后，现已通过外部包实现版权隔离，注册表不再包含内置 crypt spec） |

## 2. 能力位

```dart
int get capabilities => AccountCaps.list | AccountCaps.read | AccountCaps.delete;
```

- `list`（1<<0）/ `read`（1<<1）/ `delete`（1<<6）三位开启。
- **没有** mkdir / move / copy 位：网易云盘本身不提供这些操作（对应方法均为可读错误的
  NotSupport 桩）；禁用即隐藏。
- **没有** write 位：上传能力整体砍掉（产品决策）。
- `runtimeCapabilities` 未覆写（基类默认 `null` = 用 spec 静态表）；`runtimeTypeLabel`
  同样未覆写。`dispose()` 未覆写（不持有跨请求资源）。
- `CloudDriverDataException` 本驱动**不使用**（无解密层）；所有失败都是
  `CloudDriverException`。

## 3. 表单字段

| key | 类型 | label | required | obscure | 默认值 | 开关联动 |
|---|---|---|---|---|---|---|
| `cookie` | `CloudDriverField` | Cookie | **true** | **true** | `''` | 无 |
| `song_limit` | `CloudDriverField` | 歌曲数量上限 | false | false | `'200'`（`kDefaultSongLimit`） | 无 |

- `cookie` 的 hint：必填；需含 `__csrf` 与 `MUSIC_U`；登录 music.163.com 后从开发者工具
  复制完整 Cookie。
- `song_limit` 的 hint：默认 200；网易云盘接口按此上限一次列取。
- 无 select / switch / account 字段，无任何开关联动（`visibleWhenSwitch` 等全空）。

**secretFieldKeys**：基类合成 = obscure 字段 ∪ `runtimeSecretKeys` = `{'cookie'}`。
**runtimeSecretKeys**：保持基类默认**空集**——该驱动无令牌轮换。`create()` 注释：
「Cookie 是唯一凭证，网易不轮换它，因此没有 onTokenUpdate 通道」。

## 4. 认证与加密

### 4.1 init() 与 Cookie 认证

- `NeteaseMusicDriver.init()` 仅转发 `_client.init()`。
- `NeteaseMusicClient.init()`：用正则 `'$name=([^(;|$)]+)'` 从 `addition.cookie` 取
  `__csrf` 与 `MUSIC_U`；任一为空即抛 `CloudDriverException`（提示网页版登录后从
  开发者工具复制完整 Cookie）。不发任何网络请求（测试断言 `adapter.hits` 为空）。
- `initialized` getter：两个字段都非空。Cookie 值本身可以含 `=`（正则按 `;`/`$` 截断）。
- 额外 Cookie（如 `os=pc`）在请求时**追加**在配置 Cookie 之后（`; k=v` 形式，`_cookieHeader`）。

### 4.2 加密算法清单（netease_music_crypto.dart）

**weapi**（`neteaseWeapi`，`WeapiResult{params, encSecKey}`）：

1. 明文 = `jsonEncode(data)`（`Map<String, String>`，插入顺序）。
2. 第一层：`AES-CBC(明文, presetKey, iv)`，PKCS7 补齐。
3. 第二层明文 = 内层结果的 **base64 字符串**（关键语义，见 §7.1）。
4. 第二层：`AES-CBC(base64 串, 随机密钥的逆序, iv)` → base64 = `params`。
5. 随机密钥 16 字节（字符集 `kNeteaseStdChars` 62 字符）→ **raw RSA**（无填充）：
   128 字节缓冲、密钥放**末 16 字节**、前 112 字节为零，`c = m^65537 mod n`，输出定长
   128 字节 → 小写 hex 256 字符 = `encSecKey`（加密的是**原始**密钥，第二层用的是逆序）。
- 常量：`kNeteasePresetKey='0CoJUm6Qyw8W8jud'`、`kNeteaseIv='0102030405060708'`、
  `kNeteaseRsaModulusHex`（1024 位）、`kNeteaseRsaExponent=65537`、
  `kNeteaseRsaPublicKeyPem`（PEM 形式公钥，仅测试核对 modulus 用）。
- 辅助原语：`neteaseAesKeyPending`（密钥补零到 16/24/32，超 32 截断）、`pkcs7Pad`、
  `aesCbcEncrypt`、`aesEcbEncrypt`（逐块手动循环）、`bigIntToBytes`、
  `neteaseSecretKey`（返回 `(key, reversed)` record）。

**linuxapi**（`neteaseLinuxapi`）：

- 明文 = `jsonEncode({url, method:'POST', params})`；`AES-ECB(linuxapiKey)` →
  **大写** hex = 表单字段 `eparams`。密钥 `kNeteaseLinuxApiKey='rFgB&h#%2?^eDg:Q'`。

### 4.3 Dio 注入与请求管道（`NeteaseMusicClient.request`）

- 构造：`NeteaseMusicClient(addition, {Dio? dio})`——可选注入（测试用）；默认自建
  `Dio(BaseOptions(connectTimeout: 15s, receiveTimeout: 60s, headers: {'User-Agent': apiUA},
  validateStatus: (_) => true))`。`validateStatus` 全放行是为了「非 2xx 也回来读 body」
  ——报错翻译需要读到网易的 `code`。
- `request(url, {crypto, data, cookies})` 流程：
  1. 目标含 `music.163.com` 时带 `Referer: https://music.163.com`。
  2. `crypto=='weapi'`：`neteaseWeapi(data).toForm()`（`params` + `encSecKey`），
     URL 经 `_rewriteApiSegment(target,'weapi')`（正则 `/\w*api/` → `/weapi/`；
     对现有三个端点是恒等变换）。
  3. `crypto=='linuxapi'`：载荷 = `{url: _rewriteApiSegment(target,'api'), method:'POST',
     params: data}`，`neteaseLinuxapi` 加密；**覆写** `User-Agent = linuxApiUA`；实际
     POST 到 `https://music.163.com/api/linux/forward`。
  4. 其它 crypto 值抛 `CloudDriverException('未知的加密方式：$crypto')`。
  5. POST 为 `application/x-www-form-urlencoded` + `ResponseType.plain`，手工
     `jsonDecode`（失败 → 非 JSON 错误）。
- UA 常量：`apiUA`（Chrome/142 系浏览器 UA 串，含 `OpenList/425.6.30` 版本后缀——
  既有实现的既定值）；`linuxApiUA`（X11 Linux Chrome/60；linuxapi 请求必须覆写为该
  UA，为既定要求）。
- 端点常量：`cloudGetUrl='https://music.163.com/weapi/v1/cloud/get'`、
  `songUrlApi='https://music.163.com/api/song/enhance/player/url'`、
  `cloudDelUrl='http://music.163.com/weapi/cloud/del'`（**http**，历史行为逐字节保留）、
  `linuxApiForward`、`referer`。

## 5. 接口实现逐条

### 5.1 list（`weapi/v1/cloud/get`）

- 端点/方法：POST `cloudGetUrl`，crypto `weapi`，data `{'limit': '$songLimit', 'offset': '0'}`，
  cookies `{'os': 'pc'}`（追加在配置 Cookie 后）。
- 响应解析：`body['data']` 非 List → 空数组；每个元素经 `NeteaseSong.fromMap`：
  `fileName`→name、`songId`、`fileSize`→size、`addTime`（**毫秒**）→modified
  （0 → null，不伪造时间）；`simpleSong.al.picUrl`→picUrl（解析进 `NeteaseSong` 但
  `_toItem` 不映射——`CloudFileItem` 无对应字段）。缺 `fileName` / `songId` 的条目
  **跳过**（`fromMap` 返回 null），不整体失败。
- 映射到 `CloudFileItem`：全部 `isDir: false`。
- 平铺语义：**忽略 path**，任意路径都返回全部歌曲。网易云盘是单层云盘（只有歌曲
  文件，没有目录树）。
- 分页：无翻页——offset 恒 `'0'`，一次按 `song_limit` 列取。缓存：**无**，每次现拉。
- 错误翻译：见 §5.5。

### 5.2 get（定位 + `linuxapi` 直链）

- 根路径（`'/'` / 空 / basename 空）→ 返回 `CloudFileItem(name: '/', isDir: true)`
  目录占位，**不出网**。
- 否则 `cloudBasename(path)` 取文件名 → `_findByName`（重新 `getSongObjs(songLimit)`
  全量列表后按 `fileName` 精确匹配）→ 找不到抛 `CloudDriverException('文件不存在：$name')`
  （不再发直链请求）。
- 找到后 `getSongLink(songId)`：POST `songUrlApi`，crypto `linuxapi`，data
  `{'ids': '[$id]', 'br': '999000'}`，cookies `{'os': 'pc'}`；实际打到
  `/api/linux/forward` 并带 `linuxApiUA`。响应 `data[0].url`；`data` 非 List / 空 /
  `url` null / 空 → 抛 `CloudDriverException('网易云音乐未返回播放链接（可能是 VIP /
  版权受限 / 已下架的歌曲）')`。
- 返回 `CloudFileItem(name, isDir: false, size, modified, rawUrl: url, rawHeaders:
  {'User-Agent': apiUA})`。
- 「远程路径是纯虚拟前缀」：驱动只认文件名，`/netease/prefix/target.mp3` 与
  `/target.mp3` 等价（改远程路径不会让条目失联）。

### 5.3 remove（`weapi/cloud/del`）

- 根路径 → `CloudDriverException('网易云音乐不支持删除根目录')`（不出网）。
- `_findByName` 定位（先拉一次全量列表）→ 找不到抛 `文件不存在`（不发删除请求）。
- `removeSong(songId)`：POST `cloudDelUrl`（**http**），crypto `weapi`，data
  `{'songIds': '[$id]'}`；**不追加 `os=pc`**（只有列表与直链请求加——行为契约明确
  锁定这一点）。
- 响应只需过 `_throwOnApiError`（code 校验），无其它解析。

### 5.4 mkdir / rename / move / copy（NotSupport 桩）

- 四个方法全部 `async => throw _unsupported(...)`，消息形如
  `网易云音乐云盘不支持新建文件夹（该网盘未提供此操作）`（重命名/移动/复制同式）。
- 实现形态：返回**失败的 Future** 而不是同步 throw——`async` 之外的同步抛出会绕过
  `await` / `expectLater` 的错误通道，调用方拿不到可读原因。这是重写时必须保持的
  陷阱级细节。

### 5.5 错误翻译汇总（全部为 `CloudDriverException`）

| 条件 | 消息要点 |
|---|---|
| Cookie 缺 `__csrf` / `MUSIC_U` | 提示网页版登录复制完整 Cookie |
| `DioException` | `网易云音乐请求失败：…`（`_short` 截 300 字符） |
| 响应非 JSON | `…非 JSON 响应（HTTP <status>）` + 片段 |
| JSON 非 Map | `…非预期结构` |
| `code` 存在且非 200，且 code 为 301 / 250 | `登录态已失效（code …）… Cookie 可能已过期，请重新登录` |
| `code` 其它非 200 值 | `网易云音乐接口报错（code …：message）` |
| 未知 crypto 值 | `未知的加密方式：…` |
| get/remove 找不到文件 | `文件不存在：<name>` |
| 直链缺失 | `未返回播放链接（可能是 VIP / 版权受限 / 已下架的歌曲）` |

### 5.6 保存前校验（verify）

- `NeteaseMusicClient.verifyLogin()`：`init()` + `getSongObjs(1)`——拉一次 limit=1 的
  真实列表，确认 Cookie 在服务端可用（不只是格式对；对齐「真连成功才保存」的语义）。
- `NeteaseMusicSpec.verify` 覆写为 `create(...)` 后调 `client.verifyLogin()`（真连），
  而非基类默认的 `create().init()`。

## 6. 直链与请求头

- **rawUrl 来源**：linuxapi `player/url` 响应 `data[0].url`（网易 CDN 地址，如
  `http://m801.music.126.net/...`）。
- **有效期 / 缓存**：实现层面**无缓存、无有效期管理**——每次 `get()` 都先拉全量列表
  定位、再现取直链。VIP / 版权受限 / 已下架歌曲拿不到链接时抛可读错误而非返回空 URL。
- **rawHeaders**：`{'User-Agent': NeteaseMusicClient.apiUA}`，仅此一项。直链由网易
  CDN 直接提供，无需 Referer / Cookie。
- **Link parsed / RangeReader 语义不实现**：依赖服务端代理端点，对端客户端里无对应物。

## 7. 特殊机制与取舍（设计决策）

1. **weapi 第二层明文用内层 base64 字符串**（关键语义）：不是内层密文原始字节；
   金标向量 + 手工重算双重锁定。
2. **拿不到直链时抛真实原因**：`CloudDriver.get` 契约要求文件条目必须带 `rawUrl`，
   静默返回空 URL 会让客户端下游必然失败且无从排查。
3. **校验响应 `code`**：`code` 存在且非 200 时报错；301 / 250 专门识别为登录态失效
   （否则 Cookie 失效表现为「空列表」，保存校验与浏览都给不出可读原因）。
4. **RSA 输出补足到 128 字节**（长度恒定 256 hex）；服务端按大整数解析，去前导零的
   短输出也等价，但定长输出更稳。
5. **JSON 键顺序无语义**（服务端把明文当 JSON 解析）；本实现按插入顺序序列化，
   测试对两种顺序向量都锁定。
6. **上传不实现**：上传能力整体砍掉（产品决策）。
7. **`.lrc` 歌词条目不实现**：本应用的播放链路不消费远端歌词。
8. **`Link` 的 `parsed` / `RangeReader` 不实现**：依赖服务端代理端点，对端客户端
   无对应物。
9. **单层平铺 + 文件名定位**：网易云盘无目录树；list 忽略路径，get / remove 按
   `fileName` 在全量列表里定位。远程路径是纯虚拟前缀，改路径不失联。
10. **无缓存设计**：每次 list / get / remove 都重新拉取全量歌曲列表（上限
    `song_limit`）；实现简单但意味着 remove 后紧跟 list 立即反映删除。
11. **picUrl 解析但不消费**：`NeteaseSong.picUrl` 从 `simpleSong.al.picUrl` 解析，
    但 `_toItem` 不映射到 `CloudFileItem`（无对应字段）。

## 8. 行为契约（既有测试套件锁定，重写必须保持）

### 8.1 test/netease_music_driver_test.dart（9 组 34 用例；自定义 `_FakeAdapter`
按闭包产出响应，不出真网络，记录 method/uri/headers/body）

- **spec 与能力遮罩（3）**：typeId / displayName / 注册表 `cloudDriverSpec()` 可查；
  caps 恰为 list|read|delete（mkdir/move/copy/write 全无）；表单 cookie 必填且
  obscure、song_limit 默认 `'200'`。
- **登录态（5）**：`__csrf`+`MUSIC_U` 通过（值可含 `=`）；缺任一 / 空 Cookie →
  `CloudDriverException` 且**零出网**。
- **列表（7）**：请求形状（POST `/weapi/v1/cloud/get`、host music.163.com、Cookie 含
  `MUSIC_U` 与追加的 `os=pc`、Referer、表单体恰为 `params`+`encSecKey`、encSecKey
  256 字符、params 合法 base64）；条目映射（name/isDir=false/size/modified 毫秒）；
  limit 进请求体（不同 limit → 不同密文）；平铺（`/` 与 `/whatever/deep` 同结果）；
  空列表 / 缺 `data` → 空数组；缺 `fileName`/`songId` 条目跳过；`addTime:0` →
  modified null。
- **取单条与直链（6）**：按文件名定位后直链请求打到 `/api/linux/forward` 且 UA=
  `linuxApiUA`、Referer 在、表单体仅 `eparams` 且大写 hex；`rawUrl`/`rawHeaders`
  正确；远程路径只当 basename 前缀；根路径 get → 目录占位零出网；文件不存在 →
  可读错误且只发列表请求（1 hit）；`data` 空 / `url` null → 「未返回播放链接」。
- **删除（3）**：按名字找到 songId 后 POST `/weapi/cloud/del`（weapi 表单体），
  Cookie **不含** `os=pc`；不存在 → 报错只发 1 个请求；根路径删除 → 拒绝零出网。
- **未实现操作（1）**：mkdir/rename/move/copy 全部抛可读错误且零出网。
- **错误原文透传（3）**：code 301 → 消息含 `301` 与 `Cookie`；code -460 → 含 code 与
  message；非 JSON（502 html）→ 含「非 JSON」与状态码。
- **保存前真连校验（4）**：`verifyLogin` 拉一次 `/weapi/v1/cloud/get`；服务端 301 →
  抛可读错误（不落库）；Cookie 形态不对 → 零出网即失败；`spec.verify` 覆写在
  形态不对时抛 `CloudDriverException`。
- **配置解析（2）**：`fromJson` 默认 200、字符串/整数 `'50'`/50 均解析为 50、
  `'abc'`/`'0'`/`-5`/null 回默认 200；`toJson` 往返一致。

### 8.2 test/netease_music_crypto_test.dart（5 组 21 用例；金标向量 = 固定随机密钥
`'0123456789abcdef'` 下的确定性输出）

- **RSA 公钥（2）**：modulus 以 `kGoldenModulusHex` 为准（256 hex / 128 字节）、
  指数 65537；PEM 形式公钥解析出的 modulus 与之一致。
- **AES 原语（4）**：CBC（预设密钥+固定 IV，明文 `{"limit":"200","offset":"0"}`）
  匹配 `kGoldenAesCbcPreset`；ECB（linuxapi 密钥，player/url 完整 JSON）匹配大写
  hex 向量；PKCS7（15→16、16→32、空→16、补齐值=补齐长度）；`aesKeyPending`
  （补零到 16/24/32、40→32、短密钥补零非循环）。
- **raw RSA（4）**：固定密钥匹配 `kGoldenRsaRawHex`；输出恒 128 字节（随机密钥亦然）；
  密钥非 16 字节 → `ArgumentError`；末 16 字节布局 ≡ 直接对小整数做 `m^65537 mod n`
  模幂（手工等价验证）。
- **weapi 完整输出（8）**：cloud/get 与 cloud/del 的 `params`/`encSecKey` 匹配金标；
  encSecKey 恒 256 小写 hex；params 合法 base64 且长度 %16==0；每次调用 params 与
  encSecKey 都不同（随机密钥）；随机密钥字符集限于 62 字符 `stdChars`；第二层必须用
  **逆序**密钥（误用原始密钥则与向量不符）；第二层明文是内层 **base64 字符串**
  （手工重算 `AES-CBC(base64(AES-CBC(text,preset,iv)),reversed,iv)` 锁定）。
- **linuxapi 完整输出（3）**：键顺序（url, method, params）匹配金标
  `kGoldenLinuxapiWorkerOrder`；eparams 大写 hex 且长度 %32==0；键顺序不同 → 密文
  不同（插入序序列化）。

## 9. 重写注意事项（实现中提炼的陷阱）

1. **weapi 第二层明文是内层 base64 字符串**，不是内层密文字节；金标向量与手工重算
   双保险，重写时直接复用向量。
2. **两层密钥的用法不对称**：第二层 AES 用随机密钥的**逆序**，RSA 加密的是**原始**
   密钥；`neteaseSecretKey` 同时返回两者。
3. **hex 大小写分用途**：weapi 的 `encSecKey` 是**小写** hex；linuxapi 的 `eparams`
   是**大写** hex（服务端区分与否未知，逐字节保持）。
4. **RSA 是无填充 raw 模幂**，密钥放 128 字节缓冲的**末 16 字节**（前 112 字节
   为零）；输出恒定补足 128 字节。别用标准 RSA 库的 padding 模式。
5. **`aesKeyPending` 补零**（非循环、非 PKCS 填充）：密钥不足 16/24/32 补零，超 32
   截断——网易的 weapi 密钥路径依赖这个行为。
6. **URL 重写规则**：weapi 把 `/\w*api/` 段替换为 `/weapi/`；linuxapi 把（重写为
   `/api/` 的）**原始 URL 塞进加密载荷**，实际请求永远打到 `/api/linux/forward`，
   且必须覆写 `User-Agent` 为 `linuxApiUA`。
7. **`cloudDelUrl` 是 http:// 不是 https://**——历史行为，逐字节保留（勿"顺手
   修复"，可能与既有行为对齐有关）。
8. **`os=pc` 只加在列表与直链请求**，删除请求不加——行为契约明确锁定。
9. **`validateStatus: (_) => true`**：非 2xx 也要读 body 拿网易 `code`，否则错误翻译
   全部失效。
10. **code 301 / 250 = 登录态失效**：必须翻译成「Cookie 过期请重新登录」的可读提示；
    其它非 200 带 code + message 透传。
11. **`addTime` 是毫秒**；0 → modified null，不伪造时间。
12. **不支持的操作必须 `async => throw`**（失败的 Future），不能同步 throw——否则绕过
    调用方的 `await` 错误通道。
13. **Cookie 正则 `name=([^(;|$)]+)` 逐字节保留**：值里可以含 `=`；额外 cookie 以
    `; k=v` 追加在配置串**之后**。
14. **平铺定位语义**：get / remove 都要先拉全量列表按 `fileName` 精确匹配；文件名是
    唯一键，远程路径是纯虚拟前缀。重名文件会命中第一个（实现未处理重名）。
15. **条目级容错**：缺 `fileName` / `songId` 的条目跳过（不整体失败）；`data` 缺失/
    非 List → 空列表。
16. **`song_limit` 解析容错**：非数字 / <1 一律回默认 200；表单里是文本字段。
17. **真连校验**：保存前 `verifyLogin()`（init + limit=1 列表拉取），不能只做本地
    格式校验。
18. **测试策略**：金标向量用固定密钥生成（把随机密钥换为固定值即得确定性输出）；
    驱动测试用 `_FakeAdapter`（HttpClientAdapter 闭包）不出真网络。
