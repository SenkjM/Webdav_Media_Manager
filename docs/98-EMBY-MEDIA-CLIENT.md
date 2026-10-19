# 98 · Emby 兼容媒体库客户端

> **状态：远期项目，暂不实现。本文件只保留路径与设计，不排期、不开工。布局提案 + demo 脚手架已落地（见 [EMBY-MEDIA-LAYOUT.md](EMBY-MEDIA-LAYOUT.md)），完整浏览与播放仍未排期。**
> 总索引：[00-INDEX.md](00-INDEX.md)
> 关联：[01](01-DATA-MODEL.md)（身份约定）、[03](03-MUSIC-LIBRARY.md)（现有音乐库）、[08](08-SYNC-AND-BACKUP.md)（同步与备份）、[11](11-CLOUD-DRIVER-PORTING.md)（云盘驱动实现）、[99](99-IN-PROGRESS.md)（开发中文档 §20 Emby 媒体库）、[EMBY-MEDIA-LAYOUT.md](EMBY-MEDIA-LAYOUT.md)（UI 布局建议）

---

## 0. 方向变更说明（pivot）

> **原方向（已放弃）**：把现有音乐库按 **OpenList 媒体库**（`dev-media` 分支）重构，对接其自有
> API（`/api/fs/media/*` + `/api/admin/media/*`）。这套 API **自成一套，非 Emby 兼容**。
>
> **新方向（当前）**：远程媒体库后端改为对接 **Emby / Jellyfin MediaBrowser REST API**。
> Jellyfin 说同一套 API（相同路径、相同 `X-Emby-Authorization` 头，也接受 `X-Emby-Token`/`api_key`），
> 因此一个客户端同时覆盖 Emby 与 Jellyfin。

本文登记这条**远期路线**：把现有音乐库按 **Emby / Jellyfin 媒体库**的概念重构为通用媒体库，
远程后端走 MediaBrowser REST API。

**本文写的是目标形态（设计），与源码冲突时以源码和测试为准。** 代码当前只有 demo 脚手架
（`feat/emby-media` 分支：连接管理 + Views/条目浏览），无完整实现。

---

## 1. 设计主线

- **本地库**：本地 SQLite，利用现有**网盘兼容层 + WebDAV** 取文件，抽象层路由**直接读写本地库**。
- **远程库**：抽象层路由到 **Emby/Jellyfin MediaBrowser REST API**，操作**同一套语义**。
- **若干个远程库**：客户端可同时配置多个远程地址，每个是独立的一个"库"。
- **本地 / 远程可切换**：同一份界面与调用方，切后端即可。
- **操作集合以远程 API 支持的为核心**：本地操作向 API 看齐。
- **鉴权在抽象层实现**：路由到远程库时，抽象层自动附加凭证，调用方不接触 token。
- **CUE 等"客户端已有、上游未实现"的能力**：保持本地独立表，Emby/Jellyfin 无对应语义。

---

## 2. 总体架构

```
   UI / screens
        │
   MediaLibraryService          ← 领域层：扫描 / 刮削 / 条目 CRUD / 查询
        │
   MediaLibraryBackend          ← 【抽象层接口】本地库与远程库共同实现
        │  （鉴权在这一层完成：路由到远程时自动附加凭证与操作对象）
   ┌────┴─────────────────────────┐
   │                              │
LocalMediaBackend            RemoteMediaBackend
（SQLite 本地库）              （Emby/Jellyfin HTTP API）
```

### 2.1 抽象层职责（含鉴权）

```dart
abstract class MediaLibraryBackend {
  String get libraryId;
  Set<MediaCapability> get capabilities;
}
```

- **凭证存储**：Emby 远程库用**独立连接表 `emby_connections.db`** + secure storage
  （见 [EMBY-MEDIA-LAYOUT.md §5](EMBY-MEDIA-LAYOUT.md)）。**不得**扩展 `accounts.provider_type`。
  **令牌一律不进日志、不进提交**；stream/download URL 内嵌 `api_key`，也不记录日志。
- 抽象层只看 `capabilities`，不写 `if (backend is RemoteBackend)`（与 [11 §13.1](11-CLOUD-DRIVER-PORTING.md) 纪律一致）。

### 2.2 CloudDriver 层保持零改动

媒体库不是驱动：

| | `CloudDriver`（[11](11-CLOUD-DRIVER-PORTING.md)） | 媒体库抽象层 |
|---|---|---|
| 语义 | 字节在哪、怎么拿 | 元数据、扫描、刮削、条目 |
| 形态 | 无状态、即时 CRUD | 有状态、持久化表 |

---

## 3. 数据库基本架构（远期，demo 阶段未建本地媒体库表）

字段设计沿用原方案：路径身份（`music_id = sha1(sourceName + remotePath)`）+ Emby 兼容列 +
本应用保留列。Emby 侧以 `Item.Id`（服务端 GUID）为远程主键，抽象层在映射时补
`source_name`（连接 id）。Emby 无 `bitrate`/`sample_rate`/`disc_*`，本地保留列解决。

`accounts`/`cache_groups`/`cache_access`/`deleted_tracks`/`sync_state` 沿用现状，
语义见 [01 §2](01-DATA-MODEL.md)。

---

## 4. Emby / Jellyfin API 操作清单

### 4.1 鉴权

| 操作 | 端点 | 备注 |
|---|---|---|
| 用户名+密码登录 | `POST /Users/AuthenticateByName` | JSON `{"Username","Pw"}` → `AccessToken` + `User.Id` |
| 用户列表（apiKey 模式解析 userId） | `GET /Users` | 用 API Key 调，取第一个非禁用用户 |
| 每个请求的头 | `X-Emby-Authorization` | `MediaBrowser Client="WDMM", Device, DeviceId, Version[, Token]` |
| 认证后额外头 | `X-Emby-Token` | 与 `Token=` 同值 |
| URL 内嵌令牌 | `api_key=<token>` | stream/download URL 专用；**不记录日志** |

### 4.2 浏览（demo 脚手架已接通）

| 操作 | 端点 | 参数 |
|---|---|---|
| 库视图列表 | `GET /Users/{UserId}/Views` | → `Items[]`（Id, Name, CollectionType） |
| 条目分页 | `GET /Users/{UserId}/Items` | `ParentId`, `IncludeItemTypes`, `Recursive`, `StartIndex`, `Limit`, `SortBy`, `SortOrder`, `SearchTerm`, `ArtistIds`, `AlbumIds`, `Fields` |
| 艺术家 | `GET /Artists/AlbumArtists` | `ParentId`, `UserId`, `StartIndex`, `Limit` |
| 封面图 | `GET /Items/{Id}/Images/{type}` | `maxWidth`, `tag`（图请求带 `X-Emby-Token` 头加载） |

### 4.3 音乐辅助（thin wrapper over getItems）

| 操作 | 实现 |
|---|---|
| 专辑列表 | `getItems(ParentId=view, IncludeItemTypes=MusicAlbum, Recursive=true)` |
| 专辑曲目 | `getItems(ParentId=album, IncludeItemTypes=Audio, SortBy=ParentIndexNumber,IndexNumber,SortName)` |
| 全部歌曲 | `getItems(ParentId=view, IncludeItemTypes=Audio, Recursive=true)` |

### 4.4 流 / 下载 URL（含 `api_key`，**不记录日志**）

| 操作 | URL |
|---|---|
| 音频流 | `{base}/Audio/{Id}/stream?static=true&api_key=<token>` |
| 视频流 | `{base}/Videos/{Id}/stream?static=true&api_key=<token>[&Container=...]` |
| 下载 | `{base}/Items/{Id}/Download?api_key=<token>` |

### 4.5 本地独有（远程后端显式 `UnsupportedError`）

rev 时钟、墓碑（`deleted_tracks`）、同步游标（`sync_state`）、CUE 相关全部操作。

### 4.6 远期（本文件不设计细节）

转码 HLS 子系统——Emby/Jellyfin 转码可选，远期若做播放后端再单独设计。
播放进度上报（`POST /Sessions/Playing`）当前 TODO（见 §6 R8）。

---

## 5. 身份模型

Emby/Jellyfin 三层身份：

- **ServerId**：登录返回（`AuthenticateByName` 响应里的 `ServerId`），标识一个服务器实例。
- **UserId**：Emby 用户 ID（非秘密，持久化在 `emby_connections.user_id`，首次登录后由服务端返回）。
- **ItemId**：每个媒体条目的 GUID（`Item.Id`），用于图片/流/下载等按条目操作的路径参数。

与本地 `music_id = sha1(sourceName + remotePath)` 的对齐：远程后端在抽象层补
`source_name = connectionId`，`remotePath` 用 `Item.Path`（若有）或 `Item.Id` 兜底。
**该对齐是 Phase 2 再定**，当前 demo 脚手架只做在线浏览，不写本地库。

---

## 6. 主要风险（远期开工前必须复核）

| # | 风险 | 说明 |
|---|---|---|
| R1 | **云端分片同步失效** | `library_shard_codec.dart` / `sync_service.dart` 编码了曲目身份；换表可能让已同步用户数据全废。**未核实** |
| R2 | 上游字段缺口 | Emby 无 `bitrate`/`sample_rate`/`disc_*`；本地保留列解决 |
| R3 | 单位 / 语义变化 | `RunTimeTicks`（ticks/10_000 = ms）→ `Duration`；`Artists` 是 JSON 数组；`UserData.Played/IsFavorite` 嵌套对象 |
| R4 | **"库里有什么"的定义变了** | [03](03-MUSIC-LIBRARY.md) 曲库 = 本地已缓存曲目；`Items` 是元数据层（含未下载条目） |
| R5 | **令牌吊销** | Emby AccessToken 可能被吊销；客户端需 401 → 重登一次（密码从 secure storage 取） |
| R6 | **Emby vs Jellyfin 分歧** | 较新 Jellyfin 把 `/Users/{id}/Items` 部分路径标记 deprecated；Emby Premiere 锁部分功能 |
| R7 | 转码不在范围 | demo 只 `static=true` 直链；转码子系统远期单独设计 |
| R8 | 播放进度上报 TODO | `POST /Sessions/Playing` 等上报未接；远期做播放集成时补 |
| R9 | 改动面大 | 15 个文件依赖 `tracks`（见 §7） |
| R10 | 无渐进 migration | [01 §2](01-DATA-MODEL.md)：换 schema 即 DROP 重建 |

---

## 7. 影响面

依赖 `tracks` 表的现有文件（15 个）：

```
lib/providers/app_state.dart            lib/services/library_sync_store.dart
lib/screens/library_screen.dart         lib/services/settings_service.dart
lib/screens/player_screen.dart          lib/services/share_rename_service.dart
lib/screens/playlist_detail_screen.dart lib/services/sync_service.dart
lib/services/backup_service.dart        lib/widgets/library_cover_art.dart
lib/services/cache_service.dart         lib/services/library_shard_codec.dart
lib/services/download_queue_service.dart lib/services/library_service.dart
lib/services/library_actions.dart       lib/services/library_database.dart
```

---

## 8. 远期实施工序（不排期，仅供开工时参考）

1. 核实 R1（读 [08](08-SYNC-AND-BACKUP.md) + 三个 codec 文件），判定是否阻塞。
2. 定抽象层接口与 `MediaLibraryBackend` / `MediaLibraryRouter`。
3. 建本地库（schema），实现 `LocalMediaBackend`。
4. 一次性搬迁 `tracks` → `media_items`（含 R3 映射与单位换算），带测试。
5. `LibraryService` 改走 `MediaLibraryService` → 抽象层，15 个文件逐个迁移。
6. 实现 `RemoteMediaBackend`（Emby/Jellyfin API），能力位显式标注。
7. 重构音乐库功能为媒体库功能。
8. 收口：按 [00 §1](00-INDEX.md) 把语义写进完整文档。

---

## 9. 未决问题

- [ ] R1 结论：云端分片格式是否受影响？（决定能否安全落地）
- [ ] 本地库与远程库关系：互斥切换，还是本地为主 / 远程为镜像？
- [ ] 「本地库」是否作为用户可见概念进 UI？
- [ ] 多个远程库时，`source_name` 用连接 id 还是显示名？改名如何不丢身份？
- [ ] Emby vs Jellyfin 分歧：是否需要按 ServerId 探测后端类型分支？
- [ ] 播放进度上报（`/Sessions/Playing`）何时接入？
- [ ] 转码子系统是否做？
- [ ] 图片缓存：`Image.network` 直接加载封面，是否接入 `CachedNetworkImage`？
