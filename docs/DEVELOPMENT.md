# 开发文档（开发者 / Coding Agents）

面向人类开发者与自动化 coding agent 的可执行指南。产品概览见根目录 [README.md](../README.md)；**细节与约束以本文为准**。

仓库：https://github.com/SenkjM/WEBDAV-music-player  
许可：**AGPL-3.0**（见根目录 `LICENSE`）。

---

## 1. 项目概览与目标

**WebDAV 音乐播放器**是 Android-first 的 Flutter 客户端：

- 在 WebDAV 上浏览目录 → **先下载到本地缓存** → 再用本地路径播放。
- **不做网络流式播放**（`just_audio` 只用 `AudioSource.file`；播放路径上禁止隐式入队下载）。
- 本地「音乐库」持久化标签 / CUE 分片 / 封面缩略图；**清空音频缓存不会毁掉曲库身份**。
- 多 WebDAV 账号、下载队列、歌单（本地 + 可选 M3U8 同步）、按站点备份 / 恢复、媒体通知（`audio_service`）。

`pubspec.yaml` 描述：`Android-first WebDAV music player — download-to-cache, never stream.`

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
| 下载队列 / CUE 组下载 / ingest | `download_queue_service.dart`, `library_service.dart` |
| music_id / 路径规范化 | `utils/track_identity.dart` |
| DB schema（accounts/tracks/cue_*/cache） | `library_database.dart`（当前 **schemaVersion = 5**） |
| 网络库 UI / 预览 CUE | `network_library_screen.dart` |
| 音乐库 UI / 销毁 / 多选分享 | `library_screen.dart`, `library_actions.dart` |
| 缓存路径 / 过期清理 / annex | `cache_service.dart` |
| 备份 ZIP / WMPB1 | `backup_service.dart`, `backup_crypto.dart` |
| 设置（缓存策略、封面边长） | `settings_service.dart`, `settings_screen.dart` |
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
5. 播放：`ClippingAudioSource`（`MusicAudioHandler._sourceFor`）按 INDEX 裁切。

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

- `just_audio`：实际解码 / 播放本地文件。
- `audio_service`（vendored）：`MusicAudioHandler` → MediaSession + MediaStyle 通知。
- 配置要点（`initMusicAudioService`）：
  - 通道 id：`com.webdav.webdav_music_player.audio.v4`（IMPORTANCE_DEFAULT；历史曾用 v1–v3，升级靠换 id 生效）
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

### 起播静音（勿卡住）

- 静音窗口应尽量短：主要盖住 `setAudioSource` / clip 准备；**在可闻的 `play()` 之前恢复 volume=1**。
- 历史回归（`922d3c4`）：若「先 `play()` 再 unmute」，冷启动 `play` Future 卡住会把音量永久留在 0 → 首曲无声。`play()` / `playing` 与 `finally` 需有 unmute 安全网；见 `test/music_audio_handler_volume_safety_test.dart`。
- **禁止**在每次 `play()` 调 `androidForceEnableMediaButtons`（会播一段静音 AudioTrack → 双击杂音）。
- `stop()` 必须清除 mute 标志并恢复 volume=1。
- 不要把 `ProcessingState.idle` 在仍有选中曲时转成 `AudioProcessingState.idle`（native 会 `stop()` 拆掉通知）。详见 PATCHES.md 与 idle guard 测试。

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

## 10. 备份格式

- **默认范围**：按 WebDAV **站点**（`accountId` + base URL），不是整机糊成一团。
- 远程路径：`/WebDAVMusicPlayer/backup/<accountDir>/backup-<UTC>.wmpbak`，同目录 `webdav_music_backup.wmpbak`（latest）。
- `BackupService.formatVersion = 3`：统一包内含该站凭证、`library_json`（tracks + cue_albums + cue_slices）、相关歌单、covers、settings。
- **不含**：`music_cache` 音频、下载队列。
- 加密：可选口令，魔数 **`WMPB1`** + PBKDF2 + AES-256-GCM（`backup_crypto.dart`）。
- **恢复策略**：`cachePolicy: restore_uncached_unless_files_on_disk`——恢复后 cache annex 视为未缓存，**除非**文件已真实在磁盘；避免「库以为有文件但播不了」。
- 可选「全部账号」`full-backup-….wmpbak`（非默认）。
- 恢复按站点写回，校验 accountId/URL，禁止把站点 A 凭证合并进站点 B。

---

## 11. CI 与签名

工作流：`.github/workflows/android-build.yml`

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
- 不要让起播静音逻辑在异常路径卡死（`stop`/错误路径要 unmute）。
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
lib/services/music_audio_handler.dart  # 媒体会话；静音；ClippingAudioSource
lib/services/audio_player_service.dart # 仅本地播放门面
lib/services/download_queue_service.dart
lib/services/library_service.dart      # ingestCueAlbum 等
lib/services/library_database.dart     # schema v5
lib/services/cache_service.dart
lib/services/backup_service.dart
lib/services/library_actions.dart      # 删除缓存 / 分享（禁 CUE）
lib/utils/track_identity.dart          # music_id / cue_id
lib/utils/cue_sheet.dart               # decodeCueText + parser
lib/utils/android_background.dart      # moveTaskToBack 通道
lib/utils/cover_image.dart             # 缩略图边长常量
lib/utils/backup_crypto.dart           # WMPB1
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
| **idle 拆掉媒体通知** | 把 just_audio idle 映射成 `AudioProcessingState.idle` | 有选中曲时用 loading 等非 idle；见 idle guard 测试 |
| **未下载显示「排队中」** | 远程浏览误用 queued 状态 | 未入队 → `TrackUiState.remote`，Chip 为空 |
| **播放器顺手下载** | 在 play 路径 enqueue | 拒绝并提示先下载（`892ff89`） |
| **清缓存误删曲库** | 把 tracks 和文件绑死 | 标签在 DB；cache 为 annex；销毁才是 wipe |
| **备份恢复后假「已缓存」** | 恢复了 annex 路径但文件未打包 | 恢复策略 uncached unless on disk |
| **schema 升级丢库** | v5 `onUpgrade` 直接 DROP | bump version 前告知用户；无自动 migration |
| **OEM 无媒体通知** | LOW 通道 / 未 typed FGS | 保留 vendor 补丁与 v4 通道；真机测 ColorOS/OnePlus |

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
flutter test test/cache_group_deletion_test.dart
# 或全量
flutter test
```

---

*本文随代码演进；若与实现冲突，以源码与测试为准，并请更新本文。*
