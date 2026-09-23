# 99 · 开发中文档

只记录**正在开发**的功能的原始语义：需求原话、取舍、临时决定、还没定型的实现。
用法与收口规则见 [00-INDEX.md](00-INDEX.md) 的「完整文档与开发中文档」。

- 开发新功能前**先读本文件**，再读每一条链接到的完整文档。
- 开发期间，完整文档里对应的位置只留占位，不写半成品语义。
- 开发完成后：删掉这里的条目，把语义按完整文档的写法补进对应功能块，并去掉占位。

## 1. 安装包分包与压缩存放（进行中）

**状态**：代码已改并推 `main`，还没跑过一次真实构建，**未验证**。

**为什么**：v0.1.0 的通用 APK 有 101.3 MiB，其中 99.7 MiB 是三个 ABI 各带一份原生库——`libmpv.so` 38.1 MiB、`libflutter.so` 31.8 MiB、`libapp.so` 28.4 MiB——非原生部分只有 2.7 MiB。

**要什么行为**：

- `--split-per-abi` 出三个单 ABI 包：`arm64-v8a`、`armeabi-v7a`、`x86_64`。
- 额外再出一个**去掉 x86_64** 的合并包（`android-arm,android-arm64`），给不确定自己 ABI 的人。
- 原生库**压缩存放**（`useLegacyPackaging = true`）：下载更小，代价是安装时要解压。
- `.aab` 照旧产出，给 Play 用。

**取舍**：压缩存放会让安装占用变大、安装变慢。若日后确认 Play 分发不需要它，再单独评估是否只对 APK 生效。

**影响面**：[09-MISC.md](09-MISC.md) 的「构建与发布」——那里现在只留占位。

## 2. flavor 与本地 dev 环境（进行中）

**状态**：代码已改。`flutter run --flavor dev` 已在本机 + 真机（PJZ110 / Android 16）上跑通：装成 `com.senkjm.media_manager.dev`，`versionName=1.0.0-dev`，能与正式包并存。**CI 里那几处产物路径改动没在真实 CI 上跑过，未验证。**

**需求原话**：配置 flavor，设置一个本地测试的 dev 环境，使用不同的包名，包名在后面加上 `.dev`。

**要什么行为**：

- `env` 一个维度，两个 flavor：`prod`（applicationId 不变）与 `dev`（`applicationIdSuffix = ".dev"`）。
- 两个包能并存在同一台手机上，各自持有独立数据目录。
- 桌面 / 最近任务里能区分：`android:label` 改用 `manifestPlaceholders["appName"]`，dev 叫 `Webdav Media Manager Dev`。
- 本地 release 与 CI 都改成显式 `--flavor prod`。

**取舍**：

- **不动 `namespace`**：`MainActivity.kt` 的包路径，以及 `com.senkjm.media_manager/app`、通知 channel id 这类字符串都是应用内部标识，与 applicationId 无关，改了只是白白搬家。
- 代价：存在 flavor 之后，不带 flavor 的 `flutter build apk --release` 失效。
- CI 的产物名字随 flavor 变成 `app-prod-*.apk` / `bundle/prodRelease/app-prod-release.aab`，两份 workflow 的收集步骤已同步改。

**影响面**：[09-MISC.md](09-MISC.md) 的「构建与发布」——本地命令与 flavor 表已写进那一节；待 CI 跑过一次后收口。
