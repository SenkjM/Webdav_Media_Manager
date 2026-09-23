# 08 · 同步与备份

> 编号 08 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/services/sync_service.dart`、`credential_vault_service.dart`、`backup_service.dart`、`library_sync_store.dart`、`lib/screens/sync_screen.dart`  
> 文件语义（名字 / 魔数 / 分片含义）见 [01](01-DATA-MODEL.md)。

## 1. 统一远端路径（唯一目的地）

入口：设置 →「同步与备份」。**「定时同步」下面就是「远端路径」**一栏：

- **① 网盘**：下拉框选一个 WebDAV 账号（`SettingsService.setSyncAccountId`）。
- **② 路径**：地址框（`setSyncRemoteRoot`），写入前补首尾 `/`；默认 `/WebdavMediaManager/`。

这条「网盘 + 路径」是**凭证 / 歌单 / 音乐库 / 备份共用的云端根**，四类数据的云端位置全部由它派生，界面上没有第二处路径输入。用户选 123网盘、填 `/player`：

| 数据 | 云端位置 | 派生 getter（`settings_service.dart`） |
|------|----------|------------------------------------------|
| WebDAV 凭证 | `/player/credentials.json` | `credentialsRemotePath` |
| 歌单 | `/player/playlists/` | `playlistRemotePath` |
| 音乐库 | `/player/library/` | `libraryRemotePath` |
| 全部备份 | `/player/backup/` | `backupRemotePath` |

- 派生实现：`_syncRemoteRootBase`（补尾斜杠）+ `_syncSubdir(name)`；子目录名固定在 `SettingsService`。
- 真正用的账号：`SyncService.syncDestination()` = `syncAccountId ?? 当前选中账号`。备份、凭证、歌单、曲库都走它，不可能各挑各的盘。
- 同步页在路径框下方直接列出这四条派生路径，改路径的效果不需要靠猜。
- 旧版歌单目录 `/Playlists/` 已并入总路径下的 `playlists/`。

### 迁移

- 新键 `sync_account_id`；旧键 `sync_credentials_account_id` / `sync_playlists_account_id` / `sync_library_account_id` / `sync_backup_account_id` **只读不写**：`init()` 按此顺序取第一个非空值，避免升级后原地丢掉用户已选网盘。
- 旧路径键 `backup_remote_path` / `library_sync_remote_path` / `playlist_remote_path` 已删除：不再读取、不再写入、不再导出。路径全部派生，用户自定义过的旧值不再生效；曾把音乐库放在别处的需要在新栏里重填一次总路径。
- **路径**随备份往返（`sync_remote_root` 在 `exportForBackup` / `importFromBackup` 中）；**网盘选择不随备份走**——账号 id 只在本机有意义，换设备后下拉回落到「当前选中网盘」，需要时重选一次。

## 2. 三种数据，三种同步方式

**不存在站点隔离**：一份凭证表、一份音乐库、一份歌单，全落在同一条远端根下。

| 数据 | 行为 |
|------|------|
| WebDAV 凭证 | **真同步**：与云端 `credentials.json` 双向合并；`autoScan()` 在启动 / 切换账号 / 定时到点时跑 |
| 歌单 | **真同步**：双向 M3U8，`updatedAt` 最后写入胜出；改动即时上传，启动 / 切换账号 / 定时拉取 |

歌单文件是扩展 M3U8：`#EXTM3U` + `#EXT-X-WMP-ID` / `-UPDATED` / `-NAME`，路径行 `wmp://<accountId>/<remotePath>`；最后写入胜出由 `-UPDATED` 判定。**`WMP` 前缀是历史产品缩写、属于磁盘格式，不要改名**——已同步的歌单依赖它。编解码在 `lib/utils/m3u8_playlist.dart`。
| 音乐库 | **增量**：`library.addListener` 防抖 20 s 后 `syncLibraryIncremental()`；手动「重建」`syncLibraryFull()` 才对齐删除 |
| 全部备份 | `backupTo(passphrase:)` 打成**一个**归档写到 `<远端路径>backup/` |

凭证加密与恢复：

- `credentials.json` 里地址 / 用户名明文，只有密码加密（`AESGCMv1:`，PBKDF2-SHA256 120k + AES-256-GCM）。`passwordEncrypted: true` 表示是密文。
- `tryDecrypt` 失败时**账号照常恢复、密码留空**（`AccountsService` 返回 missing 列表供 UI 提示），**绝不**因缺密钥中止整次同步。
- 统一加密密钥由用户在同步页指定，存在 Keystore，与网盘登录密码**无关**（密钥若取自某网盘密码，改密码或换盘就会让已同步的密码全部解不开）。未设置密钥时，自动扫描会跳过凭证拉取，歌单照常合并。
- 密钥不写进备份 / 导出文件；换机恢复必须手动再输一次。
- 曲目按**网盘名 + remote_path** 绑定，云端清单里没有地址 / 用户名 / 密码；来源网盘改名会让行显示「来源网盘未绑定」（见 [03](03-MUSIC-LIBRARY.md)）。

## 3. 定时同步默认关闭

- `SyncInterval`：`off` / 15 分钟 / 30 分钟 / 每小时 / 每 6 小时 / 每天。`SyncIntervalX.fallback = off`，`fromStorageKey(null)` 与未知值都回落 `off`。
- `SettingsService.syncInterval` 与 `AppState._appliedSyncInterval` 初值同为 `off`：**全新安装不自行联网**；界面上那行显示「已关闭，仅手动同步」。
- 已显式存过 `15m / 30m / 1h / 6h / 24h / off` 的安装不受影响。
- 改间隔由 `AppState._onSettingsChanged` 即时重排定时器（`_schedulePeriodicSync`）。

## 4. 同步页的交互约定

- **长任务提示走全局槽位**：重建 / 同步 / 备份可能跑几分钟，用户常常直接退出设置，因此结果一律用 `AppSnack.showGlobal(…)`（见 [07 §3](07-NOTIFICATIONS.md)），不因页面消失而沉默。自动扫描与下载后的后台增量保持静默——它们不是用户动作。
- 设置页的「同步与备份」入口是 `ListTile` + `Icons.chevron_right` 箭头行（与「视频播放设置」「文件后缀管理」一致：打开另一个界面用箭头行，不用按钮），副标题显示当前远端路径。
- 页面按区块排列：定时同步 → 远端路径 → WebDAV 凭证 → 歌单 → 音乐库 → 全部备份 → 本地导入导出；除了「远端路径」那一条，任何地方都不再出现路径输入。
- 音乐库区块除「同步 / 重建 / 整理」外，另有上下两个**红底白字的不可逆动作**。两者都要二次确认：确认框正文说会发生什么，小一号字补后果，最后**手打 `YES`（不区分大小写）**确认按钮才可用。两个动作是一对反义词——一个把云端拉到本地，一个把本地的删除推到云端。
  - **从云端覆写音乐库**：只清索引（tracks / CUE / 墓碑 / 同步游标，`LibraryDatabase.clearLibraryIndex()`）再整库拉一次。cache annex、封面与已下载音频保留，所以拉回来的行仍指向本地文件；未推上云端的本地改动会随索引消失。
  - **销毁音乐库**：**只逐首立墓碑**——本地行、cache annex、封面、歌单引用一律不动，也不删任何文件。墓碑是这次操作的唯一产物：下次同步把它们作为 `del-*.wdmm` 推上云端，云端在下一次重建时才真正抹掉这些行。结束时把「定时同步」设为关闭，什么时候推由用户手动决定。注意本地墓碑**不会**让曲目从本地界面消失（`tombstonedKeys()` 目前无人调用），所以这个动作在本地看起来「什么都没发生」，只靠操作后那条「已标记 N 首」的提示确认，详见 [99 §3](99-IN-PROGRESS.md)。
  - 两个动作都在「静默窗口」里跑：`AppState._quietLibraryWrites` 期间置起 `_libraryMaintenance`，撤掉已排队的推送防抖，并让 20 s 防抖与定时扫描直接返回，避免后台写库与操作交错。已经在飞的那一趟同步不会被中断。

## 5. 全部备份归档（BackupService）

- `formatVersion = 5`；一个 `WmpContainer`（kind `BK`）：META（含 format 标记）+ TRACKS（含 CUE 分片行）+ 原始 COVERS（每行一份）+ JSON side sections（credentials / playlists / settings / cueAlbums）。
- 内容 = 全部凭证 + 全部音乐库行（tracks + cue_slices + cue_albums）+ 全部歌单 + 封面缩略图 + 设置；**不含** `music_cache` 音频与下载队列。
- 加密：可选口令，魔数 `WDMMEN01` + PBKDF2 + AES-256-GCM（`backup_crypto.dart`）；归档内凭证的密码另行按 `credentials.json` 的规则加密。
- **恢复策略**：恢复后 cache annex 一律清空 → 「库以为有文件但播不了」不可能发生；封面写回后再把各行的 `cover_path` 重写为本地路径。
- 备份的写入与列出都只认 `<远端路径>backup/`，没有按站点分目录。

## 6. 云端库整理（audit）

`library_sync_store.dart` 的 `audit` / `deleteOrphans`（纯函数 `auditLibraryParts`）判定孤儿文件与缺失分片；UI 入口是同步页「整理」：一致时提示「一切一致，无需处理。」，发现孤儿可一键删除，发现缺失给出「以本机为准重建」出口。同步页还会显示「云端分片：N 个（约 X KB）」，超过设置里的「重建提示阈值」时提示重建。

## 7. 本地导入 / 导出

- 「导出到系统下载目录」→ `Download/WebdavMediaManager/wdmm-export-<UTC>.wdmm`（可读 JSON 模式为 `.json`；`PlatformExportService.saveToDownloads`）。
- 「从本地文件导入」→ 原生 SAF `ACTION_OPEN_DOCUMENT` 拷贝到应用缓存后读取（`pickFile`），也支持粘贴 Base64。
- 导入端按魔数自动识别「容器 / 可读 JSON」。

## 8. 相关代码

`sync_service.dart`（编排 / `syncDestination`）、`credential_vault_service.dart`（`credentials.json` 读写）、`credential_vault_crypto.dart`（仅密码加密）、`library_sync_store.dart` + `library_shard_codec.dart` + `utils/library_index_merge.dart`（清单与分片）、`playlist_service.dart`（M3U8 双向）、`backup_service.dart`（归档）、`sync_screen.dart`（界面）、`settings_service.dart`（远端路径与账号键）。
