# 05 · 音频播放

> 编号 05 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/services/music_audio_handler.dart`、`audio_player_service.dart`、`lib/screens/player_screen.dart`

> **占位（开发中）**：串流与缓存已合一为同一套底部播放控件（只差本地是否有音频）；播放队列持久化 / 编辑、元数据 enrich 与预载职责见 [99 §20](99-IN-PROGRESS.md)。

## 1. 统一播放与队列

- `AudioPlayerService.playTrack` 统一缓存播放 / 串流播放：缓存模式优先 `music_cache`（缺文件入队并等待，可接受系统管理的 `prefetch_cache` 完整音频）；串流模式优先本地，否则临时预载文件或远端 URL。
- 起播前**不等待**刮削：队列先落地（身份 + 可选库元数据），播放成功后后台按播放顺序把未入库条目逐个入队 scan，入库后自动 enrich（标题 / 封面 / 时长 / 通知栏）。
- 队列是**引用曲库的公共队列**：条目只存身份（`sourceName` + `remotePath`/`musicId`/CUE 字段），元数据不单独维护；持久化到本机 JSON，**不进备份 / 同步**，冷启动恢复但不自动播放。
- 队列编辑：默认「插播」（新批次插到当前曲之前并立即播放，旧当前曲保留在其后），另提供「添加到末尾」FIFO；允许重复；上移 / 下移 / 删除；清空按钮需二次确认。
- 预载窗口保留（设置里仍是 ±N），但**只做音频 lookahead**；标签 / 封面的拉取与入库统一走持久化刮削。CUE 分片在缓存模式先缓存 backing audio 再裁切；流式模式用 `Media(uri, start:, end:)`，远端不可 seek 时自动回退为「缓存后再播」。

## 2. 播放栈

| 组件 | 职责 |
|------|------|
| `media_kit`（libmpv / FFI） | 实际解码与播放本地文件；`Media(path, start:, end:)` 原生裁切 CUE 分片 |
| `audio_service`（**vendored**：`packages/audio_service/`） | `MusicAudioHandler` → MediaSession + MediaStyle 通知；播放引擎与通知桥接解耦，`Player` 的 stream 被动推到 `playbackState` / `mediaItem` |
| `audio_session` | 音频焦点与中断（来电 / 其它 App 播放）→ `MusicAudioHandler._onInterruption` 手动 duck / pause |

- 不要随手把 vendored `audio_service` 换回 pub.dev 版本；补丁清单在 `packages/audio_service/PATCHES.md`（Android 14+ typed `startForeground`、通道重要性、失败后 notify 回退、缺通知时重入 FGS）。
- 通道 id `com.senkjm.media_manager.audio.v4`、`androidStopForegroundOnPause: false`、图标 `drawable/ic_stat_music`（不要用自适应 launcher 图标）。通道的唯一定义与权限见 [07](07-NOTIFICATIONS.md)。

## 3. 返回键 vs 退出

| 操作 | 行为 | 代码 |
|------|------|------|
| 根路由系统返回 | `moveTaskToBack`（等同 Home），**音乐继续** | `home_shell.dart` → `moveAppToBackground()` → `MainActivity.moveTaskToBack` |
| 抽屉「退出应用」 | `AudioPlayerService.stop()` 后 `SystemNavigator.pop()` | `home_shell.dart` |
| `onTaskRemoved` | Handler 空实现，避免划掉最近任务直接停播 | `MusicAudioHandler.onTaskRemoved` |

**禁止**在根返回路径上调用 `SystemNavigator.pop()`：那会 finish Activity、拆掉 `AppState` 与播放器，表现为「一返回音乐就停」。

## 4. CUE 分片播放

- 播放：`Media(path, start:, end:)`（`MusicAudioHandler._mediaFor`），由 libmpv 按 INDEX 原生裁切。
- 对外：`MusicAudioHandler` 把绝对 position / duration 换算成 **clip 相对值**再暴露给通知和界面。
- 分片的产生与身份见 [03 §4](03-MUSIC-LIBRARY.md) 与 [01 §1](01-DATA-MODEL.md)。

## 5. 起播静音：历史背景，已移除

旧栈（`just_audio` / ExoPlayer）冷启动 `play()` 前需要一段静音窗口盖住 `setAudioSource`，否则有双击杂音或卡在音量 0。相关 hack（`_muteForPrep` / `_waitReadyWhileMuted`）已随引擎换成 `media_kit`（libmpv）一起删除——**mpv 没有这个问题，不要凭旧记忆重新引入**。

## 6. idle 广播

只有当 `_index < 0`（没有选中曲目）时才广播 `AudioProcessingState.idle`。media_kit 没有 just_audio 那种过渡态 idle 事件，不需要再用 gate 抑制；回归由 idle guard 测试守着（见 [09](09-MISC.md) 测试入口）。

## 7. OEM 已知问题（ColorOS / 一加 / Oppo）

- 低重要性媒体通道可能被系统栏隐藏 → 用 **v4 + IMPORTANCE_DEFAULT**（锁屏 visibility PUBLIC）；通道被用户关掉时诊断字段为 `channelBlocked`。
- ColorOS 媒体中心常忽略 `CONNECTING`：`loading + playing` 应映射为 **`BUFFERING`**，不要映射成会变成 CONNECTING 的 loading。
- Android 14+ 未声明 typed FGS 会导致通知永不出现 → vendor 补丁必须保留。
- 诊断走 MethodChannel；**不要**在 `MainActivity` 里 import `AudioService` 类（会把 `MediaBrowserServiceCompat` 拉进 release 编译）——见 [09](09-MISC.md) 陷阱表。

## 8. 迷你播放条

- 只在有当前曲目时出现；**从不**显示下载 / 准备进度。
- 顶部那条进度线**可拖拽定位**：拖动期间显示手指位置，松手 seek 到该位置。
- 松手后刻度会保持到播放器回报接近的位置（或 900 ms 超时），避免 seek 还没落地时回跳。
- 单击这条线（以及迷你条其它位置）仍然是打开完整播放器，不会误 seek；时长为未知时拖拽无效。
- 实现：`lib/widgets/mini_player.dart` 的 `_MiniProgressBar`（只有触摸条被加高，视觉仍是 2.5 px 细线）。

## 9. 音乐流式播放页

> 流式文字标签 / 内嵌歌词（开发中）：见 [99 §14](99-IN-PROGRESS.md)。


`lib/screens/music_stream_screen.dart`。它和视频播放页共用同一条远端流管线与同一个媒体会话，但界面完全不同——因为「正在听的歌」和「正在看的片」要求不一样：

| 项 | 视频播放页 | 音乐流式播放页 |
|----|------------|----------------|
| 图像 | `VideoController` + libmpv 输出 | **不建**，只有封面占位 |
| 控件 | 贴底、点按切换显隐、自动隐藏 | 居中常驻，**不自动隐藏** |
| 手势 | 左右亮度 / 音量、双击、长按加速 | **全部没有**，只有按钮与可拖动进度条 |
| 旋转 | 横屏 | 不锁定也不强制，随系统 |
| 画中画 | 有 | **没有** |
| 队列 | 同目录视频队列 | 同目录音频队列，放完自动下一首 |
| 控制条 | 快退 / 播放 / 快进 | 上一首 / 播放 / 下一首，两端是**播放模式**与**播放列表**（快退快进移到进度条下方） |

- **自动连播**：控制器（`VideoQueueController`）不实现推进，谁开播谁接下一首——这一页监听 `player.stream.completed`（视频页早已有这路订阅；「自动连播」的 `autoAdvance` 字段全库没有读取方，是历史空壳）。
- **播放模式**（控制条最左边轮换）：单曲循环 / 顺序 / 列表循环。存在设置里，下次进页面沿用。**顺序**到队尾停住，**列表循环**回第一首。两个实现约束：流式页与视频页**共用同一个播放器实例**（`music_audio_handler.videoPlayer`），音乐页设了 `loop` / `single` 后视频页打开时要重置成 `none`，否则视频跟着循环；到队尾**不能**靠播放器的 `PlaylistMode` 兜底——流式页在播放器眼里始终只有一条媒体（切歌是 `_open` 重新开流），`loop` 只会退化成重播同一首。
- **播放列表**（控制条最右边）：面板外形与视频页一致，另加**搜索框**；搜索激活时每行多一行相对目录，用来区分子目录里的同名曲。
- **搜索子目录**由「设置 → 网络库 → 音频流式」的开关决定（**默认关**；已在设置里明确打开的用户不受影响）：关掉就只列当前这一层。这是音乐流式自己的开关，和图片查看里那个同样默认关闭的子目录扫描不是同一个偏好。
- 判定走 [02 §2](02-NETWORK-LIBRARY.md) 的动作模型：网络库在打开前就按后缀决定进哪一页，把音频改成视频后缀也照样进这一页。
- 退出页面会 `VideoPlaybackService.stop()`，也就是 `exitVideoMode()`：媒体会话还给本地播放（通知栏会回到之前暂停的本地歌；这是已知的交互粗糙处，优化方向见 [99 §1](99-IN-PROGRESS.md)）。
- 这一页**初步实现**：会话归还、常亮、封面与时长、停止按钮等优化项还没有具体方案，清单见 [99 §1](99-IN-PROGRESS.md)。

## 10. 相关代码

`music_audio_handler.dart`、`audio_player_service.dart`、`player_screen.dart`、`music_stream_screen.dart`、`video_playback_service.dart`、`widgets/mini_player.dart`、`models/library_track.dart`、`models/webdav_stream.dart`、`packages/audio_service/`。
