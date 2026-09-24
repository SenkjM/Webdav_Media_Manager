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

### 1.1 流式页的控制与设置（已实现，待真机验收）

**状态**：播放模式轮换、播放列表面板（含搜索）、音频/视频各自的「搜索子目录」开关、新的「音频流式设置」子页都已落地并推 `main`。语义写进 [05 §9](05-AUDIO-PLAYBACK.md) 与 [06 §3](06-VIDEO-PLAYBACK.md)。

**真机待验**：

- 一首放完真的接下一首（此前从来没生效：连播的监听根本没写，见下）；顺序到队尾停住、列表循环回第一首、单曲循环从头再来，三种都对。
- 播放模式按一下换一个，图标与提示跟着变，**退出再进页面还是刚才那个模式**。
- 播放列表：面板里能跳转；搜索框中文与英文都能搜；开了子目录后同名曲靠行内的相对目录区分。
- 「设置 → 音频流式 → 搜索子目录」关掉后，列表只剩当前这一层；「视频播放设置 → 搜索子目录」同理。两处互不影响。
- 流式开关从「文件后缀管理」搬走后，旧用户的状态要能接上（旧键 `experimental_music_streaming` 只读一次做迁移）。

**本轮查证到、值得记住的三件事**：

- 「自动连播」此前是个**空的开关**：`VideoQueueController.autoAdvance` 只在两处被赋值，全库没有读取方；真正的推进是视频页自己监听 `player.stream.completed`，而音乐页**没有**这路订阅。文档里那句「放完自动下一首」是照视频抄过来的。
- 流式页与视频页**共用同一个播放器实例**（`music_audio_handler.videoPlayer`）。所以播放模式必须两边都设：音乐页设了 `loop` / `single` 之后，视频页打开时要重置成 `none`，否则视频也跟着循环。
- 到队尾**不能**靠播放器的 `PlaylistMode` 兜底：流式页在播放器眼里始终只有一条媒体（切歌是 `_open` 重新开流），`loop` 只会退化成重播同一首。

**还没做的**：控制条挪走快退 / 快进后，这两个动作改到进度条下方的一行小按钮（保留了 15 秒步长）；没有做手势。

### 1.2 流式传输音乐界面的 UI 优化（未开工，方向已定）

**用户原话**：「新加一条流式传输音乐界面的 UI 优化，现在太丑了。」

**为什么丑（可直接确认，不是主观印象）**：

- **这一页现在根本没有深色底**：`AppColors.nearBlack` 等于 `background`（`0xFFFAFAFA`），`onDark` 等于 `primaryText`（墨黑）。所以「近黑底 + 亮点文字」写出来的其实是**浅灰底 + 深字**。视频页看着是黑的，靠的是 `media_kit_video` 自带的 `Video` 组件，与主题无关；音乐页刻意不建它，于是原形毕露。这是 [§5](99-IN-PROGRESS.md) 阶段一欠的账，不是这一页自己写错。
- 封面 200×200 **写死**，小屏顶边、大屏显小；72 px 纯灰图标没有任何层次。
- 标题 18 px 与副标题「流式传输 · 未缓存」12 px 挤在一起，中间没有歌手 / 专辑层。
- 进度条下方那行时间：左侧时间与右侧「已缓冲」字号相同、没有主次；进度条底轨是默认灰，拖动时的高亮也没接强调色。
- 控制条 5 个按钮 `spaceBetween` 等距，**大播放键与小图标混排**，节奏乱。
- 模式按钮是自绘 `Stack` + `Positioned` 角标「1」，不够精致；切模式用 `SnackBar`，在居中常驻布局里从底部弹出来很突兀。
- 整页 `Center` + `SingleChildScrollView`，短屏上方留白过多。

**用户已拍板的三件事**：

1. **底色**：走 [§5](99-IN-PROGRESS.md) 阶段一（`AppColors` 上下文取色），**不**在这一页单独铺深色底。
2. **封面**：这轮**不抓远端图**，只把占位做得像样（尺寸自适应、圆角、阴影、强调色渐变图标）。内嵌封面是独立的一块（Range 读头部 + 解析 ID3 / FLAC 图块），不在本次范围。
3. **范围**：视觉与布局都改，**元素一个不增不减**——大封面 + 标题层 + 紧致进度 + 居中控制条这套常规播放器骨架。

**顺序**：阶段一必须先做。这一页的底色问题就是阶段一的产物，先重排布局等于照着浅色底调一遍，取色做完还得再调一遍。

**阶段一的实测规模**（本轮查证，比 §5.1 记的数字更准）：

| 项 | 值 |
|---|---|
| 带 `AppColors.` 的文件 | **26** 个 |
| 引用总数 | **329** 处 |
| 其中 `app_theme.dart` | 77 处（定义本身，不替换） |
| 真正要动的 | **25 个文件、约 252 处** |
| 最集中的文件 | `downloads_screen` 29、`sync_screen` 27、`library_screen` 25、`video_player_screen` 20、`network_library_screen` 19、`player_screen` 17、`music_stream_screen` 16 |

**阶段一最大的隐藏成本是 `const`**：大量引用长在 `const TextStyle` / `const BoxDecoration` / `const Icon(…)` 里（`app_theme.dart` 自己就有 `const BorderSide(color: AppColors.divider)` 这类）。上下文取色是运行时值，这些 `const` 全部要拆掉。所以这不是「纯替换」，而是「替换 + 拆 const」，逐文件做、逐个跑 analyze。

**一个必须先说清的前提**：阶段一做完，`main.dart` 里 `themeMode: ThemeMode.light` 仍然写死（`main.dart:87`），所以**这一页不会立刻变深**。要让暗色真正生效，还得把阶段二里的三态开关（跟随系统 / 亮 / 暗 + 持久化）补上。也就是说「流式页变好看」依赖的是**阶段一 + 三态开关**两件事，而阶段二里的「自定义配色」边界在 §5.3 里还标着**未定**。

**待用户决定**：

- 阶段一与三态开关是否放在同一条分支里做完再验（否则阶段一做完了看不到任何变化）。
- 自定义配色（只改主色 vs 整套色板）是否并入这次，还是等前两件做完再单独议。

**布局重排的具体方向**（阶段一 + 三态开关落地后执行）：

| 部位 | 现在 | 改成 |
|------|------|------|
| 封面 | 写死 200×200，灰图标 | 自适应 `min(宽 - 64, 高 × 0.35)`，夹在 160–280；圆角 + 阴影；占位图标用强调色渐变 |
| 标题区 | 18 px + 12 px 两行 | 主标题 20 / w600、次要行 13 / secondaryText，上下间隔重排 |
| 进度与时间 | 一行混排、无主次 | 时间左右分置、进度条上下留白加大、拖动时用强调色 |
| 控制条 | `spaceBetween`、大小混排 | `spaceEvenly`、播放键放大成强调色实心圆、次要按钮统一灰色小图标 |
| 模式按钮 | 自绘角标 | 收进统一次要按钮，激活状态用强调色表示，不再自绘角标 |
| 切模式反馈 | 底部 SnackBar | 页内轻提示（图标附近短文案），不弹 SnackBar |
| 页面骨架 | `Center` + 滚动 | 去掉多余留白，短屏也不顶边 |

**验收**：亮色主题下逐元素比对（**阶段一不能改变亮色观感**，这是它的安全底线）；暗色 + 重排之后，这一页应当是「深底 + 干净封面 + 居中控制条」，不再有浅灰残留。
### 1.3 流式音乐播放的预载（未开工，方案待定）

**用户原话**：「流式音乐播放的预载功能，自动加载向前 x 首向后 y 首，可在配置页面配置。」

**放哪**：参数进「设置 → 音频流式」（`audio_stream_settings_screen.dart`，现在只有「流式传输音乐」和「搜索子目录」两项）。

**能不能做 —— 关键卡点：流式页与视频页共用同一个 `Player` 实例**

`music_audio_handler.videoPlayer` 是单例（`music_audio_handler.dart:173`），视频页只是借它。media_kit 的预载手段是把媒体挂进 `Player` 的播放列表再用 `next()` / `previous()` 切换，而**列表是播放器的全局状态**：流式页预载了「当前 + 后 2 首」之后切到视频页，视频的 `player.open(Media)` 会把整份列表换掉。反之亦然。

**另一处硬对抗**：现在切歌是 `_open()` → `player.open(Media(...))`。`open` **清空播放列表**。也就是说只要还走 `_open`，预载进去的条目下一次翻页就没了——预载等于白做。

**三条路线**：

| 路线 | 做法 | 代价 |
|------|------|------|
| **A. 播放器原生列表**（唯一有真实预载效果的） | 流式页改成「播放器列表 = 向前 x 首 + 当前 + 向后 y 首」，切歌走 `next()` / `previous()` / `jump()`；队列变化时增量 `add` / `remove` | 要改切歌模型；要处理「视频页独占播放器时清空列表」；且**必须同时处理 `_open` 清空列表的问题** |
| **B. HTTP 层预取** | 自己按 Range 预读下一首的起始分片 | 需要确认网盘是否可靠支持 Range；要做本地流缓存与失效；工作量最大，且不一定减少起播延迟 |
| **C. 混合** | 列表预载 + 自己维护流缓存 | 两条都要做，收益是否叠加未验证 |

**方案 A 的既有资产**：media_kit 的 `open` / `add` / `next` / `previous` / `jump` / `move` 都在（`media_kit-1.2.6` 的 `player.dart` 第 160–227 行），`open` 接受单个 `Media` **或 `List<Media>`**。所以不需要新依赖。

**待用户决定**：

1. 走哪条路线。**倾向上不建议 B**：它不一定减少起播延迟，却要动网络层；要动先做一次 Range 支持与真实延迟的实测。
2. 预载的语义：是「让下一首**起播更快**」还是「尽量**不要中途卡**」。前者是列表级的预开流，后者才是缓冲级的（后者用 Android 上 media_kit 的 `bufferSize` 参数控制，它是 ExoPlayer 的缓冲策略，能否控制 HTTP 源的预取深度**未验证**）。
3. `x` / `y` 的默认值与范围（默认向后 1、向前 1？上限按队列长度夹住，不循环）。

**必须一起定下的边界**（无论选哪条路线）：

- 预载**不得**触发任何下载入队——[09 §4](09-MISC.md) 的陷阱表写着「不要在播放路径上偷偷入队下载」。
- 预载失败不能影响当前这一首的播放（静默降级）。
- 队列短于 `x + y` 时按实际可用数量处理，到队首 / 队尾不绕圈。

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
- **CUE 组走「整组销毁、逐片落地」**：点中一片 = 销毁整张专辑，但删除与墓碑都按片做——每片各删自己的 `cue_slices` 行、各留各的墓碑（`library_service.destroyTrack`），`cue_albums` 行只在最后一片走完时删（`remainingSlicesForCue`）。
  - **展开与落地的分工**：「整组」由 `AppState.destroyTargets()` 展开（查全库，只选一片时选中集合里只有一片），「逐片」由 `LibraryService.destroyTrack()` 落地。少了展开那一步，单首销毁就只掉一首——第一版逐片改动漏的正是这里。原来的写法是整组一次清空行、只给被点的那片留墓碑，墓碑范围比删行范围小；云端旧基础分片里的其余几片没有 `del-*` 记录挡着，下一次增量拉取 / 从云端覆写就会把它们带回来——这就是「销毁后重建，其他歌又出来」的成因，不是重建本身。
- **「原子」指的是逻辑边界，不是数据库事务**：`destroyTrack` 内部没有 `db.transaction()`，一首歌要跨 `deleted_tracks` / 封面文件 / `tracks` / 内存四处写。取消只能在两首之间生效。
- 进度条按「已处理 / 总数」推进。CUE 组改成逐片销毁之后，每一片都会真的删掉一行，所以进度与销毁数一致；早期版本里「整组行被第一片带走、兄弟片 `destroyLibraryTrack` 返回 false」的那个错位已经不存在。
- 进度框是**模态**的，销毁不会在界面消失后继续跑——这正是「删除界面不要做成异步的」。每首都会 `notifyListeners()` 一次，换来的是一首歌一个完整动作、取消点永远落在歌与歌之间。
- **重建后本地墓碑必须为 0**（硬约束，`sync_service.syncLibraryFull`）：重建后云端基础分片就是本地全部行的快照，删除意图也一起物化了，墓碑已无剩余职责。所以重建后先 `clearDeadTombstones()` **静默清掉**「行已不在」的墓碑，再数一次；若仍有残留（说明某条墓碑对应着还活着的行），写进 `outcome.warn` 提示用户「建议检查数据」。
  - 顺带补上了 `purgeTombstonesUpTo(baseUpTo)` 的缺口：`baseUpTo` 只统计**活行**的 rev，而销毁后的墓碑 rev 通常更高，那一步天然漏掉一批。目前靠 `clearDeadTombstones()` 兜底，没有改 `baseUpTo` 的语义（它还要参与云端游标比较）。
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

## 7. 云盘 Provider（OpenList 驱动移植，已立项定界，未开工）

**用户决策原话**：「砍掉上传功能，采用路线B，尽量不要改动WebDavService」「按照A表全部删除」「B的话建立新的网络库功能列表，分类不同网络库支持的能力并在对应的按钮功能前加上检测，尽量保证WebDavService实现的功能全面，由账号对应的能力遮罩判断功能是否开启」「C中保留crypt列入待开发功能，其他的砍掉不进入文档」「netease_music加入待开发文档」「几个优先做的加入文档并开始讨论细节」。

相关完整文档：[02 §10 占位](02-NETWORK-LIBRARY.md)、[04](04-DOWNLOAD-QUEUE.md)（下载带自定义头）、[08](08-SYNC-AND-BACKUP.md)（云端写路径禁用）、[10 T6](10-SIDE-QUESTS.md)（账号模型地基）。

### 7.1 路线与参照物

- **路线 B**：把 OpenList 的驱动层（REST 直连各家网盘）移植成 Dart provider。**不移植** worker 的 WebDAV/XML 协议层——WDMM 本身是 WebDAV 客户端，自己转 WebDAV 再解析回去是绕路。
- 参照实现已克隆到 `localdev/`（已 gitignore，不入库）：`OpenListTeam/OpenList-Worker`（TS，HEAD `a355867`，移植底稿）+ `OpenListTeam/OpenList`（Go main，语义兜底）。驱动代码与 worker 运行时零耦合（抽样 quark：`env.|KV|waitUntil|durable` 零命中），移植是机械工作。
- 下载模型天然契合：驱动 `get()` 返回 `FileItem{raw_url, raw_url_headers}`（直链 + 必需请求头），正好对上现有 `WebDavStreamSource{uri, headers}`（`webdav_stream.dart`）；视频流式与下载都走「直链 + 头」。

### 7.2 已定型的取舍

1. **上传砍掉**：`CloudDriver` 接口无 put；云盘账号上 `writeBytes` / `ensureDirectory` 与 backup / sync / playlist 的云端写路径一律禁用（显式报语义，不做静默失败）。**例外**：`createFolder` 走独立「创建文件夹」位（见 7.2.3 / 7.3.2），baidu 支持。WebDAV 账号行为不变。
2. **`WebDavService` 对外 API 与行为不变**（14 个文件直接 import 它，全部零改动）。唯一接入缝：`_connFor` / `_resolve`（`webdav_service.dart:44-54`）之后按账号类型转调 `CloudDriveService` 同名方法。绕不开的配套：`WebDavAccount.providerType`（[10 T6](10-SIDE-QUESTS.md)）；云盘凭证走 AccountsService + credential vault 独立通道，`configure()` 的 url/user/pass 形状不动。
3. **能力遮罩**：账号类型 → 能力集合，枚举定型为**列出 / 读取 / 写入 / 创建文件夹 / 移动 / 复制 / 删除**（列出默认拥有、不在用户界面显示；「创建文件夹」按用户决定从「写入」拆出独立位，上传与写同步仍归「写入」）。云盘类型由驱动静态给定；**WebDAV 账号的能力由用户在表单里配置**（默认全量）。网络库行操作与多选工具栏按钮**先查遮罩再启用**；新建文件夹按钮按「创建文件夹」位遮罩（网络库 AppBar 与目录选择器两处，已实现）；WebDAV 表单的能力勾选区已实现（读取 / 写入 / 创建文件夹 / 移动 / 复制 / 删除）。**静态表登记原则（用户决定）**：`AccountCaps.staticCaps` 只登记已落地驱动（当前仅 `baidu_netdisk`），未落地盘先记 7.3.2 的核查表，落地时照表抄。
  - **与 OpenList 的对比（本轮查证）**：它的每驱动能力标志只有传输侧（`NoUpload` / `OnlyProxy` / `NoLinkURL` / `PreferProxy`，`internal/driver/config.go`），**写操作没有能力位、不做按钮遮罩**——只读驱动（openlist_share 等）在操作时返回 `errs.NotImplement` 由前端弹错；WebDAV 层按用户权限位（WEBDAV_READ / WEBDAV_MANAGE）拦截。WDMM 按本项目「禁用即隐藏」的决策在按钮层遮罩，比 OpenList 更进一步，属于有意差异。
4. **驱动范围已定界**：除 7.3 / 7.4 / 7.5 列出的驱动外，其余一律不做，不进文档不展开。
5. **读取能力的绑定**（用户原话「缓存音乐、下载文件、浏览、播放、流式传输功能绑定到账号类型的读取能力」）：这五类功能都要求账号具备「读取」。
6. **禁用即隐藏**：能力被遮罩时，单文件「更多」菜单的对应条目与多选工具栏的对应按钮**隐藏而非置灰**；「更多」按钮本身只要还有可用条目就保留。
7. **账号表单定型**：第一行名称、第二行类型（默认 WebDAV），选类型后动态出该盘自身字段。WebDAV 在服务器 URL 之下新增「远程路径」（默认 `/`，空置视为 `/`），**云盘账号同样有远程路径**；保存时 URL 结尾 `/` 隐式清除（`configure()` 已有同样的 trim，表单层保持同一规则）。云盘字段默认照 worker `Addition` 原样保留以便移植，逐盘细节落实时询问用户。
8. **云端写目标唯一选择点**（已按用户决定简化落地）：`sync_screen.dart`「① 选择网盘」下拉（落 `settings.syncAccountId`；凭证 / 歌单 / 音乐库 / 备份共用这条远端路径）与 `SyncService.targetAccount`（含活跃账号兜底）**只认 WebDAV 类型**——云盘没有写路径（7.2.1），用户原话「同步和备份也无法实现，只遍历 webdav 类型即可」。`backup_service.dart` 的账号遍历（备份档案凭据导出）与 `credential_vault_service.dart` 的条目构建同样只收 WebDAV：**推翻早前「云盘凭据也进备份」的说法**——档案里没有 secure storage 的驱动配置，云盘账号行恢复不了，只会占名误导。

9. **流式体验：界面先落地**（用户决定，已实现）：音乐与视频两条流式入口的跳转都**不等源解析**——网络库把解析交给页内 loader（云盘解析要列表 + filemetas + HEAD 三跳，原来会卡住整条跳转链），解析失败在页内错误态表达；「伪装成视频的音频」由视频页解析后 `pushReplacement` 去音乐页（复用同一队列 seed）。音乐页缓冲可视化（不改其它 UI 元素）：删除「已缓冲」文字，已缓冲区间 = 播放进度条**二级轨道**（实心）；源解析 / 起播前的老式等待缓冲 = 二级轨道铺满**左右渐变**（自定义轨道形状）。**账号表单保存流**（用户决定，已实现）：点保存不关弹窗，保存按钮变圈等待，校验（名称 / 重名 / 身份确认 / refresh_token / 云盘真连验证）在弹窗内完成；失败报错留在表单，云盘添加成功提示「成功添加（名称）」后随表单关闭。

10. **驱动自描述与注册表**（用户决定，已实现，99 §7.2.10）：处理逻辑、能力遮罩、表单配置参数**全部收进驱动文件**（`cloud_drivers/<name>_driver.dart`：驱动 + Addition + `XxxSpec extends CloudDriverSpec`）；`driver_registry.dart` 是唯一注册点（对齐 OpenList 的 bootstrap/drivers）——**新增一个盘 = 新增一个文件 + 注册表加一行**。账号表单按 `spec.form`（`CloudDriverField` / `CloudDriverSwitchField`，支持 visibleWhenSwitch / enabledWhenSwitch 依赖开关）通用渲染，类型下拉读 `kCloudDriverSpecs`，保存校验与配置组装按 spec 声明的键 / 必填 / 默认值执行；兼容层 `CloudDriveService` 只查表（`cloudDriverSpec(typeId)`）做构造 / 校验 / 令牌 patch 持久化，`AccountCaps` 只剩通用位定义与 WebDAV 归一（`staticCaps` / `forType` 已删）。**接口层独立**：`CloudDriver` + `CloudFileItem` + `CloudDriverException` + spec 全在 `cloud_driver.dart`，不依赖账号 / 存储；crypt 这类中间处理层以后实现同一 spec，`create()` 包住内层驱动、注册即接入。顺带：远程路径提为通用字段（类型之后、动态区之前），百度动态区顺序变为 spec 声明序（refresh_token → 在线续期地址 → 本地刷新开关 → Client ID / Secret）。

### 7.3 首批驱动（优先做）

`aliyundrive_open`、`baidu_netdisk`、`quark`、`115open`、`123_open`、`onedrive`、`onedrive_app`、`terabox`、`139`。共同特征：refresh_token 或 cookie **粘贴式**登录、直链 + 必需头、写操作全、无重加密（worker 驱动 18–40KB）。移植底稿 `localdev/OpenList-Worker/src/backend/drivers/<name>/`，语义兜底对照 Go 版同目录。
**首个端到端驱动：`baidu_netdisk`**（用户有测试条件）；`aliyundrive_open` 顺延——缺少测试条件，发布后靠其他用户反馈验收。移植 baidu 时**砍掉 crack 下载 API**（`download_api=crack/crack_video`、`custom_crack_ua`、`getCrackLink` / `getCrackVideoLink`，只走官方 dlink）——用户决定。
注意：`139` 带字符集标记，真机要先验编码。

### 7.3.1 baidu_netdisk 表单与驱动（已实现，待真机验收）

- **动态区顺序**：refresh_token（必填，粘贴，可切换明文）→ 远程路径（默认 `/`，空置视为 `/`）→ 在线续期地址（默认 OpenList 公共服务 `api.oplist.org/baiduyun/renewapi`，常驻可编辑）→ 开关「在本地处理令牌刷新」→ Client ID / Secret（仅开关开启时显示）。
- **开关语义（用户原话）**：「加一个开关：在本地处理令牌刷新，开启后显示Client ID和 Client Secret同时online_api变灰不可用，后端时也需要检查该开关，一旦打开就不使用online api逻辑而使用自建百度应用的刷新逻辑。」实现为 `BaiduAddition.localRefresh`，`BaiduClient.refreshToken()` 每次都检查。
- **保存语义（用户原话）**：「能获取到access_token即保存，不能获取到的话则原样传递报错。」保存前 `verifyNewAccount` 真连一次（换 token + uinfo 校验），失败把 `CloudDriverException` 原文弹给用户、不落库、表单内容保留。
- **存储映射**：refresh_token / client_id / client_secret / api_url_address / local_refresh / access_token 缓存 → `AccountsService.saveDriverConfig`（secure storage JSON，按账号隔离，删号即清）；remote_path / provider_type → accounts 表。
- **不进表单**：crack 全部、上传 6 字段、order_by / only_list_video_file（客户端自己排序 / 分类）、use_online_api 开关（被本地刷新开关取代，默认走在线续期）。
- **落点**：`lib/services/cloud_drivers/baidu_netdisk_driver.dart`（BaiduClient + 驱动 + **spec 自描述**：能力遮罩 / 表单参数 / 构造，见 7.2.10）、`cloud_drive_service.dart`（查表工厂 / 直链下载 / resolveStreamSource / 五个文件操作）、`accounts_screen.dart`（表单按 spec 通用渲染）、`accounts_service.dart`（驱动配置通道）、`webdav_service.dart`（`resolveStreamSource` 异步统一入口，四个调用点已切换）。
- **阶段 1 真机清单**：添加账号（换 token 成功 / 错误 token 原文报错不落库）；浏览（远程路径生效）；下载 / 缓存音乐 / 本地播放；视频与音乐流式（直链 302 + UA `pan.baidu.com`）；重命名 / 删除 / 移动 / 复制；新建文件夹按钮按「创建文件夹」位遮罩；baidu 含该位，云盘账号可建目录，WebDAV 由表单勾选决定（见 7.2.6）；添加账号保存全程（保存变圈等待 → 失败原文报错留表单 → 成功提示「成功添加（名称）」后退出，见 7.2.9）。

### 7.3.2 mkdir（创建文件夹）能力逐盘核查（OpenList 源码，本轮查证）

- **机制**：Go 版把 MakeDir / Move / Rename / Copy / Remove / Put 做成 `internal/driver` 的**可选接口**（方法名是 `MakeDir`，不是 Mkdir），87 个驱动都有方法签名，只读 / 索引驱动在方法体里返回 `errs.NotImplement`（桩实现）；op 层 type-switch 调用。Worker TS 把 mkdir 做成 `StorageDriver` 必备方法，行为与 Go 一致——真实现或抛「not supported」。**两版能力面一致**（worker 是我们的移植底稿）。
- **首批 9 盘全部真实现 mkdir**（静态表 mkdir = 有）：`baidu_netdisk`（Go `driver.go:96` MakeDir → `create(path, 0, 1)` isdir=1，已验真；worker 同）、`aliyundrive_open`、`quark`、`115open`（worker `driver.ts:339` → `client.mkdir` 真调用，勿被「方法体含 throw」的粗扫误判）、`123_open`、`onedrive`、`onedrive_app`、`terabox`、`139`。
- **只读家族 mkdir = 无（桩）**：`115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`autoindex`、`github_releases`、`lenovonas_share`、`google_photo`、`quark_uc_tv`、`emby`；`url_tree` 疑似桩（落表前再确认一次）。
- **待开发**：`netease_music` 无 mkdir（桩）；`crypt` 透传内挂驱动，落表时按宿主动态给位、不进静态表。
- **登记**：已落地 → `AccountCaps.staticCaps`；未落地 → 本表，落地时照表抄（用户决定：写代码会影响运行的先只进文档）。

### 7.4 只读家族（能力遮罩 = 只读）

`115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`autoindex`、`github_releases`、`lenovonas_share`、`google_photo`、`quark_uc_tv`、`emby`、`url_tree`——浏览 / 下载 / 流式可用，写操作按遮罩隐藏（worker 驱动内五项写方法全部显式抛「不支持」，二次扫描证实）。批次已定：先接 `openlist_share` + `github_releases`（API 形状差异最大的两个）验证遮罩机制，再批量铺其余。

### 7.5 待开发

#### crypt（阶段进行中：cipher 层已完成并互操作验证）

- **格式**：逐字节对齐 rclone crypt（OpenList crypt 直接包 rclone 的 cipher，v1.75.1）。内容 = 魔数 "RCLONE\\0\\0"(8B) + 随机 nonce(24B) + 64KiB 明文分块 secretbox（XSalsa20-Poly1305，16B MAC，块 nonce = 文件 nonce + 块号 LE 加法）；KDF = scrypt(N=16384, r=8, p=1, 80B → dataKey32 / nameKey32 / nameTweak16)，空密码 = 全零密钥（格式一部分）；名字 = PKCS7(16) + EME(AES-256, nameTweak，≤128 块) + Base32（Hex 表小写去填充）/ Base64（URL 安全去填充，OpenList 默认）/ Base32768（与 rclone SafeEncoding 同表）三选一，off 模式 = 原名 + `.bin`（文件）/ 原名（目录），混淆 = rclone obfuscate 方案（含 `!` 双写、latin1 / ≥U+100 区段）。
- **实现**：`lib/services/cloud_drivers/crypt/cipher/`（salsa20 / secretbox / eme / name_codec / base32768 + base32768_table / rclone_cipher），pointycastle 组合，无新增原生依赖。
- **互操作验证**：本机编译 rclone v1.75.1 生成金标向量（名字 ×4、内容 ×2、混淆 ×1）+ NaCl 官方向量，`test/crypt_cipher_test.dart` 固化；生成环境在 localdev（gitignored）。
- **字段（照 OpenList meta.go，默认值也照抄）**：filename_encryption（off/standard/obfuscate，默认 off）、directory_name_encryption（默认 false）、filename_encoding（base64/base32/base32768，默认 base64）、encrypted_suffix（默认 .bin，仅文件名加密=off 时生效）、password、salt；另加源账号引用与源目录（用户决定：源 = 已有账号 id，**WebDAV 也可作源**；crypt 浏览根 = 源账号远程路径 + 源目录，如源账号根 /456 + 源目录 /789 → 实际落 /456/789）。
- **坏名字行为（照 OpenList driver.go 202-219）**：解密失败用原名原大小透传。本驱动只读取、不改动远端，透传既不写入也不做二次加密（早期「宁可不加密也不丢文件」的说法不成立，已删）。
- **范围（用户决定）**：只读链路（浏览 / 下载 / 流式解密 + 改名 / 删除 / 建目录名加密）；无内容上传（7.2.1）。
- **已完成**：`CryptSource` 抽象 + `CloudDriverEnv.resolveSource` 注入（`WebDavAccountSource` 落在 crypt 目录，由 AppState 注入工厂，避免反向依赖；源不存在 → 浏览时报错不炸注册）；能力随源映射并剥离 write 位（防上传权限泄漏进 UI）；名称编码三档（base32768 用 rclone 官方 17 条 golden 向量验证）。
- **待办（下一批）**：libsodium FFI 引擎 + 手动切换（两种实现同一格式可随时互切，落点设置或账号级待定）。
- **盐**：rclone `cipher.go` 内置 `defaultSalt`（16 字节 `A8 0D F4 3A 8F BD 03 08 A7 CA B8 3E 58 1F 86 B1`），salt 为空即用它；OpenList 把 salt 去掉 obfuscated 前缀后作 `password2` 交给 rclone，语义相同 → 我方「留空用内置默认盐」与两端一致。密码与盐一律按 UTF-8 字节进 scrypt（对应 Go 的 `[]byte(s)`）。
- **本批修复（真机反馈）**：① 云盘表单 `CloudDriverField` 的控制器创建曾被误删 → 密码填了仍报「请填写密码」（TextField 自建内部控制器，校验读到 null）；② 表单校验错误改为弹窗内联显示（SnackBar 被 AlertDialog 盖住，真机只露出一条边）；③ 下拉框加 `isExpanded` 并去掉标签长括号，消除右溢出。④ 应用内消息（`AppSnack`）改为**最顶层底部横幅**：挂在 `MaterialApp.builder` 的 Stack 里、Navigator 之上，位置仍在屏幕底部（用户澄清「置顶」= 层级最上，不是移到上方），对话框 / 键盘 / 底部导航都盖不住；音乐流式页切模式的提示也统一走 `AppSnack`，仓库里不再有裸 `showSnackBar`。
- **本批修复（第二批，真机反馈）**：⑤ **下载进度**：crypt `openContent` 原为「整包下载 → 一次 yield」，队列进度只有 0 与 100；现改为 按 rclone 的块结构做 Range 分段（先取 32B 文件头拿 nonce，再按 65536+16B 逐块拉取、逐块认证、逐块 yield），进度随块推进且内存只占一块；源忽略 Range（一次回整个文件）或长度未知时退回整包解密。新增 `RcloneCipher.fileNonceOf` / `decryptBlock` 与「逐块 = 整包」等价测试。⑥ **账号类型名**：网盘账号列表的副标题原为 `a.url.isEmpty ? '百度网盘' : a.url`（写死），crypt 因此显示成源网盘名；改为 `CloudDriveService.typeLabelFor`，crypt 显示「<源网盘类型> Crypt」（源已删则退化为「Crypt」），其余云盘显示 spec 的 `displayName`。⑦ **AGP 9 Kotlin 弃用警告（查证结论：应用侧消不掉）**：删掉 `android/gradle.properties` 的 `android.builtInKotlin=false` 后再构建，Flutter 的 gradle migrator 会把它**自动写回**（注释由 `added by the Flutter template` 变成 `added automatically by Flutter migrator`），`:app` 的 `Deprecated 'org.jetbrains.kotlin.android' plugin usage` 警告照旧；同一警告还来自第三方插件（`:audio_service`）。Gradle 给的正解是「同时删 `android.builtInKotlin=true` 与 `android.newDsl=false` 并迁移到内置 Kotlin」，这要 Flutter 自身先完成迁移且会牵动第三方插件 → 保持现状，不再逐次删除。
⑧ **本地流桥（crypt 流式播放落地）**：`crypt/crypt_stream_bridge.dart`。media_kit / ffmpeg 只认 URL 或本地路径，所以把新增的 `CloudDriver.openContentRange`（crypt 覆写：明文区间 → 只拉覆盖它的 rclone 块、逐块解密、首尾块裁剪）包成**只监听 127.0.0.1** 的 HTTP 端点：HEAD 回 Content-Length、无 Range 回 200 全量、有 Range 回 206 + Content-Range（含 `bytes=-n` 后缀区间），token 一次性映射 (accountId, path) 且 URL 里不含凭证，空闲 10 分钟自动关服务器。`CloudDriveService.resolveStreamSource` 对 MustProxy 驱动直接返回桥 URL，**播放入口（视频 / 音乐）不需要任何分支判断**；`size` 未知时明确报错，绝不给密文直链。测试 `test/crypt_stream_bridge_test.dart`：桥的 HTTP 语义 + 「本地密文服务 → Range → 块解密」端到端。
⑨ **保存失败无提示**：表单 `fail()` 除了弹窗内联文字，同时推一条最顶层横幅（内联文字可能落在滚动区之外看不到）；`verifyNewAccount` 的捕获从 `on CloudDriverException` 放宽为全部异常 —— 此前网络层异常会直接冒泡，用户看不到任何提示、按钮默默恢复。
- **base32768 移植**：`cipher/base32768.dart`（逐条对齐上游 `Max-Sum/base32768`：15 位块 + 末块 7 位、补 1、排序后前 4 字符为尾部字母表）与 `cipher/base32768_table.dart`（由 localdev 脚本从上游包生成，1028 个码点）；测试 `test/base32768_test.dart` 用 rclone `TestEncodeFileNameBase32768` 的 17 条向量 + 非法输入位置 + 0..200 全长度往返。

- **crypt**：rclone 兼容加密层（worker 侧 aes + hash-wasm）。它是 MustProxy 驱动——开工前必须先定「本地流桥」（应用内 127.0.0.1 HttpServer 把驱动字节流转成 media_kit 可拉的 URL）还是「仅下载播放」。
- **netease_music**：cookie + rsa/aes 登录；只支持删除，不能建目录 / 改名 / 移动 / 复制。对音乐管理器语义贴合。

### 7.6 关键技术点（移植时要一起处理的）

- token / cookie 刷新与持久化：worker 的 cookie 持久化机制（`persistStorageCookie`）要有 Dart 版，落 secure storage。
- path→id 缓存：worker 驱动实例内的 Map 缓存（如 quark）在移动端的生命周期与失效策略。
- 直链必需头贯穿下载链路：`WebDavStreamSource` 已带 headers；`download_queue` 的下载请求要能带同样的头，[04](04-DOWNLOAD-QUEUE.md) 待补。
- 流式统一入口：`WebDavService.resolveStreamSource`（异步）已落地，四个调用点（网络库视频 / 音乐流式、音乐流式页、视频页）已切换；云盘账号走 `CloudDriveService.resolveStreamSource` 取直链 + 头。
- Range：流式必须；上游拒绝 / 忽略 Range 时按 worker 的做法降级（去掉 Range 重试一次）。
- refresh_token「粘贴式获取」逐盘实测：部分盘可能必须应用内回调页，查不到的以真机为准。

### 7.7 分阶段（每段独立交付、独立验收）

| 阶段 | 内容 | 验收 |
|---|---|---|
| 0 | 地基：[10 T6](10-SIDE-QUESTS.md) 迁移、`CloudDriver` 接口 + `CloudDriveService` 骨架、`WebDavService` 缝、能力遮罩枚举与静态表。**已完成**：`flutter analyze` 全清 + 244 测试全过，[10 T6](10-SIDE-QUESTS.md) 随之删除 | `flutter analyze` + `flutter test`；WebDAV 账号行为不变 |
| 1 | 首个驱动端到端：`baidu_netdisk`。**代码已实现（表单 + 驱动 + 下载 / 流式全链路），待真机验收**，清单见 7.3.1 | 真机：添加账号 → 浏览 → 下载 → 流式 |
| 2 | 能力遮罩接线 UI：WebDAV 表单能力勾选 + 行操作 / 多选按钮按遮罩隐藏 + 只读试点（`openlist_share` + `github_releases`）。**新建文件夹遮罩已提前接入**（网络库 AppBar + 目录选择器，按写入位隐藏） | 真机：只读账号无写入口；WebDAV 能力勾选生效 |
| 3 | 首批其余驱动逐个移植（`aliyundrive_open` 靠后，验收依赖发布后用户反馈） | 逐盘真机验收 |
| 4 | 云端写路径禁用语义（backup / sync / playlist 对云盘账号的提示） | 真机：云盘账号同步入口有明确文案 |

阶段 0 代码落点：`lib/models/account_capabilities.dart`（能力位 + 静态表）、`lib/models/webdav_account.dart`（`providerType` / `remotePath` / `capabilities`）、`lib/services/cloud_driver.dart`（接口 + `CloudFileItem`）、`lib/services/cloud_drive_service.dart`（骨架：类型判定 / 能力解析 / 写路径永久禁用）、`lib/services/webdav_service.dart`（`_cloudOf` 分流缝，12 个方法头）、`lib/services/library_database.dart`（v6，accounts 补列 `provider_type` / `remote_path` / `capabilities`）、`lib/services/accounts_service.dart`（`accountById` + 扩参）、`lib/providers/app_state.dart` 与 `lib/main.dart`（装配）。

### 7.8 剩余未定

1. crypt 流桥形态（用户已定向，细节随实现定）：下载/缓存走内存流解密（已定）；流式播放内存流优先、media_kit 仅认 URL 时退本地 HTTP 桥（只服务 crypt，不碰原播放逻辑）；cipher 引擎切换（纯 Dart / libsodium FFI）的落点（设置全局 vs crypt 账号级）在引擎落地时定。
2. 直链风控、refresh_token 粘贴式可行性：逐盘真机实测（见 7.6）。baidu 首轮真机验收就是第一手数据。
3. 后续驱动（`aliyundrive_open` 等）落实表单时仍按 7.3.1 的模式先报字段清单给用户确认；教程文案统一链 OpenList 官方文档对应驱动页。

