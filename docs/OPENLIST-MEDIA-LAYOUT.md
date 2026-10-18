# OpenList 媒体库客户端 UI 布局建议(计划,未实现)

> **状态:计划阶段,本文档只写布局建议,不实现 UI 代码。**
> 相关文档:[98-OPENLIST-MEDIA-CLIENT.md](98-OPENLIST-MEDIA-CLIENT.md)(远期设计)、[99-IN-PROGRESS.md](99-IN-PROGRESS.md#20-openlist-媒体库客户端布局阶段进行中)

---

## 1. 概述

本客户端作为 **OpenList 媒体库的只读/浏览侧**接入现有应用:
- **不替换**现有音乐库(仍是本地 SQLite + WebDAV 下载缓存模式)。
- **平级接入**:抽屉里新增一条「OpenList」入口,与现有音乐库、网络库并列。
- **只接 OpenList 媒体 HTTP API**(`/api/fs/media/*` + 部分 `/api/admin/media/*`),不混入现有网盘兼容层。
- **本阶段只出布局建议**,不写 `lib/` 实现代码(除非为了让分支有意义的极小 scaffold)。

---

## 2. 抽屉入口

### 2.1 插入位置

当前抽屉顺序(`lib/screens/home_shell.dart:114-131`):
```
0. 文件夹
1. 音乐库
2. 歌单
3. 漫画库
4. 网络库
5. 任务队列
6. 设置
```

**已锁定插入位置**:**索引 5**(任务队列之前、网络库之后):
```
0. 文件夹
1. 音乐库
2. 歌单
3. 漫画库
4. 网络库
5. OpenList          ← 新增
6. 任务队列
7. 设置
```

理由:
- OpenList 是**远程库**,语义更接近「网络库」,排在网络库后比排在曲库之后更符合用户预期。
- 任务队列/设置是功能工具,排在最后保持不变。

### 2.2 标签与图标

- **标签**:`OpenList`(固定英文,不本地化)
- **图标**:`Icons.cloud_circle_outlined`(云 + 圆环,区别于网络库的 `Icons.cloud_outlined`)

### 2.3 迁移注意点

插入新条目后,`home_tab_index` 存储键需要一次性迁移(类似 `home_tab_v024_folders_inserted` / `home_tab_v025_manga_inserted`):
- 若用户主页设置在「任务队列」(5) 或「设置」(6) → 新值 +1
- 其余不受影响

---

## 3. 屏幕与 Tab 结构

主屏建议名:`OpenListMediaScreen`(`lib/screens/openlist_media_screen.dart`)。

### 3.1 Tab 划分(建议:视频/音乐/图片/书籍 四 Tab,对齐 MediaType)

```
OpenListMediaScreen
 └─ TabController (4 tabs)
     ├─ 视频 (video)
     ├─ 音乐 (music)
     ├─ 图片 (image)
     └─ 书籍 (book)
```

每个 Tab 内结构:
- **列表/网格视图**(复用 `FolderViewMode`)
- **搜索**(AppBar 搜索框,传 `keyword` 给 API)
- **多选**(工具栏复用 `SelectionToolbar`)
- **筛选**(可选,见 §3.2)

### 3.2 备选方案:专辑/文件夹/扫描路径子视图(仅音乐,暂定平铺列表)

若音乐 Tab 要做分组浏览:
- **专辑列表**:`PublicListAlbums` → 分页专辑卡片 → 点开进「专辑详情」调 `PublicGetAlbum`
- **文件夹浏览**:`PublicListFolders` → 文件夹列表 → 选一个文件夹后调 `PublicListMedia?folder_path=...`
- **扫描路径筛选**:`PublicListScanPaths` → 下拉选择 → 传 `scan_path_id` 给 `PublicListMedia`

其它三类(视频/图片/书籍)暂时只做平铺列表。

---

## 4. API 映射表与鉴权层级

### 4.1 核心端点(`/api/fs/media/*`,Auth(true)允许 guest)

| 界面 | API 端点 | 必需鉴权 | 参数 | 用途 |
|------|---------|----------|------|------|
| 视频 Tab | `GET /api/fs/media/list` | Auth(true) | `media_type=video`, `page`, `page_size`, `order_by`, `order_dir`, `keyword` | 平铺列表 |
| 音乐 Tab | `GET /api/fs/media/list` | Auth(true) | `media_type=music`, `page`, `page_size`, `keyword` | 平铺列表 |
| 音乐 · 专辑 | `GET /api/fs/media/albums` | Auth(true) | `page`, `page_size`, `keyword`, `scan_path_id?` | 专辑列表 |
| 音乐 · 专辑详情 | `GET /api/fs/media/album` | Auth(true) | `album_name`, `album_artist` | 专辑内曲目 |
| 音乐 · 文件夹 | `GET /api/fs/media/folders` | Auth(true) | `media_type=music` | 文件夹列表 |
| 图片 Tab | `GET /api/fs/media/list` | Auth(true) | `media_type=image`, … | 平铺列表 |
| 书籍 Tab | `GET /api/fs/media/list` | Auth(true) | `media_type=book`, … | 平铺列表 |
| 条目详情 | `GET /api/fs/media/item/:id` | Auth(true) | 路径参数 `id` | 单条元数据 |
| 筛选 · 扫描路径 | `GET /api/fs/media/scan_paths` | Auth(true) | `media_type?` | 路径下拉选项 |

**鉴权级别说明**:
- **Auth(true)** → 允许 guest(空 token)、站点 token(admin)、JWT(普通用户)
- 媒体 handler 内**无额外权限检查**,依赖上游 `fsAndShare` 中间件放行
- guest 用户(user_id=2)可浏览媒体库,但无写权限(媒体 API 本身是只读)

### 4.2 管理侧端点(`/api/admin/media/*`,AuthAdmin 强制,暂不实现)

以下端点需要管理员权限(`AuthAdmin` 拦截非 admin),**本阶段不做 UI**:
- 扫描路径 CRUD(`/scan_paths/create|update|delete|clear`)
- 扫描进度 / 启动扫描(`/scan/start|progress`)
- 刮削进度 / 启动刮削(`/scrape/start|stats`)
- 删除失效条目 / 清空库(`/delete_invalid|clear|clear_scrape`)
- 导入 / 导出(`/export|import`)

未来若做管理侧,可在「设置」里新增「OpenList 管理」子页。

---

## 5. 鉴权机制与集成建议(已查证上游源码)

### 5.1 上游鉴权机制(OpenList `server/middlewares/auth.go` + `server/handles/auth.go`)

1. **空 token** → guest 用户(user_id=2,role 权限位 0)
2. **站点 token**(setting `Token`) → admin(user_id=1,role 权限位 2)
3. **JWT token**(`/api/auth/login` 或 `/api/auth/login/hash` 签发) → 普通用户(role=1),Claims 含 `username` + `pwd_ts`

**媒体 API 路由**(`server/router.go:234-252`):
- `/api/fs/media/*` 挂在 `fsAndShare(api.Group("/fs", middlewares.Auth(true)))` 下
- `Auth(true)` 的 `allowDisabledGuest=true` 参数允许 guest 放行(即使 guest 被禁用也能访问)

**admin 端点路由**(`server/router.go:131-226`):
- `/api/admin/media/*` 挂在 `admin(auth.Group("/admin", middlewares.AuthAdmin))` 下
- `AuthAdmin` 强制 `user.IsAdmin()` 为真

### 5.2 集成建议(凭证存储与请求构造)

**方案一(推荐):存 JWT + refresh 机制**
- 用户在 OpenList 账号表单填**用户名 + 密码**,客户端后台调 `/api/auth/login/hash`(密码先 sha256 再传)换 JWT
- JWT 存 secure storage 键 `openlist_jwt_<accountId>`
- 每次请求带 `Authorization: <JWT>` 头
- JWT 过期时重新 login 刷新(OpenList JWT 默认 `token_expires_in=48` 小时，见 `internal/conf/config.go` 默认值与 `server/common/auth.go` `GenerateToken`；无单独 refresh token)
- **取舍**:OpenList 本身无 refresh_token 机制,过期需重新用密码换 JWT;客户端可缓存密码在 secure storage,或让用户重登

**方案二(更简单,适用于私有部署):存站点 token**
- 用户在 OpenList 账号表单填**站点 token**(即 admin 的 `setting.Token`)
- 直接存 secure storage 键 `openlist_site_token_<accountId>`
- 每次请求带 `Authorization: <站点token>` 头
- **取舍**:站点 token 是全局 admin,权限过大;仅适用于用户自己的 OpenList 实例,不适合多租户

**方案三(适用于 guest 可读场景):完全不存凭证**
- 空 token 请求走 guest(user_id=2)
- **限制**:若 OpenList 管理员禁用 guest(user.Disabled=true),所有媒体 API 会 401(`Auth(false)` 路径),但媒体走的是 `Auth(true)` 不拦截禁用 guest

### 5.3 推荐实现(Phase 0 锁定,Phase 1 实现前再确认)

- **账号模型**:专用 OpenList 连接表(新表 `openlist_connections` 或独立 settings + secure storage),字段:
  - `id` TEXT PRIMARY KEY
  - `display_name` TEXT(用户可编辑的别名)
  - `base_url` TEXT(OpenList 实例地址,如 `https://pan.example.com`)
  - `username` TEXT
  - `role_scope` TEXT(缓存的角色/权限,如 `admin` / `user` / `guest`)
  - `updated_at` INTEGER
- **secure storage 键约定**:
  - `openlist_password_<id>`:明文密码(若缓存密码策略)
  - `openlist_jwt_<id>`:当前 JWT token
  - `openlist_jwt_expires_<id>`:过期时间戳
- **不复用 `accounts` 表 + `provider_type='openlist'`**:现有 `accounts` 表的 `provider_type='webdav'` / 云盘驱动调用点太多(网络库、下载、同步、crypt 源),overload 会产生冲突
- **OpenList Tab 内自带 picker UI**:不走「设置 → 网盘账号管理」,在 OpenList 主屏右上角下拉选择当前连接

### 5.4 `/api/admin/media/*` vs `/api/fs/media/*` 权限对刮削的影响

- **用户态**(JWT / guest):只能调 `/api/fs/media/list` 等 Public 端点,**无法触发刮削**(`/api/admin/media/scrape/start` 需 AuthAdmin)
- **admin 态**(站点 token 或 admin JWT):可调全部端点,包括启动扫描 / 刮削
- **Phase 1 只做只读浏览**,不需 admin 权限;Phase 3(管理侧)才需处理 admin 鉴权

---

## 6. 账号管理与隔离边界(用户锁定)

### 6.1 独立连接管理(不复用 `accounts` 表)

**理由**:
- 现有 `accounts` 表由 `AccountsService` 管理,`provider_type='webdav'` 及云盘驱动调用点遍布:
  - `network_library_screen.dart` / `webdav_service.dart` / `cloud_drive_service.dart`(直接查 `accountById`)
  - `download_queue_service.dart`(按 `sourceName` 解析账号)
  - `sync_service.dart` / `backup_service.dart`(账号凭证导出)
  - `crypt_driver.dart`(源账号引用)
  - 共计 **14+ 个文件直接 import `AccountsService`**
- 扩展 `provider_type='openlist'` 进这张表会与上述调用点产生冲突:
  - `WebDavService._connFor` 按 `providerType` 分流时需新增 OpenList 专用客户端,而 OpenList 媒体库**不是字节层驱动**
  - 下载队列 / 同步服务假定账号有 `remotePath` / `password` / WebDAV session,OpenList 只有 HTTP JSON API

**方案**:
- 新表 `openlist_connections`(或独立 settings JSON + secure storage),结构见 §5.3
- 在 **OpenList Tab 内**自带连接选择器 UI(下拉或设置页子入口),与「设置 → 网盘账号管理」完全分离
- 连接切换后刷新当前 Tab 列表(传新 `baseUrl` + JWT 给 HTTP 客户端)

### 6.2 功能隔离(不共享本地虚拟文件 / 网络库 / WebDAV session)

| 功能 | OpenList 媒体库 | 现有网络库 / 音乐库 | 隔离边界 |
|------|----------------|---------------------|----------|
| 浏览元数据 | HTTP JSON API(`/api/fs/media/list`) | WebDAV PROPFIND / 云盘 REST | 完全独立 |
| 流式播放 | 拼 `folder_path + file_name` 传给现有播放栈 | 同左 | **共享播放栈**,不共享元数据来源 |
| 下载 | (Phase 2)可能复用 `download_queue_service`,传 OpenList 文件 URL | WebDAV GET / 云盘直链 | 下载队列可共享,源解析独立 |
| 刮削 | OpenList 服务端已刮削,客户端只读取 | 本地 SQLite 曲库按需刮削 | 不冲突 |
| 同步 | 不做(媒体库是服务端资源) | 本地 SQLite 与云端双向同步 | 完全独立 |
| 缓存策略 | (Phase 2 再定)可能不走 `music_cache` | `CacheService` 管理 LRU 淘汰 | 待定 |

**禁止调用的现有服务**:
- `LibraryService`(本地曲库 SQLite,与 OpenList 媒体表无关)
- `SyncService`(音乐库云端同步,OpenList 不需要)
- `CacheService.touch*` / `cleanupExpired`(若 OpenList 不走本地缓存)
- `WebDavService.configure` / `CloudDriveService`(OpenList 不是驱动)

**允许调用的服务**:
- `AudioPlayerService` / `VideoPlaybackService`(共享播放栈,传 URL + headers)
- `DownloadQueueService.enqueue*`(Phase 2,若下载走统一队列)
- `PlatformExportService`(导出到系统相册,与源无关)

---

## 7. 复用 vs 新建

### 7.1 可复用(不改既有代码)

- **封面组件**:`LibraryCoverArt` / `MangaCoverArt`(封面 URL 直接传给 `CachedNetworkImage`)
- **多选工具栏**:`SelectionToolbar`(下载、添加到歌单等操作,Phase 2)
- **分页**:`PageResp` 对应 API 的 `{content, total}` 结构
- **网格/列表视图**:`FolderViewMode`
- **播放栈**:`AudioPlayerService.playTrack` / `VideoPlaybackService.play`(传 `PlayableMedia.fromStream`)

### 7.2 新建(Phase 1 实现)

- `OpenListHttpClient`(HTTP 客户端,管理 JWT / base URL / 错误翻译)
- `OpenListMediaScreen`(主屏幕 + TabController)
- `OpenListConnectionService`(连接表 CRUD + JWT 刷新)
- `OpenListMediaItem`(适配 API 的 `MediaItem` → 应用侧显示模型)

### 7.3 不改动现有代码

- `accounts_screen.dart` 不新增 `provider_type='openlist'` 选项(不走网盘账号管理)
- `WebDavService` / `CloudDriveService` 不接入 OpenList(媒体库不是驱动)
- `network_library_screen.dart` 不显示 OpenList 内容(完全独立入口)

---

## 8. 分阶段

| 阶段 | 内容 | 交付物 | 鉴权需求 |
|------|------|--------|----------|
| **Phase 0** | **本文档 + 极小 scaffold**(抽屉入口 + 空白主屏,不调 API) | 本文档 + 可点击进入的空白页 | 不需要 |
| Phase 1 | 只读浏览(视频/音乐/图片/书籍 Tab,列表/网格,分页,搜索) | 可浏览四类媒体条目的完整界面 | **JWT**(推荐)或站点 token |
| Phase 2 | 下载 / 添加到歌单 / 流式播放(复用现有播放栈) | 媒体条目可操作 | 同 Phase 1 |
| Phase 3 | 管理侧(扫描/刮削/配置,需 AuthAdmin) | 设置页「OpenList 管理」子页 | **admin JWT** 或站点 token |

---

## 9. 明确不做

以下项目**不在**本客户端范围内:
- 改动现有音乐库(仍保持本地 SQLite + 缓存模式)
- 接入 `CloudDriver` 层(媒体库不是驱动,是元数据层)
- 上传 / 写操作(媒体库 API 本身只读)
- 转码子系统(`/api/fs/transcode/*`,Phase 2 可能接播放申请端点 `/api/fs/transcode/play`)
- 评论上游 `OpenListTeam/OpenList` 的 PR 或 issue
- 推 `OpenListTeam/OpenList` 远端(只读用户,不碰上游)

---

## 10. 关键技术点

### 10.1 路径身份

OpenList 用 `(folder_path, file_name)` 组合身份(无 `source_name`)。
客户端需在抽象层补 `source_name = connectionId` 映射,才能对齐本地 `music_id = sha1(source + path)` 约定(若要与本地曲库互操作,Phase 2 再定)。

### 10.2 直链与流式

MediaItem 的 `cover` 字段可能是:
- HTTP(S) URL → `CachedNetworkImage` 直接用
- `data:` URI → 内嵌 base64 图片
- 本地路径 → 不适用于远程库

音频/视频文件播放:
- 拿到 `MediaItem.file_name` / `folder_path` 后,拼 `baseUrl + folder_path + file_name` 成完整 URL
- 传给 `PlayableMedia.fromStream(url: ..., headers: {'Authorization': jwt})`
- 不走 `WebDavStreamSource`(那是 WebDAV 专用),直接传 HTTP URL + headers

### 10.3 分页

API 默认 `page_size=40`(Public)或 `20`(Admin)。
建议客户端用 40,与其它库保持一致。

---

## 11. 未决问题(待 Phase 1 开工前确认)

- [ ] **OpenList 实例测试地址与凭证**(用户提供 base URL + 用户名密码,或站点 token)
- [ ] **凭证存储策略**:是否缓存密码?JWT 过期重新登录的 UX?
- [ ] 多库切换 UI:下拉(推荐) / Tab 子级 / 设置页选择?
- [ ] 音乐 Tab 是否做专辑/文件夹子视图?(暂定平铺列表,子视图可后续补)
- [ ] 是否支持离线缓存元数据?(暂定纯在线,不做本地镜像)

---

## 12. 后续工作

Phase 0 完成后,产出:
1. 本文档(已完成)
2. 在 `99-IN-PROGRESS.md` 登记进度条目(指向本文档)
3. (可选)极小 scaffold(仅抽屉入口 + 空白主屏,`git commit` 一次)
4. 评估:是否立即进入 Phase 1(等用户决定)

Phase 1 开工前,需用户确认:
- OpenList 实例的测试地址(base URL)
- 测试账号凭证(用户名 + 密码,或站点 token)
- 连接选择器 UI 形态(下拉 / 设置页)
- 音乐 Tab 子视图需求(专辑 / 文件夹,或暂时只做平铺列表)

---

**文档结束**
