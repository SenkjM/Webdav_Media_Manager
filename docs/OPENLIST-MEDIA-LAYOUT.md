# OpenList 媒体库客户端 UI 布局建议（计划，未实现）

> **状态：计划阶段，本文档只写布局建议，不实现 UI 代码。**
> 相关文档：[98-OPENLIST-MEDIA-CLIENT.md](98-OPENLIST-MEDIA-CLIENT.md)（远期设计）、[99-IN-PROGRESS.md](99-IN-PROGRESS.md#20-openlist-媒体库客户端布局阶段进行中)

---

## 1. 概述

本客户端作为 **OpenList 媒体库的只读/浏览侧**接入现有应用：
- **不替换**现有音乐库（仍是本地 SQLite + WebDAV 下载缓存模式）。
- **平级接入**：抽屉里新增一条「OpenList」入口，与现有音乐库、网络库并列。
- **只接 OpenList 媒体 API**（`/api/fs/media/*` + 部分 `/api/admin/media/*`），不改网盘兼容层。
- **本阶段只出布局建议**，不写 `lib/` 实现代码（除非为了让分支有意义的极小 scaffold）。

---

## 2. 抽屉入口

### 2.1 插入位置

当前抽屉顺序（`lib/screens/home_shell.dart:114-131`）：
```
0. 文件夹
1. 音乐库
2. 歌单
3. 漫画库
4. 网络库
5. 任务队列
6. 设置
```

**建议插入位置**：**索引 5**（任务队列之前、网络库之后）：
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

理由：
- OpenList 是**远程库**，语义更接近「网络库」，排在网络库后比排在曲库之后更符合用户预期。
- 任务队列/设置是功能工具，排在最后保持不变。

### 2.2 标签与图标

- **中文标签**：`OpenList`（固定英文，不本地化）
- **图标**：`Icons.cloud_circle_outlined`（云 + 圆环，区别于网络库的 `Icons.cloud_outlined`）

### 2.3 迁移注意点

插入新条目后，`home_tab_index` 存储键需要一次性迁移（类似 `home_tab_v024_folders_inserted` / `home_tab_v025_manga_inserted`）：
- 若用户主页设置在「任务队列」(5) 或「设置」(6) → 新值 +1
- 其余不受影响

---

## 3. 屏幕与 Tab 结构

主屏建议名：`OpenListMediaScreen`（`lib/screens/openlist_media_screen.dart`）。

### 3.1 Tab 划分（建议：视频/音乐/图片/书籍 四 Tab，对齐 MediaType）

```
OpenListMediaScreen
 └─ TabController (4 tabs)
     ├─ 视频 (video)
     ├─ 音乐 (music)
     ├─ 图片 (image)
     └─ 书籍 (book)
```

每个 Tab 内结构：
- **列表/网格视图**（复用 `FolderViewMode`）
- **搜索**（AppBar 搜索框，传 `keyword` 给 API）
- **多选**（工具栏复用 `SelectionToolbar`）
- **筛选**（可选，见 §3.2）

### 3.2 备选方案：专辑/文件夹/扫描路径子视图（仅音乐）

若音乐 Tab 要做分组浏览：
- **专辑列表**：`PublicListAlbums` → 分页专辑卡片 → 点开进「专辑详情」调 `PublicGetAlbum`
- **文件夹浏览**：`PublicListFolders` → 文件夹列表 → 选一个文件夹后调 `PublicListMedia?folder_path=...`
- **扫描路径筛选**：`PublicListScanPaths` → 下拉选择 → 传 `scan_path_id` 给 `PublicListMedia`

其它三类（视频/图片/书籍）暂时只做平铺列表。

---

## 4. API 映射表

### 4.1 核心端点（`/api/fs/media/*`，用户态 Auth）

| 界面 | API 端点 | 参数 | 用途 |
|------|---------|------|------|
| 视频 Tab | `GET /api/fs/media/list` | `media_type=video`, `page`, `page_size`, `order_by`, `order_dir`, `keyword` | 平铺列表 |
| 音乐 Tab | `GET /api/fs/media/list` | `media_type=music`, `page`, `page_size`, `keyword` | 平铺列表 |
| 音乐 · 专辑 | `GET /api/fs/media/albums` | `page`, `page_size`, `keyword`, `scan_path_id?` | 专辑列表 |
| 音乐 · 专辑详情 | `GET /api/fs/media/album` | `album_name`, `album_artist` | 专辑内曲目 |
| 音乐 · 文件夹 | `GET /api/fs/media/folders` | `media_type=music` | 文件夹列表 |
| 图片 Tab | `GET /api/fs/media/list` | `media_type=image`, … | 平铺列表 |
| 书籍 Tab | `GET /api/fs/media/list` | `media_type=book`, … | 平铺列表 |
| 条目详情 | `GET /api/fs/media/item/:id` | 路径参数 `id` | 单条元数据 |
| 筛选 · 扫描路径 | `GET /api/fs/media/scan_paths` | `media_type?` | 路径下拉选项 |

### 4.2 管理侧端点（`/api/admin/media/*`，AuthAdmin，暂不实现）

以下端点需要管理员权限，**本阶段不做 UI**：
- 扫描路径 CRUD（Create/Update/Delete/Clear）
- 扫描进度 / 启动扫描
- 刮削进度 / 启动刮削
- 删除失效条目 / 清空库
- 导入 / 导出

未来若做管理侧，可在「设置」里新增「OpenList 管理」子页。

---

## 5. 鉴权与账号绑定

### 5.1 账号来源

复用现有 `accounts` 表 + `WebDavAccount`：
- `provider_type` 新增取值 `'openlist'`
- `base_url` 存 OpenList 实例地址（如 `https://pan.example.com`）
- `username` / `password` / `secure storage` 照旧存 token 或凭证

### 5.2 token 持有方

抽象层：`WebDavService` / `CloudDriveService` 查账号表 → 拿 token → 附加到请求头 `Authorization: Bearer <token>`。
调用方（UI）**只传** `accountId`，不持有 token。

### 5.3 多远程库

允许多个 OpenList 账号（每个是一个地址 + 一套凭证）。
主屏右上角下拉选择「当前 OpenList 库」，切换后刷新列表。

---

## 6. 复用 vs 新建

### 6.1 可复用（不改既有代码）

- **账号管理**：`accounts_screen.dart`，新增 `provider_type=openlist` 选项，表单字段动态渲染（URL + token / username+password）
- **封面组件**：`LibraryCoverArt` / `MangaCoverArt`（封面 URL 直接传给 `CachedNetworkImage`）
- **多选工具栏**：`SelectionToolbar`（下载、添加到歌单等操作）
- **分页**：`PageResp` 对应 API 的 `{content, total}` 结构
- **网格/列表视图**：`FolderViewMode`

### 6.2 新建（本阶段写最小抽象，不实现完整 UI）

- `OpenListMediaBackend`（抽象层，[98](98-OPENLIST-MEDIA-CLIENT.md) §2）
- `OpenListMediaScreen`（主屏幕）
- `OpenListMediaService`（领域层，包一层 API 调用）
- `OpenListMediaItem`（适配 `MediaItem` → 应用侧显示模型）

---

## 7. 分阶段

| 阶段 | 内容 | 交付物 |
|------|------|--------|
| **Phase 0** | **本文档 + 极小 scaffold**（抽屉入口 + 空白主屏，不调 API） | 本文档 + 可点击进入的空白页 |
| Phase 1 | 只读浏览（视频/音乐/图片/书籍 Tab，列表/网格，分页，搜索） | 可浏览四类媒体条目的完整界面 |
| Phase 2 | 下载 / 添加到歌单 / 流式播放（复用现有播放栈） | 媒体条目可操作 |
| Phase 3 | 管理侧（扫描/刮削/配置，需 AuthAdmin） | 设置页「OpenList 管理」子页 |

---

## 8. 明确不做

以下项目**不在**本客户端范围内：
- 改动现有音乐库（仍保持本地 SQLite + 缓存模式）
- 接入 `CloudDriver` 层（媒体库不是驱动）
- 上传 / 写操作（只读/浏览侧）
- 转码子系统（`/api/fs/transcode/*`）
- 评论上游 `OpenListTeam/OpenList` 的 PR 或 issue

---

## 9. 关键技术点

### 9.1 路径身份

OpenList 用 `(folder_path, file_name)` 组合身份（无 `source_name`）。
客户端需在抽象层补 `source_name = accountId` 映射，才能对齐本地 `music_id = sha1(source + path)` 约定。

### 9.2 直链与流式

MediaItem 的 `cover` 字段可能是：
- HTTP(S) URL → `CachedNetworkImage` 直接用
- `data:` URI → 内嵌 base64 图片
- 本地路径 → 不适用于远程库

音频/视频文件播放：
- 拿到 `MediaItem.file_name` / `folder_path` 后，拼远端路径传给现有播放栈
- 复用 `WebDavStreamSource`（URL + headers）
- 不走 `CloudDriver`（媒体库是元数据层，不是字节层）

### 9.3 分页

API 默认 `page_size=40`（Public）或 `20`（Admin）。
建议客户端用 40，与其它库保持一致。

---

## 10. 未决问题

- [ ] 鉴权方式：用 token 还是 username+password？（待 OpenList 实例配置确认）
- [ ] 多库切换 UI：下拉 / Tab 子级 / 设置页选择？
- [ ] 音乐 Tab 是否做专辑/文件夹子视图？（暂定平铺列表，子视图可后续补）
- [ ] 是否支持离线缓存元数据？（暂定纯在线，不做本地镜像）
- [ ] 上游 `dev-media` 何时合入 `main`？（不阻塞本客户端，但影响上游依赖稳定性）

---

## 11. 后续工作

Phase 0 完成后，产出：
1. 本文档（已完成）
2. 在 `99-IN-PROGRESS.md` 登记进度条目（指向本文档）
3. 极小 scaffold（仅抽屉入口 + 空白主屏，`git commit` 一次）
4. 评估：是否立即进入 Phase 1（等用户决定）

Phase 1 开工前，需确认：
- OpenList 实例的测试地址与凭证
- 鉴权方式（token / user+pass）
- 音乐 Tab 是否做专辑子视图

---

**文档结束**
