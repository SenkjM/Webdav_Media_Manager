# 99 · 开发中文档

只记录**正在开发**的功能的原始语义：需求原话、取舍、临时决定、还没定型的实现。
用法与收口规则见 [00-INDEX.md](00-INDEX.md) 的「完整文档与开发中文档」。

- 开发新功能前**先读本文件**，再读每一条链接到的完整文档。
- 下面**按功能 / 项目分节**，不按「已完成 / 待验收 / 取舍」这类状态分类；每条自己的状态写在它的开头。
- 自动化的做完是代码门槛：`flutter analyze` 干净 + `flutter test` 全过；当前 `main` 的真机状态默认按通过处理，只有新的可复现问题才记录为进行中事项。
- 开发完成后：删掉这里的条目，把语义按完整文档的写法补进对应功能块，并去掉占位。

## 1. 音乐流式播放（界面优化未开工；预载与封面已实现）

**状态**：已初步实现并推 `main`。新安装的音乐流式开关默认开，单击动作仍是缓存音乐，不是流式；已经保存过单击动作的安装保持原选择。语义写在 [05 §9](05-AUDIO-PLAYBACK.md) 与 [06](06-VIDEO-PLAYBACK.md) 的对比表里。**界面优化（§1.1）还没做。预载与封面已按 §1.2 落地。**

**当前 main 状态按已通过收口**：后台切换、锁屏控制、耳机按键、断网、切回本地播放。

- 2026-10-03：进入 `MusicStreamScreen` 的首帧回调调用 `AudioPlayerService.pauseForVideo()` 暂停本地音乐并保留队列；页面销毁只停远端流，不自动恢复本地播放。
- 2026-10-03：标题下的「流式传输 · 未缓存」已去掉。键 `streamingNotCached` 从 `app_zh.arb`、`app_zh_TW.arb`、`app_en.arb` 删除（没有 ja 等其它 locale），`MusicStreamScreen` 不再显示这行。流式缺封面仍是 `_buildCover` 里原来的 `ColorScheme` 占位，这一轮没有重画。

**已知粗糙处（优化的候选，都还没有具体方案）**：

- 离开音乐流式页会 `VideoPlaybackService.stop()`，而它内部是 `exitVideoMode()`——语义是「**恢复**本地音乐队列」。所以停下流式歌时通知栏会跳回之前暂停的本地歌。要更干净，得让远端流用途参与 `exitVideoMode` 的分支判断。
- **没有屏幕常亮**：项目里没有 wakelock 依赖；视频页的常亮来自 `media_kit_video` 的 `Video` 组件，音乐页刻意不建它。
- **时长不单独解析**：进度由播放器自己报。封面按 §1.2，用 Range 读内嵌图或同目录图片，不把整首音频下下来找图。
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
2. **封面占位样式**：这一轮界面重排**不改占位的画法**（尺寸自适应、圆角、阴影、强调色渐变图标仍是未做的视觉项）。内嵌图和同目录封面已经按 §1.2 显示在现有 200×200 区域里；找不到图时仍是原来的占位图标。
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
### 1.2 流式音乐播放的预载与封面（已实现，路线 A）

**用户原话**：「流式音乐播放的预载功能，自动加载向前 x 首向后 y 首，可在配置页面配置。」同目录封面开关和可编辑的封面文件名也放在同一页。

**放哪**：设置 → 音频流式（`audio_stream_settings_screen.dart`）。

**已定并落地的行为**：

- 路线 **A**：共享 media_kit `Player` 的列表是「已打开过的曲目」，切歌用 `jump`，不靠 `player.open` 清空列表。第一次进入这一页（以及视频页把同一播放器的列表换掉之后回到这一页）只对**当前**一首 `open` 一次。视频页仍可能换掉列表；回到流式页会重建窗口。
- 预载窗口两个整数，设置键 `audio_stream_prefetch_backward`（向前，上一首方向）和 `audio_stream_prefetch_forward`（向后，下一首方向）。默认都是 1，范围 0–5。0 表示该方向不预载。队首队尾不绕圈；队列短于窗口就用现有的几首。
- 当前播放占一条网络。这条播放流不因为预载暂停或取消。预载共用第二条，不进下载队列，也不并行。同一轮在这一条线程上先补封面，再下音频。
- 封面窗口和音频窗口相同：当前这首，加上向前 N 首、向后 M 首（先向前，再向后，不绕圈）。先取当前这首的封面并显示。然后逐首补窗口里其余曲目的封面，一次只处理一首；音频已经在播放列表里、或音频缓存已经完整的邻居，封面仍然要补。某一首封面失败只记在这一轮并继续下一首，不让后面的音频预载永远开始不了，也不打断正在播放的那首。邻居封面只进缓存，不更新界面，也不改当前会话的封面。之后切到这首时，当前封面路径命中已有文件，不再发请求。窗口里的封面都已缓存或这一轮已失败之后，才开始邻居音频。
- 邻居音频仍是整文件、一次只下一首，先向前再向后。已经在播放列表里、这一轮已经打开过、或者缓存文件已经完整的，不再取。刚播完的那首留在列表里，滑进向前窗口时也不会再下。音频失败记一笔后继续，不打断当前这首。切歌、窗口变化，或音频文件还在下但窗口里仍有封面没处理时，取消的是这条预载中的音频文件，先把封面补完再继续音频。
- 预载文件（音频和图片）在 `getApplicationCacheDirectory()/prefetch_cache`。每次启动、播放器创建之前清一次。滑出窗口不删，页面 dispose 也不删。不完整的文件先写 `.part`，成功后再改名。
- 封面顺序（当前和邻居相同）：曲库里已有的封面文件（有则直接用，不走网络）→ 预载缓存 `covers` 里已经完整的文件（不走网络）→ 按**文件头**判断格式再 Range 取内嵌图（`coverFront` 优先，否则第一张）→ 同目录封面开关打开时按文件名匹配一张图 → 否则占位。后缀不可信：`ID3` 或 MP3 帧同步、`fLaC`、偏移 4 的 `ftyp`、`OggS`、`RIFF`+`WAVE`。其余（含裸 AAC）当没有内嵌图。只发 Range；服务器不按区间回（不是 206）就放弃，不把整首当封面下载。FLAC / MP3 / OGG 的图靠近文件头。M4A 的 `covr` 在 `moov` 里，头上没有就再取尾部。失败保持播放和占位图。
- 同目录封面默认**关**。设置键 `audio_stream_sidecar_cover`。只看同一层，不进子目录。名字大小写不敏感。默认可编辑列表是 `cover, folder, front, album`（键 `audio_stream_sidecar_names`）；音频文件自己的主文件名始终额外试一次，不写进这份列表。扩展名只认 jpg、jpeg、png、webp。同名只是扩展名不同时按这个顺序挑一个，其它扩展名忽略。能用扫描时已经拿到的目录列表就用，否则只对该目录再列一次。只下载选中的那一张图。

**仍不做**：不把预载写成「尽量播完不卡」的缓冲策略；`bufferSize` 没动。不提供「永久保留预载缓存」开关。§1.1 的界面重排仍未开工。

## 2. 主题配色（设置里已可切换；非整库换色）

相关完整文档：[09 §编码约定](09-MISC.md)、[05](05-AUDIO-PLAYBACK.md)、[06](06-VIDEO-PLAYBACK.md)、[07](07-NOTIFICATIONS.md)。待发布与拆分见 本文件对应章节。

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
- 自定义配色：2026-10-02 已拍板，见 §2.5。只改种子色，不开放整套色板。
- 裸颜色审计与收敛，按类判断：哪些该跟主题、哪些本来就该固定。

### 2.4 验收与回归点

- 纯黑播放器页、下载进度 / 状态色、封面占位在两种模式下都要可读；`docs/05`、`06`、`07` 的界面描述要跟着补。
- 阶段一落地后跑 `flutter analyze` 与 `flutter test`；阶段二补设置项相关的测试。


### 2.5 交接

本轮的 MD3 界面改造交接单（分支、worktree、逐文件改动点、本轮不改清单）已移到 [97 §H-001](97-AGENT-HANDOFF.md)。

本节只保留方向与验收：§2.1 现状、§2.2 为什么不能只打开 `themeMode`、§2.3 两阶段拆分、§2.4 验收与回归点。执行侧的交接单仍在 [97](97-AGENT-HANDOFF.md)。下面只记已经落地、并入 `feat/l10n-leftovers` 的结果，不再把未做的交接清单回填到这里。

### 2.6 本分支实际结果（feat/md3-theme，已并入 feat/l10n-leftovers）

- 三态主题存在 `SettingsService` 键 `theme_mode`（`light` / `dark` / `system`）。没有存过的安装仍是浅色。`main.dart` 读这个值，不再写死 `ThemeMode.light`。
- 种子色是一个不透明 ARGB，键 `theme_seed_argb`，默认 `0xFF2EC4B6`。浅色和深色都用 `ColorScheme.fromSeed`（`DynamicSchemeVariant.fidelity`，不是 Expressive）生成。`onPrimary` 来自方案。设置页在「杂项」里用现有列表行放三态下拉和种子色（当前色块 + 预设 + 色相/饱和度/明度）。
- 抽屉、设置页分区标题、以及 `AppTheme` 里的组件色跟当前种子走。非播放器页面的脚手架和卡片底改为当前 `ColorScheme.surface` / `surfaceContainer`，默认种子和自定义种子都跟着走；这些页上原来写死的深色字改成 `onSurface` / `onSurfaceVariant`，避免深色底上看不见。播放器页、流式页、视频手势和黑白叠层、图片页码、迷你播放条、封面占位、缓存和下载队列服务没改。
- 次要信息行用 `MetaText`：`bodySmall` + 当前方案的 `onSurfaceVariant`。默认种子和后来改的种子、浅色和深色都走这一条，不靠写死的 `AppColors.mutedText`。点名位置：网络库目录行去掉「目录」；有大小只显示大小，没有大小才留类别；「点按下载」和已存相册留下。歌单 / 艺人 / 专辑 / 标签数量仍是「{count} 首」（专辑仍可带艺人）。下载队列 CUE 数量改成「{count} 首」，没有曲目时类别改成「CUE」。CUE 弹层标题收成数量。歌单缺歌行收成「暂无 · 来源」。文件夹选择和字幕目录只显示末级路径。播放器页没改，流式页仍用原来的「{count} 首」。
- 流体玻璃没有进产品。`BackdropFilter` / `ImageFilter.blur` 在 Flutter 3.47 上不用新插件就能用，也不必碰到 `media_kit`。不发的原因：应用栏和页面底现在是不透明的平面（圆角和紧凑密度要留着）；模糊只有内容滚到栏下才看得见，那时文字对比会跟着封面和行色变，保证不了；设置页底下没有可模糊的内容，要做出玻璃得另铺一层装饰，等于换外观；滚动列表上的 `saveLayer` 成本在这台没有 ColorOS 16 真机的环境里没法量。所以应用栏和脚手架背景保持不透明。
- 预览只加了 `lib/preview/md3_widget_previews.dart`（`@Preview`，`kDebugMode`）。`main.dart` 和正式页面不引用它。`.widget_preview/` 本来就在忽略列表里。预览里有主题设置控件，以及文件夹行、一条带大小的音频行、一条歌单数量行。没有把整页拆成「一帧数据 + 动作接口」。没拆的页面：音乐库、歌单、歌单详情、网络库、下载、同步、账号、其余设置页、文件夹选择、字幕选择、正在播放、图片查看。播放器三页本来就不进预览。

### 2.7 播放器与流式页的深色残留（本分支补了一轮，只改颜色）

视频设置页脚手架本来就是 `ColorScheme.surface`，分区标题仍写死 `AppColors.accent`，已改成 `primary`。仍是浅色底、不跟主题的还有：视频控制条、倍速 / 字幕 / 手势 / 队列弹层、退出确认、流式音乐页、本地正在播放（含迷你条和详情弹层）、下载设置里的白字说明。这些改成 `surface` / `onSurface` / `onSurfaceVariant` / `outline`，强调用 `primary`。

没动：贴在画面上的字幕字色和黑底、视频黑边、缓冲 / 切集 / 快进提示、手势分区、进度条怎么拖、封面模糊参数和图片本身、图片查看页、封面占位、`cover_image.dart`、缓存和下载队列行为。本地正在播放的白蒙层只在深色时换成 `surface`（透明度仍是 0.82），亮色仍是原来的白。

播放器字幕弹层加了和设置页相同的字号：预设 12、14、16、20、24、30，滑条 10–40，默认 16。两边都写 `SettingsService.videoSubtitleFontSize`。占位符参数顺序是生成代码的字母序（`max`, `min`, `size`）。

### 2.8 浅色取色偏暗（流式音乐页）

没换变体。`DynamicSchemeVariant.fidelity` 仍生成深色，也仍是浅色的起点（种子彩度不被压成粉彩，不用 Expressive）。浅色偏暗是 fidelity 本身：`primary` 被压到色调约 40（种子更暗时更低），`primaryContainer` 钉在种子色调上。换 `tonalSpot` 抬不高 `primary`（还是约 40）。所以只在 `fromSeed` 之后抬浅色：表面色调上移（`surface` 到 99，容器大约 98–93），强调色至少到色调 68，主/次/第三容器至少到 90。白字对比不够时 `on*` 改成同色相色调 20 的深色字，对比仍不低于 4.5。深色不改。流式页的进度条和强调色跟着这套方案变亮，没有单独刷白。没动模糊、封面图、进度条手势。

### 2.9 曲库缺封面占位跟主题（本分支）

`CoverArt._placeholder` 不再写死 `AppColors.elevatedHigh` / `AppColors.mutedText`。底色用 `colorScheme.surfaceContainerHigh`，图标用 `colorScheme.onSurfaceVariant`，深色模式和种子色都跟着走。`PlayerCoverArt`、迷你条、正在播放队列在没有封面时共用这个占位，只跟着改颜色，其它样式不动。`MusicStreamScreen._buildCover`、`Image.memory` / `Image.file`、圆角、`LibraryCoverArt` 的分辨率、`cover_image.dart` 没动。


## 3. 多语言（已分析，未决定，未开工）


用户问「多语言怎么处理」，只做了查证与拆分：**没有动代码**。相关完整文档：本文件 §3。

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
| 0 | `flutter_localizations` + `l10n.yaml` + ARB + `MaterialApp` 接线 | 见 本文件 §3；key 命名规则必须在这一步定死 |
| 1 | 6.2 的三类结构性问题 | 做不完就替换文案 = 白干 |
| 2 | 按模块替换 944 条文案 | 线性体力活，一批一个 commit |
| 3 | 平台侧资源（应用名、通知渠道名） | 见 本文件 §3 |
| 4 | 语言切换（跟随系统 / 应用内切换 + 持久化） | 独立功能，可选 |

### 3.4 需要用户决定的三件事

1. 目标语言（中 + 英？）；2. 范围（全量还是先跑通一两个模块）；3. 要不要应用内语言切换。**未决定前不开工。**

## 4. 云盘 Provider（网盘直连驱动，进行中）

**用户决策原话**：「砍掉上传功能，采用路线B，尽量不要改动WebDavService」「按照A表全部删除」「B的话建立新的网络库功能列表，分类不同网络库支持的能力并在对应的按钮功能前加上检测，尽量保证WebDavService实现的功能全面，由账号对应的能力遮罩判断功能是否开启」「C中保留crypt列入待开发功能，其他的砍掉不进入文档」「netease_music加入待开发文档」「几个优先做的加入文档并开始讨论细节」。

相关完整文档：[02 §10 占位](02-NETWORK-LIBRARY.md)、[04](04-DOWNLOAD-QUEUE.md)（下载带自定义头）、[08](08-SYNC-AND-BACKUP.md)（云端写路径禁用）、本文件 §4（账号模型地基）。

### 4.1 路线与参照物

- **路线 B**：驱动层以 Dart provider 直连各家网盘 REST API。**不引入** worker 的 WebDAV/XML 协议层——WDMM 本身是 WebDAV 客户端，自己转 WebDAV 再解析回去是绕路。
- 参照实现已克隆到 `localdev/`（已 gitignore，不入库）：`OpenListTeam/OpenList-Worker`（TS，HEAD `a355867`，实现底稿）+ `OpenListTeam/OpenList`（Go main，语义兜底）。驱动代码与 worker 运行时零耦合（抽样 quark：`env.|KV|waitUntil|durable` 零命中），逐盘对接是机械工作。
- 下载模型天然契合：驱动 `get()` 返回 `FileItem{raw_url, raw_url_headers}`（直链 + 必需请求头），正好对上现有 `WebDavStreamSource{uri, headers}`（`webdav_stream.dart`）；视频流式与下载都走「直链 + 头」。

### 4.2 已定型的取舍

1. ~~**上传砍掉**~~（**2026-10-15 推翻**）：`CloudDriver` 接口已补 `uploadStream` / `ensureDirectory` 两个写原语，默认抛 `err.uploadStreamUnsupported` / `err.ensureDirectoryUnsupported`；**crypt 驱动已实现**，能力完全继承源（源可写 → crypt 可写）；其余 15 个云盘驱动维持默认抛错。兼容层 `CloudDriveService` 三个写方法全部转调驱动原语，删掉了 `if (driver is CryptDriver)` 特判与 `_writeDisabled` 常量。所有入口一律查 `can(accountId, AccountCaps.write)`，不再按 `providerType` 硬挡。`createFolder` 走独立「创建文件夹」位（见 7.2.3 / 7.3.2），baidu 支持。WebDAV 账号行为不变。
2. **`WebDavService` 对外 API 与行为不变**（14 个文件直接 import 它，全部零改动）。唯一接入缝：`_connFor` / `_resolve`（`webdav_service.dart:44-54`）之后按账号类型转调 `CloudDriveService` 同名方法。绕不开的配套：`WebDavAccount.providerType`（本文件 §4）；云盘凭证走 AccountsService + credential vault 独立通道，`configure()` 的 url/user/pass 形状不动。
3. **能力遮罩**：账号类型 → 能力集合，枚举定型为**列出 / 读取 / 写入 / 创建文件夹 / 移动 / 复制 / 删除**（列出默认拥有、不在用户界面显示；「创建文件夹」按用户决定从「写入」拆出独立位，上传与写同步仍归「写入」）。云盘类型由驱动静态给定；**WebDAV 账号的能力由用户在表单里配置**（默认全量）。网络库行操作与多选工具栏按钮**先查遮罩再启用**；新建文件夹按钮按「创建文件夹」位遮罩（网络库 AppBar 与目录选择器两处，已实现）；WebDAV 表单的能力勾选区已实现（读取 / 写入 / 创建文件夹 / 移动 / 复制 / 删除）。**静态表登记原则（用户决定）**：`AccountCaps.staticCaps` 只登记已落地驱动（当前仅 `baidu_netdisk`），未落地盘先记 7.3.2 的核查表，落地时照表抄。
  - **与 OpenList 的对比（本轮查证）**：它的每驱动能力标志只有传输侧（`NoUpload` / `OnlyProxy` / `NoLinkURL` / `PreferProxy`，`internal/driver/config.go`），**写操作没有能力位、不做按钮遮罩**——只读驱动（openlist_share 等）在操作时返回 `errs.NotImplement` 由前端弹错；WebDAV 层按用户权限位（WEBDAV_READ / WEBDAV_MANAGE）拦截。WDMM 按本项目「禁用即隐藏」的决策在按钮层遮罩，比 OpenList 更进一步，属于有意差异。
4. **驱动范围已定界**：除 4.3 / 4.4 / 4.5 / 4.9 列出的驱动外，其余一律不做，不进文档不展开。
5. **读取能力的绑定**（用户原话「缓存音乐、下载文件、浏览、播放、流式传输功能绑定到账号类型的读取能力」）：这五类功能都要求账号具备「读取」。
6. **禁用即隐藏**：能力被遮罩时，单文件「更多」菜单的对应条目与多选工具栏的对应按钮**隐藏而非置灰**；「更多」按钮本身只要还有可用条目就保留。
7. **账号表单定型**：第一行名称、第二行类型（默认 WebDAV），选类型后动态出该盘自身字段。WebDAV 在服务器 URL 之下新增「远程路径」（默认 `/`，空置视为 `/`），**云盘账号同样有远程路径**；保存时 URL 结尾 `/` 隐式清除（`configure()` 已有同样的 trim，表单层保持同一规则）。云盘字段默认照 worker `Addition` 原样保留以便对接，逐盘细节落实时询问用户。
8. **云端写目标唯一选择点**（2026-10-15 更新）：`sync_screen.dart`「① 选择网盘」下拉与 `SyncService.targetAccount`（含活跃账号兜底）**一律查 `CloudDriveService.can(id, AccountCaps.write)`**——只要账号有写能力就列入（含 crypt 包住可写 WebDAV 源的账号）；无写能力的账号不作为同步目标。早前「只认 WebDAV 类型」的硬编码已删除。
   - **账号凭证进备份 / 同步（用户决定，2026-07 追加，推翻本条早前的排除段）**：用户原话「同步与备份功能中的WebDav凭证改为账号凭证……除了原有的webdav备份字段，还应该备份其他类型的网盘凭证」「从云端恢复时静默过滤不支持的网盘类型」「加密凭证配置也同步到所有在配置界面默认为密码的数据」。落地：`credentials.json` 升 formatVersion 2（WebDAV 条目 + 云盘条目 `providerType` + `driverConfig`）；云盘配置里 spec 表单 `obscure` 字段（`CloudDriverSpec.secretFieldKeys`）逐字段 AESGCMv1 加密，其余明文；恢复端 `cloudDriverSpec(typeId)` 查不到的类型**静默跳过**（不报错、不建空壳账号）；备份归档的账号遍历同步放开（`BackupService.buildPayload`）。早前「云盘凭据不进备份（档案里没有 secure storage 的驱动配置，恢复不了）」的前提已消失——驱动配置现在随档案 / 凭证库走。细节收口进 [08 §2 / §5](08-SYNC-AND-BACKUP.md)。

9. **流式体验：界面先落地**（用户决定，已实现）：音乐与视频两条流式入口的跳转都**不等源解析**——网络库把解析交给页内 loader（云盘解析要列表 + filemetas + HEAD 三跳，原来会卡住整条跳转链），解析失败在页内错误态表达；「伪装成视频的音频」由视频页解析后 `pushReplacement` 去音乐页（复用同一队列 seed）。音乐页缓冲可视化（不改其它 UI 元素）：删除「已缓冲」文字，已缓冲区间 = 播放进度条**二级轨道**（实心）；源解析 / 起播前的老式等待缓冲 = 二级轨道铺满**左右渐变**（自定义轨道形状）。**账号表单保存流**（用户决定，已实现）：点保存不关弹窗，保存按钮变圈等待，校验（名称 / 重名 / 身份确认 / refresh_token / 云盘真连验证）在弹窗内完成；失败报错留在表单，云盘添加成功提示「成功添加（名称）」后随表单关闭。

10. **驱动自描述与注册表**（用户决定，已实现，4.2.10）：处理逻辑、能力遮罩、表单配置参数**全部收进驱动文件**（`cloud_drivers/<name>_driver.dart`：驱动 + Addition + `XxxSpec extends CloudDriverSpec`）；`driver_registry.dart` 是唯一注册点（对齐 OpenList 的 bootstrap/drivers）——**新增一个盘 = 新增一个文件 + 注册表加一行**。账号表单按 `spec.form`（`CloudDriverField` / `CloudDriverSwitchField`，支持 visibleWhenSwitch / enabledWhenSwitch 依赖开关）通用渲染，类型下拉读 `kCloudDriverSpecs`，保存校验与配置组装按 spec 声明的键 / 必填 / 默认值执行；兼容层 `CloudDriveService` 只查表（`cloudDriverSpec(typeId)`）做构造 / 校验 / 令牌 patch 持久化，`AccountCaps` 只剩通用位定义与 WebDAV 归一（`staticCaps` / `forType` 已删）。**接口层独立**：`CloudDriver` + `CloudFileItem` + `CloudDriverException` + spec 全在 `cloud_driver.dart`，不依赖账号 / 存储；crypt 这类中间处理层以后实现同一 spec，`create()` 包住内层驱动、注册即接入。顺带：远程路径提为通用字段（类型之后、动态区之前），百度动态区顺序变为 spec 声明序（refresh_token → 在线续期地址 → 本地刷新开关 → Client ID / Secret）。

### 4.3 首批驱动（优先做）

`aliyundrive_open`、`baidu_netdisk`、`quark`、`115open`、`123_open`、`onedrive`、`onedrive_app`、`terabox`、`139`。共同特征：refresh_token 或 cookie **粘贴式**登录、直链 + 必需头、写操作全、无重加密（worker 驱动 18–40KB）。实现底稿 `localdev/OpenList-Worker/src/backend/drivers/<name>/`，语义兜底对照 Go 版同目录。
**首个端到端驱动：`baidu_netdisk`**（用户有测试条件）；`aliyundrive_open` 顺延——缺少测试条件，发布后靠其他用户反馈验收。实现 baidu 时**砍掉 crack 下载 API**（`download_api=crack/crack_video`、`custom_crack_ua`、`getCrackLink` / `getCrackVideoLink`，只走官方 dlink）——用户决定。
注意：`139` 带字符集标记，真机要先验编码。

### 4.3.1 baidu_netdisk（已实现，当前 main 状态按已通过收口）

实现语义与取舍已收口进 [11 §10](11-CLOUD-DRIVER-PORTING.md)（动态区顺序、本地刷新开关、保存语义、存储映射、落点）。后续问题按当前 main 状态和用户反馈记录：

- 添加账号：换 token 成功；错误 token 原文报错不落库；保存全程（变圈等待 → 失败留表单 → 成功提示「成功添加（名称）」后退出）。
- 浏览：远程路径生效；解密名正确。
- 下载 / 缓存音乐 / 本地播放。
- 视频与音乐流式：直链 302 + UA `pan.baidu.com`。
- 本地刷新开关联动：**打开**时 online_api 变灰且出现 Client ID / Secret；**关闭**时 online_api 可编辑（极性修正后的可观察行为，见 [11 §10](11-CLOUD-DRIVER-PORTING.md)）。
- 写操作四件套：重命名 / 删除 / 移动 / 复制；新建文件夹按钮按「创建文件夹」位遮罩（能力位见 4.3.2）。
- **源被删后的恢复路径**（本轮修复，见 [11 §4](11-CLOUD-DRIVER-PORTING.md)）：源账号删除后 crypt 报错应显示**源名字**并提示可恢复；重新添加**同名**源账号后 crypt 直接可用（无需重建）。
- **加载失败重试纪律**（本轮修复，见 [02 §6](02-NETWORK-LIBRARY.md)）：源被删状态下网络库不得无限自动重试拖慢应用；连续 3 次失败后停在错误界面等手动重试；恢复网络后自动补一次。

### 4.3.2 mkdir（创建文件夹）能力逐盘核查（OpenList 源码，本轮查证）

- **机制**：Go 版把 MakeDir / Move / Rename / Copy / Remove / Put 做成 `internal/driver` 的**可选接口**（方法名是 `MakeDir`，不是 Mkdir），87 个驱动都有方法签名，只读 / 索引驱动在方法体里返回 `errs.NotImplement`（桩实现）；op 层 type-switch 调用。Worker TS 把 mkdir 做成 `StorageDriver` 必备方法，行为与 Go 一致——真实现或抛「not supported」。**两版能力面一致**（worker 是我们的实现底稿）。
- **首批 9 盘全部真实现 mkdir**（静态表 mkdir = 有）：`baidu_netdisk`（Go `driver.go:96` MakeDir → `create(path, 0, 1)` isdir=1，已验真；worker 同）、`aliyundrive_open`、`quark`、`115open`（worker `driver.ts:339` → `client.mkdir` 真调用，勿被「方法体含 throw」的粗扫误判）、`123_open`、`onedrive`、`onedrive_app`、`terabox`、`139`。
- **只读家族 mkdir = 无（桩）**：`115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`autoindex`、`github_releases`、`lenovonas_share`、`google_photo`、`quark_uc_tv`、`emby`；`url_tree` 疑似桩（落表前再确认一次）。
- **已落地盘的能力位实录不再留在本表**：见 [11 §10](11-CLOUD-DRIVER-PORTING.md)（baidu_netdisk）、[11 §11](11-CLOUD-DRIVER-PORTING.md)（netease_music，`list | read | delete`——除删除外四个写方法上游全是桩）、[11 §12](11-CLOUD-DRIVER-PORTING.md)（粘贴凭证直连盘批次：123_open 无 copy，其余三盘五项全）与各驱动实录节。
- **未落地**：`crypt` 透传内挂驱动，落表时按宿主动态给位、不进静态表。
- **登记**：已落地 → `AccountCaps.staticCaps`；未落地 → 本表，落地时照表抄（用户决定：写代码会影响运行的先只进文档）。

### 4.3.3 netease_music（已实现，当前 main 状态按已通过收口）

实现语义、加密对齐与取舍已收口进 [11 §11](11-CLOUD-DRIVER-PORTING.md)。后续问题按当前 main 状态和用户反馈记录：

- **添加账号**：粘贴含 `__csrf` + `MUSIC_U` 的 Cookie → 真连校验（拉一页列表）通过才保存；Cookie 不全时表单内联报错且不出网；Cookie 过期（`code 301`）时提示「Cookie 可能已过期」、不落库、表单内容保留。
- **浏览**：云盘歌曲以平铺列表出现（无目录层级）；远程路径只作虚拟前缀，改名后账号条目仍可打开。
- **下载 / 缓存音乐 / 本地播放**：直链由网易 CDN 给出，能正常下载与播放。
- **音乐流式**：VIP / 版权受限 / 已下架的歌曲要给出可读错误（不是空 URL、不是 0B 文件）。
- **删除**：列表里删一首歌 → 云端确实少一首；再刷新列表确认。
- **能力遮罩**：账号行**看不到**新建文件夹 / 重命名 / 移动 / 复制入口（隐藏而非置灰）；删除入口可见可用。
- **`song_limit`**：填小值（如 5）后列表只剩 5 首；非法值回落 200。
- **`weapi` / `linuxapi` 真连**：若网易改签（返回 `code -460` 之类），报错要带 code 与 message 原文，便于判断是风控还是实现问题。

### 4.3.4 第二批四盘（已实现，真机验收通过——用户确认，123_open 打开目录报 invalid_grant 已按用户决定不排查）：123_open / aliyundrive_open / 115open / terabox

按 4.9 的评估与 [13](13-DRIVER-BATCH-PLAN.md) 的筛选标准（粘贴凭证、有直链、无重加密、写方法真实现、单账号形态、worker 底稿完整）选出的快速批次，四盘全部走 [12](12-DRIVER-PORTING-GUIDE.md) 的工序（解耦检查 → 六步接入 → 一盘一测试）。语义与取舍收口进 [13 §4](13-DRIVER-BATCH-PLAN.md) 的字段清单与 [12](12-DRIVER-PORTING-GUIDE.md) 的表单/能力位规则。**共同语义**：直链必需头进 `rawHeaders`；`access_token` 只作缓存经 `onTokenUpdate` 持久化、不进表单；上传/排序字段不进表单；错误原文透传 `CloudDriverException`；`get()` 拿不到直链抛真实原因（不返回无直链条目，11 §10 的有意差异）。

- **`123_open`**（`lib/services/cloud_drivers/_123_open_driver.dart`，前缀 `_` 因 Dart 标识符不能以数字开头；typeId 仍 `123_open`）：refresh_token + 在线续期（默认 `api.oplist.org/123cloud/renewapi`，空串回落默认值）+ 本地刷新开关（client_id/secret 联动，极性照百度）；`{code,message,data}` 包裹、`code===401` 刷新后重试一次防死循环；path→id 实例缓存（写后清）。**copy 上游未实现 → 能力位不给 copy**。真机重点见 [13 §6.1](13-DRIVER-BATCH-PLAN.md)。
- **`aliyundrive_open`**：refresh_token + 在线续期**多候选轮询**（自定义地址优先 + 6 内置，去重）→ 全失败落直连 OAuth（内置 client_id）；`drive_type`（resource/default/backup）决定 drive_id，`UserNotAllowedAccessDrive` 自愈重解析一次；`remove_way`（trash/delete）。能力位含 copy。
- **`115open`**（文件名 `open115_*`，typeId 仍 `115open`）：refresh_token 每次刷新都轮换（`passportapi.115.com/open/refreshToken`，form 而非 JSON）；响应 `{state,code,message,data}`，`state=false` 且 code 99 / 401 开头 → 刷新重试一次，**430004 = 对象不存在**；直链必须配 OpenList UA（`rawHeaders` 贯穿）；**downurl 有每日配额 → 按 fid+UA 缓存 30 分钟**；`folder/get_info` 只认目录路径，430004/990002 回退逐层列目录。能力位含 copy。
- **`terabox`**：cookie 粘贴式（会过期，重贴）；列表 `errno===9000` 是地区不可用；**jsToken 从首页正则抓取**（4000023/450016 失效重取）、errno -6 换域名；签名 `genSign()=sign(sign3, sign1)`，MD5 上游只用于上传（已砍）故无需 crypto 依赖；直链响应 `dlink` / `info` 两种形态都处理。五项写操作全真实现，能力位含 copy。
- **实现中修复的驱动缺陷**（测试暴露，已随分支提交）：`123_open` path→id 缓存键与查表键不同形（缓存永远查不中）、续期地址空串不回落默认值；`aliyundrive_open` 在线续期候选地址未去重（custom 与 builtin 首项重复）。
- **验收状态（用户确认）**：真机验收按通过处理——123_open 添加与浏览真机通过（打开目录曾报一次 invalid_grant，用户决定不排查、按验收通过收口），其余三盘按用户决定一并视为验收通过；通用清单见 [12 §9](12-DRIVER-PORTING-GUIDE.md)，逐盘重点见 [13 §6.1](13-DRIVER-BATCH-PLAN.md)。

### 4.4 只读家族（能力遮罩 = 只读）

`115_share`、`123_share`、`aliyundrive_share`、`openlist_share`、`pikpak_share`、`onedrive_sharelink`、`autoindex`、`github_releases`、`lenovonas_share`、`google_photo`、`quark_uc_tv`、`emby`、`url_tree`——浏览 / 下载 / 流式可用，写操作按遮罩隐藏（worker 驱动内五项写方法全部显式抛「不支持」，二次扫描证实）。批次已定：先接 `openlist_share` + `github_releases`（API 形状差异最大的两个）验证遮罩机制，再批量铺其余。

### 4.5 待开发

#### crypt（cipher / 下载流式 / libsodium 设置已合入 main；账号级切换未定）

- **格式**：逐字节对齐 rclone crypt（OpenList crypt 直接包 rclone 的 cipher，v1.75.1）。内容 = 魔数 "RCLONE\\0\\0"(8B) + 随机 nonce(24B) + 64KiB 明文分块 secretbox（XSalsa20-Poly1305，16B MAC，块 nonce = 文件 nonce + 块号 LE 加法）；KDF = scrypt(N=16384, r=8, p=1, 80B → dataKey32 / nameKey32 / nameTweak16)，空密码 = 全零密钥（格式一部分）；名字 = PKCS7(16) + EME(AES-256, nameTweak，≤128 块) + Base32（Hex 表小写去填充）/ Base64（URL 安全去填充，OpenList 默认）/ Base32768（与 rclone SafeEncoding 同表）三选一，off 模式 = 原名 + `.bin`（文件）/ 原名（目录），混淆 = rclone obfuscate 方案（含 `!` 双写、latin1 / ≥U+100 区段）。对齐细节与坑见 [11 §2/§3](11-CLOUD-DRIVER-PORTING.md)。
- **实现**：密码学在独立包 [`openlist_crypt`](https://pub.dev/packages/openlist_crypt)（secretbox 可选 libsodium FFI，其余仍 Dart/pointycastle）；驱动层仅 `lib/services/cloud_drivers/crypt/`。互操作验证：rclone v1.75.1 金标向量 + NaCl 官方向量（包内测试；应用侧见 `crypt_*` 测试）。
- **盐**：rclone `cipher.go` 内置 `defaultSalt`（16 字节 `A8 0D F4 3A 8F BD 03 08 A7 CA B8 3E 58 1F 86 B1`），salt 为空即用它；OpenList 把 salt 去掉 obfuscated 前缀后作 `password2` 交给 rclone，语义相同 → 我方「留空用内置默认盐」与两端一致。密码与盐一律按 UTF-8 字节进 scrypt（对应 Go 的 `[]byte(s)`）。
- **字段（照 OpenList meta.go，默认值也照抄）**：filename_encryption（off/standard/obfuscate，默认 off）、directory_name_encryption（默认 false）、filename_encoding（base64/base32/base32768，默认 base64）、encrypted_suffix（默认 .bin，仅文件名加密=off 时生效）、password、salt；另加源账号引用与源目录（用户决定：源 = 已有账号 id，**WebDAV 也可作源**；crypt 浏览根 = 源账号远程路径 + 源目录，如源账号根 /456 + 源目录 /789 → 实际落 /456/789）。
- **坏名字行为（照 OpenList driver.go 202-219）**：解密失败用原名原大小透传。本驱动只读取、不改动远端，透传既不写入也不做二次加密。
- **范围（用户决定）**：只读链路（浏览 / 下载 / 流式解密 + 改名 / 删除 / 建目录名加密）；无内容上传（4.2.1）。
- **架构**：`CryptSource` 抽象 + `CloudDriverEnv.resolveSource` 注入（`WebDavAccountSource` 落在 crypt 目录，由 AppState 注入工厂，避免反向依赖；源不存在 → 浏览时报错不炸注册）；能力随源映射并剥离 write 位（防上传权限泄漏进 UI）。**源适配层必须给 size**（单文件 PROPFIND，`webdav_service.statPath`）——漏掉会让 crypt 误判成整包，产出 0B 文件（真机反馈，已修，[11 §5](11-CLOUD-DRIVER-PORTING.md)）。
- **已落地增量（真机反馈驱动，语义已收口进固定文档）**：表单控制器与校验显示（[11 §6](11-CLOUD-DRIVER-PORTING.md)）；应用内消息最顶层横幅（[07](07-NOTIFICATIONS.md)）；下载进度按 rclone 块结构 Range 分段、逐块解密（[04 §3](04-DOWNLOAD-QUEUE.md)）；本地流桥（127.0.0.1 HTTP 端点包 `openContentRange`，播放入口无分支，[11 §5](11-CLOUD-DRIVER-PORTING.md)）；账号类型名 `typeLabelFor`（[02 §10](02-NETWORK-LIBRARY.md)）；下载重试三层兜底（分类 / 退避 / 断点续传）与超时补齐、原地重试、单一计数来源（退避见 [04 §2](04-DOWNLOAD-QUEUE.md)；后台失败与重试计数的后续变更见本文件 §7）；大小判定四态 shape + Content-Range 纠偏（[11 §5](11-CLOUD-DRIVER-PORTING.md)）。测试：`crypt_cipher_test` / `crypt_driver_test` / `crypt_stream_bridge_test` / `crypt_webdav_source_test` / `crypt_size_race_test`。
- **已落地（合入 main）**：libsodium FFI 仅覆盖 **内容 secretbox**（EME/文件名仍纯 Dart）。依赖 pub.dev hosted [`openlist_crypt: ^0.1.0`](https://pub.dev/packages/openlist_crypt)（源码 [SenkjM/openlist_crypt](https://github.com/SenkjM/openlist_crypt)），不再内置 `packages/openlist_crypt`；libsodium **1.0.20** 由该包 native assets hook 按目标 ABI 只打包一份（Android `armeabi-v7a` / `arm64-v8a` / `x86_64`，Flutter 不构建 x86；16 KB 对齐），不走 `jniLibs`。默认仍走 Dart；开关 `preferLibsodiumSecretbox()` / `--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`；加载顺序 `OPENLIST_CRYPT_LIBSODIUM_PATH` → 随包资产 → 平台默认名 → 纯 Dart。sandbox 只含 arm64 依赖 `android/gradle.properties` 的 `disable-abi-filtering=true` + flavor 级 `abiFilters`（见 [09](09-MISC.md)）。ISC 声明经 `lib/utils/third_party_licenses.dart` 进关于页。设置 → 网络库 →「加密设置」：Crypt 顺序流解密 +「优先使用 libsodium」（键 `prefer_libsodium_secretbox`，启动 `applySecretboxBackendPreference()`）；库加载失败时开关禁用并提示已走 Dart。**待办**：账号级切换落点仍未定；真机确认 FFI 加载与吞吐按用户反馈记录。

### 4.6 关键技术点（接入时要一起处理的）

- token / cookie 刷新与持久化：worker 的 cookie 持久化机制（`persistStorageCookie`）要有 Dart 版，落 secure storage。
- path→id 缓存：worker 驱动实例内的 Map 缓存（如 quark）在移动端的生命周期与失效策略。
- 直链必需头贯穿下载链路：`WebDavStreamSource` 已带 headers；`download_queue` 的下载请求要能带同样的头，[04](04-DOWNLOAD-QUEUE.md) 待补。
- 流式统一入口：`WebDavService.resolveStreamSource`（异步）已落地，四个调用点（网络库视频 / 音乐流式、音乐流式页、视频页）已切换；云盘账号走 `CloudDriveService.resolveStreamSource` 取直链 + 头。
- Range：流式必须；上游拒绝 / 忽略 Range 时按 worker 的做法降级（去掉 Range 重试一次）。
- refresh_token「粘贴式获取」逐盘实测：部分盘可能必须应用内回调页，查不到的以真机为准。

### 4.7 分阶段（每段独立交付、独立测试，按 main 状态收口）

| 阶段 | 内容 | 验收 |
|---|---|---|
| 0 | 地基：本文件 §4 迁移、`CloudDriver` 接口 + `CloudDriveService` 骨架、`WebDavService` 缝、能力遮罩枚举与静态表。**已完成**：`flutter analyze` 全清 + 244 测试全过，本文件 §4 随之删除 | `flutter analyze` + `flutter test`；WebDAV 账号行为不变 |
| 1 | 首个驱动端到端：`baidu_netdisk`。**代码已实现（表单 + 驱动 + 下载 / 流式全链路），当前 main 状态按已通过收口**，清单见 4.3.1 | 真机：添加账号 → 浏览 → 下载 → 流式 |
| 2 | 能力遮罩接线 UI：WebDAV 表单能力勾选 + 行操作 / 多选按钮按遮罩隐藏 + 只读试点（`openlist_share` + `github_releases`）。**新建文件夹遮罩已提前接入**（网络库 AppBar + 目录选择器，按写入位隐藏） | 真机：只读账号无写入口；WebDAV 能力勾选生效 |
| 3 | 首批其余驱动逐个接入。**已完成**：粘贴凭证直连盘批次 4 盘（`123_open` / `aliyundrive_open` / `115open` / `terabox`）——批量筛选与逐盘判定见 [13](13-DRIVER-BATCH-PLAN.md)，实现实录见 [11 §12](11-CLOUD-DRIVER-PORTING.md)；`flutter analyze` 无 issue、测试全过，**真机验收通过（用户确认）**。`quark_open`（MustProxy 需流桥）/ `139`（多形态）/ `quark`(cookie) 下沉到后续批 | 真机验收通过（用户确认） |
| 4 | 云端写路径禁用语义（backup / sync / playlist 对云盘账号的提示） | 真机：云盘账号同步入口有明确文案 |

阶段 0 代码落点：`lib/models/account_capabilities.dart`（能力位 + 静态表）、`lib/models/webdav_account.dart`（`providerType` / `remotePath` / `capabilities`）、`lib/services/cloud_driver.dart`（接口 + `CloudFileItem`）、`lib/services/cloud_drive_service.dart`（骨架：类型判定 / 能力解析 / 写路径永久禁用）、`lib/services/webdav_service.dart`（`_cloudOf` 分流缝，12 个方法头）、`lib/services/library_database.dart`（v6，accounts 补列 `provider_type` / `remote_path` / `capabilities`）、`lib/services/accounts_service.dart`（`accountById` + 扩参）、`lib/providers/app_state.dart` 与 `lib/main.dart`（装配）。

### 4.8 剩余未定

1. crypt 流桥形态（用户已定向，细节随实现定）：下载/缓存走内存流解密（已定）；流式播放内存流优先、media_kit 仅认 URL 时退本地 HTTP 桥（只服务 crypt，不碰原播放逻辑）；cipher 引擎切换（纯 Dart / libsodium FFI）**已落设置全局**（加密设置子页）；账号级切换仍未定。
2. 直链风控、refresh_token 粘贴式可行性：逐盘真机实测（见 4.6）。baidu 首轮真机验收就是第一手数据。
3. 后续驱动（`aliyundrive_open` 等）落实表单时仍按 4.3.1 的模式先报字段清单给用户确认；教程文案统一链 OpenList 官方文档对应驱动页。

### 4.9 全量驱动清单与驱动接入评估（OpenList 源码逐盘核查）

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

### 5.0 歌单格式换二进制容器 + 主键统一 + 解绑曲库（格式层已落地，解绑未动）

**状态**：
- **格式层已落地**：`PlaylistCodec` / `WDMMPL01`（`playlist_codec.dart`）、`CredentialVaultCodec` / `WDMMCV01`（`credential_vault_codec.dart`）、备份归档内嵌 PL/CV 段（`backup_service.dart`）全部完成；`credential_vault_roundtrip_test` 13 passed。
- **解绑曲库未动**：`PlaylistService.removeEntriesNotIn` 误删逻辑、`PlaylistEntry.musicId` 主键、CUE 分片 `cueTrackIndex` 字段均**代码未动**。下列「现状」和「应有语义」描述的就是这部分。

**用户原话与决定**：

1. 「我想使用方案 B，并使用和外部导出数据库类似的逻辑。」——即复用曲库分片 / 备份归档已有的二进制容器（`WmpContainer`，魔数 `WDMM` + 文件类 + 段表 + CRC32 + deflate），**不发明第二套容器**。
2. 「构建专有格式，使用二进制直接编码而不用 json 这种面向人类的格式以节省空间。」——`META` / `ENTRIES` 走现有 tag 记录编码；封面段走 `rawIds`（不 deflate）。
3. 「区别是采用每个歌单独立文件进行管理。」——曲库是**一个大库分片**（`lib-` / `seg-` / `del-`，为增量）；歌单是**多个小库各自成文件**（每个歌单独立同步、独立删除）。这是刻意的不对称。
4. **错误绑定修正**：「销毁曲目只影响音乐库，不影响歌单列表，歌单列表应视为与音乐库平行，但是主键和管理方式类似的一种格式，在某种意义上可以认为是一个小型音乐库。」
5. **备份内嵌歌单与凭证文件（方案 c + c2′）**：备份归档里的歌单段不再装 JSON，改为**段内每歌单一条 record**，record 的 payload 是该歌单 `.wdmp` 文件的完整字节；凭证段同理改为内嵌 `WDMMCV01` 容器字节。恢复时走与拉取远端**完全相同**的解码路径，编码只有一处。
   - **c2′ 的原因**：段 id 是 `u8`（`entry.addByte(id)`，全表 256 个且必须唯一），所以「一个歌单一个段 **id**」最多撑 246 个歌单。改为「一个歌单一条**段内记录**」，容量无上限。
6. **凭证包纳入本次改动**：远端 `credentials.json` 改为 `WDMMCV01` 容器文件，同步与备份共用同一编码。`credential_vault_crypto` 的**字段级加密语义不变**（url/username 明文，password 与 `secretFieldKeys` 逐字段 `AESGCMv1:`）——换的只是外层容器。
7. **不保留历史兼容**：不写旧 M3U8 读取路径、不写旧 `credentials.json` 读取路径、不做旧备份兼容读取、不做一次性迁移工具。
   - **不主动删远端旧文件（用户决定）**：`.m3u` / `.m3u8` / 旧 `credentials.json` 一律**无视**，同步流程里不加删除动作。删除是不可逆的破坏性操作，而旧文件留着没有危害——本版本不再读它们，读路径只认 `WDMMPL01` / `WDMMCV01`。副产品是**降级回旧版本仍能读到旧格式内容**。
8. **`layoutVersion` 保持全局共享（本次核查结论，不改）**：魔数末两位 `'01'` 是**全局常量**，不属于任何文件类。已查清完整影响面（5 处代码 + 3 个调用方 + 1 个测试）并写入 [10 §4.1.2](10-PLAYLIST-FORMAT.md)。决定**保持现状**：当前只有一个版本，改成按类独立是纯预付费；且与 §4.3 的嵌套容器叠加后会引入「外层版本 × 内层版本」矩阵。未来改动预案（含必须回答的三个问题）已记录在该节。

**现状（错误绑定）**：

- `PlaylistService.removeEntriesNotIn(validKeys)` 会把「不在曲库里的歌单条目」当作孤儿**直接删除**（`playlist_service.dart`），即歌单条目被曲库存亡绑架。曲库重建、扫描不全、路径书写变体都会**静默删掉用户歌单条目**。
- 另有 `AppState.destroyMusicLibrary()` 调 `removeEntriesNotIn(const {})` 清空全部歌单条目——**这一条是正确的**（用户显式选择销毁整库），保留。
- 推断出的第二条风险（未构造数据复现）：`identityKey` 用**未归一化**的原始 `remotePath` 拼键，而曲库 `musicId` 用 `normalizeRemotePath`；两者不等价，是「明明有这条却匹配不上」的根源，也是上面静默删除的触发器之一。

**应有的语义**：

- 歌单条目与曲库行**解耦**。曲库里没有的歌只是「未解析」（界面显示「库中暂无」），**不构成删除理由**；条目删除只能来自用户显式操作。
- 条目权威身份改为 `musicId`（与曲库同键），`sourceName` / `remotePath` 保留作显示与回退；CUE 分片加**显式字段** `cueTrackIndex`，不再依赖 `remotePath` 内嵌 `#cue:<n>`。
- 远端格式换 `.wdmp`（`WmpFileKind` 新增 `PL`，magic `WDMMPL01`；新增 `ENTRIES` 段 id `9`），只认 `.wdmp`；旧 `.m3u` / `.m3u8` **无视、不删**。
- 凭证远端文件换 `WDMMCV01` 容器（`WmpFileKind` 新增 `CV`），只用 `CREDENTIALS=5` 段装二进制 record 表；旧 `credentials.json` **无视、不删**。
- 备份归档的 `PLAYLISTS=6` / `CREDENTIALS=5` 两段改为内嵌 `PL` / `CV` 容器字节（走 `rawIds`），每歌单一条段内 record；`SETTINGS=7` / `CUE_ALBUMS=8` 保持 JSON 不动。

**影响面（待改）**：`lib/utils/m3u8_playlist.dart`（替换）、`lib/models/playlist.dart`（`PlaylistEntry` 加 `musicId` / `cueTrackIndex`）、`lib/services/playlist_service.dart`（同步编排、去掉误删逻辑）、`lib/services/playlist_store.dart`（`entries_json` 是 JSON blob，**不需要改表、不需要 DB 版本迁移**）、`lib/utils/wmp_container.dart`（`PL` / `CV` 文件类 + `ENTRIES` 段 id）、`lib/services/playlist_codec.dart`（新）、`lib/services/credential_vault_codec.dart`（新）、`lib/services/credential_vault_service.dart`（远端文件换容器）、`lib/services/backup_service.dart`（两段改内嵌容器字节、恢复侧改调 codec）、`lib/utils/track_identity.dart`。

**验收（未做）**：`flutter analyze` 干净 + `flutter test` 全过；需补的测试：`.wdmp` round-trip、`musicId` 命中、CUE 分片区分、**销毁曲目后歌单条目仍在**、`CV` 容器加解密往返、备份内嵌 `PL` / `CV` 往返、`rawIds` 不重复压缩。

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

**当前 main 状态按已通过收口**：老库升级（v7→v9）后 CUE 组删除、按保留期自动清理、已缓存标记在升级后按推导路径恢复；后续可复现问题按用户反馈记录。

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

## 7. 后台下载保活（前台服务）

**状态**（2026-09-29，分支 `feature/bg-download-keepalive`）：默认方案的代码已落地。**ColorOS / 一加真机验收没有做，下面任何一条真机检查都不要当成已通过。**

已落地（本分支）：
- S1 诊断：失败时 Dart 打前后台、`Connectivity`、`isOfflineError` / `DioException.type`、FGS 是否在跑；原生 `diagnostics` 返回忽略电池优化、`isBackgroundRestricted`、`getRestrictBackgroundStatus`、`isDeviceIdleMode`。
- S2 `DownloadKeepAliveService`（`foregroundServiceType=dataSync`）、`FOREGROUND_SERVICE_DATA_SYNC`、部分唤醒锁（10 分钟超时，服务活着时每 4 分钟续期）、Android 15+ `onTimeout`（停 FGS、通知 Dart，任务挂起为等待，30 分钟内不再立刻重启 FGS）。
- S3 `lib/services/download_keepalive.dart` 状态机（idle → starting → running → stopping / failed-to-start）+ 设置「后台下载保活」默认开，旁有说明文字（ARB：`downloadKeepAlive` / `downloadKeepAliveHint`）。只在应用处于前台时启动，队列排空（含退避中的 pending）才停。启动失败只记诊断，下载继续。
- S4 **默认路径已接线**：Kotlin 用同通道最小通知 `startForeground(2001)` 之后不再更新；Dart 继续以 700 ms 节流 `show(2001)` 替换内容；完成通知 2003 仍由 Dart 发。排空顺序：Dart 停更 2001 → `stopForeground(STOP_FOREGROUND_REMOVE)` → `stopSelf` → Dart 发 2003。关保活 = 不启 FGS，2001 走原来的路径。**原生持有 2001 的备选没有写代码**，仍是 S4 真机验证失败后的退路。
- S5 后台 offline 自动重试上限 3、前台及其余错误仍是 5（`autoRetryCap` / `shouldAutoRetry`，`_handleFailure` 里取上限）。不改现有失败文案码，不改数据库。后台 3 次失败后回前台不自动恢复。`test/download_retry_test.dart` 覆盖这个上限。
- 本机 `flutter analyze` 无问题，`flutter test` 595 通过、1 跳过。这不是真机结果。

未做，必须真机或另开工作：
- §7.2 零代码 A/B（冷启动从不播放 vs 先播再暂停）没有在设备上跑。
- S4 ColorOS 检查：同 id 替换无闪烁 / 无第二条；`dumpsys activity services` 仍在前台；`dumpsys notification` 里 2001 带 FGS 标记；FGS 期间 Dart `cancel(2001)` 的表现；通道 / 小图标 / ongoing 一致且最小通知不残留。
- §7.9 验收（锁屏 ≥10 分钟 10 首下完、关掉下载通知仍有一条、排空后消失、后台断网 3 次、开关文案）未做。
- S6 电池优化 / ColorOS 引导文案未做。
- S7 语义收口进 04 §7、07、09、README，以及压缩进 `main`，都未做。
- S8 / §7.6 音乐 FGS 延迟释放不在本分支。

相关完整文档（开发期间保留占位）：[04 §7](04-DOWNLOAD-QUEUE.md)（占位）、[07](07-NOTIFICATIONS.md)（下载进度通知 2001 仍由 Dart 更新，同时作为保活 FGS 的前台通知）、[05](05-AUDIO-PLAYBACK.md)（音乐 FGS 与 `androidStopForegroundOnPause`）、[09 §6](09-MISC.md)（占位）、[README.md](../README.md)（收口时补用户向说明）。

**用户原话**：「dns解析问题本质上就是下载的前端保活错误造成的」「下载保活做成设置可配置的就行，在前台运行时尽量避免与现有的下载通知重叠出现，或者复用现有的下载通知」「可不可以配置成谷歌的实时活动类型的通知，color os似乎会兼容进流体云（灵动岛）」「通知尽量尝试使用原本的路径」。

### 7.1 现象与根因

- **现象**：切后台 / 锁屏后音乐下载失败，报 `Failed host lookup`；前台正常。
- **根因**：下载没有**自己的**前台服务。进程退到后台后被系统限网（Doze / App Standby / 厂商后台管控）；每次重试 `WebDavService.downloadToFile` 都新建一个 `Dio`，第一步就是 DNS 解析，于是首先暴露为 `Failed host lookup`。本质是缺下载保活，不是 DNS 本身。
- **现在为什么「有时能下」**：下载在「蹭」音乐的 `audio_service` FGS。`music_audio_handler.dart` 的 `AudioServiceConfig` 设了 `androidStopForegroundOnPause: false`，所以只要播放过一次，暂停后 FGS（mediaPlayback）+ wakelock 仍在，下载跟着活；没播过音乐就没有 FGS。
- **放大器**（`download_queue_service.dart`，已核对）：
  - `_handleFailure`：`isOfflineError`（含 `failed host lookup`）的失败**也 `attempts += 1`**，每次等 `offlineRetryDelay`（10 s），`maxAutoRetries = 5` → 约 50 s 后永久 `failed`（「重试 5 次仍失败：网络不可用」）。注意 `offlineRetryDelay` 的注释写着「不消耗重试次数」，与 `_handleFailure` 实际行为不符。
  - `didChangeAppLifecycleState(resumed)` 只是取消 `_retryTimer` 再 `_pump()`：只会接着跑到期的 pending，已 `failed` 的任务不会复活。
  - `_listenConnectivity`（`connectivity_plus`）只看设备级连通性，看不到「本应用被限网」，这时它一直报在线、不会触发唤醒。

### 7.2 零代码验证（S1 前先做，A/B）

同一台机、同一批 10 首未缓存歌曲，入队后按 Home 再锁屏 3 分钟：

- **A**：冷启动后**从未播放音乐**直接入队 → 预期出现 `Failed host lookup`、任务停在「重试 5 次仍失败」。
- **B**：先播一首再暂停（FGS 仍在），再入队 → 预期全部完成。

A 失败 B 成功即坐实「蹭音乐 FGS」的根因判断；两者都成功或都失败则回来重新定位。

### 7.3 方案（已定）

**原生侧**
- 新 Kotlin 服务 `DownloadKeepAliveService`，`android:foregroundServiceType="dataSync"`；manifest 加 `FOREGROUND_SERVICE_DATA_SYNC`（现有只有 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` / `WAKE_LOCK`）。
- 持 CPU `PARTIAL_WAKE_LOCK`，**带超时**（防泄漏），队列活着时续期。
- Android 15+ dataSync 有累计时长上限（24 h 内约 6 h），实现 `Service.onTimeout(int, int)`：停 FGS、把当前任务挂起为等待、通知 Dart；不崩、不硬撑。
- **启动时机**：Android 12+ 禁止后台启动 FGS，所以只在**应用前台**时启动——入队 / `_pump` 开跑时；保持到队列排空（**包括等待退避 / 等网络的 pending**）才停。启动失败（`ForegroundServiceStartNotAllowedException` 等）要 catch 并回报 Dart，写进诊断，不影响下载本身（退回今天的行为）。
- MethodChannel：`com.senkjm.media_manager/download_keepalive`（与现有 `com.senkjm.media_manager/app` 同命名风格）。

**通知：复用现有下载进度通知，不出现第二条；尽量沿用原路径（用户决定）**
- FGS 的前台通知**就是**现有下载进度通知：id `2001`（`DownloadNotificationService.currentId`），通道 `com.senkjm.media_manager.downloads.v1`（Importance.low），普通进度通知（不做实时活动，见 §7.5）。
- **默认方案：Dart 继续持有 2001**。`flutter_local_notifications` 照旧 `show(2001)` 创建与更新进度（`progressInterval` 700 ms 节流不变）；Kotlin `DownloadKeepAliveService` 只用**同一通道**构建一条最小通知（标题 + 小图标 + ongoing），调 `startForeground(2001, …)`，之后不再更新它，由 Dart 的下一次 `show(2001)` 按同 id 替换内容（系统保留 FGS 标记）。完成通知（id 2003，`downloads.done.v1`）仍由 Dart 发。
- **S4 真机验证（ColorOS）**：同 id 替换无闪烁 / 无第二条；FGS 不被破坏（`dumpsys activity services` 仍在前台、`dumpsys notification` 2001 带 FGS 标记）；FGS 运行期间 Dart `cancel(2001)` 的表现（预期被忽略或通知被重建）；两侧通道 / 小图标 / ongoing 一致，最小通知不残留。
- **备选（仅当上述验证失败）**：改为原生持有 2001——FGS 运行期间由 Kotlin 构建与更新进度，Dart 停止 `show(2001)`，改经 MethodChannel 推进度；关保活时 Dart 仍按原样发 2001（两条路径只能有一条在写 2001）。
- **排空时的顺序**要写死：Dart 先停止更新 2001 → 原生 `stopForeground(STOP_FOREGROUND_REMOVE)` 移除 2001 → `stopSelf` → Dart 再发 2003 完成通知。避免「清进度」与「停 FGS」互相抢导致进度条残留或完成通知被带走。
- 关闭保活开关时：不启 FGS，2001 行为与今天完全一致。

**设置可配置**（已确认）
- 新开关「后台下载保活」，**默认开**（用户已确认）。关 = 完全保持今天的行为（不启 FGS、不改重试）。
- 保活开着时，即使用户关了「下载队列系统通知」，下载期间 2001 也会常驻（Android 要求 FGS 必须有通知）——**用户已接受**。要求：在开关旁写说明文字，如「开启后，下载期间通知栏会常驻一条下载通知（系统要求），关闭下载通知也会显示」。新增字符串 1–2 条（开关标题 + 说明）。

**Dart 侧**
- 新文件 `lib/services/download_keepalive.dart`：状态机 idle → starting → running → stopping（+ failed-to-start），对外只暴露 `ensureRunning()` / `release()` / 诊断（走 §7.3 备选时才加 `updateProgress()`）。
- `download_queue_service.dart` 只加最小挂点：`_pump` 开跑时 `ensureRunning`、排空（`_pump` 的 finally 且无 pending）时 `release`、`_handleFailure` 里读前后台状态做 §7.4 的判定。

**诊断**（S1 先落，失败时记录）：前后台状态、`Connectivity` 当前结果、错误类型（`isOfflineError` / DioException type）、保活 FGS 是否在跑；原生诊断方法返回 忽略电池优化与否、`ActivityManager.isBackgroundRestricted`、`ConnectivityManager.getRestrictBackgroundStatus`、`PowerManager.isDeviceIdleMode`。

### 7.4 重试语义（已确认：后台断网重试 3 次）

- 应用在**后台**且错误属于 offline 类（`isOfflineError`：`failed host lookup` / `network is unreachable` 等）→ 最多自动重试 **3 次**，耗尽即判 `failed`。
- 前台保持现有规则不变（5 次；offline 固定 10 s、其余 2/4/8/16/32 s 退避）。
- 实现上是 `_handleFailure` 按前后台状态取上限（后台 offline 3 / 其余 `maxAutoRetries` 5），**不改现有文案字符串**（§7.8）；不改 DB schema（`download_store.dart` 升版本即 `DROP TABLE` 重建）。
- **未确认**：回到前台时是否自动恢复这些「后台断网 3 次失败」的任务。当前按**不自动恢复**写——用户手动「重试」/「全部下载」。
- `test/download_retry_test.dart` 在 S5 补用例：后台 offline 上限 3、前台仍 5。

### 7.5 实时活动 / 流体云

**状态**：已放弃（用户决定）。不做。下载通知保持普通进度通知。以下只作查证记录，**不进计划**：

- Android 16 [Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)：需 `POST_PROMOTED_NOTIFICATIONS` + `setRequestPromotedOngoing(true)`，API 36.1（16 QPR1）起才提升；要求 ongoing + 标题，不能自定义 RemoteViews / group summary / colorized，通道不能是 MIN；`androidx.core` 1.17.0+ 才有 `NotificationCompat.ProgressStyle`。
- `flutter_local_notifications` 22.3.1 不支持（[issue #2773](https://github.com/MaikuB/flutter_local_notifications/issues/2773)）。
- ColorOS 16 流体云接入原生 Live Updates（[IT之家](https://www.ithome.com/0/890/345.htm)；[社区实测](https://www.yehenest.com/posts/miao-time-dynamic-island-fluid-cloud) ColorOS 16.1 仅原生 API 可进流体云）；OxygenOS 16 第三方应用默认关；国行默认值与是否过滤下载场景未知。

### 7.6 后续（计划，未排期，单独分支）：音乐前台保活「暂停后延迟释放」

- 暂停 N 分钟（如 10，可配置）后 `stopForeground` + 释放 wakelock，但保留媒体通知 / 会话；恢复播放再进 FGS。
- 风险（ColorOS）：停 FGS 后媒体通知 / 控制中心卡片可能被系统移除；从锁屏恢复播放时的 FGS 启动限制（当年设 `androidStopForegroundOnPause: false` 就是为了绕开 Android 12+ 的这个限制，见 [05](05-AUDIO-PLAYBACK.md)）。
- **必须排在下载保活之后**：下载不再蹭音乐 FGS，才能放音乐 FGS 走。

### 7.7 分步

| 步 | 内容 |
|---|---|
| S0 | 本节文档；04 §7 / 09 §6 占位 |
| S1 | 只加诊断字段 + 原生诊断方法；真机跑 §7.2 A/B |
| S2 | 原生 `DownloadKeepAliveService` + manifest（`FOREGROUND_SERVICE_DATA_SYNC`）+ MethodChannel `com.senkjm.media_manager/download_keepalive`；`startForeground(2001)` 用的最小通知（同通道 `downloads.v1`，不做进度构建器） |
| S3 | Dart `download_keepalive.dart` 状态机 + 「后台下载保活」设置项（默认开 + 说明文字） |
| S4 | 通知复用：FGS 借 2001 启动、Dart 照旧更新同 id、排空顺序；ColorOS 真机验证（无闪烁、FGS 不被破坏、FGS 期间 `cancel(2001)`、通道 / 配置一致）；不过则切 §7.3 备选（原生持有 + MethodChannel 进度） |
| S5 | §7.4 后台断网 3 次上限 + `test/download_retry_test.dart` 用例（后台 offline 上限 3） |
| S6 | 电池优化 / ColorOS 引导文案（等 i18n 落地后做） |
| S7 | `flutter analyze` / `flutter test` / 真机验收；语义收口进 04 §7、07、09、README，压缩提交 |
| S8 | （以后，单独分支）§7.6 音乐 FGS 延迟释放 |

### 7.8 与 i18n 重构的冲突面

另一条分支在做全库 i18n。本项：不改 `_handleFailure` 里的现有文案字符串；新逻辑放新文件；新增用户可见字符串 ≤2 条；设置页 UI 改动最小（一个开关 + 至多一行说明）。

### 7.9 验收

- 保活开：锁屏 ≥10 分钟，10 首全部完成；日志无 `host lookup`；全程**只有一条**下载通知（不与 FGS 通知重叠）；关掉「下载队列系统通知」后下载期间仍显示这一条，排空后消失。
- 后台真断网：offline 失败重试 3 次后判失败；回前台不自动恢复，手动重试可继续。
- 开关旁说明文字可见；开关关 = 旧行为。

### 7.10 风险 / 未知

- ColorOS 对 dataSync FGS 的额外管控（未加入「允许后台运行」时是否仍被杀）。
- Android 15+ dataSync 6 h 上限对超大队列的影响。
- 蹭音乐 FGS 与保活 FGS 同时存在时的交互（两条通知是不同通道，不算重叠，但要确认）。
- 默认方案（`flutter_local_notifications` 更新 FGS 借用的 2001）在 ColorOS 上是否可靠：闪烁、FGS 标记丢失、`cancel(2001)` 行为、通道 / 配置不一致（§7.3，S4 验证；不过则走原生持有备选）。
- 后台断网 3 次失败后回前台是否自动恢复（§7.4，未确认）。
- 后台限网时 `connectivity_plus` 仍报在线，后台 3 次可能在网络其实已恢复前就耗尽（保活生效后应少见）。

**adb 测试命令**：

```sh
adb shell dumpsys deviceidle force-idle            # 强制 Doze；恢复：adb shell dumpsys deviceidle unforce
adb shell am set-inactive <pkg> true               # App Standby
adb shell am set-standby-bucket <pkg> restricted
adb shell cmd appops set <pkg> RUN_ANY_IN_BACKGROUND ignore   # 恢复：allow
adb shell dumpsys activity services <pkg>          # FGS 是否在跑
adb shell dumpsys netpolicy                        # 后台限网
adb shell dumpsys power                            # wakelock
adb shell dumpsys notification | grep -A5 2001     # 下载通知是否唯一 / FGS 标记
adb logcat | grep -Ei 'host lookup|DownloadQueue|KeepAlive'
```

`<pkg>`：prod / dev / sandbox flavor 包名不同（`com.senkjm.media_manager`、`.dev`、`.test`），分别测。

## 8. 设置页重排、下载目录排除扫描、图片存相册

**状态**：本分支已实现。完整文档已按新信息架构改写；本条保留原始需求与取舍，收口前不要删。

相关：[02](02-NETWORK-LIBRARY.md)、[03](03-MUSIC-LIBRARY.md)、[04](04-DOWNLOAD-QUEUE.md)、[05](05-AUDIO-PLAYBACK.md)、[07](07-NOTIFICATIONS.md)、[08](08-SYNC-AND-BACKUP.md)、[09](09-MISC.md)。

**用户原话**：「在主页和导航，媒体通知上方缺少分隔符。重新排版设置界面，修复原有的排版不规范问题。整体思路按照音乐库、网络库、杂项、备份与同步重新排版。有三条以上或者需要填写的放入二级菜单。另外WEBDAV服务器也改成网络库下面的网盘账号管理。分享、缩略图放入媒体库主页和导航放到上面。」随后追加：下载目录「排除媒体扫描」（`.nomedia`，默认关，只作用于 `Download/WebdavMediaManager`）；图片增加「下载到系统相册」（MediaStore Images / Pictures，与视频相册同一条导出，不受 `.nomedia` 影响）。

**取舍**：

- 最上分区标题用既有键 `homeAndNavigation`，文案改为「媒体库主页和导航」。里面是自定义主页、记住网络库路径、分享（要填模板，进二级页）、缩略图（自定义边长要填，进二级页）。媒体通知仍是行，不是新功能；它上方补了与其它分区一致的 `Divider`。
- 四个分区顺序：音乐库、网络库、杂项、备份与同步。缓存清理要填天数，进二级页；刷新标签只有一行，留在音乐库。网盘账号、下载、视频、音频流式、图片查看、后缀都在网络库，各自仍打开原来的页面。账号页标题改为「网盘账号管理」。
- 语言和提示显示时长是两项简单选择，留在杂项。下载通知、后台保活、测试通知跟下载有关，挪进「网络库 → 下载」，默认值不变。
- `.nomedia` 偏好键 `download_nomedia`，默认 false。打开才创建，关掉才删除。**旧语义**「冷启动只在开关为开时补文件，不会因为开关关着就删」已被 §20 的双向 `alignNomedia` 取代（见 [§20](#20-saf-自定义下载目录本分支实现)）。API 28 直接写公共文件且不扫描；API 29+ 走 `MediaStore.Downloads`，显示名 `.nomedia`；API 28 以下忽略。相册导出不写这个文件。
- 图片动作存储键 `download_to_gallery`，只允许图片类别，出厂默认仍是查看图片。视频相册仍是「⋮」里的单独入口，不改单击默认。


## 9. 预发布标签名与已有 .nomedia（本分支实现，2026-10-19 更新）

**状态**：本分支实现。语义已写入 [04](04-DOWNLOAD-QUEUE.md)、[09](09-MISC.md) 与 README。收口前不要删。

**用户原话（2026-09-29）**：新的预发布标签只用 `${base}-${versionCode}`（例 `v0.2.2-2020004`），不改 Release 标题模板，不改已有标签和已有 Release 标题。同一提交重跑仍复用该标签及其 versionCode，按标签 metadata 的 sha / seq / version_code 查找，不靠标签名里的短 SHA。`.nomedia` 开关：先调平台方法检测与应用，只有成功（含 already）才保存设置。打开时已经有真正的 `.nomedia`，或关闭时已经没有，则不写不删，保存设置并提示外部操作已完成。状态不一致才按原逻辑写入或删除。API 29+ 先查显示名恰好为 `.nomedia` 的 MediaStore.Downloads 行，查不到时回退查磁盘文件（外部放置的文件也能读到），存在且可读才算 present；插入后 MediaStore 改写了显示名时，Samsung 返回专用错误「三星系统会改写 .nomedia 文件名，无法干净排除媒体扫描，已取消」，非 Samsung 返回通用错误；删除时若 MediaStore 无行但磁盘有文件，尝试 `File.delete()`，失败返回「无法删除外部放置的 .nomedia，请用文件管理器手动删除」。API 28 认磁盘文件；API 27 及以下忽略。相册路径不动。

**取舍**：

- 新标签名在算出 seq / versionCode 之后才确定。旧标签 `v0.2.2-f046956`、`v0.2.2-ba29461`、`v0.2.2-0d5148a` 与浮动 `prerelease` 不改名、不移动。`version_name` 仍等于标签名，所以新版本的标题会变成 `Pre-release v0.2.2-<versionCode> (<versionCode>)`，模板那一行不改。
- 开关的「已经一致」走原生返回的 `already`，不是错误。**旧语义**「冷启动和进入下载设置时若开关为开，仍然只在缺失时补文件」已被 §20 双向 `alignNomedia` 取代（见 [§20](#20-saf-自定义下载目录本分支实现)）。
- Dart 侧 `_toggleNomedia` 改为：先保存设置，再调 `alignNomedia`；成功时继续，失败时回滚设置并显示错误。

**2026-10-19 更新**：Samsung 机型在 MediaStore 插入后改写显示名的处理；API 29+ 查不到 MediaStore 行时回退查磁盘文件作为 present 判定；删除时若 MediaStore 无行但磁盘文件存在的特殊处理；Dart 侧「先保存设置、再对齐、失败回滚」的顺序（对应 §20 的 SAF 架构，toggle 通过 `DownloadDestinationService.alignNomedia` 而不是直接调 `PlatformExportService`）。

## 10. 日语衬线字体（本分支已按最小改法落地）

**状态**：2026-10-03 `feat/l10n-leftovers` 已改代码。不恢复 `app_zh_CN.arb`。简体偏好改回 `Locale('zh', 'CN')`。`MaterialApp.localeListResolutionCallback` 用 `resolveAppLocaleList`：系统 `zh_CN`、`zh_Hans`、裸 `zh` 都解析成 `Locale('zh', 'CN')`；`zh_TW` 或 script `Hant` 仍是 `Locale('zh', 'TW')`；英文仍是 `Locale('en')`。`lookupAppLocalizations` 本来就把非 TW 的 zh 映到简体，`isSupported` 只看语言码。

**现象**：中文和英文仍是原来的无衬线字体。日语假名退化成衬线体，每台机器落到的衬线不一样。

**原因**：`923007e` 把简体界面从 `Locale('zh', 'CN')` 改成 `Locale('zh')`，文案没变。Android 字体表按 `zh-CN` / `zh-Hans` / `ja` 登记，没有裸的 `zh`。汉字多半还能落到黑体，假名对不上就继续往下找，先碰到的常常是 Noto Serif CJK 一类衬线。跟系统时也一样：手机是 `zh_CN`，但 `supportedLocales` 只有裸 `zh`，解析会把地区丢掉。

**最小改法（本分支已做）**：见上面的状态。繁体、英文不动。

## 11. 下拉菜单直角（本分支已按最小改法落地）

**状态**：2026-10-03 `feat/l10n-leftovers` 已改代码。每个 `DropdownButton` / `DropdownButtonFormField` 传入 `borderRadius: BorderRadius.circular(10)`（设置、同步、后缀、视频手势设置、视频播放页手势菜单、账号、网络库）。`AppTheme` 亮色和暗色都加了 `popupMenuTheme`，圆角同样是 10。没有新 UI kit，播放器手势区、进度条、底衬没有改样式。

**现象**：设置、同步、后缀、视频手势、账号里的 `DropdownButton` / `DropdownButtonFormField` 弹出菜单是直角，和卡片、对话框、输入框的 10–16 圆角不是一套。

**原因**：这些调用都没传 `borderRadius`。Flutter 3.47 的 `dropdown.dart` 在未传入时用 `BorderRadius.zero`。`AppTheme` 没有下拉菜单的总开关。

**最小改法（本分支已做）**：见上面的状态。没有换成 Material 3 `DropdownMenu`。

## 12. 语言选项跟着界面语言变（已在 feat/md3-theme 落地，本合并保留）

**状态**：2026-10-03 先只分析。同日 `feat/md3-theme` 按该方案改了代码，本合并保留。语言菜单里简体永远是「简体中文」，繁体永远是「繁體中文」，英文永远是「English」，写在 `AppLocalePreference.nativeName`。「跟随系统」仍用 `l10n.languageSystem`。根目录 `agent.md` 要求之后的开发沿用现有圆角、颜色角色和这条约定。

**现象**：语言下拉在简体界面里「简体中文 / 繁体中文」都是简体字；切到繁体后这两项都变成繁体字；切到英文后变成 Simplified Chinese / Traditional Chinese。

**原因**：`settings_screen.dart` 的选项用的是 `l10n.languageSimplifiedChinese` 等键。这三个键在 `app_zh.arb`、`app_zh_TW.arb`、`app_en.arb` 里各有一份译文，所以显示的是当前界面语言，不是该选项自己的语言。

**方案（已做）**：语言名字不要走 l10n。在 `AppLocalePreference` 上写死自称：简体永远是「简体中文」，繁体永远是「繁體中文」，英文永远是「English」。以后加语言只加这条自称，不把语言名翻译进每份 ARB。「跟随系统」不是一种语言，仍用当前界面的 `languageSystem`。


## 13. 界面残留中文、下载重试、一次性哨兵迁移（本分支）

**状态**：`feat/l10n-leftovers` 未推送。`pubspec.yaml` 仍是 `1.0.0+1`，没有为这条迁移改版本号。注释里的 0.2.2 / 0.2.4 是用户指定的正式版本说法，不是 pubspec。

**界面文案**：还露在界面上的简体写进 `app_zh.arb` / `app_zh_TW.arb` / `app_en.arb`，繁体和英文是各自的句子，不是简体副本。没有恢复 `app_zh_CN.arb`。

**故意不翻译**：写进数据库或文件名的哨兵（`未知艺术家`、`未知专辑`、`未命名`、`新歌单`、`默认服务器`、`服务器`、`未分类`、`新文件夹`、`系统相册`、`下载目录`）仍是存储值。语言自称 `简体中文` / `繁體中文` / `English` 已按 §12 写在 `AppLocalePreference.nativeName`，不进 ARB。`debugPrint`、`MusicAudioHandler` 探测串、Open115 `msg.contains('网络')`、原生 Kotlin（`MainActivity` 错误、`DownloadKeepAliveService` 回退「下载进度 / 正在下载」）不动。

**下载重试**：`DownloadQueueService.isRetryable` 不再把 401 / 403 / 404 / unauthorized / forbidden 或非 5xx 的 `badResponse` 排除。所有上游错误（含奇怪的授权失败）走原来的次数和退避。仍然不重试：用户取消、`StateError`、解密失败 `CloudDriverDataException`。

**一次性迁移**：`migrateLegacySentinelsOnce`（`lib/services/legacy_sentinel_migration.dart`）在 `AppState.init` 里、缓存目录就绪之后、曲库 / 账号 / 歌单 / 下载把名字读进内存之前跑一次。文件头注释写明：这是正式版本 0.2.2；本迁移只在 0.2.2 运行；到 0.2.4 必须做完并删掉全部迁移代码；0.2.4 之后旧数据库不再兼容。没有第二套迁移框架，也没有抬高曲库 schema。

只改两处精确匹配：

- 歌单名 `未命名` → `__wdmm_unnamed_playlist__`（`playlists.name` 与 `entries_json` 里的 `sourceName` / `accountId`）。不碰 `新歌单`。改过的行抬高 `updated_at`，同步才能推稳定键。不在启动时去拉远端 `.wdmp`。
- `默认服务器` → `__wdmm_default_server__`：`accounts.name`、各表 `source_name`、下载任务、歌单条目 `sourceName`，以及恰好是这个名字或以 `cue\0默认服务器\0` / `默认服务器\0` 开头的 `cache_group_id` / `cache_groups`。不碰默认名 `服务器`。`music_id` 不重算哈希；缓存和封面文件按旧 stem 改名到新 stem，`cover_path` 同样改。

不改：真实流派标签 `未分类`（空流派已经是 `__wdmm_uncategorized__`）、`未知艺术家` / `未知专辑`（空艺术家 / 空专辑的分组键已经是稳定键，界面用 `displayArtistFor` / `displayAlbumFor`）、`新文件夹`、`系统相册`、`下载目录`、字幕存储值 `默认`、原生 Kotlin。再跑一次找不到这些中文哨兵。下一版（最迟到 0.2.4）删掉整个函数——预发布成功后与临时同名清理门闸一并移除（见 §17.17 末「0.2.4 计划」）。

## 15. 启动默认主页 tab 与网络库路径仅内存

**状态**：已合入 main（2026-10-12）。相关：[02](02-NETWORK-LIBRARY.md)、设置「主页和导航」。

**用户原话**：
1. `network_last_path`（上次访问网盘路径）不要持久化到数据库/prefs，只放内存。
2. 即使设了 `home_tab_index: 2`，启动仍默认音乐库——要修好，启动时真正打开用户设定的默认主页 tab。

**取舍**：
- `HomeShell` 冷启动读 `SettingsService.homeTab` 作为 `_index`（原先写死 `0`）；返回键回主页逻辑本来就会读该值，只是首帧没用上。
- `network_last_path`：进程内字段保留，供「记住上次路径」在**同一运行期**、网络库 State 被重建时恢复；`SharedPreferences` 与备份 JSON 不再读写该键；`init` 清掉旧安装残留；冷启动始终从 `/`。开关 `network_remember_last_path` 仍持久化，文案改为标明不跨冷启动。

## 16. 备份恢复前口令校验块

**状态**：已合入 main（2026-10-12）；语义见 [08 §5](08-SYNC-AND-BACKUP.md)。

**用户原话**：
1. 恢复（本机/云端）在真正写库前先校验备份口令；密码正确按现有逻辑恢复；密码错误/空但归档需要口令 → 弹确认（提示可能出现预料之外的问题/空密文等，可取消或强制按现有逻辑继续）；无加密备份跳过校验。新建归档带可验证校验块；旧归档无校验块时尽量用已有密文字段试解，否则明确「无法预检」。
2. 备份文件整包加密（WDMMEN01）或密钥不对时，不要只弹错误 Snackbar；要弹窗，提供「继续」和「取消」。整包解不开就不能真正导入——与「字段级密文错误可强制写入空密码」不是一回事。

**取舍**：
- 预检 / 弹窗在 `_runSync` / `_guard` **之外**（下载或选文件拿到 bytes 后先弹窗，用户确认再 `_runSync` 执行 restore），避免弹窗被错误捕获收成 Snackbar。三个入口：网盘 `_restore`、本地 `_importLocal`、Base64 `_importBase64`。
- `BackupPassphraseProbe.envelopeMismatched`：整包信封解密失败；UI「取消」/「继续」。继续后再失败 → 仅确认对话框，不走错误 Snackbar。`_guard` / `_showOutcome` 对备份解密类异常做同样兜底。
- `mismatched` / `unverifiable`：保持字段级「强制继续」文案与语义。

**落地**：
- 格式：`formatVersion = 6`；`WmpSections.passCheck = 11`（`AESGCMv1:` canary）；JSON 导出顶层 `passCheck`。
- 预检：`lib/utils/backup_pass_check.dart`；UI：`sync_screen`。
- 测试：`test/backup_pass_check_test.dart`。

## 17. 媒体库 / 任务队列 / 播放合一（重大改动，进行中）

**状态**：2026-10-12 基于 `origin/main` tip `8c2b6c5` 开分支 `feat/media-library-unify`。不要历史包袱：可删过时测试、可改 DB schema、功能级重构优于叠补丁。

**落地进度**：
- **错误模型（§17.12 第 1 步）**：已落地。见 `lib/utils/task_error.dart`、`TaskQueueService.describeError` / `describeErrorDetail`、`tasks_screen`。
- **任务队列外壳（§17.12 第 2 步）**：已落地。用户文案「任务队列」；`QueueTask.kind`；双进度；`TaskQueueService` / `TasksScreen`；非 download kind 可入队展示但不调度。扫描执行器未做。
- **遍历 / 深度（§17.12 第 3 步）**：已落地共用 `WalkOptions` / `DirectoryWalker`（防环 + maxEntries 默认 500）。**三套 prefs 完全独立**（默认 maxDepth=1）：
  1. 视频播列表：`video_scan_subdirs`（默认关）+ `video_playlist_max_depth`
  2. 音乐网络库播列表：`audio_scan_subdirs`（默认关）+ `audio_playlist_max_depth`
  3. 媒体库刮削：`media_scan_recursive`（默认**开**）+ `media_scan_max_depth`
  图片 `image_scan_subdirs` 保持独立、不复用。视频/音乐渐进扫描已接 WalkOptions；刮削执行器未做。
- **入库与预载 / 播放合一（§17.12 第 4–5 步）**：**已落地**（无 MusicStreamScreen 旁路）。
  - Range 标签：`StreamCoverReader.extractTags`（cherry-pick 自 stream-tags）。
  - 入库：`LibraryService.ingestFromTags`；预载 `onIngestTags` 先入库再下邻居。
  - **统一播放**：`AudioPlayerService.playTrack` → `PlayableMedia`（本地文件 **或** 流式 URL+headers）→ `MusicAudioHandler` 同一音乐队列 / 媒体会话 / MiniPlayer / PlayerScreen。
  - 预载：`MusicPrefetchService`（挂在 AudioPlayerService；标签→封面→音频进 `prefetch_cache`）。已删 `MusicStreamScreen` 与 `AudioStreamEngine`。
  - 队列：网络库按当前路径 siblings；媒体库按列表/歌单。视频仍走 `VideoPlaybackService`（video mode）；音乐起播会 `exitVideoMode`，流式音乐不再占用 video mode。
  - 状态点：`streamable` / `ready` 主题色；红点未做。
- **红点 / 刮削 / 设置（§17.12 第 6–7 步）**：**已落地**。
  - Schema v10：`tracks` / `cue_slices`.`remote_missing`；起播 404 写红点（有本地缓存跳过）；点红点再试 → 删除/重定向。
  - `TaskKind.scan` 执行器 + 网络库多选「扫描入库」（先统计再入队，units 进度，增量只比路径）。
  - `TaskKind.retagCloud` 执行器；设置「从云端更新标签」入队。
  - 顶栏「媒体库」；音乐设置进子页；音乐默认打开（缓存/串流）独立 pref；后缀页音乐不再改默认打开；库长按「串流（仅本次）」。
- **全屏播放状态条**：`PlayerScreen` 按当前 `PlayableMedia.isLocal` 显示「缓存」/「流式」（三语 ARB）；MiniPlayer 不加。
- **歌单对齐曲库状态（本轮）**：**已落地并扩展**。歌单行经 `musicId` → `LibraryTrack` 解析，与曲库共用 `libraryRowUiState` / 状态点（缓存淡金 / 可串流 primary / remote_missing 红点 / 播放中图标）。库中无此曲 → 「库中暂无」。`PlaylistEntry.remoteMissing` 已镜像（entries_json / `.wdmp` ENTRIES tag 8）；起播失败与全量匹配同步写曲库 + 歌单。点红点再试 → 删歌单条目或重定向（`retargetTrack` + `replaceTrack`）。
- **音乐库单文件更多（本轮）**：长按仍进多选；行尾 ⋮：流式播放 / 缓存 / 清理 / 从缓存更新标签 / 从云端更新标签 / 重定向 / 删除。播放页「更多信息」更新标签改成左右两个按钮（从缓存更新标签 / 从云端更新标签）。
- **剩余缺口**：列表封面桶（无本地时 Range 写入 `covers/`）、刮削走 `ingestCueRemote`。全量匹配写红点与重定向后 Range ingest 已有实现入口，按真机反馈再收。
- **播放打开模式锁定（本轮）**：默认文案「缓存播放 / 串流播放」；`PlayOpenMode` 贯通网络库 / 媒体库 / 歌单。
  - **缓存播放**：仅 `music_cache`；缺文件则 `ensureQueued` 并等待后再播（不静默串流）；邻居按预载窗口经任务队列入 `music_cache`。
  - **串流播放**：有 `music_cache` 用本地；否则只串流；不入队 `music_cache`、不后台暖邻居进缓存；临时 `prefetch_cache` 仍可用于邻居。
  - 状态条：只有 `music_cache` 算「缓存」；仅有 `prefetch_cache` 显示「串流」。
  - 「从缓存更新标签 / 从云端更新标签」仅用于更新标签，不作播放模式名。
  - `music_cache` 容量上限 + 既有按时间清理；跳过正在播放；清缓存后经 `CacheService` 刷新。
  - 音频流式设置并入媒体库设置；预载文案区分串流临时预载 vs 缓存播放后台缓存。
  - 任务队列：展示层按时间连续同 kind（下载再按 `DownloadTarget`）合并；保留 CUE 组合并；聚合进度 / 取消组 / BottomSheet 看成员。
- **曲库管理模式（本轮，已按播放触发重锁）**：设置 → 媒体库 → 音乐库。互斥两项：
  1. **手动管理**（默认，`music_library_auto_backfill=false`）：库只因用户显式操作变化；**不**自动刮削。
  2. **自动补齐**（`true`）：**起播**时浅层刮削为默认行为（见 §17.17）；**已移除**「打开音乐库时检查」入队与「播放时检查」开关。
  - 网络库手动「扫描音乐」/ 多选「扫描入库」**两种模式都可**；自动入队仅自动补齐 + 播放触发。
  - 更新标签文案「从缓存更新标签」/「从云端更新标签」；空库引导可扫描或下载。

**相关完整文档**：[02](02-NETWORK-LIBRARY.md)、[03](03-MUSIC-LIBRARY.md)、[04](04-DOWNLOAD-QUEUE.md)、[05](05-AUDIO-PLAYBACK.md)、[06](06-VIDEO-PLAYBACK.md)、[09](09-MISC.md)。开发期间上述文档只留一行占位指向本节。

### 17.1 目标（原话级）

1. ~~错误模型（短码 + 详情全文）~~ **已落地**
2. ~~任务队列外壳（改名、`kind`、列表 / 详情）~~ **已落地**
3. ~~遍历 / 深度（网络库音乐列表、视频列表、刮削深度分设）~~ **已落地**（三套独立 prefs，见上）
4. ~~入库与预载（Range 标签先入库再预载；sidecar 保留）~~ **第一段已落地**（见上）
5. ~~播放合一（同一套底部控件；串流 / 缓存只差本地文件）~~ **已落地**
6. ~~红点 / 重定向~~ **已落地**
7. ~~扫描与更新标签~~ **已落地**

### 17.13 stream-tags（Range 读标签）依赖说明

- 提交 `ebe8424`（`feat: read stream tags, cover and lyrics over HTTP Range`）在分支 `feat/stream-tags`，**尚未合入 `main`**。
- **本分支已 cherry-pick** 该能力（见落地进度）；`main` 仍无。勿在合入 main 前假装全树已有。

### 17.14 未决

无。

### 17.15 分支与范围

- 分支：`feat/media-library-unify`（worktree：`worktree/media-library-unify`）。
- 不推 `main`、不发版。按 §17.12 顺序逐步落地业务代码。

### 17.16 播放打开模式与任务合并（已锁定并落地）

**用户锁定规则**（2026-10-12）：

1. 默认名：**缓存播放** / **串流播放**（不用「缓存后播放」）。设置说明覆盖网络库、媒体库、歌单。
2. 「从缓存更新标签 / 从云端更新标签」只用于更新标签（勿与播放模式混淆）。
3. 缓存播放：有本地文件只播文件；缺则自动入队 `music_cache` 并等待再播；邻居经任务队列、同一预载窗口暖缓存。
4. 串流播放：有本地用本地；无则只串流；不入队 / 不暖 `music_cache`；临时 `prefetch_cache` 可用。
5. 缓存有无不以 DB 为准，用 `CacheService` 的 `File.exists`；下载 / 删除 / 清理时 notify。
6. `music_cache` 容量上限 + 按时间清理；跳过正在播放；设置 UI；清理后刷新。
7. 音频流式设置并入媒体库设置分类；文案只写操作；预载窗口：串流→临时预载，缓存播放→同窗口后台缓存。
8. TasksScreen 展示层时间连续同 kind 合并；保留 CUE 组合并；不改 `QueueTask` 存储；聚合进度、取消组、BottomSheet；同 kind 不同 `DownloadTarget` 拆开。
9. 状态条：仅 `music_cache` = 缓存；仅 `prefetch_cache` = 串流。
10. 入口统一：`network_library` / `library_screen` / `playlist_detail_screen` 都尊重 `musicDefaultStream` / `PlayOpenMode`。

### 17.17 曲库管理模式 → 播放触发浅层刮削（已重锁）

**用户原话（2026-10-12，后改）**：只刮削；下载跟播放模式；前缀匹配；去掉打开音乐库时自动入队；改为起播时浅层列父目录；绑定路径开关；修账号选择器重复。再改：播放时检查应为自动补齐默认、去掉开关；清理同名账号可进详情看完整凭证；刮削成功入库后可把同目录新曲同步进当前播放列表（见下）。

**取舍（锁定）**：
1. **去掉** `shouldAutoBackfillOnLibraryOpen` / 打开音乐库 tab 自动入队。
2. **起播触发**（`AudioPlayerService` 成功 `loadAndPlay` 后）：已知 `accountId` + `sourceName` + `remotePath` 时，只 `listDirectory` **当前曲父目录一层**（`WalkOptions(includeSubdirs: false)`）；与本地库该 source 的远端路径 diff；仅缺失路径 `enqueueScan`（刮削语义，**不下载**；下载只走缓存播放等播放模式）。自动补齐开启时**始终**允许起播浅层刮削——**已移除**「播放时检查」开关 / `musicLibraryBackfillOnPlay` API；旧 prefs 键 `music_library_backfill_on_open` 读入时忽略。
3. Pref：
   - `music_library_auto_backfill`（默认 false）= 自动补齐总开关（开则默认起播浅层刮削）。
   - `music_library_backfill_bind_roots`（默认 false）：关 = 不做绑定过滤，起播总是浅列父目录；开 = 先用绑定根对当前曲 `remotePath` 做前缀匹配，不命中则整次跳过，命中再扫父目录一层。
   - `music_library_backfill_roots`：绑定根 UI 仅在绑定开关开时显示。
4. **账号同名（DB 兜底）**：名称是逻辑主键（`normalizeSourceName` + 大小写不敏感 = `accountNameKey`）。应用层 `addAccount`/`updateAccount` 拒绝重名（友好错误）；`library_database` schema **v11** 对 `accounts.name_key` 加 **UNIQUE** 作硬底。历史同名：启动检测后展示**临时清理 UI**，冲突行可点进**详情页**查看完整凭证（名称 / id / URL / 用户名 / 密码可见切换 / 远程路径 / 类型）以便区分，再手动删除；名称唯一后才创建 UNIQUE 索引（或已存在则跳过）。**不**在启动时自动折叠/合并同名行；选择器**不**自行去重。备份恢复仍按名去重；同名接管（按 id 恢复）可删掉占用该名的另一行。
5. 显式网络库扫描两种模式都可；自动入队仅自动补齐门控。
6. 更新标签 / 空库文案保持「更新标签」与可扫描入库。
7. **起播刮削后同步当前播放列表**（内存 now-playing，非已存歌单文档）：
   - 仅当本次起播浅层刮削**发现缺失并入队**刮削任务时登记意图；列出无缺失则不碰队列。
   - **等该刮削任务成功入库后再改队列**；失败 / 取消则放弃；若完成前用户已切到其他目录 / 队列（当前曲 source+父目录与登记不一致）也放弃，不做迟到静默改写。
   - 范围：只改内存播放队列；只追加**同一 source + 同一父目录**的新入库曲，按远端路径序插入该段；**不删**已有项、不重排其他目录、不中断当前曲 / 不 seek、不停止播放、不清空队列、不自动下载。

### 17.18 歌单：当前播放列表 → 已有歌单（已落地）

- 除「从当前播放列表创建」新歌单外，可将**内存 now-playing 队列**整批加入**已有歌单**（歌单页 AppBar / FAB，以及当前播放列表页动作）。
- 复用 `showAddManyToPlaylistDialog`；已在目标歌单中的条目按 identity 跳过（`PlaylistService.addTrack`）。
- **不**因此改自动补齐后的队列同步规则（§17.17 第 7 点）。

### 17.19 音乐库选曲器行展示（计划，未做）

用户反馈：仅显示歌名过于抽象。计划改为**文件夹路径风格**行（展示路径层级 / 所在目录信息，便于区分同名曲），具体字段与布局待定后实现。**本轮只记文档，不改选曲器 UI。**

**0.2.4 计划**：见 [§18](#18-用户文件夹树与-024-历史兼容清理进行中)（本分支 `feat/v024-library-folders` 执行）。

## 18. 用户文件夹树与 0.2.4 历史兼容清理（进行中）

**状态**：2026-10-12 基于 `origin/main` tip `7756275` 开分支 `feat/v024-library-folders`（worktree：`worktree/v024-library-folders`）。用户偏好中文 UI。不推 `main`、不发版。

**相关完整文档**：[01](01-DATA-MODEL.md)、[02](02-NETWORK-LIBRARY.md)、[03](03-MUSIC-LIBRARY.md)、[05](05-AUDIO-PLAYBACK.md)。开发期间上述文档只留一行占位指向本节。

### 18.1 产品锁定：本地用户文件夹树（叠加层）

**用户原话级**：

1. **本地-only** 用户文件夹树，用来组织曲库内容；**不要**改扁平曲库元数据表作为曲目身份源——文件夹是**独立叠加层**。
2. 允许多层嵌套；**叶子**挂引用（本轮：专辑 / 艺人 / 曲目）；更细粒度以后只在文档登记。
3. 选择器默认落在「**我的文件夹**」；路径风格展示（例：`我的文件夹 / 摇滚 / 2020`）。
4. 往文件夹里加内容：参照**网络库**浏览 / 多选交互。
5. 同分支做 0.2.4 历史 DB 兼容删除（见 §18.4）。
6. 预载旁注：预载只管**正在进行的网络拉取**；已刮削 + 已缓存不得被串流邻居窗口过滤伤害（见 §18.5）。

**取舍（锁定）**：

| 项 | 决定 |
|----|------|
| 存储 | `music_library.db` 新表 `user_folders` / `user_folder_items`；**不动** `tracks` / `cue_*` 身份列 |
| 虚拟根 | 「我的文件夹」**不是**库行；`parent_id IS NULL` = 挂在虚拟根下 |
| 叶子引用 kind（v1） | `album` / `artist` / `track` |
| 引用键 | 专辑 = `LibraryTrack.displayAlbum`；艺人 = `displayArtist`；曲目 = `music_id`（与现有分组一致） |
| 新建文件夹默认名 | 存储哨兵可沿用界面「新文件夹」文案键；不写进 tracks |
| 销毁曲库 | `clearAllLibraryData` 清文件夹树 + 引用；`clearLibraryIndex` **只清引用**（树壳保留） |
| 同步 / 备份 | **本轮不做**远端镜像；纯本机 |

### 18.2 选择器与可扩展维度（v1）

**v1 只做**三种「添加」选择器，且**一律带搜索**：

| 选择器 | 数据源 | 行展示 |
|--------|--------|--------|
| 添加专辑 | 扁平专辑列表（`groupedByAlbum` 的 key） | 专辑名 + 曲数 / 艺人摘要 |
| 添加艺人 | 扁平艺人列表（`groupedByArtist`） | 艺人名 + 曲数 |
| 添加曲目 | 扁平曲目列表 | 标题 + 艺人 / 专辑（路径风格摘要可后续接 §17.19） |

交互参照网络库：列表浏览、搜索过滤、多选、确认写入当前叶子文件夹。文件夹目的地选择器（移动 / 新建后放入）默认路径 = 「我的文件夹」，路径条可横向滚动。

**抽象（本轮落地）**：`LibraryTagDimension`（或同名）描述「扁平标签维度」——`id` / 如何从 `LibraryTrack` 取分组键 / 如何解析显示名 / 如何列出候选项。v1 注册 `album` / `artist`；`track` 是按曲目而非按标签分组，走同一选择器外壳但数据源是曲目列表。

**可插拔、本轮不实现的维度**（只文档）：`genre`、`year`、远端父路径、`composer` / `lyricist`、`albumArtist`。以后按同一 `LibraryTagDimension` 注册即可，不必再做第三套选择器。

### 18.3 UI 落点

- 主导航增加「**文件夹**」（中文）顶级入口，排在音乐库 / 网络库之前；进入后是网络库式目录浏览（进子夹、上一级、路径条）。**不**嵌在音乐库内。
- 叶子文件夹 AppBar / ⋮：新建子文件夹、添加专辑、添加艺人、添加曲目、重命名、删除。
- 非叶子：只显示子文件夹；叶子同时显示子文件夹（若有）与引用行。
- 点专辑 / 艺人引用 → 展开为该组曲目（复用现有详情列表模式）；点曲目 → 按媒体库默认打开方式播放。

### 18.4 同分支：0.2.4 删除历史 DB 兼容

按先前 0.2.4 约定：

1. **删除** `migrateLegacySentinelsOnce` / `lib/services/legacy_sentinel_migration.dart` 及 `AppState.init` 调用；0.2.4 起旧中文哨兵库不再兼容迁移。
2. **账号同名临时门闸**：正常新装 CREATE TABLE 已带 `UNIQUE(name_key)`；无冲突升级也会装上 UNIQUE 索引。因此**撤掉**启动态 `AccountNameCleanupScreen` / `needsNameCleanup` 门闸。
3. **仅当**仍存在同名 `name_key`、UNIQUE 装不上时，才做一次非静默的必要收敛：每组保留一条（优先当前活跃账号，否则最小 `id`），删其余账号行 + secure 密码 / 驱动配置，再施加 UNIQUE。**无冲突则不合并。**
4. 删掉 `account_name_cleanup_screen.dart`；测试改为覆盖「有冲突时 keep-one + UNIQUE」。

### 18.5 预载旁注（串流邻居窗口）

**语义**：`MusicPrefetchService` / `prefetchNeighborIndexes` **只**决定还要不要向网络拉封面 / 音频；**不得**影响：

- 已在 `music_cache` 的可播判定（`resolvePlayable` 仍先查缓存）；
- 已入库的标签 / 封面行；
- 播放队列里窗口外曲目的存在。

若代码路径已满足，本轮加注释 + 99 记实；若发现窗口过滤误伤已缓存解析，再小修。

### 18.6 实现顺序

1. 本文件收口计划（本条）。
2. schema v12 叠加表 + `UserFolderService` + `LibraryTagDimension`。
3. 文件夹浏览 / 目的地选择器 / 三种带搜索添加选择器 UI。
4. 媒体库 Tab 接入；ARB 中/繁/英。
5. §18.4 兼容删除 + 账号 keep-one。
6. §18.5 文档 / 必要注释。
7. `flutter analyze` + 相关 `flutter test`；推送功能分支（非 main）。

### 18.7 未决 / 开放问题

- 备份 / 云端是否将来纳入用户文件夹树（本轮明确不做）。
- 专辑键目前与 `groupedByAlbum` 一样仅用专辑名，同名异艺人会并组——与现专辑 Tab 一致；若以后要 `(albumArtist, album)` 复合键，叠加层可迁，不改 tracks 表。
- §17.19 选曲器路径风格行展示仍未做；曲目添加选择器本轮用标题 + 艺人 / 专辑摘要。

### 18.8 文件夹 Tab UI 抛光（本轮）

**用户原话级**（路径条 / 封面 / 视图 / 选择器 / 曲目行文案 / 「+」 / 网格更多）：

1. 路径条：缩小路径盒；去掉分隔线，改为大圆角浅底圆角矩形。
2. 目录列表（列表视图）显示专辑封面；复用本地封面缓存（`LibraryCoverArt` / `pickCoverTrack`），不新开远程拉取。
3. 视图切换：列表 + 网格 5→2 列；网格单元同样显示封面。视图模式持久化 prefs 键 `folder_view_mode`（`list` / `grid2`…`grid5`），默认列表。
4. 专辑（及艺人 / 曲目）添加选择器：已有搜索，本轮核验保留。
5. 流派 / 艺人展示：暂用专辑封面；插桩 `LibraryGroupCoverOverrides.resolver`（`lib/utils/library_group_cover.dart`），日后自定义封面可直接挂上。流派 Tab 列表 leading 同步改为专辑封面。
6. 文件夹内曲目行：主名只显示标题；小字区两行分别为专辑、音轨号；不额外加大行盒。
7. 路径条尾部「⋯」改为「+」（添加菜单）。
8. 网格单元带「更多」；三点控件随格子尺寸缩放。

**仍不做**：不改扁平 tracks 元数据 schema；自定义封面 UI / 资源选择器未做（仅插桩）。

### 18.9 文件夹独立壳 + 曲目副标题 + 任务组合并删除（本轮）

**用户锁定（2026-10-12）**：

**A. 曲目副标题布局**（文件夹曲目行 + 音乐库「歌曲/标题」`_TrackTile`）：
- 主行只显示标题
- 小字行 1：专辑 + 碟号 + 音轨号（一行）
- 小字行 2：优先艺人，否则专辑艺人；二者皆无则省略
- 尽量不撑高现有行高（`dense` + 紧凑 MetaText）

**B. 网络库下载文案清理**：
- 单文件「更多」去掉「设置里的默认动作」「不下载、不进音乐库」说明
- 列表行去掉「点按下载」提示；底部表头副标题只留类别
- 其他文件更多菜单同样去掉默认动作说明

**C. 任务合并视图**：
- 合并组增加「全部删除」
- 详情 BottomSheet 内删除后经 `Consumer` 同步回合并列表（成员清空则关表）

**D. 文件夹独立管理 + chrome**：
- 「文件夹」从音乐库抽出，作为主导航（抽屉）**顶级入口**，与「音乐库」「网络库」同级，且排在三者**最前**（索引 0；音乐库 1；歌单 2；网络库 3；任务队列 4；设置 5）。仍挂 UserFolderService。不再嵌在音乐库 SegmentedButton / 子 Tab。
- 多选 + 「更多」；破坏性删除只在多选更多 / 行更多菜单，不放在 + 旁主 chrome
- 叶子引用右侧类型芯片（专辑/歌手/流派/曲目）；文件夹节点不加类型标签
- 视图模式按文件夹 id 持久化（`folder_view_modes_json`；根用 `root`；迁旧全局 `folder_view_mode`）
- `home_tab_index`：首次启动检测 `home_tab_v024_folders_inserted`，已有用户索引整体 +1，避免原先「网络库 / 任务 / 设置」主页错位。

**E. 曲目副标题数字（本轮补）**：
- 碟号 / 音轨号只显示**原始数字**，不加「碟」「音轨」等标签；缺字段整段省略（无「音轨 —」占位）。

**F. 任务队列文案「下载」→「同步」**：
- 任务列表状态 / 清队列确认、入队 Snackbar、系统通知通道名与进度 / 完成标题，统一改为同步语义（中/繁/英 + Kotlin 保活回退文案）。

**仍跳过**：自定义封面选择器 UI、文件夹树备份同步、专辑复合键。


## 19. 漫画库（已完成，2026-10-13 并入 main）

**状态**：2026-10-12 基于 `main` tip `e0d7280` 开分支 `feat/manga-library` 开发，2026-10-13 `flutter analyze` 与全量 `flutter test` 通过后快进并入 `main`；2026-10-13 真机验收通过（用户确认）。用户偏好中文 UI。

**相关完整文档**：[01](01-DATA-MODEL.md)、[02](02-NETWORK-LIBRARY.md)、[03](03-MUSIC-LIBRARY.md)（对照音乐库交互）。

### 19.1 命名锁定（2026-10-12）

可读单元概念上曾称 Book，但**任何全局 / 共享 / 跨模块**字段、表、类型、id、路径键、软引用 kind **必须用 `manga`，禁止 `book`**。电子书以后需要 `book`。本地注释可写「可读单元」；代码符号：`Manga`、`manga_id`、`mangas`、`MangaSeries`、`manga_series`、叶子 kind `manga` / `mangaSeries` 等。

### 19.2 产品锁定

1. **Manga** = 唯一管理 / 扫描 / 进度 / 软引用单元（一个可读容器：CBZ/CBR/PDF/EPUB，或一整目录图片当作一本）。
2. **MangaSeries** 只链接 / 排序 Mangas（类似专辑分组）；进度按 Manga 的页索引；系列可展示汇总，不拥有进度行。
3. **身份 / PK**：`(source_name, normalized_remote_path)` — **无内容哈希**。路径索引，远端可按网盘名重绑。有 ComicInfo.xml / 格式头则持久化元数据，否则文件名 / 文件夹派生，再冻结页列表。
4. **分话发布**（一 CBZ/目录 = 一话）：仍是 Manga，带 `chapter_number`（卷常空）。
5. **单行本 / 卷**：Manga 带 `volume`；仅当容器内已有章节子目录才嵌套，不发明拆分。
6. **散图目录（用「建立 / 创建」措辞，不用「扫描」）**：列目录、筛图片、**不下载整本**建索引；默认封面 = 排序后第一张图，建立和重新扫描时单独下载这一张并写成缩略图（失败不让建书失败）。阅读器中间选项表可以把当前页设为封面（先确认，再以可取消的阻塞对话框执行）。提交前确认表可改元数据。支持子目录，两种模式：
   - **合并建立**：整棵树（或选定文件夹）内图片 → **一本** Manga；默认标题 = 根文件夹名。
   - **按目录批量建立**：遍历结构；每个含图目录各自成为一本 Manga；**标题 = 该目录名**。
7. **结构化容器（CBZ/CBR/PDF/EPUB，用「扫描」措辞）**：文件夹可**递归**扫描子目录中的漫画容器并**批量加入**；单文件「加入漫画库」。建立时先落 Manga 行（只读文件名），随后入队的刮削任务用 Range 读 ComicInfo 与首页封面补齐元数据与页表（见 [19.14](#1915-扫描刮削与整包缓存改入任务队列2026-10-13)）。
13. **漫画库 · 单本 Tab 多选**：除常规多选外，提供 **批量修改系列** — 多本 Manga 一并指到同一系列（可新建或选已有）。
8. **页列表**：入库时冻结排序后的相对路径到 DB；阅读器按该序。
9. **用户文件夹**：软引用稍后；本刀注册 `manga` / `mangaSeries` kind 常量即可。
10. **延后**：全库哈希去重、自动打 CBZ、远端元数据刮削、KOOBONE、超出用户文件夹的自定义结构。
11. **漫画库内 Tab**（对照音乐）：系列 / 单本 / 作者。
12. **抽屉顺序（用户更正 2026-10-12）**：文件夹(0) → 音乐库(1) → 歌单(2) → **漫画库(3)** → 网络库(4) → 任务(5) → 设置(6)。`home_tab_index` 一次性迁移：prefs 旗标 `home_tab_v025_manga_inserted`；已有用户保存索引 **≥3** 则 +1（与文件夹插入同模式）。

### 19.3 Schema（v13 加表 → v14 `page_turn` → v16 系列降为标签 → v17 用户文件夹去外键 → v18 散图代理键）

同库 `music_library.db`（多媒体库共用；不另拆库）。`LibraryDatabase.schemaVersion` **13 → 14**（v13 加漫画表；v14 `mangas.page_turn`）；v15 再加 `mangas.rev` / `deleted_mangas` / `local_meta`，见 [19.11](#1912-漫画库云同步--进度同步--文件夹同步--云端路径重排) 的「schema 15」；**v16 把 `manga_series` 表折进 `mangas.series` 标签**；v17 去掉 `user_folders` / `user_folder_items` 上的外键（虚拟根 `'root'` 要能挂软引用）；**v18 把漫画行的身份一分为二**——容器书仍是派生的 `mangaIdForRemote(源, 路径)`，散图（`format = 'images'`）改用代理键 uuid，详见 [19.20](#1920-散图代理键与-schema-v18散图身份2026-10-13)。升级路径：`_ensureMangaTables` 幂等（风格对齐 `_ensureUserFolderTables`）；**不** DROP tracks。

| 表 | 要点 |
|----|------|
| `mangas` | `id` TEXT PK（**容器**由 `mangaIdForRemote(源, 路径)` 推出；**散图**是代理键 uuid——v18）；容器唯一性由部分唯一索引 `idx_mangas_container_key`（`source_name, remote_path`，`WHERE format <> 'images'`）保证（v18 起取代表级 `UNIQUE`）；`series` TEXT nullable（v16；**不是外键**，就是行上的标签，空 = 未指定）；`title` / `author` / `volume` / `chapter_number`；`page_count`；`cover_relpath`；`format`=`cbz\|cbr\|pdf\|epub\|images\|unknown`；`remote_path` / `source_name`；`remote_missing`；`page_turn` nullable（v14；`ltr`/`rtl`；null=跟随全局）；`updated_at` |
| `manga_pages` | PK `(manga_id, page_index)`；`rel_path`（容器 = 包内条目名；散图 = **相对网盘根**的完整路径，v18 起） |
| `manga_progress` | PK `manga_id`；`page_index`；`updated_at` |
| `deleted_mangas` | PK `manga_id`（v18 起；此前是 `(source_name, remote_path)`）；`source_name` / `remote_path` / `sync_key` / `rev` / `deleted_at` / `pushed` |

索引：`series`、`author`、`source_name`，以及部分唯一索引 `idx_mangas_container_key`（v18）。

**系列不是实体（v16，用户 2026-10-13 决定）**：`manga_series` 表已删除，模型侧 `MangaSeries` 退化为**派生视图**（只剩 `title`，`id = mangaSeriesIdForTitle(title) = sha1('mangaSeries\0' + trim(title))`）。系列列表 / 本数 / 封面全部由行分组派生，所以**空系列在结构上不可能存在**，也就没有「系列作者」这种可独立编辑的字段——改名 = 给成员行重新打标签（等于合并），清空 = 解绑。这与音乐库的 `tracks.album` 完全同构（`LibraryTrack.album` 也是一列，空值用哨兵 `kUnknownAlbum`，显示时才换成本地化词；列表与封面分别由 `library_screen.dart` 的 `groups.keys` 与 `library_group_cover.dart` 的 `pickCoverTrack` 派生）。迁移在 `_ensureMangaSeriesTag`：先 `ALTER TABLE mangas ADD COLUMN series TEXT`，再把 `manga_series.title` 按旧 `series_id` 回填进行，最后 `DROP TABLE manga_series`。

### 19.4 本刀交付

- 模型 + DB ensure + `MangaLibraryService`（按系列 / 单本 / 作者列表、扫描 upsert、进度 get/set）
- 网络库：文件夹「扫描漫画文件」（递归批量容器）+「合并建立漫画」+「按目录批量建立」；单文件「加入漫画库」
- 漫画库屏：Segmented 系列/单本/作者；单本 / 系列内 / 作者内都能多选（批量修改系列、清理缓存、删除）；列表显示 `x/y` 阅读进度，网格显示封面进度条
- HomeShell 抽屉 + IndexedStack + home_tab 迁移
- `UserFolderRefKind.manga` / `mangaSeries` 常量
- ARB zh / zh_Hant / en；`flutter analyze` + `flutter test` 全绿
- 漫画单文件在网络库里成为一等文件类别（`FileCategory.comic` + `FileAction.addToMangaLibrary`），见 [19.12](#1913-漫画单文件成为一等文件类别2026-10-13)

### 19.5 阅读器（本刀升级）

- **复用** `ImageViewerScreen`（网络图与漫画同一套 chrome / 预取 / 下载）。
- 中间点击 → **选项 BottomSheet**（适应方式、**翻页方向**、幻灯片、进更多设置）；左右点与横向滑动翻页。
- 预取每侧 **1–20**（设置 `image_prefetch_count`）。
- 散图：按冻结 `manga_pages` 远端路径下载；CBZ：HTTP Range 读 ZIP 中央目录后**按页惰性抽取**（先抽阅读记录那一页，其余页随查看器的预取窗口按需落地）；CBR / PDF / EPUB 不支持应用内读（见 [19.18](#1919-图片扫描深度与-cbz-首屏2026-10-13)）。
- 翻页写 `manga_progress`。
- **翻页方向**（LTR / RTL）：
  - 全局：`SharedPreferences` 键 `image_page_turn`（设置 → 图片查看；非漫画查看器 BottomSheet 仅全局）。
  - 每本：`mangas.page_turn`（nullable；null = 跟随全局）。漫画阅读器 BottomSheet 有「全局」+「当前漫画」（跟随全局 / LTR / RTL）。
  - 改动立即生效；改当前漫画不改写全局。

### 19.6 明确不做

完整阅读器 chrome（已改为共享查看器）、文件夹选择器加漫 UI（kind 常量即可）、打开即自动补齐整本页表。

### 19.7 开放问题

- CBR / PDF / EPUB 的页索引是否要接本地解析器（本刀只做 CBZ 与散图，见 [19.9](#1910-锁定缺口2026-10-12本轮必须落地) 第 10 条）
- 系列自动归并规则（手填 vs 文件夹名启发）

### 19.8 设置默认（媒体库 → 漫画库）

| 键 | 默认 | 用途 |
|----|------|------|
| `manga_scan_subdirs` | **开** | 扫描漫画文件时进子目录 |
| `manga_scan_max_depth` | **1** | 扫描深度（与建立独立）。2026-10-13 起默认 1：漫画目录天然扁平，扫太深会把整棵盘扫进来 |
| `manga_create_subdirs` | **开** | 散图建立时进子目录 |
| `manga_create_max_depth` | **1** | 建立深度（与扫描独立），同上 |
| `manga_read_mode` | **流式** | 打开漫画时的默认读取方式（流式 / 先整包缓存）。流式失败时对话框可当场改成缓存并记住 |
| `manga_cache_retention` | **一周** | 漫画缓存的过期清理时长（与音乐的 `retention` 分开） |
| `manga_cache_custom_retention_hours` | **720** | 上面选「自定义」时的小时数 |

与音乐刮削 / 播放列表 walk prefs **完全分开**。网络库文件夹动作读 `mangaScanWalkOptions` / `mangaCreateWalkOptions`。

### 19.9 文案对照（网络库文件夹）

| 动作 | 中文倾向 | 说明 |
|------|----------|------|
| 递归找 CBZ 等 | **扫描**漫画文件 | 批量加入，不下载整包 |
| 散图合并为一本 | **合并建立**漫画 | 不说「扫描」 |
| 散图每目录一本 | **按目录批量建立** | 标题 = 目录名 |
| 单容器文件 | **加入**漫画库 | 与文件夹扫描并列 |

### 19.10 锁定缺口（2026-10-12，本轮必须落地）

命名：全局字段一律 `manga`，禁止 `book`。

1. **封面**：漫画库列表（系列 / 单本 / 作者）显示封面。
2. **视图模式**：列表 / 网格 2–5 列（同文件夹）；**按**漫画子 Tab（系列 / 单本 / 作者）分别持久化；默认 **列表**。
3. **音乐库**：同样可配置视图模式，**按**音乐子 Tab 分别保存；默认列表。
4. **单本 Tab**：分区「未指定系列」（`series` 为空 **或** 系列名等于哨兵「未指定」；v16 前的 `series_id` 为空与此等价）。
5. **CBZ 流式**：HTTP Range 读 ZIP 中央目录 + 按页抽取；若源不支持 Range → **拒绝流式**并提示整包缓存。
6. **CBZ 刮削**：后台任务类别（与音乐刮削分开），ComicInfo / 元数据 + 封面抽取；队列形态对齐音乐刮削。
7. **元数据编辑**：漫画标题 / 系列 / 作者；系列整体改名（批量重新打标签，等于合并到新名）；作者重命名**级联**所有漫画；空系列名 = 未指定。**v16 起没有「系列作者」这一项**——系列只剩名字。
8. **本地缓存**：独立 `manga_cache/` 路径。2026-10-13 起**各自一套缓存设置**（见 [19.13](#1914-按库分开的缓存设置与缓存索引2026-10-13)）：漫画库设置页里有自己的缓存占用 / 过期清理 / 容量上限 / 全部清理，不再与音乐挤在同一页；设置偏好 + 更多菜单手动缓存（对齐音乐）。
9. **用户文件夹**：软引用 `manga` + `mangaSeries`；除删除外支持 **移动** + **复制**（引用复制）；选择器根在用户文件夹；自身 / 子孙灰显。
10. CBR / PDF / EPUB 保持 stub。

prefs：`manga_view_modes_json`（键 `series` / `manga` / `author`）；`music_view_modes_json`（键 `albums` / `artists` / `titles` / `genres`）；复用 `FolderViewMode`。漫画缓存上限键 `manga_cache_max_mb`（0=不限），保留期见 [19.13](#1914-按库分开的缓存设置与缓存索引2026-10-13)；视图键除三个 Tab 外，详情页与文件夹叶子页另有各一套（见 [19.17](#1918-文件夹叶子引用页复用媒体库子页2026-10-13)）。

任务：`TaskKind.mangaScrape`（storage `manga_scrape`）——与 `scan`（音乐）分列。


### 19.11 批量任务部分失败（锁定）
- 扫描（音乐刮削/标签更新）与漫画刮削：每个文件内部自动重试至多 3 次（`lib/utils/batch_outcome.dart` `retryItem`；取消不重试；Range 不支持不重试）。
- 仍失败的文件记录 errorMessage，批次继续。终态：全成功 → completed；部分失败 → 新 `TaskStatus.partial`（「部分失败」，橙色）；全失败 → failed。
- 手动重试沿用现有 `TaskQueueService.retry`（已放行 partial）；扫描为增量，重跑只会补失败项。合并任务卡片/单任务卡片的重试按钮与通知汇总均已计入 partial。

### 19.12 漫画库云同步 / 进度同步 / 文件夹同步 / 云端路径重排

**用户决定（2026-10-12）**：进度本地持久化并同步；路径改为 `<远端路径>library/music/`、`library/manga/`，留扩展位，**不兼容旧 `library/` 平铺布局**；漫画同步完全对照音乐（index.json + lib-/seg-/del-*.wdmm、rev + 墓碑、增量 / 重建 / 整理 / 覆写 / 删除、一键同步 + 防抖 + 定时；增量始终带封面，重建「嵌入封面」默认开）；全部备份含漫画表 + 进度 + 用户文件夹；用户文件夹整份快照同步，路径与合并规则由实现方定。

- **manga_pages 是否覆盖 CBZ**：是。散图在入库时写；CBZ 在首次打开（Range 读 zip 目录或已下载 zip，`manga_reader_prep.dart`）或刮削任务（`replacePages`）时冻结页序。
- **页序按类分流（用户决定 2026-10-12 晚 → 10-13 定案）**：`manga_pages` 按漫画类别分两种待遇。
  - **A 类 散图（`format = images`）**：页表是数据（成员集合 + 顺序），**进**同步分片（`WmpManga.pages = 18`，JSON 数组，`MangaSyncRow` 只对 images 填充；CBZ 等容器行永远不带）、**进**全部备份 v7 漫画段 `pages` 段。本地编辑页表 bump `mangas.rev`；从云端拉取时**替换本地页表且不 bump**（避免回环重传）；`replacePages` 只在页数 / 封面变化时改行。恢复备份后散图页表直接可用。**v18 起散图是代理键**：`id` 是 uuid（`newMangaId()`，不从任何属性推导），页 `rel_path` 是相对网盘根的完整路径，书与目录彻底解耦——同一目录可以并存多本（merged 与 perDir 的成员集合本就不同，因此不再需要 `build_mode` 列），目录改名 / 移动也不影响身份。旧散图行在升级时被丢弃，见 [19.20](#1920-散图代理键与-schema-v18散图身份2026-10-13)。
  - **B 类 容器（CBZ / CBR / PDF / EPUB）**：页序由文件推出，**只作本地缓存**——不进同步分片、不进全部备份，不做兼容。别的设备拉到行 / 恢复备份后照旧首次打开（`manga_reader_prep.dart`）或刮削时生成。写页序**永不 bump rev**；`replacePages` 只在页数 / 封面变化时改行，所以重建缓存不会触发重传。
  - `0e77127` 里「散图缺页序时打开即递归列目录重建」的实现已删除——散图的页表是建立时筛选出的成员集合（扩展名、深度、子目录开关、按目录模式只取本层），列目录无法复现，且按目录模式下父目录会吞掉子书。现在散图缺页表时直接报空页错误，让用户回网络库重建该本。
- **远端布局**：`library/music/`（原音乐库内容，不迁移旧路径）、`library/manga/`（`index.json` format `wmp_manga_library_index` + 分片 + `progress.json`）、`library/folders/folders.json`。
- **漫画行合并**：容器书键 `网盘名 + 规范化 remotePath`，散图书键是**自身 uuid**（分片里 `WmpManga.mangaId` = tag 20）；高 rev 胜（与到达顺序无关）；墓碑只在 `tomb.rev >= row.rev` 时隐藏；本地写入清掉本地墓碑。系列就是行上的 `mangas.series` 标签（v16 起），线上仍写 `WmpManga.seriesTitle`（tag 7），系列 id 由标题确定性推出 `sha1('mangaSeries\0'+title)`，避免跨设备分裂；tag 6 / 8 / 9（`seriesId` / `seriesAuthor` / `seriesSortTitle`）已退役，读端忽略、写端不再产出。
- **进度合并**：每个 manga_id 独立，较新 `updatedAt` 胜；相等不动。增量同步时一并读写 `progress.json`。
- **文件夹合并**：整份快照 LWW。本机自上次同步后改过 → 推；只有云端 `updatedAt` 变了 → 拉（整份替换本地）；两边都改 → 本机修改时间与云端 `updatedAt` 比，新者整份胜，另一方修改丢弃不合并。本机修改时间在 `local_meta.folders_changed_at`，上次同步与所见云端时间按目的地存在 `local_meta`。
- **备份**：`formatVersion 7`，新增段 `mangaLibrary = 13`（漫画 / **散图页行** / 进度 / 墓碑 JSON，容器页序不入归档）、`userFolders = 14`、`mangaCovers = 15`（**漫画封面缩略图字节**，与音乐 `COVERS = 3` 同一套连续布局，每本一份；归档里不存路径——本地路径由漫画 id 派生，所以行上只带一个 `cover_index`，恢复时写回 `manga_cache/covers/` 并抹掉下标）。恢复时散图页表直接可用，容器本地页序缓存清空，按上条重新生成。
- **schema 15**：`mangas.rev`、`deleted_mangas`、`local_meta`。音乐「覆写」不再清漫画 / 文件夹；同步游标按前缀 `library:` / `manga:` 分开清。
- **schema 16（2026-10-13）**：`manga_series` 表折进 `mangas.series` 标签（见 [19.3](#193-schemav13-加表--v14-page_turn--v16-系列降为标签)）。迁移回填旧系列名再删表；`LibraryDatabase` 不再有 `loadMangaSeries` / `upsertMangaSeries` / `deleteMangaSeries`，`loadMangas` 按 `series` 过滤。快照导出不再带顶层 `series` 列表（系列由行派生），但导入**仍认**旧快照里的 `series` 列表——靠它把老的 `series_id` 还原成名字，所以 v15 及更早的归档仍能还原分组。
- **顺带修复**：同步页碎片提示「（约 true）」——gen-l10n 无 @ 元数据时占位参数按字母序生成（`count, hint, size`），调用方按模板顺序传了；`stepMangaIncremental` 同理按 `adopted, progress, tombs, uploaded` 传。图片预取测试按上限 20 改为 9→9、25→20。

### 19.13 漫画单文件成为一等文件类别（2026-10-13）

用户要求「对于 cbz 之类的漫画单文件，后缀设置里加上」与「参考音乐实现网络库的行为」。

- **`FileCategory.comic`**：`FileTypeConfig` 新增 `comicExtensions`（默认 `kDefaultComicExtensions` = **只有 cbz**——阅读器只解得了 ZIP，cbr / pdf / epub 会在 `MangaReaderPrep` 里报 unsupported，所以不放进默认值，用户要自己加；存储键 `comic`，与 `music` / `video` / `cue` / `image` 并列）。判定排在**图片之后**，所以把 `png` 写进漫画列表也不会从图片类别里抢走文件。旧配置没有 `comic` 键时补默认；显式清空则一个后缀都不认（`isComicContainerFileName` 收到空列表返回 false，不回退默认）。
- **`FileAction.addToMangaLibrary`**（存储键 `add_to_manga_library`，`downloadTarget` 为 null）：漫画单文件的出厂默认动作，与音乐的「缓存音乐」同构；`FileActionCatalog.comic = [addToMangaLibrary, download]`，但 `FileActionConfig.choicesFor` 会把 `download` 从漫画的可选列表里滤掉——**下载不作为漫画的单击动作**，要下载只走多选或行尾「⋮」。
- **网络库**：整行点按 = 加入漫画库（确认表 → `draftForComicFile` → `upsertFromDraft` → `enqueueMangaScrape`，刮削在任务队列里可见）；「更多」菜单第一条就是它，原来那条 `if (isComicContainerFileName(item.name))` 的专用项已删除（重复项）；多选工具栏新增「加入漫画库」按钮（`Icons.menu_book_outlined`），选中的单文件直接建立、选中的文件夹用 `listComicContainersRecursive` 递归扫出，按路径去重后一起建立并刮削，只报一次结果。
- **后缀设置页**：新增「漫画文件」一节（文本框 + 应用 + 恢复默认）。动作那一行不放下拉框，只显示当前动作——它固定是「加入漫画库」，与漫画库设置页的「点按行为」是同一个值。
- **设置备份**：`comic` 键随 `fileTypes` 进 `WmpSections.settings`（见 [08 §5](08-SYNC-AND-BACKUP.md)）；旧归档没有该键，导入时补默认。
- **迁移兼容**：两处旧设置迁移（`SettingsService._legacyFileActions` 与旧的 `music_tap_action` 路径）都补了 `FileCategory.comic`，否则 `FileActionConfig` 按类别构造会漏这一类。
- **测试**：`test/file_action_model_test.dart` 补了漫画后缀 / 「漫画不抢图片」/ 「清空漫画后缀」三组断言；原「`readme.pdf` → 普通文件」的断言随之改为 `readme.txt`。

### 19.14 按库分开的缓存设置与缓存索引（2026-10-13）

用户要求「缓存设置合并进各自的库设置子页」「用独立的缓存管理」「用独立缓存数据库记录文件访问时间」。

- **缓存索引库** `lib/services/cache_index_db.dart`：独立 sqlite 文件 `cache_index.db`，表 `cache_entries(path PRIMARY KEY, kind, size, accessed_at)`，`schemaVersion = 1`。`CacheKind { music, manga }`（`lib/models/cache_policy.dart`）。读写全部 try/catch 静默——索引只是**加速器**，丢了退回 mtime，不能因此让缓存操作失败。
- **`CacheService`**：新增 `attachIndexDb`、`touchMangaFile` / `touchMangaCover` / `registerMangaFileWritten` / `registerMangaCoverWritten`、`cleanupExpired({kind, policy})`、`evictCacheToMaxBytes({kind, maxBytes})`、`pruneIndex(kind)`、`cacheSizeFor(kind)`。访问时间优先读索引，回退 `cache_access` 表的音乐条目、再回退 mtime。
- **漫画封面不参与过期与上限淘汰**：`_cacheCandidates(CacheKind.manga)` 跳过 `covers/` 与 `.part`。缩略图极小、且 UI 只读不生成（`manga_cover_art.dart` 只读不生成），删掉就要等下次刮削才有；只有显式的「全部清理」会连它一起删。
- **设置**：新增 `manga_cache_retention` / `manga_cache_custom_retention_hours`（音乐继续用全局 `retention` / `custom_retention_hours`），并加 `musicCacheExpiryPolicy` / `mangaCacheExpiryPolicy`。
- **界面**：`lib/widgets/library_cache_settings.dart` 的 `LibraryCacheSettings(kind:)` 是唯一的缓存区块（占用 / 过期时长 / 容量上限 / 全部清理，按 kind 分发到不同的 AppState 方法）。`cache_settings_screen.dart` **已删除**；设置 →「媒体库」现在是「音乐库」「漫画库」两个平级入口，各自页内带自己的缓存区块（`lib/screens/manga_library_settings_screen.dart` 是新页）。
- **漫画库设置页顺序**：扫描 / 建立的子目录开关与深度 → 打开方式（`manga_read_mode`）→ 缓存区块。

### 19.15 扫描刮削与整包缓存改入任务队列（2026-10-13）

用户要求「漫画扫描刮削没有进入任务队列，只是在后台静默完成，不符合预期」「漫画缓存应该也和音乐缓存一样，先进任务队列而不是占着前端」。

- **刮削入队**：网络库三处建立入口（`_scanComicContainers` / `_ingestComicSelection` / `_ingestComicFile`）在 `upsertFromDraft` 之后改为 `TaskQueueService.enqueueMangaScrape(...)`。早期那个「就地 await 一次、失败吞掉」的 `scrapeMangaNow` 已整个删除——它就是「静默完成」的来源。
- **整包缓存入队**：新增 `TaskKind.mangaCache`（storage `manga_cache`），配 `enqueueMangaCache(...)` 与 `_runMangaCache`。漫画「更多」里的「缓存整包」不再借用阅读器（原来是 `openMangaReader(forceFullCache: true)`，会占着界面下载），改为入队并提示「已加入漫画缓存任务」。
- 两条任务共用 `localPath = manga:<id>` 的约定。

### 19.16 网络库漫画单文件：加入之后就是打开（2026-10-13）

用户要求「加入了之后再点击应该是走默认的串流打开，如果加入的时候默认是整包缓存，那就把缓存也加到任务队列里面完成」「对一个漫画重复加入……应该不加入队列也不提示而是直接打开才对」。

- 先按 `mangaIdForRemote(sourceName, normalizeRemotePath(path))` 查库：**命中就直接打开**，不弹确认表、不入刮削队列、不提示。
- 未命中才走建立流程；建立完成后按当前阅读方式收尾：`mangaReadMode == cache` 且本地还没有整包时排一条 `mangaCache` 任务（`_queueMangaCacheIfNeeded`），否则直接 `openMangaReader`。
- 只有 `MangaFormat.images`（散图）跳过缓存入队——它没有整包可下。

### 19.17 阅读进度显示（2026-10-13）

用户要求「文件夹和漫画库都要显示阅读进度，网格视图采用小进度条，列表视图采用 x/y 标签」。

- `MangaLibraryService` 新增内存进度表（`reload()` 里一次性 `allMangaProgress()`）、`mangaById`、`progressByManga`、`progressOf(mangaId)`；`setProgress` 同步更新。
- 列表视图：读到过时副标题显示 `mangaReadProgress`（`{current}/{total}`），没读过显示 `mangaPageCount`。
- 网格视图：封面右下角一条 3px `LinearProgressIndicator`，未读不画。
- 文件夹叶子页复用媒体库的展示组件，进度一起带过去（见 [19.17](#1918-文件夹叶子引用页复用媒体库子页2026-10-13)）。

### 19.18 文件夹叶子引用页复用媒体库子页（2026-10-13）

用户要求「文件夹的叶子引用页面也要有视图选择和与对应媒体库里相同的显示，如果可以的话可以直接引用对应的媒体库子页而不是另写」。

- **复用，不另写**：漫画系列叶子页直接返回 `MangaDetailScreen`（原 `_MangaDetailScreen`，已公开），音乐曲目叶子页返回 `TrackListPage`（原 `_TrackListPage`，已公开）；各自那个只画几行的私有列表页（`_FolderMangaListPage` / `_FolderTrackListPage`）已删除，多选、行尾「⋮」、封面、阅读进度全部与媒体库一致。
- 视图模式复用同一套 `mangaViewModeFor` / `musicViewModeFor`，但**用各自的键**，所以文件夹的视图选择不会串到媒体库的 Tab 上：漫画库 Tab 是 `series` / `manga` / `author`，漫画详情页是 `seriesDetail` / `authorDetail`，音乐库 Tab 是 `albums` / `artists` / `titles` / `genres`，音乐详情页是 `musicDetail:<维度>`，两边的叶子页各是 `folderLeaf:<kind>`（如 `folderLeaf:mangaSeries`、`folderLeaf:album`）。
- 音乐曲目本来只有列表，为此补了网格分支（`_TrackGridTile`），`TrackListPage` 现在也能切网格。


### 19.19 图片扫描深度与 CBZ 首屏（2026-10-13）
### 19.19 图片扫描深度与 CBZ 首屏（2026-10-13）


用户要求「图片查看也有扫描子目录，把深度设置也给加上，默认为 1」，随后要求「流式传输不该是从第一页开始加载」。
用户要求「图片查看也有扫描子目录，把深度设置也给加上，默认为 1」，随后要求「流式传输不该是从第一页开始加载」。


- **图片扫描深度**：新增偏好 `image_scan_max_depth`（默认 1，`WalkOptions.defaultMaxDepth`）与 `SettingsService.imageScanWalkOptions`；图片查看设置页在「搜索子目录」打开时显示深度输入；`image_viewer_screen.dart` 的手写 BFS 换成 `DirectoryWalker`，环路保护与条目上限一起拿到。
- **图片扫描深度**：新增偏好 `image_scan_max_depth`（默认 1，`WalkOptions.defaultMaxDepth`）与 `SettingsService.imageScanWalkOptions`；图片查看设置页在「搜索子目录」打开时显示深度输入；`image_viewer_screen.dart` 的手写 BFS 换成 `DirectoryWalker`，环路保护与条目上限一起拿到。
- **CBZ 首屏（惰性抽页）**：`_prepareCbzWithZip` 原来**无条件从第 0 页抽完整本**才返回，从第 150 页打开也要等 40 秒。现在先读 `progressFor` 定位起始页，只抽那一页，其余页挂 `ImagePageLoader` 闭包；`ImageViewerPage.localLoader` 与 `image_viewer_screen.dart` 的 `_ensureLocal` 惰性分支把它接进查看器本来就有的 ±N 预取窗口。实测 181 页 / 36.4 MB 的 CBZ：到首屏 **1.0 秒**（原来 48.9 秒）。
- **CBZ 首屏（惰性抽页）**：`_prepareCbzWithZip` 原来**无条件从第 0 页抽完整本**才返回，从第 150 页打开也要等 40 秒。现在先读 `progressFor` 定位起始页，只抽那一页，其余页挂 `ImagePageLoader` 闭包；`ImageViewerPage.localLoader` 与 `image_viewer_screen.dart` 的 `_ensureLocal` 惰性分支把它接进查看器本来就有的 ±N 预取窗口。实测 181 页 / 36.4 MB 的 CBZ：到首屏 **1.0 秒**（原来 48.9 秒）。
- **现场诊断脚本** `tool/dav_cbz_probe.dart`：`dart run tool/dav_cbz_probe.dart --url … --user … --pass … --path '…' [--all-pages]`，先打四种 Range 形态（`0-0` / `0-` / `-65536` / 中间段），再用 `CbzRangeZip` 开包，报告页数、`totalSize`、到首帧耗时与 ComicInfo。2026-10-13 对 123pan WebDAV 实测四种形态全 206：**慢的是阅读器，不是服务器**。
- **现场诊断脚本** `tool/dav_cbz_probe.dart`：`dart run tool/dav_cbz_probe.dart --url … --user … --pass … --path '…' [--all-pages]`，先打四种 Range 形态（`0-0` / `0-` / `-65536` / 中间段），再用 `CbzRangeZip` 开包，报告页数、`totalSize`、到首帧耗时与 ComicInfo。2026-10-13 对 123pan WebDAV 实测四种形态全 206：**慢的是阅读器，不是服务器**。


### 19.20 散图代理键与 schema v18（散图身份，2026-10-13）
### 19.20 散图代理键与 schema v18（散图身份，2026-10-13）


用户决定：「彻底抛弃漫画散页的目录绑定原则」「散图不需要保存什么源、路径、模式，唯一可信就是页列表」。方案代号**丙**——**书是用户资产，页列表是内容，目录只是一次性的输入来源**。
用户决定：「彻底抛弃漫画散页的目录绑定原则」「散图不需要保存什么源、路径、模式，唯一可信就是页列表」。方案代号**丙**——**书是用户资产，页列表是内容，目录只是一次性的输入来源**。


- **身份**：`lib/utils/manga_identity.dart` 新增 `newMangaId()`（uuid v4）与 `mangaSyncKeyForManga({id, format, sourceName, remotePath})`（散图取自身 id，容器回落到 `trackIdentityKey(源, 规范化路径)`），以及认出旧行的 `isLegacyLooseManga(...)`。容器书的身份**一个字都没变**（仍 `mangaIdForRemote`）——它「物化之后基本确定」，与音乐单曲同构，也省掉旧设备 / 旧分片的兼容问题。
- **身份**：`lib/utils/manga_identity.dart` 新增 `newMangaId()`（uuid v4）与 `mangaSyncKeyForManga({id, format, sourceName, remotePath})`（散图取自身 id，容器回落到 `trackIdentityKey(源, 规范化路径)`），以及认出旧行的 `isLegacyLooseManga(...)`。容器书的身份**一个字都没变**（仍 `mangaIdForRemote`）——它「物化之后基本确定」，与音乐单曲同构，也省掉旧设备 / 旧分片的兼容问题。
- **页路径**：散图的 `MangaPage.relPath` 由「相对书根」改成**相对网盘根**的完整路径，由 `MangaIngestDraft.draftForImageDir` / `draftForMergedImages` 通过 `_sourceRoot` / `_underSourceRoot` 生成。页表因此自带定位信息，`mangas.remote_path` 从身份降级为「上次是从哪个目录建的」这一条线索。`MangaReaderPrep._prepareImages` 本来就按「以 `/` 开头当绝对路径」解析，阅读器一行没改。
- **页路径**：散图的 `MangaPage.relPath` 由「相对书根」改成**相对网盘根**的完整路径，由 `MangaIngestDraft.draftForImageDir` / `draftForMergedImages` 通过 `_sourceRoot` / `_underSourceRoot` 生成。页表因此自带定位信息，`mangas.remote_path` 从身份降级为「上次是从哪个目录建的」这一条线索。`MangaReaderPrep._prepareImages` 本来就按「以 `/` 开头当绝对路径」解析，阅读器一行没改。
- **schema v18**（`_upgradeMangaV18`）：`mangas` 重建去掉表级 `UNIQUE(source_name, remote_path)`，改为**部分唯一索引** `idx_mangas_container_key ... WHERE format <> 'images'`（容器唯一性与 v17 完全等价，散图不再受限，同一目录的两本散图可以共存）；`deleted_mangas` 重建为 `manga_id` 主键 + `sync_key` 列，旧行按「此前墓碑都是容器的」逐条重键；升级时**直接丢弃 `format = 'images'` 的旧行**，并清掉随之孤立的 `manga_pages` / `manga_progress`。不写数据搬运、不兼容旧散图数据。
- **schema v18**（`_upgradeMangaV18`）：`mangas` 重建去掉表级 `UNIQUE(source_name, remote_path)`，改为**部分唯一索引** `idx_mangas_container_key ... WHERE format <> 'images'`（容器唯一性与 v17 完全等价，散图不再受限，同一目录的两本散图可以共存）；`deleted_mangas` 重建为 `manga_id` 主键 + `sync_key` 列，旧行按「此前墓碑都是容器的」逐条重键；升级时**直接丢弃 `format = 'images'` 的旧行**，并清掉随之孤立的 `manga_pages` / `manga_progress`。不写数据搬运、不兼容旧散图数据。
- **墓碑**：`WmpTomb.syncKey = 5`；`manga_sync_store` / `sync_service` / `library_sync_store` 三处合并键统一成 `row['sync_key'] ?? 回落 trackIdentityKey`。指向已删散图书的用户文件夹软引用**不清理**——`UserFolderService` 遇到不匹配的 id 只是取不到内容，不报错，留给用户手动删。
- **墓碑**：`WmpTomb.syncKey = 5`；`manga_sync_store` / `sync_service` / `library_sync_store` 三处合并键统一成 `row['sync_key'] ?? 回落 trackIdentityKey`。指向已删散图书的用户文件夹软引用**不清理**——`UserFolderService` 遇到不匹配的 id 只是取不到内容，不报错，留给用户手动删。
- **重新扫描此本（丙的核心）**：散图书的行尾「⋮」新增一项，走 `WebDavFolderPickerScreen(initialPath: manga.remotePath)` 选目录后入队一个带 `targetMangaId` 的 merged 建立任务；`_runMangaBuild` 见到目标 id 就改走 `MangaLibraryService.rescanLoose`——**就地替换页表**（bump rev）并更新 `remote_path` / `page_count` / `cover_relpath`，id、阅读进度与手工元数据全部保留。没有目标 id 时照旧新建（分配新 uuid）。
- **重新扫描此本（丙的核心）**：散图书的行尾「⋮」新增一项，走 `WebDavFolderPickerScreen(initialPath: manga.remotePath)` 选目录后入队一个带 `targetMangaId` 的 merged 建立任务；`_runMangaBuild` 见到目标 id 就改走 `MangaLibraryService.rescanLoose`——**就地替换页表**（bump rev）并更新 `remote_path` / `page_count` / `cover_relpath`，id、阅读进度与手工元数据全部保留。没有目标 id 时照旧新建（分配新 uuid）。
- **重复建立的现状**：容器入口（`_scanComicContainers` / `_ingestComicSelection`）仍无条件入队一次刮削；`_ingestComicFile` 先查库，命中直接打开（见 [19.16](#1916-网络库漫画单文件加入之后就是打开2026-10-13)）。散图的两个建立入口（合并 / 每目录）都从网络库出发，见 [19.15](#1915-扫描刮削与整包缓存改入任务队列2026-10-13)。
- **重复建立的现状**：容器入口（`_scanComicContainers` / `_ingestComicSelection`）仍无条件入队一次刮削；`_ingestComicFile` 先查库，命中直接打开（见 [19.16](#1916-网络库漫画单文件加入之后就是打开2026-10-13)）。散图的两个建立入口（合并 / 每目录）都从网络库出发，见 [19.15](#1915-扫描刮削与整包缓存改入任务队列2026-10-13)。
- **测试**：`test/manga_library_test.dart` 的 `_MemMangaDb` 去重规则改成「按 id 去重；`(源, 路径)` 只在两行都不是散图时去重」，与 v18 同形；补了「同一目录两次建立得到两本」「`rescanLoose` 保留元数据」的断言。
- **测试**：`test/manga_library_test.dart` 的 `_MemMangaDb` 去重规则改成「按 id 去重；`(源, 路径)` 只在两行都不是散图时去重」，与 v18 同形；补了「同一目录两次建立得到两本」「`rescanLoose` 保留元数据」的断言。


### 19.21 上传与散图物化（2026-10-13）
### 19.21 上传与散图物化（2026-10-13）


用户规范：「上传暂时只考虑 WebDAV（云盘不管）；用任务列表管理；物化 CBZ 拆成两个任务（先打包再上传）；网络库『新建文件夹』改成加号，展开为『新建文件夹』+『上传』；用安卓系统文件选择器（SAF）而不是申请全部文件权限」。
用户规范：「上传暂时只考虑 WebDAV（云盘不管）；用任务列表管理；物化 CBZ 拆成两个任务（先打包再上传）；网络库『新建文件夹』改成加号，展开为『新建文件夹』+『上传』；用安卓系统文件选择器（SAF）而不是申请全部文件权限」。


- **上传**：`TaskKind.upload`（storage `upload`）+ `enqueueUpload({sourceName, remotePath, displayName, localPath})`（`progressMode: bytes`）+ `_runUpload`。传输层是 `WebDavService.writeFromFile`（`lib/services/webdav_service.dart`）：从磁盘流式读、逐块报进度、吃 `CancelToken`，所以几百 MB 的包不会先进内存；`CloudDriveService.writeFromFile` 直接抛 `err.cloudWriteDisabled`——云盘没有上传原语。**成功后删本地副本，失败保留**，重试才有东西可发。
- **上传**：`TaskKind.upload`（storage `upload`）+ `enqueueUpload({sourceName, remotePath, displayName, localPath})`（`progressMode: bytes`）+ `_runUpload`。传输层是 `WebDavService.writeFromFile`（`lib/services/webdav_service.dart`）：从磁盘流式读、逐块报进度、吃 `CancelToken`，所以几百 MB 的包不会先进内存；`CloudDriveService.writeFromFile` 直接抛 `err.cloudWriteDisabled`——云盘没有上传原语。**成功后删本地副本，失败保留**，重试才有东西可发。
- **入口**：网络库右上角原来那个新建文件夹的 `IconButton` 换成 `PopupMenuButton`（`Icons.add`），两项——「新建文件夹」（`_canCreateFolder`）与「上传」（`_canUpload`：`providerType == 'webdav'` 且账号带 `AccountCaps.write`）。`_uploadFile()` 调 `PlatformExportService().pickFile()`；SAF 返回的 `PickedFile.path` 是**应用缓存里的副本**，天然就是「传完即删」的临时件。manifest 里没有 `MANAGE_EXTERNAL_STORAGE`，走 SAF 是唯一不申请全盘权限的路。
- **入口**：网络库右上角原来那个新建文件夹的 `IconButton` 换成 `PopupMenuButton`（`Icons.add`），两项——「新建文件夹」（`_canCreateFolder`）与「上传」（`_canUpload`：`providerType == 'webdav'` 且账号带 `AccountCaps.write`）。`_uploadFile()` 调 `PlatformExportService().pickFile()`；SAF 返回的 `PickedFile.path` 是**应用缓存里的副本**，天然就是「传完即删」的临时件。manifest 里没有 `MANAGE_EXTERNAL_STORAGE`，走 SAF 是唯一不申请全盘权限的路。
- **散图物化（打包）**：`TaskKind.mangaPack`（storage `manga_pack`）+ `enqueueMangaPack({sourceName, mangaId, remotePath, displayName})` + `_runMangaPack`。**刻意拆成两条任务**：打包与上传各占行、各有各的进度。打包把页逐张下到同一个临时文件、再用 `ZipFileEncoder.addFile` 流进归档（峰值磁盘一页、峰值内存一个缓冲），条目名带 5 位序号前缀 `00001_原名`，同时保证页序与「两个源目录里有同名文件」时的唯一性；成功后自动 `enqueueUpload`，归档本身由上传任务负责删。
- **散图物化（打包）**：`TaskKind.mangaPack`（storage `manga_pack`）+ `enqueueMangaPack({sourceName, mangaId, remotePath, displayName})` + `_runMangaPack`。**刻意拆成两条任务**：打包与上传各占行、各有各的进度。打包把页逐张下到同一个临时文件、再用 `ZipFileEncoder.addFile` 流进归档（峰值磁盘一页、峰值内存一个缓冲），条目名带 5 位序号前缀 `00001_原名`，同时保证页序与「两个源目录里有同名文件」时的唯一性；成功后自动 `enqueueUpload`，归档本身由上传任务负责删。
- **入口**：散图书的行尾「⋮」新增「物化为 CBZ」——先 `WebDavFolderPickerScreen(initialPath: manga.remotePath)` 选目标目录，再填文件名（默认取书名，`\ / : * ? " < > |` 替换成 `_`）。**这里刻意不用 `TextEditingController`**：对话框 pop 之后路由还在播退场动画，随手 `dispose()` 会在 `_dependents.isEmpty` 上炸（与批量改系列名那次同一个坑），所以改用 `TextFormField(initialValue:)` + 局部变量。
- **入口**：散图书的行尾「⋮」新增「物化为 CBZ」——先 `WebDavFolderPickerScreen(initialPath: manga.remotePath)` 选目标目录，再填文件名（默认取书名，`\ / : * ? " < > |` 替换成 `_`）。**这里刻意不用 `TextEditingController`**：对话框 pop 之后路由还在播退场动画，随手 `dispose()` 会在 `_dependents.isEmpty` 上炸（与批量改系列名那次同一个坑），所以改用 `TextFormField(initialValue:)` + 局部变量。
- **文件夹上传优化备选方案 B（待评估）**：现有 `_uploadFolder` 调 `pickFolder()` 会在原生线程把整个目录**全量复制**到缓存后才回调，大文件夹用户零响应。方案 B 是「枚举先行、物化惰性」：
  - 原生新增 `listFolderTree`（只枚举 SAF URI + relativePath + size，不复制字节）和 `readUriToCache`（单文件按需复制到临时目录）两个 channel 方法，请求码 `REQUEST_LIST_FOLDER_TREE = 4713`。
  - Dart 侧 `PlatformExportService` 暴露 `listFolderTree() -> PickedFolderTree` 和 `readUriToCache(uri) -> String?`；`QueueTask` 新增 `localUri` 字段（SAF URI），`enqueueUpload` 同步加 `localUri` 可选参数。
  - `_runUpload` 检测到 `localUri` 时，在 worker 里调 `readUriToCache` 拿缓存路径再上传，成功后删临时文件；重试时缓存路径已写回 `task.localPath` 无需再次枚举。
  - 好处：picker 界面即时消失，进度在任务列表可见；暂推迟，等文件夹上传量级达到实际瓶颈时再上。
- **文件夹上传优化备选方案 B（待评估）**：现有 `_uploadFolder` 调 `pickFolder()` 会在原生线程把整个目录**全量复制**到缓存后才回调，大文件夹用户零响应。方案 B 是「枚举先行、物化惰性」：
  - 原生新增 `listFolderTree`（只枚举 SAF URI + relativePath + size，不复制字节）和 `readUriToCache`（单文件按需复制到临时目录）两个 channel 方法，请求码 `REQUEST_LIST_FOLDER_TREE = 4713`。
  - Dart 侧 `PlatformExportService` 暴露 `listFolderTree() -> PickedFolderTree` 和 `readUriToCache(uri) -> String?`；`QueueTask` 新增 `localUri` 字段（SAF URI），`enqueueUpload` 同步加 `localUri` 可选参数。
  - `_runUpload` 检测到 `localUri` 时，在 worker 里调 `readUriToCache` 拿缓存路径再上传，成功后删临时文件；重试时缓存路径已写回 `task.localPath` 无需再次枚举。
  - 好处：picker 界面即时消失，进度在任务列表可见；暂推迟，等文件夹上传量级达到实际瓶颈时再上。
## 20. SAF 自定义下载目录（本分支实现）

**状态**：已实现并待验收。

**用户原话**：允许用户选择自定义的 SAF 树目录作为下载目标，替代 MediaStore 的系统下载目录。

**决定与取舍**：

- **只读树授权泄漏修复**：漫画库 `listFolderTree` 得到的子文档 URI 存进上传任务 `localUri`，任务运行时（可能重启后）才用 `readUriToCache` 读——所以**不能**列举完立刻释放。方案：`_releaseUnusedReadTreeGrants()` 取只读（write=false）的树授权；排除 `settings.customDownloadTreeUri`；对每个 grant，若队列中**不存在**任何 status != completed 的任务其 localUri 属于该树，则 releaseReadTree。调用时机：队列 init 完成后一次；任何 localUri 非空的任务进入 completed 或被 remove / clearAll / clearCompleted 之后。
- **错误分类**：SAF 写入失败分三类：`safInvalid`（权限丢失、根文档不可用、FLAG_DIR_SUPPORTS_CREATE 缺失）→ 全局回落到系统下载目录；`io`（ENOSPC 等 IOException）→ 不回落；`other`（其它异常）→ 不回落。**只有 safInvalid 会导致上层全局回落**。
- **重复任务对话框**：单文件下载时，先查 `blockingPublicDuplicate`；有 → 对话框「已有重复任务，是否重新进行？」确认 → `requeuePublicFresh`（删旧行、删 .part、新建任务）。批量下载时，`enqueueSelection` 先扫描收集重复项；若 duplicates>0，对话框「有 N 个重复任务，是否全部重新进行？」确认 → `requeuePublicFreshMany`。
- **.nomedia 双向对齐**：启动、下载设置页打开、切换目标（pick / disable / fallback）、备份导入后、每次 downloads 提交前（SAF 模式 best-effort）都调 `alignNomedia`。开关切换时用 `alignNomedia(reportAlready:true)`，若已匹配则提示，失败才拨回开关。替代 99 §8/§9 里「冷启动只补不删」的旧语义。

**相关文档**：

- [04-DOWNLOAD-QUEUE.md](04-DOWNLOAD-QUEUE.md)：提交时决定目标、SAF 写入、错误分类与回落、.nomedia 双向对齐、重复任务对话框
- [08-SYNC-AND-BACKUP.md](08-SYNC-AND-BACKUP.md)：备份新增键与不备份键（含 custom_download_* 不备份）

**UI**：

- 设置 → 下载队列：自定义下载目录开关、当前目录名、重新选择按钮、Android 11 说明
- 任务队列：downloads 完成标签用「已下载」；进行中用「目标：下载目录」（不提「系统」）
- 网络库：单文件与批量下载的重复任务对话框

**实现细节**见本分支规格 `/workspace/saf_work/spec.md`。
