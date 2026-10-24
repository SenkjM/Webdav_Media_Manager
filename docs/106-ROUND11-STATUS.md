# Round 11 Status — Dart originals cutover (post device smoke)

## SHAs at round start

| Repo | Branch | SHA |
|------|--------|-----|
| WDMM-core | (submodule) | `d8b2217` (Round 10 submodule pin) |
| Webdav_Media_Manager | refactor/rust-core | `293bfe4` (round start) |

---

## What landed (Round 11)

### A — Library DB write cutover (`kRustLibraryWriteEnabled = true`)

All track upsert / delete write paths in `library_service.dart` are now
**Rust-only** when `kRustLibraryWriteEnabled` is `true` (which it is).
Sqflite `_db.upsertTrack()` / `_db.deleteTrack()` / `_db.deleteTracksForSource()`
calls removed from every write method:

| Method | Before | After |
|--------|--------|-------|
| `upsertTracks` | sqflite + parallel Rust | Rust-only; `StateError` on FFI fail |
| `replaceTracksForAccount` | sqflite delete-by-source + upsert | Rust delete per-id + Rust upsert |
| `ingestDownloaded` | sqflite + parallel Rust | Rust-only; `StateError` on FFI fail |
| `markRemoteMissing` | sqflite + parallel Rust | Rust-only |
| `clearRemoteMissing` | sqflite + parallel Rust | Rust-only |
| `updateCoverPath` | sqflite + parallel Rust | Rust-only |
| `retargetTrack` | sqflite delete + sqflite upsert | Rust delete + Rust upsert |
| `ingestFromTags` | sqflite + parallel Rust | Rust-only |
| `destroyTrack` (non-CUE) | sqflite delete | Rust delete; `StateError` on FFI fail |
| `removeTrack` | sqflite delete | Rust delete |

**Kept on sqflite (no Rust FFI equivalent yet):**
- Tombstones (`upsertTombstone`, `clearTombstone`, `unpushedTombstones`, …)
- Sync cursor (`saveSyncState`, `loadSyncState`, `clearSyncState`)
- CUE album / slice tables (`replaceCueAlbumTracks`, `deleteCueSlice`,
  `deleteCueAlbum`, `remainingSlicesForCue`, `upsertCueSlice`)
- Bulk-clear ops (`clearAllLibraryData`, `clearLibraryIndex`) — carries
  `TODO(cutover-R12)`: add `wdmm_library_clear_all` / `wdmm_library_clear_index`
  FFI exports.
- `getTrack()` — still used to look up `existing?.musicId` in ingest paths.

### B — Queue cutover (`kRustQueueEnabled = true`)

`task_queue_service.dart` now imports `rust_queue_bridge.dart`.

When `kRustQueueEnabled` is `true`:
- `_runCacheDownload` calls `RustQueueBridge.enqueue(taskJson)` at download start
  so the Rust `global_queue` carries the task and `pollStatus()` reflects it in
  the Tasks UI `_RustQueuePanel`.
- `cancel()` mirrors the cancel to `RustQueueBridge.cancel(id)`.

**Dart `_pump` is kept as the live engine.** The Rust `global_queue` in
`wdmm-ffi` is a bare `TaskQueue` with no executor/SerialPump wired — enqueuing
via FFI parks tasks in `Pending` forever; the Rust crate has no WebDAV
credentials or crypto layer available. Removing `_pump` now would break all
downloads.

`TODO(queue-cutover-R12)`: once a Rust executor + WebDAV credential flow lands
in `wdmm-ffi`, hand the whole `_runCacheDownload` branch to Rust and remove the
Dart pump download path.

### C — Proxy / LocalStreamBridge

`kRustProxyEnabled = true` was already set in Round 10/11. Updated doc-comment
in `rust_proxy_bridge.dart` to reflect Round 11 status.

**`LocalStreamBridge` is NOT deleted** — two live call sites remain:
- `cloud_drive_service.dart:_streamBridge` — MustProxy (crypt/encoded) driver
  streaming uses a Dart `ranges` callback into the crypto/WebDAV layer; the Rust
  proxy cannot supply this over FFI without a credential/stream bridge.
- `dlna_cast_service.dart` — DLNA LAN cast builds a `LocalStreamBridge` with
  `bindAddress: anyIPv4` for DMR reach.

`TODO(proxy-cutover-R12)`: wire credential/stream bridge in `wdmm-proxy` and
delete `LocalStreamBridge` once both call sites can route through Rust FFI.

### D — Docs

- Added this file (`docs/106-ROUND11-STATUS.md`).
- Updated `docs/101-ROUND5-HANDOFF.md` status lines (see checkbox updates below).

---

## Checklist updates (101-ROUND5-HANDOFF.md §A)

- [x] **Delete sqflite write dual-path** — done Round 11 for non-CUE track rows.
- [ ] **Delete `music_library_database_impl.dart`** — sqflite DB still needed for
  tombstones / sync cursor / CUE tables. Blocked on: bulk-clear FFI + CUE schema
  in Rust + `wdmm_library_clear_all`.

---

## Remaining dual-path / deferred items

| Item | Blocker |
|------|---------|
| CUE slice writes via Rust | No CUE schema in Rust storage yet |
| Bulk-clear library FFI (`destroyAll`, `prepareCloudOverwrite`) | No `wdmm_library_clear_all` FFI export |
| Bulk delete-by-source FFI (`replaceTracksForAccount`) | No `wdmm_track_delete_by_source` FFI export |
| Queue: Rust executor + credential flow | No executor wired in `wdmm-ffi` global queue |
| Proxy: delete `LocalStreamBridge` | MustProxy + DLNA cast need Dart `ranges` callback |
| OpenAPI binding to real on-device library DB (`:memory:` still used) | Out of scope R11 |
| Terabox deep fix | Out of scope R11 |
| OpenList-Frontend backend adapter | Out of scope R11 |

---

## `flutter analyze` result

See commit message — analyze ran clean (0 errors, 0 warnings) on all changed
files: `library_service.dart`, `task_queue_service.dart`, `rust_proxy_bridge.dart`.
