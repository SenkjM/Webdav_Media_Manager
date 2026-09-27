# 10 · 歌单格式与身份

> 编号 10 · 总索引：[00-INDEX.md](00-INDEX.md)

歌单是与[音乐库](03-MUSIC-LIBRARY.md)**平行**的一等数据：它有自己的独立数据库、自己的远端目录、自己的持久化格式。它**不是**曲库的附属品，也不是曲库的视图。

**当前状态（现状）**：歌单使用扩展 M3U8 文本格式（见 §3）。§4 起的二进制容器格式是**计划（未实现）**，原始语义与取舍见 [99 §X](99-IN-PROGRESS.md)。

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

### 4.1 文件类（magic）

新增 `WmpFileKind` 成员 `PL`，magic 为 `WDMMPL01`。与现有 `LB` / `SE` / `DL` / `BK` / `EN` 并列，落在同一张文件类表里，因此 `WmpContainer.looksLikeContainer` / `kindOf` / 版本诊断（「由更新版本写入」）对歌单文件**自动生效**。

### 4.2 段布局

| 段 id | 名称 | 内容 |
|-------|------|------|
| `META` | 元信息 | 歌单 `id` / 名称 / `updatedAt` / 条目数 / `deviceId` / `createdAt` / 格式版本 |
| `ENTRIES` | 条目表 | 每条：`musicId` + `sourceName` + `remotePath` + `title` + `durationMs` + （CUE 分片时）`cueTrackIndex` |
| `COVERS`（可选） | 封面 | 复用现有 COVERS 段与 `WmpCoverEntry` 布局 |

- `META` / `ENTRIES` 用现有的 **tag 记录编码**（`encodeRecords` / `decodeRecords`）与现有 tag 号分配表，与曲库分片同样紧凑：整数走变长、字符串走长度前缀。
- `COVERS` 段走 `rawIds`（不 deflate），与曲库分片一致——封面本来就是压缩图像。
- `META.kind` 与文件魔数**互为校验**（沿用 `LibraryShardCodec.decode` 里那条「两者必须一致，否则不是该喂给本系统的文件」的规则）。

### 4.3 身份：`musicId` 成为歌单条目的权威身份

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

### 4.4 兼容与迁移

- **读**：拉取时同时扫 `*.wdmp`（新）与 `*.m3u` / `*.m3u8`（旧）。同 `id` 时新格式优先。
- **写**：一律写新格式。
- **迁移**：首次同步把旧格式歌单重写为 `.wdmp` 并删除旧文件。删除是**必要**的——否则同一歌单会以两种格式各存在一份，下次拉取时按 `id` 合并虽然能去重，但旧文件会永远留着并可能被外部工具当成有效歌单。
- **回退风险**：降级回旧版本 App 后，旧版本只认 `.m3u8`，会看不到全部歌单（本地 `playlists.db` 仍在，但任何一次拉取都看不到它们）。这是接受的代价，需在发版说明里写明。

## 5. 实现位置

现状：

- `lib/services/playlist_service.dart`：CRUD、双向同步编排、LWW 合并
- `lib/services/playlist_store.dart`：`playlists.db`（表 `playlists`，字段 `id` / `name` / `updated_at` / `remote_file_name` / `entries_json`）
- `lib/models/playlist.dart`：`Playlist` / `PlaylistEntry`
- `lib/utils/m3u8_playlist.dart`：M3U8 编解码（待替换）

计划新增：

- `lib/utils/wdmp_container.dart` 或扩展 `wmp_container.dart`：`PL` 文件类登记
- `lib/services/playlist_codec.dart`：歌单容器编解码（含旧 M3U8 兼容读取）
- `lib/utils/track_identity.dart`：`musicId` 参与歌单条目身份

## 6. 与其它文档的关系

- [01-DATA-MODEL.md](01-DATA-MODEL.md)：容器与魔数、`musicId` 身份定义
- [03-MUSIC-LIBRARY.md](03-MUSIC-LIBRARY.md)：销毁语义（谁删谁不删）
- [08-SYNC-AND-BACKUP.md](08-SYNC-AND-BACKUP.md)：远端路径与同步方式
