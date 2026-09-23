# 05 · 音频播放

> 编号 05 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/services/music_audio_handler.dart`、`audio_player_service.dart`、`lib/screens/player_screen.dart`

## 1. 铁律：音频只播本地文件

- `AudioPlayerService.playTrack` 解析本地路径失败就报「本地无缓存，请先下载」，**不会**在播放路径上入队下载。
- 判定一律用 `File.exists` / `existsSync`（见 [01 §3](01-DATA-MODEL.md)），不要信任「曾经 completed」的队列状态。
- 音频没有流式播放。想让音频串流是一个**未立项**的方向（[02 §5](02-NETWORK-LIBRARY.md) 的 T6）。

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

## 9. 相关代码

`music_audio_handler.dart`、`audio_player_service.dart`、`player_screen.dart`、`widgets/mini_player.dart`、`models/library_track.dart`、`packages/audio_service/`。
