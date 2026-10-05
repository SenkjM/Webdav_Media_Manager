---
name: WebDAV Media Manager
description: 在改 SenkjM/Webdav_Media_Manager 时使用：分支、提交、构建、本地化、数据库哨兵、流式预读和主题边界。
---

# WebDAV Media Manager

改 [SenkjM/Webdav_Media_Manager](https://github.com/SenkjM/Webdav_Media_Manager) 时用这份约束。它是给后续 agent 的操作说明，不是变更记录。与源码冲突时以源码和测试为准，然后改文档。先读 [00-INDEX.md](../00-INDEX.md)，再读 [99-IN-PROGRESS.md](../99-IN-PROGRESS.md)，然后读 99 链到的功能文档。未完成的需求、取舍和影响面写进 99；临时交接写 [97-AGENT-HANDOFF.md](../97-AGENT-HANDOFF.md)。不要另开计划文档。

## 分支、提交、发版

- 主干只有 `main`。功能从 `main` 开分支，worktree 放在仓库根的 `worktree/<name>`：`git worktree add -b <branch> worktree/<name> main`。一个功能一个 worktree，不复用。进 worktree 后单独 `flutter pub get`。不要跨 worktree 复制 `.dart_tool/`、`build/`。同一个 worktree 里会写这两处的 Flutter 命令串行跑。
- 提交前缀只用 `feat:` / `fix:` / `docs:` / `ci:` / `deps:`。纯文档或 CI 必须用 `docs:` / `ci:`，这样 `.github/scripts/commit-list.sh` 不会把它们写进面向用户的发版列表。带代码的提交不要用 `docs:`。
- 不要推 `main`，不要 `gh workflow run`，不要为了看构建给 workflow 加 `on: push`，不要打预发布或移动标签，除非用户当次明确说了。密钥、`key.properties`、keystore、token、`.env` 不打印、不提交。
- `pubspec.yaml` 的 `version: 1.0.0+1` 不是发布版本。正式版版本名等于 git 标签。`versionCode` = 主×1e8 + 次×1e6 + 修订×1e4 + 序号（正式版序号 0）。`v0.2.3` → `2030000`。公式在 `.github/scripts/version-gate.sh` 的 `version_code`。当前正式版标签是 `v0.2.3`（指向引入 sandbox `abiFilters` 例外的 `9ec1dc7`）。发版说明见 [09-MISC.md](../09-MISC.md)。

## 构建

- 有 product flavor 之后，所有 Android 构建必须带 `--flavor`。`flutter analyze` / `flutter test` 不用。维度是 `env`，三个 flavor：`prod`、`dev`、`sandbox`。见 `android/app/build.gradle.kts`。
- 不要把 flavor 命名为 `test`，也不要以 `test` 开头。AGP 禁止这种 ProductFlavor 名字。旁路包的 flavor 名是 `sandbox`，`applicationIdSuffix` 才是 `.test`，包名 `com.senkjm.media_manager.test`。`prod` 是 `com.senkjm.media_manager`，`dev` 是 `com.senkjm.media_manager.dev`。
- `ndk.abiFilters` 只在 **没有** `-Psplit-per-abi=true` 时写在 `sandbox` 上，值为 `arm64-v8a`。`prod` / `dev` 不设。`flutter build apk --split-per-abi` 会给每个 variant 打开 `splits.abi`；AGP 只要任一 variant（包括这次没在编的 sandbox）还留着 `abiFilters` 就失败。所以分包构建不能看到这份过滤。修法在 `9ec1dc7`，说明在 [09](../09-MISC.md) 的 flavor 小节。09 开头仍有两句把 Testbuild 写成 `test` flavor，以 gradle 和同文对照表的 `sandbox` 为准，不要按那两句改名。
- Testbuild 是手动 workflow，命令是 `flutter build apk --release --flavor sandbox --target-platform android-arm64`，带 `--build-name=<最新正式版标签>-<7 位短哈希>`、`--build-number=<正式版 versionCode + run_number>`。sandbox flavor 用固定测试 keystore（`ANDROID_SANDBOX_*` secrets），不用正式 `ANDROID_KEY*` / `ANDROID_KEYSTORE_*`，也不再用会随 runner 变化的 debug 签名。不要擅自跑它。

## 不要顺手改的界面

用户在一加 13 国行 ColorOS 16 上验收。仓库只写了 ColorOS / 一加（[05 §7](../05-AUDIO-PLAYBACK.md)、[09](../09-MISC.md)），没有把这一台机型写进代码。不要加机型判断。

除非用户点名，不要改这些的样式或行为：本地播放页、流式音乐页的布局、视频手势区、进度条怎么拖、背景模糊（`BackdropFilter` / `ImageFilter.blur`，产品里没有流体玻璃）、`lib/utils/cover_image.dart`、`CacheService`、下载队列。缺封面占位只按下面「主题」那条走，不要重画封面图本身。

## 本地化

- 界面文案在 `lib/l10n/app_zh.arb`、`app_zh_TW.arb`、`app_en.arb`。没有 `app_zh_CN.arb`。`l10n.yaml` 里 `use-escaping: true`，`preferred-supported-locales` 是 `zh`、`zh_TW`、`en`，模板是 `app_zh.arb`。改 ARB 后跑 `flutter gen-l10n`。生成文件在 `lib/l10n/generated/`。
- 运行时简体是 `Locale('zh', 'CN')`，不是裸 `zh`。`MaterialApp.localeListResolutionCallback` 用 `resolveAppLocaleList`（`lib/models/app_locale.dart`，接到 `lib/main.dart`）。`zh_CN`、`zh_Hans`、裸 `zh` 都落到 `Locale('zh', 'CN')`；`zh_TW` 或 script `Hant` 保持 `Locale('zh', 'TW')`；`en` 保持英语。列表对不上时回落简体。
- 生成方法的占位符参数顺序是名字母序，不是句子里出现的顺序。例如 `videoSubtitleSizeCurrent(max, min, size)`（`lib/l10n/generated/app_localizations_zh.dart`）。调用时按生成签名传，不要按中文语序排。
- 语言菜单里的语言名是自称，写在 `AppLocalePreference.nativeName`：简体中文、繁體中文、English。不进 ARB。「跟随系统」仍用 `l10n.languageSystem`。
- 直接写在 Dart / Kotlin 里的中文不会随语言变，三种界面都仍是这句中文。新的用户可见句子放进三份 ARB。不要为了某一个 locale 去改这句字面量。`debugPrint`、探测串、以及有意留下的原生回退文案保持中文。
- 下拉和弹出菜单圆角是 10。`DropdownButton` / `DropdownButtonFormField` 要自己传 `borderRadius: BorderRadius.circular(10)`；不传时 Flutter 用直角。`AppTheme` 的 `popupMenuTheme` 也是 10（`lib/theme/app_theme.dart`）。不要换成 `DropdownMenu`。

## 数据库哨兵

稳定键，不要就地翻译成当前语言：

| 键 | 常量 | 旧字面量 |
|----|------|----------|
| `__wdmm_default_server__` | `kDefaultServerName`（`lib/models/account_sentinels.dart`） | `默认服务器` |
| `__wdmm_unnamed_playlist__` | `kUnnamedPlaylistName`（`lib/models/playlist_sentinels.dart`） | `未命名` |

显示走映射（例如 `localizedAccountName`），存储值保持键。

一次性重写在 `lib/services/legacy_sentinel_migration.dart` 的 `migrateLegacySentinelsOnce`。文件头写明这是给正式版 0.2.2 的兼容，**0.2.4 必须删掉整个路径**；0.2.4 之后旧库不再兼容。源码没有按版本号开关。当前 `main`（标签 `v0.2.3`）每次启动仍会跑。99 里「只在 0.2.2 运行」与源码不符，以文件头和 `AppState.init` 为准。

启动顺序（`lib/providers/app_state.dart` 的 `init`）：先打开曲库、歌单、下载三个库，让 `onCreate` / `onUpgrade` 跑完，再做哨兵重写。重写不能对着还没建出来的表。歌单库 `lib/services/playlist_store.dart` 现在是 version 1，只有 `onCreate`，没有 `onUpgrade`。下载库的 `onUpgrade` 会丢掉并重建 `download_tasks`（队列可以丢，见 `lib/services/download_store.dart`）。

不要查询 `tracks.cache_group_id`。`tracks` 建表就没有这一列（`lib/services/library_database.dart`）。普通曲目的组成员在 `cache_groups`。`cue_albums`、`cue_slices`、`download_tasks` 才有 `cache_group_id`。迁移注释写了这一点。

不要重写：用户自己的歌单名 `新歌单`、用户流派标签 `未分类`、默认名 `服务器`。空流派已经是别的稳定键，和用户写下的 `未分类` 不是一回事。同样不要动迁移头列出的 `未知艺术家`、`未知专辑`、`新文件夹`、`系统相册`、`下载目录`、字幕存储值 `默认`。

## 流式音乐

语义在 [05](../05-AUDIO-PLAYBACK.md) 与 [99 §1](../99-IN-PROGRESS.md)。实现以这些文件为准：`lib/services/audio_stream_engine.dart`、`lib/services/stream_cover_reader.dart`、`lib/services/stream_window.dart`、`lib/services/prefetch_cache.dart`、`lib/screens/music_stream_screen.dart`。

- 内嵌封面只发 HTTP Range，用文件头魔数判断格式，再用 `audio_metadata_reader` 取图。后缀不算数。魔数：`ID3` 或 MP3 帧同步、`fLaC`、偏移 4 的 `ftyp`、`OggS`、`RIFF`+`WAVE`。不是 206 就放弃，不要把整首音频当封面下下来。优先 `PictureType.coverFront`，否则第一张。裸 AAC 当没有内嵌图。
- 同目录封面只在设置打开时找。默认关（`SettingsService` 的 `audioStreamSidecarCover`，默认 `false`）。默认可编辑名单 `cover, folder, front, album`。只认 jpg、jpeg、png、webp。只下选中的那一张，不进子目录。
- 封面顺序：曲库里已有的封面文件 → 预载缓存里已经完整的封面 → Range 内嵌图 → 开关打开时的同目录图 → 占位。
- 预载是一条正在播放的流，加一条预载线程。窗口里的封面先于邻居音频。不要为了预载取消正在播放的那条流。邻居先向前（上一首）再向后，不绕圈。设置键 `audio_stream_prefetch_backward` / `audio_stream_prefetch_forward`，默认都是 1，范围 0–5。
- 预载文件在应用缓存目录的 `prefetch_cache`。进程内保留；滑出窗口不删，页面 dispose 不删。下次启动、任何播放器打开缓存文件之前清一次（`lib/main.dart` 里 `PrefetchCache.wipe()`，在 `MediaKit.ensureInitialized()` 之前）。不完整文件先写 `.part` 再改名。
- 进入流式页的首帧调用 `AudioPlayerService.pauseForVideo()`：暂停本地播放，队列留着。离开时 `dispose` 调 `VideoPlaybackService.stop()`，也就是 `exitVideoMode()`。它把模式交回本地，`playing` 仍是 false，**不会自动接着播**。若本地队列还有曲目，通知栏会重新挂上那首暂停的歌。这是 99 §1 记下的粗糙处，不要顺手改 `exitVideoMode`。
- 流式路径不要偷偷把曲子放进下载队列。

## 主题

Material Design 3，经典色调，不是 Expressive。`AppTheme._build` 用 `ColorScheme.fromSeed`，`DynamicSchemeVariant.fidelity`（`lib/theme/app_theme.dart`）。`useMaterial3: true` 不是开关。

浅色在 `fromSeed` 之后用 `_liftLightScheme` 抬高：表面色调上移，强调色至少到色调 68，主/次/第三容器至少到 90。白字对比不够时 `on*` 改成同色相色调 20。深色不抬。不要把浅色变体换成 `tonalSpot` 来「修」偏暗，那抬不高 `primary`。

种子色键 `theme_seed_argb`，默认 `0xFF2EC4B6`。三态键 `theme_mode`：`light` / `dark` / `system`。没存过的安装仍是浅色。

曲库缺封面占位只改颜色：`CoverArt._placeholder`（`lib/widgets/cover_art.dart`）底色 `ColorScheme.surfaceContainerHigh`，图标 `onSurfaceVariant`。`PlayerCoverArt`、迷你条、正在播放队列在没有封面时共用它。真实封面（`Image.file` / `Image.memory`）不跟主题变。`MusicStreamScreen._buildCover` 的占位画法、圆角、`cover_image.dart` 不要跟着改。
