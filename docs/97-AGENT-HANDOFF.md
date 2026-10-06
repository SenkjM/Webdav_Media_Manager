# 97 · 跨 Agent 交接与临时对话

本文件不参与功能块编号，也不写长期方向。它是**人与多个 agent 之间的传话板**：交接单讲清「谁在做、做到哪、边界在哪、下一步」，临时对话讲清「谁问、问什么、谁答了什么」。

**长期的方向与计划、以及其中已经落地的部分，写在 [99](99-IN-PROGRESS.md)**；本文件只收**临时的**东西——工作交接、具体改动细节（GUI 改动清单就属于这类）、跨 agent 问答。一律**指向 99 或对应完整文档，不复制它们的结论**。

## 1. 什么时候用这里

- **工作交接**（§3）：一个 agent 把没做完的活交出去时。带分支、worktree、当前进度、卡点、下一步、验收命令。
- **临时对话**（§4）：跨 agent 的提问、确认、纠偏。**结论一旦定型就回流到 99 或对应完整文档，然后删掉这里的条目。**

## 2. 规则

- 条目是**临时的**：交接被接手、对话收敛之后**删除该条**；本文件不留历史。
- 不写验收清单、不写过程日志；`flutter analyze` / `flutter test` 只写一句结论。
- 不写密钥、token、账号明文。
- 每条必须带：日期、发言人、任务、分支 / worktree、状态、下一步。
- 与源码冲突时以源码与测试为准，然后回来改文档。

## 3. 交接条目


### H-002 · libsodium secretbox 实验（feat/libsodium-secretbox）

- **日期**：2026-10-06
- **发言人**：executor agent
- **状态**：设置 UI 已接上；待真机验 FFI 加载与开关
- **需求语义**：[99 §4.5](99-IN-PROGRESS.md) crypt 待办（FFI + 加密设置）
- **分支 / worktree**：`feat/libsodium-secretbox` @ `worktree/libsodium-secretbox`。**不要推 main，不要跑 workflow。**
- **已做**：可选 libsodium secretbox；设置 → 加密设置子页（顺序流 + prefer libsodium prefs / 启动 apply；库加载不了时禁用）。`openlist_crypt` 已换成独立包 [SenkjM/openlist_crypt](https://github.com/SenkjM/openlist_crypt)（git 依赖，固定提交），libsodium 1.0.20 由其 native assets hook 按 ABI 打包（Android 四个 ABI、16 KB 对齐），分支 `feat/openlist-crypt-standalone` @ `worktree/openlist-crypt-standalone`（基于本分支）。
- **下一步**：一加 / sandbox 真机确认 `libsodium.so` 加载、开关切换与解密吞吐。


### H-001 · MD3 界面改造（预览非播放器页 + 明暗切换 + 种子色）

- **日期**：2026-10-02
- **发言人**：本地 agent → 下一位执行者
- **状态**：**未开工**
- **需求语义**：[99 §2](99-IN-PROGRESS.md)（§2.1 现状、§2.2 为什么不能只打开 themeMode、§2.3 两阶段拆分、§2.4 验收与回归点）
- **分支 / worktree**：从 `main` 开功能分支，worktree 放 `worktree/<name>`。**不要推 `main`，不要跑 workflow。**

**用户原话**：用本地 agent 做基于 MD3 的界面改造；预览用 Flutter 自带的 Widget Previewer；加上实时取色和 light/dark 切换。点名弱化「目录、文件大小、歌单内歌曲数量」这一类次要信息，并精简文案。

**先读**：99 §2，以及通用 skill「Material Design 3」。网上现成参考，不要抄进仓库：

- 规范：[Material Design 3](https://m3.material.io/)
- [hamen/material-3-skill](https://github.com/hamen/material-3-skill)（最完整，Compose 为主，Flutter 为辅）
- [pouani/material-3-skill](https://github.com/pouani/material-3-skill)
- 预览器：[Flutter Widget Previewer](https://docs.flutter.dev/tools/widget-previewer)（3.47 起稳定；本仓库文档里记过的 Flutter 是 3.47.5）
- 只在要做 Expressive 时才看 [material3-expressive-flutter](https://github.com/Mic-360/material3-expressive-flutter)。本轮不要。

**已拍板，覆盖上面「边界未定」**：

- Material 3 已经开着（`AppTheme` 里 `useMaterial3: true`）。不要再加 UI 库，不要把 `useMaterial3` 当开关。
- 种子色用 `ColorScheme.fromSeed`。默认种子保持现在的青绿 `0xFF2EC4B6`。只让这个种子变，不开放整套色板。`onAccent` 由 scheme 算出来。
- 三态：light / dark / 跟随系统，存 `SettingsService`，`main.dart` 的 `themeMode` 读它。现在写死的是 `ThemeMode.light`。
- 圆角和 `VisualDensity.compact` 保持。亮色默认观感不要换成另一套产品。
- 分支：从 `main` 开功能分支，worktree 放在 `worktree/<name>`。不要推 `main`，不要跑 workflow。改完 `flutter analyze` 和相关 `flutter test`。

**预览只走 Widget Previewer，不要在应用里加预览路由。**

- 启用方式：IDE 侧边栏 Flutter Widget Preview，或在仓库根目录 `flutter widget-preview start`。它另开一套网页，不跑 `main()`，不打进 APK，也不走 `--flavor`。
- 会在仓库根目录写出 `.widget_preview/` 缓存。加进忽略，不要提交。
- 只有标了 `@Preview` 的公开顶层函数、静态方法，或没有必填参数的公开构造函数会出现。导入 `package:flutter/widget_previews.dart`。
- 每个预览自带明暗切换。种子色的实时取色不是预览器的功能，做在被预览的控件里，用 `theme` 套 `AppTheme`。
- 预览器是 Flutter Web。`dart:io`、`dart:ffi`、`media_kit` 一调用就抛。能覆盖的是不碰这些依赖的小组件：封面、列表行、开关、按钮，以及下面点名的次要信息行。抽成小组件再标 `@Preview`。
- 播放器整页不进预览：`PlayerScreen`、`MusicStreamScreen`、`video_player_screen.dart`。它们要 `media_kit`，不是一份列表。其余要看主题的页面都进预览：曲库、歌单、歌单详情、网盘库、下载、同步、账号、设置各页、文件夹选择、字幕选择、正在播放队列、图片查看里不依赖播放器的列表部分。
- 做法：这些页面改成能用「这一帧的数据 + 动作接口」构建。预览里传预制的空数据（几行假标题、空列表），动作是空实现。真实服务仍只在 `flutter run` 里接上。

**空数据不会进正式包，前提是应用的入口碰不到它。** 预览函数和假数据放在单独文件里，`main.dart` 和正式页面不要 import 它们。Release 从 `main` 做树摇，没被引用的代码不会进 APK。再用 `kDebugMode` 包住更稳：release 里它是常量 `false`，那段会被编译器删掉。如果正式页面 import 了假数据文件，它就会进包。预览器自己的 `.widget_preview/` 只是本地缓存，本来就不进包。

**次要信息：压低，并缩短文案。** 用 `onSurfaceVariant`（现在的 `secondaryText` / `mutedText` 这一档），字阶用 `bodySmall` 或 `labelMedium`，不要再手写 11、12。布局已经说明的名词删掉。状态词留下（未下载、下载中、来源未绑定、错误），它们不是这类装饰信息。

点名这些位置：

- `lib/screens/network_library_screen.dart` 目录行副标题，约 1302 行：`l10n.directory`（中文「目录」）。文件夹行已经是文件夹，这行删掉或改成真正有用的一句，不要留「目录」两个字。
- 同文件文件行的大小：CUE 约 1315、视频约 1342、图片约 1375、其他文件约 1392、音频约 1426，都走 `_fmtSize`（1676）。大小留下，但跟类别词拆开：能拿到大小就只显示大小，不要再写「视频 / 图片 / 文件 / 音频」。没有大小时才留类别。`_fmtSize` 只有 B/KB/MB。
- `lib/screens/playlists_screen.dart` 列表副标题，约 192 行：`l10n.playlistTrackCount`（「{count} 首」）。歌单行上这就是数量，留数字，去掉能省的量词以外的说明；不要再加别的句子。
- `lib/screens/library_screen.dart`：`_ArtistTab` / `_AlbumTab` 传给 `_CoverTile` 的 `playlistTrackCount`；`_CoverTile` 副标题约 740 行；`_TagsTab` 的 `ListTile.subtitle` 约 298 行。同样只留数量，专辑那行已有的「数量 · 艺人」里艺人可以留，数量按上面缩短。
- `lib/screens/downloads_screen.dart` `_CueGroupTile` 约 318 行：`l10n.songCount`（「{count} 首歌」）和没有曲目时的 `l10n.cueAlbum`。数量按歌单那条缩短；「CUE 专辑」这种类别词改短或去掉。

同一类、本轮一起改，但不要扩到播放器：

- `lib/screens/playlist_detail_screen.dart` 缺歌行约 94 行的「库中暂无 · 名称」可以缩短，曲目行上的艺人 / 专辑留着。
- `lib/screens/network_library_screen.dart` CUE 弹层约 676 行的 `netCueGroupTitle` / `netCueGroupTitleMulti` 太长（「多歌曲合并分片 · CUE · N 曲 · M 个音频文件」），收成数量。
- `lib/screens/webdav_folder_picker_screen.dart` 约 200 行整段 `_path`，和 `lib/screens/subtitle_remote_picker_screen.dart` 约 109 行的当前目录：路径是次要信息，压低，能显示末级就不要整段。

**本轮不要改：**

- `MusicStreamScreen`、`PlayerScreen` 的布局、滑条绘制、详情里的远程路径和文件大小。流式页的重排仍以 99 §1.1 为准，不并进这次。
- `video_player_screen.dart` 的手势区和黑白叠层，包括进度时间、队列里的大小和 `扫描中…`。
- `image_viewer_screen.dart` 上的白色页码。
- `lib/utils/cover_image.dart`、`CacheService`、下载队列服务。下载行上的百分比和状态色留下。
- 视频、图片叠在画面上的纯白纯黑，那是对比色，不跟种子色走。

**做完应看到：** 预览器里能切换明暗、拖种子色。除播放器外的页面用空数据画出来，点名的那几行变淡、变短。正式安装包里没有这些空数据。默认种子仍是现在的青绿。

## 4. 临时对话

格式：`Q-xxx`（提问）/ 对应 `A-xxx`（回答）。收敛后删除。

_（暂无）_
