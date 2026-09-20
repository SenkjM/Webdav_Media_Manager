# WebDAV 音乐播放器

基于 **Flutter** 的 **Android** WebDAV 音乐客户端。

仓库：[https://github.com/SenkjM/WEBDAV-music-player](https://github.com/SenkjM/WEBDAV-music-player)

## 作者与致谢

- **实现**：Grok Bot（基于需求完成工程搭建、核心功能与 CI）
- **创意与需求框架**：SenkjM

本仓库代码由 Grok Bot 实现；SenkjM 提出产品思路与约束（WebDAV 先缓存再播放、下载队列、缓存策略、本地音乐库、多网盘等）。

## 这是什么

在 WebDAV 上浏览音乐目录，把文件下载到本地缓存后再播放。**不做网络流式播放**。

### 主要能力

- **网络库（多 WebDAV）**：可添加 / 编辑 / 删除多个服务器账号（URL、用户名、密码经安全存储）；在网络库中切换当前服务器；浏览时只显示条目名称（不铺满远程完整路径）
- **下载队列**：后台异步排队下载，支持取消 / 重试 / 清除已完成；长按文件夹可**递归下载整个目录**中的音频
- **标签读取**：下载完成后用 `audio_metadata_reader` 读取 title / artist / album / track / disc / 封面 / 时长，并写入本地音乐库
- **本地音乐库**：仅索引「至少缓存过一次」的曲目；可按 **专辑 / 作者 / 音乐名** 浏览；支持按 **名称** 或 **专辑曲序（碟号/曲号）** 排序；身份键为 `(webdav_account_id + remote_path)`
- **元数据持久化**：库记录与 100×100 封面缩略图独立于音频缓存；清空或过期清理音频缓存**不会**删除库与封面；同一账号+路径再次下载会刷新标签与封面
- **本地播放**：仅用本地文件路径播放（`just_audio` + `audio_service` 媒体通知 / 系统媒体控制）
- **当前播放列表**：正在播放页 / 迷你条可打开**临时队列**（不自动同步歌单）；歌单页可「从当前播放列表创建」保存后再同步
- **媒体通知**：`audio_service` 使用应用内补丁（Android 14+ `FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK` + 通道 IMPORTANCE_DEFAULT）；小图标为单色 `drawable/ic_stat_music_white`
- **缓存清理**：可按 1 天或 1 周自动清理**音频缓存文件**；正在播放或下载中的文件受保护
- **WebDAV 管理**：长按可重命名 / 删除；可新建文件夹；权限不足（401/403）时弹出错误对话框
- **歌单**：本地独立数据库（`playlists.db`）创建 / 编辑 / 删除歌单，按 `(accountId + remotePath)` 添加曲目；音频缓存清理**不会**删除歌单。可选同步到 WebDAV（默认 `/Playlists/`）为 **M3U8**（含 `#EXT-X-WMP-*` 扩展）；本地修改后上传，启动/切换账号时拉取，按 `updatedAt` **最后写入胜出**合并
- **按站点 WebDAV 备份 / 恢复**：默认按 WebDAV 账号（`accountId` + 站点 URL）分别备份到 `/WebDAVMusicPlayer/backup/<accountDir>/backup-….wmpbak`（并写 latest）。含该站凭证、该站曲库、相关歌单与封面；恢复写回对应账号，不会把站点 A 凭证合并进站点 B。可选「全部账号」备份。建议口令 AES-256-GCM（`WMPB1`）。不含音频缓存与下载队列
- **歌曲库同步**：设置中「同步歌曲库」对所选站点双向同步歌曲索引 JSON、封面缩略图与歌单（不同步音频文件）；身份键仍为 `accountId + remotePath`

### 导航

侧边栏（Drawer）：音乐库、歌单、网络库、下载队列、设置、关于 / AGPL。

## 技术要点

| 模块 | 方案 |
|------|------|
| 库 / 账号持久化 | `sqflite`（`music_library.db`：accounts + tracks） |
| 下载队列 | `sqflite`（`download_queue.db`） |
| 标签 | `audio_metadata_reader` |
| 封面缩放 | `image` → 100×100 JPEG，存于应用文档 `covers/` |
| 凭证 | `flutter_secure_storage` |
| WebDAV | `webdav_client` |
| 媒体通知 / 后台播放 | `audio_service` + `just_audio`（`MusicAudioHandler`） |
| 通知权限（Android 13+） | `permission_handler`（`POST_NOTIFICATIONS`） |

## 状态

**WIP（开发中）**。核心流程已实现，仍在完善与打磨。

### UI

界面以**浅色系**为主（近白 / 浅灰底、深色文字、青绿强调色），参考过 **Poweramp** 信息密度与 **Salt Player** 信息架构（非仿冒皮肤；无商标素材）。大封面 Now Playing 与底部迷你播放条。

## 许可

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）** 授权。

完整文本见仓库根目录 [LICENSE](./LICENSE)。

简要说明：你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，必须按 AGPL-3.0 公开对应完整源代码。详情以 LICENSE 原文为准。



## 权限与媒体通知

- **Android 13+**：运行时请求 `POST_NOTIFICATIONS`（首次播放 / 设置页）。通知权限开启后，媒体通知才能显示。
- **媒体播放通知**：通过 `audio_service` 的 `MusicAudioHandler` 在播放时启动 `mediaPlayback` 前台服务，并发布 `MediaItem` + `PlaybackState`，使通知栏 / 锁屏 / 系统媒体控制中心显示 MediaStyle 控件（播放/暂停，有队列时上一首/下一首）。通知小图标使用 `drawable/ic_stat_music`（不可用自适应 launcher 图标）。
- 需声明 `WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`，并注册 `AudioService` / `MediaButtonReceiver`；`MainActivity` 继承 `AudioServiceActivity`。
- 真机验证：通知样式与锁屏控件需在真实 Android 设备上确认；模拟器上权限与 FGS 行为可能不完整。

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
- **UI**：抽屉「歌单」；音乐库曲目长按「添加到歌单」

## WebDAV 备份（按站点）

- **默认范围**：单个 WebDAV 账号/站点（`accountId` + base URL）
- **路径**：`/WebDAVMusicPlayer/backup/<accountId前缀_站点名>/backup-<UTC时间戳>.wmpbak`，同目录另写 `webdav_music_backup.wmpbak`（latest）。根路径可在设置中改
- **包含（按站点）**：该站 `accounts.json`（含密码）、`tracks.json`（仅该 `accountId`）、相关 `playlists.json`（条目带 accountId）、`covers/`、`settings.json`
- **可选**：全部账号备份（`full-backup-….wmpbak`）仍可用，但非默认
- **不含**：`music_cache/` 音频、下载队列
- **加密**：推荐口令；魔数 `WMPB1` + PBKDF2 + AES-256-GCM
- **恢复**：按站点写回匹配账号（或重建该挂载）；校验 accountId/URL，避免把站点 A 凭证写入站点 B

## 歌曲库同步

- **入口**：设置 →「同步歌曲库」
- **内容**：所选站点的 `library_index.json`（曲目元数据）+ `covers/` 缩略图 + 歌单 M3U8（复用现有歌单同步）
- **策略**：按 `lastTagReadAt` 最后写入胜出合并；不同步音频缓存文件
- **路径**：默认 `/WebDAVMusicPlayer/library/<accountId>/`
- **身份**：始终 `accountId + remotePath`

## CI：自动构建并发布 Pre-release

**自动构建只在 `beta` 上跑**（`main` / `dev` 的 push 不触发）。正式 release 等 beta 测完后再合入 `main` 并打版本号。

工作流：`.github/workflows/android-build.yml`

**触发条件（全部由 Actions 自动执行）：**

| 触发 | 行为 |
|------|------|
| 推送到 `beta` | 分析、测试、打 APK，并更新 GitHub **Pre-release** |
| 推送到 `main` / `dev` | **不**触发 Actions 自动构建 |
| 每天定时（约北京时间 00:00） | 检查 **beta**：相对上次 `prerelease` 有新提交才发布；无变动跳过 |
| 手动 `workflow_dispatch`（选 `beta`） | 强制从 beta 构建并更新 Pre-release |

**产物：**

- Actions Artifacts：`app-release-apk`（及可选 `app-release-aab`）
- GitHub Pre-release 标签：`prerelease`（持续覆盖更新，附 APK）

说明：

- **私有仓库**需在 Settings → Actions 启用工作流；发布 Pre-release 使用默认 `GITHUB_TOKEN`（`contents: write`）。
- CI APK 为默认签名，仅适合内测；正式分发请自行配置 keystore（不要把密钥提交进仓库）。
- 每次构建写入递增 `versionCode`（`1000+run_number`）与带短 hash 的 `versionName`，Pre-release 正文同步显示，便于覆盖安装。
