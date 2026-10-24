# feat/dlna-dmr-ui Status Report

**Date:** 2026-10-25 (updated R12.1)
**Branch:** `feat/dlna-dmr-ui`
**Base:** `3b06939` (refactor/rust-core Round 11 tip)
**Status:** R12.1 — non-HLS polish applied; HLS / cloud-stream / transport / prefs FFI remain Core-blocked

---

## Executive Summary

The Android DLNA/DMR UI has been cut over to **Rust FFI**. The Dart DLNA
implementation (`dlna_cast_service.dart`, `dlna_queue_controller.dart`) is
**deleted**; the DLNA cast path now drives the Rust proxy (`wdmm_proxy_start` +
`wdmm_proxy_register_hls`) and Dart SOAP control through a single
`RustDlnaCastService`. Per-device DMR prefs are persisted in
`RustDmrPrefsService` keyed by SSDP USN (temporary Dart store — see below).

`LocalStreamBridge` (`stream_bridge.dart`) is **deleted** (R12.1).
`cloud_drive_service.resolveStreamSource` now throws a clear
`CloudDriverException` naming `wdmm_proxy_register_stream` when the driver
cannot supply a direct URL (MustProxy/crypt path). MustProxy playback is broken
until that FFI lands in wdmm-core.
- Deleted: `lib/services/cloud_drivers/stream_bridge.dart`
- Deleted: `test/crypt_stream_bridge_test.dart`

### What is blocked

Cast e2e is wired end-to-end for **locally cached files**. Two gaps remain
where the FFI at SHA `4a37aa4` does not yet provide the export:

1. **Cloud-stream cast** — there is no `wdmm_proxy_register_stream`
   (remote WebDAV + crypto decryption) at this SHA. The new service requires
   the file to be in the local cache; it surfaces a friendly error otherwise.
   The brief permits this: "mark cast e2e blocked only where probe/ffmpeg
   still Unavailable."
2. **DMR prefs FFI** — no `wdmm_dmr_prefs_*` exports at this SHA. The brief
   permits a "minimal clearly-temporary store keyed for migration":
   `RustDmrPrefsService` uses SharedPreferences keyed by USN, with backup
   hooks, ready to migrate to the Rust DB once the FFI lands.

Everything else (SSDP discovery, AVTransport SOAP control, DIDL-Lite /
protocolInfo negotiation, polling, queue, transcode settings, error→compat
fallback) is fully wired.

---

## SHAs

- **Submodule:** `rust/wdmm-core` pinned at `4a37aa4`
  (`feat/proxy-hls-ffmpeg`) — unchanged, not bumped in R12.1.
- **New FFI exports used:** `wdmm_proxy_register_hls`, `wdmm_proxy_unregister_hls`
  (added in 4a37aa4). `wdmm_proxy_start` / `_stop` / `_port` reused.
- **Branch tip:** R12 = `d8f1c6d`; LocalStreamBridge deletion = `7331d87`
  (prior commit on this branch); R12.1 commits on top of `7331d87`.

## Deleted Dart paths

- `lib/services/dlna_cast_service.dart` (1024 lines) — full Dart DLNA DMR
  controller (SSDP, SOAP, ffmpeg pipeline, LocalStreamBridge ownership).
  Deleted in R12; **confirmed still absent** in R12.1.
- `lib/services/dlna_queue_controller.dart` (238 lines) — DLNA playlist queue.
  Deleted in R12; **confirmed still absent**. Logic lives inline in
  `RustDlnaCastService._DlnaQueue`.
- `lib/services/cloud_drivers/stream_bridge.dart` (LocalStreamBridge) —
  deleted in prior commit `7331d87` (after R12). MustProxy/crypt stream
  playback now throws pending `wdmm_proxy_register_stream`. **Confirmed absent.**

## Created files

- `lib/services/rust_dlna_cast_service.dart` — FFI-wired cast service. Models
  (`DlnaRenderer`, `DlnaTranscodeSettings`, `DlnaCompatibilityHint`,
  `DlnaCastState`, `DlnaPlaybackState`) moved here. Inline queue.
- `lib/services/rust_dmr_prefs_service.dart` — per-USN DMR device prefs
  (`DmrDevicePrefs`) via SharedPreferences + backup export/import.

## FFI matrix

| Flow | Rust FFI | Dart | Status |
|---|---|---|---|
| SSDP discovery | `wdmm_dlna_discover_json` (blocking) | async UDP M-SEARCH (used) | ✅ wired (Dart — non-blocking) |
| Stream proxy | `wdmm_proxy_start` + `wdmm_proxy_register_hls` | — | ✅ wired (local file → HLS) |
| Cloud-stream proxy | `wdmm_proxy_register_stream` | — | ❌ BLOCKED — no FFI at SHA 4a37aa4 |
| Cast start (SetAVTransportURI + Play) | `wdmm_dlna_cast` available | Dart SOAP (used) | ✅ wired (Dart — full DIDL-Lite) |
| Transport control (pause/seek/stop) | none | Dart SOAP | ⚠️ Dart (no FFI equivalent; TODO r12-dlna-transport-ffi) |
| Position/state polling | none | Dart SOAP timer | ⚠️ Dart (same TODO) |
| DIDL-Lite / protocolInfo negotiation | none | Dart | ✅ wired (Dart) |
| DMR prefs persistence | `wdmm_dmr_prefs_*` (none) | SharedPreferences keyed by USN; schema_version=1 (R12.1) | ⚠️ temporary Dart store (migration-ready) |
| Backup integration | n/a | `RustDmrPrefsService.exportForBackup/importFromBackup` | ✅ wired |
| MustProxy/crypt stream | `wdmm_proxy_register_stream` (absent) | `stream_bridge` deleted (`7331d87`) | ❌ BROKEN — throws until FFI lands |

## Modified files

- `lib/services/rust_core_service.dart` — added `proxyRegisterHls` /
  `proxyUnregisterHls` bindings + lazy HLS symbol loader (non-fatal on older
  builds). Updated stale "Dart remains source of truth" comments.
- `lib/services/rust_proxy_bridge.dart` — updated cutover-status comment
  (DLNA cut over; LocalStreamBridge **deleted** in R12.1 — MustProxy/crypt
  path throws until `wdmm_proxy_register_stream` lands).
- `lib/services/settings_service.dart` — removed the three DLNA transcode
  keys (`dlna_remux_container` / `_transcode_video` / `_transcode_audio`) and
  their getters/setters. Per-device prefs now live in `RustDmrPrefsService`.
- `lib/services/backup_service.dart` — added `dmr_prefs` section to the
  payload (`_buildPayload` + `_applyPayload`), injected via
  `attachDmrPrefs` so BackupService has no hard dep on the cast service.
- `lib/providers/app_state.dart` — `dlnaCast` is now `RustDlnaCastService`;
  added `dmrPrefs: RustDmrPrefsService`; init phase + dispose wired;
  `backup.attachDmrPrefs` called after `dmrPrefs.init()`.
- `lib/main.dart` — provider swap (`RustDlnaCastService` +
  `RustDmrPrefsService`).
- `lib/widgets/dlna_cast_bar.dart`, `lib/widgets/dlna_device_sheet.dart`,
  `lib/screens/network_library_screen.dart`,
  `lib/screens/video_player_screen.dart`,
  `lib/screens/settings_screen.dart` — swapped to `RustDlnaCastService`;
  updated settings-screen proxy note.

## R12.1 changes (non-HLS polish — this slice)

### A. Cloud-cast typed errors (`rust_dlna_cast_service.dart`)

Replaces bare `Exception` throws with `DlnaCastError` (typed enum + Chinese messages).

| Code | Trigger | Chinese user message |
|---|---|---|
| `notCached` | File absent from local cache | 文件尚未缓存，请先下载后再投屏。 |
| `proxyUnavailable` | `wdmm_proxy_start` failed | 投屏引擎不可用，请在 Android 设备上运行（需要 wdmm-ffi）。 |
| `hlsRegisterFailed` | `wdmm_proxy_register_hls` returned error | HLS 代理注册失败，请确认 wdmm-ffi 已为此设备编译（SHA 4a37aa4）。 |
| `rendererNoVideo` | SinkProtocolInfo has no `video/*` | \<device\> 不支持视频播放，请检查设备是否支持 DLNA 视频投屏。 |
| `soapFailed` | AVTransport SOAP HTTP/network error | 投屏控制失败，请检查设备是否在线或重启后重试。 |
| `unknown` | Other | 投屏出错，请重试。 |

`DlnaCastError.userMessage` is shown in the cast bar; `techDetail` is appended
on clipboard ("Copy all"). `_friendlyError(raw)` removed (dead code).
New `castError` / `errorCode` getters on `RustDlnaCastService`. `_castError`
cleared in `_cleanupSession`. `playPause` error path also uses typed errors.

`_ErrorDetail` widget (`dlna_cast_bar.dart`) now takes `display` (shown) and
`copyText` (clipboard), keeping tech detail out of the main UI. After
`startCast`, a brief `AppSnack` fires only for `notCached` in both
`network_library_screen.dart` and `video_player_screen.dart` — all other
error codes are already visible in the cast bar.

### B. DMR prefs schema version (`rust_dmr_prefs_service.dart`)

- `_kSchemaVersionKey = 'dmr_prefs_schema_version'` stored on first init
  (`_kCurrentSchemaVersion = 1`).
- `init()` calls `_migrateIfNeeded()` (v1→v1 no-op; stub for future Rust import).
- Class doc records target Rust JSON shape and migration steps.
- Backup `exportForBackup` flat `usn → prefs` unchanged (back-compat).

### C. Transport FFI — **skipped per brief**

No Rust AVTransport FFI. Dart SOAP + `TODO(r12-dlna-transport-ffi)` as-is.

### D. HLS — **not chased per brief**

No changes to `wdmm_proxy_register_hls` arity, `device_id`, or HLS seek.

## Remaining blockers + next SHA dependencies

| Blocker | Missing export | Next action |
|---|---|---|
| Cloud-stream cast | `wdmm_proxy_register_stream` | Bump submodule when `feat/proxy-hls-ffmpeg` exports it |
| MustProxy/crypt playback | same | Same bump |
| Transport control (pause/seek/stop) | AVTransport Rust exports | Same or separate bump |
| DMR prefs FFI | `wdmm_dmr_prefs_upsert/_get/_list/_delete` | Same or separate bump |
| HLS `device_id` / seek | Core follow-up | **Do not chase** — Core-blocked, out of scope |

## Leftovers / follow-ups

- **MustProxy LocalStreamBridge** — deleted in `7331d87`. MustProxy/crypt
  playback in `cloud_drive_service.resolveStreamSource` throws until
  `wdmm_proxy_register_stream` lands in wdmm-core.
  TODO(proxy-cutover): wire that FFI to restore MustProxy.
- **DMR prefs → Rust DB** — once `wdmm_dmr_prefs_*` lands, replace
  `RustDmrPrefsService` body with FFI wrappers; migrate existing
  SharedPreferences keys on first open (see migration stub in the class doc).
- **Transport FFI** — Pause/Seek/Stop/GetPosition need Rust AVTransport SOAP
  exports (TODO r12-dlna-transport-ffi) to retire the Dart SOAP layer.
- **Cloud-stream cast** — `wdmm_proxy_register_stream` absent at 4a37aa4.
  `notCached` error code directs user to download first.

---

**Blocker Status:** R12.1 non-HLS polish done. Cast e2e blocked on
cloud-stream + transport + prefs FFI (core follow-ups on `feat/proxy-hls-ffmpeg`).
HLS remains Core-blocked — not chased in this slice.
No Dart DLNA regression; no HLS chase; deleted paths confirmed absent.
