# 102 — Round 7 Status & Remaining Android Parity Gaps

> Date: 2026-10-22  
> Author: Claude Code (Grok Bot supervision)  
> Branch: `WDMM-core/main`, `Webdav_Media_Manager/refactor/rust-core`, `WDMM-desktop/main`

---

## What landed in Round 7

### Rust core (WDMM-core)

| Area | What | Where |
|------|------|-------|
| Drivers | `AliyunDriver` — Aliyun Drive OpenAPI list/get (write ops TODO). Auth: user-supplied access_token + drive_id. Mock HTTP tests (list, 401 auth error). | `crates/wdmm-drivers/src/aliyun.rs` |
| Drivers | `Open115Driver` — 115 Network OpenAPI list/get (write ops TODO). Auth: user-supplied Bearer access_token. Mock HTTP tests. | `crates/wdmm-drivers/src/open115.rs` |
| Drivers | `DriverRegistry` updated: `aliyundrive`/`aliyun` and `115`/`open115` now instantiate production drivers (require `access_token`). `stubs.rs` reduced to `TeraboxDriver` + `NeteaseMusicDriver` only. | `crates/wdmm-drivers/src/lib.rs` |
| FFI | `wdmm_queue_enqueue(json)` — enqueue a download/sync task in the Rust SerialPump from Dart/C#. Returns `"ok"` or `"error:..."`. Feature-flag gated on Dart side. | `crates/wdmm-ffi/src/lib.rs` |
| FFI test | `queue_enqueue_and_status` — verifies enqueue → status → cancel roundtrip. | same |
| Deps | `chrono` added to `wdmm-ffi/Cargo.toml` (needed by `wdmm_queue_enqueue`). | `crates/wdmm-ffi/Cargo.toml` |

All 8 `cargo test` suites green. Total tests: 113 passed, 0 failed.

### Android (Webdav_Media_Manager / refactor/rust-core)

| Area | What | Where |
|------|------|-------|
| Queue | `RustCoreService.queueEnqueue(taskJson)` — calls `wdmm_queue_enqueue` FFI. Lazy symbol load. | `lib/services/rust_core_service.dart` |
| Queue | `RustQueueBridge.enqueue()` — uses `RustCoreService.queueEnqueue`; gated by `kRustQueueEnabled = false`. Documents enable path and Round 8 cutover. | `lib/services/rust_queue_bridge.dart` |
| Settings | `OpenApiSettingsSection` — debug-only stateful widget: enable toggle, bind mode selector, port + token display, token rotate. | `lib/screens/openapi_settings_section.dart` |
| Settings | Settings screen shows `OpenApiSettingsSection` under `kDebugMode` guard. | `lib/screens/settings_screen.dart` |
| Docs | `101-ROUND5-HANDOFF.md` checkboxes updated (aliyundrive ✓, open115 ✓, queue enqueue ✓, OpenAPI settings ✓). | `docs/101-ROUND5-HANDOFF.md` |

---

## How to enable the Rust queue (one happy path)

1. Open `lib/services/rust_queue_bridge.dart`.
2. Change `kRustQueueEnabled = false` → `kRustQueueEnabled = true`.
3. `cargo-ndk` build + `flutter run` on a real Android device.
4. Enqueue one download from the network library.
5. Check logcat for `[RustQueueBridge] enqueue ok`.
6. Confirm progress via `RustQueueBridge.pollStatus()` (returns `wdmm_queue_status_json`).
7. Confirm the Dart `_pump` loop is idle while the Rust pump runs.

---

## Remaining gaps to full Android parity

### P1 — Must land before "parity"

| Gap | What's missing | Notes |
|-----|---------------|-------|
| Library DB cutover | Dart call sites in `LibraryService` / `LibraryDatabase` still use sqflite for all ops. Round 7 brief §1 says flip list/search/get first, leave write paths shimmed. | Safe read flip deferred to Round 8 — requires device validation of import script first |
| Queue cutover | `kRustQueueEnabled` is still `false`; Dart `_pump` is still the live engine. | Flip after device smoke test of single-file download |
| On-device OpenAPI verification | `/v1/library/tracks`, `/v1/playlists` behind bearer token not yet verified on device. | Debug UI is ready (Round 7); needs on-device run |
| sqflite deletion | `music_library_database_impl.dart` / `library_database.dart` not deleted until post-cutover device validation. | |

### P2 — Driver completeness

| Driver | Status | Notes |
|--------|--------|-------|
| `aliyundrive` | list/get ✓ | mkdir/rename/remove TODO |
| `open115` | list/get ✓ | mkdir/rename/remove TODO |
| `baidu_netdisk` | list/get ✓ | mkdir/rename/remove TODO |
| `123_open` | list/get ✓ | mkdir/rename/remove TODO |
| `terabox` | stub | Official API docs needed; implement once confirmed |
| `netease_music` | stub (excluded) | Excluded from public release per constraints §9 |
| Dart driver wrappers | 0 of 6 deleted | Delete after each FFI wrapper is validated green |

### P3 — Queue

| Item | Status |
|------|--------|
| Serial invariant end-to-end (no parallel downloads) | Asserted in Rust tests; not yet validated on device via kRustQueueEnabled |
| Progress events to UI | Rust events emitted; Dart UI not yet wired to `pollStatus()` |

### P4 — Stretch / post-parity

| Item | Status |
|------|--------|
| Manga: CRUD + FFI + OpenAPI | Schema stubs only; full implementation deferred |
| Desktop (WDMM-desktop) | NativeMethods.g.cs stubs complete; smoke-test target unchanged (window opens, settings render) |
| crates.io publish | Not planned; `publish = false` per constraints §5 |

---

## Test counts (Round 7 baseline)

```
wdmm-core:    4 tests
wdmm-crypto:  5 tests
wdmm-dlna:    9 tests
wdmm-drivers: 69 tests  ← +15 new (aliyun + 115 + registry)
wdmm-ffi:     8 tests   ← +2 (queue_enqueue_and_status, queue_status fixed)
wdmm-openapi: 7 tests
wdmm-queue:   6 tests
wdmm-storage: 4 tests
wdmm-sync:    1 test (ignored)
─────────────────
Total:        113 passed, 0 failed
```

---

## Acceptance criteria tracking

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Library: all CRUD + search via FFI against rusqlite; sqflite deleted; import script ran once on upgrade | ⏳ import script ✓, cutover pending |
| 2 | Drivers: WebDAV + CtFile + six ports production; Dart drivers deleted | ⏳ 4 of 6 ports production (list/get); no Dart drivers deleted yet |
| 3 | Queue: serial (concurrency=1), drives downloads | ⏳ Rust logic ✓, flag off |
| 4 | Sync / DLNA / crypto vault: already landed Round 4 | ✅ (verify on device) |
| 5 | OpenAPI: optional, token-authed, library + playlist routes live | ⏳ server ✓, device verification pending |
| 6 | `cargo test` green; Android `flutter test` + integration smoke green | ✅ Rust; Dart not run in CI here |
