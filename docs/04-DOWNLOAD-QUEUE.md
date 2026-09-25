# 04 · 下载队列

> 编号 04 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/services/download_queue_service.dart`、`lib/screens/downloads_screen.dart`、`lib/models/download_task.dart`

所有下载都经由队列——网络库的每一次入队、CUE 整组下载、视频存相册都走这里。队列是**唯一**的下载真相，界面只是它的投影。

## 1. 任务模型

`DownloadTask`（持久化在 `download_queue.db`）：

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

## 2. 状态机与执行

- **串行**：`_pump()` 一次只跑一个任务，取 `orderPending(_tasks)` 的第一个，跑完再取下一个；全部排空后统一刷新进度通知。
- 启动时把落库的 `active` 任务改回 `pending`（上次进程被杀留下的残留）。
- 任务抛异常也要**落库成 failed**（否则数据库里的行会永远停在 active，而内存说失败）。
- 取消 / 重试：`cancel(id)` 把 pending / active 标 cancelled（active 还会触发取消 token）；`retry(id)` 把 failed / cancelled 复位成 pending 并重新入会话计数。

## 3. 入队语义（`enqueue`）

1. 已有 completed 且 `localPath` 文件**存在**的同名任务 → 直接复用，顺手重新 ingest 一次标签。
2. 否则检查推导缓存路径命中（文件已在缓存里，`hasLocalFile`）→ 造一条 completed 任务并 ingest。
3. 否则若已有 pending / active 的同名任务 → 等待它，不重复排。
4. 否则新建 pending 任务并 `_pump`。

相册与下载目录另走 `enqueueGallery` / `enqueueToDownloads`（`enqueuePublic`），**不入音频缓存**。

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

**现象**：切到后台后音乐下载失败，报 `fail host lookup`；前台正常。**尚未修**。

调查方向（均为假设，实现前需要先复现并验证）：前台服务 / 进程优先级导致 DNS 或 socket 被回收；应用在后台时被系统限制网络；下载期间未持有唤醒 / 前台约束。

实现时要一并写清：固定失败场景、加日志或诊断字段、以及「后台下载成功」的可观察验收。此块优先级最高，单独推进，不与[网络库](02-NETWORK-LIBRARY.md)的文件动作重构绑在一起。

## 8. 相关代码

`download_queue_service.dart`（队列 / 入队 / 传输 / ingest 派发）、`download_store.dart`（持久化）、`models/download_task.dart`（模型与枚举）、`downloads_screen.dart`（队列界面）、`library_service.dart`（ingest）。
