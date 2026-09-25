# 03 · 音乐库

> 编号 03 · 总索引：[00-INDEX.md](00-INDEX.md)  
> 代码：`lib/screens/library_screen.dart`、`lib/services/library_service.dart`、`lib/services/library_actions.dart`

音乐库是**本地曲库**：标签、封面路径、CUE 虚拟分片都在本地数据库里，与音频文件是否还在磁盘上**解耦**。数据模型见 [01](01-DATA-MODEL.md)。

## 1. 库里有什么

- 普通曲目行（`tracks`）与 CUE 虚拟分片行（`cue_slices`）；一行对应一条 `music_id`。
- 曲目身份 = **网盘名 + remote_path**，行内不含地址 / 用户名 / 密码。
- 来源网盘改名后，属于它的行显示「**来源网盘未绑定**」，点它不会下载或播放，而是提示先添加 / 改回同名网盘；改回原名即恢复。

## 2. 缓存状态、标签与页签

页签分 **标题**（全部曲目的平铺列表）、**流派**（用户可见的页签名，代码与库内字段仍叫 genre / 标签；按 `groupedByGenre()` 分组，缺流派信息的归「未分类」）、**播放列表**（数据模型见 [01](01-DATA-MODEL.md)，双向同步见 [08](08-SYNC-AND-BACKUP.md)）。点流派的组进子界面看该组曲目，长按进子界面时**直接带着整组多选**。

- 「是否已缓存」只有一个判定：cache annex 有行 **且** 文件存在（见 [01 §3](01-DATA-MODEL.md)）。
- 标签复用 `TrackUiState` 那一套（`lib/widgets/track_status_chip.dart`）：下载中显示百分比、就绪是绿色、未缓存不显示标签。
- 清空音频缓存后，曾经下载过的行应回到「未下载」；**不应该**出现「错误」标签（队列里的 stale 任务行会被删除，见 [04 §4](04-DOWNLOAD-QUEUE.md)）。
- 性能约定：列表不要 `context.watch<AudioPlayerService>`（会按帧重建），用 `read` + 局部订阅。

## 3. 删除 / 销毁

| 操作 | 多选工具条显示 | 效果 |
|------|----------------|------|
| 删除缓存 | 该条有缓存时显示 | 删音频 + annex，标签 / 封面 / 歌单引用保留 |
| 销毁 | 总是显示 | 标签、cue 行、封面、对应音频、annex 一并删；歌单去掉失效引用 |
| 混合选择 | 两个都显示 | 各自按上面执行 |

多选工具条左端那个按钮是「全选」/「取消全选」，判定用**计数器对比**：选中数打满时它才变成叉号，作用是取消全选而**不是**退出多选；退出多选靠返回键（或点掉最后一项）。与网络库同一套交互，见 [02 §5](02-NETWORK-LIBRARY.md)。

多选状态下按系统返回键 → **只退出多选**，不会翻页也不会回主页。库页面里的多选组件向 `BackHandlerRegistry` 注册处理器并只在当前路由生效；流派 / 专辑的**子界面**不靠这条链——`_TrackListPage` 用自己的 `PopScope(canPop: !selecting)` 接管，多选时先吃返回键，退出多选后再按才 pop（见 [02 §5](02-NETWORK-LIBRARY.md) 的共用外壳说明）。

- CUE 虚拟分片**整组销毁、逐片落地**：点中任意一片就等于销毁整张专辑（提示与删除范围都是 cache group），但删除与墓碑都按**片**进行——每一片各删自己那行 `cue_slices`、各留各的墓碑；`cue_albums` 行只在最后一片走完时删掉。
  - 分工别搞混：**「整组」的展开在 `AppState.destroyTargets()`**（成员要查全库，只点一片时选中集合里只有一片），**「逐片」的落地在 `LibraryService.destroyTrack()`**。展开放错位置就会出现「点一首只掉一首」。确认框与进度条的数字都按展开后的集合算。
- 早期版本是「整组一次性清空行 + 只给被点的那片留墓碑」，墓碑范围比删行范围小。后果：云端旧基础分片里其余几片没有 `del-*` 记录挡着，下一次增量拉取（或「从云端覆写」）会把它们带回来。
- 「销毁音乐库」（菜单）是整库版本，见 `AppState.destroyMusicLibrary()` 与 [01 §3](01-DATA-MODEL.md)。

## 4. CUE 分轨

流程：点 `.cue` → **预览**曲目列表 → 确认后**整组下载**（CUE + 引用的音频进同一 `cacheGroupId`）→ 下载完成由队列调 `LibraryService.ingestCueAlbum` → 虚拟曲目进库。

- 库里是 `cue_slices` 虚拟行，**原始 `.cue` 文件本身不是一首歌**。
- 解码必须走 `decodeCueText(bytes)`（`lib/utils/cue_sheet.dart`）：处理 UTF-8 BOM、UTF-16 LE/BE，严格 UTF-8 失败时 `allowMalformed`（兼容 GBK）。用 `readAsString` 读非 UTF-8 CUE 会抛错，表现为「下载成功但虚拟曲目永不入库」——这是历史回归，不要再踩。
- 展示：多分片行标「多歌曲合并分片」，虚拟路径标记 `#cue:<trackIndex>`。
- 播放时按 clip 裁切，见 [05 §4](05-AUDIO-PLAYBACK.md)。
- **分享**：CUE 虚拟曲目不支持分享（提示「CUE 音轨不支持分享」）；不要恢复 ffmpeg 裁切导出的老方案。
- **删除**：按 cache group 整组删除；清空音频后 clip 元数据保留，便于重新下载后续播。

## 5. 分享与重命名

- 分享已有缓存的曲目时弹出「改文件名」对话框，默认模板 `{artist}-{title}`，也可「用原文件名」。
- 开关与模板在 **设置 → 分享**（不在同步页）。
- 实现：`share_rename_service.dart`、`library_actions.dart`。

## 6. 封面缩略图

- 默认边长 100，预设大图 300，也可自定义正方形边长（`clampCoverThumbSize`）。
- 设置只影响**新写入**的缩略图；已有文件要重新下载 / 重写标签 / 销毁后重下才会变尺寸。
- `AppState.setCoverThumbSize` 会同步到 `CoverService.thumbSize`。

## 7. 相关代码

`library_screen.dart`（列表 / 多选 / 销毁入口）、`library_actions.dart`（删除缓存、分享、入队）、`library_service.dart`（ingest / destroyTracks）、`library_database.dart`（schema）、`cache_service.dart`（annex 与文件）、`models/library_track.dart`。
