# WebDAV 音乐播放器

基于 **Flutter** 的 **Android** WebDAV 音乐客户端。

仓库：[https://github.com/SenkjM/WEBDAV-music-player](https://github.com/SenkjM/WEBDAV-music-player)

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

## CI：用 GitHub Actions 构建 APK

工作流文件：`.github/workflows/android-build.yml`

- 触发：推送到 `main`/`master`、Pull Request、以及手动 `workflow_dispatch`
- 步骤：`pub get` → `analyze` → `test` → `flutter build apk --release`（并尝试构建 AAB）
- 产物：在 Actions 运行页的 **Artifacts** 中下载 `app-release-apk`（以及若成功的 `app-release-aab`）

说明：

- **私有仓库**需在仓库 Settings → Actions 中启用 GitHub Actions，否则工作流不会跑。
- CI 产出的 release APK 默认使用 Flutter/Android 调试密钥签名，仅适合冒烟与内测安装；上架或正式分发需另行配置 keystore 密钥（勿把密钥硬编码进仓库）。
