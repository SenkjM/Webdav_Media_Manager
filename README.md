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
- **标签读取**：下载完成后用 `audio_metadata_reader` 读取 title / artist / album / 封面 / 时长，并写入本地音乐库
- **本地音乐库**：仅索引「至少缓存过一次」的曲目；可按 **专辑 / 作者 / 音乐名** 浏览；身份键为 `(webdav_account_id + remote_path)`
- **元数据持久化**：库记录与 100×100 封面缩略图独立于音频缓存；清空或过期清理音频缓存**不会**删除库与封面；同一账号+路径再次下载会刷新标签与封面
- **本地播放**：仅用本地文件路径播放（`just_audio` + `just_audio_background` 媒体通知）
- **缓存清理**：可按 1 天或 1 周自动清理**音频缓存文件**；正在播放或下载中的文件受保护
- **WebDAV 管理**：长按可重命名 / 删除；可新建文件夹；权限不足（401/403）时弹出错误对话框

### 导航

侧边栏（Drawer）：音乐库、网络库、下载队列、设置、关于 / AGPL。

## 技术要点

| 模块 | 方案 |
|------|------|
| 库 / 账号持久化 | `sqflite`（`music_library.db`：accounts + tracks） |
| 下载队列 | `sqflite`（`download_queue.db`） |
| 标签 | `audio_metadata_reader` |
| 封面缩放 | `image` → 100×100 JPEG，存于应用文档 `covers/` |
| 凭证 | `flutter_secure_storage` |
| WebDAV | `webdav_client` |
| 媒体通知 / 后台播放 | `just_audio_background`（底层 `audio_service`） |
| 通知权限（Android 13+） | `permission_handler`（`POST_NOTIFICATIONS`） |

## 状态

**WIP（开发中）**。核心流程已实现，仍在完善与打磨。

### UI

界面参考 **Poweramp** 观感 / **Salt Player** 信息架构（非仿冒皮肤；无商标素材）。默认深色近黑底、琥珀/橙强调色、大封面 Now Playing 与底部迷你播放条。

## 许可

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）** 授权。

完整文本见仓库根目录 [LICENSE](./LICENSE)。

简要说明：你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，必须按 AGPL-3.0 公开对应完整源代码。详情以 LICENSE 原文为准。



## 权限与媒体通知

- **Android 13+**：运行时请求 `POST_NOTIFICATIONS`。首次开始播放时自动请求；也可在 **设置 → 媒体通知** 中手动开启 / 跳转系统设置。
- **媒体播放通知**：通过 `just_audio_background` 在播放（及暂停保持会话）时显示系统媒体样式通知（标题 / 艺术家 / 封面；播放/暂停）。需声明 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`WAKE_LOCK` 等，并注册 `AudioService` 前台服务（`mediaPlayback`）。
- 真机验证：通知样式与锁屏控件需在真实 Android 设备上确认；模拟器上权限与 FGS 行为可能不完整。

## 分支策略

| 分支 | 用途 |
|------|------|
| `main` | 稳定主干 |
| `beta` | 预发布线；**GitHub Pre-release 只从 beta 构建发布** |
| `dev` | 实验线，给助手试新功能 / 不稳定改动 |

日常：在 `dev` 试新鲜玩意 → 成熟后合入 `beta` 打 Pre-release → 再合入 `main`。

## CI：自动构建并发布 Pre-release

工作流：`.github/workflows/android-build.yml`

**触发条件（全部由 Actions 自动执行）：**

| 触发 | 行为 |
|------|------|
| 推送到 `beta` | 分析、测试、打 APK，并更新 GitHub **Pre-release** |
| 推送到 `main` / `dev` | 分析、测试、打 APK（**不**发 Pre-release） |
| 每天定时（约北京时间 00:00） | 检查 **beta**：相对上次 `prerelease` 有新提交才发布；无变动跳过 |
| 手动 `workflow_dispatch`（选 `beta`） | 强制从 beta 构建并更新 Pre-release |
| Pull Request | 只做分析 / 测试 / 构建产物，**不**发 Release |

**产物：**

- Actions Artifacts：`app-release-apk`（及可选 `app-release-aab`）
- GitHub Pre-release 标签：`prerelease`（持续覆盖更新，附 APK）

说明：

- **私有仓库**需在 Settings → Actions 启用工作流；发布 Pre-release 使用默认 `GITHUB_TOKEN`（`contents: write`）。
- CI APK 为默认签名，仅适合内测；正式分发请自行配置 keystore（不要把密钥提交进仓库）。
