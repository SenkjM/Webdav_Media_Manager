# Webdav Media Manager — Agent Instructions

## Flutter in the DSH workspace sandbox

`flutter` resolves to `D:\flutter\bin\flutter.bat`. Its standard startup path takes a shared-cache lock under `D:\flutter\bin\cache`, may run a Flutter version check (`git fetch --tags`), and may implicitly verify dependencies. Those steps are outside this repository and can stall or require broader permissions in a `workspace-write` DSH session.

For routine verification, do **not** invoke `flutter analyze`, `flutter test`, or `flutter gen-l10n` directly. Use the checked-in wrappers instead:

```powershell
pwsh -File tool\flutter-sandbox.ps1 Analyze
pwsh -File tool\flutter-sandbox.ps1 Test
pwsh -File tool\flutter-sandbox.ps1 Test test\download_queue_ordering_test.dart
pwsh -File tool\flutter-sandbox.ps1 GenL10n
```

`tool\flutter-sandbox.ps1 Analyze` uses `dart analyze --fatal-infos --fatal-warnings` directly, so it does not invoke Flutter's universal-artifact update and must not request access to update `D:\flutter\bin\cache`. However, the DSH `workspace-write` sandbox may deny Dart's analysis-server child process with `ProcessException: 拒绝访问`. This cannot be fixed with command-line flags. In that case, stop, report that static analysis was not run, and do **not** automatically request or assume an elevation. Run the wrapper only after the user explicitly switches the session to full access.

`Test` and `GenL10n` use Flutter's cached Dart snapshot with `FLUTTER_ALREADY_LOCKED=true`, `--no-version-check`, and `--no-pub`. They are valid only when dependencies and the required Flutter SDK artifacts are already available. If one reports an absent or stale SDK artifact such as `libimobiledevice.stamp`, stop and tell the user that the SDK cache requires explicit initialization with full access; do **not** automatically request or assume an elevation for routine verification.

When `pubspec.yaml`, `pubspec.lock`, or `pubspec_overrides.yaml` changes, initialize dependencies first:

```powershell
pwsh -File tool\flutter-pub-get.ps1
```

That script redirects `PUB_CACHE` to `.pub-cache/` in this workspace. It intentionally uses the official launcher because `pub get` is stateful. Do not set `PUB_HOSTED_URL`; this repository's tracked lockfile is pinned to `https://pub.dev`.

Use a normal `flutter` command only when the user has explicitly provided full access or when a wrapper reports a missing cached prerequisite. Always report the exact wrapper and outcome used for verification.
