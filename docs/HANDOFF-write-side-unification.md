# 交接：云端写侧统一（crypt 写入能力 + 入口能力化）

> 用途：把已查明的现状、决策与改动细节交接给新会话，**用于直接实施大重构**（不只是制定计划）。
> 大重构的目标、合并面清点与已定方案见 **§8**——§8 是最新口径，与本文件其余部分冲突时以 §8 为准。
> 本文件是过程性交接件，计划落地后可删。
> 生成时的仓库状态：分支 `feat/upload-multi-and-folder`，HEAD `6143ab2`，`git status --short` 只有 `?? test/crypt_basepath_double_join_test.dart`。

---

## 0. 一句话

把「云端写」从当前状态——**每个入口各写一套 `providerType` 判断 + 兼容层两个写方法无条件抛错**——改成
**驱动级两个写原语（`uploadStream` / `ensureDirectory`）+ 网络库能力列表单一来源**，
让 crypt（以及未来任何可写驱动）自动获得上传 / 同步 / 备份能力，而不是被类型名硬挡。

---

## 1. 里程碑与分支

| commit | 内容 |
| --- | --- |
| `289df22` | fix(ci): split-per-abi 构建关闭 ABI versionCode 偏移（早于此轮工作） |
| `73b27b9` | feat(upload): 上传文件支持多选，新增上传文件夹（SAF DocumentTree），10 files |
| `5c515db` | feat(crypt): crypt 上传能力，能力完全继承源（含 write），14 files |
| `6143ab2` | fix(saf): 单选调用方在多选 intent 下不再误判取消；主题默认跟随系统，4 files |

**未提交**：`test/crypt_basepath_double_join_test.dart`（134 行，新增文件，**尚未跑通**，见 §3.6）。

---

## 2. 用户已拍板的需求（决策基线，不要重新征询）

1. **能力完全继承**：crypt 的能力 = 源账号能力，**不按类型名判断**，只做能力继承（crypt 源不可解析时回落 `CryptSpec.capabilities`，不含 write）。
2. **推翻「上传砍掉」的旧设计决定**：本轮即为上传能力扩展，**不另开分支**。
3. **接受两项代价**（用户明确「可以接受」）：
   - crypt 目标上的远端索引 / 歌单 / 凭证库 / 备份包会以**密文**落盘（读回时按 crypt 语义解密）；
   - crypt 上传**不做断点续传**。
4. **进度归一化**：crypt 上传的进度按**明文字节**口径上报（现在报的是密文累加，见 §3.2）。
5. **入口判定不独立实现**：所有云端操作的入口一律查网络库的能力列表；「网络库必须是所有云端操作的唯一方法来源」。
6. **顺序**：先统一写侧，再改五处入口。
7. **虚拟文件层一并统一**：用户原话「我构建虚拟文件层就是为了防止每次读取写入都使用单独的方法的，尽量统一一下」——写侧要收敛到与读侧同级的驱动原语，不允许每个调用方各走一套。
8. **双拼 bug 先坐实**：用户要求「先把这个双拼的确凿触发条件写个最小测试坐实」。
9. 早前的同类倾向（本地备份导入修复、主题默认跟随系统）已落地并提交，不在本轮范围。

### 2.1 开工前的六项决策（已确认，按此执行，不要再问）

| # | 决策点 | 结论 |
| --- | --- | --- |
| 1 | basePath 双拼怎么修 | **crypt 侧修**：`_mapToInner` 不再拼 `src.basePath`，约定「传给源层的 path 相对 `basePath`」；只动 crypt + `CloudSource` 契约文档。依据：`crypt_driver.dart` 里 15 处 `_mapToInner` 调用点（:290/:299/:323/:332-333/:338-339/:349/:351/:362-363/:368-369/:382-383/:388-389/:423/:807/:1016）**全部**把结果喂给 `src.*`，而源层每个方法都会 `_join([basePath, path])`，所以去掉后自洽。 |
| 2 | 接口改动范围 | **一次补齐契约**：`CloudDriver` 加 `uploadStream` / `ensureDirectory`，`CloudSource.writeFile` 同时加 `cancelToken`；取消语义真正透传，测试假源一并更新。 |
| 3 | 后台自主度 | **自主推进**：按「能力位单一来源」原则自行决定并记录，写进交接文档等复核。 |
| 4 | 提交粒度 | **分步提交四笔**：驱动原语 / 兼容层 / 入口 / 文档；每步 Analyze + 单测通过再提交。 |
| 5 | 验证边界 | **静态分析 + 单测通过即可交付**，真机项另附待核清单（见 §6）。 |
| 6 | 放行范围 | **仅 crypt**：15 个云盘驱动的「不给 write（99 §7.2.1）」维持不变。 |

---

## 3. 已查明的改动细节

### 3.1 驱动接口：要新增的两个写原语

`lib/services/cloud_driver.dart` 的 `CloudDriver` **目前没有任何上传方法**，只有：

```
openContent(:31) / openDownloadContent(:36) / openContentRange(:43) / list(:47)
get(:51) / mkdir(:53) / rename(:57) / remove(:60) / move(:63) / copy(:66)
```

计划新增（与 `openContent(:31)` / `openContentRange(:43)` 对称，**默认实现抛 `err.cloudWriteDisabled`**）：

```dart
Future<void> uploadStream(String path, Stream<List<int>> content, int length,
    {void Function(int count)? onProgress, CancelToken? cancelToken});
Future<void> ensureDirectory(String path);
```

依据已写进契约：`CloudSource.writeFile` 的 doc（cloud_driver.dart:270-275）原文要求
**「调用前必须先用 `AccountCaps.has(capabilities, AccountCaps.write)` 判断，而不是按源的类型名特判」**。

### 3.2 crypt 侧

- `lib/services/cloud_drivers/crypt/crypt_driver.dart:1007`
  `Future<void> uploadContent(String path, Stream<List<int>> plaintext, int plainSize, {onProgress, cancelToken})`
  → 提升 / 改名为 `uploadStream`，**实现体基本不动**：
  - `_mapToInner(:169)`（明文路径 → 密文路径）→ `RcloneCipher.encryptedSize(plainSize)` → `RcloneStreamEncrypter` → `cipherStream(){ yield header; push(); close(); }` → `src.writeFile(innerPath, cipherStream(), cipherLength, onProgress: onProgress)`（:1044-1049）。
  - **cancelToken 目前只在 `cipherStream` 内检查（:1029-1034），没有透传到源层**——因为 `CloudSource.writeFile` 没有 cancelToken 参数。要真正支持取消，得同时给源层加参数。
  - **进度口径**：现在直接把源层回调的**密文字节数**当 `onProgress` 传出（:1048）。归一化要用 double 计算 `plain = (clamped * plainSize / cipherLength).round()`，否则 3 GiB 级会溢出。
- `runtimeCapabilities(:1057-1068)` 已改为 `s.capabilities | AccountCaps.list`（完全继承，含 write）；源不可解析 → 返回 null → 上层回落 `CryptSpec.capabilities(:1102-1109)`。
- **新增 `ensureDirectory` 必须吞「已存在」**：逐级 `src.mkdir(await _mapToInner(累积路径, lastIsFile: false))`，对每级 405 / 409 静默当成功，只对真错误（权限 / 网络）抛——否则第二次同步必挂。
- **现成件：WebDAV 层已经有 `mkdirAll`**。`lib/services/webdav_service.dart:443-451` 的注释原文是「Ensure directory exists (mkdirAll) on a specific account.」→ `await client.mkdirAll(normalized)`；而同文件 `:454-458` 的 `createFolder` 走的是 `client.mkdir(path)`（单级，目标已存在会报 412 / 409，见 `:496` 的 overwrite 注释）。
  - 结论：WebDAV **源**这一侧的幂等语义直接复用 `mkdirAll` 即可，不必自己判 405/409。
  - 但 crypt 的 `ensureDirectory` 仍要自己逐级走：每一级都要单独 `_mapToInner` 加密，源层不认识加密，没法把「整条路径」交给 `mkdirAll`。
  - 待定：`CloudSource` 是否也加一个 `ensureDirectory`（默认逐级 `mkdir`），还是 crypt 只调 `src.mkdir` 并自行吞掉已存在错误——取决于 :451 那侧对 405/409 的处理是否已经吞干净。
- 包侧能力（此前已核实，无需推 pub）：`E:\openlist_crypt\lib\src\stream_encrypter.dart` 的 `RcloneStreamEncrypter`（`header()` / `push()` / `close()` / `fileNonce` / `cipherBytesProduced`，O(64KiB) 内存）就是上传孪生件；`RcloneCipher.encryptedSize` 是静态方法。
- secretbox 引擎：上传 `encryptBlock` 与解密 `decryptBlock` 共用同一引擎选择，自动继承「优先 libsodium」设置，**不需要新增开关**。

### 3.3 兼容层（CloudDriveService）三个写方法

`lib/services/cloud_drive_service.dart`：

| 位置 | 现状 | 目标 |
| --- | --- | --- |
| `writeBytes(:417-419)` | 无条件 `throw UnsupportedError(_writeDisabled)` | 转 `_requireDriver(accountId).uploadStream(...)` |
| `writeFromFile(:425-447)` | 已有 `if (driver is CryptDriver)` 特判 | **删特判**，统一走 `uploadStream` |
| `ensureDirectory(:450-452)` | 无条件 `throw` | 转驱动 `ensureDirectory` |

- `_writeDisabled = 'err.cloudWriteDisabled'`，常量声明在 :582（另有 :418 / :446 / :451 使用点）。
- 已可用的配角：`_remote(:589)`、`_requireDriver(:611)`；`readAsBytes(:396-414)` 已经能走 crypt（`rawUrl == null` → `driver.openContent`）。
- `capabilitiesFor(:59-70)`：云盘优先 `_drivers[accountId]?.runtimeCapabilities`，WebDAV 走 `AccountCaps.forWebdav`。

### 3.4 六个入口判定（要改为能力判定）

| 文件:行 | 现状 |
| --- | --- |
| `lib/screens/network_library_screen.dart:350-356` | `_canUpload`，关键行 :354 `account.providerType != 'webdav'` → return false |
| `lib/utils/upload_backend.dart:11-17` | `accountCanUpload`，关键行 :15 `if (providerType != 'webdav') return false;`；doc 注释 :6-10 **已过时** |
| `lib/services/sync_service.dart:226-239` | `targetAccount`，:233 / :238 `providerType == 'webdav'` |
| `lib/screens/sync_screen.dart:963-973` | 同步网盘根账号判定，:966 / :970 |
| `lib/screens/sync_screen.dart:1052-1061` | 下拉 items 过滤，:1056 |
| `lib/screens/manga_library_screen.dart:717-729` | `_uploadCapableAccounts`，:723；同文件 :776-779 `sourceCanUpload` |

**正确范式**（照抄即可）：`lib/screens/webdav_folder_picker_screen.dart:214`
`context.read<CloudDriveService>().can(_accountId, AccountCaps.mkdir)`。
相邻的 `_canCreateFolder`（`network_library_screen.dart:342-346`）已经是这个范式。

### 3.5 不该合并的判断（有证据，别顺手改）

- **路由判断**：`lib/services/webdav_service.dart` 的 `_cloudOf(:541-545)` 与全文件 14 处分流样板（:147/:176/:195/:234/:277/:319/:367/:380/:399/:445/:455/:462/:475/:493/:506）——WebDAV 走原生 client、云盘走驱动，**类型判断是路由的必要条件**。
- **存储 / 凭证判断**（序列化格式不同，合并会丢数据）：`lib/services/accounts_service.dart:505/525`、`lib/services/backup_service.dart:130`、`lib/services/credential_vault_service.dart:54`、`lib/providers/app_state.dart:55`（WebDAV 源工厂）。
  - `backup_service.dart:155` `if (a.providerType != 'webdav') continue;` 是**死代码**（:130 已 continue 覆盖全部非 webdav），可删。
- `lib/services/cloud_drive_service.dart:50` `isCloudType` = **谁接管**，不是能力，不要拿它当能力位。

### 3.6 已确认的真 bug：basePath 双拼（读 + 写都中招）

- `lib/services/cloud_drivers/crypt/crypt_driver.dart:176` `parts = <String>[src.basePath]` —— `_mapToInner` **已经拼了 basePath**。
- `lib/services/cloud_drivers/webdav_source.dart:31` `_join(path) => cloudJoinPath([basePath, path])` —— 源层每个方法**又拼一次**（:35/:50/:82/:86/:90/:94/:98/:109）。
- 触发条件：WebDAV 源账号 `remotePath` 非根（如 `/vault`）→ 实际请求打到 `/vault/vault/...` → 404。
- 为什么一直没暴露：① `basePath == '/'` 时 `cloudJoinPath`（cloud_driver.dart:118-124，各段去首尾斜杠、空段忽略、以 `/` 开头）归一后无害；② 测试假源不调 `_join`（`test/crypt_driver_test.dart` 的 `FakeCloudSource.list(:57)` / `get(:80)` / `writeFile(:129)` 直接拿传入路径查表，`basePath => '/src456'`）。
- 根因是 `CloudSource` 契约（`cloud_driver.dart:248-284`）**没说清传入 path 是相对 basePath 还是已绝对含之**。修法二选一（必须统一契约）：`_mapToInner` 不拼 basePath，或源层不再 `_join`。
- 坐实测试：`test/crypt_basepath_double_join_test.dart`（134 行，**未提交、未跑绿**）。当前版本是第二版——第一版起 `HttpServer` 断言 404，**两测试全绿但不该绿**（404 没让 readDir / PUT 抛错）。教训：**不要用 HTTP 状态码断言，要在 `_join` 出口截获路径**。第二版用 `_RecordingWebDavService extends WebDavService` 覆写 `listDirectory` / `writeStream` 记录最终 path，断言 `'/vault'.allMatches(requested).length >= 2` 且 `startsWith('/vault/vault/')`，**注释已注明「修复后这两个测试应该失败」**。

### 3.7 要同步的文档与注释（这是推翻设计决定，不是补 TODO）

- `docs/99-IN-PROGRESS.md:222`（§4.2 第 1 条「上传砍掉」）与 `:230`（§4.2 第 8 条，含用户原话「同步和备份也无法实现，只遍历 webdav 类型即可」）。
- 代码注释同步点：`cloud_drive_service.dart:27/:416/:424`、`cloud_driver.dart:8/:308`、`webdav_service.dart:391`、`task_queue_service.dart:3140`。
- 其他引用：`legacy/infrastructure.md:20/:136`、`docs/02-NETWORK-LIBRARY.md:94`。
- **15 个云盘驱动文件里「write 一律不给（99 §7.2.1）」对云盘仍然成立，不用改**——本次只放行「驱动声明了自己能写」的路径（crypt 继承源）。

### 3.8 读侧现状（已统一，是写侧要照抄的模板）

- 唯一入口：`lib/services/webdav_service.dart:170-190` `resolveStreamSource`（doc 明写「新代码一律用这个」）；云盘账号转 `CloudDriveService.resolveStreamSource(:531-578)`。
- 机制：`LocalStreamBridge.expose(accountId, remotePath, size, name, ranges: (p, s, e) => driver.openContentRange(p, s, e))` → `WebDavStreamSource(uri: 回环 URL)`。
- 桥（`lib/services/cloud_drivers/stream_bridge.dart`）：`HttpServer.bind(InternetAddress.loopbackIPv4, 0)`，token 映射 `(accountId, path)`，**有效区间恒回 206 + Content-Range**，空闲 10 分钟自动关。这就是用户说的「虚拟文件层」。
- 调用点（11 处）：`library_cover_art.dart:220`、`audio_player_service.dart:224`、`library_screen.dart:1478/:1697`、`network_library_screen.dart:474`、`playlist_detail_screen.dart:394/:476`、`manga_reader_prep.dart:147`、`music_prefetch_service.dart:357`、`video_player_screen.dart:423`、`task_queue_service.dart:2793/:2865/:3262/:3602`、`webdav_source.dart:51`。
- **crypt 的 Range 是原生支持**：`crypt_driver.dart:588` `Stream<List<int>> openContentRange(String path, int start, int end)`，按块边界精确解密（`_fetchRange(:903)` / `_fetchRangeWithMeta(:958)` / `_decryptBatch(:703)` / `_decryptAll(:725)`，批约 1 MiB `_blocksPerBatch`，:37 注释「网络按批」）；源不支持 Range 时退化整包。已被 `CloudDownloadMode.cryptRange` 用于下载续传（`cloud_drive_service.dart:347/:368`）。
- **CBZ 刮削对 crypt 本来就能跑**：`_runMangaScrape`（`task_queue_service.dart:2845-2914`）只**远程读** + 只**写本地**（ComicInfo.xml / 首页 → 本地封面），走 `resolveStreamSource` + `CbzRangeZip`；`CbzRangeZip._rangeBytes`（`lib/utils/cbz_range_zip.dart:165-254`）要求**严格 206**（拿到 200 就抛 `CbzRangeUnsupportedException`），而桥恒定回 206。所以 crypt 的 CBZ 不需要新增写能力就能刮削 —— 缺的只是入口判定。
- 反过来，「cbz 打包物化」（把散图打成 CBZ 传回远端）才是**写**路径，走 `writeFromFile` 上传链。

---

## 4. 实施顺序（用户已确认）

1. `CloudDriver` 加 `uploadStream` / `ensureDirectory`（crypt 实现，默认抛 `err.cloudWriteDisabled`）。
2. 兼容层三个写方法改成能力分流，删掉 `if (driver is CryptDriver)`。
3. 六处入口改查 `CloudDriveService.can(id, AccountCaps.write)`；`lib/utils/upload_backend.dart` 可删或退化为薄封装。
4. 测试：
   - `test/manga_pack_upload_target_test.dart:7-37` 现有三断言（webdav+all → true；webdav+list|read → false；`aliyundrive_open`+all → **false**，注释「a cloud drive cannot upload even if a write bit is set」）——第 3 条在 crypt 放行后需要**重新表述**（按驱动是否声明可写，而不是按类型名）。
   - `test/crypt_driver_test.dart:294-341` crypt 上传回环（路径逐段解密、密文长度 = 预算、`decrypt(密文) == 原明文`、进度单调）。
   - `test/crypt_basepath_double_join_test.dart` 跑绿（当前未跑）。
5. `docs/99-IN-PROGRESS.md` §4.2 第 1 / 第 8 条同步。

每步验证：`pwsh -File tool\flutter-sandbox.ps1 Analyze`（期望 `No issues found!`）+ `pwsh -File tool\flutter-sandbox.ps1 Test <file>`。

---

## 5. 环境与工具备忘（踩过的坑）

- **Flutter 一律走沙箱包装脚本**：`tool\flutter-sandbox.ps1 {Analyze|Test|GenL10n}`。不要直接 `flutter analyze`。
- **LOOP_GUARD_DUPLICATE 会误判**：任何「看起来重复」的调用会被拦，连续几次后**所有工具**都会被拦（曾导致 Write/Edit/Read/Grep 全灭）。对策：换参数、换工具，或稍等再试；不要硬撞。
- `write` 偶发 `Error: ReplaceFileW EIO (Win32 1175)`，重试即可（曾发生一次）。
- 测试里覆写 `writeStream` 时 `cancelToken` 目前写成 `dynamic`（因为没 import dio）；若 `Analyze` 报 `invalid_override`，改成 `CancelToken?` 并 `import 'package:dio/dio.dart';`。
- 早前「起 HttpServer 断言 404」的双拼测试**不该绿却绿了**——见 §3.6 的教训。

---

## 6. 未决 / 待核验

0. **写这份文档的一轮里源码一行未改**——只做了调研 + 本文档，`lib/` 与 `android/` 下没有改动，当时工作区唯一的新文件就是 §3.6 那个未提交的测试。
   **补充（2026-10-15，核查时发现）**：工作区此后已出现 5 个源文件的改动，与 §4 步骤 ①②③ 的范围完全吻合，**不是本文档这轮做的**（疑似用户插入提示词的那个 running agent 已在实施）：
   `lib/services/cloud_driver.dart` (+18/-2)、`lib/services/cloud_drive_service.dart` (+55/-46 形态)、`lib/utils/upload_backend.dart`、`lib/screens/network_library_screen.dart`、`lib/services/sync_service.dart`（`git diff --stat`：5 files changed, 51 insertions(+), 46 deletions(-)）。
   接手时请先 `git diff` 确认这批改动的归属与完成度，别在未看清的情况下叠加。本文档的「源码现状」描述一律以 §3 与 §8 的记录为准，不代表当前工作区。
1. `test/crypt_basepath_double_join_test.dart` **尚未跑绿**（文件在工作区，未提交）。
2. ~~basePath 双拼的修法二选一还没定~~ → **已定**：由 crypt 侧修，`_mapToInner` 不再拼 `src.basePath`（见 §2.1 第 1 项）；`CloudSource` 契约文档要同步写明「传给源层的 path 相对 basePath」。
3. `ensureDirectory` 对「已存在」的静默判定：**现成件已找到**——WebDAV 源可直接复用 `lib/services/webdav_service.dart:443-451` 的 `client.mkdirAll`（幂等；`createFolder:454-458` 才是单级 `client.mkdir`）。剩余待核：`mkdirAll` 对 405/409 的实际处理，以及 crypt 侧逐级 `_mapToInner` 后每级都要吞「已存在」。
4. **crypt 上传的真机验证**：WebDAV 流式 PUT 的 Content-Length 是否被服务端接受、取消语义是否真的生效（cancelToken 目前未透传源层）。
5. `lib/services/webdav_service.dart:18-20` 类注释仍写「音乐播放从不使用远端流」，但 `audio_player_service.dart:224` 已在调 `resolveStreamSource` —— **注释至少过时**，需一并订正。
6. ~~**大合并留后续，本次不做**~~ —— **已作废（2026-10-15）**：大重构是**当前工作**，见 §8，写侧统一是它的第一个可提交单元。
   （当时给的理由「读侧已由 `resolveStreamSource` / `LocalStreamBridge` 统一、写侧统一后收益递减」只够支持「暂缓」，不足以否决；实际合并面仍有 24 个门面成员与 10 个直接 import 方待收编，见 §8.2。）

---

## 7. 关键文件索引

| 文件 | 作用 |
| --- | --- |
| `lib/services/cloud_driver.dart` | `CloudDriver` / `CloudSource` / `CloudFileItem` / `CloudDriverException` / `AccountCaps`；新增两个写原语的落点 |
| `lib/services/cloud_drivers/crypt/crypt_driver.dart` | crypt 驱动；`uploadContent(:1007)` 待提升为 `uploadStream`；`_mapToInner(:169)` 是双拼嫌疑点 |
| `lib/services/cloud_drivers/webdav_source.dart` | `WebDavAccountSource`；`_join(:31)` 是双拼嫌疑点 |
| `lib/services/cloud_drive_service.dart` | 兼容层；`writeBytes(:417)` / `writeFromFile(:425)` / `ensureDirectory(:450)` 是三个改造点 |
| `lib/services/webdav_service.dart` | 对外 API 门面；`resolveStreamSource(:170)` 是读侧统一入口，`writeStream(:424)` 是写侧源层原语 |
| `lib/services/cloud_drivers/stream_bridge.dart` | 本地流桥（虚拟文件层实现） |
| `lib/utils/upload_backend.dart` | 待退化的固定类型判定 |
| `lib/screens/network_library_screen.dart` | 上传菜单与 `_canUpload(:354)` |
| `docs/99-IN-PROGRESS.md` | §4.2 第 1 / 第 8 条是要改写的设计决定 |

---

## 8. 大重构（**当前工作**）：目标、合并面清点、已定方案

> **口径更正（2026-10-15）**：本文件第 3 行的用途句、以及 §6 第 6 条「大合并留后续，本次不做」
> **均已作废**。大重构就是当前工作，§4 的「写侧统一」是它的**第一个可提交单元**，不是全部。
> 本节起以本文档为准。

### 8.1 目标

云端操作只有唯一来源——调用方不再需要知道账号类型，不再各自判断能力：

- **对外入口统一**：`WebDavService` 的 24 个公开成员与 `CloudDriveService` 的对应方法收敛成一层。
- **能力判断统一**：所有入口一律查 `can(accountId, AccountCaps.xxx)`，不再有 `providerType` / `isCloudType` 式判断。
- **数据结构统一**：`WebDavItem` ↔ `CloudFileItem` 归一。
- **路由层处理**：`webdav_service.dart:541-545` 的 `_cloudOf` 与全文件 14 处分流样板，删除或降级为一层薄适配。

### 8.2 合并面清点（2026-10-15 实测，可直接引用）

**`WebDavService` 公开成员（24 个）**

| 类别 | 成员 |
| --- | --- |
| 状态 | `isConnected:41` / `baseUrl:45` / `registeredAccountIds:49` / `hasAccount:52` |
| 连接 | `configure:68` / `disconnect:103` / `setActiveAccount:118` |
| 流 | `buildStreamSource:135` / `resolveStreamSource:170` |
| 探测 | `testConnection:194` |
| 读 | `listDirectory:229` / `statPath:276` / `downloadToFile:306` / `readAsBytes:366` |
| 写 | `writeBytes:375` / `writeFromFile:392` / `writeStream:424` / `ensureDirectory:444` |
| 结构 | `createFolder:454` / `deletePath:461` / `renamePath:469` / `copyPath:488` / `movePath:501` |
| 遍历 | `collectFilesRecursive:518` |
| 诊断 | `toString:567` |
| 路由 | `_cloudOf:541-545` + 14 处分流 |

**import 关系（爆炸半径）**：`lib/` 下共 **29 个文件**提到这两个服务（含 `webdav_service.dart` 自身）→ 外部 **28 个**。

- **只 import `WebDavService`：18 个文件** —— 改造中**保持签名零改动**：
  `screens/image_viewer_screen.dart`、`screens/library_screen.dart`、`screens/playlist_detail_screen.dart`、`screens/subtitle_remote_picker_screen.dart`、`screens/video_player_screen.dart`、`services/audio_player_service.dart`、`services/library_backfill.dart`、`services/library_sync_store.dart`、`services/manga_reader_prep.dart`、`services/manga_sync_store.dart`、`services/music_prefetch_service.dart`、`services/playlist_service.dart`、`services/task_queue_service.dart`、`services/video_queue_controller.dart`、`utils/manga_scan_walk.dart`、`utils/scan_candidates.dart`、`widgets/library_cover_art.dart`、`services/cloud_drivers/webdav_source.dart`
- **直接 import `CloudDriveService`：10 个文件** —— **必须迁移**：
  `main.dart`、`providers/app_state.dart`、`screens/accounts_screen.dart`、`screens/manga_library_screen.dart`、`screens/network_library_screen.dart`、`screens/webdav_folder_picker_screen.dart`、`services/backup_service.dart`、`services/credential_vault_service.dart`、`services/sync_service.dart`、`utils/upload_backend.dart`

**数据结构差异**（`lib/models/webdav_item.dart` ↔ `lib/services/cloud_driver.dart` 的 `CloudFileItem`）

| 字段 | `WebDavItem` | `CloudFileItem` | 冲突 |
| --- | --- | --- | --- |
| `name` | :15 | :80 | 一致 |
| 是否目录 | `isDirectory:17` | `isDir:81` | 纯改名 |
| `size` | `int?:18`（null = 未知） | `int:82`（默认 0） | **语义冲突，见 8.3 第 2 项** |
| `modified` | :19 | :83 | 一致 |
| `path` | :16 有（完整路径） | 无 | 见 8.3 第 4 项 |
| `category` | :23 `FileCategory` | 无 | 见 8.3 第 3 项 |
| `rawUrl` / `rawHeaders` | 无 | :86 / :89 | WebDAV 侧直链由 `buildStreamSource` 现算 |
| 派生属性 | `isAudio`/`isVideo`/`isCue`/`isImage`/`isComic`:25-29 | 无 | 调用方大量依赖，不能丢 |

### 8.3 已定方案（五项按最佳方案判定，**不要再问**）

1. **迁移方向：`WebDavService` 是唯一对外门面，`CloudDriveService` 降为内部实现**（能力表 + 驱动注册 + 云盘路由）。
   - 依据：只 import `WebDavService` 的有 18 个文件，直接 import `CloudDriveService` 的只有 10 个——收编朝人多的一侧，要动的调用点最少。
   - 落地三步，**每步可回退**：① `WebDavService` 加 `can()` / `capabilitiesFor()` 转发 → ② 10 个文件逐个改用门面 → ③ 删掉所有直接 import。
2. **`size` 语义：统一为 `int?`，`null` = 未知，`0` = 真实空文件。**
   - 依据：`WebDavItem` 已是 `int?`；且现有调用点已有「无法确定大小」的明确报错（`err.downloadSizeUnknown|name`、`err.streamSizeUnknown|name`），把未知压成 0 会与真 0 字节文件混淆。
3. **`FileCategory` 归属：留在上层（门面），不下沉驱动层。**
   - 依据：它由用户可配的 `FileTypeConfig` 扩展名表决定，属于**策略**；`CloudDriver` 接口层的自我约束是不依赖账号 / 存储 / 配置（`cloud_driver.dart:132-137`、`:377-379`）。驱动只报客观事实（名字 / 是否目录 / 大小 / 时间 / 直链）。
4. **`CloudFileItem` 补 `path`：补，但由门面层在返回时填充**（门面知道请求路径），驱动可选填、**驱动实现零改动**。
   - 依据：统一后调用方需要完整路径；让每个驱动各自补会牵动全部驱动文件，收益不成正比。补字段与补实现是两件事，不要混做。
5. **爆炸半径：不承诺全体零改动。** 边界写死：只 import `WebDavService` 的 18 个文件保持签名零改动；直接 import `CloudDriveService` 的 10 个文件必须迁移（清单见 8.2）。
   - 注：设计文档 §4.2 第 2 条那句「14 个文件全部零改动」与实际数量不符，实施以 §8.2 清点为准。

### 8.4 验收口径

- 门面之外**不存在**任何 `providerType` / `isCloudType` 形式的**能力**判断（路由判断除外，见 §3.5）。
- 28 个外部 import 方中，除 8.3 第 1 项明确要迁移的 10 个外，其余 **diff 为空**。
- `pwsh -File tool\flutter-sandbox.ps1 Analyze` 无 issue；现有测试全绿。
