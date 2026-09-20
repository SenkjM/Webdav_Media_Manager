# WebDAV 音乐播放器

基于 **Flutter** 的 **Android** WebDAV 音乐客户端。

仓库：[https://github.com/SenkjM/WEBDAV-music-player](https://github.com/SenkjM/WEBDAV-music-player)


## 作者与致谢

- **实现**：Grok Bot（基于需求完成工程搭建、核心功能与 CI）
- **创意与需求框架**：SenkjM

本仓库代码由 Grok Bot 实现；SenkjM 提出产品思路与约束（WebDAV 先缓存再播放、下载队列、缓存策略、目录式曲库等）。

## 这是什么

在 WebDAV 上浏览音乐目录，把文件下载到本地缓存后再播放。**不做网络流式播放**。

主要能力：

- **目录浏览**：按 WebDAV 目录树导航；未下载曲目只显示文件名/路径，不扫描标签
- **下载队列**：后台异步排队下载，支持取消 / 重试 / 清除已完成，队列可持久化
- **本地播放**：仅用本地文件路径播放（`just_audio`）
- **缓存清理**：可按 1 天或 1 周自动清理；正在播放或下载中的文件受保护

## 状态

**WIP（开发中）**。核心流程已实现，仍在完善与打磨。

## 许可

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）** 授权。

完整文本见仓库根目录 [LICENSE](./LICENSE)。

简要说明：你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，必须按 AGPL-3.0 公开对应完整源代码。详情以 LICENSE 原文为准。

## CI：自动构建并发布 Pre-release

工作流：`.github/workflows/android-build.yml`

**触发条件（全部由 Actions 自动执行）：**

| 触发 | 行为 |
|------|------|
| 推送到 `main` / `master` | 分析、测试、打 APK，并更新 GitHub **Pre-release** |
| 每天定时（约北京时间 00:00） | **仅当自上次 `prerelease` 标签以来有新提交** 时才构建并更新 Pre-release；无变动则跳过发布 |
| 手动 `workflow_dispatch` | 强制构建并更新 Pre-release |
| Pull Request | 只做分析 / 测试 / 构建产物，**不**发 Release |

**产物：**

- Actions Artifacts：`app-release-apk`（及可选 `app-release-aab`）
- GitHub Pre-release 标签：`prerelease`（持续覆盖更新，附 APK）

说明：

- **私有仓库**需在 Settings → Actions 启用工作流；发布 Pre-release 使用默认 `GITHUB_TOKEN`（`contents: write`）。
- CI APK 为默认签名，仅适合内测；正式分发请自行配置 keystore（不要把密钥提交进仓库）。
