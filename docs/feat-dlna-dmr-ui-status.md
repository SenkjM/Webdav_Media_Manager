# feat/dlna-dmr-ui Status Report

**Date:** 2026-10-25
**Branch:** `feat/dlna-dmr-ui`
**Base:** `3b06939` (refactor/rust-core Round 11 tip)
**Status:** IMPLEMENTED (Round 12) — cast e2e blocked only where cloud-stream/probe FFI absent

---

## Executive Summary

The Android DLNA/DMR UI has been cut over to **Rust FFI**. The Dart DLNA
implementation (`dlna_cast_service.dart`, `dlna_queue_controller.dart`) is
**deleted**; the DLNA cast path now drives the Rust proxy (`wdmm_proxy_start` +
`wdmm_proxy_register_hls`) and Dart SOAP control through a single
`RustDlnaCastService`. Per-device DMR prefs are persisted in
`RustDmrPrefsService` keyed by SSDP USN (temporary Dart store — see below).

`LocalStreamBridge` (`stream_bridge.dart`) is **kept**: `cloud_drive_service.dart`
still uses it for the MustProxy (crypt) path, which is unrelated to DLNA. It will
be deleted when MustProxy cuts over to Rust FFI (TODO proxy-cutover-R13).

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

- **Submodule bump:** `rust/wdmm-core` `d8b2217` → `4a37aa4`
  (`feat/proxy-hls-ffmpeg`, Round 11 — wdmm-ffmpeg skeleton + HLS session
  proxy + FFI).
- **New FFI exports used:** `wdmm_proxy_register_hls`, `wdmm_proxy_unregister_hls`
  (added in 4a37aa4). `wdmm_proxy_start` / `_stop` / `_port` reused.

## Deleted Dart paths

- `lib/services/dlna_cast_service.dart` (1024 lines) — full Dart DLNA DMR
  controller (SSDP, SOAP, ffmpeg pipeline, LocalStreamBridge ownership).
- `lib/services/dlna_queue_controller.dart` (238 lines) — DLNA playlist queue.
  Logic moved inline into `RustDlnaCastService._DlnaQueue`.

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
| DMR prefs persistence | `wdmm_dmr_prefs_*` (none) | SharedPreferences keyed by USN | ⚠️ temporary Dart store (migration-ready) |
| Backup integration | n/a | `RustDmrPrefsService.exportForBackup/importFromBackup` | ✅ wired |

## Modified files

- `lib/services/rust_core_service.dart` — added `proxyRegisterHls` /
  `proxyUnregisterHls` bindings + lazy HLS symbol loader (non-fatal on older
  builds). Updated stale "Dart remains source of truth" comments.
- `lib/services/rust_proxy_bridge.dart` — updated cutover-status comment
  (DLNA cut over; LocalStreamBridge kept for MustProxy only).
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

## Leftovers / follow-ups

- **MustProxy LocalStreamBridge** — still used by `cloud_drive_service.dart`
  for crypt/encoded stream serving. Delete after MustProxy cuts over to a
  Rust credential/stream bridge (TODO proxy-cutover-R13).
- **DMR prefs → Rust DB** — once `wdmm_dmr_prefs_*` lands, replace the
  SharedPreferences body of `RustDmrPrefsService` with FFI wrappers and
  migrate existing keys on first open.
- **Transport FFI** — `wdmm_dlna_cast` only does SetAVTransportURI+Play.
  Pause/Seek/Stop/GetPosition need Rust AVTransport SOAP exports
  (TODO r12-dlna-transport-ffi) to fully retire the Dart SOAP layer.
- **Cloud-stream cast** — `wdmm_proxy_register_stream` (remote WebDAV +
  crypto) not present at 4a37aa4. Until it lands, cast requires a locally
  cached file.

---

**Blocker Status:** RESOLVED for the UI/FFI wiring job. Cast e2e blocked
only on cloud-stream + transport FFI (core follow-ups on
`feat/proxy-hls-ffmpeg`).
