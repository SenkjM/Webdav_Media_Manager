# 开发文档（开发者 / Coding Agents）

面向人类开发者与自动化 coding agent 的可执行指南。产品概览见根目录 [README.md](../README.md)；**细节与约束以本文为准**。

仓库：https://github.com/SenkjM/WEBDAV-music-player  
许可：**AGPL-3.0**（见根目录 `LICENSE`）。

---

## 1. 项目概览与目标

**Webdav Media Manager**是 Android-first 的 Flutter 客户端：

- 在 WebDAV 上浏览目录 → **先下载到本地缓存** → 再用本地路径播放。
- **不做网络流式播放**（`media_kit` 的 `Player.open` 只喂本地文件路径；播放路径上禁止隐式入队下载）。
- 本地「音乐库」持久化标签 / CUE 分片 / 封面缩略图；**清空音频缓存不会毁掉曲库身份**。
- 多 WebDAV 账号、下载队列、歌单（本地 + 可选 M3U8 同步）、按站点备份 / 恢复、媒体通知（`audio_service`）。

`pubspec.yaml` 描述：`Android-first WebDAV music player — download-to-cache, never stream.`

---

## 后续计划

与 README 的[后续计划（路线图）](../README.md#后续计划路线图)保持同一份概览；**本表仅规划，未排期实现。除非用户明确要求，agents 不得开始这些工作，也不要把规划项当作已实现功能。**

下次开发分块计划（后台下载优先 + 文件动作 / 多选重构）见：[NEXT-DEV-PLAN.md](NEXT-DEV-PLAN.md)（唯一计划源；旧 [BUGS-AND-PLANS.md](BUGS-AND-PLANS.md) 仅作跳转）。

| 优先级 | 方向 | 说明 | 状态 |
|---|---|---|---|
| 高 | WebDAV 管理增强 | 在现有基础上扩展：上传本地文件、移动/复制、属性查看、批量操作、回收站，以及覆盖冲突策略等；现有网络库已有新建文件夹、重命名、删除。 | 规划中 |
| 高 | 国产 ROM 媒体体验 | ColorOS / 一加等国产 ROM 的媒体通知与后台保活仍需真机验证与加固。 | 规划中 |
| 中 | 视频播放体验 | 缓冲进度条第二层、空闲自动隐藏控件、手势引导；见 `DEVICE-QA-CHECKLIST` 未做项。 | 规划中 |
| 中 | 同步体验 | 冲突可视化，以及云端分片整理与审计体验打磨。 | 规划中 |
| 低 | 音乐输出后端 | 规划 AudioTrack / AAudio 等可选输出后端；仅规划，成本较高。 | 规划中 |
| 中 | 启动与低端机体验 | 持续优化启动耗时与资源占用，减少启动阶段的可感知等待。 | 规划中 |
| 低 | 无障碍与多语言 | 补充无障碍语义、字号适配，并逐步完善多语言支持。 | 规划中 |
| 低 | iOS / 桌面端 | 在 Android-first 定位不变的前提下，作为远期跨平台评估方向。 | 规划中 |

---

## 2. 分支与发布策略

| 分支 | 用途 |
|------|------|
| `main` | 稳定主干 |
| `beta` | 预发布线；**GitHub Pre-release 只从 beta 发布**（标签 `prerelease`） |
| `dev` | 实验线；助手默认在此试功能 / 不稳定改动 |

推荐流程：`dev` 试验 → 成熟后合入 `beta` → 验证 Pre-release → 再合入 `main`。

### CI 触发（重要）

工作流：`.github/workflows/android-build.yml`

| 事件 | 行为 |
|------|------|
| **任意分支 push** | **不**触发构建 |
| 每天定时（cron `0 16 * * *`，约北京时间 00:00） | 检视 **beta**：相对上次 `prerelease` 有新提交才构建发布；无变动跳过 |
| 手动 `workflow_dispatch` | 可构建；**仅当所选引用为 beta 时才发布 Pre-release** |

**对 agents 的硬约束：**

- **永远不要**为了「看构建结果」去改 workflow 加 `on: push`，或擅自 `gh workflow run`。
- 需要打 Pre-release 时：**先等用户确认**，再在 UI / `gh` 上对 **beta** 做 `workflow_dispatch`。
- 日常开发推送 **`origin/dev` only**；不要擅自推 `beta` / `main`，不要触发 Actions。

---

## 3. 本地环境搭建

### 依赖

- Flutter **stable**（仓库 `environment.sdk: ^3.13.4`；本机常用路径示例 `/workspace/flutter-sdk`）
- Android SDK + JDK 17（与 CI `setup-java` 一致）
- 真机或模拟器（媒体通知 / FGS 行为建议真机验证）

### 常用命令

```bash
cd WEBDAV-music-player
flutter pub get
flutter analyze
flutter test
flutter run                    # debug
flutter build apk --release    # 本地 release；签名见下文 CI/signing
```

Vendored 依赖：`audio_service` 使用 path 包 `packages/audio_service`（勿随意改回 pub.dev 版本，除非同步补丁说明）。

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

## 6. CUE 分轨

### UX 流程（网络库）

1. 用户点击 `.cue` → **预览**曲目列表（`network_library_screen` + `CueSheetParser`）。
2. 确认后 **整组下载**：CUE + 引用的音频进同一 `cacheGroupId`。
3. 下载完成后 `DownloadQueueService` 调 `LibraryService.ingestCueAlbum` → 虚拟曲目进入音乐库。
4. **原始 `.cue` 文件本身不是音乐库里的「一首歌」**；库里是 `cue_slices` 虚拟行。
5. 播放：`Media(path, start:, end:)`（`MusicAudioHandler._mediaFor`）原生按 INDEX 裁切。

### 编码：`decodeCueText`

`lib/utils/cue_sheet.dart`：

- 处理 UTF-8 BOM、UTF-16 LE/BE；严格 UTF-8 失败时用 `allowMalformed`（兼容 GBK 等）。
- **历史回归**：用 `File.readAsString` 读非 UTF-8 CUE 会抛错，导致下载成功但 **虚拟曲目永不 ingest**。解析前必须走 `decodeCueText(bytes)`。

### 展示标签

- `LibraryTrack.cueMultiSliceLabel` / UI：`「多歌曲合并分片」`。
- 虚拟路径标记：`#cue:<trackIndex>`（`cueVirtualRemotePath`）。

### 分享

- **禁止**分享 CUE 虚拟曲目：`shareLibraryTracks` 跳过 `isCueVirtual`，SnackBar「CUE 音轨不支持分享」。
- 已移除基于 ffmpeg 裁切导出的分享路径；不要重新加「裁一条出来再分享」。

### 删除

- 删缓存时按 **cache group** 整组提示 / 删除。
- 清空音频后 clip 元数据可留在库中，便于重新下载后续播。

---

## 7. 播放与媒体会话

### 栈

- `media_kit`（libmpv/FFI）：实际解码 / 播放本地文件；`Media(path, start:, end:)` 原生裁切 CUE 分片，`MusicAudioHandler` 再把绝对 position/duration 换算成 clip 相对值对外暴露。
- `audio_service`（vendored）：`MusicAudioHandler` → MediaSession + MediaStyle 通知；播放引擎与通知桥接解耦，`Player` 的 stream 被动推送到 `playbackState`/`mediaItem`。
- Android 原生依赖 `libmpv`：`media_kit_libs_android_audio` 随 APK 打包各 ABI 的 so；CI 在 ubuntu-latest 上跑 `flutter test` 前需 `apt install libmpv-dev mpv`（`flutter test` 进程本身是 Linux 可执行文件，会走 GNU/Linux 加载路径）。
- 配置要点（`initMusicAudioService`）：
  - 通道 id：`com.senkjm.media_manager.audio.v4`（IMPORTANCE_DEFAULT；历史曾用 v1–v3，升级靠换 id 生效）
  - `androidStopForegroundOnPause: false`（避免 Android 12+ 暂停后再起 FGS 被拦）
  - 图标：`drawable/ic_stat_music`（不要用自适应 launcher）
- 补丁说明：`packages/audio_service/PATCHES.md`（Android 14+ typed `startForeground`、通道重要性、失败后 notify 回退、缺通知时重入 FGS）。

### 返回键 vs 退出

| 操作 | 行为 | 代码 |
|------|------|------|
| 根路由系统返回 | `moveTaskToBack`（等同 Home），**音乐继续** | `home_shell.dart` → `moveAppToBackground()` → `MainActivity.moveTaskToBack` |
| 抽屉「退出应用」 | `AudioPlayerService.stop()` 后 `SystemNavigator.pop()` | `home_shell.dart` |
| `onTaskRemoved` | Handler **空实现**，避免划掉任务直接停播 | `MusicAudioHandler.onTaskRemoved` |

**禁止**：在根返回路径上调用 `SystemNavigator.pop()`——会 finish Activity、拆掉 `AppState` / 播放器，表现为「一返回音乐就停」。

### 起播静音（历史背景，media_kit 起已移除）

- 旧栈（`just_audio`/ExoPlayer）冷启动 `play()` 前需要静音窗口盖住 `setAudioSource`，否则会有双击杂音或卡在音量 0；相关hack（`_muteForPrep`/`_waitReadyWhileMuted`）已随引擎换成 `media_kit`（libmpv）一起移除——mpv 没有这个问题，不要凭旧记忆重新引入。
- `_index < 0`（无选中曲）才广播 `AudioProcessingState.idle`；media_kit 没有 just_audio 式的过渡态 idle 事件，无需再靠 gate 抑制。详见 PATCHES.md 与 idle guard 测试。
- `stop()` 通过 `AudioSession.setActive(false)` 释放音频焦点；`play()` 通过 `setActive(true)` 申请焦点——media_kit 不像 ExoPlayer 那样自动管理 Android 音频焦点，中断（来电/其它 App 播放）靠 `audio_session` 的 `interruptionEventStream` 手动 duck/pause（见 `MusicAudioHandler._onInterruption`）。

### OEM 已知问题（ColorOS / OnePlus / Oppo 等）

- 低重要性媒体通道可能被系统栏隐藏 → 使用 **v4 + IMPORTANCE_DEFAULT**（锁屏 visibility PUBLIC）；通道被用户关掉时诊断字段 `channelBlocked`。
- ColorOS 媒体中心常忽略 `CONNECTING`：`loading + playing` 应映射为 **`BUFFERING`**，不要映射成会变成 CONNECTING 的 loading（`922d3c4` / vendor MediaSession TRANSPORT + STREAM_MUSIC）。
- Android 14+ 未声明 typed FGS 会导致通知永远不出现 → vendor 补丁必须保留。
- 设置页「测试媒体通知」含中文 OEM 提示（耗电不限制、通知含锁屏、允许关联启动）；诊断走 MethodChannel（**不要**在 `MainActivity` 引用 `AudioService` 类——见第 14 节）。
- Upstream changelog 曾记 Oppo/OnePlus Android 13 相关崩溃；升级 / 回退 `audio_service` 时对照 `PATCHES.md`。

---

## 8. 网络库 UX：未下载 ≠「排队中」

- `TrackUiState.remote`：未下载且从未入队 → **不显示**状态 Chip（`TrackStatusChip` 对 remote 返回空）。
- 仅用户点按 / 多选 / 文件夹递归下载后才入队，此时才可能出现「排队」「下载中」。
- 实现：`DownloadQueueService.uiStateFor` 末尾 `return TrackUiState.remote`；网络库列表对 remote 不渲染 chip。
- **不要**把「浏览可见的远程文件」默认标成排队。

迷你条 / 播放器：**从不**展示下载进度；未缓存曲在音乐库仅为占位 + 点按下载。

---

## 9. 销毁音乐库 vs 清空缓存；封面尺寸

| 操作 | 入口 | 删除内容 | 保留 |
|------|------|----------|------|
| 手动清空音频缓存 | 设置 | 音频文件 + cache annex（保护正在播放/下载） | tracks / cue / covers / 账号 / 歌单 |
| 自动按天/周清理 | 设置策略 | 同上（过期文件） | 同上 |
| **销毁音乐库** | 音乐库菜单「销毁」 | 标签、cue 表、压缩封面、对应本地音频、annex；歌单去掉失效引用 | **网络库与账号**；歌单壳可留空 |

实现：`AppState.destroyMusicLibrary()` → `library.destroyAll()` + `cache.markAllUncached()` 等。

### 封面缩略图边长

- 默认 `coverThumbSize = 100`；预设大图 `coverThumbSizeLarge = 300`；可自定义正方形边长（`clampCoverThumbSize`）。
- 设置只影响 **新写入** 的缩略图；已有文件保持旧尺寸，需重新下载/写标签或销毁后重下。
- `AppState.setCoverThumbSize` 同步到 `CoverService.thumbSize`。

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

## 11. CI 与签名

工作流：`.github/workflows/android-build.yml`

### 编译依赖参数

| 依赖 | 参数 | 说明 |
|------|------|------|
| JDK | `17`（temurin） | 与 AGP 9.1 / Kotlin `jvmTarget 17` 一致；`flutter_local_notifications` 依赖 core library desugaring（`android/app/build.gradle.kts` 已启用） |
| Flutter | `stable` | 与 `.metadata` 记录的本机 SDK 线一致（当前 stable 线：Dart `^3.13.4`） |
| Android SDK | `platform-tools` + `platforms;android-36` + `build-tools;36.0.0` | 对应 Flutter 默认 `compileSdk/targetSdk = 36`（`android/app/build.gradle.kts` 取 `maxOf(flutter.compileSdkVersion, 35)`） |
| Linux 测试库 | `libmpv-dev`、`mpv` | media_kit 的 Linux 后端，`flutter test` 需要 |
| Gradle | `cache: gradle` | 缓存 AGP/Gradle 编译依赖（`actions/setup-java`） |

### 版本号

| 变量 | 规则 |
|------|------|
| `VERSION_NAME` | `pubspec` 版本基（如 `1.0.0`）+ `-` + `SHORT_SHA`（sha 前 7 位） |
| `VERSION_CODE` | `1000 + github.run_number`（单调递增，便于覆盖安装） |

```bash
flutter build apk --release \
  --build-name="$VERSION_NAME" \
  --build-number="$VERSION_CODE"
```

### Secrets（仓库 Settings → Secrets）

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

固定内测 keystore，避免 Actions 换机器导致签名变化。从旧 debug 包换成内测签名需 **卸载一次**。

本地可用环境变量或未提交的 `android/key.properties`（**勿提交密钥**）。

Agents：**不要**打印 / 提交任何 keystore、token、密码。

---

## 12. Agents 编码约定

**Do**

- UI 文案用 **中文**；标识符 / 路径 / API 名保持英文。
- 默认在分支 **`dev`** 上开发、提交、推送 `origin/dev`。
- 推送前 `git fetch` + `pull --rebase`（可能有并发提交）。
- 改完跑 `flutter analyze` / 相关 `flutter test`。
- 播放只走本地文件；下载走队列服务。
- CUE 解析用 `decodeCueText`；ingest 后虚拟曲才进库。
- 根返回用 `moveTaskToBack`；真正退出才 `SystemNavigator.pop`。
- 保持 AGPL-3.0；显著修改保留版权与许可头（若文件已有）。

**Don't**

- 不要做流式播放 / 在 `playTrack` 里偷偷 enqueue。
- 不要把未下载远程文件标成「排队中」。
- 不要分享 CUE 虚拟曲；不要恢复已删除的 ffmpeg CUE 导出分享。
- 不要在 `MainActivity` 引用 `com.ryanheise.audioservice.AudioService` 类（见陷阱）。
- 不要重新引入 just_audio 时代的起播静音 hack；media_kit 不需要它（见第 7 节历史背景）。
- **不要**改 CI 为 push 自动构建；**不要**未经用户确认 `workflow_dispatch`；**不要**推 beta/main 或打 Pre-release，除非用户明确要求。
- 不要提交 `key.properties`、keystore、secrets、`.env`。
- 不要发明不存在的 API；以仓库源码为准。

提交信息风格：简短英文前缀（如 `docs:` / `fix:` / `feat:`）+ 说明，参考 `git log`。

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

## 14. 已知陷阱与历史回归

| 问题 | 原因 / 表现 | 正确做法 |
|------|-------------|----------|
| **UTF-8 CUE ingest 失败** | 非 UTF-8 CUE 用 `readAsString` 抛错；下载成功但库无虚拟曲 | 始终 `decodeCueText(bytes)` 再 `CueSheetParser`；见 `cue_library_ingest_test` |
| **MainActivity AudioService classpath** | 在 Kotlin 中 `import AudioService` 会拉进 `MediaBrowserServiceCompat`，release 编译失败 | 继承 `AudioServiceFragmentActivity`；通知诊断用 `NotificationManager` / `MediaSessionManager`，**不要**引用 `AudioService` 类（`251e46a`） |
| **切后台后通知/播放状态消失** | `AudioServiceActivity`（普通 `FlutterActivity` 变体）只重写 `provideFlutterEngine()`，未重写 `getCachedEngineId()`/`shouldDestroyEngineWithHost()`，导致其默认值为 `true`：Activity 被系统回收/从最近任务划掉时，共享的 `FlutterEngine`（同时承载 `MusicAudioHandler`）被销毁，通知与播放状态一起消失 | `MainActivity` 改继承 `AudioServiceFragmentActivity`（正确重写全部三个方法，engine 不随 Activity 销毁） |
| **SystemNavigator.pop 停音乐** | 根返回 finish Activity → 拆掉 handler | 根返回 `moveTaskToBack`；仅抽屉「退出」才 pop（`9c9d5c5`） |
| **起播双击杂音 / 首曲无声** | 每次 play 播静音 AudioTrack；或 unmute 排在卡住的 `play()` 之后 | 禁止 `androidForceEnableMediaButtons` on play；mute 仅罩住 setAudioSource，**play 前 unmute**；`stop`/finally 清 mute（`0ed9591`, `922d3c4`） |
| **idle 拆掉媒体通知** | 只在无选中曲（`_index < 0`）时广播 `AudioProcessingState.idle` | 见 idle guard 测试 |
| **未下载显示「排队中」** | 远程浏览误用 queued 状态 | 未入队 → `TrackUiState.remote`，Chip 为空 |
| **播放器顺手下载** | 在 play 路径 enqueue | 拒绝并提示先下载（`892ff89`） |
| **清缓存误删曲库** | 把 tracks 和文件绑死 | 标签在 DB；cache 为 annex；销毁才是 wipe |
| **备份恢复后假「已缓存」** | 恢复了 annex 路径但文件未打包 | 恢复策略 uncached unless on disk |
| **schema 升级丢库** | v5 `onUpgrade` 直接 DROP | bump version 前告知用户；无自动 migration |
| **OEM 无媒体通知** | LOW 通道 / 未 typed FGS | 保留 vendor 补丁与 v4 通道；真机测 ColorOS/OnePlus |
| **通道状态查不到 / 与系统不一致** | 通道原先只由首次播放的原生 `createChannel()` 创建，设置页在播放前读到「未创建」 | 由 `notification_permission_service.dart` 经 `flutter_local_notifications` 在启动时建通道（`media_notification_channel.dart` 为唯一定义）；原生侧发现通道已存在即复用，故两侧参数必须一致（IMPORTANCE_DEFAULT、静音、不震动、无角标） |
| **Android 13+ 通知抛 `You must specify an icon resource id to build a CustomAction`** | `MediaControl.stop`（以及 ff/rewind）在 API 33+ 会被 audio_service 转成 `CustomAction`，其 builder 在图标解析为 0 时抛异常；vendor 插件自带的 `drawable/audio_service_*` 图标在该 app 的 release 构建里不可靠合并 | 媒体控制按钮改用 app 自带 `drawable/ic_media_*` 矢量图标（与 `ic_stat_music` 同源、必能解析）：见 `music_audio_handler.dart` 的 `_k*Control` 常量、`android/app/src/main/res/drawable/ic_media_*.xml` 与 `res/raw/keep.xml` |

相关提交可参考：`c235c92`（CUE ingest）、`1649677`（music_id v5 / 备份）、`0ed9591`（mute + remote chip）、`922d3c4`（unmute before play + ColorOS BUFFERING / v4）、`9c9d5c5`（返回键）、`251e46a`（MainActivity）、`ebe85b7`（禁用 push 触发 CI）。

---

## 15. 测试入口（改核心逻辑时优先跑）

```bash
flutter test test/library_data_model_test.dart
flutter test test/cue_sheet_test.dart
flutter test test/cue_library_ingest_test.dart
flutter test test/local_only_play_policy_test.dart
flutter test test/network_remote_status_test.dart
flutter test test/music_audio_handler_idle_guard_test.dart
flutter test test/music_audio_handler_volume_safety_test.dart
flutter test test/media_notification_channel_test.dart
flutter test test/cache_group_deletion_test.dart
# 或全量
flutter test
```

---

*本文随代码演进；若与实现冲突，以源码与测试为准，并请更新本文。*
