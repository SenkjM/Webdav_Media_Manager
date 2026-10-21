# 04 · 下载队列

> 编号 04 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/services/task_queue_service.dart`、`lib/screens/tasks_screen.dart`、`lib/models/queue_task.dart`（开发中语义见 [99 §17](99-IN-PROGRESS.md)）

所有下载都经由队列——网络库的每一次入队、CUE 整组下载、视频存相册都走这里。队列是**唯一**的下载真相，界面只是它的投影。

> **占位（开发中）**：已改名任务队列并落地 `kind` / 双进度外壳；扫描执行器等见 [99 §17](99-IN-PROGRESS.md)。

## 1. 任务模型

`QueueTask`（持久化在 `task_queue.db` / 表 `queue_tasks`；外壳已支持 `kind` 与计数进度，见 [99 §17](99-IN-PROGRESS.md)）：

| 字段 | 语义 |
|------|------|
| `sourceName` | **网盘名**，唯一的绑定点。真正的传输开始时才由它解析本机账号（URL / 用户名 / 密码），所以改名或重加网盘不会留下过期指针 |
| `remotePath` / `fileName` | 远端路径与落盘用的文件名 |
| `status` | `pending` / `active` / `completed` / `failed` / `cancelled` |
| `target` | 落盘目的地：`cache`（应用缓存）/ `gallery`（系统相册）/ `downloads`（系统下载目录）；界面上对应「应用缓存」「系统相册」「系统下载目录」 |
| `localPath` | 缓存任务是**文件路径**；相册 / 下载目录任务是 `content://` URI（或 API<29 的绝对路径）——所以 `File(localPath).existsSync()` 对它们**永远为假** |
| `cacheGroupId` | CUE 组：同一组的任务折叠、同删同卸 |
| `progress` / `bytesReceived` / `bytesTotal` / `errorMessage` | 进度与失败原因 |
| `isPublic` | `target != cache`，即「落到公共集合」；`isGallery` 单独判相册 |

持久化读取（`QueueTask.fromMap`）对旧库**类型宽容**：字符串 / 时间字段经 `_asString` / `_asDate` 转换，避免老 schema 行里混入的 bool / 数值让启动初始化崩溃。

### 1.1 任务种类

`kind` 决定执行器，也决定行在任务页里怎么分组——相邻的同种类行会折叠成一项，展开才看得到成员。

| kind | storage | 干什么 | 进度 |
|------|---------|--------|------|
| `download` | `download` | 下载到缓存 / 系统相册 / 系统下载目录 | 字节 |
| `scan` | `scan` | 音乐扫描入库（CUE 先跑，覆盖的音频不再重复） | 件 |
| `retagCloud` | `retag_cloud` | 单曲从云端重读标签 | 件 |
| `matchRemote` | `match_remote` | 远端存在性探测，给不在了的行打红点 | 件 |
| `mangaScrape` | `manga_scrape` | 读容器里的 ComicInfo，写标题 / 作者 / 系列 / 封面 | 件 |
| `mangaCache` | `manga_cache` | 把整包拉进漫画缓存 | 件 |
| `mangaBuild` | `manga_build` | 散图目录建立成书（合并成一本 / 每目录一本） | 件 |
| `mangaPack` | `manga_pack` | 把散图书逐页打包成一个 CBZ，然后交给 `upload` | 件 |
| `upload` | `upload` | 把本机文件流式写回远端（目前只有 WebDAV） | 字节 |

两条约定：**枚举器不计入批次**——扫描与建立这类「先展开再派活」的任务带 `isEnumerator`，它们不占批次的完成 / 失败 / 待办计数，运行期折叠成一个槽位，否则一个含 N 首的文件夹会在通知里凭空多出 3 项；**入队一律单元形式**——前端不做递归、不预先统计，递归全在 worker 里，单元之间只在显示层合并。

## 2. 状态机与执行

- **串行**：`_pump()` 一次只跑一个任务，取 `orderPending(_tasks)` 的第一个，跑完再取下一个；全部排空后统一刷新进度通知。`_pump()` 正忙时被再次调用不会丢唤醒——请求被记录（`_pumpRequested`），当前任务退出后自动重启调度，所以「取消正在下载的任务」后下一个 pending 任务必定接续启动。
- 启动时把落库的 `active` 任务改回 `pending`（上次进程被杀留下的残留）。
- 任务抛异常也要**落库成 failed**（否则数据库里的行会永远停在 active，而内存说失败）。
- 取消 / 重试：`cancel(id)` 把 pending / active 标 cancelled（active 还会触发取消 token）；`retry(id)` 把 failed / cancelled 复位成 pending 并重新入会话计数。
- **手动唤醒**：工具栏提供三个动作——「全部下载」（把 failed / cancelled 全部复位并清空退避，再从 pending 起跑）、「唤醒等待中任务」（清空所有 pending 行的 `nextRetryAt`，让退避中的任务立即参与调度）、「全部取消」（终止 active、取消全部 pending）。

## 3. 入队语义（`enqueue`）

1. 已有 completed 且 `localPath` 文件**存在**的同名任务 → 直接复用，顺手重新 ingest 一次标签。
2. 否则检查推导缓存路径命中（文件已在缓存里，`hasLocalFile`）→ 造一条 completed 任务并 ingest。
3. 否则若已有 pending / active 的同名任务 → 等待它，不重复排。
4. 否则新建 pending 任务并 `_pump`。

**重复任务处理（public 目标）**：单文件下载时，先查 `blockingPublicDuplicate`（pending/active/completed）；有重复 → 对话框询问是否重新进行，确认则 `requeuePublicFresh`（删旧行、删 .part、新建任务）。批量下载时，`enqueueSelection(replaceDuplicates:false)` 先扫描收集重复项；若 duplicates>0，对话框询问「有 N 个重复任务」，确认则 `requeuePublicFreshMany` 重新入队。cache 目标不受影响。

**目标决定时机**：提交时（.part 下载完成后）读 settings 决定写入 SAF 自定义目录还是 MediaStore 系统下载目录。

**SAF 自定义下载目录**：用户可在设置 → 下载队列中选择自定义目录作为 downloads 目标。写入走 `DownloadDestinationService.save(retryOnFallback:false)`；SAF 目录失效（`safInvalid`）时全局回落到系统下载目录并提示，任务保持 failed（用户可手动重试）。io 错误不回落。

**错误分类**：SAF 写入失败分三类：`safInvalid`（权限丢失、根文档不可用、FLAG_DIR_SUPPORTS_CREATE 缺失）→ 全局回落；`io`（ENOSPC 等）→ 不回落；`other`（其它）→ 不回落。只有 safInvalid 触发回落。

相册与下载目录另走 `enqueueGallery` / `enqueueToDownloads`（`enqueuePublic`），**不入音频缓存**。视频相册进 `Movies/WebdavMediaManager`，图片「下载到系统相册」进 `Pictures/WebdavMediaManager`，两条都不写 `.nomedia`。

`.nomedia` 双向对齐：启动、下载设置页打开、切换目标（pick / disable / fallback）、备份导入后、每次 downloads 提交前（SAF 模式 best-effort）都调 `alignNomedia`。开关切换时用 `alignNomedia(reportAlready:true)`，若已匹配则提示「外部操作已完成」，失败才拨回开关并报错。API 29+ 先查 `MediaStore.Downloads` 里显示名恰好是 `.nomedia` 的行（改过显示名不算），查不到时回退查磁盘文件 `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)/WebdavMediaManager/.nomedia`（外部放置的也能读到），存在且可读才算 present；插入失败、或 MediaStore 改写了显示名时，Samsung 厂商返回专用错误「三星系统会改写 .nomedia 文件名，无法干净排除媒体扫描，已取消」，非 Samsung 返回通用错误；删除时若 MediaStore 无行但磁盘有文件，尝试 `File.delete()`，失败返回错误「无法删除外部放置的 .nomedia，请用文件管理器手动删除」。API 28 只查磁盘文件，API 27 及以下忽略。开关逻辑：先写入设置再调 `alignNomedia`（含 already），失败时拨回开关并报错。

## 4. 完成之后（ingest）

| 目标 | 之后发生什么 |
|------|--------------|
| `cache`（音频） | `LibraryService.ingestDownloaded` 写入曲库标签；CUE 组会走 `ingestCueAlbum`（先清 standalone 行再建虚拟分片） |
| `cache`（CUE 音频） | 与同组任务一起结算，整组进库 |
| `gallery` / `downloads` | 只落盘，不进曲库、不进缓存 |

## 5. 与缓存清理的联动

设置里「手动清空音频缓存」= `AppState.manualClearCache()`：先 `cache.clearAll(...)`（删 `music_cache/` 下文件，保护正在播放 / 下载的），再调 `downloads.invalidateMissingCompleted()`。

`invalidateMissingCompleted()` 的语义（**新近修正**）：

- **跳过 `isPublic` 任务**：相册 / 下载目录的文件根本不在音频缓存里，`File(content://…).existsSync()` 永远为假，不能因此被判失效。
- 其余 completed 任务，只要文件已不在，就把**任务行删除**（`_tasks.remove` + `_store.delete`）。
- **不要**改成标 `cancelled`：`uiStateFor` 把 cancelled 映射成 `TrackUiState.error`，会让每一个曾经下载过的曲目在[音乐库](03-MUSIC-LIBRARY.md)里挂一个红「错误」标签。删行之后 `taskForRemote` 返回 null，行回到 `remote`（不显示标签），与「音乐库 → 删除缓存」的表现一致。
- `enqueue` 本来就不会复用 cancelled 行（第 3 节的第 1 步只认「文件还在」的 completed），所以删行不改变「再点一下重新下载」的行为。

## 6. 队列界面

- 每行显示文件名、状态、进度百分比、目标标签（`已存入系统相册` / `目标：系统相册`、`系统下载目录`）。
- 支持取消、重试、删除、清除已完成；「清除所有队列」需要二次确认，确认后列表清空且系统通知消失。
- CUE 组折叠成一行显示。
- 进度与完成通知的文案、两条进度条的含义见 [07](07-NOTIFICATIONS.md)。

## 7. 计划（未实现）：后台下载 `fail host lookup`

开发中：后台下载保活的代码在 `feature/bg-download-keepalive`，ColorOS 真机验收未做。语义与未通过的检查见 [99 §7](99-IN-PROGRESS.md)。

## 8. 相关代码

`task_queue_service.dart`（队列 / 入队 / 传输 / ingest 派发）、`task_store.dart`（持久化）、`models/queue_task.dart`（模型与枚举）、`tasks_screen.dart`（队列界面）、`library_service.dart`（ingest）。
