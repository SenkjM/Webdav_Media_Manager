# crypt 驱动功能实现清单（已作废 · 重写参考）

> **状态声明**：本驱动已按维护者决定作废、待重写。本文档记录当前实现的完整功能面，
> 供重写参考。全部事实来自源码；与上游 OpenList / OpenList-Worker 的差异只记录
> 代码注释明确提到的内容，并注明出处（文件:行号）。

## 1. 标识

| 项 | 值 |
|---|---|
| typeId | `crypt` |
| displayName | `Crypt 加密目录` |
| Spec 类 | `CryptSpec`（`const`，`lib/services/cloud_drivers/crypt/crypt_driver.dart:1015`） |
| 驱动类 | `CryptDriver extends CloudDriver`（同文件 `:44`） |
| 内部状态类 | `_CryptTarget`（一次解析结果：直链/头/nonce/密文长/首块，`:1116`） |
| 主文件 | `lib/services/cloud_drivers/crypt/crypt_driver.dart`（约 1195 行，包装驱动） |
| 密码学库 | `packages/openlist_crypt/`（独立 package，rclone crypt 字节级互操作） |
| 测试 | `test/crypt_driver_test.dart`、`test/crypt_read_path_test.dart`、`test/crypt_size_race_test.dart`、`test/crypt_source_name_binding_test.dart`、`test/crypt_webdav_source_test.dart` |
| 上游来源（Go） | `localdev/OpenList/drivers/crypt/`（driver.go / meta.go / types.go / util.go；`meta.go:23-31` config：Name "Crypt"、OnlyProxy、NoLinkURL、NoCache、LocalSort、DefaultRoot "/"） |
| 上游来源（TS 参照） | `localdev/OpenList-Worker/src/backend/drivers/crypt/`（driver.ts + cipher.ts；表单字段定义另见 `localdev/OpenList-Worker/src/backend/server/admin.ts:3512-3579`） |
| 注册 | `lib/services/cloud_drivers/driver_registry.dart:27`，`kCloudDriverSpecs` 最后一位（注释：crypt 永远最后，包装层） |

### 1.1 openlist_crypt package（重写时格式层应保留或复用）

**互操作是硬约束**：库文档（`packages/openlist_crypt/lib/openlist_crypt.dart:1-43`）声明
"byte-for-byte wire compatible, verified against rclone v1.75.1 golden vectors"；
`rclone_cipher.dart:13` 注 "rclone crypt 文件格式（v1.75.1，OpenList 同格式）"；
`name_codec.dart:6` 注 "逐行对照 rclone v1.75.1 backend/crypt/cipher.go"。
重写驱动层可以，**格式层不能重新发明**——与 rclone / OpenList 互认取决于此。

导出（`openlist_crypt.dart:45-49`）：`rclone_cipher.dart`、`stream_encrypter.dart`、
`secretbox.dart`、`base32768.dart`、`name_codec.dart`（`eme.dart`、`salsa20.dart`
经 rclone_cipher 间接暴露）。

公开 API / 算法清单：

- **常量**：`kFileMagic`（"RCLONE\0\0"，8B）、`kFileHeaderSize=32`、
  `kBlockHeaderSize=16`、`kBlockDataSize=64*1024`、
  `kBlockSize=kBlockHeaderSize+kBlockDataSize`、`kNameCipherBlockSize=16`、
  `kDefaultEncryptedSuffix='.bin'`、`kDefaultSaltBytes`（rclone 内置默认盐 16B）、
  `kKeyMaterialLength=80`、`kSecretboxOverhead=16`。
- **密钥派生**：`deriveKeyMaterialSync({password, salt})` /
  `deriveKeyMaterial({password, salt})`（isolate 异步版，`rclone_cipher.dart:93`）。
  scrypt(N=16384, r=8, p=1, dkLen=80) → `dataKey[32] + nameKey[32] + nameTweak[16]`
  （`:68-84`）。空盐用 `kDefaultSaltBytes`；**空密码 = 全零密钥材料**（rclone 格式
  的一部分，`:70-77`）。
- **`RcloneCipher`**：构造 `RcloneCipher({password, salt, mode=standard,
  dirNameEncrypt=true, nameEncoding='base32', encryptedSuffix='.bin'})` 或
  `RcloneCipher.fromKeyMaterial(material, {…同参})`（长度必须 80B）。
  - 名字：`encryptFileName/decryptFileName/encryptDirName/decryptDirName`。
  - 内容：`encrypt(plain, {nonce?})` / `decrypt(cipher)` 全量；
    `encryptBlock(fileNonce, blockIndex, plainBlock)` / `decryptBlock(fileNonce,
    blockIndex, cipherBlock)` 单块（块号参与块 nonce，随机访问解密的基础）；
    静态 `encryptedSize(plainSize)` / `decryptedSize(cipherSize)` /
    `fileNonceOf(header)`（校验魔数并取 24B nonce）/ `randomFileNonce()`。
- **`RcloneStreamEncrypter`**（上传管线用，本驱动未用）：`header()`（32B 文件头，
  必须在第一块密文前写出）、`push(chunk)`（0 或多个整块密文，内部自行按
  `kBlockDataSize` 切块）、`close()`（余数块）、`fileNonce`（续传需持久化）、
  已产出密文字节计数（进度上报）。
- **底层件**：`secretboxSeal/secretboxOpen`（NaCl secretbox，XSalsa20-Poly1305，
  纯 Dart）；`EmeCipher(key32).transform(tweak, data, encrypt)`（EME 宽块
  AES-256）；`base32HexLowerEncode/Decode`、`base64UrlNoPadEncode/Decode`、
  `pkcs7Pad16/pkcs7Unpad16`、`obfuscateSegment/deobfuscateSegment`、
  `Base32768Encoding.safe.encode/decode`；`nameModeFromConfig(String)`（
  'off'/'obfuscate'/'standard'/'' → 枚举，其余抛 `RcloneCipherException`）；
  `RcloneCipherException(message)`。

**格式**（库文档 `openlist_crypt.dart:27-42`）：

- 内容：魔数 8B + 随机文件 nonce 24B，之后明文按 64KiB 分块，每块 secretbox
  （16B MAC 前缀）；块 nonce = 文件 nonce + 块号（LE 64 位加法）→ 任意块独立解密。
- 名字（standard）：PKCS7(16) + EME(AES-256, tweak=nameTweak, key=nameKey)，编码
  base32（Hex 表小写去填充）/ base64（URL-safe 去填充）/ base32768。
- 名字（obfuscate）：rclone 旋转密码，key=nameKey。
- 名字（off）：文件原名 + `encryptedSuffix`；目录保持原名。
- 解名守卫（`rclone_cipher.dart:186-192, 220-223`）：解码后长度非 16 倍数 →
  'not a multiple of blocksize'；>2048 → 'too long after decode'；off 模式缺后缀 →
  'suffix missing'。

## 2. 能力位

- **静态**（`CryptSpec.capabilities`，`crypt_driver.dart:1030-1036`）：
  `AccountCaps.list | read | mkdir | move | copy | delete`——**无 write**。
- **`runtimeCapabilities`**（`:987-997`）：`(s.capabilities | AccountCaps.list) &
  ~AccountCaps.write`。注释（`:991-992`）：「上传权限传递隔离：源即使有 write
  （WebDAV 配置），crypt 也绝不继承——内容上传不在 crypt 能力里（99 §7.5 用户决定）」。
  源不存在（`_requireSource` 抛错）→ 返回 `null` = 回落 spec 静态表（保守）。
- **`runtimeTypeLabel`**（`:999-1010`）：`'<源displayName> Crypt'`（如「Fake Crypt」）；
  源缺失或源 `displayName` 为空 → 退化 `'Crypt'`。注释：真机反馈源被删后重加同名账号
  即恢复，类型名也别显示成空白。
- **`isWrapper => true`**（`:1026`）：包装驱动不出现在「源账号」下拉候选里（防套娃，
  基类 `cloud_driver.dart:296-300` 契约；`CloudDriveService._resolveSourceByName`
  亦过滤 wrapper 账号，`cloud_drive_service.dart:217`）。
- `dispose()` 覆写（`:982-985`）：`_invalidateTargets()`（关掉缓存目标的 Dio 连接池）。

## 3. 表单字段

| key | 类型 | label | required | obscure | 默认值 | 开关联动 |
|---|---|---|---|---|---|---|
| `source_account_id` | `CloudDriverAccountField` | 源账号 | **true** | — | —（账号 id） | 无 |
| `source_dir` | `CloudDriverField` | 源目录 | false | false | `''`（驱动内回落 `'/'`） | 无 |
| `filename_encoding` | `CloudDriverSelectField` | 文件名编码 | **true** | — | `'base64'` | 无 |
| `encrypted_suffix` | `CloudDriverField` | 文件名后缀 | false | false | `'.bin'` | 无 |
| `password` | `CloudDriverField` | 密码 | **true** | **true** | `''` | 无 |
| `salt` | `CloudDriverField` | 盐值（可选） | false | **true** | `''` | 无 |
| `filename_encryption` | `CloudDriverSelectField` | 文件名加密 | **true** | — | `'off'` | 无 |
| `directory_name_encryption` | `CloudDriverSwitchField` | 目录名加密 | — | — | `false` | 无（无字段依赖它） |

- hint 原文：`source_account_id`「选择现有 WebDAV 或网盘账号作为加密源」；
  `source_dir`「源账号浏览根下的目录，默认 /（加密文件就存在这里）」；
  `filename_encoding`「与 rclone 的 filename_encoding 对应（base32 / base64 /
  base32768）」；`encrypted_suffix`「仅文件名加密=关闭时生效（OpenList
  encrypted_suffix）」；`salt`「留空用 rclone 内置默认盐；密码 + 盐相同即可与
  rclone / OpenList 互认」；`directory_name_encryption` subtitle「OpenList 默认关闭；
  开启后目录名同样加密」。
- select 选项：`filename_encoding` = base64/Base64、base32/Base32、base32768/Base32768；
  `filename_encryption` = standard/标准 (EME)、obfuscate/混淆、off/关闭。
- **无任何 `visibleWhenSwitch` / `enabledWhenSwitch` / `disabledWhenSwitch` 联动**。
- **secretFieldKeys**：基类合成（`cloud_driver.dart:310-314`）= obscure 字段 ∪
  `runtimeSecretKeys` = **`{'password', 'salt'}`**。`runtimeSecretKeys` 保持默认空集
  （无令牌轮换；基类注释点名 crypt 属此类，`cloud_driver.dart:322`）。
- **隐式键 `source_account_id_name`**：不在表单声明。表单渲染器保存
  `CloudDriverAccountField` 时写入快照：`cfg['${item.key}_name'] =
  accounts.accountById(v)?.name ?? ''`（`lib/screens/accounts_screen.dart:301-303`，
  注释「源账号名快照：源被删后重添同名账号可按名恢复（crypt 场景）」）。
  `test/driver_secret_scope_test.dart:118-121` 清点：crypt 共 9 键 = 表单 8 +
  隐式 `source_account_id_name`（非凭证，明文正确）。
- 构造器默认值（`crypt_driver.dart:45-66`）：`filename_encoding` 缺省 `'base64'`、
  `encrypted_suffix` 缺省 `kDefaultEncryptedSuffix`、`directory_name_encryption`
  缺省 `false`、`source_dir` 缺省 `'/'`、`source_account_id_name` 缺省 `''`。
  `filename_encryption` 非法值 → 构造器抛
  `CloudDriverDataException('crypt 配置无效：…')`；**空字符串按 standard 解**
  （`nameModeFromConfig` 的 `case ''`，`rclone_cipher.dart:52`）。

## 4. 包装机制（源解析）

- `CloudDriverEnv`（`cloud_driver.dart:272-281`）注入两个解析器：
  `resolveSource(accountId)`（按 id）与 `resolveSourceByName(accountName)`（按名，
  可空）。
- **crypt 只用按名解析**。`_requireSource()`（`crypt_driver.dart:150-165`）：
  1. 命中实例缓存 `_source` 直接返回；
  2. `normalizeSourceName(_sourceAccountName)`（trim + 折叠内部空白，
     `lib/utils/track_identity.dart:30-32`）为空 → 抛
     `CloudDriverException('crypt 未保存源账号名称；请重新编辑并选择源账号')`；
  3. `_env?.resolveSourceByName?.call(sourceName)` 为 null → 抛
     `CloudDriverException('crypt 源账号不存在或已删除「$sourceName」；重新添加同名源账号即可恢复')`。
  注释（`:157-158`）：「名称是 Crypt 源的唯一绑定关系。source_account_id 仅保留作
  旧配置兼容字段，不参与实际解析；这样删除并重建账号后同名账号仍可恢复。」
- **`resolveSource`（按 id）在本驱动中从不调用**——`source_account_id` 只被表单
  渲染为账号下拉的存库值 + 名字快照来源。
- 名字匹配语义（`CloudDriveService._resolveSourceByName`，`cloud_drive_service.dart:215-222`）：
  排除 wrapper 账号后按 `name.trim()` 精确匹配，命中即用该账号 id 走
  `_resolveSource`（WebDAV 走 `webdav_source.dart` 适配，云盘走
  `CloudAccountSource`，路径挂到账号浏览根 `basePath`）。
- **源被删后的行为**：懒解析——`init()` 只调 `_requireSource()`（表单保存校验会撞
  上），注册流程不受影响；真正浏览/读取时才报上面的明确错误（`:148-149` 注释）。
- 密钥缓存键也带源账号名（`:95-103`，见 §7.1），与同名恢复语义一致。

## 5. 接口实现逐条

路径映射基础：`_mapToInner(outerPath, {required bool lastIsFile})`（`:168-186`）=
`src.basePath` + `_sourceDir` 各段 + 外层路径**逐段加密**：非末段一律
`cipher.encryptDirName`；末段 `lastIsFile ? encryptFileName : encryptDirName`。
拼接用 `cloudJoinPath`（去空段、单斜杠、以 / 开头）。

### 5.1 list / get（透传 + 加密名映射）

- `list(path)`（`:286-293`）：`src.list(_mapToInner(path, lastIsFile: false))` →
  `_decryptNames(inner)`（见 §6）→ 逐条 `_reveal`。空列表短路返回。
- `_reveal(e, decryptedName)`（`:268-284`）：名字解密失败（null）→ **原名透传**；
  文件大小 `RcloneCipher.decryptedSize(e.size)`，`RcloneCipherException` →
  保留内层原值（注释 `:274`「大小换算失败用内层原值（OpenList 同款告警语义）」）；
  **`rawUrl: null`**（MustProxy：密文直链不外泄，内容走 openContent 族）。
- `get(path)`（`:295-317`）：`src.get(_mapToInner(path, lastIsFile: true))`，
  名字按**文件**语义解（`isDir: false` 恒定，即便目标实际是目录——get 契约按文件
  取直链用）；同样抹 `rawUrl`。

### 5.2 mkdir / rename / remove / move / copy

全部模式一致：映射到密文路径透传内层；**末段文件/目录二义性**用「先按文件试、
`CloudDriverException` 后按目录重试」兜底；成功后 `_invalidateTargets()`（目录
改动 → 缓存直链可能失效，整批丢弃）。

- `mkdir(path)`（`:319-324`）：`lastIsFile: false`（目录名加密）。
- `rename(path, newPath)`（`:326-342`）：两侧都 `lastIsFile: true` 映射，失败后
  两侧都按 `false` 重试（注释 `:335`「末段可能是目录：按目录映射重试」）。
- `remove(path)`（`:344-353`）：同上双试。
- `move(srcPath, dstDir, newName)`（`:355-373`）：src 按 `true`/重试 `false`；
  dstDir 恒 `false`；`newName` 用 `cipher.encryptFileName(newName)`，重试用
  `encryptDirName`。
- `copy`（`:375-393`）：与 move 同构。

### 5.3 openDownloadContent（CloudDownloadMode.cryptSequential）

下载专用顺序路径（`:413-501`，注释「Download-only sequential path: one ciphertext
GET, decrypted block by block. Range playback and resumed downloads continue using
the existing paths」）：**一次整包 GET 流式响应**，边收边按 `kBlockSize` 切块
解密（首 32B 是文件头 → `_fileNonce`），块解密失败 →
`CloudDriverDataException('crypt 第 N 块解密失败（内容损坏或密钥不匹配）')`；
流结束后余数字节按尾块解密；`inner.size > 0 && total != inner.size` →
`CloudDriverException('crypt 内容长度不符（期望 X，收到 Y）')`。无直链 →
`CloudDriverException('crypt 源不提供直链，无法顺序下载')`。`finally` 中
`dio.close(force: true)`。支持 `cancelToken`。

**模式选择在上层**（`lib/services/cloud_drive_service.dart:339-347`，
`downloadToFile`）：`item.rawUrl != null` → `direct`；否则
`resumeFrom > 0 || !useCryptSequentialDownload` → `cryptRange`，否则
`cryptSequential`（即：首次全新下载且勾了顺序下载才走 5.3；续传/区间播放一律走
5.4 的 `openContentRange`）。

### 5.4 openContent / openContentRange（MustProxy 流）

共同前置 `_openTarget(path, {prefetchFirstBlock})`（§7.3）：解析直链 + 文件头
（+ 可选首块），产出 `_CryptTarget`。

**四态 shape 判定**（`_CryptTarget.shape`，`:1189-1194`，互斥、必须按此顺序）：

1. `shapeWholeBody`：服务器**无视 Range**（响应比请求多，`rangeIgnored`）→
   `body` 即整包密文 → `_decryptAll`（isolate 全量解密）。
2. `shapeEmptyFile`：`cipherSize == kFileHeaderSize`（密文恰 32B = rclone 空文件
   合法格式）→ 空明文流。
3. `shapeRanged`：`cipherSize > kFileHeaderSize` → 分块 Range 解密。
4. `shapeUnknownSize`：三者皆非（总长为 0/未知）→ **明确抛**
   `CloudDriverException('无法确定加密内容的大小（源未提供长度且不支持 Range）')`。

注释（`:1113-1115`）：「大小未知」**不**折叠进 wholeBody——静默返回空内容 =
下载出 0 字节损坏文件，真机踩过。

`openContent(path)`（`:503-577`，shapeRanged 主路径）：

- 预取窗口 `[_fetchWindow]=4` 批同时在途（每批 `_blocksPerBatch=16` 块 ≈1MiB）；
  首块若随解析请求带回则注入窗口（`offset` 越过它）。注释（`:524-529`）：Dart
  单线程下同步解密期间事件循环不转，**单个**在途请求无法重叠（实测提前发下一个，
  每批等待仍是完整 34ms；16 个 1MiB 同时发 90ms、顺序发 547ms）。
- 消费循环：取一批 → `fill()` 补满窗口 → 批内切 `kBlockSize` 块 →
  `_decryptBatch`（isolate）→ 逐明文块 yield；批间 `Future.delayed(Duration.zero)`
  让出事件循环。
- `CloudDriverDataException` → `_dropTarget(t)` 后 rethrow（注释 `:572`「内容
  本身坏了：别让缓存的解析结果继续骗下一个人」）。

`openContentRange(path, start, end)`（`:579-694`，含端点，同 HTTP Range 语义，
ffmpeg 拖进度条用）：

- `start < 0 || end < start` → 空流；`start < kBlockDataSize` 时解析请求带回首块
  （远离开头的 seek 不预取，免得每次拖动多下 64KiB）。
- wholeBody → 全量解密后内存切片；emptyFile → 空；unknownSize → 抛（同上）。
- shapeRanged：`plainSize = _decryptedSize(t.cipherSize)`（失败 →
  `CloudDriverDataException('crypt 密文长度不合法：…')`）；`start >= plainSize`
  → 空流；区间换算到块号 `firstBlock..lastBlock`，首/尾块按 `from/to` 裁剪；
  首块（若预取）先消化；其余按批窗口在途（注释 `:625-626`：区间读取也要多批
  在途，否则每个 1MiB 往返直接暴露给播放器，吞吐接近播放速率时周期性断粮）；
  每批 2 块让出一次事件循环；批校验长度短缺 →
  `CloudDriverException('crypt 内容提前结束（第 N 块起，期望 X 字节，收到 Y 字节）')`。

### 5.5 大小换算与异常翻译分层纪律

- `_decryptBatch`（`:697-716`）：整批丢 `Isolate.run`（顶层函数
  `_decryptBatchInIsolate`，`:15-28`，用密钥材料在 isolate 内重建 cipher）；
  **任何异常**（含 isolate 失败）→
  `CloudDriverDataException('crypt 第 N 块起解密失败（内容损坏或密钥不匹配）')`。
- `_decryptAll`（`:719-728`）`RcloneCipherException` → `CloudDriverDataException`；
  `_fileNonce`（`:738-744`）→ `CloudDriverDataException('不是有效的 rclone 加密文件：…')`。
- 分层纪律（类注释 `:42-43`）：「`openlist_crypt` 的异常在这里全部翻译成
  `CloudDriverException` / `CloudDriverDataException`，密码学细节不越过本文件」。
  `CloudDriverDataException` = 内容本身坏（解密失败/密钥不匹配/损坏），重试无意义
  （`cloud_driver.dart:102-108`；`DownloadQueueService.isRetryable` 对其返回 false，
  测试断言）。
- 网络侧：Dio `connectTimeout` 20s、`receiveTimeout` 60s、`validateStatus`
  2xx-3xx；`Range: bytes=start-end` 请求头；`Content-Range` 总长用正则
  `bytes\s+\d+-\d+/(\d+|\*)` 解析（`*` → null，`:973-980`）。

## 6. 名称加密映射

- **明文 → 密文**（写入/映射方向）：逐段调 `cipher.encryptDirName(seg)`（目录段）
  或 `cipher.encryptFileName(seg)`（文件末段）。`RcloneCipher` 内部
  `_mapPath`（`rclone_cipher.dart:197-212`）：`dirNameEncrypt=false` 时**目录段
  不动**（仅最后文件段处理）；standard → EME；obfuscate → obfuscateSegment。
  off 模式：`encryptFileName = name + encryptedSuffix`，目录名原样。
- **密文 → 明文**（读取方向）：`_decryptNames(entries)`（`:216-255`）整目录批解，
  顺序保留；`_tryDecrypt`（`:258-264`）按 `isDir` 选
  `decryptDirName/decryptFileName`，**任何异常 → null**。null 的条目 `_reveal`
  原名透传（注释 `:214-215`「解不开的名字按原名列出（只读取、不改动远端，也不做
  二次加密，99 §7.5）」）——这就是目录遍历的**虚拟明文视图**：远端仍是密文名，
  UI 看到的是解出的明文名（或解不开的密文名）。
- **大小换算**：`RcloneCipher.decryptedSize(cipherSize)`
  （`rclone_cipher.dart:249-263`）：<32 → 'file too short'；余数 ≤16 →
  'bad header'；公式 `blocks*64KiB + (residue-16)`。列表侧失败保留原值（§5.1）；
  流侧失败抛 `CloudDriverDataException`（§5.4）。
- **encrypted_suffix**：仅 `filename_encryption=off` 时参与（`encryptFileName`
  加 / `decryptFileName` 剥；剥不到 → `RcloneCipherException('suffix missing')`
  → 名字解不开 → 原名透传）。默认 `.bin`。
- 名字解密的**性能双路径**（§7.5）与 isolate 门槛详见特殊机制。

## 7. 特殊机制与取舍

### 7.1 密钥派生与进程内缓存

- scrypt 走 isolate + **进程内复用**（类注释 `:34-36`：多花 0.1~1s 在 UI 线程上
  就是一次明显掉帧；密钥材料是 (密码, 盐) 的纯函数，进程内缓存不改变任何映射）。
  驱动每次 `registerAccounts` 都会重建实例，不缓存就要反复付这笔钱。
- `_keyMaterial(accountName, password, salt)`（`:97-123`）：静态缓存
  `_keyCacheLimit=4` 条（LRU 队列淘汰）；缓存键 =
  `'${normalizeSourceName(accountName)}\u0000$password\u0000$salt'`（带源账号名：
  与读取时的同名恢复语义一致，`:95-96`）；**派生失败从缓存移除**（否则该配置永远
  起不来）。
- **只在内存**（`:93` 注释）：密钥材料不落盘（用户明确否决落盘缓存）。
- 懒构造：构造器把派生提前踢到后台（`unawaited`，错误吞掉、真正用时原样抛，
  `:63-65`）；`_materialFuture` / `_cipherFuture`（`RcloneCipher.fromKeyMaterial`
  + 名字参数）late final。

### 7.2 网络批次与预取窗口

- `_blocksPerBatch = 16`（16×64KiB ≈ 1MiB，`:397-402`；注释：一块一个请求会把
  700MB 拆成约 10700 次往返，正是真机「播放/下载加密文件一直转圈」的主因）。
- `_fetchWindow = 4`（`:404-411`；实测 16MiB：顺序 904ms / 窗口 2:612 / 3:591 /
  4:523 / 6:430 / 8:440ms，CPU 地板 219ms。取 4 不取拐点 6：真机瓶颈是每请求的
  服务端延迟，同时压带宽与风控；限流有窗口退避兜底）。
- **429 限流退避**（`_fetchRange`，`:894-928`）：429 → 目标 `t.window` 减半
  （下限 1）→ 延迟 300ms → 同区间重试**一次**。注释（`:890-893`）：「预取窗口
  是我们的选择，源说不的时候就该收窄，而不是把限流当成永久失败（403/429 在下载
  队列里都是『不可重试』）」。
- **直链过期重解析**（`:941-945` 判定 401/403/404/410 = `_isStaleLink`）：
  `_refreshTarget(t)` → `t.refresh()` 重新 `src.get(innerPath)` 换 URL/头并续期
  TTL（nonce/长度理论不变）；仍无直链 →
  `CloudDriverException('crypt 源不再提供直链，无法继续解密内容'）`。注释：真机
  反馈百度/123 的直链有 TTL，长下载中途会 403。

### 7.3 解析缓存（_CryptTarget）

- `_targetTtl = 45s`（`:749` 真机直链有 TTL，取短不取长）、`_targetCacheLimit = 8`
  条 LRU；命中**滑动续期** + LRU 触碰（`:790-794`）。目的（类注释 `:38-39`）：
  播放器反复拖动进度条不重复解析直链。
- `_openTarget`（`:780-864`）：发 `Range: bytes=0-(31 或 32+65551)`（prefetch 时
  头+首块同一个请求，少一个往返；按 `inner.size` 裁上限）；body < 32B →
  `CloudDriverException('crypt 内容不完整（读不到文件头）')`；
  `rangeIgnored = body.length > wantEnd+1`。
- **密文总长优先级**（`:777-779, 826-831`）：响应 `Content-Range` 总长（与内容
  **同请求**，不会错位）> 源元数据 `CloudFileItem.size`；服务器无视 Range 回整包
  → 整包长度即总长。三者都拿不到（0）才算「大小未知」。
- **首块只在完整时留用**（`:832-841`）：整块 kBlockSize 或恰为整个文件尾。注释：
  元数据 size 可能过期（比真实小）——那时请求区间被裁短，手上这半块不能当块 0 用，
  否则解出来的是错位数据（宁可多一个请求）。
- `_CryptTarget` 持有专用 `Dio`（连接池）；生命周期归解析缓存（过期/淘汰/弃用/
  dispose 时 `requestClose`），**不在流结束时关**；`retain()/release()` 读者计数，
  关闭请求挂起直到最后一个读者释放（`:1158-1177`）。目录改动
  `_invalidateTargets()`（§5.2）；内容坏 `_dropTarget`（§5.4）。
- `t.window`：当前预取窗口，初值 `_fetchWindow`，429 时减半（`:1150-1152`）。

### 7.4 名字解密的性能路径

- 成本模型 `_nameCost(name) = 300 + name.length`（`:192`，定长开销约 15µs + 每
  字符约 0.05µs）；总代价 ≥ `_nameIsolateCost = 600000` → 整批丢 isolate。
- 注释（`:196-201`）核心取舍：实测 isolate 的**总时间从来不更省**（固定开销约
  0.5ms + 逐条跨 isolate 传输；n=512 就地 1058µs vs isolate 1276µs）——门槛不是
  为省时间，而是**不卡帧**：桌面 1.6µs/条 → 中端安卓约 5~10µs/条，约 1900 条
  吃掉 16ms 一帧。
- 就地路径每 `_yieldEvery = 64` 条 `Future.delayed(Duration.zero)` 让出一次
  （`:205-209`，一次让出实测约 0.11ms）。
- isolate 闭包**只捕获局部变量**（`:224-225` 注释：不能碰 this，否则整个驱动
  实例（Dio、源适配器……）都会被搬进 isolate）。
- 诊断计数 `static int nameIsolateRuns`（`:212`）：测试断言「真的走了哪条路」。

### 7.5 与上游 OpenList / OpenList-Worker 的差异（仅代码注释明确提到的）

1. **表单字段集**：`CryptSpec` 注释（`:1013-1014`）「字段照 OpenList meta.go 子集
   + 源账号 / 源目录（用户决定：源 = 已有账号 id，WebDAV 亦可）」。即上游的
   `remote_path`（Go `meta.go:11` / TS `admin.ts:3527`）换成 `source_account_id`
   （账号下拉）+ `source_dir`；上游的 `thumbnail`（`meta.go:18`）与
   `show_hidden`（`meta.go:20`）未实现。
2. **TS 参照版的名字加密限制**：`localdev/OpenList-Worker/src/backend/drivers/crypt/driver.ts:4-5`
   头注释「当前支持 filename_encryption=off（默认）……standard / obfuscate 文件名
   加密为后续增强」；`init()`（`driver.ts:39-44`）对非 off 模式直接抛错。Dart 版
   借 openlist_crypt 三模式全支持（spec 三个选项都在）。
3. **大小换算告警语义**：`:274` 注释「大小换算失败用内层原值（OpenList 同款
   告警语义）」。
4. **nameEncoding 默认值**：Dart spec 默认 `'base64'`；`rclone_cipher.dart:135-137`
   注释「'base32'（rclone 传统）或 'base64'（OpenList 默认）；base32768 与 rclone
   SafeEncoding 同表」——与上游 meta.go/admin.ts 的 default base64 一致。
5. 上游 `driver.Config` 位（OnlyProxy/NoLinkURL/NoCache 等，`meta.go:23-31`）在
   Dart 侧体现为 MustProxy（`rawUrl: null`）+ spec 能力位，不逐项实现。

### 7.6 代码注释提到的已知问题 / 真机踩坑（重写必读）

- 大小未知被误判成 wholeBody → 静默解出空内容（下载 0B 文件 / 流式报错），
  真机源 = WebDAV 拿不到 size（`test/crypt_size_race_test.dart:1-9` 头注释；
  `test/crypt_webdav_source_test.dart:1-6` 头注释：根因是
  `WebDavAccountSource.get()` 没带 size，修复 = 单文件 PROPFIND 补 size/modified）。
- 首块半块当块 0 用 → 错位数据（`crypt_driver.dart:832-834`）。
- isolate 总时间不更省但防卡帧（`:196-201`，见 §7.4）。
- isolate 闭包捕获 this 会把整个驱动实例搬进 isolate（`:224-225`）。
- Dart 单线程下单个在途请求无法与同步解密重叠（`:524-529`）。
- 密钥材料不落盘（用户明确否决，`:93`）。

## 8. 测试覆盖（重写必须保持的契约）

### 8.1 test/crypt_driver_test.dart（基础语义，7 用例）

1. `list decrypts names and hides raw url`：列表解出 `photos` / `song.flac`；
   所有条目 `rawUrl == null`（MustProxy 密文直链不外泄）；`song.flac` 的 size =
   明文字节长度。
2. `missing source surfaces a clear error on browse`：源名解析不到 → `list`
   抛 `CloudDriverException`。
3. `runtime capabilities inherit source but never write`：源给
   `AccountCaps.all`（含 write）→ caps 无 write、有 read/mkdir（上传权限传递隔离）。
4. `runtime capabilities null when source missing`。
5. `mkdir encrypts the directory name toward the source`：内层收到的 mkdir 路径
   末段密文名可解回 `新专辑`（即真的做了目录名加密）。
6. `rename re-encrypts names both sides`：src/dst 两侧密文名各自解回
   `song.flac` / `renamed.flac`。
7. `spec declares required fields`：form 键含 `source_account_id / source_dir /
   password / salt / filename_encryption / directory_name_encryption`；
   `spec.capabilities` 无 write。
   （附：`FakeCloudSource` 内存源被 `test/crypt_stream_bridge_test.dart` 复用。）

### 8.2 test/crypt_read_path_test.dart（性能/健壮性回归，12 用例）

文件头注释锁死四件事：按批 Range / 解析缓存 / 直链过期自动重解析 / 坏内容 →
`CloudDriverDataException`。用本地 `CountingCipherServer`（记录 Range 头、并发度、
可模拟直链过期 403 与 429）逐条断言：

1. 2MiB+100B 文件 `openContent` 只发 **3 个请求**（头+首块合一、再两批）；
   首个 Range 头必须是 `bytes=0-65583`。
2. 跨多块区间读取（块 1→9）只发 2 个请求。
3. 解析缓存：连续两次 `openContentRange` 同文件 → `getCalls == 1`、请求数不变
   （首块复用）；`mkdir` 后 → `getCalls == 2`（缓存失效重解析）。
4. 直链过期（403 数据块）：自动重解析一次（`getCalls == 2`）后内容完整。
5. 坏块 → `CloudDriverDataException`，且 `DownloadQueueService.isRetryable` 对其
   返回 false（重试无意义）。
6. 预取窗口：4MiB `openContent` → `maxInflight` >1、≥3、≤4；共 5 个请求；
   内容逐字节正确（150ms/请求延迟下墙钟可区分真并发）。
7. 区间预取窗口：`openContentRange(0, len-1)` 同窗口断言。
8. 活动中的区间流在 `_invalidateTargets`（mkdir）后仍能完整完成（读者计数保护）。
9. 429 限流一次：退并发 + 重试同区间，内容完整（`rateLimited == 1`）。
10. 大目录（2500 条）名字解密走 isolate（`nameIsolateRuns == 1`）且结果与就地
    一致；小目录不起 isolate（`== 0`）。
11. 解不开的名字按原名列出（只读不改远端）。
12. `runtimeTypeLabel`：有源 → `'Fake Crypt'`；源缺失 → `'Crypt'`。

### 8.3 test/crypt_size_race_test.dart（大小判定竞态，4 用例）

头注释四条铁律：32B 密文 = 合法空文件；Content-Range 总长优先于过期元数据；
两者都无 → 明确报错；元数据偏小按 Content-Range 纠正不产截断文件。

1. 空文件（密文恰 32B）→ `openContent` 空流，不误解为整包。
2. 元数据 size=0 但支持 Range → Content-Range 纠正总长，正常分块解密。
3. 元数据 size=0 且不回 Content-Range → `CloudDriverException`（绝不静默空内容）。
4. 元数据 size 过期（100 vs 真实 70000+）→ 按 Content-Range 纠正，内容完整。

### 8.4 test/crypt_source_name_binding_test.dart（名称绑定语义，6 用例）

纯逻辑复刻（不实例化驱动）：按名命中不依赖 id；id 指向别的账号仍以名称为准；
源删除后重添同名可恢复；名字也对不上 → 失败（不误接别的源）；无名字快照 →
无法绑定；名字匹配忽略首尾空白。

### 8.5 test/crypt_webdav_source_test.dart（WebDAV 源适配，2 用例）

1. `WebDavAccountSource.get()` 必须带回密文条目 size 与 modified（单文件
   PROPFIND），且 `rawUrl` 仍带回（crypt 拉密文用）——流式 Content-Length、下载
   进度、wholeBody 判定都依赖 size。
2. `statPath` 正常返回单文件元数据。

## 9. 重写注意事项（从实现中提炼的陷阱）

1. **格式层直接复用 openlist_crypt**：与 rclone v1.75.1 / OpenList 字节级互操作
   是硬约束（黄金向量已验证）；重写驱动层即可，格式层重新发明必踩互操作坑。
   块边界纪律：除最后一块外每块必须恰 64KiB（块号参与块 nonce，错位 → 整文件
   不可解，`rclone_cipher.dart:292-296`）。
2. **密钥参数别改**：scrypt(N=16384, r=8, p=1, dkLen=80)；空盐 = rclone 内置
   默认盐；**空密码 = 全零密钥**（格式的组成部分）。密钥材料只在内存缓存
   （用户明确否决落盘）。
3. **名字绑定用账号名而非 id**：源删后重添同名即恢复；`source_account_id` 只是
   旧配置兼容。缓存键也要带账号名，否则同名恢复后缓存失配。
4. **MustProxy 纪律**：list/get 一律 `rawUrl: null`；解密失败绝不落坏数据
   （块失败即抛）；`RcloneCipherException` 必须在驱动文件内翻译成
   `CloudDriverException`（可重试类）/ `CloudDriverDataException`（数据坏、
   不可重试）——上层不认识任何密码学实现。
5. **cipherSize 判定顺序**：Content-Range 总长 > 元数据 size > 整包长度；
   全拿不到 → 明确报错。绝不能把「未知」静默当 wholeBody（真机踩过：下载 0B
   损坏文件）。首块只在完整（整块或文件尾）时复用——过期 size 会裁短请求，
   半块当块 0 = 错位密文。
6. **并发模型**：Dart 单线程 → 必须**多个在途请求**才能与服务端延迟重叠
   （单在途无法与同步解密重叠）；窗口取 4（不取实测拐点 6）：带宽/风控/内存
   折中。429 → 窗口减半 + 300ms + 重试一次；401/403/404/410 → 重解析直链一次。
7. **isolate 纪律**：闭包只捕获局部变量（捕获 this 会把 Dio/源适配器整实例搬进
   isolate）；名字解密 isolate 的门槛是防卡帧不是省时间（isolate 总时间从不更省）；
   就地路径定期 `Duration.zero` 让出。
8. **改动即失效**：mkdir/rename/remove/move/copy 后必须丢解析缓存（直链可能已
   指向不存在的东西）；但活动流不能被杀（读者计数）。内容坏 → 单独 drop 该
   target（别让缓存骗下一个读者）。
9. **`filename_encryption` 边界**：空字符串按 standard 解（rclone 语义）；非法值
   在构造器就抛 `CloudDriverDataException`。`encrypted_suffix` 只在 off 模式生效。
   默认 `filename_encoding='base64'`（OpenList 默认；rclone 传统是 base32）。
10. **上游差异清单**（§7.5）：remote_path → source_account_id + source_dir；
    thumbnail/show_hidden 未实现；TS 参照版仅支持 off 模式而 Dart 全支持。上游
    `directory_name_encryption` 是 select false/true，Dart 用 switch 表达（默认
    均 false）。
11. **测试锁死的数字契约**：2MiB → 3 请求、首 Range `bytes=0-65583`、窗口
    ∈(2,4]、2500 条走 isolate、32B = 空文件、Content-Range 纠正……重写若改批次
    大小/窗口/缓存 TTL，先改测试再改实现（这些数字是防回归的锚）。
12. 相关但本清单未展开的测试：`test/crypt_stream_bridge_test.dart`（本地流桥的
    HTTP Range 语义，复用本驱动 `FakeCloudSource`）、
    `test/driver_secret_scope_test.dart`（crypt 密文键 = password/salt 的清点）。
