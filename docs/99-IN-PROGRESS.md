# 99 · 开发中文档

只记录**正在开发**的功能的原始语义：需求原话、取舍、临时决定、还没定型的实现。
用法与收口规则见 [00-INDEX.md](00-INDEX.md) 的「完整文档与开发中文档」。

- 开发新功能前**先读本文件**，再读每一条链接到的完整文档。
- 下面**按功能 / 项目分节**，不按「已完成 / 待验收 / 取舍」这类状态分类；每条自己的状态写在它的开头。
- 自动化的做完只是门槛：`flutter analyze` 干净 + `flutter test` 全过，不代表真机行为对。所以代码上了 `main`、真机还没碰过的，仍留在这里。
- 开发完成后：删掉这里的条目，把语义按完整文档的写法补进对应功能块，并去掉占位。

## 1. 音乐流式播放（初步实现，优化待定）

**状态**：已初步实现并推 `main`（实验开关控制，默认关闭）。语义写在 [05 §9](05-AUDIO-PLAYBACK.md) 与 [06](06-VIDEO-PLAYBACK.md) 的对比表里。**真机没有验收，优化方案也还没有**。

**待真机验收**：后台切换、锁屏控制、耳机按键、断网、切回本地播放。

**已知粗糙处（优化的候选，都还没有具体方案）**：

- 离开音乐流式页会 `VideoPlaybackService.stop()`，而它内部是 `exitVideoMode()`——语义是「**恢复**本地音乐队列」。所以停下流式歌时通知栏会跳回之前暂停的本地歌。要更干净，得让远端流用途参与 `exitVideoMode` 的分支判断。
- **没有屏幕常亮**：项目里没有 wakelock 依赖；视频页的常亮来自 `media_kit_video` 的 `Video` 组件，音乐页刻意不建它。
- **封面与时长不取**（用户此前允许先不做）：流式拿不到本地文件，`audio_metadata_reader` 无从解析。要取得用 Range 读头部几 MB 再喂现有解码器，而 FLAC 的 `STREAMINFO`、MP4 的 `moov` 还可能落在文件尾部。
- **没有「停止流式播放」的显式按钮**：退出页面才会结束。
- 音乐流式的**切歌语义与本地不同**：本地有 CUE 裁切 / 队列语义，流式没有；从流式切回本地必须以「停止 + 清会话」结束，而不是暂停。
- **后缀改过的音频会走错页**：把 `.m4a` 改成 `.mp4` 的音频，进的是视频播放页而不是音乐流式页——路由按后缀判定，不看实际内容（**用户已报，暂不处理**）。
- 流式**不得**顺手入队下载（[09 §4](09-MISC.md) 陷阱表：不要在播放路径上偷偷入队下载）。

## 2. 网络库交互模型（已实现，待真机验收）

**状态**：全选按计数器判定、全选按钮只取消选择不退出多选、三个入口共用 `judgeAction`、复制 / 移动走原生 `COPY` / `MOVE` 并自动加 ` (n)`。语义已进 [02](02-NETWORK-LIBRARY.md)。

**待真机验收**：部分服务端对目录目标的 `Destination`（加不加结尾 `/`）处理不一致，要在真实网盘上各试一次。

**已知未做**：

- 移动 / 重命名远端文件后，本机音乐库里绑定旧路径的曲目**不会跟随**（需要一次「路径重写」才能做对）。
- 复制 / 移动**没有进度与取消**：`webdav_client` 的 `copy` / `rename` 是单次请求，大文件只能等。

## 3. 音乐库的两个不可逆动作（已实现，待真机验收）

**状态**：从云端覆写音乐库 / 销毁音乐库，交互约定已进 [08](08-SYNC-AND-BACKUP.md)。**真机待验**：两个按钮的按压与确认框排版、进度条推进、终止 / 返回键取消、多选销毁。

**已定型的取舍**（还没按完整文档的写法搬进 [08](08-SYNC-AND-BACKUP.md)）：

- 覆写只清**索引**（`LibraryDatabase.clearLibraryIndex()`），不清 cache annex：连 annex 一起清的话，磁盘上已有的音频会被当成没下过，白白多出一次全量下载。
- 销毁走**逐条**、不走 `clearAllLibraryData()` 整表清空：整表清空会连 `deleted_tracks`（墓碑）和 `sync_state`（游标）一起抹掉，云端永远收不到删除记录，下次同步还会把整库拉回来。顺序固定为**先墓碑、后删行**（`LibraryService.destroyTracks`），中途被杀掉留下的中间态是安全的。
- 让曲目从本地列表消失的是「删行 + `_tracks.removeWhere` + `notifyListeners()`」，墓碑只影响同步的拉取判定。所以「只立墓碑」那版在本地毫无可见变化，用户要的是逐条删除。
- 逐条会删掉本地已下载的音频，**不可逆**；云端那行同时被墓碑标记，重建云端库之后两边都没有了。
- **「原子」指的是逻辑边界，不是数据库事务**：`destroyTrack` 内部没有 `db.transaction()`，一首歌要跨 `deleted_tracks` / 封面文件 / `tracks` / 内存四处写。取消只能在两首之间生效。
- 进度条按「已处理 / 总数」推进，不是「已销毁 / 总数」：CUE 分片会被同一张专辑的第一片带走，后面的兄弟曲目直接跳过（`destroyLibraryTrack` 返回 false），所以进度会走满而销毁数可能小于总数。
- 进度框是**模态**的，销毁不会在界面消失后继续跑——这正是「删除界面不要做成异步的」。每首都会 `notifyListeners()` 一次，换来的是一首歌一个完整动作、取消点永远落在歌与歌之间。
- 销毁结束把定时同步置为 `off` 是刻意的：推不推、什么时候推，交回用户手动决定。
- 「其他行为干扰」的实现是**静默窗口**（`_quietLibraryWrites`）：暂停 20 s 推送防抖与定时扫描，并取消已排队的防抖。没有做互斥锁——已经在飞的同步不会被中断，只是不再有新的自动触发。
- `LibraryService.destroyTracks(Iterable)` 保留为「没有进度界面时的循环封装」，目前没有调用方。

## 4. 构建与发布（已实现，真机与体积未核）

**安装包分包与压缩存放**：三个单 ABI 包（`arm64-v8a` / `armeabi-v7a` / `x86_64`）加一个去掉 x86 的合并包；原生库压缩存放（`useLegacyPackaging = true`）。v0.2.0 的 CI 已成功产出三个 split APK，**APK 的安装与体积没在真机上核过**。

- 实测（v0.1.0 通用包 101.3 MiB）：`libmpv.so` 38.1 MiB、`libflutter.so` 31.8 MiB、`libapp.so` 28.4 MiB，非原生部分只有 2.7 MiB——所以分包才是主要收益。
- 产物命名由构建工具决定，**不要写死**：Flutter 3.47.5 在 `build/app/outputs/flutter-apk/` 下出的是 `app-<abi>-prod-release.apk`（ABI 在前），而 `build/app/outputs/apk/prod/release/` 下仍是 `app-prod-<abi>-release.apk`（flavor 在前）。两份 workflow 已改成新序，并在收集前 `ls` 打印目录清单。
- 教训见 [09 §4](09-MISC.md)：本地只跑 `--no-pub lib` 会漏掉 CI 完整 `flutter analyze` 能看见的 warning（v0.2.0 因此失败过一次）。

**flavor 与本地 dev 环境**：`env` 维度两个 flavor，`dev` 带 `applicationIdSuffix = ".dev"` 与 `appName = Webdav Media Manager Dev`，可与正式包并存。`flutter run --flavor dev` 已在 PJZ110 上跑通；CI 侧随 v0.2.0 一起验证。存在 flavor 之后**所有构建都必须显式带 `--flavor`**。

- 刻意**不动 `namespace`**：`MainActivity.kt` 包路径、`com.senkjm.media_manager/app`、通知 channel id 都是应用内部标识，与 applicationId 无关。

**缓存音乐与下载两条线**：界面只有一个流程，扫描与去重在 `enqueueSelection`。**真机待验**：同时选中文件夹与其中的文件（缓存、下载各点一次）、窄屏下的工具栏、单文件夹 / 多文件夹 / 混选。

## 5. 主题配色（已分析，未开工）

相关完整文档：[09 §编码约定](09-MISC.md)、[05](05-AUDIO-PLAYBACK.md)、[06](06-VIDEO-PLAYBACK.md)、[07](07-NOTIFICATIONS.md)。待发布与拆分见 [10 T1 / T2](10-SIDE-QUESTS.md)。

### 5.1 现状（可直接确认）

- `lib/theme/app_theme.dart` 里 `AppTheme.light` 与 `AppTheme.dark` **两套都已写完**，各约 240 行，覆盖 AppBar / Drawer / Card / ListTile / TabBar / Slider / Chip / Dialog / SnackBar / SegmentedButton 等。
- `lib/main.dart` 已传 `theme:` 与 `darkTheme:`，但 `themeMode: ThemeMode.light` 是**写死**的——`AppTheme.dark` 现在是死代码。
- `AppColors`（同文件）是 `static const Color`，全库 **24 个文件、325 处**直接引用。
- 另有约 **417 处**裸颜色（`Colors.xxx` / `Color(0x…)`），分布在 25 个文件，其中一部分是**有意**的（封面占位、状态色、播放器黑底）。

### 5.2 为什么不能只把 `themeMode` 打开

改成 `ThemeMode.dark` 会立刻得到「深色主题 + 一堆亮色残留」：`AppColors.xxx` 是编译期常量，不跟主题走，于是文字、分隔线、卡片底色仍是亮色值。这是这个功能真正的工作量所在。

### 5.3 拆分（两阶段，各自独立可交付）

**阶段一 · 静态引用转上下文取色**

- `AppColors` 改成「静态常量（默认亮色，保持兼容）+ 上下文取色入口（`AppColors.of(context)` 或 `BuildContext` 扩展）」。
- 逐文件把 `AppColors.xxx` 换成上下文取色，**24 个文件、325 处**。
- 只认「该值是否随主题变化」：`nearBlack` / `onDark` 这类语义在暗色下会**反转**（播放器黑底在暗色下应是深背景而不是纯黑），要单独过一遍，不能机械替换。
- 完成后亮色下**行为完全不变**，暗色下除裸颜色外应当正常。默认仍是 `ThemeMode.light`，所以这一步落地即安全。

**阶段二 · 模式开关与自定义取色**

- 三态开关：跟随系统 / 亮 / 暗；持久化沿用 `SettingsService` 既有模式。
- 自定义配色：边界**未定**（是只让用户改主色 accent，还是整套色板）。只改主色工作量小得多，但要让对比色（`onAccent`）跟着算出来。**需要先确认**。
- 裸颜色审计与收敛，按类判断：哪些该跟主题、哪些本来就该固定。

### 5.4 验收与回归点

- 纯黑播放器页、下载进度 / 状态色、封面占位在两种模式下都要可读；`docs/05`、`06`、`07` 的界面描述要跟着补。
- 阶段一落地后跑 `flutter analyze` 与 `flutter test`；阶段二补设置项相关的测试。

## 6. 多语言（已分析，未决定，未开工）

用户问「多语言怎么处理」，只做了查证与拆分：**没有动代码**。相关完整文档：[10 T4 / T5](10-SIDE-QUESTS.md)。

### 6.1 实测现状

| 项 | 值 |
|---|---|
| 含中文的字符串字面量 | 944 条（约 1.1 万汉字） |
| 分布在 | 61 / 85 个 Dart 文件 |
| `flutter_localizations` | 未引入 |
| `intl` | pubspec 已声明 `^0.20.3`，代码中未直接使用 |
| `l10n.yaml` / `.arb` | 都不存在 |
| `android/app/src/main/res/values*/strings.xml` | 不存在（应用名走 gradle `manifestPlaceholders["appName"]`） |
| 文案最集中的文件 | `sync_screen` 112、`settings_screen` 84、`network_library_screen` 75、`video_player_screen` 64 |

### 6.2 三个结构性难点（必须在批量替换**之前**处理）

1. **枚举的显示名**：`models/` 下 38 个文件有中文，多为 `XxxLabel` / `label` 扩展（`CacheRetention`、`DownloadTarget`、`FileAction`、`SyncInterval`、`VideoGestureAction` …）。model 层拿不到 `BuildContext`。推荐给这些 label 扩一个 `AppLocalizations` 参数，而不是把映射表搬到 UI 层（后者要动几十个调用点）。
2. **被持久化的字符串值**：`library_service.dart:503` 用 `'未分类'` 当 key 并参与排序比较；`playlist.dart:75` 落库默认值 `'未命名'`；`accounts_service.dart:127` 默认服务器名 `'默认服务器'`。**改字符串之前必须先脱钩**，否则旧数据对不上。真机数据库里是否已存在这些值，查不到。
3. **后台服务的文案**：`services/` 下 18+ 个文件、38 组含中文，例如 `download_queue_service` 的 `_lastError`、`audio_player_service` 的 `'本地无缓存，请先下载'`、`backup_service` 的异常文案。service 层没有 `BuildContext`，正确做法是返回错误码 / 结构化结果、由 UI 层映射文案——这是重构，不是替换。

### 6.3 分阶段（顺序不能调）

| 阶段 | 内容 | 备注 |
|---|---|---|
| 0 | `flutter_localizations` + `l10n.yaml` + ARB + `MaterialApp` 接线 | 见 [10 T4](10-SIDE-QUESTS.md)；key 命名规则必须在这一步定死 |
| 1 | 6.2 的三类结构性问题 | 做不完就替换文案 = 白干 |
| 2 | 按模块替换 944 条文案 | 线性体力活，一批一个 commit |
| 3 | 平台侧资源（应用名、通知渠道名） | 见 [10 T5](10-SIDE-QUESTS.md) |
| 4 | 语言切换（跟随系统 / 应用内切换 + 持久化） | 独立功能，可选 |

### 6.4 需要用户决定的三件事

1. 目标语言（中 + 英？）；2. 范围（全量还是先跑通一两个模块）；3. 要不要应用内语言切换。**未决定前不开工。**
