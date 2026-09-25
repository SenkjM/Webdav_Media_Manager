# 09 · 杂项：代码地图、构建发布、约定与陷阱

> 编号 09 · 总索引：[00-INDEX.md](00-INDEX.md)

## 1. 代码地图（改什么找谁）

分层（按目录）：

| 层 | 路径 | 职责 |
|----|------|------|
| Screens | `lib/screens/` | 页面：音乐库 / 网络库 / 播放器 / 视频 / 下载 / 设置 / 壳 |
| Widgets | `lib/widgets/` | 迷你条、封面、状态 chip 等 |
| Providers | `lib/providers/app_state.dart` | 生命周期编排（含 `destroyMusicLibrary`） |
| Services | `lib/services/` | WebDAV、缓存、下载队列、曲库、播放、备份、同步 |
| Models | `lib/models/` | `LibraryTrack`、账号、下载任务、WebDAV 条目、各设置枚举 |
| Utils | `lib/utils/` | `music_id`、CUE 解析、容器、加密、路径 |
| Android | `android/app/.../MainActivity.kt` | `AudioServiceFragmentActivity` + MethodChannel |
| Vendor | `packages/audio_service/` | 带 Android 14+ FGS / 通道补丁的 audio_service |

| 要改的东西 | 去哪儿 |
|------------|--------|
| 播放 / 媒体会话 / CUE 裁切 / 起播 | `music_audio_handler.dart`、`audio_player_service.dart`（[05](05-AUDIO-PLAYBACK.md)） |
| 视频控件 / 手势 / 倍速 / 队列 | `video_player_screen.dart`、`video_queue_controller.dart`、`video_playback_service.dart`（[06](06-VIDEO-PLAYBACK.md)） |
| 下载队列 / 入队 / ingest / 相册目标 | `download_queue_service.dart`、`library_service.dart`、`models/download_task.dart`（[04](04-DOWNLOAD-QUEUE.md)） |
| 网络库浏览 / 多选 / 行操作 | `network_library_screen.dart`、`library_actions.dart`（[02](02-NETWORK-LIBRARY.md)） |
| 音乐库 / 销毁 / 多选删除 | `library_screen.dart`、`library_actions.dart`（[03](03-MUSIC-LIBRARY.md)） |
| 缓存路径 / 过期清理 / 已缓存判定 | `cache_service.dart`（[01](01-DATA-MODEL.md)） |
| DB schema / 曲目身份 | `library_database.dart`、`utils/track_identity.dart`（[01](01-DATA-MODEL.md)） |
| 同步 / 备份 / 云端分片 | `sync_service.dart`、`backup_service.dart`、`library_sync_store.dart`（[08](08-SYNC-AND-BACKUP.md)） |
| 通知 / 通道 / 权限 | `media_notification_channel.dart`、`notification_permission_service.dart`、`download_notification_service.dart`（[07](07-NOTIFICATIONS.md)） |
| 原生相册 / SAF / PiP / 返回键 | `MainActivity.kt`、`platform_export_service.dart`、`utils/video_pip.dart`、`utils/android_background.dart` |
| **文件后缀判定（单一真相）** | `models/file_type_config.dart`；下载队列由 `configureFileTypes` 注入，**禁止**再写硬编码后缀列表 |
| 设置项 | `settings_service.dart`、`settings_screen.dart` |

导航壳 `HomeShell`：Drawer（音乐库、歌单、网络库、下载队列、设置、关于）+ 全局迷你条（设置页隐藏）。子页用嵌套 `Navigator`，避免盖住迷你条。

## 2. 构建与发布

| 分支 | 用途 |
|------|------|
| `main` | 唯一主干；合并与推送都需用户明确允许 |
| `feature/*` | 功能分支，**基于 `main` 开**，独立工作 |

推荐流程：基于 `main` 开独立功能分支 → 成熟后（用户明确允许时）用标准 PR 合入 `main`。
`beta` 与 `dev` 已删除（本地与 `origin` 都不存在）：没有长期保存线，中途成果留在自己的功能分支上。
Pre-release 从 `main` 出，相当于给 `main` 的每个提交做一次内测快照。

CI 触发：正式版走 `.github/workflows/release-build.yml`，预发布走 `.github/workflows/pre-release-build.yml`。两份都是「检查 → 编译 → 发版」串在同一次运行里，发版直接用本次运行的产物，不再靠 `workflow_run` 接续。

| 事件 | 行为 |
|------|------|
| 任意分支 push | **不**触发构建 |
| 推 `v*` 标签（release） | 检查标签合法且严格递增 → 编译 → 建 Release |
| 手动 `workflow_dispatch`（release） | 给当前 `main` 打标签，再做同一套检查；所选引用不是 `main` 时拦下 |
| 每天定时（cron `0 16 * * *`，约北京时间 00:00）（pre-release） | 检视 `main`：相对上次 `prerelease` 有新提交才构建发布 |
| 手动 `workflow_dispatch`（pre-release） | 同上；**所选引用不是 `main` 时跳过** |

**分包与压缩存放**：三个单 ABI 包（`arm64-v8a` / `armeabi-v7a` / `x86_64`）加一个去掉 x86 的合并包；原生库压缩存放（`useLegacyPackaging = true`）。实测（v0.1.0 通用包 101.3 MiB）：`libmpv.so` 38.1 MiB、`libflutter.so` 31.8 MiB、`libapp.so` 28.4 MiB，非原生部分只有 2.7 MiB——所以分包才是主要收益。v0.2.0 起 CI 产出三个 split APK（安装与体积尚待真机核对，见 §6）。

**产物命名不要写死**：Flutter 3.47.5 在 `build/app/outputs/flutter-apk/` 下出的是 `app-<abi>-prod-release.apk`（ABI 在前），而 `build/app/outputs/apk/prod/release/` 下仍是 `app-prod-<abi>-release.apk`（flavor 在前）；两份 workflow 都在收集前 `ls` 打印目录清单。教训见 §4：本地只跑 `--no-pub lib` 会漏掉 CI 完整 `flutter analyze` 能看见的 warning（v0.2.0 因此失败过一次）。

**硬约束**：不要为了看构建结果加 `on: push`，不要擅自 `gh workflow run`；需要打 Pre-release 时先等用户确认。

本地环境与常用命令：

```bash
cd <仓库根目录>          # 不要写死目录名，路径随工作区迁移
flutter pub get
flutter analyze
flutter test
flutter run --flavor dev                    # 真机调试；会话内 r 热重载 / R 热重启
flutter build apk --release --flavor prod   # 本地 release；签名见下
```

**flavor**（`env` 一个维度，`prod` / `dev` 两个）：构建**必须显式带** `--flavor`——AGP 只要存在 product flavor 就不再生成 `assembleRelease` 这类不带 flavor 的任务；`flutter analyze` / `flutter test` 不受影响。

| flavor | applicationId | 应用名 | 用途 |
|--------|---------------|--------|------|
| `prod` | `com.senkjm.media_manager` | Webdav Media Manager | 正式包；本地 release 与 CI 都走它 |
| `dev` | `com.senkjm.media_manager.dev` | Webdav Media Manager Dev | 本地调试；`versionNameSuffix = "-dev"` |

- 两个包 applicationId 不同，能装在同一台手机上并存，数据库 / 偏好 / 安全存储目录各自独立。
- flavor 只影响 `applicationId`、`versionName` 后缀和 `android:label`（走 `${appName}` 占位符）；`namespace` 与 Dart 代码不动，`MainActivity` 不搬家。
- CI 的产物文件名随 flavor 变成 `app-prod-*.apk` / `build/app/outputs/bundle/prodRelease/app-prod-release.aab`。

- Flutter **stable**（`environment.sdk: ^3.13.4`）；本机 SDK 装在 `D:\flutter`，`android/local.properties` 里的 `flutter.sdk` 只对本机有效，换机器会重新生成。
- Android SDK + JDK 17（与 CI `setup-java` 一致）；CI 里 `flutter test` 前需 `apt install libmpv-dev mpv`（media_kit 的 Linux 后端）。
- 版本号：正式版 `VERSION_NAME` = 标签（如 `v0.1.0`）；预发布 = 上一个正式版标签 + `-` + 短 SHA。`VERSION_CODE` = 主×1e8 + 次×1e6 + 修订×1e4 + 序号（正式版序号 0，预发布 1–999），单调递增便于覆盖安装。
- 签名：CI 用固定内测 keystore（Secrets：`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`）。本地没有 `android/key.properties` 时 release 会回落到 debug 签名，仅够自测；**不要提交** `key.properties`、keystore、token、`.env`。

## 3. 编码约定

**Do**

- UI 文案中文；标识符 / 路径 / API 名英文。
- 改完跑**完整**的 `flutter analyze`（不要只跑 `--no-pub lib`：CI 跑的是全项目，测试目录里的 warning 只在完整分析里出现）与相关 `flutter test`。
- 播放只走本地文件；下载走队列服务。
- CUE 解析用 `decodeCueText`；ingest 后虚拟曲才进库。
- 根返回用 `moveTaskToBack`；真正退出才 `SystemNavigator.pop`。
- 长任务的结果用 `AppSnack.showGlobal` 汇报。
- 保持 AGPL-3.0；显著修改保留版权与许可头。

**Don't**

- 不要在播放路径上偷偷 enqueue 下载（视频侧本来就流式播放）。
- 音频流式播放只在实验开关打开时可用，且必须复用视频侧的远端流模式，不要另起播放栈，见 [05 §9](05-AUDIO-PLAYBACK.md)（优化方向 [99 §1](99-IN-PROGRESS.md)）。
- 不要把未下载的远端文件标成「排队中」。
- 不要分享 CUE 虚拟曲；不要恢复 ffmpeg CUE 导出分享。
- 不要在 `MainActivity` 里 import `AudioService` 类。
- 不要重新引入 just_audio 时代的起播静音 hack。
- 不要改 CI 触发方式、不要擅自推 `main`、不要提交任何密钥。
- 不要发明不存在的 API；以仓库源码为准。

## 4. 已知陷阱与历史回归

| 问题 | 原因 / 表现 | 正确做法 |
|------|-------------|----------|
| **UTF-8 CUE ingest 失败** | 非 UTF-8 CUE 用 `readAsString` 抛错，下载成功但库里没有虚拟曲 | 始终 `decodeCueText(bytes)`（[03 §4](03-MUSIC-LIBRARY.md)） |
| **MainActivity AudioService classpath** | 在 Kotlin 里 import `AudioService` 会拉进 `MediaBrowserServiceCompat`，release 编译失败 | 继承 `AudioServiceFragmentActivity`；诊断用 `NotificationManager` / `MediaSessionManager` |
| **切后台后通知 / 播放状态消失** | 普通 `FlutterActivity` 变体没重写 `getCachedEngineId()` / `shouldDestroyEngineWithHost()`，Activity 被回收时把共享 engine（含 `MusicAudioHandler`）一起销毁 | `MainActivity` 继承 `AudioServiceFragmentActivity` |
| **`SystemNavigator.pop` 停音乐** | 根返回 finish Activity → 拆掉 handler | 根返回 `moveTaskToBack`（[05 §3](05-AUDIO-PLAYBACK.md)） |
| **起播双击杂音 / 首曲无声** | `just_audio` 时代的问题 | 引擎已换 `media_kit`，不要再引入 mute hack（[05 §5](05-AUDIO-PLAYBACK.md)） |
| **idle 拆掉媒体通知** | 播放状态误报 idle | 只在 `_index < 0` 时广播 idle（[05 §6](05-AUDIO-PLAYBACK.md)） |
| **未下载显示「排队中」** | 远程浏览误用 queued 状态 | `TrackUiState.remote` → 不显示 chip（[02 §1](02-NETWORK-LIBRARY.md)） |
| **播放器顺手下载** | 在 play 路径 enqueue | 拒绝并提示先下载（[05 §1](05-AUDIO-PLAYBACK.md)） |
| **清缓存误删曲库** | 把 tracks 和文件绑死 | 标签在 DB，缓存只是 `music_cache/` 下的文件，销毁才是 wipe（[01 §3](01-DATA-MODEL.md)） |
| **清缓存后整库挂「错误」标签** | `invalidateMissingCompleted` 曾把 stale 任务标成 `cancelled`，而 `uiStateFor` 把 cancelled 当 error | 删任务行、跳过相册 / 下载目录任务（[04 §5](04-DOWNLOAD-QUEUE.md)） |
| **相册任务被判「文件不存在」** | 它们的 `localPath` 是 `content://` URI，`File(...).existsSync()` 永远为假 | 判定前先看 `isPublic`（[04 §5](04-DOWNLOAD-QUEUE.md)） |
| **音乐后缀判定两份实现** | 队列用硬编码后缀表、网络库用用户配置，`.m4a`/`.aac` 下载后在 ingest 抛错 | 后缀真相只有 `file_type_config.dart`；队列由 `configureFileTypes` 注入 |
| **备份恢复后假「已缓存」** | 旧版恢复了 annex 路径但文件没打包 | v9 起已缓存=推导路径文件在，天然不可能假（[08 §5](08-SYNC-AND-BACKUP.md)） |
| **schema 升级丢库** | `onUpgrade` 直接 DROP 重建 | bump version 前告知用户；没有渐进 migration（[01 §2](01-DATA-MODEL.md)） |
| **OEM 无媒体通知** | 通道重要性过低 / 未声明 typed FGS | 保留 vendor 补丁与 v4 通道；真机测 ColorOS / 一加（[05 §7](05-AUDIO-PLAYBACK.md)） |
| **通道状态查不到 / 与系统不一致** | 通道原先只由首次播放时的原生代码创建 | 通道唯一定义在 `media_notification_channel.dart`，启动时创建，参数两侧必须一致（[07 §2](07-NOTIFICATIONS.md)） |
| **API 33+ 自定义动作图标崩溃** | `audio_service` 自带 `drawable/audio_service_*` 在 release 里合并不可靠 | 用 app 自带 `drawable/ic_media_*` + `res/raw/keep.xml`（[07 §2](07-NOTIFICATIONS.md)） |
| **工具栏整条不显示 / 渲染时炸** | 外壳是横向滚动层，宽度约束无限：`minWidth: double.infinity` 不可满足；`Expanded` / `Flexible` / `Spacer` 没有剩余空间可分 | 铺满用具体宽度（`constraints.maxWidth`）；按钮里不用 `Expanded`，文字自然宽度。**analyze 与测试都发现不了**（[02 §5](02-NETWORK-LIBRARY.md)） |
| **两库工具栏各写一套** | 网络库与音乐库曾各写一遍，于是各修一次、各炸一次 | 共用 `lib/widgets/selection_toolbar.dart`；子项只放按钮，业务逻辑留各库 |
| **多选全选点了没反应** | `toggleSelectAll` 没把 `total` 设成传入的键数（音乐库不走 `sync`） | `total` 由传入列表定；计数对着**当前列表**比（[02 §5](02-NETWORK-LIBRARY.md)） |
| **多选里按返回回到上一页 / 主页** | 子页只用 `ModalRoute.isFirst` 判断（嵌套 Navigator 上恒为真，没用） | 子页本地 `PopScope(canPop: !_selecting)` 接管（[02 §5](02-NETWORK-LIBRARY.md)） |
| **缓存按钮变灰** | 按「只选了一个文件夹」特判，多选文件夹就废 | 两条线都不挑个数；该灰只可能是 `items.isEmpty`（[02 §5](02-NETWORK-LIBRARY.md)） |
| **选中文件夹与其中的文件时重复排队 / 炸** | 界面自己分「文件夹路」与「文件路」，同一路径从两个入口各排一次 | 扫描与去重都在后端：一个 `enqueueSelection(folderPaths, files, target)`（[04](04-DOWNLOAD-QUEUE.md)） |
| **先点缓存再点下载，第二条被悄悄吃掉** | 去重键只有 (来源, 路径) | 键是 **(来源, 路径, 目标)**（[04](04-DOWNLOAD-QUEUE.md)） |
| **下载跳过音频 / 视频 / CUE** | 下载路径曾自作主张按 `FileTypeConfig` 过滤 | 下载**不挑类型**，一个都不跳；只有缓存那条才只收音频（[02 §5](02-NETWORK-LIBRARY.md)） |
| **下载图标随对象变** | 行菜单里文件夹项用过 `folder_zip_outlined` | 下载恒为 `Icons.download`：文件夹、文件、工具栏一致（[02 §5](02-NETWORK-LIBRARY.md)） |
| **目录选择器「上一级」一步跳回根目录** | `_stack` 把整条 `initialPath` 当成一层压入 | `remoteAncestors` 逐层压栈；上一级与返回键**各退一层**，到根再按才关闭（`lib/utils/remote_path.dart`） |
| **下拉菜单顶出屏幕 / 往上弹** | 服务器多起来时菜单高度不受限 | `menuMaxHeight` 半屏 + `isExpanded: true`（[02 §4](02-NETWORK-LIBRARY.md)） |
| **本地全绿、CI 的 Analyze 失败** | 本地只跑 `flutter analyze --no-pub lib`，CI 跑完整 `flutter analyze`——测试目录里的 `unused_import` 之类 warning 只有完整分析才报 | 提交前跑**完整** `flutter analyze`（v0.2.0 因此失败过一次：`test/file_action_model_test.dart` 的未用 import） |

本轮相关提交：`fa0c92f`（缓存 / 下载分成两条线）、`c366b2a`（扫描与去重收进 `enqueueSelection`）、`a408c5b`（音乐库工具栏 `Expanded`）、`65d7a55`（选择器逐级返回）、`b9ecd65`（文件夹下载图标）、`0ec8349`（下拉框限高半屏）。

更早的相关提交：`c235c92`（CUE ingest）、`1649677`（music_id v5 / 备份）、`0ed9591`（mute + remote chip）、`922d3c4`（unmute before play + ColorOS BUFFERING / v4）、`9c9d5c5`（返回键）、`251e46a`（MainActivity）、`ebe85b7`（禁用 push 触发 CI）。

## 5. 测试入口（改核心逻辑时优先跑）

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
flutter test test/music_extension_policy_test.dart
flutter test test/download_queue_ordering_test.dart
flutter test test/remote_path_test.dart       # 目录选择器逐级返回
flutter test test/remote_path_test.dart      # 目录选择器逐级返回
flutter test test/sync_interval_test.dart
flutter test                   # 或全量
```

## 6. 已知未修 / 待定

| 项 | 状态 |
|----|------|
| 启动黑屏约 1.4 s（`Skipped 85 frames`） | 未修；`main()` 里串行 init 导致，可异步化 |
| 后台下载 `fail host lookup` | 未修，优先级最高，见 [04 §7](04-DOWNLOAD-QUEUE.md) |
| 分包 APK 的安装与体积 | 分包 CI 已出包，**真机未核**（装得上 / 体积收益兑现），见 §2 |
| 缓存 / 下载多选混选 | 同选文件夹与其中的文件、窄屏工具栏、单 / 多 / 混选，真机未核 |
| 网络库「文件动作模型」T1–T5 | **已实现**，见 [02](02-NETWORK-LIBRARY.md)；部分服务端目录 `Destination` 待真机核（见 [02 §8](02-NETWORK-LIBRARY.md)） |
| 进度条没有缓冲进度第二层 | 未做；libmpv 有 `player.stream.buffer` 可用 |
| 空闲若干秒自动隐藏控件 | 未做，需先确认是否要 |
| 左右手势区首次使用引导 | 未做，需先确认是否要 |
| 音频串流（复用视频侧流式栈） | 已接入（实验开关，默认关闭）；连播 / 模式记忆等清单见 [05 §9](05-AUDIO-PLAYBACK.md)，优化方向见 [99 §1](99-IN-PROGRESS.md) |
