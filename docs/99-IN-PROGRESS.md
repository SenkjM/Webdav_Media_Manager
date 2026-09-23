# 99 · 开发中文档

只记录**正在开发**的功能的原始语义：需求原话、取舍、临时决定、还没定型的实现。
用法与收口规则见 [00-INDEX.md](00-INDEX.md) 的「完整文档与开发中文档」。

- 开发新功能前**先读本文件**，再读每一条链接到的完整文档。
- 开发期间，完整文档里对应的位置只留占位，不写半成品语义。
- 开发完成后：删掉这里的条目，把语义按完整文档的写法补进对应功能块，并去掉占位。

## 1. 安装包分包与压缩存放（进行中）

**状态**：代码已改并推 `main`，还没跑过一次真实构建，**未验证**。

**为什么**：v0.1.0 的通用 APK 有 101.3 MiB，其中 99.7 MiB 是三个 ABI 各带一份原生库——`libmpv.so` 38.1 MiB、`libflutter.so` 31.8 MiB、`libapp.so` 28.4 MiB——非原生部分只有 2.7 MiB。

**要什么行为**：

- `--split-per-abi` 出三个单 ABI 包：`arm64-v8a`、`armeabi-v7a`、`x86_64`。
- 额外再出一个**去掉 x86_64** 的合并包（`android-arm,android-arm64`），给不确定自己 ABI 的人。
- 原生库**压缩存放**（`useLegacyPackaging = true`）：下载更小，代价是安装时要解压。
- `.aab` 照旧产出，给 Play 用。

**取舍**：压缩存放会让安装占用变大、安装变慢。若日后确认 Play 分发不需要它，再单独评估是否只对 APK 生效。

**影响面**：[09-MISC.md](09-MISC.md) 的「构建与发布」——那里现在只留占位。

## 2. flavor 与本地 dev 环境（进行中）

**状态**：代码已改。`flutter run --flavor dev` 已在本机 + 真机（PJZ110 / Android 16）上跑通：装成 `com.senkjm.media_manager.dev`，`versionName=1.0.0-dev`，能与正式包并存。**CI 里那几处产物路径改动没在真实 CI 上跑过，未验证。**

**需求原话**：配置 flavor，设置一个本地测试的 dev 环境，使用不同的包名，包名在后面加上 `.dev`。

**要什么行为**：

- `env` 一个维度，两个 flavor：`prod`（applicationId 不变）与 `dev`（`applicationIdSuffix = ".dev"`）。
- 两个包能并存在同一台手机上，各自持有独立数据目录。
- 桌面 / 最近任务里能区分：`android:label` 改用 `manifestPlaceholders["appName"]`，dev 叫 `Webdav Media Manager Dev`。
- 本地 release 与 CI 都改成显式 `--flavor prod`。

**取舍**：

- **不动 `namespace`**：`MainActivity.kt` 的包路径，以及 `com.senkjm.media_manager/app`、通知 channel id 这类字符串都是应用内部标识，与 applicationId 无关，改了只是白白搬家。
- 代价：存在 flavor 之后，不带 flavor 的 `flutter build apk --release` 失效。
- CI 的产物名字随 flavor 变成 `app-prod-*.apk` / `bundle/prodRelease/app-prod-release.aab`，两份 workflow 的收集步骤已同步改。

**影响面**：[09-MISC.md](09-MISC.md) 的「构建与发布」——本地命令与 flavor 表已写进那一节；待 CI 跑过一次后收口。

## 3. 音乐库的两个不可逆动作（进行中）

**状态**：代码已改，`flutter analyze` 与 `flutter test`（202 项）通过。**真机未跑过**——按钮按压、确认框排版与实际效果都没验证。

**需求原话**：在备份与恢复的音乐库下面，分成纵向两个红底白字按钮。上面是「从云端覆盖音乐库」，点击后提醒会从云端下载数据库并覆盖本地，逻辑就可以清空本地表并从云端下载重建。另一个是「销毁音乐库」，销毁后将定时同步设为关闭（在此操作中不可更新数据库，如果发现有其他行为干扰就关掉）；点击后提醒会销毁全部本地音乐库，小一号字提醒：同步会将删除记录上传云端，再次重建这次不可恢复，此操作后会关闭自动同步。

**需求修订（同日，两次）**：

1. 按钮改名「从云端**覆写**音乐库」；两个动作都要手打 `YES`（不区分大小写）才放行。
2. **销毁先改成「只立墓碑」，随后又改回「逐条删除」**。只立墓碑那版在本地毫无可见变化（墓碑不影响本地列表，见下），用户确认要的是逐条删除的语义。
3. 补上歌单悬空引用清理与下载队列对账；销毁过程要有进度条、可终止、返回即取消；销毁本身重构成「每次只销毁一首歌」的固定函数，多选销毁共用同一套。

**要什么行为**：

- 两个按钮整行宽、上下排列，放在「音乐库」区块内、重建提示阈值那行下面。
- 覆盖：清索引 → 从云端整库拉一次；已下载的音频与封面保留。
- 销毁：一首一首地走，每首的顺序是墓碑 → 缓存音频 → 封面 → 库行 → 内存，走完这一首才轮到下一首；整库收尾再清歌单悬空引用、对账下载队列、把定时同步置为 `off`。
- 进度框：进度条 + 「已处理 N / 总数」+「终止」；终止、点框外、返回键都算取消。
- 多选销毁与整库销毁共用同一个逐首函数（`AppState.destroyLibraryTrack`），差别只有「销毁哪些」。
- 两个动作期间不允许后台写库。
- 两者互为反面：覆写把云端拉到本地，销毁把本地的删除推到云端。

**取舍**：

- 覆写只清**索引**（新增 `LibraryDatabase.clearLibraryIndex()`），不清 cache annex：连 annex 一起清的话，磁盘上已存在的音频会被当成没下过，白白多出一次全量下载。
- 销毁走逐条、不走 `clearAllLibraryData()` 整表清空：整表清空会把 `deleted_tracks`（墓碑）和 `sync_state`（游标）一起抹掉，云端永远收不到删除记录，下一次同步还会把整库拉回来；逐条则是「先墓碑、后删行」，顺序由 `LibraryService.destroyTracks` 保证。代价是 N 次数据库写入，比一条 `DELETE FROM` 慢得多。
- 为什么必须是逐条而不是只立墓碑：**本地列表只认行**。让曲目消失的是「删行 + `_tracks.removeWhere` + `notifyListeners()`」，墓碑只对同步的拉取判定有意义（`LibraryDatabase.tombstonedKeys()` 注释写着 for the library UI + ingest，但全仓没有调用方），只立墓碑的话本地曲库不会有任何变化。
- 逐条会删掉本地已下载的音频，这是不可逆的：云端那行同时被墓碑标记，重建云端库之后两边都没有了。
- 「原子」说的是**逻辑边界**，不是数据库事务：`LibraryService.destroyTrack` 内部没有 `db.transaction()`，一首歌要跨 `deleted_tracks` / 封面文件 / `tracks` / 内存四处写。取消只能在两首之间生效；进程若在中间被杀，留下的是「墓碑写了、行还在」——顺序（墓碑在前）保证这个中间态是安全的，重跑一次即可收尾。
- 进度条按「已处理 / 总数」推进，不是「已销毁 / 总数」：CUE 分片会被同一张专辑的第一片带走，后面的兄弟曲目直接跳过（`destroyLibraryTrack` 返回 false），所以进度会走满而销毁数可能小于总数。
- 进度框是模态的，销毁不会在界面消失之后继续在后台跑——这正是「删除界面不要做成异步的」：返回键把取消标志置起来，当前这一首走完就停。
- 每首都会 `notifyListeners()` 一次，进度框后面的界面会被重建 N 次；换来的是「一首歌就是一个完整动作」，以及取消点永远落在歌与歌之间。
- `LibraryService.destroyTracks(Iterable)` 保留为「没有进度界面时的循环封装」，目前没有调用方。
- 关掉定时同步是刻意的：推不推、什么时候推，交回用户手动决定。
- 「其他行为干扰」的实现是静默窗口（`_quietLibraryWrites`）：暂停 20 s 推送防抖与定时扫描，并取消已排队的防抖。没有做成互斥锁——已经在飞的同步不会被中断，只是不再有新的自动触发。

**影响面**：[08-SYNC-AND-BACKUP.md](08-SYNC-AND-BACKUP.md) 的「同步页的交互约定」已写入这两个动作；真机验证后再收口。

## 2. 统一网络库交互模型（**代码已完成，未在真机验收**）

**状态**：分支 `feature/network-action-model`，`flutter analyze` 干净、`flutter test` 全量通过；**没有跑过真机**。已完成的语义写进 [02-NETWORK-LIBRARY.md](02-NETWORK-LIBRARY.md)，本文件只留未定型的部分。

**原始诉求**（用户原话，节选）：

- 「多选时使用全选再次取消会退出多选，多选界面的叉号不该一开始就出现，应该是在检测到全选后，全选按键变为叉号，此处除了全选按钮还应该需要检测用户是否手动全选，可以使用计数器对比实现。」
- 「在网络库中支持对文件进行复制、移动。」
- 「建立统一的『文件动作模型』……音乐文件默认缓存，cue 文件调用 cue 读取，视频文件调用流式传输，普通文件调用下载。这里的下载指下载到下载文件夹而非缓存。」
- 「多选工具栏 / 单文件右侧更多菜单与 T1 对齐。」

**做法与取舍**：

- 全选判定用**计数器对比**（`SelectionController.isAllSelected`），不看按钮按过没有。理由是手动一项项点满也必须让按钮变成叉号，否则会出现「明明全选了按钮还是全选，一点就把选择清空」。
- 那个按钮只在全选时才是叉号，且**只取消全选、不退出多选**；退出交给返回键（用户明确说「选择一项就退出时可以直接使用返回键」），所以没有另设关闭按钮。
- 三个入口共用 `judgeAction` / `_runAction`。动作与类型不匹配时直接说明原因，**不静默替换成别的动作**——那会让设置看起来没生效。
- 「下载」= `DownloadTarget.downloads`（系统下载目录），与「缓存音乐」严格分开；多选下载逐项按类型分发。
- 复制 / 移动走 WebDAV 原生 `COPY` / `MOVE`；同名冲突**自动加 ` (n)`**，不用 `Overwrite: T`（不可逆）。

**已知未做**：

- 移动 / 重命名远端文件后，本机音乐库里绑定旧路径的曲目不会跟随（需要一次「路径重写」才能做对）。
- 复制 / 移动没有进度与取消：`webdav_client` 的 `copy` / `rename` 是单次请求，大文件只能等。
- 真机验收未做。已知风险：部分服务端对目录目标的 `Destination`（加不加结尾 `/`）处理不一致，需要在真实网盘上各试一次。

## 3. 音乐流式传输（**代码已接入，未真机验收**）

**状态**：分支 `feature/music-streaming`。实验开关打开后，网络库对音乐条目（整行点按 / 更多菜单 / 多选单曲）会直接流式播放，`flutter analyze` 干净。**没有跑过真机，没有任何自动化测试覆盖播放栈**。按用户要求目标只是「能播就行」，封面等需要大改的内容先不做。

**已实现**：

- `WebDavStreamSource.kind`（`StreamKind.video` / `.music`）：远端流管线只有一条，用途标记只影响媒体会话文案与队列语义。
- `WebDavStreamSource` 构造默认按后缀推断用途，`WebDavService.buildStreamSource` 可以显式覆盖。
- `enterVideoMode` 在音乐用途下把通知写成「流式播放 / WebDAV 流媒体」，不再写成「视频」。
- `AudioPlayerService.playRemoteMusic({source, artist})`：建媒体会话 → 打开远端源 → 播放；`stopRemoteMusic()` 退出。
- 网络库 `_streamMusic` 走上面这条路径，失败时把 `AudioPlayerService.error` 显示出来（远端 401 / 断网不再静默）。

### 3.1 现状里有什么

- `MusicAudioHandler`（`lib/services/music_audio_handler.dart`）已经持有**两个** `media_kit` `Player`：`_player` 播本地音频，`_videoPlayer` 播远端流，靠 `_mode`（`AudioHandlerMode.music` / `.video`）切换。
- 远端播放要用的东西视频侧已经齐了：`WebDavService.buildStreamSource()` 出直链 + Basic 认证头，`VideoPlaybackService.mediaFor()` 转 `Media`，`MusicAudioHandler.enterVideoMode()` 建媒体会话 / 通知 / 队列。
- 后台播放、锁屏控制、耳机按键都工作在这套 handler 上（视频侧已经在用）。

### 3.2 怎么复用，怎么区别

音视频在媒体会话上的**差别只有三处**：

| 项 | 视频现状 | 音乐流式需要 |
|----|----------|--------------|
| 队列 | `queue.add(const [])`，隐藏上一首 / 下一首 | 可以同样为空；要切歌得先列目录建远端队列 |
| 通知文案 | `album: '视频'`、`artist: 'WebDAV 流媒体'` | 换成音乐语义（专辑 / 艺人留空或从文件名猜） |
| 画面 | 开 `VideoPlayerScreen`（libmpv 输出） | 不开播放页；要封面就只显示在通知与迷你条上 |

结论：**不需要另起播放栈**，把 `enterVideoMode` 泛化成「远端流模式」，用一个用途标记区分视频 / 音乐即可。

### 3.3 必须先解决的一个坑

`enterVideoMode` 会把 `_mode` 置成 `video`，而 `exitVideoMode()` 的语义是「**恢复**音乐队列并暂停」。音乐流式若共用这个模式，「流式播完 → 切回本地音乐」时 handler 会把本地队列状态重新广播一遍，通知栏会闪回上一首本地歌。

需要在 `_mode` 之外单独记一个「远端流用途」标记，让 `exitVideoMode` 只对视频做恢复，音乐流式走「清空会话」的分支。**这一条不解决，实验功能会污染本地播放状态。**

### 3.4 封面与时长（用户已允许先不做）

- 为什么难：流式播放拿不到本地文件，`audio_metadata_reader` 无从解析。要拿封面与时长，至少得用 Range 把文件**头部几 MB** 读回来（`Options(headers: {'Range': 'bytes=0-…'})`）再喂给现有标签 / 封面解码；FLAC 的 `STREAMINFO`、MP4 的 `moov` 还可能落在文件尾部，需要读两次。
- 折中（第一版建议）：通知与列表用同目录同名的本地封面（`cover.jpg`）或占位图标；时长由 `media_kit` 解析出来后回填 `MediaItem.duration`（视频侧已经这么做）。

### 3.5 操作优化与其它代价

- **看不出区别**：用户分不清「这首是流式还是已缓存」。建议行上加「流」角标，或在通知专辑名写「流式传输」。
- **流量**：整张专辑连播是几十到几百 MB。建议默认**不连播**。
- **切歌语义**：本地播放有 CUE 裁切 / 队列语义，流式没有；从流式切到本地必须以「停止 + 清会话」结束，而不是暂停。
- **失败表现**：远端 401 / 断网时错误落在 `player.stream.error`，要像视频侧那样提示，不要静默。
- **与缓存的关系**：流式**不得**顺手入队下载（[09](09-MISC.md) 的陷阱表：不要在播放路径上偷偷入队下载）。

### 3.6 建议的落地顺序（独立分支）

1. `MusicAudioHandler`：远端流模式加用途标记，`exitVideoMode` 只对视频恢复队列。
2. `AudioPlayerService` 增加 `playRemoteTrack(...)`：建 `WebDavStreamSource` → 进远端流模式 → 通知用音乐文案（不带封面）。
3. ~~网络库 `_streamMusic()` 调用它~~（已完成）。
4. **真机验收（未做）**：后台切换、锁屏控制、耳机按键、断网、切回本地播放。

**已知的粗糙处（第一版接受）**：

- `exitVideoMode()` 的语义仍是「恢复本地音乐队列」。流式音乐停下时会把之前暂停的本地歌重新广播到通知栏，看起来像「跳回了另一首歌」。要更干净，得让远端流用途参与 `exitVideoMode` 的分支判断。
- 多选工具栏的「播放」按钮仍然只对单个视频可用；音频走整行点按 / 更多菜单。

**影响面**：[02-NETWORK-LIBRARY.md](02-NETWORK-LIBRARY.md)（§2、§8）、[05-AUDIO-PLAYBACK.md](05-AUDIO-PLAYBACK.md)（「仅本地播放」的约定要改）、[06-VIDEO-PLAYBACK.md](06-VIDEO-PLAYBACK.md)（共享的远端流模式）、[07-NOTIFICATIONS.md](07-NOTIFICATIONS.md)（媒体通知文案）、[09-MISC.md](09-MISC.md)（陷阱表里的「不要给音频做流式播放」要改写成「实验开关控制的流式播放」）。

