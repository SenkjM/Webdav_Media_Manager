# A01 · 变更计划：视频播放 / 系统相册 / 媒体通知 / 同步与备份重构

> **文档编号 A01** · 状态：已完成 · 模式：**归档（禁止再改正文）**  
> 总索引：[INDEX.md](../INDEX.md)  
> Agents：不得修改本文正文；勘误请新建编号文档并在 INDEX 备注。

> 本文件记录需求实施结果与关键设计决定。第二轮（用户反馈）已并入。

## 第二轮修复（用户反馈）

- **音乐库下载功能被破坏** ✅ 修复
  - 根因：`DownloadQueueService._ingest` 与 `ensureQueued`、`LibraryService.ingestDownloaded` 用**硬编码**后缀列表（缺 `.m4a` / `.aac`），而网络库用**用户配置**的后缀集分类。两者不一致 → `.m4a`/`.aac` 下载在 ingest 处抛 `StateError`，任务被标为失败；用户自定义后缀也会被静默丢弃。
  - 修法：下载队列新增 `isMusicFile` 谓词，由 `AppState` 从 `settings.fileTypes` 注入（`configureFileTypes`，在设置页改后缀后调用 `refreshFileTypeClassifiers()` 重新注入）；`LibraryService.ingestDownloaded` 不再自行校验（调用方已判定）。新增回归测试 `test/music_extension_policy_test.dart`。
- **无用脚本** ✅ 删除 `.ab-bench.ps1` / `.standard-test.ps1`（socks5-tunnel 技能的一次性基准脚本），并在 `.gitignore` 忽略这几个本地文件。
- **控件位置** ✅ 从居中改为**靠下**（`Alignment(0, 0.66)` 的控件簇 + 底部进度条），不再占据画面中央。
- **单击 / 双击** ✅ 单击画面显示控件，再次单击隐藏；**双击画面中间 = 播放/暂停**。实现：整屏拆成左 30% / 中 40% / 右 30% 三个 `GestureDetector` 区域，中间区域双击固定为播放暂停，两侧仍走可配置手势。
- **退出二次确认可配置** ✅ `SettingsService.videoConfirmExit`（默认关闭）；开启后对话框只问「确认关闭视频吗？」+ 取消/关闭。
- **视频当前播放列表** ✅ 新增 `VideoQueueController`：用当前目录列表作种子**立即开播**，同时后台**深度优先渐进扫描**子目录，每扫完一个目录就合并进队列（按名称排序、去重），所以「上一个 / 下一个 / 自动连播」不必等扫描结束。控件含跳过按钮、队列计数（`3 / 27 · 扫描中…`）和可跳转的播放列表面板。
- **分享重命名配置位置** ✅ 从「同步」页移到**设置 → 分享**（开关 + 模板编辑）。
- **备份不做站点隔离** ✅ `BackupService` 重写（`formatVersion 4`）：**一个**归档 = 全部凭证 + 全部音乐库 + 全部歌单 + 封面。界面先选「① 存放备份的网盘」再填「② 备份路径」再「③ 开始备份」；可列出该路径下的备份并恢复。旧的按站点 `/backup/<站点>/` 目录、`full-backup` 等概念全部移除。
- **三种数据三种同步** ✅ 删除 `library_sync_service.dart`，`SyncService` 重写：

  | 数据 | 行为 |
  |------|------|
  | WebDAV 凭证 | 真同步：与云端 `credentials.json` 双向合并；`autoScan()` 在启动 / 切换账号 / 每 30 分钟跑 |
  | 歌单 | 真同步：双向 M3U8，最后写入胜出；改动即时上传，定时拉取 |
  | 音乐库 | 增量：`library` 监听 + 20s 防抖 → `syncLibraryIncremental()`（只补差异、不删除）；手动 `syncLibraryFull()` 对齐删除 |
  | 全部备份 | `backupTo(destination, remoteDir, passphrase)` 一次性归档 |

- **不必兼容老版本** ✅ 直接移除站点作用域恢复、`fullMultiAccount`、`librarySyncRemotePath` 分支等旧路径，未保留迁移逻辑。

## 第一轮需求

### A. 视频播放界面
- [x] A1 控件靠下的浮动控件簇
- [x] A2 前进/后退缩放淡出动画反馈
- [x] A3 长按 = 按住期间临时加速，松手恢复
- [x] A4 倍速浮窗滑块 0.5×–3.0×，记忆上次选择
- [x] A5 长按倍速可配置（默认 2.0×）
- [x] A6 小窗（PiP）不显示任何控件
- [x] A7 后台播放由主页键挂后台触发；返回键一定停止
- [x] A8 视频发布媒体通知（`AudioHandlerMode.video`，复用同一 MediaSession）

### B. 下载与系统相册
- [x] B1 视频下载写入系统相册（`MediaStore Movies/WebdavMediaManager`）
- [x] B2 下载队列与网络库标注「系统相册」
- [x] B3 本地备份导出到系统下载目录

### C. 播放互斥
- [x] C1 视频播放暂停音乐（保留音乐队列，退出视频后可在通知里继续）

### D. 分享音乐文件
- [x] D1 分享时可重命名文件名
- [x] D2 设置中可配置，默认开启且为 `作者-标题`

### E. 网络库
- [x] E1 视频条目不显示下载按钮，只有播放按钮
- [x] E2 长按 / 多选时才出现下载

### F. 音乐库
- [x] F1 有缓存：显示「删除」+「销毁」
- [x] F2 无缓存：只显示「销毁」
- [x] F3 混合选择：两个都显示
- [x] F4 销毁 = 删缓存 + 从音乐库删除 + 销毁元数据与缓存封面

### G. 同步与备份
- [x] G1 歌单同步 / 歌曲库同步 / WebDAV 备份 合并为「同步与备份」
- [x] G2 WebDAV 凭证统一存放在云端
- [x] G3 本地导入 / 导出
- [x] G4 仅加密密码，地址与用户名明文
- [x] G5 无统一解密密钥时密码留空恢复

## 验证

- `flutter analyze`：无告警
- `flutter test`：113 通过；2 个 `music_audio_handler*_test.dart` 因本机缺 `libmpv-2.dll` 无法加载（改动前即如此，CI 有 `libmpv-dev`）
- `flutter build apk --debug`：编译通过（含 MediaStore / SAF / PiP 原生代码）
