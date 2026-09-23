# A03 · 播放与曲库行为

> **文档编号 A03** · 状态：已完成 · 模式：归档（正文只读）  
> 总索引：[INDEX.md](../INDEX.md)  
> 自原开发文档拆出：CUE、媒体会话、网络库状态、销毁与封面。

勘误不得直接改正文。需要更正时新建编号文档，并在索引备注。

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
