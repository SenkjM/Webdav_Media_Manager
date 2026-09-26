# 99 · 开发中文档

只记录**正在开发**的功能的原始语义：需求原话、取舍、临时决定、还没定型的实现。
用法与收口规则见 [00-INDEX.md](00-INDEX.md) 的「完整文档与开发中文档」。

- 开发新功能前**先读本文件**，再读每一条链接到的完整文档。
- 下面**按功能 / 项目分节**，不按「已完成 / 待验收 / 取舍」这类状态分类；每条自己的状态写在它的开头。
- 自动化的做完只是门槛：`flutter analyze` 干净 + `flutter test` 全过，不代表真机行为对。所以代码上了 `main`、真机还没碰过的，仍留在这里。
- 开发完成后：删掉这里的条目，把语义按完整文档的写法补进对应功能块，并去掉占位。

## 1. 音乐流式播放（优化方向已定，未开工）

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

### 1.1 流式传输音乐界面的 UI 优化（未开工，方向已定）

**用户原话**：「新加一条流式传输音乐界面的 UI 优化，现在太丑了。」

**为什么丑（可直接确认，不是主观印象）**：

- **这一页现在根本没有深色底**：`AppColors.nearBlack` 等于 `background`（`0xFFFAFAFA`），`onDark` 等于 `primaryText`（墨黑）。所以「近黑底 + 亮点文字」写出来的其实是**浅灰底 + 深字**。视频页看着是黑的，靠的是 `media_kit_video` 自带的 `Video` 组件，与主题无关；音乐页刻意不建它，于是原形毕露。这是 [§2](99-IN-PROGRESS.md) 阶段一欠的账，不是这一页自己写错。
- 封面 200×200 **写死**，小屏顶边、大屏显小；72 px 纯灰图标没有任何层次。
- 标题 18 px 与副标题「流式传输 · 未缓存」12 px 挤在一起，中间没有歌手 / 专辑层。
- 进度条下方那行时间：左侧时间与右侧「已缓冲」字号相同、没有主次；进度条底轨是默认灰，拖动时的高亮也没接强调色。
- 控制条 5 个按钮 `spaceBetween` 等距，**大播放键与小图标混排**，节奏乱。
- 模式按钮是自绘 `Stack` + `Positioned` 角标「1」，不够精致；切模式用 `SnackBar`，在居中常驻布局里从底部弹出来很突兀。
- 整页 `Center` + `SingleChildScrollView`，短屏上方留白过多。

**用户已拍板的三件事**：

1. **底色**：走 [§2](99-IN-PROGRESS.md) 阶段一（`AppColors` 上下文取色），**不**在这一页单独铺深色底。
2. **封面**：这轮**不抓远端图**，只把占位做得像样（尺寸自适应、圆角、阴影、强调色渐变图标）。内嵌封面是独立的一块（Range 读头部 + 解析 ID3 / FLAC 图块），不在本次范围。
3. **范围**：视觉与布局都改，**元素一个不增不减**——大封面 + 标题层 + 紧致进度 + 居中控制条这套常规播放器骨架。

**顺序**：阶段一必须先做。这一页的底色问题就是阶段一的产物，先重排布局等于照着浅色底调一遍，取色做完还得再调一遍。

**阶段一的实测规模**（本轮查证，比 §2.1 记的数字更准）：

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
### 1.2 流式音乐播放的预载（未开工，方案待定）

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

## 2. 主题配色（已分析，未开工）

相关完整文档：[09 §编码约定](09-MISC.md)、[05](05-AUDIO-PLAYBACK.md)、[06](06-VIDEO-PLAYBACK.md)、[07](07-NOTIFICATIONS.md)。待发布与拆分见 [10 T1 / T2](10-SIDE-QUESTS.md)。

### 2.1 现状（可直接确认）

- `lib/theme/app_theme.dart` 里 `AppTheme.light` 与 `AppTheme.dark` **两套都已写完**，各约 240 行，覆盖 AppBar / Drawer / Card / ListTile / TabBar / Slider / Chip / Dialog / SnackBar / SegmentedButton 等。
- `lib/main.dart` 已传 `theme:` 与 `darkTheme:`，但 `themeMode: ThemeMode.light` 是**写死**的——`AppTheme.dark` 现在是死代码。
- `AppColors`（同文件）是 `static const Color`，全库 **24 个文件、325 处**直接引用。
- 另有约 **417 处**裸颜色（`Colors.xxx` / `Color(0x…)`），分布在 25 个文件，其中一部分是**有意**的（封面占位、状态色、播放器黑底）。

### 2.2 为什么不能只把 `themeMode` 打开

改成 `ThemeMode.dark` 会立刻得到「深色主题 + 一堆亮色残留」：`AppColors.xxx` 是编译期常量，不跟主题走，于是文字、分隔线、卡片底色仍是亮色值。这是这个功能真正的工作量所在。

### 2.3 拆分（两阶段，各自独立可交付）

**阶段一 · 静态引用转上下文取色**

- `AppColors` 改成「静态常量（默认亮色，保持兼容）+ 上下文取色入口（`AppColors.of(context)` 或 `BuildContext` 扩展）」。
- 逐文件把 `AppColors.xxx` 换成上下文取色，**24 个文件、325 处**。
- 只认「该值是否随主题变化」：`nearBlack` / `onDark` 这类语义在暗色下会**反转**（播放器黑底在暗色下应是深背景而不是纯黑），要单独过一遍，不能机械替换。
- 完成后亮色下**行为完全不变**，暗色下除裸颜色外应当正常。默认仍是 `ThemeMode.light`，所以这一步落地即安全。

**阶段二 · 模式开关与自定义取色**

- 三态开关：跟随系统 / 亮 / 暗；持久化沿用 `SettingsService` 既有模式。
- 自定义配色：边界**未定**（是只让用户改主色 accent，还是整套色板）。只改主色工作量小得多，但要让对比色（`onAccent`）跟着算出来。**需要先确认**。
- 裸颜色审计与收敛，按类判断：哪些该跟主题、哪些本来就该固定。

### 2.4 验收与回归点

- 纯黑播放器页、下载进度 / 状态色、封面占位在两种模式下都要可读；`docs/05`、`06`、`07` 的界面描述要跟着补。
- 阶段一落地后跑 `flutter analyze` 与 `flutter test`；阶段二补设置项相关的测试。

## 3. 多语言（已分析，未决定，未开工）

用户问「多语言怎么处理」，只做了查证与拆分：**没有动代码**。相关完整文档：[10 T4 / T5](10-SIDE-QUESTS.md)。

### 3.1 实测现状

| 项 | 值 |
|---|---|
| 含中文的字符串字面量 | 944 条（约 1.1 万汉字） |
| 分布在 | 61 / 85 个 Dart 文件 |
| `flutter_localizations` | 未引入 |
| `intl` | pubspec 已声明 `^0.20.3`，代码中未直接使用 |
| `l10n.yaml` / `.arb` | 都不存在 |
| `android/app/src/main/res/values*/strings.xml` | 不存在（应用名走 gradle `manifestPlaceholders["appName"]`） |
| 文案最集中的文件 | `sync_screen` 112、`settings_screen` 84、`network_library_screen` 75、`video_player_screen` 64 |

### 3.2 三个结构性难点（必须在批量替换**之前**处理）

1. **枚举的显示名**：`models/` 下 38 个文件有中文，多为 `XxxLabel` / `label` 扩展（`CacheRetention`、`DownloadTarget`、`FileAction`、`SyncInterval`、`VideoGestureAction` …）。model 层拿不到 `BuildContext`。推荐给这些 label 扩一个 `AppLocalizations` 参数，而不是把映射表搬到 UI 层（后者要动几十个调用点）。
2. **被持久化的字符串值**：`library_service.dart:503` 用 `'未分类'` 当 key 并参与排序比较；`playlist.dart:75` 落库默认值 `'未命名'`；`accounts_service.dart:127` 默认服务器名 `'默认服务器'`。**改字符串之前必须先脱钩**，否则旧数据对不上。真机数据库里是否已存在这些值，查不到。
3. **后台服务的文案**：`services/` 下 18+ 个文件、38 组含中文，例如 `download_queue_service` 的 `_lastError`、`audio_player_service` 的 `'本地无缓存，请先下载'`、`backup_service` 的异常文案。service 层没有 `BuildContext`，正确做法是返回错误码 / 结构化结果、由 UI 层映射文案——这是重构，不是替换。

### 3.3 分阶段（顺序不能调）

| 阶段 | 内容 | 备注 |
|---|---|---|
| 0 | `flutter_localizations` + `l10n.yaml` + ARB + `MaterialApp` 接线 | 见 [10 T4](10-SIDE-QUESTS.md)；key 命名规则必须在这一步定死 |
| 1 | 6.2 的三类结构性问题 | 做不完就替换文案 = 白干 |
| 2 | 按模块替换 944 条文案 | 线性体力活，一批一个 commit |
| 3 | 平台侧资源（应用名、通知渠道名） | 见 [10 T5](10-SIDE-QUESTS.md) |
| 4 | 语言切换（跟随系统 / 应用内切换 + 持久化） | 独立功能，可选 |

### 3.4 需要用户决定的三件事

1. 目标语言（中 + 英？）；2. 范围（全量还是先跑通一两个模块）；3. 要不要应用内语言切换。**未决定前不开工。**

## 4. 云盘 Provider（OpenList 驱动移植，进行中）

**用户决策原话**：「砍掉上传功能，采用路线B，尽量不要改动WebDavService」「按照A表全部删除」「B的话建立新的网络库功能列表，分类不同网络库支持的能力并在对应的按钮功能前加上检测，尽量保证WebDavService实现的功能全面，由账号对应的能力遮罩判断功能是否开启」「C中保留crypt列入待开发功能，其他的砍掉不进入文档」「netease_music加入待开发文档」「几个优先做的加入文档并开始讨论细节」。

相关完整文档：[02 §10 占位](02-NETWORK-LIBRARY.md)、[04](04-DOWNLOAD-QUEUE.md)（下载带自定义头）、[08](08-SYNC-AND-BACKUP.md)（云端写路径禁用）、[10 T6](10-SIDE-QUESTS.md)（账号模型地基）。

### 4.1 路线与参照物

- **路线 B**：把 OpenList 的驱动层（REST 直连各家网盘）移植成 Dart provider。**不移植** worker 的 WebDAV/XML 协议层——WDMM 本身是 WebDAV 客户端，自己转 WebDAV 再解析回去是绕路。
- 参照实现已克隆到 `localdev/`（已 gitignore，不入库）：`OpenListTeam/OpenList-Worker`（TS，HEAD `a355867`，移植底稿）+ `OpenListTeam/OpenList`（Go main，语义兜底）。驱动代码与 worker 运行时零耦合（抽样 quark：`env.|KV|waitUntil|durable` 零命中），移植是机械工作。
- 下载模型天然契合：驱动 `get()` 返回 `FileItem{raw_url, raw_url_headers}`（直链 + 必需请求头），正好对上现有 `WebDavStreamSource{uri, headers}`（`webdav_stream.dart`）；视频流式与下载都走「直链 + 头」。

### 4.2 已定型的取舍

1. **上传砍掉**：`CloudDriver` 接口无 put；云盘账号上 `writeBytes` / `ensureDirectory` 与 backup / sync / playlist 的云端写路径一律禁用（显式报语义，不做静默失败）。**例外**：`createFolder` 走独立「创建文件夹」位（见 7.2.3 / 7.3.2），baidu 支持。WebDAV 账号行为不变。
2. **`WebDavService` 对外 API 与行为不变**（14 个文件直接 import 它，全部零改动）。唯一接入缝：`_connFor` / `_resolve`（`webdav_service.dart:44-54`）之后按账号类型转调 `CloudDriveService` 同名方法。绕不开的配套：`WebDavAccount.providerType`（[10 T6](10-SIDE-QUESTS.md)）；云盘凭证走 AccountsService + credential vault 独立通道，`configure()` 的 url/user/pass 形状不动。
3. **能力遮罩**：账号类型 → 能力集合，枚举定型为**列出 / 读取 / 写入 / 创建文件夹 / 移动 / 复制 / 删除**（列出默认拥有、不在用户界面显示；「创建文件夹」按用户决定从「写入」拆出独立位，上传与写同步仍归「写入」）。云盘类型由驱动静态给定；**WebDAV 账号的能力由用户在表单里配置**（默认全量）。网络库行操作与多选工具栏按钮**先查遮罩再启用**；新建文件夹按钮按「创建文件夹」位遮罩（网络库 AppBar 与目录选择器两处，已实现）；WebDAV 表单的能力勾选区已实现（读取 / 写入 / 创建文件夹 / 移动 / 复制 / 删除）。**静态表登记原则（用户决定）**：`AccountCaps.staticCaps` 只登记已落地驱动（当前仅 `baidu_netdisk`），未落地盘先记 7.3.2 的核查表，落地时照表抄。
  - **与 OpenList 的对比（本轮查证）**：它的每驱动能力标志只有传输侧（`NoUpload` / `OnlyProxy` / `NoLinkURL` / `PreferProxy`，`internal/driver/config.go`），**写操作没有能力位、不做按钮遮罩**——只读驱动（openlist_share 等）在操作时返回 `errs.NotImplement` 由前端弹错；WebDAV 层按用户权限位（WEBDAV_READ / WEBDAV_MANAGE）拦截。WDMM 按本项目「禁用即隐藏」的决策在按钮层遮罩，比 OpenList 更进一步，属于有意差异。
4. **驱动范围已定界**：除 4.3 / 4.4 / 4.5 / 4.9 列出的驱动外，其余一律不做，不进文档不展开。
5. **读取能力的绑定**（用户原话「缓存音乐、下载文件、浏览、播放、流式传输功能绑定到账号类型的读取能力」）：这五类功能都要求账号具备「读取」。
6. **禁用即隐藏**：能力被遮罩时，单文件「更多」菜单的对应条目与多选工具栏的对应按钮**隐藏而非置灰**；「更多」按钮本身只要还有可用条目就保留。
7. **账号表单定型**：第一行名称、第二行类型（默认 WebDAV），选类型后动态出该盘自身字段。WebDAV 在服务器 URL 之下新增「远程路径」（默认 `/`，空置视为 `/`），**云盘账号同样有远程路径**；保存时 URL 结尾 `/` 隐式清除（`configure()` 已有同样的 trim，表单层保持同一规则）。云盘字段默认照 worker `Addition` 原样保留以便移植，逐盘细节落实时询问用户。
8. **云端写目标唯一选择点**（已按用户决定简化落地）：`sync_screen.dart`「① 选择网盘」下拉（落 `settings.syncAccountId`；凭证 / 歌单 / 音乐库 / 备份共用这条远端路径）与 `SyncService.targetAccount`（含活跃账号兜底）**只认 WebDAV 类型**——云盘没有写路径（7.2.1），用户原话「同步和备份也无法实现，只遍历 webdav 类型即可」。
   - **账号凭证进备份 / 同步（用户决定，2026-07 追加，推翻本条早前的排除段）**：用户原话「同步与备份功能中的WebDav凭证改为账号凭证……除了原有的webdav备份字段，还应该备份其他类型的网盘凭证」「从云端恢复时静默过滤不支持的网盘类型」「加密凭证配置也同步到所有在配置界面默认为密码的数据」。落地：`credentials.json` 升 formatVersion 2（WebDAV 条目 + 云盘条目 `providerType` + `driverConfig`）；云盘配置里 spec 表单 `obscure` 字段（`CloudDriverSpec.secretFieldKeys`）逐字段 AESGCMv1 加密，其余明文；恢复端 `cloudDriverSpec(typeId)` 查不到的类型**静默跳过**（不报错、不建空壳账号）；备份归档的账号遍历同步放开（`BackupService.buildPayload`）。早前「云盘凭据不进备份（档案里没有 secure storage 的驱动配置，恢复不了）」的前提已消失——驱动配置现在随档案 / 凭证库走。细节收口进 [08 §2 / §5](08-SYNC-AND-BACKUP.md)。

9. **流式体验：界面先落地**（用户决定，已实现）：音乐与视频两条流式入口的跳转都**不等源解析**——网络库把解析交给页内 loader（云盘解析要列表 + filemetas + HEAD 三跳，原来会卡住整条跳转链），解析失败在页内错误态表达；「伪装成视频的音频」由视频页解析后 `pushReplacement` 去音乐页（复用同一队列 seed）。音乐页缓冲可视化（不改其它 UI 元素）：删除「已缓冲」文字，已缓冲区间 = 播放进度条**二级轨道**（实心）；源解析 / 起播前的老式等待缓冲 = 二级轨道铺满**左右渐变**（自定义轨道形状）。**账号表单保存流**（用户决定，已实现）：点保存不关弹窗，保存按钮变圈等待，校验（名称 / 重名 / 身份确认 / refresh_token / 云盘真连验证）在弹窗内完成；失败报错留在表单，云盘添加成功提示「成功添加（名称）」后随表单关闭。

10. **驱动自描述与注册表**（用户决定，已实现，4.2.10）：处理逻辑、能力遮罩、表单配置参数**全部收进驱动文件**（`cloud_drivers/<name>_driver.dart`：驱动 + Addition + `XxxSpec extends CloudDriverSpec`）；`driver_registry.dart` 是唯一注册点（对齐 OpenList 的 bootstrap/drivers）——**新增一个盘 = 新增一个文件 + 注册表加一行**。账号表单按 `spec.form`（`CloudDriverField` / `CloudDriverSwitchField`，支持 visibleWhenSwitch / enabledWhenSwitch 依赖开关）通用渲染，类型下拉读 `kCloudDriverSpecs`，保存校验与配置组装按 spec 声明的键 / 必填 / 默认值执行；兼容层 `CloudDriveService` 只查表（`cloudDriverSpec(typeId)`）做构造 / 校验 / 令牌 patch 持久化，`AccountCaps` 只剩通用位定义与 WebDAV 归一（`staticCaps` / `forType` 已删）。**接口层独立**：`CloudDriver` + `CloudFileItem` + `CloudDriverException` + spec 全在 `cloud_driver.dart`，不依赖账号 / 存储；crypt 这类中间处理层以后实现同一 spec，`create()` 包住内层驱动、注册即接入。顺带：远程路径提为通用字段（类型之后、动态区之前），百度动态区顺序变为 spec 声明序（refresh_token → 在线续期地址 → 本地刷新开关 → Client ID / Secret）。

### 4.3 首批驱动（优先做）

`aliyundrive_open`、`baidu_netdisk`、`quark`、`115open`、`123_open`、`onedrive`、`onedrive_app`、`terabox`、`139`。共同特征：refresh_token 或 cookie **粘贴式**登录、直链 + 必需头、写操作全、无重加密（worker 驱动 18–40KB）。移植底稿 `localdev/OpenList-Worker/src/backend/drivers/<name>/`，语义兜底对照 Go 版同目录。
**首个端到端驱动：`baidu_netdisk`**（用户有测试条件）；`aliyundrive_open` 顺延——缺少测试条件，发布后靠其他用户反馈验收。移植 baidu 时**砍掉 crack 下载 API**（`download_api=crack/crack_video`、`custom_crack_ua`、`getCrackLink` / `getCrackVideoLink`，只走官方 dlink）——用户决定。
注意：`139` 带字符集标记，真机要先验编码。

### 4.3.1 baidu_netdisk（已实现，待真机验收）

实现语义与取舍已收口进 [11 §10](11-CLOUD-DRIVER-PORTING.md)（动态区顺序、本地刷新开关、保存语义、存储映射、落点）。**待办只剩真机验收**：

- 添加账号：换 token 成功；错误 token 原文报错不落库；保存全程（变圈等待 → 失败留表单 → 成功提示「成功添加（名称）」后退出）。
- 浏览：远程路径生效；解密名正确。
- 下载 / 缓存音乐 / 本地播放。
- 视频与音乐流式：直链 302 + UA `pan.baidu.com`。
- 本地刷新开关联动：**打开**时 online_api 变灰且出现 Client ID / Secret；**关闭**时 online_api 可编辑（极性修正后的可观察行为，见 [11 §10](11-CLOUD-DRIVER-PORTING.md)）。
- 写操作四件套：重命名 / 删除 / 移动 / 复制；新建文件夹按钮按「创建文件夹」位遮罩（能力位见 4.3.2）。
- **源被删后的恢复路径**（本轮修复，见 [11 §4](11-CLOUD-DRIVER-PORTING.md)）：源账号删除后 crypt 报错应显示**源名字**并提示可恢复；重新添加**同名**源账号后 crypt 直接可用（无需重建）。
- **加载失败重试纪律**（本轮修复，见 [02 §6](02-NETWORK-LIBRARY.md)）：源被删状态下网络库不得无限自动重试拖慢应用；连续 3 次失败后停在错误界面等手动重试；恢复网络后自动补一次。

### 4.3.2 mkdir（创建文件夹）能力逐盘核查（OpenList 源码，本轮查证）

- **机制**：Go 版把 MakeDir / Move / Rename / Copy / Remove / Put 做成 `internal/driver` 的**可选接口**（方法名是 `MakeDir`，不是 Mkdir），87 个驱动都有方法签名，只读 / 索引驱动在方法体里返回 `errs.NotImplement`（桩实现）；op 层 type-switch 调用。Worker TS 把 mkdir 做成 `StorageDriver` 必备方法，行为与 Go 一致——真实现或抛「not supported」。**两版能力面一致**（worker 是我们的移植底稿）。
- **首批 9 盘全部真实现 mkdir**（静态表 mkdir = 有）：`baidu_netdisk`（Go `driver.go:96` MakeDir → `create(path, 0, 1)` isdir=1，已验真；worker 同）、`aliyundrive_open`、`quark`、`115open`（worker `driver.ts:339` → `client.mkdir` 真调用，勿被「方法体含 throw」的粗扫误判）、`123_open`、`onedrive`、`onedrive_app`、`terabox`、`139`。
- **只读家族 mkdir = 无（桩）**：`115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`autoindex`、`github_releases`、`lenovonas_share`、`google_photo`、`quark_uc_tv`、`emby`；`url_tree` 疑似桩（落表前再确认一次）。
- **已落地盘的能力位实录不再留在本表**：见 [11 §10](11-CLOUD-DRIVER-PORTING.md)（baidu_netdisk）、[11 §11](11-CLOUD-DRIVER-PORTING.md)（netease_music，`list | read | delete`——除删除外四个写方法上游全是桩）、[11 §12](11-CLOUD-DRIVER-PORTING.md)（粘贴凭证直连盘批次：123_open 无 copy，其余三盘五项全）与各驱动实录节。
- **未落地**：`crypt` 透传内挂驱动，落表时按宿主动态给位、不进静态表。
- **登记**：已落地 → `AccountCaps.staticCaps`；未落地 → 本表，落地时照表抄（用户决定：写代码会影响运行的先只进文档）。

### 4.3.3 netease_music（已实现，待真机验收）

实现语义、加密对齐与取舍已收口进 [11 §11](11-CLOUD-DRIVER-PORTING.md)。**待办只剩真机验收**：

- **添加账号**：粘贴含 `__csrf` + `MUSIC_U` 的 Cookie → 真连校验（拉一页列表）通过才保存；Cookie 不全时表单内联报错且不出网；Cookie 过期（`code 301`）时提示「Cookie 可能已过期」、不落库、表单内容保留。
- **浏览**：云盘歌曲以平铺列表出现（无目录层级）；远程路径只作虚拟前缀，改名后账号条目仍可打开。
- **下载 / 缓存音乐 / 本地播放**：直链由网易 CDN 给出，能正常下载与播放。
- **音乐流式**：VIP / 版权受限 / 已下架的歌曲要给出可读错误（不是空 URL、不是 0B 文件）。
- **删除**：列表里删一首歌 → 云端确实少一首；再刷新列表确认。
- **能力遮罩**：账号行**看不到**新建文件夹 / 重命名 / 移动 / 复制入口（隐藏而非置灰）；删除入口可见可用。
- **`song_limit`**：填小值（如 5）后列表只剩 5 首；非法值回落 200。
- **`weapi` / `linuxapi` 真连**：若网易改签（返回 `code -460` 之类），报错要带 code 与 message 原文，便于判断是风控还是实现问题。

### 4.3.4 第二批四盘（已实现，真机验收通过——用户确认，123_open 打开目录报 invalid_grant 已按用户决定不排查）：123_open / aliyundrive_open / 115open / terabox

按 4.9 的评估与 [13](13-DRIVER-BATCH-PLAN.md) 的筛选标准（粘贴凭证、有直链、无重加密、写方法真实现、单账号形态、worker 底稿完整）选出的快速批次，四盘全部走 [12](12-DRIVER-PORTING-GUIDE.md) 的工序（解耦检查 → 六步移植 → 一盘一测试）。语义与取舍收口进 [13 §4](13-DRIVER-BATCH-PLAN.md) 的字段清单与 [12](12-DRIVER-PORTING-GUIDE.md) 的表单/能力位规则。**共同语义**：直链必需头进 `rawHeaders`；`access_token` 只作缓存经 `onTokenUpdate` 持久化、不进表单；上传/排序字段不进表单；错误原文透传 `CloudDriverException`；`get()` 拿不到直链抛真实原因（不返回无直链条目，11 §10 的有意差异）。

- **`123_open`**（`lib/services/cloud_drivers/_123_open_driver.dart`，前缀 `_` 因 Dart 标识符不能以数字开头；typeId 仍 `123_open`）：refresh_token + 在线续期（默认 `api.oplist.org/123cloud/renewapi`，空串回落默认值）+ 本地刷新开关（client_id/secret 联动，极性照百度）；`{code,message,data}` 包裹、`code===401` 刷新后重试一次防死循环；path→id 实例缓存（写后清）。**copy 上游未实现 → 能力位不给 copy**。真机重点见 [13 §6.1](13-DRIVER-BATCH-PLAN.md)。
- **`aliyundrive_open`**：refresh_token + 在线续期**多候选轮询**（自定义地址优先 + 6 内置，去重）→ 全失败落直连 OAuth（内置 client_id）；`drive_type`（resource/default/backup）决定 drive_id，`UserNotAllowedAccessDrive` 自愈重解析一次；`remove_way`（trash/delete）。能力位含 copy。
- **`115open`**（文件名 `open115_*`，typeId 仍 `115open`）：refresh_token 每次刷新都轮换（`passportapi.115.com/open/refreshToken`，form 而非 JSON）；响应 `{state,code,message,data}`，`state=false` 且 code 99 / 401 开头 → 刷新重试一次，**430004 = 对象不存在**；直链必须配 OpenList UA（`rawHeaders` 贯穿）；**downurl 有每日配额 → 按 fid+UA 缓存 30 分钟**；`folder/get_info` 只认目录路径，430004/990002 回退逐层列目录。能力位含 copy。
- **`terabox`**：cookie 粘贴式（会过期，重贴）；列表 `errno===9000` 是地区不可用；**jsToken 从首页正则抓取**（4000023/450016 失效重取）、errno -6 换域名；签名 `genSign()=sign(sign3, sign1)`，MD5 上游只用于上传（已砍）故无需 crypto 依赖；直链响应 `dlink` / `info` 两种形态都处理。五项写操作全真实现，能力位含 copy。
- **实现中修复的驱动缺陷**（测试暴露，已随分支提交）：`123_open` path→id 缓存键与查表键不同形（缓存永远查不中）、续期地址空串不回落默认值；`aliyundrive_open` 在线续期候选地址未去重（custom 与 builtin 首项重复）。
- **验收状态（用户确认）**：真机验收按通过处理——123_open 添加与浏览真机通过（打开目录曾报一次 invalid_grant，用户决定不排查、按验收通过收口），其余三盘按用户决定一并视为验收通过；通用清单见 [12 §9](12-DRIVER-PORTING-GUIDE.md)，逐盘重点见 [13 §6.1](13-DRIVER-BATCH-PLAN.md)。

### 4.4 只读家族（能力遮罩 = 只读）

`115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`autoindex`、`github_releases`、`lenovonas_share`、`google_photo`、`quark_uc_tv`、`emby`、`url_tree`——浏览 / 下载 / 流式可用，写操作按遮罩隐藏（worker 驱动内五项写方法全部显式抛「不支持」，二次扫描证实）。批次已定：先接 `openlist_share` + `github_releases`（API 形状差异最大的两个）验证遮罩机制，再批量铺其余。

### 4.5 待开发

#### crypt（进行中：cipher 完成、下载/流式链路已通，剩 FFI 与收尾）

- **格式**：逐字节对齐 rclone crypt（OpenList crypt 直接包 rclone 的 cipher，v1.75.1）。内容 = 魔数 "RCLONE\\0\\0"(8B) + 随机 nonce(24B) + 64KiB 明文分块 secretbox（XSalsa20-Poly1305，16B MAC，块 nonce = 文件 nonce + 块号 LE 加法）；KDF = scrypt(N=16384, r=8, p=1, 80B → dataKey32 / nameKey32 / nameTweak16)，空密码 = 全零密钥（格式一部分）；名字 = PKCS7(16) + EME(AES-256, nameTweak，≤128 块) + Base32（Hex 表小写去填充）/ Base64（URL 安全去填充，OpenList 默认）/ Base32768（与 rclone SafeEncoding 同表）三选一，off 模式 = 原名 + `.bin`（文件）/ 原名（目录），混淆 = rclone obfuscate 方案（含 `!` 双写、latin1 / ≥U+100 区段）。对齐细节与坑见 [11 §2/§3](11-CLOUD-DRIVER-PORTING.md)。
- **实现**：`lib/services/cloud_drivers/crypt/cipher/`（salsa20 / secretbox / eme / name_codec / base32768 + base32768_table / rclone_cipher），pointycastle 组合，无新增原生依赖。互操作验证：本机编译 rclone v1.75.1 生成金标向量（名字 ×4、内容 ×2、混淆 ×1）+ NaCl 官方向量，`test/crypt_cipher_test.dart` 固化。
- **盐**：rclone `cipher.go` 内置 `defaultSalt`（16 字节 `A8 0D F4 3A 8F BD 03 08 A7 CA B8 3E 58 1F 86 B1`），salt 为空即用它；OpenList 把 salt 去掉 obfuscated 前缀后作 `password2` 交给 rclone，语义相同 → 我方「留空用内置默认盐」与两端一致。密码与盐一律按 UTF-8 字节进 scrypt（对应 Go 的 `[]byte(s)`）。
- **字段（照 OpenList meta.go，默认值也照抄）**：filename_encryption（off/standard/obfuscate，默认 off）、directory_name_encryption（默认 false）、filename_encoding（base64/base32/base32768，默认 base64）、encrypted_suffix（默认 .bin，仅文件名加密=off 时生效）、password、salt；另加源账号引用与源目录（用户决定：源 = 已有账号 id，**WebDAV 也可作源**；crypt 浏览根 = 源账号远程路径 + 源目录，如源账号根 /456 + 源目录 /789 → 实际落 /456/789）。
- **坏名字行为（照 OpenList driver.go 202-219）**：解密失败用原名原大小透传。本驱动只读取、不改动远端，透传既不写入也不做二次加密。
- **范围（用户决定）**：只读链路（浏览 / 下载 / 流式解密 + 改名 / 删除 / 建目录名加密）；无内容上传（4.2.1）。
- **架构**：`CryptSource` 抽象 + `CloudDriverEnv.resolveSource` 注入（`WebDavAccountSource` 落在 crypt 目录，由 AppState 注入工厂，避免反向依赖；源不存在 → 浏览时报错不炸注册）；能力随源映射并剥离 write 位（防上传权限泄漏进 UI）。**源适配层必须给 size**（单文件 PROPFIND，`webdav_service.statPath`）——漏掉会让 crypt 误判成整包，产出 0B 文件（真机反馈，已修，[11 §5](11-CLOUD-DRIVER-PORTING.md)）。
- **已落地增量（真机反馈驱动，语义已收口进固定文档）**：表单控制器与校验显示（[11 §6](11-CLOUD-DRIVER-PORTING.md)）；应用内消息最顶层横幅（[07](07-NOTIFICATIONS.md)）；下载进度按 rclone 块结构 Range 分段、逐块解密（[04 §3](04-DOWNLOAD-QUEUE.md)）；本地流桥（127.0.0.1 HTTP 端点包 `openContentRange`，播放入口无分支，[11 §5](11-CLOUD-DRIVER-PORTING.md)）；账号类型名 `typeLabelFor`（[02 §10](02-NETWORK-LIBRARY.md)）；下载重试三层兜底（分类 / 退避 / 断点续传）与超时补齐、原地重试、单一计数来源（[04 §7](04-DOWNLOAD-QUEUE.md)）；大小判定四态 shape + Content-Range 纠偏（[11 §5](11-CLOUD-DRIVER-PORTING.md)）。测试：`crypt_cipher_test` / `crypt_driver_test` / `crypt_stream_bridge_test` / `crypt_webdav_source_test` / `crypt_size_race_test`。
- **待办**：libsodium FFI 引擎 + 手动切换（两种实现同一格式可随时互切，落点设置或账号级待定）。真机验收：流式播放已通过（用户确认）；浏览 / 下载 / 坏名字透传仍待逐项确认。

### 4.6 关键技术点（移植时要一起处理的）

- token / cookie 刷新与持久化：worker 的 cookie 持久化机制（`persistStorageCookie`）要有 Dart 版，落 secure storage。
- path→id 缓存：worker 驱动实例内的 Map 缓存（如 quark）在移动端的生命周期与失效策略。
- 直链必需头贯穿下载链路：`WebDavStreamSource` 已带 headers；`download_queue` 的下载请求要能带同样的头，[04](04-DOWNLOAD-QUEUE.md) 待补。
- 流式统一入口：`WebDavService.resolveStreamSource`（异步）已落地，四个调用点（网络库视频 / 音乐流式、音乐流式页、视频页）已切换；云盘账号走 `CloudDriveService.resolveStreamSource` 取直链 + 头。
- Range：流式必须；上游拒绝 / 忽略 Range 时按 worker 的做法降级（去掉 Range 重试一次）。
- refresh_token「粘贴式获取」逐盘实测：部分盘可能必须应用内回调页，查不到的以真机为准。

### 4.7 分阶段（每段独立交付、独立验收）

| 阶段 | 内容 | 验收 |
|---|---|---|
| 0 | 地基：[10 T6](10-SIDE-QUESTS.md) 迁移、`CloudDriver` 接口 + `CloudDriveService` 骨架、`WebDavService` 缝、能力遮罩枚举与静态表。**已完成**：`flutter analyze` 全清 + 244 测试全过，[10 T6](10-SIDE-QUESTS.md) 随之删除 | `flutter analyze` + `flutter test`；WebDAV 账号行为不变 |
| 1 | 首个驱动端到端：`baidu_netdisk`。**代码已实现（表单 + 驱动 + 下载 / 流式全链路），待真机验收**，清单见 4.3.1 | 真机：添加账号 → 浏览 → 下载 → 流式 |
| 2 | 能力遮罩接线 UI：WebDAV 表单能力勾选 + 行操作 / 多选按钮按遮罩隐藏 + 只读试点（`openlist_share` + `github_releases`）。**新建文件夹遮罩已提前接入**（网络库 AppBar + 目录选择器，按写入位隐藏） | 真机：只读账号无写入口；WebDAV 能力勾选生效 |
| 3 | 首批其余驱动逐个移植。**已完成**：粘贴凭证直连盘批次 4 盘（`123_open` / `aliyundrive_open` / `115open` / `terabox`）——批量筛选与逐盘判定见 [13](13-DRIVER-BATCH-PLAN.md)，实现实录见 [11 §12](11-CLOUD-DRIVER-PORTING.md)；`flutter analyze` 无 issue、测试全过，**真机验收通过（用户确认）**。`quark_open`（MustProxy 需流桥）/ `139`（多形态）/ `quark`(cookie) 下沉到后续批 | 真机验收通过（用户确认） |
| 4 | 云端写路径禁用语义（backup / sync / playlist 对云盘账号的提示） | 真机：云盘账号同步入口有明确文案 |

阶段 0 代码落点：`lib/models/account_capabilities.dart`（能力位 + 静态表）、`lib/models/webdav_account.dart`（`providerType` / `remotePath` / `capabilities`）、`lib/services/cloud_driver.dart`（接口 + `CloudFileItem`）、`lib/services/cloud_drive_service.dart`（骨架：类型判定 / 能力解析 / 写路径永久禁用）、`lib/services/webdav_service.dart`（`_cloudOf` 分流缝，12 个方法头）、`lib/services/library_database.dart`（v6，accounts 补列 `provider_type` / `remote_path` / `capabilities`）、`lib/services/accounts_service.dart`（`accountById` + 扩参）、`lib/providers/app_state.dart` 与 `lib/main.dart`（装配）。

### 4.8 剩余未定

1. crypt 流桥形态（用户已定向，细节随实现定）：下载/缓存走内存流解密（已定）；流式播放内存流优先、media_kit 仅认 URL 时退本地 HTTP 桥（只服务 crypt，不碰原播放逻辑）；cipher 引擎切换（纯 Dart / libsodium FFI）的落点（设置全局 vs crypt 账号级）在引擎落地时定。
2. 直链风控、refresh_token 粘贴式可行性：逐盘真机实测（见 4.6）。baidu 首轮真机验收就是第一手数据。
3. 后续驱动（`aliyundrive_open` 等）落实表单时仍按 4.3.1 的模式先报字段清单给用户确认；教程文案统一链 OpenList 官方文档对应驱动页。

### 4.9 全量驱动清单与批量移植评估（OpenList 源码逐盘核查）

**数据基线**：worker 版 77 个驱动目录 + Go 版 88 个（`localdev/OpenList-Worker/src/backend/drivers/` 与 `localdev/OpenList/drivers/`），逐盘提取了 Addition 字段、方法实现、代理能力表（`internal/driver/proxy.ts` 是唯一真相）与 crypto 依赖。**能力面的两版一致性已核**：worker 的 mkdir / 写方法与 Go 的可选接口一致（4.3.2）。

#### 批次方案（P0 已在做，P1 起每批独立交付、独立验收）

| 批次 | 驱动 | 判定依据 |
|------|------|----------|
| **P0 已落地 / 进行中** | `baidu_netdisk`（已实现待验收）、`crypt`（cipher 完成） | 见 4.3.1 / 4.5 |
| **P1 粘贴凭证直连盘** | **`123_open`、`aliyundrive_open`、`115open`、`terabox`（✅ 本轮已移植，见 4.3.4）**；`quark_open`、`139`、`quark`(cookie) 下沉（判定见 [13 §2.2](13-DRIVER-BATCH-PLAN.md)：MustProxy 要流桥 / 5 种账号形态） | refresh_token / cookie 粘贴式登录、直链 + 必需头、写操作全、无重加密；依赖 `pkg/crypto` 或 `crypto-js` 的地方都有 Dart 对应（AES/RSA/MD5，pointycastle 覆盖） |
| **P2 只读家族**（能力遮罩=只读，浏览器式登录或分享链接） | `115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`github_releases`、`lenovonas_share`、`autoindex`、`url_tree`、`quark_uc_tv`、`emby`、`google_photo` | 五项写方法全部显式抛「不支持」；接入成本 = `CloudSource` 适配 + 能力遮罩；先接 `openlist_share` + `github_releases`（API 形状差异最大的两个）验证遮罩机制（4.4） |
| **P3 OAuth 回调盘** | `onedrive`、`onedrive_app`、`google_drive`、`dropbox`、`yandex_disk`、`pikpak`、`febbox`、`halalcloud_open`、`thunder` | 需要 OAuth client_id/secret + 回调或设备码流程，本地刷新与百度同构（`localRefresh` 开关模式直接复用）；体积不小但模式统一，可模板化批量铺 |
| **P4 协议 / 存储类** | `webdav`、`sftp`、`smb`、`ftp`、`alist_v3`、`openlist`、`cloudreve_v3`、`cloudreve_v4`、`seafile`、`kodbox`、`mega`、`proton_drive` | 与已有 WebDAV 能力重叠或需要额外协议栈（smb/ftp/sftp 要原生依赖，mega/proton 有自家加密）；`webdav` 驱动可作为「WebDAV 账号统一到云盘账号模型」的迁移出口，优先级单独评估 |
| **P5 对象存储 / 自建** | `s3`（+Doge）、`uss`、`azure_blob`、`bunny_storage`、`cloudflare_imgbed`、`ipfs_api` | 签名上传/下载为主，无浏览器登录问题；对媒体库场景价值取决于用户是否有这类存储 |
| **不移植**（用户已砍或无意义） | 上传 6 字段相关、`alias`/`strm`/`virtual`/`chunk`（worker 组合层，语义由本地已有功能承担）、`local`（Go 本地盘）、`template`/`base`（基础设施）、`123_link`（直链专用）、`aliyundrive`（旧版已被 open 取代）、`doubao_new`/`doubao_share`/`thunder_browser`/`thunderx`/`ilanzou`/`123pan`(账号密码版) 等 Go 特有变体 | 用户决定：「C 中保留 crypt 列入待开发，其他的砍掉不进入文档」；变体驱动等首批同源驱动真机验收后再议 |

#### 逐盘关键参数（P1/P3 全量，移植时按 4.3.1 模式先报字段清单）

| 驱动 | 登录 | Addition 必填 | 关键依赖 / 坑 |
|------|------|--------------|---------------|
| `aliyundrive_open` | refresh_token 粘贴 | `drive_type` `refresh_token` | 13 字段；token 401 时要用 refresh_token 换新（驱动内自动） |
| `115open` | refresh_token 粘贴 | 无（token 即凭证） | 7 字段；OSS 直传（`ossPutObject`）我们不用 |
| `123_open` | refresh_token 粘贴 | 无 | 10 字段；`api_url_address` 在线续期与百度同构 |
| `quark_open` | refresh_token + app_id + sign_key | 三项全必填 | 签名算法在 util；MustProxy（proxy 表：强制代理，无直链）→ 必须接流桥 |
| `terabox` | cookie 粘贴 | `cookie` | 依赖 `pkg/crypto`（js sha1/aes 变体）；直链带 UA 校验 |
| `139` | authorization 粘贴 | 无（可选 14 项） | **带字符集标记，真机先验编码**（4.3）；ProxyRangeOption |
| `onedrive` | OAuth | region 等 | 16 字段，`use_online_api`+`api_url_address` 在线续期（百度同构）；region 决定 API host |
| `onedrive_app` | OAuth(client+tenant) | client_id/secret | 12 字段；`getDirectUploadInfo` 不移植 |
| `google_drive` | OAuth | client_id/secret/refresh | MustProxy（无公开直链）→ 必须接流桥；API key 可选 |
| `dropbox` | OAuth | refresh_token | 10 字段；下载是 POST 流，不是 GET 直链（流桥要处理） |
| `yandex_disk` | OAuth | refresh_token | 标准 REST；MustProxy=false 有直链 |
| `pikpak` | OAuth(用户名密码换 token) | 无必填 | 12 字段；`pkg/crypto` 依赖 |
| `thunder` | OAuth 设备码 | 无必填 | 11 字段；`crypto-js` 依赖 |
| `febbox` / `halalcloud_open` | client_id+secret | 两项 | 模式与 P3 同 |

> 登录方式注记：cookie 类（`quark` `139` `terabox` `weiyun` 等）过期要用户手动重贴，表单要放「打开网页复制」的教程链接（教程统一链 OpenList 官方文档对应驱动页，4.8）；OAuth 类的本地刷新直接复用百度「在本地处理令牌刷新」开关 + `disabledWhenSwitch` 联动极性（4.3.1）。

#### 移植模板（批量铺开时的固定工序）

1. 照 worker `types.ts` Addition 字段定 spec 表单（默认值照抄 Go `meta.go`），先报字段清单给用户确认（4.8）；
2. 逐方法移植 `driver.ts`（list/get/mkdir/rename/move/copy/remove；**当前只读批次不移植 put**，4.2.1；未来恢复上传时必须按 [4.10](#410-方案-b云盘上传恢复计划未开工) 的 U3–U7 批次与能力门槛单独加入）。
3. 能力位照 4.3.2 的静态表登记；MustProxy 驱动同步接流桥（crypt 的 `crypt_stream_bridge.dart` 是范例）；
4. crypto 依赖对照：`pkg/crypto`/`crypto-js` 用到的原语（MD5/SHA1/AES/RSA）在 pointycastle 都有对应实现，逐个过测试向量；
5. 直链必需头进 `rawHeaders` 贯穿下载与流式（[11 §5](11-CLOUD-DRIVER-PORTING.md)）；
6. 一盘一测试文件：列表 / 直链头 / 錯误原文透传；cookie 类加「过期报错原文」用例。

**评估结论**：批量移植的主要成本不在单个驱动的 API 对接，而在**登录形态**（粘贴 vs OAuth 回调）与**直链形态**（302 vs MustProxy+流桥）。这两维各收敛一套模板后，P1–P3 的 20+ 个驱动可以流水线化铺开；建议每批 2–4 个驱动、真机验收通过后再进下一批。
## 4.10 方案 B：云盘上传恢复计划（未开工）

**状态**：未开工，仅作为后续实现参考；当前代码仍保持 [4.2.1](#42-已定型的取舍) 的语义：云盘账号上传与云端写同步禁用。本节不代表上传已经支持，也不改变当前版本的能力遮罩。

**方案结论**：采用「调用方提供本地文件 / 可重读流，驱动自己完成真实上传」的方案。OpenList Go 的通用边界是 `Put(ctx, dstDir, model.FileStreamer, UpdateProgress)`（参照 `localdev/OpenList/internal/driver/driver.go`）；Worker 的 `put` 虽然使用 `Buffer`，也是由驱动持有上传协议。不要把百度、115、123、夸克、TeraBox 等盘的上传状态机上移到 `CloudDriveService`。

### 4.10.1 目标与非目标

- **目标**：在不破坏现有 `WebDavService` 对外 API 的前提下，为具备真实 `Put` 实现的云盘逐盘恢复写能力；小文件同步继续可走 `writeBytes`，大文件上传增加文件 / 流入口。
- **目标**：上传协议、鉴权、哈希、分片、秒传、完成轮询、错误翻译全部留在具体驱动；兼容层只负责路由、能力查询、输入适配、取消与进度传递。
- **目标**：复用 `AccountCaps.write`。它在本项目中的定义就是「上传 + 云端写同步」，不另造 upload 位；`mkdir` 继续使用独立位。
- **非目标**：不把 OpenList Worker 的 WebDAV/XML 层移植进 App；不为了上传恢复顺手接入用户已砍掉的 crack 下载 API；不让只读 / 分享 / 索引驱动出现伪写能力；不默认开放所有 OpenList Go 驱动。
- **当前产品边界**：先恢复驱动层能力与小文件写路径，再单独决定网络库「上传本地文件」UI、上传队列、云盘同步目标是否开放。

### 4.10.2 推荐接口边界

#### A. 输入源：文件优先，内存流兼容

建议新增通用 `CloudUploadSource`（名称待实现时确定），至少表达以下信息：

- `name`：远端文件名；
- `size`：已知文件大小，绝大多数 OpenList Put 都需要；
- `mimeType`：可选；
- `openRead()`：可重复打开的顺序流；
- `openRange(start, end)` 或等价的可重读能力：给百度 / 115 / 123 / 夸克等哈希校验、分片重试使用；
- `materialize()`：对不可重读的内存流落临时文件，避免驱动各自实现不同的缓存策略。

输入优先级：

1. **本地 `File` / 文件路径**：大媒体文件的首选，支持随机访问和重复读取，不把整文件放进 Dart 堆；
2. **`Stream<List<int>>` + size**：适合调用方已有流的场景，但必须在进入需要哈希或重试的驱动前确认可重读；
3. **`Uint8List`**：只作为 `writeBytes` 小文件适配，凭证、M3U8、曲库分片、备份小档案可用；不作为大文件上传的唯一接口。

OpenList Go 的 `FileStreamer` 会在需要时缓存到临时文件（例如百度快速上传 / 123 的哈希计算），Dart 侧应统一由通用输入适配层完成同样的事情，而不是让每个驱动各写一份内存转文件逻辑。

#### B. 驱动接口：驱动负责真实上传

示意边界（名称和返回值可在实现阶段调整）：

```dart
Future<CloudFileItem?> put(
  String dstPath,
  CloudUploadSource source, {
  void Function(int sent, int total)? onProgress,
  CancelToken? cancelToken,
});
```

- `CloudDriveService` 只做 `accountId → driver`、远程根路径拼接、能力检查、输入适配和异常边界；不出现 `if (type == 'baidu_netdisk')` 一类协议分支。
- `WebDavService.writeBytes` 继续是统一调用入口；云盘侧有 `write` 能力时转到 `CloudDriveService.putBytes`，无能力时保留明确的 `UnsupportedError`。
- 具体驱动内部可调用通用的 HTTP / 分片 / 哈希 helper，但 helper 不能认识具体盘名或账号配置。
- 需要返回远端对象的驱动实现 `PutResult` 语义时，返回 `CloudFileItem`；只需确认成功的驱动可以返回 `void`，由兼容层统一按成功 / 异常处理。

#### C. 通用上传设施（先于驱动落地）

建议放在 `lib/services/cloud_drivers/` 的通用文件中，不放进 `CloudDriveService` 的类型路由：

- 可取消的流式 HTTP PUT / POST，统一接 `Dio CancelToken`；
- `onSendProgress` 到统一进度回调的适配；
- `Content-Length`、`Content-Range`、multipart 表单和文件流的构造；
- 按分片读取本地文件，避免整文件内存占用；
- 分片失败重试、429 / 5xx 退避、上传会话过期后的重新初始化；
- MD5 / SHA-1 / SHA-256 的流式哈希和指定区间哈希；项目已有 `crypto`、`cryptography`、`pointycastle`，先复用，不新增原生依赖；
- 内存流不可重读时统一落临时文件，完成或取消后清理；
- 不把「所有分片并发」作为默认策略。OpenList Go 明确要求限制并发，否则会因待上传 chunk 缓冲造成内存增长；首版以串行 / 小窗口为主。

### 4.10.3 按 OpenList Go Put 形态的实现分类

| 分类 | 典型驱动 | OpenList Go 形态 | 方案 B 难度 | WDMM 落地策略 |
|---|---|---|---|---|
| **G0：只读 / 无 Put** | `*_share`、`openlist_share`、`github_releases`、`autoindex`、`emby`、`google_photo`、`quark_uc_tv` | Put 桩、缺失或语义上没有写路径 | 不适用 | 保持只读能力，不能因为接口新增 put 就默认开放 write |
| **G1：简单单请求上传** | WebDAV、`alist_v3`、`openlist`、`yandex_disk` | 先获取目标 URL 或直接调用远端 `/api/fs/put`，流式 PUT/POST | 低 | 作为通用上传设施和输入源的验证批次；WebDAV 复用已有客户端 |
| **G2：预签名 / 分片 URL** | `aliyundrive_open`、`onedrive`、`onedrive_app`、`google_drive`、`dropbox` | 建立上传会话，获得 URL，按分片 PUT/POST，完成会话 | 中 | 驱动负责会话与回执，通用层只负责字节搬运、进度、取消、重试 |
| **G3：哈希秒传 + 分片状态机** | `baidu_netdisk`、`terabox`、`123_open`、`quark_open`、`quark_uc` | 预计算 MD5/SHA-1，秒传尝试；失败后 precreate / uploadid / 分片 / complete | 中高 | 必须使用可重读文件源；先移植 Go 语义，再用 Worker 做请求形状交叉核对 |
| **G4：哈希 + 二次校验 + OSS / 自有签名** | `115open`、`pikpak`、部分国内盘 | 首 hash、指定区间 hash、获取临时凭证、OSS 或签名上传、回调确认 | 高 | 将签名和二次校验留在驱动；真机验证风控、过期凭证和大文件 |
| **G5：包装 / 加密上传** | `crypt`、`chunk` 等 | 先转换内容或文件名，再委托内层 Put | 高 | 基础源具备 write 后再做；crypt 只按源能力动态暴露 write，不能无条件继承 |
| **G6：协议 / 自有加密栈** | `sftp`、`smb`、`ftp`、`mega`、`proton_drive` | 非 HTTP 或包含自有加密 / 会话协议 | 高 / 很高 | 不作为本轮上传恢复目标，单独评估依赖、后台执行和安全性 |
| **G7：对象存储** | `s3`、`uss`、`azure_blob`、`bunny_storage`、`ipfs_api` | SDK、签名 PUT、multipart 或 API add | 中高 | 作为独立 P5；先确定是否有真实用户场景，不因“协议简单”提前铺开 |

### 4.10.4 具体驱动清单与难度

#### 第一阶段：地基与低风险验证

| 驱动 / 模块 | 难度 | 依据与材料 | 先做什么 |
|---|---:|---|---|
| 通用 `CloudUploadSource` | 中 | `CloudDriver`、`CloudDriveService`、OpenList `FileStreamer` | 先实现 File / Uint8List / 可重读 Stream 三种适配；补取消、size、临时文件清理测试 |
| 通用 HTTP / multipart / chunk helper | 中 | OpenList `driver.Put` 注释中的取消、进度、限速要求 | 不绑定盘名；先做单请求、分片读取、哈希、重试；限制并发 |
| WebDAV 写路径 | 低 | `webdav_service.dart:355-376` 已有 `writeBytes`；现有 WebDAV client | 用现有 WebDAV 行为验证新输入源和进度，不先改变云盘能力表 |
| `alist_v3` / `openlist` | 低 | Go `drivers/alist_v3/driver.go`、`drivers/openlist/driver.go`：`PUT /api/fs/put` + `File-Path` | 如果未来接入，作为 HTTP 流式上传模板；当前仍受 4.9 范围约束 |

#### 第二阶段：首批云盘上传

| 驱动 | 难度 | OpenList Go 关键步骤 | 必须准备的材料 | 验收重点 |
|---|---:|---|---|---|
| `aliyundrive_open` | 中低 | create file → part info → get upload URL → 分片 PUT → complete | `drivers/aliyundrive_open/upload.go`、`types.go`、现有 Dart driver；有效 refresh token；至少一个可写测试盘 | 小文件、大文件、断点 / 取消、token 过期、分片失败重试、重复文件 |
| `baidu_netdisk` | 中高 | rapid upload → precreate → slice MD5 → superfile2 → create；空文件拒绝 | Worker `driver.ts` 上传段、Go `driver.go` / `util.go`；MD5 向量；百度测试账号；upload API 字段是否重新暴露需单独确认 | 秒传命中、秒传失败后真实上传、uploadid 过期、动态域名、空文件、目录与文件名 |
| `terabox` | 中高 | locateupload → precreate → 分片 superfile2 → create；Cookie + UA | Worker `driver.ts` 上传段、Go `driver.go`；已有 `genSign` 测试；可用 Cookie 和地区可用账号 | Cookie 过期、地区错误、分片 MD5、不完整上传清理、重试 |
| `115open` | 高 | UploadInit：全 SHA1 / 首 128K / sign_check → upload token → OSS PUT / callback | Worker `driver.ts` `ossPutObject`；Go `upload.go`；OSS V1 签名材料；可写 refresh token | 秒传、二次校验区间、签名头、空文件、大文件流式、凭证过期、上传失败后远端残留 |
| `123_open` | 中高 | SHA1 秒传 → create → MD5 etag → 分片上传 → complete 轮询 | Go `drivers/123_open/driver.go` 上传段；Worker 仅作请求格式参考；refresh token | 秒传、分片、complete 轮询、20103 等未知响应、超时取消、上传后重新 list |

> 这五个驱动不能按“Worker 是否有 put”简单筛选：`123_open` 的 Worker Put 是因 stateless 环境限制而砍掉，Go 版才是本地 App 应采用的语义；`115open` 的 Worker 单 Buffer OSS 形态也不能直接照搬为大文件实现。

#### 第三阶段：包装与复杂协议

| 驱动 / 模块 | 难度 | 结论 |
|---|---:|---|
| `crypt` | 高 | Go 版是 EncryptData → 重新构造密文对象 → 内层 `op.Put`。WDMM 要补可写 `CloudSource`、内容加密输出、密文大小 / 文件名映射和源能力传递；必须保证源无 write 时 crypt 仍只读 |
| `quark_open` | 高 | Go 版需要 MD5/SHA1、预上传、分片 URL、etag / commit；Worker 桩不能作为上传依据；MustProxy 只影响读取，不阻止上传 |
| `quark` / `quark_uc` | 高 | 与 `quark_open` 类似，额外有 Cookie / 账号形态差异；等待 quark_open 的通用分片和签名材料收敛后再做 |
| `139` | 很高 | Go 版按 PersonalNew、Group、Family、旧流上传等多形态分支；Worker 只有空壳；先完成字符集与账号形态核验再排期 |
| `netease_music` | 高 | Go 版 `putSongStream` 要缓存完整文件、检查存在、分配 token、上传、发布信息；Worker 没有可用上传底稿；技术可行但不纳入第一轮 |

#### 第四阶段：OAuth、协议和对象存储

- **P3 OAuth**：`onedrive` / `onedrive_app` / `google_drive` / `dropbox` / `yandex_disk` / `pikpak` / `thunder` 等，上传协议本身多为标准会话或预签名 URL，难度中；真正的前置是 OAuth 回调、刷新和移动端后台生命周期。建议先完成一个 OneDrive 小文件 + 大文件会话模板，再批量展开。
- **P4 协议类**：WebDAV 可低成本复用；`sftp` / `smb` / `ftp` 需要独立协议栈；`mega` / `proton_drive` 包含自有加密与会话，单独立项，不和 HTTP 上传混做。
- **P5 对象存储**：`s3` / `uss` / `azure_blob` / `bunny_storage` / `ipfs_api`。需要准备签名、multipart、临时凭证和大文件测试材料；只有确认真实用户需求后再做。

### 4.10.5 分阶段实施计划

| 阶段 | 内容 | 完成判据 |
|---|---|---|
| U0 | 决定恢复上传的产品边界；确认 `write` 仍同时表示上传和同步；确定上传是否需要独立队列 | 用户确认：是否开放网络库本地文件上传；是否允许云盘成为同步 / 备份目标 |
| U1 | `CloudUploadSource`、File/bytes/stream 适配；临时文件；取消、进度、size；通用 HTTP helper | 单元测试覆盖空流、短读、不可重读流、取消、临时文件清理；WebDAV 行为不变 |
| U2 | WebDAV 走新输入源；恢复 `CloudDriveService.putBytes/putFile` 路由，但云盘仍按能力位关闭 | WebDAV 上传、覆盖策略、错误、进度、取消通过；无 write 云盘仍明确失败 |
| U3 | `aliyundrive_open` 或 `baidu_netdisk` 首盘上传 | 真机：小文件、大文件、取消、失败重试、重复名、刷新列表；Go / Worker 请求形状有测试锁定 |
| U4 | `terabox`、`115open`、`123_open` 逐盘落地 | 每盘一个测试文件；秒传 / 非秒传 / 分片 / 过期 / 错误原文 / 上传后 list 验收 |
| U5 | 恢复云盘 `write` 能力遮罩；按能力决定 `writeBytes` 与 `ensureDirectory`；再讨论同步、备份、歌单目标放开 | 无能力按钮隐藏；有能力按钮可用；恢复旧配置不改变；WebDAV 回归通过 |
| U6 | `crypt` 可写透传 | WebDAV / 一个云盘作为源分别验证明文→加密上传→重新读取解密；坏密文不得误报成功 |
| U7 | P3 / P4 / P5 按用户需求独立批次 | 每批 2–4 个驱动；OAuth / 协议依赖单独验收，不与 U3/U4 混合提交 |

### 4.10.6 每盘都必须准备的测试材料

1. **可写测试账号**：独立目录、非主账号；支持删除测试文件；记录账号类型与远程根路径。
2. **固定测试文件集**：0B、1B、空白文本、非 ASCII 文件名、1 个小于分片大小的文件、跨分片边界文件、较大媒体文件；MD5/SHA1 固定值写入测试说明，不写入凭证。
3. **OpenList 对照材料**：Go `driver.go` / `upload.go` / `util.go` / `meta.go`；Worker `driver.ts` / `util.ts` 仅作为请求形状和字段参考；Go 行为优先。
4. **失败注入**：取消首片 / 中间片 / complete 轮询；模拟 401、403、404、409、429、5xx；模拟 token 过期、uploadid 过期、直链过期。
5. **一致性校验**：上传成功后重新 `list` / `get`，核对名称、大小、修改时间和可读链；对 crypt 还要核对密文大小与解密内容逐字节一致。
6. **安全材料**：覆盖策略、远端残留清理、凭证不进日志、上传 URL / OSS 签名不落库；测试账号与 token 不进仓库。

### 4.10.7 能力、UI 和同步边界

- 驱动只有在 `put` 真实实现、测试通过、且当前批次决定开放时才给 `AccountCaps.write`；上游有 Put 不等于本项目自动开放。
- `writeBytes` 与 `putFile` 都必须经过同一个能力检查；不能只在 UI 隐藏而在服务层放行，也不能只在服务层报错而 UI 仍显示入口。
- `ensureDirectory` 继续单独检查 `AccountCaps.mkdir`；拥有 `mkdir` 不代表拥有 `write`。
- `CloudDriveService` 不按类型实现上传协议；只调用 `driver.put`。驱动私有的 hash、签名、分片和错误翻译留在 `cloud_drivers/<name>_driver.dart`。
- 账号配置中新增的上传专用字段必须进入对应 spec；秘密字段按 `secretFieldKeys` / `runtimeSecretKeys` 规则加密；上传临时 token 不得当成用户配置持久化。
- 上传恢复后，`sync_service.dart` / `sync_screen.dart` 仍需单独决定是否把云盘列入同步目标；不要因为 `write` 位恢复就自动改变用户现有 WebDAV 同步选择。

### 4.10.8 未决问题

1. `CloudUploadSource` 是否直接依赖 `dart:io File`，还是抽象出可在桌面 / Web 端复用的随机访问源；当前产品 Android-first，倾向 File-first。
2. 上传队列是否复用 `download_queue_service.dart` 的数据库与通知模型，还是先以同步调用完成小文件写入；建议先做同步调用，网络库大文件上传再单独建队列。
3. 覆盖策略是否统一为 `overwrite / skip / rename`，还是逐盘照 OpenList 默认值；在统一策略未定前不开放批量上传。
4. 分片并发默认值、后台保活、断点续传是否首版纳入；建议首版串行或小窗口，先保证正确性与可取消。
5. `crypt` 加密输出是否完全复用现有纯 Dart cipher，还是等待 libsodium FFI；上传功能不应在 FFI 未落地前偷偷引入第二套格式。

> 本节的核心顺序：先做输入源和通用传输地基，再做一个低风险上传驱动，随后按「哈希秒传 / 分片状态机 / 签名与二次校验 / 包装加密」逐类扩展。不要先在 `CloudDriveService` 堆一套按网盘类型分支的上传逻辑。

## 5. 待修复的语义冲突（用户语义 vs 实际代码）

用户语义本该成立、但当前代码不满足（或暂时搁置）的冲突。每条写明用户原话、现状、指向的固定文档小节与代码位置；修复后按 [00 §1](00-INDEX.md) 的收口规则把语义搬进对应正文，本节删除该条。

### 5.1 后缀改过的音频走错播放页（用户已报，暂不处理）

- **用户语义**：文件实际是音频（如 `.m4a` 改名成 `.mp4`），点开应该进音乐流式播放页，而不是视频播放页。
- **现状**：路由按**后缀**判定（[02 §2](02-NETWORK-LIBRARY.md) 的动作模型），不看实际内容；改过名的音频进视频页。
- **代码位置**：`network_library_screen.dart` 的 `_activateItem` / `_defaultActionFor`（后缀 → `FileCategory` → 动作）；类别判定在 `FileTypeConfig`。
- **搁置原因**：内容嗅探（读文件头）要在打开前多一次 Range 请求，慢速源上会明显拖慢点开；用户此前同意暂不处理。

### 5.2 下载完成后用户看不到「实际落在哪里」（部分修复，语义未完全满足）

- **用户语义**（真机反馈）：下载队列里「系统目录：content://xxx」对用户没用且不能反映实际下载地址，应删掉；用户要的是**可理解**的位置信息。
- **现状**：无意义 URI 已从队列删除（`downloads_screen.dart`）；但「系统相册/下载目录」这两个目标在系统里的真实位置（如相册的 `Movies/WebdavMediaManager`）只在 [02 §7](02-NETWORK-LIBRARY.md) 有文档语义，界面没有向用户展示任何位置描述。
- **差距**：若用户再报「不知道去哪找文件」，考虑在完成态补一行人类可读位置（如「已存入系统相册 › Movies/WebdavMediaManager」），不要回到原始 URI。

## 6. 存储层合并（T1 / T2 / T3 全部完成）

本地数据现状全景（T2 落地后 `music_library.db` 已是 **v9**）：**4 个介质**——3 个 SQLite 库（`music_library.db` v9 / `download_queue.db` v6 / `playlists.db` v1，均在 `getApplicationDocumentsDirectory()`）+ SharedPreferences（settings 57 键 / `active_account_id`）+ secure storage（`webdav_pass_*` / `cloud_driver_cfg_*` / vault 口令）。目录侧 `covers/` `music_cache/` 是文件不是数据库。

**已落地（T1 + T3，squash 合入 main，`8fee224`）**：cache group 成员表与 `touch()` LRU 时间戳从 prefs 迁入 `music_library.db`（`cache_groups` / `cache_access` 两张运行态表）；`cue_albums.cache_group_id` / `download_tasks.cache_group_id` 维持「每行归属」不动。

**已落地（T2，分支 `feature/storage-annex-b`）**：选了第三条路——**不搬 annex 表，直接删掉**。考古发现它的每一列都是可推导 / 无读取方的（`local_path` 恒等于 `fileForRemote` 推导值、`etag`/`size_bytes` 死列、`cached_at` 备份时硬编码空数组），于是「已缓存」改为**对推导路径的一次惰性 `File.exists`**（v9，[01 §3](01-DATA-MODEL.md)）：

- 分片同步、`onUpgrade` DROP 连坐、备份导出特例三个耦合点**全部消失**（表没了）。
- 启动 `reconcileStaleAnnex`（每行一次 stat）删除；惰性验证不可能 stale。
- `deleteTrack` / `deleteTracksForSource` 不再连带删 annex 行；`markAllUncached()` 留 no-op 兼容备份恢复调用点。
- 代价：`etag` 远端变更检测从未实现过（列本来就是死的），无实际损失。

**真机验收未做**（跨 T1+T2）：老库升级（v7→v9）后 CUE 组删除、按保留期自动清理、已缓存标记在升级后是否正确显示（靠推导路径自动恢复）。

### 6.1 不合并的（现状已合理，勿动）

- **playlists.db 独立**：文件头注释即约定「Independent from audio cache — never wiped by CacheService cleanup」；且有远端 M3U8 镜像层，生命周期独立。
- **download_queue.db 独立**：瞬态任务队列（重试 / 进度），与曲库标签无外键关联（`taskForRemote` 靠 `source_name + remote_path` 运行期对上，不落库 join）；合并会让「销毁音乐库」触碰队列服务。
- **凭证在 secure、账号元数据在 SQLite**：密文 vs 可同步明文，职责分界正确。
- **music_library.db 内 8 张表**：tracks / cue / deleted / sync_state 是同一次 `onUpgrade` DROP 重建的原子单元，强绑定有意为之；`cache_groups` / `cache_access` 是 v8 新增的运行态表（见 [01 §2](01-DATA-MODEL.md)）。

### 6.2 明确不做

- cache 表迁往 download_queue.db 或独立 cache.db：**被 T2 的删除方案取代**——比搬家更彻底，运行态寄生问题连根拔掉。若未来需要 `etag` 远端变更检测，再立新项（届时放 download_queue.db 侧）。
- prefs 57 个 settings 键不搬 SQLite：真·配置数据，KV 合适、无关系语义。
- `sync_state` 游标不并入 prefs：跟 tracks 的 rev 时钟强耦合（[01 §6](01-DATA-MODEL.md)），同库 DROP 重建是对的。
- 三个 SQLite 合成一个库：备份 / 销毁 / 清缓存三类操作的正交性就是靠库边界划的，合并是倒退。
