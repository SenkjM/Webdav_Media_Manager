# 101 — Round 5 Handoff & Round 6/7 Cutover Checklist

> Status: Round 5 landed in `WDMM-core` (serial queue, storage schema v2, library
> FFI/OpenAPI, drivers Range). This doc is the actionable checklist to reach
> **full Android feature parity via Rust core + FFI**.
>
> Author: Claude Code (Grok Bot supervision) — 2026-10-22
>
> **Round 6 (2026-10-22):** sqflite import FFI, Dart library wrappers + dual-read probe,
> CtFile mkdir/rename/remove, Baidu+123Pan list/get, SerialPump Dart coexistence stub,
> Desktop NativeMethods extended. Still open: flip Dart DB to FFI, remaining drivers
> (aliyundrive/open115/terabox/netease), full queue cutover, device OpenAPI polish, manga.
>
> **Round 7 (2026-10-22):** Aliyun Drive + 115 OpenAPI drivers (list/get + mock HTTP
> tests); `wdmm_queue_enqueue` FFI export + `RustQueueBridge.enqueue` wired; OpenAPI
> settings UI (debug-only, bind/token/enable); `RustCoreService.queueEnqueue` public
> method. Terabox/Netease remain stubs. See `docs/102-ROUND7-STATUS.md`.
>
> **Round 9 (2026-10-23):** Library write cutover path wired (`kRustLibraryWriteEnabled`,
> default false, dual-write probe); open115 mkdir/rename/remove with mock tests; Rust
> queue live panel in TasksScreen (gated by `kRustQueueEnabled`); proxy FFI Dart stubs
> (`RustProxyBridge`, `kRustProxyEnabled`, default false) + Developer / Rust Proxy
> settings note. Terabox stub; netease excluded. See `docs/104-ROUND9-STATUS.md`.

---

## What landed in Round 5 (WDMM-core)

| Area | What | Where |
|------|------|-------|
| Queue | `SerialPump` — single-worker FIFO, concurrency fixed at 1, mirrors Dart `_pump`. No concurrent download workers. Tests assert ≤1 Active task. | `crates/wdmm-queue/src/lib.rs` |
| Storage | Schema **v2**: `artists`, `albums`, extended `tracks` (album_id/artist_id/duration_ms/genre/track_number/disc_number/year/mime_type), manga stub tables. Migrations one-shot additive (`IF NOT EXISTS`). | `crates/wdmm-storage/src/lib.rs` |
| Storage CRUD | `upsert_track/get_track/list_tracks/search_tracks/delete_track`; artists + albums CRUD. | same |
| Models | `LibraryTrack` extended; new `LibraryAlbum`, `LibraryArtist`. | `crates/wdmm-core/src/models.rs` |
| FFI | `wdmm_library_init`, `wdmm_track_upsert/get/list/search/delete` (JSON in/out, `FfiString` ownership). Global library DB singleton. | `crates/wdmm-ffi/src/lib.rs` |
| Drivers | `CloudDriver::get_content_range(start, end)` (resumable Range download). WebDAV implements via `Range:` header; default impl falls back to full fetch + slice. | `crates/wdmm-drivers/src/{driver,webdav}.rs` |
| OpenAPI | `/v1/library/tracks` (list, `?q=` search, get, upsert, delete) + `/v1/playlists` CRUD + `/v1/playlists/:id/entries`. Behind existing token auth. | `crates/wdmm-openapi/src/lib.rs` |
| Docs | Phase 2/3/4 status updated honestly. | `docs/100-RUST-CORE-SPLIT.md` |

All `cargo check` + `cargo test` green before push (see REPORT).

---

## Round 6 — cutover checklist (to full Android parity)

### A. DB cutover: sqflite → rusqlite (one-shot, no dual-write)

Goal: delete `music_library_database_impl.dart`; all library DB ops go through FFI.

- [x] **Write the one-shot import script.** On first run of the Rust core on a device that has an existing `music_library.db` (sqflite):
      1. Open the old sqflite file read-only.
      2. Read all rows from the old tables (tracks, playlists, playlist_entries, accounts, …).
      3. Map columns → v2 schema (fill new v2 columns with defaults/NULL where the old DB lacks them).
      4. Insert into `wdmm-storage` rusqlite inside a single transaction.
      5. Atomically rename/swap so a crash mid-import is not destructive (write to a temp DB, then `rename`).
      6. Set a KV flag `sqflite_imported = 1` so it never re-runs.
      Expose via FFI: `wdmm_library_import_from_sqflite(old_path) -> FfiString` (JSON summary: rows imported per table).
- [x] **Dual-read probe (optional, pre-flip).** Before deleting Dart DB code, run both sqflite and rusqlite side-by-side and **log counts** (`tracks_sqflite`, `tracks_rusqlite`) on app start. Acceptable per brief; surfaces row-count drift before the flip. Do **not** dual-write.
- [x] **Flip Dart calls to FFI.** `RustLibraryService` (Round 8) gates `refresh()` and `search()` behind `kRustLibraryReadEnabled` (default false). Write paths carry `TODO(cutover)` markers. Full flip pending device validation.
- [ ] **Delete `music_library_database_impl.dart`** once the FFI path is green on a real device with an imported library. (Round 9)
- [ ] **Verify**: library list, search, upsert, delete, playlist CRUD all work against rusqlite; counts match pre-import.

### B. Dart FFI wrappers for new library CRUD

- [x] Extend `RustCoreService` (or a new `RustLibraryProbe`) in Android with Dart wrappers for: `wdmm_library_init`, `wdmm_track_upsert`, `wdmm_track_get`, `wdmm_track_list`, `wdmm_track_search`, `wdmm_track_delete`.
- [x] JSON encode/decode on the Dart side (the FFI takes/returns JSON `FfiString`). Do **not** delete the Dart DB yet (coexistence / dual-read probe only).
- [x] Smoke test: insert a track via FFI, read it back, search it, delete it.

### C. Cloud drivers — port the six stubs

Each against its official OpenAPI, user-supplied OAuth/credentials only, no embedded keys:

- [x] `baidu_netdisk` — Baidu NetDisk OpenAPI (list/get; write TODO)
- [x] `aliyundrive` — Aliyun Drive OpenAPI list/get + **mkdir/rename/remove** (Round 8) with mock HTTP tests
- [x] `open115` — 115 OpenAPI list/get + mock HTTP tests + **mkdir/rename/remove** (Round 9) with mock HTTP tests
- [ ] `terabox` — Terabox
- [ ] `netease_music` — NetEase Cloud Music (excluded from public release per constraints §9)
- [x] `123_open` — 123 Pan OpenAPI (list/get; write TODO)
- [x] CtFile write ops: `mkdir` (`POST /{ns}/folder/create`), `rename` (same-dir → rename_file/rename_folder; cross-dir → move+rename), `remove` (`POST /{ns}/file/delete`).

Pattern to follow: `webdav.rs` / `ctfile.rs` (throttle, retry, id-prefix dual strategy, no secrets). Add unit tests with mock HTTP (see `webdav.rs` mock-server tests).

- [ ] Delete Dart driver files once each FFI wrapper is tested green.

### D. Queue — wire `SerialPump` to the download path

- [x] Android download flow enqueues a `QueueTask` (RustQueueBridge coexistence stub) and lets `SerialPump` drive it (one at a time). Confirm UI progress events flow from `QueueEvent::Progress`.
- [x] **Queue enqueue wired** (Round 7). `RustQueueBridge.pollStatus()` wired to Settings → Developer / Rust Queue panel (Round 8, debug-only) **and** to TasksScreen live panel (Round 9, shown when `kRustQueueEnabled=true`). `kRustQueueEnabled` remains `false`.
- [ ] Confirm concurrency is 1 end-to-end (no parallel downloads) — matches Dart `_pump`. **Needs on-device validation** (flag still off by default).

### E. OpenAPI (optional toggle) — verify on device

- [x] Settings toggle "Enable OpenAPI Server"; show bind mode + token. **Debug-only** UI in `settings_screen.dart` → `OpenApiSettingsSection` (Round 7).
- [x] `/v1/library/tracks` and `/v1/playlists` routes implemented + unit tests (Round 8). Needs on-device verification of bearer-token flow.

### F. Manga (stretch — after music parity)

- [ ] Expand `manga_series` / `manga_chapters` from schema stubs to full CRUD + FFI + OpenAPI surface.

---

## Acceptance for "full Android parity"

1. Library: all CRUD + search via FFI against rusqlite; sqflite deleted; import script ran once on upgrade.
2. Drivers: WebDAV + CtFile + the six ports all production; Dart drivers deleted.
3. Queue: serial (concurrency=1), drives downloads.
4. Sync / DLNA / crypto vault: already landed Round 4 — verify on device.
5. OpenAPI: optional, token-authed, library + playlist routes live.
6. `cargo check` + `cargo test` green; Android `flutter test` + integration smoke green.

---

## Risks / notes

- **No secrets, no crates.io** (constraints §5). Drivers use official APIs only; OAuth keys user-supplied.
- **Serial queue is a product requirement** — do not reintroduce a concurrency knob.
- **One-shot DB cutover** — no dual-write window; the import script is the only bridge.
- Schema is v2 and additive; future column adds bump the version and use `IF NOT EXISTS` / `ALTER TABLE ADD COLUMN` with defaults.
