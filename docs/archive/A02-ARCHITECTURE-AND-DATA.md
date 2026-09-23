# A02 · 架构与数据模型

> **文档编号 A02** · 状态：已完成 · 模式：归档（正文只读）  
> 总索引：[INDEX.md](../INDEX.md)  
> 自原开发文档拆出：项目概览、分层、数据模型、文件索引。

勘误不得直接改正文。需要更正时新建编号文档，并在索引备注。

---

## 1. 项目概览与目标

**Webdav Media Manager**是 Android-first 的 Flutter 客户端：

- 在 WebDAV 上浏览目录 → **先下载到本地缓存** → 再用本地路径播放。
- **不做网络流式播放**（`media_kit` 的 `Player.open` 只喂本地文件路径；播放路径上禁止隐式入队下载）。
- 本地「音乐库」持久化标签 / CUE 分片 / 封面缩略图；**清空音频缓存不会毁掉曲库身份**。
- 多 WebDAV 账号、下载队列、歌单（本地 + 可选 M3U8 同步）、按站点备份 / 恢复、媒体通知（`audio_service`）。

`pubspec.yaml` 描述：`Android-first WebDAV music player — download-to-cache, never stream.`

---

---

## 4. 架构地图（改哪里）

### 启动与依赖注入

- `lib/main.dart`：先 `initMusicAudioService()`（Android/iOS），再 `AppState.init()`，再 `runApp`。
- `lib/providers/app_state.dart`：组装所有服务；`MultiProvider` 对外暴露。
- UI 状态：`provider` + 各 `ChangeNotifier` 服务。

### 分层（按目录）

| 层 | 路径 | 职责 |
|----|------|------|
| Screens | `lib/screens/` | 页面：音乐库 / 网络库 / 播放器 / 下载 / 设置 / 壳 |
| Widgets | `lib/widgets/` | 迷你条、封面、状态 chip 等 |
| Providers | `lib/providers/app_state.dart` | 生命周期编排（含 `destroyMusicLibrary`） |
| Services | `lib/services/` | WebDAV、缓存、下载队列、曲库、播放、备份、同步 |
| Models | `lib/models/` | `LibraryTrack`、账号、下载任务、WebDAV 条目等 |
| Utils | `lib/utils/` | `music_id`、CUE 解析、备份加密、路径 |
| Theme | `lib/theme/app_theme.dart` | 浅色系主题 |
| Android | `android/app/.../MainActivity.kt` | `AudioServiceFragmentActivity` + MethodChannel |
| Vendor | `packages/audio_service/` | 带 Android 14+ FGS / 通道补丁的 audio_service |

### 关键服务「改什么找谁」

| 需求 | 优先文件 |
|------|----------|
| 播放 / 媒体会话 / 起播静音 | `music_audio_handler.dart`, `audio_player_service.dart` |
| 视频播放器 UI（低位控件 / tap 显隐 / 中间双击暂停 / 长按加速 / 倍速滑块） | `video_player_screen.dart`, `video_playback_service.dart`, `models/video_settings.dart` |
| 视频播放列表（渐进扫描 / 上一个下一个 / 自动连播） | `video_queue_controller.dart`, `video_player_screen.dart` |
| 视频媒体通知 / 音乐-视频互斥 | `music_audio_handler.dart`（`AudioHandlerMode.video`）, `audio_player_service.dart` |
| 下载队列 / CUE 组下载 / ingest / 视频→相册 | `download_queue_service.dart`, `library_service.dart`, `models/download_task.dart` |
| 系统相册 / 下载目录 / SAF 导入 / PiP 回调（原生） | `android/.../MainActivity.kt`, `services/platform_export_service.dart`, `utils/video_pip.dart` |
| music_id / 路径规范化 | `utils/track_identity.dart` |
| **音乐/视频后缀判定（单一真相）** | `models/file_type_config.dart`；下载队列用 `configureFileTypes` 注入，**禁止**再写硬编码后缀列表 |
| DB schema（accounts/tracks/cue_*/cache/deleted_tracks/sync_state） | `library_database.dart`、`download_store.dart`；`tracks`/`cue_*` 用 `source_name` + `rev`，删除走独立表 `deleted_tracks`（不做软删列），同步游标在 `sync_state`。**不写迁移分支**：`onUpgrade` 直接 drop + 重建 |
| 网络库 UI / 预览 CUE / 多选下载 | `network_library_screen.dart` |
| 音乐库 UI / 销毁 / 多选删除与销毁 | `library_screen.dart`, `library_actions.dart` |
| 缓存路径 / 过期清理 / annex | `cache_service.dart` |
| **同步 / 备份（凭证 + 曲库 + 歌单 + 归档）** | `sync_service.dart`, `screens/sync_screen.dart`, `backup_service.dart` |
| **音乐库增量索引（清单 + 二进制分片）** | `services/library_sync_store.dart`（`index.json` 清单 + `lib-*.wdmm` 基础分片 + `seg-*.wdmm` 增量 + `del-*.wdmm` 墓碑；**无自动合并**，≥20 片由 UI 建议重建）、`services/library_shard_codec.dart`（曲目/墓碑 ⇄ 容器记录、封面每首一份）、`utils/library_index_merge.dart`（纯合并函数） |
| **曲目身份 = 网盘名 + remote_path** | `utils/track_identity.dart`；行内**不含 URL / 用户名**，`网盘名 → url/用户名/密码` 只由本机 accounts 表解析（`AccountsService.accountForSource` / `idForSource` / `nameForAccount`） |
| **下载队列只存网盘名** | `DownloadTask.sourceName`；`DownloadQueueService._accountIdForSource` 在真正传输时才解析账号，改名/重加网盘不会留下过期指针 |
| **二进制容器（云端分片 + 备份归档）** | `utils/wmp_container.dart`：8 字节魔数 `'WDMM' + kind(2) + layout(2)` + `u16 sectionCount` + `u16 flags`（预留）+ section 表 + 每 section CRC32；META/TRACKS/COVERS/TOMBS/CREDENTIALS/PLAYLISTS/SETTINGS/**CUEALBUMS**；曲目记录 tag-value varint；封面**每首一份**、连续排布便于按需 seek。**魔数即文件种类**，见下表 |
| **备份归档 `.wdmm` = 同一容器** | `backup_service.dart`：TRACKS（含 CUE 分片行）+ 原始 COVERS（每行一份）+ JSON side sections；整包可选口令加密。`buildJsonExport()` 另出**可读 JSON（不含封面）**排障用；导入按魔数自动识别容器 / JSON（**不再用 ZIP**，`archive` 依赖已移除） |
| **云端库整理 / 审计** | `library_sync_store.dart`(`audit`/`deleteOrphans`, 纯函数 `auditLibraryParts`)：孤儿文件、缺失分片；UI 在同步页「整理」 |
| **单增版本时钟 rev** | `utils/rev_clock.dart`：`rev = max(nowMs, last+1)`，严格单增、时钟回拨不回退；`compareRev` 版本相同时按 deviceId 决胜 |
| 凭证加密（仅密码） | `utils/credential_vault_crypto.dart`, `credential_vault_service.dart` |
| 分享重命名 | `share_rename_service.dart`, `library_actions.dart`；配置在 `settings_screen.dart` |
| 设置（缓存策略、封面边长、视频倍速、分享模板） | `settings_service.dart`, `settings_screen.dart`, `video_settings_screen.dart` |
| 通知权限 / 「音乐播放」通道 | `notification_permission_service.dart`, `media_notification_channel.dart` |
| 下载进度 / 完成通知（两级进度条） | `download_notification_service.dart`, `download_queue_service.dart` |
| 凭证 / 备份加密密钥（用户指定） | `settings_service.dart`(`vaultPassphrase`, Keystore), `sync_screen.dart`, `credential_vault_crypto.dart` |
| 根返回键后台 / 抽屉退出 | `home_shell.dart`, `android_background.dart`, `MainActivity.kt` |

### 导航壳

`HomeShell`：Drawer（音乐库、歌单、网络库、下载队列、设置、关于）+ 全局迷你条（设置页隐藏）。子页用嵌套 `Navigator`，避免盖住迷你条。

---

---

## 5. 数据模型

### `music_id`（稳定离线主键，SHA-1 hex）

实现：`lib/utils/track_identity.dart`

| 类型 | 规则 |
|------|------|
| 普通曲目 | `sha1(accountId + '\0' + normalizeRemotePath(remotePath))` |
| CUE 虚拟分片 | `sha1(accountId + '\0' + normalize(cuePath) + '\0' + trackIndex)` |
| CUE 专辑 `cue_id` | `sha1('cue' + '\0' + accountId + '\0' + normalize(cuePath))` |

注意：

- **不是**音频字节内容哈希。
- `normalizeRemotePath`：统一 `/`、去重斜杠、保证以 `/` 开头。
- 遗留歌单键仍可用 `trackIdentityKey(accountId, remotePath)`（`accountId\0remotePath`），新逻辑优先 `musicId`。
- 缓存文件名短茎：`music_id` 前 16 位（`identityHashStem`）。

### 表结构（`music_library.db`，schema v5）

| 表 | 含义 |
|----|------|
| `accounts` | WebDAV 站点（id / name / url / username）；密码在 secure storage |
| `tracks` | 普通曲目标签；PK=`music_id`；`UNIQUE(account_id, remote_path)` |
| `cue_albums` | CUE 专辑身份 |
| `cue_slices` | 虚拟分片（clip 起止、audio_music_id、cache_group_id） |
| `cache` | **annex**：`music_id → local_path`（与磁盘 `File.exists` 对账） |

升级策略：`onUpgrade` **整库 DROP 重建**（无渐进 migration）。改 schema 即 bump `LibraryDatabase.schemaVersion`。

### tracks vs cache annex

- **曲库行**（标签 / 封面路径 / CUE clip）在清空音频后仍可保留。
- **可播条件**：cache annex 有行 **且** `File(localPath).exists`；否则视为未缓存。
- `CacheService.reconcileStaleAnnex()` 会清掉磁盘已不存在的 stale 行。

### 其它库

| 文件 | 用途 |
|------|------|
| `download_queue.db` | 下载任务 |
| `playlists.db` | 本地歌单（与 `music_cache` 分离） |
| 应用文档 `covers/` | 正方形 JPEG 缩略图 |
| 应用文档 / cache 目录 | 音频文件 |

**库在清缓存后仍在**：设置里「手动清空音频缓存」只删音频 + annex，保留 tracks / cue / covers。  
**「销毁音乐库」**才清标签、CUE 表、封面与对应本地音频（见第 9 节）。

### 仅本地播放

`AudioPlayerService.playTrack`：解析本地路径失败则设错误「本地无缓存，请先下载」，**不会**在播放器里入队下载。  
判定一律 `File.exists` / `existsSync`，不要信任「曾经 completed」的队列状态 alone。

---

---

## 13. 关键文件索引

```
lib/main.dart                          # 入口；AudioService 先于其它播放器
lib/providers/app_state.dart           # 服务组装；destroyMusicLibrary
lib/screens/home_shell.dart            # Drawer / 迷你条 / 返回与退出
lib/screens/library_screen.dart        # 本地音乐库；销毁；多选
lib/screens/network_library_screen.dart# WebDAV 浏览；CUE 预览下载
lib/screens/player_screen.dart         # Now Playing
lib/screens/downloads_screen.dart      # 下载队列 UI
lib/screens/settings_screen.dart       # 缓存 / 备份 / 封面尺寸 / 通知测试
lib/services/music_audio_handler.dart  # 媒体会话；media_kit Player；clip 相对 position/duration
lib/services/media_notification_channel.dart # 「音乐播放」通道唯一定义（须与 AudioServiceConfig 同步）
lib/services/notification_permission_service.dart # flutter_local_notifications：建通道 + 权限/通道状态
lib/services/audio_player_service.dart # 仅本地播放门面
lib/services/download_queue_service.dart # 队列；跨账号下载；通知聚合（_sessionIds 只算本轮）
lib/services/download_notification_service.dart # 两级进度（当前文件 2001 / 整批 2002）+ 完成 2003
lib/utils/app_snack.dart               # 单槽 SnackBar（去重 / 覆盖 / 点消息消失 / 可关闭）
lib/services/library_service.dart      # ingestCueAlbum 等
lib/services/library_database.dart     # schema v5
lib/services/cache_service.dart
lib/services/backup_service.dart
lib/services/library_actions.dart      # 删除缓存 / 分享（禁 CUE）
lib/utils/track_identity.dart          # music_id / cue_id
lib/utils/cue_sheet.dart               # decodeCueText + parser
lib/utils/android_background.dart      # moveTaskToBack 通道
lib/utils/cover_image.dart             # 缩略图边长常量
lib/utils/backup_crypto.dart           # WDMMEN01 加密信封
lib/models/library_track.dart
lib/widgets/track_status_chip.dart     # remote 不显示「排队」
lib/widgets/mini_player.dart
packages/audio_service/                # vendor + PATCHES.md
android/.../MainActivity.kt            # AudioServiceFragmentActivity；诊断通道
.github/workflows/android-build.yml
test/                                  # 身份 / CUE / 本地播放 / idle guard 等
```

---
