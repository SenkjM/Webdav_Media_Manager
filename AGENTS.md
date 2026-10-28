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

## Architecture: module reuse principles

**Services are the single source of truth.** Before writing new logic, check whether an existing service already covers it:

- Network I/O: `WebDavService` (WebDAV + cloud accounts) or `CloudDriveService` (driver routing). Do not construct `Dio`, `WebDavClient`, or `http.Client` instances outside these two services.
- Download/upload queue: `DownloadQueueService` / `TaskQueueService`. Call `enqueueUpload` / `enqueueDownload`; the queue owns retry, progress notification, and cancellation.
- Settings: `SettingsService`. Never persist preferences with raw `SharedPreferences` calls outside this service.
- Account access: `AccountsService`. Never filter or iterate `WebDavAccount` lists in screens.
- Capability checks: `WebDavService.can(accountId, cap)`. Never branch on `providerType` strings to gate UI.

**All authenticated HTTP must go through the service layer.**

- Use `WebDavService.downloadToFile`, `writeBytes`, `writeFromFile`, `resolveStreamSource`, etc. These handle token refresh, error mapping, retry, and `rawHeaders` injection.
- Never call a raw `WebDavClient` or `Dio` instance from a screen or non-service file.
- Cloud driver direct-link headers come from `resolveStreamSource` -> `WebDavStreamSource`. Do not reconstruct the URL or strip headers at the call site.

**Error handling.**

- Service methods translate `DioException` / `CloudDriverException` into user-readable strings. Screens must propagate or display errors through the established pattern (`AppSnack.show`, `_error` setState). A silent `catch (_) {}` is only acceptable for cleanup paths (temp file deletion, cover cache miss); annotate with a comment.

**Adding a new cloud driver.**

One new file (`lib/services/cloud_drivers/<name>_driver.dart`) + one line in `lib/services/driver_registry.dart`. The public layer (`WebDavService`, `CloudDriveService`) must not change.

## Cloud file ops: CloudDriver is the single authority

All in-app cloud file operations go through **`CloudDriver`** — the unified driver trait in `wdmm-core`. This *is* the "virtual file layer" in product language; there is no second trait alongside it.

- Sync, backup, browse, and any other file I/O that already belongs on drivers must call `CloudDriver` methods (`list` / `mkdir` / `remove` / `put_content` / `get_content`). Do not reach past it into a raw `WebDavClient` / `Dio`.
- **Do not** introduce a `VirtualFs`, `ObjectFs`, or `RemoteStore`-as-public-VFS layer that duplicates `CloudDriver`. A private shim that only renames `CloudDriver` is deleted/inlined; engines take `Arc<dyn CloudDriver>` directly.
- Account-scoped driver factory lives only at the FFI/outer edge: `account_id` → `DriverRegistry::create_driver` → `CloudDriver`. Sync FFI takes `account_id + remote_dir (+ with_covers)`, never `url/user/pass`.
- Unsupported put/get on a driver returns a driver error — do not implement sync per driver, and do **not** silently fall back to a WebDAV-only / Dart-store path. A missing put/get must fail loudly.
- Wrapper drivers (Crypt) expose `LocalStream` (MustProxy), never a plaintext `raw_url`. Content-delivery kinds stay labeled on `CloudFileItem` / driver `get`.

This is a clean one-shot codebase: no feature flags, no dual-write/dual-read, no soft fallback to a Dart store "so mid-steps still work". See `CLAUDE.md`.
