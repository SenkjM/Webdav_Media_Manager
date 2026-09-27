# 10 · 歌单格式与身份

> 编号 10 · 总索引：[00-INDEX.md](00-INDEX.md)

歌单是与[音乐库](03-MUSIC-LIBRARY.md)**平行**的一等数据：它有自己的独立数据库、自己的远端目录、自己的持久化格式。它**不是**曲库的附属品，也不是曲库的视图。

**当前状态（现状）**：歌单使用扩展 M3U8 文本格式（见 §3）。§4 起的二进制容器格式是**计划（未实现）**，原始语义与取舍见 [99 §5.0](99-IN-PROGRESS.md)。

## 1. 核心命题：歌单 = 小型音乐库

歌单与曲库的**管理方式**同构：

| 维度 | 音乐库 | 歌单 |
|------|--------|------|
| 本地权威存储 | `music_library.db` | `playlists.db` |
| 远端镜像目录 | `<远端路径>library/` | `<远端路径>playlists/` |
| 远端编码 | 二进制容器，`lib-` / `seg-` / `del-` 分片 | 计划：二进制容器，一首歌单一个文件 |
| 条目身份 | `musicId` = `sha1(网盘名 + 归一化路径)` | 计划：同 `musicId` + 歌单自身 `id` |
| 删除语义 | 墓碑 `del-*.wdmm` | 计划：文件删除 + 墓碑 |
| 改动传输 | 增量（只传变化行） | 计划：整文件重写（单文件小） |

**关键区别**：曲库是**一个大库分片存储**（因为可能上万行，分片才能增量）；歌单是**多个小库各自成文件**（每个歌单独立管理、独立同步、独立删除）。这是刻意的：歌单数量多但每个都很小，按文件管理比按行管理更自然，也让单个歌单的增删不影响其它歌单。

## 2. 歌单与曲库的边界（重要）

**销毁曲目只影响音乐库，不影响歌单。**

- 歌单条目引用的是「网盘名 + 路径」这一**身份**，不是曲库里的行。
- 从曲库「销毁」一首歌（[03](03-MUSIC-LIBRARY.md)）只删除本地的库行、缓存音频、封面与墓碑；**歌单条目原样保留**。
- 后果是被销毁的歌在歌单里显示为「库中暂无」（见 §2.2），而不是被歌单删除。

**唯一例外是整库销毁**：`AppState.destroyMusicLibrary()` 在逐首销毁后会调 `playlists.removeEntriesNotIn(const {})`（`app_state.dart`），即清空全部歌单条目。这是「销毁整个音乐库」这个用户的显式选择，不是销毁单曲的语义。

### 2.1 已修复的错误绑定

**现状（修复前）**：`PlaylistService.removeEntriesNotIn(validKeys)` 会被当作「孤儿清理」调用，把不在曲库里的歌单条目**直接删掉**。歌单条目因此被曲库的存亡绑架——曲库重建、扫描失败、路径归一化差异都会**静默删除**用户歌单条目。

**应有语义（本次改动）**：歌单条目与曲库行**解耦**。曲库里没有的歌只是「未解析」，**不构成删除理由**。歌单条目的删除只能来自用户的显式操作（从歌单移除 / 删除歌单）。

- 界面表现为「库中暂无 · 来源网盘」标记（`playlist_detail_screen.dart` 的 missing 分支），条目仍在、仍会随歌单同步走。
- 整库销毁是唯一例外（见上）。

### 2.2 未解析状态

歌单条目可能因为以下原因暂时或永久解析不到曲库行：

- 曲目被销毁（本地库行已删）——**这是正常的、允许长期存在的状态**
- 曲库尚未扫描到该路径
- 来源网盘被重命名（身份里的「网盘名」变了）
- 路径书写变体（前导斜杠、`//`、反斜杠）

这些一律显示为「库中暂无」，**不触发任何删除**。

## 3. 现状实现：扩展 M3U8（待替换）

每个歌单一个文件，落在 `<远端路径>playlists/<安全名>_<id 前 8 位>.m3u8`。

```
#EXTM3U
#EXT-X-WMP-ID:<uuid>
#EXT-X-WMP-UPDATED:<iso8601>
#EXT-X-WMP-NAME:<名称>
#EXTINF:<秒>,<标题>
wmp://<网盘名>/<remotePath>
```

最后写入胜出由 `#EXT-X-WMP-UPDATED` 判定。编解码在 `lib/utils/m3u8_playlist.dart`。**`WMP` 前缀是历史产品缩写、属于磁盘格式，不得改名**——已同步的歌单依赖它。

**为什么换掉**：这个格式对**外部软件零可用性**——

- `wmp://` 是自定义 scheme，不是 `http(s)://`，外部播放器无法解析；
- `//` 后跟的是**网盘显示名**，不是主机名；URI 语义下这是非法 authority；
- 网盘名 → 真实地址的映射**只存在本 App 的本地账号表里**（[01](01-DATA-MODEL.md)：URL / 用户名 / 密码刻意不参与身份），外部世界无法还原；
- `#EXT-X-` 前缀是 HLS 的标准组合，`.m3u8` + `#EXT-X-` 会让其它工具**误认为这是 HLS 索引**。

结论：这个文件对任何非本项目的软件都是「解析得动、但一条都放不出来」的歌单。**通用格式带来的唯一"收益"是误导，因此不再保留。**

## 4. 计划格式：`WdmpContainer` 二进制容器（未实现）

复用音乐库与备份已有的 [WmpContainer](01-DATA-MODEL.md) 基础设施（魔数 `WDMM` + 文件类 + 段表 + CRC32 + deflate），**不发明第二套容器**。差异只在**文件类**与**段布局**。

### 4.0 已使用的魔数（现状，一字不差）

魔数固定 8 字节：`WDMM` + 文件类(2) + 布局版本(2)。

| 常量 | 文件类 | 完整魔数 | 含义 |
|------|--------|----------|------|
| `appTag` | — | `WDMM` | 全局标识，每个二进制文件都以它开头 |
| `layoutVersion` | — | `01` | 容器布局版本，所有文件类共用 |
| `WmpFileKind.base` | `LB` | `WDMMLB01` | 曲库基础分片（重建时写的大切片） |
| `WmpFileKind.seg` | `LS` | `WDMMLS01` | 曲库增量分片（只含新增 / 修改行） |
| `WmpFileKind.tomb` | `LT` | `WDMMLT01` | 曲库墓碑分片（删除记录） |
| `WmpFileKind.backup` | `BK` | `WDMMBK01` | 整机备份归档 |
| `WmpFileKind.exportBundle` | `EX` | `WDMMEX01` | 保留：可分享的曲库包 |
| `WmpFileKind.credentials` | `CR` | `WDMMCR01` | 保留：凭证 / 保管库包 |
| `WmpFileKind.envelope` | `EN` | `WDMMEN01` | 加密外壳，**不是 document**，可包裹任意 document 类文件 |

- `documents` 集合 = `{LB, LS, LT, BK, EX, CR}`；`EN` 刻意不在其中，因此 `looksLikeContainer` 永不接受一个加密外壳。
- 段 id 现状（`WmpSections`）：`META=1`、`TRACKS=2`、`COVERS=3`、`TOMBS=4`、`CREDENTIALS=5`、`PLAYLISTS=6`、`SETTINGS=7`、`CUE_ALBUMS=8`。
- 后四个段（`CREDENTIALS` / `PLAYLISTS` / `SETTINGS` / `CUE_ALBUMS`）的源码注释都标着「Backup archives only」——它们是**备份文件的内部分区**，不是独立文件类型。
- 尤其注意：**`PLAYLISTS=6` 是备份归档内嵌的歌单 JSON 段**，不是本次要建的东西（见 §4.3）。
- 读取规则：未知段 id 直接忽略，所以**新增段不需要升容器版本**。

### 4.1 文件类（magic）

新增**两个** `WmpFileKind` 成员：

| 常量 | 文件类 | 完整魔数 | 含义 |
|------|--------|----------|------|
| `WmpFileKind.playlist` | `PL` | `WDMMPL01` | 一个歌单文件 |
| `WmpFileKind.vault` | `CV` | `WDMMCV01` | 凭证包（保管库） |

登记进 `documents` 集合与 `WmpKind` 双生常量后，`WmpContainer.looksLikeContainer` / `kindOf` / 版本诊断（「由更新版本写入」）对这两类文件**自动生效**。

按 `WmpFileKind` 的既定约定，加一个文件类是「这里一行 + `WmpKind` 双生一行」，另在 `metaKindOf` / `forMetaKind` 各加一个 case。

### 4.1.1 段 id 是 `u8`，这是一个硬约束

段表项的第一个字节就是段 id：

```dart
entry.addByte(id);          // wmp_container.dart:553 — 写
id: bytes[base],            // wmp_container.dart:505 — 读
```

`encode()` 把 `sections` 当作 `Map<int, Uint8List>`（`ids = sections.keys.toList()..sort()`），**id 必须全局唯一且落在 0–255**。

**推论（写代码前必读）**：**不能**给每个歌单分配一个独立段 id。那样全表只剩约 246 个可用 id，每加一个歌单都要动 id 分配表，且歌单数一超就写不出来。

因此备份内嵌歌单采用 **c2′**：`PLAYLISTS=6` 仍是**唯一一个段**，**段内记录数 = 歌单数**，每个歌单占一条 record，容量无上限。下文 §4.3 的「一个歌单一段」指的是**段内一条独立记录**，不是独立段 id。

### 4.2 歌单文件（`PL`）段布局

| 段 id | 名称 | 内容 |
|-------|------|------|
| `META`(1) | 元信息 | 歌单 `id` / 名称 / `updatedAt` / 条目数 / `deviceId` / `createdAt`；复用现有 `WmpMeta` 标签 |
| `ENTRIES`(9) | 条目表 | 每条：`musicId` + `sourceName` + `remotePath` + `title` + `durationMs` + （CUE 分片时）`cueTrackIndex` |
| `COVERS`(3) | 封面（可选） | 复用现有 COVERS 段与 `WmpCoverEntry` 布局 |

**`ENTRIES` 是什么**：歌单**条目表**——一个歌单里「有哪些歌」的完整列表，一条记录一首歌。它在结构上对应曲库的 `TRACKS`(2)，但**字段集不同**：

- `TRACKS` 是**曲库行**，字段多（标题 / 艺术家 / 专辑 / 音轨号 / 比特率 / CUE 关系 / 封面索引 / 各种时间戳…），因为曲库要承载完整标签。
- `ENTRIES` 是**歌单条目**，字段少——歌单只需要「指向哪首歌」+「显示什么」，**不复制标签**。标签永远从曲库取。这正是 §1 里「小型」的含义：歌单存的是**引用**，不是副本。

**为什么不复用 `TRACKS=2`**：两者语义不同（引用 vs 实体），共用 id 会让人以为它们同构。段 id 新增是零成本的（未知 id 被忽略），所以用新 id `9`。

**为什么不复用备份的 `PLAYLISTS=6`**：那个段的 payload 是 **UTF-8 JSON**（`backup_service.dart` 里 `jsonEncode(payload['playlists'])`），而 `ENTRIES` 是二进制 tag 记录表。同一个 id 在 `BK` 里是 JSON、在 `PL` 里是二进制记录表，必然误读。

- `META` / `ENTRIES` 用现有的 **tag 记录编码**（`encodeRecords` / `decodeRecords`）与现有 tag 号分配表：整数走变长、字符串走长度前缀。
- `COVERS` 段走 `rawIds`（不 deflate），与曲库分片一致——封面本来就是压缩图像。
- `META.kind` 与文件魔数**互为校验**（沿用 `LibraryShardCodec.decode` 那条「两者必须一致，否则不是该喂给本系统的文件」的规则）。
- 约束：段表里 offset / length 是 `u32`，即**单段上限 4 GiB**。歌单条目表远不到，但不要假设无限增长。

### 4.2.1 凭证包（`CV`）段布局

| 段 id | 名称 | 内容 |
|-------|------|------|
| `META`(1) | 元信息 | `formatVersion` / `deviceId` / `createdAt` / 条目数；`WmpMeta.kind` = 新增的 `WmpKind.vault` |
| `CREDENTIALS`(5) | 凭证条目表 | 每条一个账号：`id` / `name` / `providerType` / `url` / `username` / `password`(+是否加密) / `remotePath` / `driverConfig` |

**关键规则：凭证包的加密语义完全不变，只换容器。**

- `url` 与 `username` **保持明文**（现有设计如此，见 `credential_vault_service.dart` 注释「Stored in plain text by design」）。
- `password` 以及 `driverConfig` 里 `spec.secretFieldKeys` 覆盖的字段，**仍然逐字段用 `CredentialVaultCrypto`（`AESGCMv1:` 前缀，PBKDF2-SHA256 120k + AES-256-GCM）加密**，密文原样存进 tag。
- 也就是说：**加密是字段级、与应用层口令绑定的，与容器无关**。换容器不改变任何密钥派生或密文格式，口令仍然是用户的统一加密密钥。

`CREDENTIALS=5` 这个段 id **不新增**——它本来就是「备份归档 only」的凭证段，本次把 payload 从 JSON 改为二进制 record 表，语义从「凭证 JSON」变成「凭证条目表」。

**同步侧的 `credentials.json` 一并改为 `CV` 容器文件**（用户决定）：远端不再是 `.json`，而是一个 `WDMMCV01` 文件；备份内嵌的就是这个文件的字节。这样凭证在**同步与备份两个出口只有一种编码**，与歌单方案对称。

- 文件名与远端路径随之变化（`credential_vault_service.dart` 的 `fileName = 'credentials.json'`）。因为不保留历史兼容，不做旧文件读取，旧 `.json` 视为不存在并按 §4.5 的规则清理。
- 注意：`credential_vault_crypto.dart` 的字段级加密**不受影响**，它作用于字段值，不作用于文件外层。加密外壳（`WDMMEN01`）是另一回事，与本次无关。

### 4.3 备份包内部实现：改动前 vs 改动后

#### 改动前（现状）

`backup_service.dart` 调 `WmpContainer.encode({...})`，**所有非曲库数据都以 UTF-8 JSON 塞进各自的段**：

```
WDMMBK01
├─ META(1)         record 表：kind/count/deviceId/createdAt/note
│                  note = jsonEncode({format, formatVersion,
│                                    activeAccountId, passwordEncryption})
├─ TRACKS(2)       曲库行 record 表（本就二进制）          ← 不变
├─ CREDENTIALS(5)  jsonEncode(payload['credentials'])      ← JSON
├─ PLAYLISTS(6)    jsonEncode(payload['playlists'])        ← JSON
├─ SETTINGS(7)     jsonEncode(payload['settings'])         ← JSON
└─ CUE_ALBUMS(8)   jsonEncode(payload['library']['cueAlbums']) ← JSON
```

- 段内一律是**一整坨 JSON 字节**，用 `jsonDecode` 解回。
- **所有歌单挤在 `PLAYLISTS=6` 这一个 JSON 数组里**，歌单之间没有独立边界——想读第 5 个歌单也得先把整坨 JSON 解完。
- 凭证是一个 JSON 对象（`jsonSection(5)`），与同步用的 `credentials.json` 是**两份独立维护的 JSON**，字段集靠人工保持一致。
- 恢复侧：`_decodeContainer` 用 `jsonSection(id)` / `jsonList(id)` 把段解回 `Map` / `List`，组装成一个 `payload`，再交给 `_applyPayload`——即**恢复路径与同步路径是两条不同的解码逻辑**。

#### 改动后（目标）

```
WDMMBK01
├─ META(1)         record 表（同现状；note 字段保留）
├─ TRACKS(2)       曲库行 record 表                        ← 不变
├─ CREDENTIALS(5)  凭证 record 表                          ← 由 JSON 改为二进制
│                   ⇒ 内容 = 一个完整 CV 容器文件的字节，
│                     或逐条凭证 record（见下）
├─ PLAYLISTS(6)    歌单 record 表                          ← 由 JSON 改为二进制
│                   段内每歌单一条 record，record 的 blob tag
│                   = 该歌单 .wdmp 文件的完整字节
├─ SETTINGS(7)     设置 JSON                               ← 不变
└─ CUE_ALBUMS(8)   CUE 专辑 JSON                           ← 不变
```

逐项差别：

| 维度 | 改动前 | 改动后 |
|------|--------|--------|
| `PLAYLISTS=6` payload | 一个 JSON 数组，全部歌单挤在一起 | record 表，**每歌单一条记录**，容量无上限 |
| 歌单在备份里的形态 | 内联的字段副本 | **内嵌完整 `.wdmp` 文件字节**（含自己的容器头 + META + CRC） |
| 单个歌单可独立解出 | 否，必须先解整坨 JSON | **是**，取一条 record 即得一个完整容器文件 |
| `CREDENTIALS=5` payload | JSON 对象 | **`WDMMCV01` 容器字节** |
| 备份 vs 同步的凭证编码 | 两套独立 JSON，人工同步字段 | **同一份 `CV` 容器**，只有一种编码 |
| 备份 vs 同步的歌单编码 | M3U8（同步）vs JSON（备份），两套 | **同一份 `PL` 容器**，只有一种编码 |
| 恢复解码路径 | `jsonSection` / `jsonList` 组装 payload，再 `_applyPayload`——**与同步路径不同** | 内嵌字节直接喂给 `PL` / `CV` 的**同一个解码器**，与拉取远端走同一条路 |
| CRC / 完整性 | 每个 JSON 段一个 CRC（段级） | 外层段有 CRC，**内嵌容器自己还有一整套段级 CRC**——双层校验 |
| 体积 | 共享一个容器头，JSON 冗余键名 | 每歌单多 12 字节头 + 18 字节/段表项；但换来二进制编码、无键名冗余 |

**一个必须说清的取舍**：改动后内嵌的 `.wdmp` / `.cv` 字节**不再 deflate**（走 `rawIds`），因为他们本身就是压缩容器。`WmpContainer.encode` 对非 `rawIds` 段默认做 deflate——**必须记得把它们加进 `rawIds`**，否则会对已压缩数据再压一次，白费 CPU 且略微增大。

**嵌套深度只有一层**：备份 → 内嵌 `PL`/`CV` 容器，内嵌容器**不再内嵌任何容器**。不允许递归，避免解包放大攻击与深度失控。

**恢复侧的对称性**：`_decodeContainer` 里 `jsonList(6)` 这类调用被替换为「读出每条 record 的 blob → 交给 `PlaylistCodec.decode`」。这样**远端拉取与备份恢复共用同一个解码函数**，编码语义不会再漂移——这是本次改动最实质的收益。

### 4.4 身份：`musicId` 成为歌单条目的权威身份

条目身份从 `sourceName + "\0" + remotePath`（原始字符串，**不归一化**）改为 `musicId`：

```
musicId = sha1(normalizeSourceName(源) + "\0" + normalizeRemotePath(路径))
        （CUE 分片再追加 "\0" + trackIndex）
```

理由与收益：

- 与曲库**同一个主键**，歌单条目与曲库行可以 O(1) 对上，不再靠精确字符串匹配。
- 归一化（前导斜杠 / `//` / `\` / 空白折叠）**进入身份**，路径书写变体不再造成「明明有这条却匹配不上」——这正是 §2.2 里最难排查的一类。
- CUE 分片获得**显式字段** `cueTrackIndex`，不再依赖 `remotePath` 里内嵌 `#cue:<n>` 字符串这种脆弱约定。

`sourceName` 与 `remotePath` **仍然保留在条目里**，作为显示信息与回退解析依据（旧的、没有 `musicId` 的数据靠它兜底）。

### 4.5 兼容与迁移

**不保留历史兼容（用户决定）**：不写旧 M3U8 的读取路径，不写旧 `credentials.json` 的读取路径，不做旧备份的兼容读取。旧格式文件视为不存在。

- **歌单读**：只认 `.wdmp`。远端 `playlists/` 下的 `.m3u` / `.m3u8` **不再扫描**。
- **凭证读**：只认 `CV` 容器。远端 `credentials.json` **不再读取**。
- **写**：一律写新格式。
- **清理**：首次同步删除远端的 `.m3u` / `.m3u8` 与旧 `credentials.json`，避免新旧格式各留一份、且旧文件可能被外部工具当成有效数据。
- **备份读**：只认新布局。`SETTINGS(7)` 与 `CUE_ALBUMS(8)` 保持 JSON 不变；`CREDENTIALS(5)` / `PLAYLISTS(6)` 按新二进制语义解。用旧版本备份恢复会失败——应给出明确错误，**不要静默丢数据**。
- **回退风险**：降级回旧版本 App 后，云端歌单与凭证都读不到（本地 `playlists.db`、Keystore 与 secure storage 都还在，但旧版本只认 `.m3u8` / `credentials.json`）。这是明确接受的代价，需在发版说明里写明。
- **不做一次性迁移工具**：按「不考虑历史兼容」的指示，旧文件不转换。若实际存在需要保住云端歌单 / 凭证的用户，这一条要重新评估。

**一处必须谨慎的顺序要求**：凭证与歌单不同——歌单丢了可以重建，**凭证丢了就登录不上云盘**。虽然本次不做迁移，但首次同步删除远端 `credentials.json` 的时机必须保证「新的 `CV` 文件已成功写入并校验通过」。实现时应当 **先写新文件、确认写入成功、再删旧文件**，绝不反过来。这是顺序要求，不是兼容性要求。

## 5. 实现位置

现状：

- `lib/services/playlist_service.dart`：CRUD、双向同步编排、LWW 合并
- `lib/services/playlist_store.dart`：`playlists.db`（表 `playlists`，字段 `id` / `name` / `updated_at` / `remote_file_name` / `entries_json`）
- `lib/models/playlist.dart`：`Playlist` / `PlaylistEntry`
- `lib/utils/m3u8_playlist.dart`：M3U8 编解码（待替换）
- `lib/services/credential_vault_service.dart`：`credentials.json` 读写（`fileName` / `formatVersion = 2` / `push` / `pull`），待改为 `CV` 容器
- `lib/utils/credential_vault_crypto.dart`：字段级加密（`AESGCMv1:`），**本次不改**
- `lib/services/backup_service.dart`：备份打包（`WmpContainer.encode`）与恢复（`_decodeContainer` 的 `jsonSection` / `jsonList`），待改

计划新增 / 改动：

- `lib/utils/wmp_container.dart`：登记 `PL` / `CV` 两个文件类与 `WmpKind` 双生常量；新增 `ENTRIES=9` 段 id；`metaKindOf` / `forMetaKind` 各加 case
- `lib/services/playlist_codec.dart`（新）：歌单容器编解码（**不含**旧 M3U8 兼容读取）
- `lib/services/credential_vault_codec.dart`（新）：凭证容器编解码，与 `credential_vault_crypto` 的字段级加解密配合
- `lib/services/backup_service.dart`：`PLAYLISTS=6` / `CREDENTIALS=5` 改为内嵌容器字节（走 `rawIds`），恢复侧改为调用两个 codec，**去掉 `jsonList(6)` / `jsonSection(5)`**
- `lib/services/credential_vault_service.dart`：远端文件名与读写改为 `CV` 容器
- `lib/utils/track_identity.dart`：`musicId` 参与歌单条目身份

## 6. 与其它文档的关系

- [01-DATA-MODEL.md](01-DATA-MODEL.md)：容器与魔数、`musicId` 身份定义
- [03-MUSIC-LIBRARY.md](03-MUSIC-LIBRARY.md)：销毁语义（谁删谁不删）
- [08-SYNC-AND-BACKUP.md](08-SYNC-AND-BACKUP.md)：远端路径、凭证与歌单同步、备份归档
