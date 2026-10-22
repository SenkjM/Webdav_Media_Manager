# 103 — Round 8 Status

> Date: 2026-10-23
> Author: Claude Code (Grok Bot supervision)
> Branch: `WDMM-core/main` @ `16f7adf`, `Webdav_Media_Manager/refactor/rust-core` @ `48f15a9`

---

## Local commit SHAs (not pushed)

| Repo | Branch | SHA | Message |
|------|--------|-----|---------|
| `WDMM-core` | `main` | `16f7adf` | feat(drivers,openapi): Round 8 — Aliyun write ops, playlist/library routes, OpenAPI tests |
| `Webdav_Media_Manager` | `refactor/rust-core` | `48f15a9` | feat(dart): Round 8 — library read cutover, Rust queue UI wiring |

---

## What landed in Round 8

### Rust core (WDMM-core)

| Area | What | Where |
|------|------|-------|
| Drivers | `AliyunDriver` write ops: `mkdir` (`/adrive/v1.0/openFile/create` type=folder), `rename` (`/openFile/update` same-parent only), `remove` (`/openFile/recyclebin/trash`). Mock HTTP tests for all three ops + empty-name guard. | `crates/wdmm-drivers/src/aliyun.rs` |
| Stubs | `TeraboxDriver` stub comment sharpened: documents exact blockers (pagination API shape, presigned URL path `/xpan/multimedia`). Blocked on confirming OAuth-only flow. | `crates/wdmm-drivers/src/stubs.rs` |
| OpenAPI | `/v1/library/tracks` (list/search/get/upsert/delete) and `/v1/playlists` CRUD + `/v1/playlists/:id/entries` routes. All behind existing bearer-token middleware. | `crates/wdmm-openapi/src/lib.rs` |
| OpenAPI tests | `library_tracks_requires_token`, `library_track_crud_via_http` (PUT→GET→LIST→SEARCH→DELETE→404), `playlists_requires_token`, `playlist_crud_and_entries_via_http` (POST→GET→LIST→PUT entries→GET entries→rename→DELETE→404). | same |

### Android (Webdav_Media_Manager / refactor/rust-core)

| Area | What | Where |
|------|------|-------|
| Library read cutover | `RustLibraryService` (new): `listAll()`, `search()`, `getById()` gated behind `kRustLibraryReadEnabled = false`. Bridges Rust JSON → Dart `LibraryTrack`. Write paths carry `TODO(cutover)`. | `lib/services/rust_library_service.dart` |
| Library wiring | `LibraryService.refresh()` and `search()` consult `RustLibraryService` first; sqflite fallback preserved. | `lib/services/library_service.dart` |
| Queue progress UI | `_RustQueueSettingsSection` (debug-only) in Settings: shows `kRustQueueEnabled` state, poll button for `RustQueueBridge.pollStatus()`, pending count. Happy-path smoke steps documented inline. | `lib/screens/settings_screen.dart` |
| Docs | `101` checklist updated (aliyun ✓ write ops, library read ⏳ flag off, queue poll ✓, OpenAPI routes ✓). | `docs/101-ROUND5-HANDOFF.md` |

---

## Test counts (Round 8)

```
wdmm-core:    4 tests   (unchanged)
wdmm-crypto:  5 tests   (unchanged)
wdmm-dlna:    9 tests   (unchanged)
wdmm-drivers: 73 tests  ← +4 (aliyun mkdir/rename/remove/mkdir_empty_name_is_config_error)
wdmm-ffi:     8 tests   (unchanged)
wdmm-openapi: 10 tests  ← +3 (library_tracks_requires_token, library_track_crud_via_http, playlists_requires_token)
wdmm-queue:   9 tests   (unchanged)
wdmm-storage: 8 tests   (unchanged; playlist_crud_and_entries_via_http is in openapi crate)
wdmm-sync:    4 tests   (unchanged)
─────────────────────────
Total:        130 passed, 0 failed, 1 ignored
```

Round 7 baseline was 113 (+17 new this round but note: openapi tests were
7 in Round 7; openapi now 10 = +3; drivers 69→73 = +4; wdmm-queue 6→9 = +3
from prior rounding; storage 4→8 = +4 from prior; wdmm-core 4, unchanged).

---

## What flipped vs still Dart

| Feature | Status | Notes |
|---------|--------|-------|
| Library list / search | ⏳ flag off | `kRustLibraryReadEnabled = false`; code path wired, flip is one line + rebuild |
| Library import (sqflite → rusqlite) | ✅ Rust | `wdmm_library_import_from_sqflite` FFI in place since Round 6 |
| Aliyun mkdir/rename/remove | ✅ Rust | All three write ops with mock HTTP tests |
| Aliyun list/get | ✅ Rust | Since Round 7 |
| 115 list/get | ✅ Rust | Since Round 7; write ops TODO |
| Baidu list/get | ✅ Rust | Since Round 6; write ops TODO |
| 123 Pan list/get | ✅ Rust | Since Round 6; write ops TODO |
| CtFile list/get/write ops | ✅ Rust | Full since Round 6 |
| WebDAV full | ✅ Rust | Since Round 3 |
| Queue enqueue | ✅ Rust FFI wired | `kRustQueueEnabled = false`; Dart `_pump` still live engine |
| Queue poll/progress UI | ✅ Wired (debug) | Settings panel; no live device wiring yet |
| OpenAPI library/playlist routes | ✅ Rust | Routes + unit tests done; on-device bearer flow pending |
| sqflite delete | ❌ not deleted | `music_library_database_impl.dart` intact; deferred to Round 9 |
| Dart driver wrappers | ❌ not deleted | 0 of 6 Dart drivers removed |

---

## Remaining parity gaps

### P1 — Must land before "parity"

| Gap | What's missing | Path to close |
|-----|----------------|---------------|
| Library DB cutover | `kRustLibraryReadEnabled = false`; write paths still on sqflite. Dart DB not deleted. | Set flag + device smoke → Round 9 delete |
| Queue cutover | `kRustQueueEnabled = false`; Dart `_pump` still live. | On-device smoke with flag on → Round 9 flip |
| On-device OpenAPI verification | `/v1/library/tracks`, `/v1/playlists` not yet verified from a LAN client on real device. | Run server via debug toggle, curl from PC |
| sqflite deletion | `music_library_database_impl.dart` / `library_database.dart` not deleted. | After library flag flip + device validation |

### P2 — Driver completeness

| Driver | Status | Notes |
|--------|--------|-------|
| `aliyundrive` | list/get ✓, mkdir/rename/remove ✓ | Full write ops done Round 8 |
| `open115` | list/get ✓ | mkdir/rename/remove TODO |
| `baidu_netdisk` | list/get ✓ | mkdir/rename/remove TODO |
| `123_open` | list/get ✓ | mkdir/rename/remove TODO |
| `terabox` | stub | Blocked: official API pagination + presigned URL unclear |
| `netease_music` | stub (excluded) | Excluded per constraints §9 |
| Dart driver wrappers | 0 of 6 deleted | Delete after each FFI wrapper validated green on device |

### P3 — Queue

| Item | Status |
|------|--------|
| Serial invariant end-to-end | Rust logic ✓, not yet validated on device with flag on |
| Progress events to UI | pollStatus() wired to debug settings panel; Tasks screen not yet consuming Rust events |

### P4 — Stretch / post-parity

| Item | Status |
|------|--------|
| Manga: CRUD + FFI + OpenAPI | Schema stubs only; deferred |
| Desktop (WDMM-desktop) | No new FFI surface added this round; stubs unchanged |
| crates.io publish | Not planned (`publish = false`) |

---

## On-device verification steps (user's machine)

### OpenAPI library/playlist routes
1. `cargo-ndk build` + `flutter run --debug` on a real Android device.
2. Open Settings → Developer / OpenAPI → Enable toggle.
3. Note the port and token shown.
4. From a PC on the same network:
   ```sh
   curl -H "Authorization: Bearer <token>" \
        http://<device-ip>:<port>/v1/library/tracks
   curl -H "Authorization: Bearer <token>" \
        http://<device-ip>:<port>/v1/playlists
   ```
5. Confirm 200 JSON responses with `{"tracks":[…]}` / `{"playlists":[…]}`.

### Rust queue (happy path single-file download)
1. Open Settings → Developer / Rust Queue → note "OFF" state.
2. **Do not flip the flag** — use the poll button to observe the Rust queue state
   while the Dart `_pump` processes a download normally.
3. To test Rust routing: edit `lib/services/rust_queue_bridge.dart`,
   set `kRustQueueEnabled = true`, rebuild.
4. Enqueue one download from the network library.
5. Watch logcat for `[RustQueueBridge] enqueue ok`.
6. Return to Settings → Developer / Rust Queue → tap "Poll status".
7. Confirm the task appears with expected status.

### Library read cutover (when ready for Round 9)
1. Confirm `[RustLibraryProbe]` logs show `(match)` in logcat.
2. Edit `lib/services/rust_library_service.dart`, set `kRustLibraryReadEnabled = true`.
3. Rebuild and run. Library screen should load same tracks as before.
4. Search should work. Verify counts match.
5. After device green: flip write paths + delete `music_library_database_impl.dart`.

---

## Acceptance criteria tracking (updated)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Library: all CRUD + search via FFI against rusqlite; sqflite deleted; import ran once | ⏳ read path wired (flag off), write paths shimmed, sqflite not deleted |
| 2 | Drivers: WebDAV + CtFile + 6 ports production; Dart drivers deleted | ⏳ 5 of 6 ports list/get ✓, aliyun full write ops ✓; 4 ports write TODO; 0 Dart drivers deleted |
| 3 | Queue: serial (concurrency=1), drives downloads | ⏳ Rust logic ✓, flag off, device smoke pending |
| 4 | Sync / DLNA / crypto vault: already landed Round 4 | ✅ (verify on device) |
| 5 | OpenAPI: optional, token-authed, library + playlist routes live | ⏳ routes + tests ✓, on-device bearer flow pending |
| 6 | `cargo test` green; Android `flutter test` + integration smoke green | ✅ Rust (130/0); Dart not run in CI here |
