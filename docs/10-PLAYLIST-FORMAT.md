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

新增 `WmpFileKind` 成员 `PL`，magic 为 `WDMMPL01`。登记进 `documents` 集合与 `WmpKind` 双生常量后，`WmpContainer.looksLikeContainer` / `kindOf` / 版本诊断（「由更新版本写入」）对歌单文件**自动生效**。

按 `WmpFileKind` 的既定约定，加一个文件类是「这里一行 + `WmpKind` 双生一行」，另在 `metaKindOf` / `forMetaKind` 各加一个 case。

### 4.2 段布局

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

### 4.3 备份里的歌单段改为内嵌完整歌单文件（用户决定）

**现状**：备份用 `PLAYLISTS=6` 装一坨 **JSON**（`backup_service.dart` 的 `WmpSections.playlists` → `jsonEncode(payload['playlists'])`），恢复侧用 `jsonList(6)` 解回。

**决定**：备份**不再内嵌歌单 JSON**，改为内嵌**完整的 `.wdmp` 歌单文件字节**。备份因此成为「歌单文件的容器」，与远端 `playlists/` 目录里放的东西**同一种编码**。

- 备份里的一个歌单 = 一段，payload 就是该歌单 `.wdmp` 文件的原始字节（走 `rawIds` 不 deflate——它在写入前已是压缩容器）。
- 恢复 = 把每段字节当作独立 `.wdmp` 文件解码，走与拉取远端歌单**完全相同**的解码路径。编码只有一处，不会漂移。
- `PLAYLISTS=6` 的语义随之变化：从「歌单 JSON」变成「歌单文件字节」。因为不保留历史兼容，旧备份不读，所以不复用、不兼容——实现时直接改语义或换新 id 均可。
- 收益：备份自包含且与同步同构；同一份歌单在两个出口只有一种编码。
- 代价：备份文件略大（每个歌单各带自己的容器头 + META，而 JSON 版是一整坨共享一个头）。单歌单头部 12 字节 + 每段表项 18 字节，可忽略。

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

**不保留历史兼容（用户决定）**：不写旧 M3U8 的读取路径，不做旧备份的兼容读取。旧格式文件视为不存在。

- **读**：只认 `.wdmp`。远端 `playlists/` 下的 `.m3u` / `.m3u8` **不再扫描**。
- **写**：一律写 `.wdmp`。
- **清理**：首次同步删除远端的 `.m3u` / `.m3u8`，避免同一歌单两种格式各留一份、且旧文件可能被外部工具当成有效歌单。
- **回退风险**：降级回旧版本 App 后看不到任何云端歌单（本地 `playlists.db` 仍在，但旧版本只认 `.m3u8`）。这是明确接受的代价，需在发版说明里写明。
- **不做一次性迁移工具**：按「不考虑历史兼容」的指示，旧 `.m3u8` 不转换。若实际存在需要保住云端歌单的用户，这一条要重新评估。

## 5. 实现位置

现状：

- `lib/services/playlist_service.dart`：CRUD、双向同步编排、LWW 合并
- `lib/services/playlist_store.dart`：`playlists.db`（表 `playlists`，字段 `id` / `name` / `updated_at` / `remote_file_name` / `entries_json`）
- `lib/models/playlist.dart`：`Playlist` / `PlaylistEntry`
- `lib/utils/m3u8_playlist.dart`：M3U8 编解码（待替换）

计划新增：

- `lib/utils/wmp_container.dart`：登记 `PL` 文件类与 `ENTRIES` 段 id
- `lib/services/playlist_codec.dart`：歌单容器编解码（**不含**旧 M3U8 兼容读取）
- `lib/utils/track_identity.dart`：`musicId` 参与歌单条目身份

## 6. 与其它文档的关系

- [01-DATA-MODEL.md](01-DATA-MODEL.md)：容器与魔数、`musicId` 身份定义
- [03-MUSIC-LIBRARY.md](03-MUSIC-LIBRARY.md)：销毁语义（谁删谁不删）
- [08-SYNC-AND-BACKUP.md](08-SYNC-AND-BACKUP.md)：远端路径与同步方式
