# 07 · 通知与应用内消息

> 编号 07 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/services/media_notification_channel.dart`、`notification_permission_service.dart`、`download_notification_service.dart`、`lib/utils/app_snack.dart`

## 1. 三类系统通知

| 通知 | 内容 | 通道 |
|------|------|------|
| 媒体通知 | 音乐或视频的标题 / 作者、播放暂停、上一首 / 下一首；视频播放时是**视频**通知 | `com.senkjm.media_manager.audio.v4` |
| 下载进度（两条） | 第一条「正在下载（第 k / N 个）」= 当前文件百分比 + 文件名；第二条「下载队列（N 个任务）」= 整批总量 + 「已完成 x / N」 | `…downloads.v1` |
| 下载完成 | 「全部下载完成 · 成功：x 个 失败：y 个」；有失败时标题变「下载结束（有失败）」 | `…downloads.done.v1` |

下载通知的行为约定：

- 两条进度条都**真的在走**——给上限的同时必须给当前值，否则永远是 0%。
- `N` 只统计**本轮**入队的任务；队列里历史的「已完成」条目不计入。
- 一次下多个 / 整个文件夹，仍只有这两条，不刷屏；新一批开始时计数从 0 重算。
- 全部下完 → 两条进度通知消失，弹出完成通知；完成通知**不会自动消失**，点掉或被下一批替换。
- 通知静音，不响铃不震动。
- 设置 → 提示与通知里关掉「下载队列系统通知」→ 立刻清掉这三条，之后不再出现。

## 2. 通道与权限

- **通道的唯一定义**在 `media_notification_channel.dart`，由 `notification_permission_service.dart` 经 `flutter_local_notifications` 在启动时创建；原生侧发现通道已存在即复用。因此两侧参数必须完全一致：IMPORTANCE_DEFAULT、静音、不震动、无角标。`media_notification_channel_test.dart` 守着这个常量。
- 历史坑：通道原先只由首次播放时的原生 `createChannel()` 创建，设置页在播放前读到「未创建」，于是状态显示与系统不一致。
- Android 13+ 需要 `POST_NOTIFICATIONS` 运行时权限；设置页提供「测试媒体通知」与中文 OEM 提示（耗电不限制、通知含锁屏、允许关联启动）。
- 媒体控制按钮一律用 app 自带的 `drawable/ic_media_*` 图标：`audio_service` 自带的 `drawable/audio_service_*` 在本 app 的 release 构建里合并不可靠，API 33+ 会抛 `You must specify an icon resource id to build a CustomAction`。

## 3. 应用内消息（AppSnack）

- 单槽**顶部横幅**：新消息覆盖旧消息、同样的消息去重、点消息本身或「知道了」立即消失（横幅不支持滑动关闭）。
- 横幅挂在根 Overlay 的顶部安全区下方：底部 SnackBar 会被 AlertDialog / 键盘 / 底部导航挡住（对话框开着时往往只露出一条边），置顶后一定看得见。
- 设置 → 提示与通知 → 「提示显示时长」有 5 档：很短 / 默认 / 较长 / 点击才消失 / 关闭。选「关闭」后任何应用内消息都不再出现（下载失败的红条也不出现）。
- **两个入口，用法有硬性区别**：
  - `AppSnack.show(context, …)` 跟着页面走，用于当前页面内的即时反馈；
  - `AppSnack.showGlobal(…)` 走 `MaterialApp.scaffoldMessengerKey` 的全局槽位。
- **长任务（重建 / 同步 / 备份）与下载完成必须用全局入口**：这些操作可能在用户退出设置之后才结束，用页面 context、或在回调里用 `if (!mounted) return` 提前返回，会把结果永远吞掉。同理，不要在异步回调里用「页面还活着吗」来决定要不要提示。

## 4. 相关代码

`media_notification_channel.dart`（通道唯一定义）、`notification_permission_service.dart`（权限 / 通道状态 / 测试通知）、`download_notification_service.dart`（两级进度 + 完成）、`music_audio_handler.dart`（媒体通知内容）、`app_snack.dart`（应用内消息）、`android/.../MainActivity.kt`（通知诊断通道）。
