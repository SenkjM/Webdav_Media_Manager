# A04 · 同步与备份

> **文档编号 A04** · 状态：已完成 · 模式：归档（正文只读）  
> 总索引：[INDEX.md](../INDEX.md)  
> 自原开发文档拆出：凭证、歌单、曲库增量与备份容器。

勘误不得直接改正文。需要更正时新建编号文档，并在索引备注。

---

## 10. 同步 / 备份格式

### 三种数据，三种同步方式

入口：设置 →「同步与备份」（`screens/sync_screen.dart`），聚合服务 `services/sync_service.dart`。
**不存在站点隔离**：一份凭证表、一份音乐库、一份歌单；备份自己挑网盘与路径。

| 数据 | 行为 |
|------|------|
| WebDAV 凭证 | **真同步**：与云端 `credentials.json` 双向合并；启动 / 切换账号 / 每 30 分钟 `autoScan()` |
| 歌单 | **真同步**：双向 M3U8，`updatedAt` 最后写入胜出；改动即时上传，启动 / 切换账号 / 定时拉取 |
| 音乐库 | **增量**：`library.addListener` 防抖 20s 后 `syncLibraryIncremental()`；也可手动 `syncLibraryFull()`（对齐删除） |
| 全部备份 | `backupTo(destination, remoteDir, passphrase)` 打成**一个**归档 |

云端布局（`SettingsService.syncRemoteRoot`，默认 `/WebdavMediaManager/`）：

| 文件 | 内容 | 加密 |
|------|------|------|
| `credentials.json` | WebDAV 账号（**地址/用户名明文** + 密码） | **仅密码**（`AESGCMv1:`，PBKDF2-SHA256 120k + AES-256-GCM） |
| `library/<accountId12>/library_index.json` | 曲库索引（`formatVersion 2`） | 无 |
| `/Playlists/*.m3u8` | 歌单 | 无 |
| `backup/`（用户自选路径）`backup-<UTC>.wdmm` + `webdav_media_backup.wdmm` | 全部备份归档（kind `BK`） | 可选口令（`WDMMEN01`） |

- `passwordEncrypted: true` 表示密码是 `AESGCMv1:` 密文；`tryDecrypt` 失败时**账号照常恢复、密码留空**（`AccountsService` 返回 missing 列表供 UI 提示），**绝不**因缺密钥中止整次同步。
- 「导出到下载目录」→ `Download/WebdavMediaManager/wdmm-export-<UTC>.wdmm`（可读 JSON 模式为 `.json`；`PlatformExportService.saveToDownloads`）。
- 「从本地文件导入」→ 原生 SAF `ACTION_OPEN_DOCUMENT` 拷贝到应用缓存后读取（`pickFile`），也支持粘贴 Base64。

### 全部备份归档（`BackupService`）

- `formatVersion = 5`；一个 `WmpContainer`（kind `BK`）：META（含 format 标记）+ TRACKS（含 CUE 分片行）+ 原始 COVERS（每行一份）+ JSON side sections（credentials / playlists / settings / cueAlbums）。
- 内容 = 全部凭证 + 全部音乐库行（tracks + cue_slices + cue_albums）+ 全部歌单 + 封面缩略图 + 设置。
- **不含**：`music_cache` 音频、下载队列。
- 加密：可选口令，魔数 **`WDMMEN01`** + PBKDF2 + AES-256-GCM（`backup_crypto.dart`）；归档内凭证的密码另行按 `credentials.json` 规则加密。
- **恢复策略**：恢复后 cache annex 一律清空 → 「库以为有文件但播不了」不可能发生；封面写回后再把各行的 `cover_path` 重写为本地路径。

### 文件魔数（`WDMM` + 种类 + 版本）

所有二进制文件（云端分片、备份、加密信封）都以同样的 8 字节开头：`'WDMM'`（来自本应用）+ 2 字符种类 + 2 位布局版本，例如 `WDMMLB01`。种类可从前 8 字节直接读出，不需要解压任何 section；未知种类 / 版本会**按名字报错**（而不是 CRC 错），因此未来的新种类或新布局能和平共存。容器头里还留了 `u16 flags` 给以后的开关用。

| 魔数 | 种类 | 用途 |
|------|------|------|
| `WDMMLB01` | `LB` base | 云端库**基础分片**（重建产出的大分片，`lib-*.wdmm`） |
| `WDMMLS01` | `LS` seg | 云端库**增量分片**（每次同步追加的小分片，`seg-*.wdmm`） |
| `WDMMLT01` | `LT` tomb | 云端库**墓碑分片**（删除记录，`del-*.wdmm`） |
| `WDMMBK01` | `BK` backup | 个人备份归档（`backup-<UTC>.wdmm` / `webdav_media_backup.wdmm`） |
| `WDMMEX01` | `EX` | **预留**：用于分享的曲库文件 |
| `WDMMCR01` | `CR` | **预留**：凭证 / vault 二进制包 |
| `WDMMEN01` | `EN` 信封 | 口令加密外壳（AES-256-GCM），解密后里面才是上面某种文件或 JSON |

新增种类 = `WmpFileKind` 里加一行 + `WmpKind` 里加对应数字（两者由 `metaKindOf` / `forMetaKind` 互相映射）；解析时会交叉校验「魔数种类」与「META.kind」是否一致。

### 视频下载目标（非备份）

视频下载不进备份，也不进音频缓存：`DownloadTask.target = DownloadTarget.gallery` → `DownloadQueueService._runGalleryDownload` → 原生 `saveToGallery`（MediaStore `Movies/WebdavMediaManager`）。因此画廊任务的 `localPath` 存的是 `content://` URI 或 API<29 的绝对路径。

---
