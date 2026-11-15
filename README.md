# Webdav Media Manager

**面向 Android 的网盘媒体管理器。** 把 WebDAV / 云盘当作媒体库：浏览、下载或流式播放、离线听歌、看漫画、投屏到 DLNA 设备，并把音乐库、漫画库与歌单增量同步到云端。

- 当前版本：**v0.4.0**（2026-11）—— [下载 APK](https://github.com/SenkjM/Webdav_Media_Manager/releases/tag/v0.4.0) · [项目主页](https://wdmm.senkjm.top)
- 许可：[AGPL-3.0](./LICENSE)
- 平台：Android 7.0+（arm64-v8a / x86_64），包名 `com.senkjm.media_manager`

## 目录

- [功能](#功能)
- [架构](#架构)
- [获取与安装](#获取与安装)
- [开发](#开发)
- [发布](#发布)
- [文档](#文档)
- [路线图](#路线图)
- [作者与协作者](#作者与协作者)
- [为什么开源](#为什么开源)
- [许可](#许可)

## 功能

### 网络库与账号

- **多账号**：可添加多个 WebDAV 服务器，也支持云盘直连（115、阿里云盘、百度网盘、123pan、TeraBox、城通、网易云音乐）。云盘驱动使用官方 API，当前为**只读**；WebDAV 支持新建文件夹、重命名、删除与上传（走系统文件选择器，进度进任务队列）。
- **Crypt 加密源**：与 rclone Crypt 格式兼容，加密内容在本地解密后经本地代理以流的形式交给播放器，不落明文、不返回明文直链。
- **浏览**：网络库首次进入才列一次目录，顶栏刷新、换账号、进出目录、失败重试会重新列。401/403 会明确提示。可按后缀识别音乐 / 视频 / 图片 / CUE / 漫画，每类后缀与点按行为均可配置。
- **绑定规则**：曲目按「网盘名 + 路径」唯一绑定；重名或改名会说明后果并在账号页拦截。
- **CUE 分轨**：识别标准 CUE，把整张专辑按分片导入音乐库并展开为分轨曲目；长按文件夹可递归下载整个目录。

### 下载与任务队列

- 先下载再播放：音乐单击默认进缓存队列，缓存完成后用本地文件播放；视频直接流式播放；图片不进队列，直接查看。
- 后台队列：取消 / 重试 / 删除 / 清除已完成 / 清除全部，状态持久化，可在任务页查看进度、失败原因与取消。
- 落盘位置可配：音频缓存、视频到系统相册（`Movies/WebdavMediaManager`）、图片到系统相册（`Pictures/WebdavMediaManager`）、「下载」到系统下载目录或自定义文件夹。
- 进度通知 + 完成通知（可关闭），下载保活与「排除媒体扫描」开关。

### 音乐库

- 至少缓存过一次的曲目进入本地库：标题 / 艺人 / 专辑 / 曲序 / 碟号 / 封面 / 时长 / 标签 / 歌词。
- 按 **专辑 / 作者 / 音乐名 / 标签（流派）** 浏览，支持搜索与排序；FTS5 全文索引。
- 长按多选：添加到歌单 / 分享 / 删除 / 销毁。删除只清音频缓存（标签与封面保留），销毁连标签、封面、缓存一起清；CUE 分片整组处理。
- 分享给其他应用时可**按标签重命名文件名**（模板可配），文件仍是缓存里的那一份。
- 支持「刷新标签」「重定向后重读」，标签解析在 Rust 侧完成。

### 漫画库

- 在网络库里把漫画**扫描进漫画库**：默认识别 CBZ，也支持把散图目录合并成一本书，或按目录批量建立。CBR / PDF / EPUB 解析目前是 stub。
- 按 **系列 / 单本 / 作者** 浏览，列表与网格各自记忆视图；阅读进度按本记录（列表 `x/y`，网格封面进度条）。
- **系列就是书身上的一个标签**：系列列表、本数、封面都从书派生，改名等于把成员并到新名字下，清空就是「未指定系列」。
- 散图书可**物化为 CBZ**：逐页打包并上传到所选目录，打包与上传是任务列表里的两行，各有进度。
- 打开方式（流式边看边取 / 先整包缓存）与漫画库自己的缓存设置（占用、过期清理、容量上限、全部清理）独立于音乐库。刮削与整包缓存都走任务队列。

### 播放

- 完整播放页 + 底部迷你播放条 + 临时播放队列（可另存为歌单）；通知栏 / 锁屏 / 耳机控制；Android 13+ 需要通知权限。
- **音频**：默认先缓存再播；打开流式开关后可直接按 HTTP Range 读取并解析内嵌标题 / 艺人 / 专辑 / 封面 / 歌词（只放内存，不入库），并显示在播放页与媒体通知里。
- **视频**：直接流式播放，按文件夹自动连播；画中画、后台播放、锁定屏幕、退出二次确认、单击显隐控件、双击中间播放 / 暂停、左右双击各自指定动作、长按临时加速、0.5×–3× 倍速。
- **字幕**：同目录外挂字幕（可再开一层子目录）、内嵌文本字幕转 WebVTT、当集手动导入；字幕位置与字号可调。
- **硬件解码**：MediaCodec 硬解优先、失败回退软件解码，可在视频设置里切换；缓冲大小可配。
- **图片**：全屏查看当前目录图片，左右点按切换、中间打开图片设置，支持幻灯片与预取；不进下载队列。

### 歌单

- 从当前播放队列或音乐库创建、编辑、删除；整份歌单以二进制文档双向同步，按更新时间合并。
- 删除另记一包（条目墓碑），避免别的设备把已删歌单或条目传回来；歌单存在独立数据库里，**清理音频缓存不会动它**。

### 同步与备份

- **统一远端根**：在「同步与备份」页选一次同步账号 + 填一次路径，凭证、歌单、音乐库、漫画库与备份都在它下面；所有路径都**相对当前账号的文件源**解析（例如填 `/WDMM`，实际写到 `<文件源>/WDMM/`）。
- **凭证**：与云端凭证包双向合并（`credentials.wdmcv`、`accounts.wdmcv`）；可选统一加密密钥，只加密密码字段，地址与用户名保持明文以便识别站点。
- **音乐库 / 漫画库**：云端清单 + 二进制分片（`lib-` / `seg-` / `del-*.wdmm`），只传变化；可手动「重建」（以本机为准重写并落实删除）与「整理」（清孤儿文件）。漫画库走同一套流程，阅读进度一并同步。
- **全部备份**：把凭证 + 音乐库 + 漫画库 + 歌单打成一个 `.wdmm` 归档（含封面）写到远端 `backup/`，可列出并恢复；恢复是合并写入，不会清空本机其它数据。
- **本地导入 / 导出**：`.wdmm` 归档或可读 `.json`，也支持粘贴 Base64。
- **定时同步**：默认关闭，可选 15 分钟 / 30 分钟 / 每小时 / 每 6 小时 / 每天；删除记录可在设置里手动清理。

### 投屏与转码

- DLNA / UPnP：SSDP 发现渲染器，AVTransport 投送；支持把网络库里的视频直接投到电视播放。
- HLS 点播化转码：进程内 FFmpeg（n9.0.2）按预设 remux 或转码，按关键帧切分片，播放端拉流由本地代理提供。
- **转码预设**：内置预设 + 自定义；视频与音频 remux 各三档（关 / 严格 / 开）。「严格」按运行时实际目标编码器与 MPEG-TS 合法编码集判定是否可直通；x264 速度预设为五档（极速 / 快速 / 均衡 / 高质量 / 极致），码率控制、编码器选项均可调。

### 其他

- 主题：浅色 / 深色 / 跟随系统，单一主题色生成整套配色；播放器上的纯黑纯白叠层不跟随。
- 多语言：跟随系统 / 简体中文 / 繁体中文 / English。
- **OpenAPI**：可开启的本地 REST 服务（默认回环，token 自动创建与持久化），提供 `/v1/library`、`/v1/playlists`、`/v1/tasks`、`/v1/media/link` 等接口；媒体字节统一由 `/v1/media/link` 返回稳定代理地址或签名直链。
- 缓存维护：查看占用、按 1 天 / 1 周 / 自定义时长自动清理或「永不」，正在播放或下载中的文件不会被删。

## 架构

从 v0.4.0 起，业务层整体在独立的 Rust 工作区 **[WDMM-core](https://github.com/SenkjM/WDMM-core)**（本仓库子模块 `rust/wdmm-core`），编译为单个 `libwdmm_ffi.so`。本仓库只保留 Flutter UI 与 Android 平台适配：

```
┌──────────────────────────────────────────────────────────┐
│  Flutter UI（lib/）                                       │
│  screens · widgets · providers · thin service adapters    │
└───────────────────────┬──────────────────────────────────┘
                        │ Dart FFI（lib/services/rust_core_service.dart）
┌───────────────────────▼──────────────────────────────────┐
│  libwdmm_ffi.so — crates/wdmm-ffi（唯一 C ABI 边界）      │
│  ├─ wdmm-storage   SQLite v21（库 / 账户 / 预设 / 队列 / KV）│
│  ├─ wdmm-core      模型、曲目身份、版本时钟                │
│  ├─ wdmm-sync      凭证 / 歌单 / 音乐库 / 漫画库增量同步   │
│  ├─ wdmm-jobs      标签、封面、刮削、预取等作业            │
│  ├─ wdmm-drivers   8 个直连驱动 + Crypt 包装（WdmmVfs）    │
│  ├─ wdmm-ffmpeg    进程内 FFmpeg n9.0.2（remux / 转码 / 硬解）│
│  ├─ wdmm-proxy     本地 HTTP 代理（Range / HLS / DLNA）    │
│  ├─ wdmm-dlna      SSDP + AVTransport                     │
│  ├─ wdmm-openapi   本地 REST API（回环 + token）           │
│  ├─ wdmm-crypto    AES-256-GCM 凭据库与备份封装            │
│  └─ wdmm-queue / wdmm-platform / wdmm-text                │
└──────────────────────────────────────────────────────────┘
```

Dart 侧不直接发认证请求、不操作数据库、也不拼接媒体 URL：所有云文件 I/O 走 `WdmmVfs`，媒体字节走 `/v1/media/link`，同步只传 `account_id + remote_dir`。

### 关键契约

- **单一驱动 trait**：只有 `WdmmVfs`（`list` / `mkdir` / `remove` / `put_content` / `get_content`），没有平行的 VFS / 对象存储层；引擎直接拿 `Arc<dyn WdmmVfs>`。
- **账号解析只在边界**：`account_id` → `DriverRegistry::create_driver` → 驱动；同步 FFI 不收 url / 用户名 / 密码。
- **Crypt 内容必须是代理流**：wrapper 只暴露 `LocalStream`，永远不返回明文直链。
- **同步根相对文件源**：FFI 用账号 credentials 里的 `remote_dir` 拼接同步路径，避免把路径解析到 WebDAV 服务器根（虚拟根可能不可写）。
- **媒体字节统一出口**：Dart 不得把上游 `raw_url` / `raw_headers` 直接塞进播放器或 DLNA `SetAVTransportURI`。
- **ABI 限制**：只支持 arm64-v8a 与 x86_64（FFmpeg LP64 FFI），不支持 armeabi-v7a；Android 构建要求 NDK r28+（16 KB 页对齐）。
- **GPL 合规**：所有 FFmpeg 构建脚本禁止 `--enable-nonfree`。

更多层图、启动序列与约束见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 获取与安装

- **正式版**：由合法且递增的 `vX.Y.Z` tag 触发 `release-build.yml` 构建，产物在 [Releases](https://github.com/SenkjM/Webdav_Media_Manager/releases)。v0.4.0 提供：
  - `webdav-media-manager-v0.4.0-arm64-v8a.apk`（绝大多数手机）
  - `webdav-media-manager-v0.4.0-x86_64.apk`（模拟器 / 部分平板）
  - `webdav-media-manager-v0.4.0.aab`
- **预发布（内测）**：来自 `main`，由 `pre-release-build.yml` 构建；版本形如 `v0.3.0-3000005`（正式版本号 + versionCode）。
- **签名**：历史上从旧签名换到当前签名需要先卸载一次，之后可直接覆盖安装。
- **不支持**：armeabi-v7a 设备、iOS、桌面端（Rust 分层已为将来跨平台留出空间，但目前只发布 Android）。

## 开发

### 环境要求

| 依赖 | 版本 / 说明 |
|---|---|
| Flutter / Dart | `pubspec.yaml` 要求 Dart `^3.13.4`；Windows 下建议 `FLUTTER_ROOT` 指向 SDK（默认 `D:\flutter`） |
| Rust | 1.99.1（由子模块 `rust/wdmm-core/rust-toolchain.toml` 固定，含 clippy 与两个 Android target） |
| Android NDK | `28.2.13676358` |
| FFmpeg | n9.0.2 共享库（Android 由 `build-ffmpeg-android.yml` 构建并发布到滚动 release `ffmpeg-android-libs`） |
| JDK | 17 |

Windows 上仓库自带 `tool/` 下的 PowerShell 包装脚本（`flutter-sandbox.ps1`、`flutter-pub-get.ps1`、`build-rust.ps1`、`e2e.ps1`），推荐直接使用。

### 初始化

```powershell
git clone --recurse-submodules https://github.com/SenkjM/Webdav_Media_Manager.git
cd Webdav_Media_Manager
# 已克隆过的话补子模块
git submodule update --init --recursive

$env:FLUTTER_ROOT = 'D:\flutter'
pwsh -File tool\flutter-pub-get.ps1
```

### 构建

```powershell
# 1) 编 Rust 核心（默认 arm64-v8a；加 -Abi arm64-v8a,x86_64 两个都编）
pwsh -File tool\build-rust.ps1 -Ffmpeg

# 2) 编 APK（flavor 可并用：prod / dev / sandbox / autodev）
flutter build apk --debug --flavor dev --target-platform android-arm64
# 产物：build\app\outputs\flutter-apk\app-dev-debug.apk
```

`-Ffmpeg` 打开进程内 FFmpeg（投屏转码 / 硬解）；不带它构建的是不含 FFmpeg 功能的 stub 版本，用于快速联调。Rust 侧直接改代码后可单独 `cd rust/wdmm-core; cargo check -p wdmm-ffi --features ffmpeg`。

### 门禁

```powershell
# Dart 静态分析与单测（lib/ 与 test/）
pwsh -File tool\flutter-sandbox.ps1 Analyze
pwsh -File tool\flutter-sandbox.ps1 Test
pwsh -File tool\flutter-sandbox.ps1 GenL10n    # 改 l10n 后

# Rust 侧（在子模块内执行，工具链由 rust-toolchain.toml 固定）
cd rust\wdmm-core
cargo test --workspace
cargo clippy --all-targets -- -D warnings
```

需要进程内 FFmpeg 的 crate（`wdmm-ffmpeg` / `wdmm-proxy` / `wdmm-ffi`）要用宿主 FFmpeg 9.0.2 的共享库并打开对应 feature（见 `rust/wdmm-core/AGENTS.md`）。

### 端到端（真机）

`tool/e2e.ps1` 是一套真机 harness：测试配置从 `.tmp/e2e/local.json`（gitignored）读取，也可用 `E2E_*` 环境变量覆盖；测试跑在 **autodev** flavor 上，不卸载、不清数据。

```powershell
pwsh -File tool\e2e.ps1 -Suite webdav     # 单个套件
pwsh -File tool\e2e.ps1 -Suite sync
pwsh -File tool\e2e.ps1 -Suite backup
pwsh -File tool\e2e.ps1 -Suite all        # 只读探针合集
```

套件：`boot` / `webdav` / `cast` / `castplay` / `music` / `cue` / `cbz` / `queue` / `scrape` / `maintenance` / `sync` / `backup` / `crypt` / `ui_regressions` / `ui` / `all`。失败时会把 logcat 与 uiautomator dump 落到 `.tmp/e2e/<timestamp>/`。

### CI

| Workflow | 用途 |
|---|---|
| `verify.yml` | 每次 push / PR：Dart analyze + test、Rust clippy + test、ABI / NDK 检查、OpenAPI 冒烟 |
| `testbuild.yml` | 完整 Android 构建检查（arm64，未签名） |
| `pre-release-build.yml` | `main` 上的预发布：无合法标签时开 Issue 提醒 |
| `release-build.yml` | 合法且递增的 `vX.Y.Z` tag 触发，签名发布 APK / AAB |
| `pages.yml` | 发布项目主页 |
| `build-ffmpeg-android.yml` | 构建 FFmpeg n9.0.2 Android 共享库（arm64-v8a / x86_64），供 `wdmm-ffmpeg` 链接 |

## 发布

- 正式版：`vX.Y.Z` tag（三段 0–99，严格递增），tag 提交必须在 `origin/main` 历史上；版本号与 versionCode 由 `.github/scripts/version-gate.sh` 校验。
- 预发布：`vX.Y.Z-<versionCode>` 形式，由 `main` 构建。
- 发布工作流会先做 check job（tag 合法性），再 checkout 对应提交（含子模块）、构建 Rust 核心、打包并上传 Release。
- 发布构建的三个已修问题：build job 未检出子模块、FFmpeg 链接目录用了相对路径（`cd` 后失效）、发布构建安装 libmpv 导致无头环境 `flutter test` 挂起。现在测试步骤与 build job 都有限时。

## 文档

> 用 Agent 接手本项目时，先让它读 `AGENTS.md` 与 `docs/ARCHITECTURE.md`，能少走很多弯路。

| 文件 | 内容 |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 分层、crate 职责、数据流、启动序列与约束（表内的 schema / crate 明细是快照，以代码为准） |
| [`AGENTS.md`](AGENTS.md) | 仓库工程约定：服务边界、驱动扩展、构建 / 测试 / CI、分支与提交规范 |
| [`CLAUDE.md`](CLAUDE.md) | 一次性完成、不留兼容垫片的默认工作方式 |
| [`rust/wdmm-core/AGENTS.md`](rust/wdmm-core/AGENTS.md) | Rust 工作区约定（子模块内） |

## 路线图

> 仅规划，未排期。

| 优先级 | 方向 | 说明 |
|---|---|---|
| 高 | WebDAV 管理增强 | 属性查看、批量操作、回收站与覆盖冲突体验；云盘上传暂不开放。 |
| 高 | 国产 ROM 媒体体验 | 继续收集 ColorOS / 一加等 ROM 的媒体通知与后台保活反馈并优化。 |
| 中 | 视频播放体验 | 缓冲进度条第二层、空闲自动隐藏控件、手势引导。 |
| 中 | 同步体验 | 冲突可视化，打磨分片整理与审计体验；多目标同步方向待评估。 |
| 中 | 启动与低端机体验 | 继续优化启动耗时与资源占用。 |
| 低 | 音乐输出后端 | 评估 AudioTrack / AAudio 等可选输出后端。 |
| 低 | 无障碍与多语言 | 补无障碍语义、字号适配与更多语言。 |
| 低 | iOS / 桌面端 | Rust 分层已留出空间，作为远期评估方向；当前 Android-first。 |

## 作者与协作者

这个项目几乎全部由 AI Agent 与自动化工具写成：需求由人提，代码、排查、文档、发版脚本由 Agent 完成，人负责使用、挑毛病、决定方向。大致分工：

### SenkjM

创意与需求框架，以及全部产品判断——包括每一次「这个不对，重做」。

### DeepSeek

早期负责「把名字、格式和链路捋顺」：应用改名 Webdav Media Manager、包名收进 `com.senkjm.media_manager`、备份后缀 `.wdmm`、二进制魔数换成 `WDMM…` 头，以及同步 / 备份 / 下载通知和 CI 预发布、正式发版脚本。2026 年 10–11 月又完成了业务层整体迁入 Rust（驱动、存储、同步、转码、代理、OpenAPI 统一到 `wdmm-ffi`）、Dart 执行层拆除，以及 v0.4.0 的发布链路修复。做法很朴素：先读代码与真机日志找证据，再改，改完跑 analyze / test 并装机验证。

### Claude

协作者，参与媒体通知与后台播放这条线的攻关与代码审查，也参与了早期几轮实现与整理。

### Grok Bot

早期实现者，音乐库、网络库、下载队列、视频播放等主体功能出自它手。

## 为什么开源

1. **对开源社区的信仰。** 这套东西几乎每一层都是别人开源出来的：Flutter、Dart、media_kit / mpv、audio_service、flutter_local_notifications……用的时候没掏钱，能还一点是一点。
2. **实在付不起继续跑 Agent 的钱了。** 与其让它躺在硬盘里长毛，不如放出来，谁想接着折腾就接着折腾。
3. **我觉得这玩意确实有用。** 拿网盘或 NAS 当音乐库、先下载到本地再播放、手机上离线听，这套流程我自己每天都在用。

## 许可

[GNU Affero General Public License v3.0](./LICENSE)

可以使用、修改与分发。若发布修改版，或通过网络提供基于本软件的服务，须按 AGPL-3.0 公开对应源代码。
