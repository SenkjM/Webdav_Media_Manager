# 14 · 多语言与媒体生命周期

> 编号 14 · 总索引：[00-INDEX.md](00-INDEX.md)

## 1. 应用语言

应用支持以下语言偏好：

- 跟随系统
- 简体中文（`zh-CN`）
- 繁体中文（`zh-TW`）
- English（`en`）

用户可在设置页的语言下拉菜单中切换。偏好由 `SettingsService` 持久化，`MaterialApp.locale` 根据该值重建；选择跟随系统时使用设备 locale。语言资源位于 `lib/l10n/app_*.arb`，生成文件位于 `lib/l10n/generated/`，修改资源后运行：

```bash
flutter gen-l10n
dart format --output=none .
flutter analyze
```

新增用户可见文案必须同时补齐所有受支持语言的 ARB key；运行时本地化文本不能放在 `const` widget、`const` 列表或 `const` 输入装饰中。

## 2. 服务层错误

服务层不能直接把中文错误字符串传给 UI。结构化错误使用 `err.<name>|<detail>` 形式，由 `CloudDriverErrors.describeException` / `describe` 根据当前 `AppLocalizations` 转换为用户可见文本。原始异常详情作为参数保留，便于诊断；未知错误仍保留可读的回退文本。

## 3. Android 媒体生命周期

视频页面创建的 `VideoController` 只负责渲染绑定，不拥有共享 `Player`。共享视频播放器由 `MusicAudioHandler` 持有，页面关闭时不能直接释放该 `Player`，以保留后台播放能力。

应用关闭或 Flutter 引擎重建时，native media 资源遵循以下顺序：

1. 停止视频播放器和音频播放器，让 mpv 工作线程退出当前操作。
2. 取消播放状态、位置、错误和系统中断等订阅。
3. 关闭状态 controller。
4. 释放音频与视频 `Player`。

`MusicAudioHandler.disposePlayer()` 使用 Future 锁保证幂等。`AppState.shutdown()` 负责等待媒体释放后再释放应用服务；同步的 `ChangeNotifier.dispose()` 只触发该 shutdown，不重复释放底层 player。

修改播放器或 native media 生命周期后，优先使用完整停止并重新运行；播放器正在播放、后台播放或画中画状态下不应依赖 hot restart 一定等待 native 线程退出。

## 4. 验证记录

本次实现已验证：

- `flutter gen-l10n`：通过
- `dart format --output=none .`：通过
- `flutter analyze --no-pub`：通过，无 issues
- `flutter test --no-pub`：589 passed，1 skipped
- Android debug 构建已生成 `build/app/outputs/flutter-apk/app-dev-debug.apk`；Flutter 命令的最终产物探测提示路径不一致，但 APK 文件实际存在。

项目级 Android Gradle JVM 代理配置位于 `android/gradle.properties`，仅用于依赖下载，不要提交包含凭据的代理 URL。
