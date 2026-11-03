# Webdav Media Manager — Agent Instructions

## Repository role

Webdav Media Manager is the Android (Flutter) UI layer for WDMM. It owns screens, widgets, blocs,
and platform adapters (SAF, MediaStore, notifications, foreground service, playback). Business
logic — cloud drivers, DB, sync, crypto, DLNA, and the local proxy — lives in the WDMM-core Rust
crate compiled into `libwdmm_ffi.so` and reached via Dart FFI (`rust_core_service.dart`).

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

- Service methods translate `DioException` / `WdmmVfsException` into user-readable strings. Screens must propagate or display errors through the established pattern (`AppSnack.show`, `_error` setState). A silent `catch (_) {}` is only acceptable for cleanup paths (temp file deletion, cover cache miss); annotate with a comment.

**Adding a new cloud driver.**

One new file (`lib/services/wdmm_vfs/<name>_driver.dart`) + one line in `lib/services/wdmm_vfs/driver_registry.dart`. The public layer (`WebDavService`, `CloudDriveService`) must not change.

## Cloud file ops: WDMM-VFS is the single authority

All in-app cloud file operations go through **`WdmmVfs`** — the unified driver trait in `wdmm-core` (product name **WDMM-VFS**; formerly `CloudDriver`). This *is* the "virtual file layer" in product language; there is no second trait alongside it.

- Sync, backup, browse, and any other file I/O that already belongs on drivers must call `WdmmVfs` methods (`list` / `mkdir` / `remove` / `put_content` / `get_content`). Do not reach past it into a raw `WebDavClient` / `Dio`.
- **Do not** introduce a `VirtualFs`, `ObjectFs`, or `RemoteStore`-as-public-VFS layer that duplicates `WdmmVfs`. A private shim that only renames `WdmmVfs` is deleted/inlined; engines take `Arc<dyn WdmmVfs>` directly.
- Account-scoped driver factory lives only at the FFI/outer edge: `account_id` → `DriverRegistry::create_driver` → `WdmmVfs`. Sync FFI takes `account_id + remote_dir (+ with_covers)`, never `url/user/pass`.
- Unsupported put/get on a driver returns a driver error — do not implement sync per driver, and do **not** silently fall back to a WebDAV-only / Dart-store path. A missing put/get must fail loudly.
- Wrapper drivers (Crypt) expose `LocalStream` (MustProxy), never a plaintext `raw_url`. Content-delivery kinds stay labeled on `CloudFileItem` / driver `get`.

This is a clean one-shot codebase: no feature flags, no dual-write/dual-read, no soft fallback to a Dart store "so mid-steps work".

## HLS / DLNA cast path

`wdmm_proxy_register_hls(device_id, input_url, preset_id)` is the only entry point for HLS transcoding. It looks up the `TranscodePreset` from the DB, starts an in-process libav job (wdmm-ffmpeg), and returns `{token, playlist_url}`. Do **not** spawn an external `ffmpeg` process or call `Process.start`/`Process.run` for transcoding.

Preset CRUD is via `wdmm_transcode_presets_json` / `wdmm_transcode_preset_save` / `wdmm_transcode_preset_delete` FFI calls. The 5 built-in presets (`passthrough`, `dlna-compat`, `balanced`, `high`, `audio-only`) are seeded at DB schema v11 init; do not hard-code preset parameters in Dart.

## OpenAPI token

`wdmm_openapi_start(port)` resolves the bearer token automatically (reads `<db_dir>/api-token` file, falls back to KV, otherwise mints a new UUID and persists both). The token file is mode 0600. Do **not** read the file or construct the token in Dart; call `wdmm_openapi_port()` and use the Dart bindings in `rust_core_service.dart`.

## Media bytes

All media byte delivery must go through `POST /v1/media/link` (OpenAPI). Dart **must not** splice upstream `raw_url` or `raw_headers` from a `CloudFileItem` directly into a player URL or DLNA `SetAVTransportURI` call. The media-link API returns a stable proxy URL or a signed direct URL; use that.

## Build, test, lint

```sh
# Dart static analysis (lib/ only — test/ has pre-existing errors)
flutter analyze lib/

# Dart unit tests
dart test

# Rust compile check
cargo check -p wdmm-ffi -p wdmm-storage -p wdmm-openapi -p wdmm-proxy -p wdmm-ffmpeg

# Rust unit tests
cargo test -p wdmm-storage && cargo test -p wdmm-openapi
```

The Rust toolchain is pinned in `rust/wdmm-core/rust-toolchain.toml` (channel + both Android
targets) and mirrored by the `dtolnay/rust-toolchain@<version>` refs in `.github/workflows/*.yml`.
Bump both in the same commit. The pin exists because `verify.yml` runs
`cargo clippy --all-targets -- -D warnings`: when the local toolchain lagged behind CI's newest
stable, clippy gained lints that only CI saw, so the guard failed on every push while passing
locally. Always run the clippy command above with the pinned toolchain before pushing.

On Windows, use the checked-in PowerShell wrappers in `tool/` (`flutter-sandbox.ps1` for
analyze/test/gen-l10n, `flutter-pub-get.ps1` for dependency resolution). Set `FLUTTER_ROOT` to your
Flutter SDK root (defaults to `D:\flutter`); `pub get` redirects `PUB_CACHE` into a workspace-local
`.pub-cache/`. This repo's tracked lockfile is pinned to `https://pub.dev` — do not set
`PUB_HOSTED_URL`.

## Branch and commit conventions

- Active branch: `refactor/rust-core`
- Commit prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Do not commit to `main` directly. No force-push. No triggering CI via API.
- Submodule bump rule: when `rust/wdmm-core` changes, pin to the target Core SHA in the same
  commit that updates Dart callers.

## CI workflows

| Workflow | Purpose |
|---|---|
| `verify.yml` | Static analysis + unit tests on push/PR |
| `testbuild.yml` | Full Android build check (unsigned) |
| `pre-release-build.yml` | Signed pre-release build; triggers on valid pre-release tag; opens an issue if none |
| `release-build.yml` | Signed release build; triggers on an incremental `vX.Y.Z` tag or manual dispatch |
| `pages.yml` | Publishes the project page |
| `build-ffmpeg-android.yml` | Builds FFmpeg Android binaries (arm64-v8a) consumed by `wdmm-ffmpeg` |

## Where docs live

- Architecture layer diagram, crate responsibilities, DB schema, startup sequence, active
  constraints: `docs/ARCHITECTURE.md`
- Per-feature docs: `docs/` (indexed at `docs/00-INDEX.md`)
- Agent instructions: this file (`AGENTS.md`)

## One-shot coding rule (mandatory)

Finish the new authority completely, then delete the old path and wire callers. No feature flags,
no dual-write/dual-read, no soft fallbacks, no dead code kept for "mid-step usability".

See `docs/ARCHITECTURE.md` for the full layer diagram, crate responsibilities, DB schema, startup
sequence, and active constraints.
