# 变更计划：视频播放 / 系统相册 / 媒体通知 / 同步与备份重构

> 本文件记录本轮需求（用户 2026 版）的实施结果与关键设计决定。

## A. 视频播放界面

- [x] **A1 控件居中**：`video_player_screen.dart` 改为「居中的浮动控制簇」（−10s / 播放暂停 / +10s 一行 + 锁定 / 倍速 / 画中画一行），标题与返回等放进顶部小胶囊条，进度条做成底部细条，都不再是通栏。
- [x] **A2 前进/后退动画**：新增 `_SeekFeedbackPill`（`TweenSequence` 缩放 + 淡入淡出，750ms）显示「前进 10 秒 / 后退 10 秒」与目标时间；按钮与双击手势都走 `_seekBy(..., label:)`。
- [x] **A3 长按 = 按住期间临时加速**：`onLongPressStart/End/Cancel` → `VideoPlaybackService.beginBoost/endBoost()`；不再是「切换 2 倍速」。
- [x] **A4 倍速浮窗滑块 0.5×–3.0×**：控制簇里的倍速按钮打开 bottom sheet，含滑块（0.05 步进）+ 预设 chip；结果写回 `SettingsService.setVideoLastRate`，下次打开自动恢复。
- [x] **A5 长按倍速可配置**：`SettingsService.videoLongPressRate`（默认 2.0×），在「视频播放设置」与播放器内手势设置里都能调。
- [x] **A6 小窗无控件**：`MainActivity.onPictureInPictureModeChanged` → `pictureInPictureChanged` → `PlatformExportService` 广播流 → 播放器进入 PiP 时隐藏整个覆盖层并禁用手势；同时避免 PiP 被视为「切后台」而暂停。
- [x] **A7 后台播放改为「主页键挂后台后生效」**：返回键 → `_handleBackPress()`（播放中弹确认框）→ `_handleExit()` 一定 `stop()`；顶部胶囊新增「转到后台」按钮调用 `moveTaskToBack`；`didChangeAppLifecycleState(paused/hidden)` 时仅在「后台播放」关闭时暂停并记录位置，回前台恢复。
- [x] **A8 视频媒体通知**：`MusicAudioHandler` 新增 `AudioHandlerMode.video`（`enterVideoMode` / `exitVideoMode`）。视频复用同一个 `audio_service` MediaSession：发布视频 `MediaItem`、只保留播放/暂停+停止控件、无队列；`VideoPlaybackService` 改成使用 handler 拥有的 `videoPlayer`（懒创建，音频-only 场景不额外开 libmpv）。该前台服务同时是切后台继续播放的前提。

## B. 下载与系统相册

- [x] **B1 视频下载写入系统相册**：`MainActivity` 新增 `saveToGallery`（MediaStore，`Movies/WebDAVMusic`；API<29 走公共目录 + `MediaScannerConnection`）。`DownloadTask` 新增 `DownloadTarget.gallery`；`DownloadQueueService.enqueueGallery/enqueueGalleryMany` + `_runGalleryDownload` 先下载到临时文件再交给 MediaStore，**不写音频缓存、不进音乐库**。
- [x] **B2 标注「系统相册」**：下载队列行显示「目标：系统相册 / 已存入系统相册」与落点；网络库视频行副标题显示「系统相册」；视频条目菜单写「下载到系统相册」。
- [x] **B3 本地备份导出到下载目录**：`SyncService.exportToDownloads` → `saveToDownloads`（`Download/WebDAVMusic/wmp-sync-<UTC>.zip`）。

## C. 播放互斥

- [x] **C1 视频播放时暂停音乐**：`AudioPlayerService.pauseForVideo()`（保留队列，可继续听）+ 打开视频时调用；反向 `AudioPlayerService._loadAndPlay` 若检测到 `handler.isVideoMode` 会先 `exitVideoMode()`。`VideoPlaybackService` 订阅 `playbackState` 在音乐接管时复位自身状态。

## D. 分享音乐文件

- [x] **D1 分享时可重命名**：`shareLibraryTracks` 单个文件时弹出可编辑文件名对话框（含「用原文件名」选项）；多选按模板批量重命名，复制到临时目录分享后清理，不改动缓存文件本身。
- [x] **D2 设置可配置、默认开启作者-标题**：`SettingsService.shareTagRenameEnabled`（默认 true）+ `shareTagRenamePattern`（默认 `{artist}-{title}`）；`ShareRenameService` 支持 `{artist} {title} {album} {albumArtist} {track} {year} {genre} {fileName}`，空字段自动收敛分隔符，保留扩展名。配置入口在「同步」页。

## E. 网络库

- [x] **E1 视频只显示播放按钮**：视频行 trailing 只有 `play_circle_outline`。
- [x] **E2 长按 / 多选才出现下载**：长按进入多选（工具条含「下载」与「下载整个文件夹」），右侧「更多操作」菜单里也有「下载到系统相册」。为保留原有长按菜单（重命名/删除），每行新增 `more_vert` 按钮。

## F. 音乐库

- [x] **F1–F3 按缓存状态显示按钮**：`_SelectionBar.hasCachedSelection`。无缓存 → 只有「销毁」；有缓存 → 「删除」+「销毁」；混合 → 两个都显示。
- [x] **F4 销毁语义**：`destroyLibraryTracks()` 删缓存（CUE 整组）→ `LibraryService.destroyTracks()` 删库表行 + `CoverService.deleteThumb/deleteFull` 删封面 → 移除内存索引。

## G. 同步与备份合并

- [x] **G1 合并**：新增 `SyncScreen`（设置 →「同步」），删掉设置页原来的「歌单同步 / 歌曲库同步 / WebDAV 备份」三块与对应 handler。`SyncService.push/pull/pullAll` 串起凭证、曲库+封面、歌单、站点备份。
- [x] **G2 凭证存云端**：`CredentialVaultService` → `/WebDAVMusicPlayer/credentials.json`。
- [x] **G3 本地导入/导出**：`exportToDownloads`；导入支持系统文件选择器（`pickFile` → SAF `ACTION_OPEN_DOCUMENT` 拷贝到缓存）、Base64 粘贴、以及应用自己导出的归档。
- [x] **G4 仅加密密码**：`CredentialVaultCrypto`（PBKDF2-SHA256 120k + AES-256-GCM，`AESGCMv1:` 前缀）只作用于密码字段；地址/用户名明文。站点备份的 `accounts.json` 也改为同一规则。
- [x] **G5 无统一密钥时密码留空**：`CredentialVaultCrypto.tryDecrypt` 失败 → 账号照常导入/恢复，密码留空并在结果里列出需要补填的服务器；`AccountsService.mergeAccountFromBackup/restoreFromBackup` 返回 missing 列表。

## 验证

- `flutter analyze`：无告警。
- `flutter test`：新增 `share_rename_test.dart`、`credential_vault_crypto_test.dart` 全通过；两个 `music_audio_handler*_test.dart` 在本机因缺 `libmpv-2.dll` 无法加载（改动前即如此，Windows 环境限制）。
- `flutter build apk --debug`：校验 Kotlin（MediaStore / SAF / PiP 回调）编译通过。
