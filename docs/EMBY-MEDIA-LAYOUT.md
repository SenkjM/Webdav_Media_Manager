# Emby 兼容媒体库客户端 UI 布局建议

> **状态：布局已定 + demo 脚手架已落地（`feat/emby-media`：连接管理 + Views 列表 + 条目浏览 + 音乐子 Tab）；完整播放与进度上报仍未做。见 [99 §20](99-IN-PROGRESS.md)。**
> 相关文档：[98-EMBY-MEDIA-CLIENT.md](98-EMBY-MEDIA-CLIENT.md)（远期设计）、[99-IN-PROGRESS.md](99-IN-PROGRESS.md#20-emby-兼容媒体库客户端)

---

## 1. 概述

本客户端作为 **Emby / Jellyfin 媒体库的只读/浏览侧**接入现有应用：
- **不替换**现有音乐库（仍是本地 SQLite + WebDAV 下载缓存模式）。
- **平级接入**：抽屉里新增一条「Emby」入口，与现有音乐库、网络库并列。
- **只接 Emby/Jellyfin MediaBrowser REST API**，不混入现有网盘兼容层。
- **已出布局建议 + demo 脚手架**（连接 / Views / 条目浏览 / 音乐子 Tab），不替换现有音乐库。

---

## 2. 抽屉入口

### 2.1 插入位置

**已锁定插入位置**：**索引 5**（任务队列之前、网络库之后）：

```
0. 文件夹
1. 音乐库
2. 歌单
3. 漫画库
4. 网络库
5. Emby          ← 新增（原 OpenList）
6. 任务队列
7. 设置
```

### 2.2 标签与图标

- **标签**：`Emby`（固定英文，不本地化）
- **图标**：`Icons.cloud_circle_outlined`

### 2.3 迁移注意点

一次性迁移旗标 `home_tab_v026_emby_inserted`（branch 从未 ship，安全重命名）：
若用户主页设置在「任务队列」(5) 或「设置」(6) → 新值 +1；其余不受影响。

---

## 3. 屏幕与导航结构

主屏名：`EmbyMediaScreen`（`lib/screens/emby_media_screen.dart`）。

### 3.1 Views 顶层 → 条目浏览

```
EmbyMediaScreen
 └─ _EmbyBrowseView (per connection)
     ├─ Views 列表（GET /Users/{id}/Views）
     └─ 点击 View → 条目分页（GET /Users/{id}/Items?ParentId=...）
         ├─ 文件夹 → 下一级 ParentId
         ├─ CollectionType='music' → 音乐子 Tab（见 §3.2）
         └─ 可播放条目 → 底部弹窗 + "播放（未接入）"（TODO）
```

### 3.2 音乐 View 内子 Tab

`CollectionType == 'music'` 时显示 SegmentedButton：

```
专辑  |  艺术家  |  歌曲
```

- 专辑：`getMusicAlbums(viewId)` → 封面网格
- 艺术家：`getArtists(viewId)` → 列表/网格
- 歌曲：`getItems(viewId, IncludeItemTypes=Audio, Recursive=true)` → 列表

---

## 4. API 映射表（Emby/Jellyfin MediaBrowser 端点）

| 界面 | 端点 | 参数 |
|---|---|---|
| Views 列表 | `GET /Users/{UserId}/Views` | — |
| 条目分页 | `GET /Users/{UserId}/Items` | `ParentId`, `IncludeItemTypes`, `Recursive`, `StartIndex`, `Limit=50`, `SortBy`, `SortOrder`, `Fields` |
| 专辑列表 | `GET /Users/{UserId}/Items` | `IncludeItemTypes=MusicAlbum`, `Recursive=true` |
| 专辑曲目 | `GET /Users/{UserId}/Items` | `ParentId=albumId`, `IncludeItemTypes=Audio`, `SortBy=ParentIndexNumber,IndexNumber,SortName` |
| 艺术家 | `GET /Artists/AlbumArtists` | `ParentId`, `UserId`, `StartIndex`, `Limit` |
| 封面图 | `GET /Items/{Id}/Images/Primary` | `maxWidth`, `tag`；以 `X-Emby-Token` 头加载 |
| 音频流（TODO） | `{base}/Audio/{Id}/stream` | `static=true&api_key=<token>`；**不记录日志** |
| 视频流（TODO） | `{base}/Videos/{Id}/stream` | `static=true&api_key=<token>`；**不记录日志** |
| 下载（TODO） | `{base}/Items/{Id}/Download` | `api_key=<token>`；**不记录日志** |
| 登录 | `POST /Users/AuthenticateByName` | JSON `{"Username","Pw"}` |

---

## 5. 鉴权机制与集成（已实现）

### 5.1 认证模式

| 模式 | 存储键 | 说明 |
|---|---|---|
| `password` | `emby_password_<id>` (密码) + `emby_token_<id>` (AccessToken) | 调 `POST /Users/AuthenticateByName` → AccessToken + UserId |
| `api_key` | `emby_apikey_<id>` | API Key 直接用作 token；UserId 通过 `GET /Users` 解析 |

### 5.2 请求头

每个请求附加：
```
X-Emby-Authorization: MediaBrowser Client="WDMM", Device="<platform>",
                      DeviceId="<conn.deviceId>", Version="0.0.0"[, Token="<token>"]
X-Emby-Token: <token>          # 认证后附加
Accept: application/json
```

`buildAuthorizationHeader(deviceId, token, platform, version)` 为纯函数，直接单元测试。

### 5.3 401 重登

token 收到 401 → `invalidateToken(id)` → 若 password 模式且 secure storage 有密码 → 重登一次 → 重试。
API Key 模式不重登（key 被删除需用户手动更新）。

---

## 6. 账号管理与隔离边界

### 6.1 独立连接管理（不复用 `accounts` 表）

**连接表**：`emby_connections.db`，表 `emby_connections`（独立于 `library.db` / `accounts`）

字段：`id`, `label`, `base_url`, `auth_mode`, `username`, `user_id`, `device_id`, `sort_order`

**Secure storage 键**：
- `emby_token_<id>`：缓存的 AccessToken
- `emby_password_<id>`：明文密码（password 模式，静默重登用）
- `emby_apikey_<id>`：API Key（apiKey 模式）

**不复用 `accounts` 表**：现有 `accounts` 有 14+ 个调用点（网络库、下载、同步、crypt 源），
接入会产生冲突。OpenList/Emby 媒体库不是字节层驱动。

### 6.2 功能隔离

| 功能 | Emby 媒体库 | 现有网络库 / 音乐库 | 隔离边界 |
|---|---|---|---|
| 浏览元数据 | MediaBrowser HTTP API | WebDAV PROPFIND / 云盘 REST | 完全独立 |
| 流式播放 | TODO（接入现有播放栈） | 同左 | 共享播放栈，不共享元数据来源 |
| 下载 | TODO | WebDAV GET / 云盘直链 | 待定 |
| 同步 | 不做（服务端资源） | 本地 SQLite 与云端双向同步 | 完全独立 |

**禁止调用**：`LibraryService`、`SyncService`、`CacheService.touch*`、`WebDavService`、`CloudDriveService`。

**允许调用**（Phase 2）：`AudioPlayerService`、`VideoPlaybackService`、`DownloadQueueService.enqueue*`。

---

## 7. 分阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| **Phase 0（已完成）** | 布局文档 + demo 脚手架（抽屉入口 + 连接管理 + Views/条目浏览 + 音乐子 Tab） | ✅ 已落地 |
| Phase 1 | 完整分页浏览、搜索、图片缓存（`CachedNetworkImage`）、Jellyfin 兼容性核验 | 待排期 |
| Phase 2 | 接入播放栈（复用 `AudioPlayerService`/`VideoPlaybackService`）、播放进度上报（`/Sessions/Playing`） | 待排期 |
| Phase 3 | 本地媒体库后端（`LocalMediaBackend`）、本地/远程同构切换 | 远期 |

---

## 8. 明确不做

- 改动现有音乐库（仍保持本地 SQLite + 缓存模式）
- 接入 `CloudDriver` 层（媒体库不是驱动，是元数据层）
- 上传 / 写操作
- 转码子系统（Phase 2 可能接直链播放申请端点，转码远期单独设计）
- 评论或推送 Emby/Jellyfin 上游仓库

---

## 9. 关键技术点

### 9.1 路径身份对齐（Phase 2 再定）

本地 `music_id = sha1(sourceName + remotePath)`。Emby 远程后端需在抽象层补 `source_name = connectionId`，
`remotePath` 用 `Item.Path`（若有）或 `Item.Id` 兜底。

### 9.2 封面图加载

`Image.network(imageUrl, headers: {'X-Emby-Token': token})` 带认证头加载。
Phase 1 可升级为 `CachedNetworkImage` 减少重复请求。

### 9.3 分页

`Limit=50`，`StartIndex` 累加，`hasMore = startIndex + items.length < totalRecordCount`。
滚动到底部 200px 内自动触发下一页（`NotificationListener<ScrollNotification>`）。

---

## 10. 未决问题

- [ ] 播放器集成策略：复用现有 `AudioPlayerService` / `VideoPlaybackService` 还是新建 Emby 专用播放器？
- [ ] 图片缓存：何时升级到 `CachedNetworkImage`？
- [ ] Emby vs Jellyfin 分歧：是否需要按 ServerId 探测后端类型分支？（Jellyfin 较新版把部分路径标记 deprecated）
- [ ] 刮削队列桥接：是否将 Emby 元数据回填到本地 library.db，还是只从服务端动态获取？
