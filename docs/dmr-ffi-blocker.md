# DMR UI FFI Blocker (feat/dlna-dmr-ui)

**Branch:** `feat/dlna-dmr-ui`  
**Base SHA:** `3b06939` (refactor/rust-core tip)  
**Submodule SHA:** `d8b2217` (Round 10)  
**Date:** 2026-10-25

## Summary

Cannot proceed with Rust FFI-based DMR UI implementation. The `wdmm-ffi` crate (Round 10) provides **local file proxy only**; it lacks the HLS / ffmpeg transcode API required for DLNA cast sessions.

## Current FFI Surface (wdmm-ffi d8b2217)

### Available
- `wdmm_dlna_discover_json` — SSDP M-SEARCH discovery (timeout_ms)
- `wdmm_dlna_cast` — basic AVTransport SOAP cast (location, mediaUrl)
- `wdmm_proxy_start` / `_stop` / `_port` — start/stop local file proxy
- `wdmm_proxy_register_file(file_path, name)` — register **static local file**, returns `{token, path_template, port}`
- `wdmm_proxy_unregister(token)` — unregister token

### Missing (Required for DMR UI)

1. **HLS session registration API**
   - No FFI export for registering a WebDAV + crypto stream session
   - No way to pass `(accountId, remotePath, size, ranges_callback)` to Rust proxy
   - Current `wdmm_proxy_register_file` only accepts local file paths

2. **FFmpeg transcode parameters**
   - No FFI export for passing `DlnaTranscodeSettings` (remuxContainer, transcodeVideo, transcodeAudio)
   - No Rust-side transcode pipeline invocation

3. **DMR device preference persistence**
   - No FFI export for storing/retrieving per-device compat settings keyed by USN
   - No backup integration hook for DMR prefs

4. **Range → HLS stream mapping**
   - No FFI export for DMR Range requests mapped to HLS segments + ffmpeg pipeline

## Dart DLNA Implementation (Current, Working)

**Core cast service:** `lib/services/dlna_cast_service.dart` (1024 lines)
- SSDP M-SEARCH discovery via UDP multicast
- AVTransport SOAP (SetAVTransportURI / Play / Pause / Seek / Stop / GetPositionInfo / GetTransportInfo)
- ConnectionManager GetProtocolInfo negotiation
- Per-file protocolInfo / DIDL-Lite construction
- ffmpeg transcode pipeline
- Polling loop for position/state
- **Owns a `LocalStreamBridge` instance per cast session**

**LocalStreamBridge (LAN proxy):** `lib/services/cloud_drivers/stream_bridge.dart` (265 lines)
- Dart `HttpServer` that maps `(accountId, remotePath)` → token → `http://<lan-ip>:<port>/s/<token>`
- Accepts Range requests
- Forwards to caller-supplied `ranges` callback (which handles WebDAV auth / crypto decryption)
- Used by `DlnaCastService` bound to `anyIPv4` so the DMR on LAN can reach it

**DMR preference storage:** `lib/services/settings_service.dart` (lines 128–130)
- Three `SharedPreferences` keys: `dlna_remux_container`, `dlna_transcode_video`, `dlna_transcode_audio`
- **NOT** included in backup pipeline (device-local preferences)
- **GAP:** No wiring between `SettingsService` keys and `DlnaCastService._transcodeSettings` — the cast session starts with all-off defaults

## Required Rust FFI API (Blocking)

To retire the Dart DLNA/cast/proxy path and wire DMR UI to FFI, `wdmm-ffi` needs:

```rust
/// Register a cloud media stream session with the proxy for DLNA cast.
///
/// Parameters:
/// - `account_id`: WebDAV account identifier
/// - `remote_path`: remote file path (e.g. "/Music/track.mp3")
/// - `size`: file size in bytes (0 if unknown)
/// - `name`: display name for Content-Type guessing
/// - `transcode_json`: JSON object with transcode settings
///   `{"remux_container":true,"transcode_video":false,"transcode_audio":false}`
///
/// Returns JSON: `{"token":"...","path_template":"/s/...","port":N}` or `"error:..."`
///
/// The Rust proxy must:
/// 1. Accept Range requests from DMR
/// 2. Fetch bytes from WebDAV with auth (callback or credential store)
/// 3. Decrypt if crypt driver (callback or crypto vault)
/// 4. Pipe through ffmpeg if transcode settings require it
/// 5. Return HTTP 206 Partial Content with Range headers
#[no_mangle]
pub extern "C" fn wdmm_proxy_register_stream(
    account_id: *const c_char,
    remote_path: *const c_char,
    size: u64,
    name: *const c_char,
    transcode_json: *const c_char,
) -> FfiString;

/// Persist DMR device compatibility settings (keyed by SSDP USN).
///
/// Parameters:
/// - `usn`: SSDP USN (device identifier)
/// - `prefs_json`: JSON object with device prefs
///   `{"display_name":"Living Room TV","remux_container":true,"direct_stream":false}`
///
/// Returns `"ok"` or `"error:..."`
#[no_mangle]
pub extern "C" fn wdmm_dmr_prefs_upsert(
    usn: *const c_char,
    prefs_json: *const c_char,
) -> FfiString;

/// Retrieve DMR device compatibility settings by USN.
/// Returns JSON or `"null"` if not found.
#[no_mangle]
pub extern "C" fn wdmm_dmr_prefs_get(usn: *const c_char) -> FfiString;

/// List all stored DMR device preferences as JSON array.
#[no_mangle]
pub extern "C" fn wdmm_dmr_prefs_list() -> FfiString;

/// Delete DMR device preferences by USN.
#[no_mangle]
pub extern "C" fn wdmm_dmr_prefs_delete(usn: *const c_char) -> FfiString;
```

## Next Steps

1. **Wait for `feat/proxy-hls-ffmpeg` core work** to land the above FFI exports
2. **Bump submodule** in this branch to the HLS SHA
3. **Wire DMR UI to FFI:**
   - Replace `DlnaCastService` SSDP / SOAP / ffmpeg / polling with FFI calls
   - Replace `LocalStreamBridge` with `wdmm_proxy_register_stream`
   - Replace `SettingsService` DLNA keys with `wdmm_dmr_prefs_*` FFI
   - Delete Dart DLNA implementation files
4. **Hook DMR prefs into backup pipeline** (backup read/write + restore callback)

## Files to Retire (After Blocker Resolved)

**Delete entirely:**
- `lib/services/dlna_cast_service.dart` (1024 lines) — full DLNA DMR controller
- `lib/services/dlna_queue_controller.dart` — playlist queue
- `lib/services/cloud_drivers/stream_bridge.dart` (265 lines) — LocalStreamBridge

**Keep (Flutter UI only):**
- `lib/widgets/dlna_cast_bar.dart` — floating overlay bar (will call FFI)
- `lib/widgets/dlna_device_sheet.dart` — bottom sheet for device discovery (will call FFI)

**Modify:**
- `lib/services/settings_service.dart` — remove `_kDlnaRemuxContainer` / `_kDlnaTranscodeVideo` / `_kDlnaTranscodeAudio` keys, replace with FFI calls
- `lib/screens/home_shell.dart` — keep `DlnaCastBar` insertion
- `lib/screens/network_library_screen.dart` — replace cast button logic with FFI calls
- `lib/screens/video_player_screen.dart` — replace cast from video player with FFI calls

## Worktree State

- Branch `feat/dlna-dmr-ui` is clean (no uncommitted changes)
- Submodule `rust/wdmm-core` initialized at `d8b2217`
- No push / PR / workflow dispatch (per task constraints)

---

**Blocker Status:** ACTIVE  
**Resolution:** Depends on `feat/proxy-hls-ffmpeg` core FFI landing in `wdmm-core`
