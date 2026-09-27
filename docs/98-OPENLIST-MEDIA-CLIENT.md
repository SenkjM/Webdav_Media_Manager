# 98 · OpenList 媒体库客户端实现（远期，暂不实现）

> **状态：远期项目，暂不实现。本文件只保留路径与设计，不排期、不开工。**
> 总索引：[00-INDEX.md](00-INDEX.md)
> 关联：[01](01-DATA-MODEL.md)（身份约定）、[03](03-MUSIC-LIBRARY.md)（现有音乐库）、[08](08-SYNC-AND-BACKUP.md)（同步与备份）、[11](11-CLOUD-DRIVER-PORTING.md)（云盘驱动移植）、[99](99-IN-PROGRESS.md)（开发中文档）

本文登记一条**远期路线**：把现有音乐库按 **OpenList 媒体库**的概念重构为通用媒体库。
上游参照物是 `OpenListTeam/OpenList` 的 **`dev-media` 分支**（beta 预发布，仍在迭代）——
不是 `main`。本地 `localdev/OpenList` 与 `localdev/OpenList-Worker` 都是 `main`，**不含**媒体库。

**本文写的是目标形态（设计），与源码冲突时以源码和测试为准。** 代码当前**没有任何**媒体库实现。

---

## 1. 设计主线

以 **OpenList 媒体库为概念基准**，在客户端实现**同一套数据库结构**，并让**本地库与远程库同构**：

- **本地库**：本地 SQLite，利用现有**网盘兼容层 + WebDAV** 取文件，抽象层路由**直接读写本地库**。
- **远程库**：抽象层路由到 **OpenList HTTP API**（`/api/fs/media/*` 等），操作**同一套语义**。
- **若干个远程库**：客户端可同时配置多个远程地址，每个是独立的一个"库"。
- **本地 / 远程可切换**：同一份界面与调用方，切后端即可。
- **操作集合以远程 API 支持的为核心**：本地操作向 API 看齐（本地不得单方面多出 API 表达不了的能力，
  除非该能力明确登记为"仅本地"且上层按能力位分支）。
- **鉴权在抽象层实现**：路由到远程库时，抽象层自动为请求**附加该库对应的凭证 / 操作对象**，
  调用方不接触 token。
- **CUE 这类"客户端已有、上游未实现"的能力**：可以**同步修改上游**推进，
  上游并非金标准；最终以双方并集为准（见 §4）。

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
（SQLite 本地库）              （OpenList HTTP API）
   │                              │
本地库文件                   远程 OpenList 实例（可多个地址）
```

### 2.1 抽象层职责（含鉴权）

抽象层是**唯一路由点**，且**唯一持有凭证**：

```dart
abstract class MediaLibraryBackend {
  /// 库标识：本地库或某个远程地址
  String get libraryId;

  /// 能力位（上层据此分支，不做类型判断）
  Set<MediaCapability> get capabilities;
}

/// 库句柄：抽象层按 libraryId 解析出后端 + 凭证
class MediaLibraryRouter {
  MediaLibraryBackend resolve(String libraryId);
}
```

- **调用方只给 `libraryId`**，不给 URL、不给 token。
- 抽象层按 `libraryId` 取出该库的**地址 + 凭证 + 操作对象**，附加到请求上。
- 凭证存储复用现有账号体系（`accounts` 表 + secure storage；密文范围约定见
  [11 §6.1](11-CLOUD-DRIVER-PORTING.md)），**令牌一律不进日志、不进提交**。

> 与 [11 §13.1](11-CLOUD-DRIVER-PORTING.md) 的关系：那条"兼容层不允许按类型分支"的纪律**同样适用**——
> 抽象层只看 `capabilities`，不写 `if (backend is RemoteBackend)`。

### 2.2 与云盘兼容层的关系

**`CloudDriver` 层保持零改动。** 媒体库不是驱动：

| | `CloudDriver`（[11](11-CLOUD-DRIVER-PORTING.md)） | 媒体库抽象层 |
|---|---|---|
| 语义 | 字节在哪、怎么拿 | 元数据、扫描、刮削、条目 |
| 形态 | 无状态、即时 CRUD | 有状态、持久化表 |
| 载体 | `list` / `get` / `mkdir` / `move` / `copy` / `remove` | 自己的库表 |

媒体库**复用**驱动层取字节（`get` → `rawUrl` + `rawHeaders`；MustProxy 走
`cloud_drivers/stream_bridge.dart`），但**不挂进**驱动层。

---

## 3. 数据库基本架构（双方并集）

> **并集**：上游字段 + 本应用字段，去重后合并。分三区标注来源，便于对齐与演进。

### 3.1 `media_items` —— 媒体条目（核心表）

```sql
CREATE TABLE media_items (
  -- ═══ 规范身份（本应用 + 上游共识：路径身份）═══
  music_id      TEXT PRIMARY KEY,        -- sha1(normalizeSourceName + '\0' + normalizeRemotePath)
  source_name   TEXT NOT NULL,           -- 网盘名 / 库名（身份的一半）
  remote_path   TEXT NOT NULL,           -- 完整路径（身份的另一半）
  UNIQUE(source_name, remote_path),

  -- ═══ 上游兼容列（remote_path 的派生视图 + 上游自有）═══
  id            INTEGER,                 -- 上游自增 id
  media_type    TEXT NOT NULL,           -- video | music | image | book
  scan_path_id  INTEGER,                 -- 上游：关联扫描路径
  folder_path   TEXT NOT NULL,           -- dirname(remote_path)
  file_name     TEXT NOT NULL,           -- basename(remote_path)
  file_size     INTEGER,
  mime_type     TEXT,
  hidden        INTEGER NOT NULL DEFAULT 0,

  -- 刮削 / 展示
  scraped_name  TEXT,                    -- 上游语义：刮削后的显示名
  description   TEXT,
  cover         TEXT,                    -- URL / data-URI / 本地路径
  release_date  TEXT,                    -- YYYY-MM-DD
  rating        REAL,                    -- 0–10
  genre         TEXT,                    -- 逗号分隔
  authors       TEXT,                    -- JSON 数组字符串 ["A","B"]
  plot          TEXT,
  reviews       TEXT,                    -- JSON 数组字符串
  external_id   TEXT,                    -- TMDB / Discogs / 豆瓣 ID
  scraped_at    TEXT,

  -- 音乐专属
  album_name    TEXT,
  album_artist  TEXT,
  track_number  INTEGER,
  duration      INTEGER,                 -- 【单位：秒】
  lyrics        TEXT,                    -- LRC

  -- 视频专属（远期）
  video_type    TEXT,                    -- movie | tv
  season        INTEGER,
  episode       INTEGER,

  -- 书籍专属（远期）
  publisher     TEXT,
  isbn          TEXT,

  -- 目录合并模式（上游 path_merge）
  is_folder     INTEGER NOT NULL DEFAULT 0,
  episodes      TEXT,                    -- JSON [{file_name,index,title}]

  -- ═══ 本应用保留（远程后端忽略）═══
  rev                INTEGER NOT NULL DEFAULT 0,   -- 版本时钟，见 01 §6
  cover_path         TEXT,                         -- 本地封面文件路径
  bitrate            INTEGER,                      -- 上游无
  sample_rate        INTEGER,                      -- 上游无
  track_total        INTEGER,                      -- 上游无
  disc_number        INTEGER,                      -- 上游无（LibraryTrack 排序依赖）
  disc_total         INTEGER,                      -- 上游无
  last_downloaded_at TEXT,
  last_tag_read_at   TEXT,

  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
```

**上游缺口（本应用保留列的来由）**：`bitrate` / `sample_rate` / `track_total` /
`disc_number` / `disc_total` 在上游模型中**没有对应字段**，而 `LibraryTrack` 的排序
依赖 `disc_number` / `track_number`。故本地保留，远程后端忽略；
远期可向上游提案扩展。

### 3.2 `media_scan_paths` —— 扫描路径（上游）

```sql
CREATE TABLE media_scan_paths (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  media_type    TEXT NOT NULL,
  name          TEXT,                    -- 前端筛选显示名
  path          TEXT NOT NULL,           -- VFS 扫描路径
  path_merge    INTEGER NOT NULL DEFAULT 0,  -- 子文件夹作为一个条目（带 episodes）
  type_tag      TEXT,                    -- 电影 / 电视剧…
  content_tags  TEXT,                    -- 逗号分隔
  enable_scrape INTEGER NOT NULL DEFAULT 1,
  last_scan_at  TEXT,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
```

> `path_merge` 是上游关键设计：子文件夹作为**一个条目 + `episodes` 选集**，
> 而非逐文件平铺。对剧集 / 专辑是必须的。

### 3.3 `media_configs` —— 媒体库配置（上游）

```sql
CREATE TABLE media_configs (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  media_type     TEXT NOT NULL UNIQUE,
  enabled        INTEGER NOT NULL DEFAULT 0,
  last_scan_at   TEXT,
  last_scrape_at TEXT,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
```

### 3.4 `media_libraries` —— 库注册表（**本应用新增**）

抽象层需要知道"有哪些库、各自什么类型、什么地址、什么凭证"。
上游没有这个概念（它自己就是那个库），客户端必须有。

```sql
CREATE TABLE media_libraries (
  library_id   TEXT PRIMARY KEY,         -- 本地固定值 'local'，远程为生成的 id
  kind         TEXT NOT NULL,            -- local | remote
  display_name TEXT NOT NULL,
  base_url     TEXT,                     -- remote 专用；local 为空
  account_id   TEXT,                     -- 凭证引用（accounts 表 / secure storage）
  enabled      INTEGER NOT NULL DEFAULT 1,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
```

### 3.5 CUE 相关（本应用保留，上游无）

`cue_albums` / `cue_slices` **保持独立表**，不并入 `media_items`：

`cue_slices` 有 `media_items` 装不下的东西——`clip_start_ms` / `clip_end_ms`（播放裁切的
物理依据）、`audio_music_id`（指向真实音频行）、`cache_group_id`（整组销毁的锚点）、
自身 `music_id`（`sha1(sourceName + cuePath + trackIndex)`）。
上游只有 `episodes`(JSON)，**套不上 clip 语义**。

远期选项：**同步修改上游**，把 clip / 分片概念补进 `media_items`；在补齐前保持独立。

### 3.6 其余沿用现有表

`accounts` / `cache_groups` / `cache_access` / `deleted_tracks` / `sync_state`
沿用现状，语义见 [01 §2](01-DATA-MODEL.md)。

---

## 4. API 支持的操作（并集）

**操作集合以远程 API 为核心**（用户要求）。下表左列是上游 `dev-media` 的端点，
右列标注本应用侧是否需要扩展。

### 4.1 条目 CRUD

| 操作 | 远程 API | 本地库 | 备注 |
|---|---|---|---|
| 列表 / 分页查询 | `GET /api/admin/media/items` | ✅ | 支持 `media_type` `keyword` `order_by` `order_dir` `page` `page_size` `scan_path_id` |
| 公开列表 | `GET /api/fs/media/list` | ✅ | 多 `folder_path` `type_tag` `content_tag` |
| 详情 | `GET /api/fs/media/item/:id` | ✅ | `hidden` 返回 404 |
| 创建 / 更新 | `POST /api/admin/media/items/update` | ✅ | 上游是「先取后改」，**无独立 create**——条目由扫描产生 |
| 删除单条 | `POST /api/admin/media/items/delete?id=` | ✅ | |
| 按身份取 | — | **本地扩展** | 上游无；本地 `music_id` / `(source_name, remote_path)` 直查 |
| 批量 upsert | — | **本地扩展** | 同步 / 搬迁用；远程后端无对应 |
| 未刮削列表 | — | **本地扩展** | 上游内部 `GetUnscrappedItems`，未开放端点 |

### 4.2 扫描

| 操作 | 远程 API | 本地库 |
|---|---|---|
| 开始扫描 | `POST /api/admin/media/scan/start` | ✅ |
| 扫描进度 | `GET /api/admin/media/scan/progress` | ✅ |
| 删除失效条目 | `POST /api/admin/media/delete_invalid` | ✅ |

### 4.3 刮削

| 操作 | 远程 API | 本地库 |
|---|---|---|
| 开始刮削 | `POST /api/admin/media/scrape/start` | ✅ |
| 刮削统计 | `GET /api/admin/media/scrape/stats` | ✅ |
| 清空刮削结果 | `POST /api/admin/media/clear_scrape` | ✅ |

### 4.4 扫描路径

| 操作 | 远程 API | 本地库 |
|---|---|---|
| 列表 | `GET /api/admin/media/scan_paths` | ✅ |
| 创建 | `POST /api/admin/media/scan_paths/create` | ✅ |
| 更新 | `POST /api/admin/media/scan_paths/update` | ✅ |
| 删除 | `POST /api/admin/media/scan_paths/delete` | ✅ |
| 清空该路径数据 | `POST /api/admin/media/scan_paths/clear` | ✅ |
| 公开只读列表 | `GET /api/fs/media/scan_paths` | ✅ |

### 4.5 配置 / 清空 / 导入导出

| 操作 | 远程 API | 本地库 |
|---|---|---|
| 配置列表 | `GET /api/admin/media/config/list` | ✅ |
| 保存配置 | `POST /api/admin/media/config/save` | ✅ |
| 清空某类型 | `POST /api/admin/media/clear` | ✅ |
| 导入 | `POST /api/admin/media/import` | ✅ |
| 导出 | `GET /api/admin/media/export` | ✅ |

### 4.6 音乐专属（上游公开端）

| 操作 | 远程 API | 本地库 |
|---|---|---|
| 专辑列表 | `GET /api/fs/media/albums` | ✅ |
| 专辑曲目 | `GET /api/fs/media/album?album_name=&album_artist=` | ✅ |
| 文件夹列表 | `GET /api/fs/media/folders` | ✅ |

### 4.7 库管理（**本应用新增**，上游无）

| 操作 | 远程 API | 本地库 | 备注 |
|---|---|---|---|
| 库列表 / 增删改 | — | **本地扩展** | `media_libraries` 表，抽象层用 |
| 切库 | — | **本地扩展** | 纯客户端概念 |

### 4.8 本地独有（远程后端显式 `UnsupportedError`，不假装支持）

- `upsertBatch` / `getUnscraped` / `getByIdentity`
- rev 时钟、墓碑（`deleted_tracks`）、同步游标（`sync_state`）
- CUE 相关全部操作

### 4.9 远期（本文件不设计细节）

`/api/fs/transcode/play` 与 `/tc/…` HLS 转码子系统——上游 `transcode_enabled` **默认关**，
是可选独立子系统。远期若做播放后端再单独设计。

---

## 5. 身份模型

**路径身份，双方共识**：

```
music_id = sha1(normalizeSourceName(sourceName) + '\0' + normalizeRemotePath(remotePath))
```

实现见 [`lib/utils/track_identity.dart`](../lib/utils/track_identity.dart)，**不改**。

- `source_name` = 网盘名 / 库名（URL、用户名、密码**不参与**，见 [01 §1](01-DATA-MODEL.md)）。
- `folder_path` / `file_name` 是 `remote_path` 的**派生视图**，不是独立事实——
  避免两处真相不一致。
- **上游不是金标准**：上游 `media_items` 目前无 `source_name` 列，唯一键是
  `(file_name, folder_path, album_name)`，多网盘挂载同一媒体库会串。
  远期可**同步修改上游**，加 `source_name` 并把唯一键改为
  `(source_name, remote_path)`。**该修改不阻塞本地实现**——远程后端在抽象层
  补 `source_name` 映射即可。

---

## 6. 主要风险（远期开工前必须复核）

| # | 风险 | 说明 |
|---|---|---|
| R1 | **云端分片同步失效** | `library_shard_codec.dart` / `library_sync_store.dart` / `sync_service.dart` 编码了曲目身份；换表可能让**已同步用户数据全废**。**未核实**，开工第一件事 |
| R2 | 上游字段缺口 | `bitrate` / `sample_rate` / `track_total` / `disc_*` 上游无（§3.1）；本地保留列解决 |
| R3 | 单位 / 语义变化 | `duration_ms` → `duration`（**ms→秒**）；`artist` → `authors`（**单值→JSON 数组**）；`title` → `scraped_name`；`year` → `release_date`。静默出错高危 |
| R4 | **"库里有什么"的定义变了** | [03](03-MUSIC-LIBRARY.md) 的曲库 = **本地已缓存曲目**；`media_items` 是**元数据层**（含未下载条目）。这是**语义上最大的变化**，不只是换表，会让 [03 §2](03-MUSIC-LIBRARY.md) 的已缓存判定、[§3](03-MUSIC-LIBRARY.md) 的销毁语义与新模型冲突 |
| R5 | 上游 beta 未定型 | schema 可能再变；本地保留自有列 + 抽象层 adapter 隔离 |
| R6 | 改动面大 | 15 个文件依赖 `tracks`（见 §7） |
| R7 | 无渐进 migration | [01 §2](01-DATA-MODEL.md)：换 schema 即 DROP 重建。本次是**换库**，需独立一次性搬迁 |
| R8 | 远程鉴权差异 | `/api/admin/media/*` 需 AuthAdmin，`/api/fs/media/*` 是用户态，能力集不同 |

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

`cache_service.dart`（缓存文件名推导，`identityHashStem`）与
`library_shard_codec.dart` / `sync_service.dart`（云端分片 wire format）是**最高风险**的三处。

---

## 8. 远期实施工序（不排期，仅供开工时参考）

1. 核实 R1（读 [08](08-SYNC-AND-BACKUP.md) + 三个 codec 文件），判定是否阻塞。
2. 定抽象层接口与 `MediaLibraryBackend` / `MediaLibraryRouter`。
3. 建本地库（§3 schema），实现 `LocalMediaBackend`。
4. 一次性搬迁 `tracks` → `media_items`（含 §6 R3 映射与单位换算），带测试。
5. `LibraryService` 改走 `MediaLibraryService` → 抽象层，15 个文件逐个迁移，
   每步跑 `flutter analyze` + 相关测试。
6. 实现 `RemoteMediaBackend`（`/api/fs/media/*`），能力位显式标注。
7. 重构音乐库功能为媒体库功能。
8. 收口：按 [00 §1](00-INDEX.md) 把语义写进完整文档。

---

## 9. 未决问题

- [ ] R1 结论：云端分片格式是否受影响？（决定能否安全落地）
- [ ] 本地库与远程库关系：互斥切换，还是本地为主 / 远程为镜像？
- [ ] 「本地库」是否作为用户可见概念进 UI？
- [ ] 多个远程库时，`music_id` 里的 `source_name` 用什么？（库 id 还是库显示名？改名如何不丢身份）
- [ ] 远程库鉴权用 admin token 还是用户 token？凭证如何进现有加密范围（[11 §6.1](11-CLOUD-DRIVER-PORTING.md)）
- [ ] CUE 是否同步修改上游（rather than 长期独立表）
- [ ] 上游 `dev-media` 若改名 / 合并入 `main`，兼容层如何应对
- [ ] 是否向上游提案 `source_name` + `bitrate`/`sample_rate`/`disc_*` 字段
