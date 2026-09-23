# A05 · 构建、发布与编码约定

> **文档编号 A05** · 状态：已完成 · 模式：归档（正文只读）  
> 总索引：[INDEX.md](../INDEX.md)  
> 自原开发文档拆出：分支、环境、CI、Agents 约定、陷阱与测试入口。

勘误不得直接改正文。需要更正时新建编号文档，并在索引备注。

---

## 2. 分支与发布策略

| 分支 | 用途 |
|------|------|
| `main` | 稳定主干 |
| `beta` | 预发布线；**GitHub Pre-release 只从 beta 发布**（标签 `prerelease`） |
| `dev` | 实验线；助手默认在此试功能 / 不稳定改动 |

推荐流程：`dev` 试验 → 成熟后合入 `beta` → 验证 Pre-release → 再合入 `main`。

### CI 触发（重要）

工作流：`.github/workflows/android-build.yml`

| 事件 | 行为 |
|------|------|
| **任意分支 push** | **不**触发构建 |
| 每天定时（cron `0 16 * * *`，约北京时间 00:00） | 检视 **beta**：相对上次 `prerelease` 有新提交才构建发布；无变动跳过 |
| 手动 `workflow_dispatch` | 可构建；**仅当所选引用为 beta 时才发布 Pre-release** |

**对 agents 的硬约束：**

- **永远不要**为了「看构建结果」去改 workflow 加 `on: push`，或擅自 `gh workflow run`。
- 需要打 Pre-release 时：**先等用户确认**，再在 UI / `gh` 上对 **beta** 做 `workflow_dispatch`。
- 日常开发推送 **`origin/dev` only**；不要擅自推 `beta` / `main`，不要触发 Actions。

---

## 3. 本地环境搭建

### 依赖

- Flutter **stable**（仓库 `environment.sdk: ^3.13.4`；本机常用路径示例 `/workspace/flutter-sdk`）
- Android SDK + JDK 17（与 CI `setup-java` 一致）
- 真机或模拟器（媒体通知 / FGS 行为建议真机验证）

### 常用命令

```bash
cd WEBDAV-music-player
flutter pub get
flutter analyze
flutter test
flutter run                    # debug
flutter build apk --release    # 本地 release；签名见下文 CI/signing
```

Vendored 依赖：`audio_service` 使用 path 包 `packages/audio_service`（勿随意改回 pub.dev 版本，除非同步补丁说明）。

---

---

## 11. CI 与签名

工作流：`.github/workflows/android-build.yml`

### 编译依赖参数

| 依赖 | 参数 | 说明 |
|------|------|------|
| JDK | `17`（temurin） | 与 AGP 9.1 / Kotlin `jvmTarget 17` 一致；`flutter_local_notifications` 依赖 core library desugaring（`android/app/build.gradle.kts` 已启用） |
| Flutter | `stable` | 与 `.metadata` 记录的本机 SDK 线一致（当前 stable 线：Dart `^3.13.4`） |
| Android SDK | `platform-tools` + `platforms;android-36` + `build-tools;36.0.0` | 对应 Flutter 默认 `compileSdk/targetSdk = 36`（`android/app/build.gradle.kts` 取 `maxOf(flutter.compileSdkVersion, 35)`） |
| Linux 测试库 | `libmpv-dev`、`mpv` | media_kit 的 Linux 后端，`flutter test` 需要 |
| Gradle | `cache: gradle` | 缓存 AGP/Gradle 编译依赖（`actions/setup-java`） |

### 版本号

| 变量 | 规则 |
|------|------|
| `VERSION_NAME` | `pubspec` 版本基（如 `1.0.0`）+ `-` + `SHORT_SHA`（sha 前 7 位） |
| `VERSION_CODE` | `1000 + github.run_number`（单调递增，便于覆盖安装） |

```bash
flutter build apk --release \
  --build-name="$VERSION_NAME" \
  --build-number="$VERSION_CODE"
```

### Secrets（仓库 Settings → Secrets）

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

固定内测 keystore，避免 Actions 换机器导致签名变化。从旧 debug 包换成内测签名需 **卸载一次**。

本地可用环境变量或未提交的 `android/key.properties`（**勿提交密钥**）。

Agents：**不要**打印 / 提交任何 keystore、token、密码。

---

## 12. Agents 编码约定

**Do**

- UI 文案用 **中文**；标识符 / 路径 / API 名保持英文。
- 默认在分支 **`dev`** 上开发、提交、推送 `origin/dev`。
- 推送前 `git fetch` + `pull --rebase`（可能有并发提交）。
- 改完跑 `flutter analyze` / 相关 `flutter test`。
- 播放只走本地文件；下载走队列服务。
- CUE 解析用 `decodeCueText`；ingest 后虚拟曲才进库。
- 根返回用 `moveTaskToBack`；真正退出才 `SystemNavigator.pop`。
- 保持 AGPL-3.0；显著修改保留版权与许可头（若文件已有）。

**Don't**

- 不要做流式播放 / 在 `playTrack` 里偷偷 enqueue。
- 不要把未下载远程文件标成「排队中」。
- 不要分享 CUE 虚拟曲；不要恢复已删除的 ffmpeg CUE 导出分享。
- 不要在 `MainActivity` 引用 `com.ryanheise.audioservice.AudioService` 类（见陷阱）。
- 不要重新引入 just_audio 时代的起播静音 hack；media_kit 不需要它（见第 7 节历史背景）。
- **不要**改 CI 为 push 自动构建；**不要**未经用户确认 `workflow_dispatch`；**不要**推 beta/main 或打 Pre-release，除非用户明确要求。
- 不要提交 `key.properties`、keystore、secrets、`.env`。
- 不要发明不存在的 API；以仓库源码为准。

提交信息风格：简短英文前缀（如 `docs:` / `fix:` / `feat:`）+ 说明，参考 `git log`。

---

---

## 14. 已知陷阱与历史回归

| 问题 | 原因 / 表现 | 正确做法 |
|------|-------------|----------|
| **UTF-8 CUE ingest 失败** | 非 UTF-8 CUE 用 `readAsString` 抛错；下载成功但库无虚拟曲 | 始终 `decodeCueText(bytes)` 再 `CueSheetParser`；见 `cue_library_ingest_test` |
| **MainActivity AudioService classpath** | 在 Kotlin 中 `import AudioService` 会拉进 `MediaBrowserServiceCompat`，release 编译失败 | 继承 `AudioServiceFragmentActivity`；通知诊断用 `NotificationManager` / `MediaSessionManager`，**不要**引用 `AudioService` 类（`251e46a`） |
| **切后台后通知/播放状态消失** | `AudioServiceActivity`（普通 `FlutterActivity` 变体）只重写 `provideFlutterEngine()`，未重写 `getCachedEngineId()`/`shouldDestroyEngineWithHost()`，导致其默认值为 `true`：Activity 被系统回收/从最近任务划掉时，共享的 `FlutterEngine`（同时承载 `MusicAudioHandler`）被销毁，通知与播放状态一起消失 | `MainActivity` 改继承 `AudioServiceFragmentActivity`（正确重写全部三个方法，engine 不随 Activity 销毁） |
| **SystemNavigator.pop 停音乐** | 根返回 finish Activity → 拆掉 handler | 根返回 `moveTaskToBack`；仅抽屉「退出」才 pop（`9c9d5c5`） |
| **起播双击杂音 / 首曲无声** | 每次 play 播静音 AudioTrack；或 unmute 排在卡住的 `play()` 之后 | 禁止 `androidForceEnableMediaButtons` on play；mute 仅罩住 setAudioSource，**play 前 unmute**；`stop`/finally 清 mute（`0ed9591`, `922d3c4`） |
| **idle 拆掉媒体通知** | 只在无选中曲（`_index < 0`）时广播 `AudioProcessingState.idle` | 见 idle guard 测试 |
| **未下载显示「排队中」** | 远程浏览误用 queued 状态 | 未入队 → `TrackUiState.remote`，Chip 为空 |
| **播放器顺手下载** | 在 play 路径 enqueue | 拒绝并提示先下载（`892ff89`） |
| **清缓存误删曲库** | 把 tracks 和文件绑死 | 标签在 DB；cache 为 annex；销毁才是 wipe |
| **备份恢复后假「已缓存」** | 恢复了 annex 路径但文件未打包 | 恢复策略 uncached unless on disk |
| **schema 升级丢库** | v5 `onUpgrade` 直接 DROP | bump version 前告知用户；无自动 migration |
| **OEM 无媒体通知** | LOW 通道 / 未 typed FGS | 保留 vendor 补丁与 v4 通道；真机测 ColorOS/OnePlus |
| **通道状态查不到 / 与系统不一致** | 通道原先只由首次播放的原生 `createChannel()` 创建，设置页在播放前读到「未创建」 | 由 `notification_permission_service.dart` 经 `flutter_local_notifications` 在启动时建通道（`media_notification_channel.dart` 为唯一定义）；原生侧发现通道已存在即复用，故两侧参数必须一致（IMPORTANCE_DEFAULT、静音、不震动、无角标） |
| **Android 13+ 通知抛 `You must specify an icon resource id to build a CustomAction`** | `MediaControl.stop`（以及 ff/rewind）在 API 33+ 会被 audio_service 转成 `CustomAction`，其 builder 在图标解析为 0 时抛异常；vendor 插件自带的 `drawable/audio_service_*` 图标在该 app 的 release 构建里不可靠合并 | 媒体控制按钮改用 app 自带 `drawable/ic_media_*` 矢量图标（与 `ic_stat_music` 同源、必能解析）：见 `music_audio_handler.dart` 的 `_k*Control` 常量、`android/app/src/main/res/drawable/ic_media_*.xml` 与 `res/raw/keep.xml` |

相关提交可参考：`c235c92`（CUE ingest）、`1649677`（music_id v5 / 备份）、`0ed9591`（mute + remote chip）、`922d3c4`（unmute before play + ColorOS BUFFERING / v4）、`9c9d5c5`（返回键）、`251e46a`（MainActivity）、`ebe85b7`（禁用 push 触发 CI）。

---

## 15. 测试入口（改核心逻辑时优先跑）

```bash
flutter test test/library_data_model_test.dart
flutter test test/cue_sheet_test.dart
flutter test test/cue_library_ingest_test.dart
flutter test test/local_only_play_policy_test.dart
flutter test test/network_remote_status_test.dart
flutter test test/music_audio_handler_idle_guard_test.dart
flutter test test/music_audio_handler_volume_safety_test.dart
flutter test test/media_notification_channel_test.dart
flutter test test/cache_group_deletion_test.dart
# 或全量
flutter test
```

---

*本文随代码演进；若与实现冲突，以源码与测试为准，并请更新本文。*
