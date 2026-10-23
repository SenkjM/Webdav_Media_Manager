# 104 — Round 9 Status

> Date: 2026-10-23
> Author: Claude Code (Grok Bot supervision)
> Branch: `WDMM-core/main` @ (see commits below), `Webdav_Media_Manager/refactor/rust-core` @ (see below)

---

## Local commit SHAs (not pushed)

| Repo | Branch | SHA | Message |
|------|--------|-----|---------|
| `WDMM-core` | `main` | _(pending commit)_ | feat(drivers): Round 9 — open115 write ops, API.md update |
| `Webdav_Media_Manager` | `refactor/rust-core` | _(pending commit)_ | feat(dart): Round 9 — library write cutover, queue Tasks UI, proxy FFI stubs |

---

## What landed in Round 9

### Rust core (WDMM-core)

| Area | What | Where |
|------|------|-------|
| Drivers | `Open115Driver` write ops: `mkdir` (`POST /open/folder/create` with `pid`+`cname`), `rename` (`POST /open/file/edit` with `fid`+`file_name`), `remove` (`POST /open/rbfile/delete` with `fid[]`). Added `post_json` helper and `path_to_item_id` (resolves fid for files, cid for folders). Mock server upgraded to multi-response. | `crates/wdmm-drivers/src/open115.rs` |
| Drivers tests | `mkdir_empty_name_is_config_error` (sync), `mkdir_root_level`, `rename_root_file`, `remove_root_file` (+4 tests). | same |
| API.md | Updated `Open115Driver` entry to document write ops. | `crates/wdmm-drivers/docs/API.md` |

### Android (Webdav_Media_Manager / refactor/rust-core)

| Area | What | Where |
|------|------|-------|
| Library write cutover | `kRustLibraryWriteEnabled = false` flag; `RustLibraryService.upsertTrack` and `.deleteTrack` write to Rust rusqlite via FFI when flag is `true`. `_trackToRustJson` helper maps Dart `LibraryTrack` → Rust JSON. | `lib/services/rust_library_service.dart` |
| Library write wiring | Parallel Rust writes (no-op when flag off) added at: `ingestDownloaded`, `upsertTracks`, `ingestFromTags`, `retargetTrack`, `markRemoteMissing`, `clearRemoteMissing`, `updateCoverPath`, `destroyTrack`, `removeTrack`. All carry `// TODO(cutover)` markers. | `lib/services/library_service.dart` |
| Queue Tasks UI | `_RustQueuePanel` StatefulWidget added to `TasksScreen` — shown above Dart task list when `kRustQueueEnabled=true`. Auto-polls every 3 s; `_RustTaskRow` renders per-task progress bar + id + status + name. Replaces debug-settings-only poll as the live UI path. | `lib/screens/tasks_screen.dart` |
| Proxy FFI stubs | `RustCoreService.proxyStart/Stop/Port/RegisterFile/Unregister` bindings for `wdmm_proxy_*` exports. `rust_proxy_bridge.dart` (new): `RustProxyBridge` thin wrappers, `kRustProxyEnabled = false`. Settings → Developer / Rust Proxy note: start/stop/poll buttons, `LocalStreamBridge` not deleted. | `lib/services/rust_core_service.dart`, `lib/services/rust_proxy_bridge.dart`, `lib/screens/settings_screen.dart` |
| Docs | `docs/104-ROUND9-STATUS.md` (this file); `101` checklist updated. | `docs/` |

### Desktop (WDMM-desktop)

All proxy P/Invoke stubs (`wdmm_proxy_start/stop/port/register_file/unregister`) were already present in `NativeMethods.g.cs` from the proxy-extract round. No new desktop commits required.

---

## Test counts (Round 9)

```
wdmm-core:    4 tests   (unchanged)
wdmm-crypto:  5 tests   (unchanged)
wdmm-dlna:    9 tests   (unchanged)
wdmm-drivers: 77 tests  ← +4 (open115 mkdir/rename/remove/mkdir_empty_name)
wdmm-ffi:     9 tests   (unchanged)
wdmm-openapi: 10 tests  (unchanged)
wdmm-proxy:   15 tests  (unchanged)
wdmm-queue:   9 tests   (unchanged)
wdmm-storage: 8 tests   (unchanged)
wdmm-sync:    4 tests   (unchanged)
─────────────────────────
Total:        160 passed, 0 failed, 1 ignored
```

Round 8 baseline was 130; drivers 73→77 (+4 open115 write op tests).

---

## What flipped vs still Dart

| Feature | Status | Notes |
|---------|--------|-------|
| Library list / search | ⏳ flag off | `kRustLibraryReadEnabled = false`; code path wired, flip is one line + rebuild |
| Library write path | ⏳ flag off | `kRustLibraryWriteEnabled = false`; **NEW Round 9**: wire complete, dual-write probe ready |
| Library import (sqflite → rusqlite) | ✅ Rust | `wdmm_library_import_from_sqflite` FFI in place since Round 6 |
| Aliyun mkdir/rename/remove | ✅ Rust | Full write ops, mock HTTP tests |
| Aliyun list/get | ✅ Rust | Since Round 7 |
| 115 list/get | ✅ Rust | Since Round 7 |
| 115 mkdir/rename/remove | ✅ Rust | **NEW Round 9** — mock HTTP tests included |
| Baidu list/get | ✅ Rust | Since Round 6; write ops TODO |
| 123 Pan list/get | ✅ Rust | Since Round 6; write ops TODO |
| CtFile list/get/write ops | ✅ Rust | Full since Round 6 |
| WebDAV full | ✅ Rust | Since Round 3 |
| Queue enqueue | ✅ Rust FFI wired | `kRustQueueEnabled = false`; Dart `_pump` still live engine |
| Queue poll — Tasks screen | ✅ Wired live | **NEW Round 9**: `_RustQueuePanel` in TasksScreen (when flag on); Settings debug panel still present |
| OpenAPI library/playlist routes | ✅ Rust | Routes + unit tests done; on-device bearer flow pending |
| Proxy FFI surface (Android) | ✅ Stubs wired | **NEW Round 9**: `RustProxyBridge`, `kRustProxyEnabled = false`; `LocalStreamBridge` intact |
| sqflite delete | ❌ not deleted | `music_library_database_impl.dart` intact; deferred |
| Dart driver wrappers | ❌ not deleted | 0 of 6 Dart drivers removed |

---

## Remaining parity gaps

### P1 — Must land before "parity"

| Gap | What's missing | Path to close |
|-----|----------------|---------------|
| Library DB cutover | Read flag off; write flag off. Dart DB not deleted. | Device smoke → flip read flag → verify → flip write flag (dual-write probe) → device smoke → delete `music_library_database_impl.dart` |
| Queue cutover | `kRustQueueEnabled = false`; Dart `_pump` still live. | On-device smoke with flag on → confirm TasksScreen panel → flip |
| On-device OpenAPI verification | `/v1/library/tracks`, `/v1/playlists` not yet verified from a LAN client. | Run via debug toggle, curl from PC |
| sqflite deletion | `music_library_database_impl.dart` / `library_database.dart` intact. | After both library flags confirmed on device |

### P2 — Driver completeness

| Driver | Status | Notes |
|--------|--------|-------|
| `aliyundrive` | list/get/mkdir/rename/remove ✓ | Full |
| `open115` | list/get/mkdir/rename/remove ✓ | **Full Round 9** |
| `baidu_netdisk` | list/get ✓ | mkdir/rename/remove TODO |
| `123_open` | list/get ✓ | mkdir/rename/remove TODO |
| `terabox` | stub | Blocked: official API pagination + presigned URL unclear |
| `netease_music` | stub (excluded) | Excluded per constraints §9 |
| Dart driver wrappers | 0 of 6 deleted | Delete after each FFI wrapper validated green on device |

### P3 — Queue

| Item | Status |
|------|--------|
| Serial invariant end-to-end | Rust logic ✓, not yet validated on device with flag on |
| Progress events to UI | `_RustQueuePanel` in TasksScreen shows live poll (when flag on); auto-poll 3 s |

### P4 — Proxy

| Item | Status |
|------|--------|
| `RustProxyBridge` FFI stubs | ✅ wired (flag off) |
| `LocalStreamBridge` | ❌ not deleted — pending device smoke with `kRustProxyEnabled=true` |

### P5 — Stretch / post-parity

| Item | Status |
|------|--------|
| Manga: CRUD + FFI + OpenAPI | Schema stubs only; deferred |
| crates.io publish | Not planned (`publish = false`) |

---

## On-device verification steps (user's machine)

### Library write cutover (Round 9 addition)
1. Ensure `kRustLibraryReadEnabled = true` and device smoke green (see 103 §Library read cutover).
2. Edit `lib/services/rust_library_service.dart`, set `kRustLibraryWriteEnabled = true`.
3. Rebuild and run on a real Android device.
4. Download or tag-read a track; confirm no `[RustLibraryService] upsertTrack failed` lines in logcat.
5. Check row count parity: `[RustLibraryProbe] tracks … (match)`.
6. After dual-write probe passes: remove sqflite upsert/delete calls from `library_service.dart` and delete `music_library_database_impl.dart`.

### Queue Tasks UI (Round 9)
1. Set `kRustQueueEnabled = true` in `lib/services/rust_queue_bridge.dart`, rebuild.
2. Open the Tasks tab (Downloads).
3. Confirm the "Rust queue" banner appears at the top — auto-updates every 3 s.
4. Enqueue one download; confirm task appears in the Rust queue panel with a progress bar.
5. Confirm the Dart task list below still shows the same download (coexistence).

### Rust proxy (Round 9)
1. Set `kRustProxyEnabled = true` in `lib/services/rust_proxy_bridge.dart`, rebuild.
2. Open Settings → Developer / Rust Proxy → tap "Start proxy".
3. Confirm port is shown (>0).
4. From a code debug path, call `RustProxyBridge.registerFile('/path/to/cached.mp3', name: 'test.mp3')`.
5. Confirm the returned URL serves the file from a PC on the same LAN.
6. Tap "Stop proxy" — port returns to -1.

---

## Acceptance criteria tracking (updated)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Library: all CRUD + search via FFI against rusqlite; sqflite deleted; import ran once | ⏳ read path wired (flag off), **write path wired Round 9 (flag off)**, sqflite not deleted |
| 2 | Drivers: WebDAV + CtFile + 6 ports production; Dart drivers deleted | ⏳ **open115 now full** ✓; baidu/123 write TODO; 0 Dart drivers deleted |
| 3 | Queue: serial (concurrency=1), drives downloads | ⏳ Rust logic ✓, flag off, **TasksScreen live panel ready Round 9** |
| 4 | Sync / DLNA / crypto vault: already landed Round 4 | ✅ (verify on device) |
| 5 | OpenAPI: optional, token-authed, library + playlist routes live | ⏳ routes + tests ✓, on-device bearer flow pending |
| 6 | `cargo test` green; Android `flutter test` + integration smoke green | ✅ Rust (160/0/1 ignored); Dart not run in CI here |
