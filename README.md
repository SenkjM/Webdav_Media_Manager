# Webdav Media Manager

基于 **Flutter** 的 **Android** 网盘媒体管理器（Webdav Media Manager）。

仓库：[https://github.com/SenkjM/WEBDAV-music-player](https://github.com/SenkjM/WEBDAV-music-player)

## 作者与致谢

- **实现**：Grok Bot（基于需求完成工程搭建、核心功能与 CI）
- **创意与需求框架**：SenkjM

本仓库代码由 Grok Bot 实现；SenkjM 提出产品思路与约束（WebDAV 先缓存再播放、下载队列、缓存策略、本地音乐库、多网盘等）。

## 开发文档

面向开发者与 coding agents 的架构、数据模型、CUE、播放约束与 CI 说明见：

- [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)

## 这是什么

在 WebDAV 上浏览音乐目录，把文件下载到本地缓存后再播放。**不做网络流式播放**。

### 主要能力

- **网络库（多 WebDAV）**：未下载音频浏览时不显示「排队」等状态徽标（点按/多选下载后才入队并显示）；可添加 / 编辑 / 删除多个服务器账号（URL、用户名、密码经安全存储）；在网络库中切换当前服务器；浏览时只显示条目名称（不铺满远程完整路径）。**视频条目只显示「播放」按钮**，下载要到长按（多选）或右侧「更多操作」菜单里才会出现
- **下载队列**：后台异步排队下载，支持取消 / 重试 / 清除已完成；长按文件夹可**递归下载整个目录**中的音频。**视频下载写入系统相册**（MediaStore `Movies/WebdavMediaManager`），下载队列与网络库都会标注「系统相册」；音乐仍下载到应用内部音频缓存（播放只读缓存）
- **标签读取**：下载完成后用 `audio_metadata_reader` 读取 title / artist / album / track / disc / 封面 / 时长，并写入本地音乐库
- **本地音乐库**：仅索引「至少缓存过一次」的曲目；可按 **专辑 / 作者 / 音乐名 / 标签（流派）** 浏览；支持 **搜索**（标题/艺术家/专辑）；长按进入多选（添加到歌单 / 分享 / **删除** / **销毁**；CUE 组删除仍整组警告；CUE 虚拟曲目不可分享）；支持按 **名称** 或 **专辑曲序（碟号/曲号）** 排序；身份键为 `(网盘名 + remote_path)`
  - 多选工具条按缓存状态显示按钮：**所有选中项都无缓存 → 只显示「销毁」**；**有缓存 → 同时显示「删除」与「销毁」**；混合选择同样显示两个
  - **删除**：只删本地音频缓存，保留标签与封面；**销毁**：删缓存 + 从音乐库移除 + 销毁元数据与压缩封面（不可恢复）
- **分享重命名**：分享已缓存音频时可按标签重命名，**默认开启且模板为「作者-标题」**（`{artist}-{title}`）；分享单个文件会弹出可编辑的文件名对话框，也可选「用原文件名」。模板支持 `{artist} {title} {album} {albumArtist} {track} {year} {genre} {fileName}`，在**设置 → 分享**里配置
- **元数据持久化**：库记录与压缩封面缩略图独立于音频缓存；清空或过期清理音频缓存**不会**删除库与封面；同一账号+路径再次下载会刷新标签与封面
- **销毁音乐库**：音乐库页菜单「销毁」可一次性清除标签/CUE 表、压缩封面与对应本地音频缓存（不可恢复）；网络库与账号保留；歌单去掉已失效曲目引用。区别于设置中的「手动清空音频缓存」（保留标签与封面）
- **封面缩略图尺寸**：设置中可选默认 **100×100**、预设 **300×300** 或自定义正方形边长；仅影响**新**写入的缩略图。已有文件保持原尺寸，需重新下载/写入标签或销毁后重下才会按新尺寸生成
- **本地播放**：仅用本地文件路径播放（`media_kit` + `audio_service` 媒体通知 / 系统媒体控制）
- **视频播放器**：控件是**靠下**的浮动控件簇（不挡画面中间）；**单击画面显示 / 再次单击隐藏控件**，**双击画面中间 = 播放 / 暂停**（左右两侧仍是可配置的跳转手势）；前进/后退带缩放淡出**动画反馈**；**长按 = 按住期间临时加速**（倍速可在设置里调，默认 2.0×），松手恢复；播放倍速用**浮窗滑块**在 **0.5×–3.0×** 之间调整并记住上次选择；**播放列表按文件夹自动建立**（先用当前目录列表立即开播，再**后台渐进扫描**子目录，扫到就追加，不必等扫完），支持上一个 / 下一个与**自动连播**；**小窗（画中画）时不显示任何控件**；**后台播放在主页键挂后台后生效**（返回键会停止，是否二次确认可配置）；视频播放期间会**暂停音乐**，并**发布媒体通知**
- **CUE 分轨**：网络库显示 `.cue`；标准 CUE（FILE + TRACK/INDEX）可整组下载（CUE+音频同一缓存组）；音乐库展开为虚拟曲目，标签以 CUE 为准；播放用 `Media(start:, end:)` 原生裁切按 INDEX 分片；删除缓存时整组提示
- **缓存占用**：设置页显示音乐缓存磁盘用量（可读大小）；曲库可单独删除某曲本地音频缓存（保留元数据/封面）
- **当前播放列表**：正在播放页 / 迷你条可打开**临时队列**（不自动同步歌单）；歌单页可「从当前播放列表创建」保存后再同步
- **媒体通知**：`audio_service` 使用应用内补丁（Android 14+ typed `startForeground` + 通道 `…audio.v4` IMPORTANCE_DEFAULT）；`androidStopForegroundOnPause: false`；播放引擎为 `media_kit`，`play()`/`stop()` 时显式申请/释放 Android 音频焦点。**音乐与视频共用一个 MediaSession**：`MusicAudioHandler` 通过 video 模式接管通知，因此视频也有媒体通知与前台服务（这也是切后台仍能继续播放的原因）。设置页「测试媒体通知」回报会话/通知是否已发布
- **缓存清理**：可按 1 天或 1 周自动清理**音频缓存文件**；正在播放或下载中的文件受保护
- **WebDAV 管理**：长按可重命名 / 删除；可新建文件夹；权限不足（401/403）时弹出错误对话框
- **同步与备份**：设置 →「同步与备份」。这个 App 只有三样数据，各自用合适的方式同步，**没有站点隔离**：
  - **WebDAV 凭证 = 真同步**：统一存放在云端 `credentials.json`，**地址与用户名为明文、只加密密码**（AES-256-GCM，`AESGCMv1:` 前缀，可关闭改成明文）。启动 / 切换账号 / 每 30 分钟自动双向扫描。无法提供统一解密密钥时**密码留空恢复**，其余字段照常写回，之后再补填
  - **歌单 = 真同步**：双向 M3U8，`updatedAt` 最后写入胜出；改动即时上传，启动 / 切换账号 / 定时拉取合并
  - **音乐库 = 增量同步**：本地下载完成（防抖 20s）即把新增曲目推到云端索引，云端新增也会拉下来；不会删除。需要对齐删除时用**全量同步**
  - **全部备份**：把凭证 + 音乐库 + 歌单打成一个归档，**自己挑网盘再挑路径**，写 `backup-<UTC>.wdmm` 与 `webdav_media_backup.wdmm`（latest）；可从该路径列出备份并恢复
  - **本地导入 / 导出**：导出到 `下载/WebdavMediaManager/wdmm-export-<UTC>.wdmm`（可读 JSON 模式则为 `.json`；口令可选）；导入走系统文件选择器（SAF）或粘贴 Base64

### 导航

侧边栏（Drawer）：音乐库、歌单、网络库、下载队列、设置、关于 / AGPL。

**全局迷你播放条**：挂在应用壳（`HomeShell`）上，音乐库 / 歌单 / 网络库 / 下载队列及其子页（嵌套 Navigator）均可见；**设置页隐藏**。仅在已有本地缓存曲目正在播放时显示；**从不**在播放器 / 迷你条上展示下载进度。未下载曲目在音乐库中仅为占位 + 点按加入下载（右侧色点区分本地 / 未下载）。

## 技术要点

| 模块 | 方案 |
|------|------|
| 库 / 账号持久化 | `sqflite`（`music_library.db`：accounts + tracks） |
| 下载队列 | `sqflite`（`download_queue.db`） |
| 标签 | `audio_metadata_reader` |
| 封面缩放 | `image` → 正方形 JPEG（默认 100×100，可设置），存于应用文档 `covers/` |
| 凭证 | `flutter_secure_storage`（本机）＋ 云端 `credentials.json`（仅密码加密） |
| WebDAV | `webdav_client` |
| 媒体通知 / 后台播放 | `audio_service` + `media_kit`（`MusicAudioHandler`，含 video 模式） |
| 系统相册 / 下载目录写入 | 原生 `MediaStore`（`MainActivity` MethodChannel，Android 10+ 免权限） |
| 本地文件导入 | 原生 SAF `ACTION_OPEN_DOCUMENT`（拷贝到应用缓存后读取） |
| 通知权限 / 通道（Android 13+） | `flutter_local_notifications`（建「音乐播放」通道 + `POST_NOTIFICATIONS` + 通道状态查询） |

## 状态

**WIP（开发中）**。核心流程已实现，仍在完善与打磨。

### UI

界面以**浅色系**为主（近白 / 浅灰底、深色文字、青绿强调色），参考过 **Poweramp** 信息密度与 **Salt Player** 信息架构（非仿冒皮肤；无商标素材）。大封面 Now Playing 与底部迷你播放条。

## 许可

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）** 授权。

完整文本见仓库根目录 [LICENSE](./LICENSE)。

简要说明：你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，必须按 AGPL-3.0 公开对应完整源代码。详情以 LICENSE 原文为准。



## 权限与媒体通知

- **Android 13+**：运行时请求 `POST_NOTIFICATIONS`（首次启动 / 首次播放 / 设置页）。通知权限开启后，媒体通知才能显示。
- **通知通道**：`flutter_local_notifications` 在启动时创建并接管「音乐播放」通道（`com.senkjM.media_manager.audio.v4`，IMPORTANCE_DEFAULT、静音、不震动），并负责查询权限与通道状态；`audio_service` 原生 `createChannel()` 发现通道已存在即复用，因此设置页在首次播放前就能显示系统真实通道状态（定义见 `lib/services/media_notification_channel.dart`，须与 `AudioServiceConfig` 保持一致）。
- **媒体播放通知**：通过 `audio_service` 的 `MusicAudioHandler` 在播放时启动 `mediaPlayback` 前台服务，并发布 `MediaItem` + `PlaybackState`，使通知栏 / 锁屏 / 系统媒体控制中心显示 MediaStyle 控件（播放/暂停，有队列时上一首/下一首）。通知小图标使用 `drawable/ic_stat_music`（不可用自适应 launcher 图标）。
- 需声明 `WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`，并注册 `AudioService` / `MediaButtonReceiver`；`MainActivity` 继承 `AudioServiceFragmentActivity`（保证共享 FlutterEngine 不随 Activity 销毁而销毁，避免切后台后通知/播放状态丢失）。
- **视频媒体通知**：`MusicAudioHandler` 与视频共用同一个 MediaSession。进入视频时切到 video 模式（`mediaItem` = 视频标题、控件只保留播放/暂停与停止、无队列），因此通知栏 / 锁屏 / 媒体控制中心都会显示视频；`FOREGROUND_SERVICE_MEDIA_PLAYBACK` 前台服务也是「主页键挂后台仍继续播放」的前提。
- **系统相册 / 下载目录**：`MainActivity` 通过同名 MethodChannel 暴露 `saveToGallery` / `saveToDownloads` / `pickFile`：Android 10+ 走 `MediaStore`（`Movies/WebdavMediaManager`、`Download/WebdavMediaManager`，无需运行时权限），Android 9 及以下退回公共目录写入 + `MediaScannerConnection`（需要 `WRITE_EXTERNAL_STORAGE`，已用 `android:maxSdkVersion="28"` 声明）。PiP 状态通过 `onPictureInPictureModeChanged` 回传 `pictureInPictureChanged`。
- 真机验证：通知样式与锁屏控件需在真实 Android 设备上确认；模拟器上权限与 FGS 行为可能不完整。
- **CUE**：网络库点开 `.cue` 先预览曲目再下载；下载队列将 CUE 组折叠为单行；清空缓存后会失效陈旧 completed 任务，库内 clip 元数据保留以便重新下载后继续分段播放。

## 分支策略

| 分支 | 用途 |
|------|------|
| `main` | 稳定主干 |
| `beta` | 预发布线；**GitHub Pre-release 只从 beta 构建发布** |
| `dev` | 实验线，给助手试新功能 / 不稳定改动 |

日常：在 `dev` 试新鲜玩意 → 成熟后合入 `beta` 打 Pre-release → 再合入 `main`。


## 预发布版本号（可覆盖安装）

CI 在 `flutter build apk` 前计算：

| 变量 | 规则 |
|------|------|
| `SHORT_SHA` | `github.sha` 前 7 位 |
| `VERSION_NAME` | `pubspec` 版本基（如 `1.0.0`）+ `-` + `SHORT_SHA`，例如 `1.0.0-abc1234` |
| `VERSION_CODE` | `1000 + github.run_number`（单调递增） |

构建命令：

```bash
flutter build apk --release \
  --build-name="$VERSION_NAME" \
  --build-number="$VERSION_CODE"
```

Android 要求新 APK 的 `versionCode` 更大才能覆盖安装；因此预发布无需先卸载。Pre-release 名称 / 正文会写入同一版本字符串；应用「关于」页显示 `version+buildNumber`。

## 歌单（M3U8）

- **本地**：`playlists.db`（应用文档目录），与 `music_cache` 分离
- **远程**：可配置目录，默认 `/Playlists/<name>_<id前8位>.m3u8`
- **格式**：扩展 M3U8，路径行为 `wmp://<accountId>/<remotePath>`；头字段 `#EXT-X-WMP-ID` / `#EXT-X-WMP-UPDATED` / `#EXT-X-WMP-NAME`
- **同步策略**：最后写入胜出（比较 `updatedAt`）；相等时保留本地
- **UI**：抽屉「歌单」；音乐库曲目长按「添加到歌单」。同步入口在「设置 → 同步与备份」

## 同步与备份

只有三样数据：**WebDAV 凭证、音乐库、歌单**。没有站点隔离 —— 一份凭证表、一份音乐库、一份歌单，备份自己挑网盘和路径。

- **入口**：设置 →「同步与备份」（`SyncScreen`）
- **云端根目录**：`SettingsService.syncRemoteRoot`（默认 `/WebdavMediaManager/`）
  - `credentials.json` — WebDAV 凭证：**地址 / 用户名明文**，密码可选加密
  - `library/<accountId12>/library_index.json` — 曲库索引（`formatVersion 2`）
  - `/Playlists/*.m3u8` — 歌单
  - 备份路径（默认 `/WebdavMediaManager/backup/`）下 `backup-<UTC>.wdmm` + `webdav_media_backup.wdmm`
- **各自的同步方式**
  | 数据 | 方式 |
  |------|------|
  | WebDAV 凭证 | 真同步（双向），启动 / 切换账号 / 每 30 分钟自动扫描 |
  | 歌单 | 真同步（双向，最后写入胜出），改动即时上传 + 定时拉取 |
  | 音乐库 | 增量（本地变化防抖 20s 后推送；云端新增拉下来），可手动**全量同步**对齐删除 |
  | 全部备份 | 一次性归档：凭证 + 音乐库 + 歌单 + 封面，写到自选网盘与路径，可从该路径恢复 |
- **凭证加密**：`settings.syncEncryptPassword`（默认开启）。密码字段为 `AESGCMv1:<base64(salt|nonce|ct|mac)>`（PBKDF2-SHA256 120k + AES-256-GCM）。**无法提供统一解密密钥时，密码留空恢复**，其余字段照常写回
- **本地导入 / 导出**：
  - 导出 → `下载/WebdavMediaManager/wdmm-export-<UTC>.wdmm`（可选口令加密，密文以 `WDMMEN01` 开头）或 `.json`（可读，不含封面）
  - 导入 ← 系统文件选择器（SAF，任意 `.wdmm` / `.json`）或粘贴 Base64

## CI：自动构建并发布 Pre-release

**自动构建只在 `beta` 上跑**（`main` / `dev` 的 push 不触发）。正式 release 等 beta 测完后再合入 `main` 并打版本号。

工作流：`.github/workflows/android-build.yml`

**触发条件（全部由 Actions 自动执行）：**

| 触发 | 行为 |
|------|------|
| 推送到任意分支 | **不**触发构建 |
| 推送到 `main` / `dev` | **不**触发 Actions 自动构建 |
| 每天定时（约北京时间 00:00） | 检查 **beta**：相对上次 `prerelease` 有新提交才发布；无变动跳过 |
| 手动 `workflow_dispatch`（选 `beta`） | 构建并更新 Pre-release |

**产物：**

- Actions Artifacts：`app-release-apk`（及可选 `app-release-aab`）
- GitHub Pre-release 标签：`prerelease`（持续覆盖更新，附 APK）

说明：

- **私有仓库**需在 Settings → Actions 启用工作流；发布 Pre-release 使用默认 `GITHUB_TOKEN`（`contents: write`）。
- CI APK 为默认签名，仅适合内测；正式分发请自行配置 keystore（不要把密钥提交进仓库）。
- 每次构建写入递增 `versionCode`（`1000+run_number`）与带短 hash 的 `versionName`，Pre-release 正文同步显示，便于覆盖安装。

## 内测签名

CI Pre-release 使用**固定内测 keystore**（GitHub Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`），避免 Actions 每次换机器导致签名变化、无法覆盖安装。

从旧的 debug 签名包换成内测签名包时，需要**卸载一次**；之后可直接覆盖安装。

本地 release 可通过环境变量或未提交的 `android/key.properties` 使用同一 keystore。
