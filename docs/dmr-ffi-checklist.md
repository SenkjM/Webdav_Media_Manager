# DMR UI FFI Implementation Checklist

**Prerequisites:** HLS/ffmpeg FFI API must be available in `wdmm-core` (see `docs/dmr-ffi-blocker.md`)

---

## Phase 1: Submodule Bump

- [ ] Monitor `feat/proxy-hls-ffmpeg` branch for completion
- [ ] Identify HLS FFI SHA in `wdmm-core` that includes:
  - `wdmm_proxy_register_stream` export
  - `wdmm_dmr_prefs_upsert` / `_get` / `_list` / `_delete` exports
- [ ] Bump submodule:
  ```bash
  cd rust/wdmm-core
  git fetch origin
  git checkout <hls-sha>
  cd ../..
  git add rust/wdmm-core
  git commit -m "chore(submodule): bump wdmm-core to HLS/ffmpeg SHA"
  ```
- [ ] Verify FFI exports in `rust/wdmm-core/crates/wdmm-ffi/src/lib.rs`

---

## Phase 2: FFI Bindings (Dart)

### A. Core Service — Add HLS Proxy FFI

**File:** `lib/services/rust_core_service.dart`

1. **Add typedefs:**
   ```dart
   typedef _ProxyRegisterStreamNative = ffi.Pointer<Utf8> Function(
       ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Uint64, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
   typedef _ProxyRegisterStreamDart = ffi.Pointer<Utf8> Function(
       ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
   ```

2. **Add static fields:**
   ```dart
   static _ProxyRegisterStreamDart? _proxyRegisterStream;
   ```

3. **Load symbols in `_loadProxySymbolsSafe`:**
   ```dart
   _proxyRegisterStream = lib
       .lookup<ffi.NativeFunction<_ProxyRegisterStreamNative>>('wdmm_proxy_register_stream')
       .asFunction();
   ```

4. **Add public method:**
   ```dart
   static String? proxyRegisterStream({
     required String accountId,
     required String remotePath,
     required int size,
     String? name,
     String? transcodeJson,
   }) {
     if (!_ensureSymbols()) return null;
     _loadProxySymbolsSafe();
     if (_proxyRegisterStream == null) return null;
     // ... implementation
   }
   ```

### B. Core Service — Add DMR Prefs FFI

**File:** `lib/services/rust_core_service.dart`

1. **Add typedefs:**
   ```dart
   typedef _OneStrToStrNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
   typedef _OneStrToStrDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
   typedef _TwoStrToStrNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
   typedef _TwoStrToStrDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
   ```

2. **Add static fields:**
   ```dart
   static _TwoStrToStrDart? _dmrPrefsUpsert;
   static _OneStrToStrDart? _dmrPrefsGet;
   static _NoArgToStrDart? _dmrPrefsList;
   static _OneStrToStrDart? _dmrPrefsDelete;
   ```

3. **Load symbols in new `_loadDmrPrefsSymbolsSafe`:**
   ```dart
   static void _loadDmrPrefsSymbolsSafe() {
     if (_dmrPrefsSymbolsLoaded) return;
     final lib = _tryLib;
     if (lib == null) return;
     try {
       _dmrPrefsUpsert = lib.lookup<ffi.NativeFunction<_TwoStrToStrNative>>('wdmm_dmr_prefs_upsert').asFunction();
       _dmrPrefsGet = lib.lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_dmr_prefs_get').asFunction();
       _dmrPrefsList = lib.lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_dmr_prefs_list').asFunction();
       _dmrPrefsDelete = lib.lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_dmr_prefs_delete').asFunction();
       _dmrPrefsSymbolsLoaded = true;
     } catch (e) {
       debugPrint('[RustCore] DMR prefs symbol lookup failed (non-fatal): $e');
     }
   }
   ```

4. **Add public methods:**
   ```dart
   static String? dmrPrefsUpsert(String usn, String prefsJson) { /* ... */ }
   static String? dmrPrefsGet(String usn) { /* ... */ }
   static String? dmrPrefsList() { /* ... */ }
   static String? dmrPrefsDelete(String usn) { /* ... */ }
   ```

---

## Phase 3: Service Layer

### A. Create `lib/services/rust_dlna_cast_service.dart`

Thin FFI wrapper over `RustCoreService`:
- `startDiscovery()` → calls `RustCoreService.dlnaDiscover`
- `cast()` → calls `RustCoreService.proxyRegisterStream` + `RustCoreService.dlnaCast`
- `stop()` → calls `RustCoreService.proxyUnregister`

Model the same interface as the current `DlnaCastService` so UI widgets don't need to change.

### B. Create `lib/services/rust_dmr_prefs_service.dart`

DMR device preference persistence via FFI:
- `upsert(usn, prefs)` → calls `RustCoreService.dmrPrefsUpsert`
- `get(usn)` → calls `RustCoreService.dmrPrefsGet`
- `list()` → calls `RustCoreService.dmrPrefsList`
- `delete(usn)` → calls `RustCoreService.dmrPrefsDelete`
- `exportForBackup()` → returns JSON for backup payload
- `importFromBackup(json)` → restores DMR prefs from backup

---

## Phase 4: Delete Dart DLNA Implementation

- [ ] **Delete:**
  - `lib/services/dlna_cast_service.dart` (1024 lines)
  - `lib/services/dlna_queue_controller.dart` (238 lines)
  - `lib/services/cloud_drivers/stream_bridge.dart` (265 lines)

- [ ] **Check for lingering references:**
  ```bash
  grep -rn "DlnaCastService\|LocalStreamBridge\|DlnaQueueController" lib/ --exclude-dir=generated
  ```

- [ ] **Remove from imports:**
  - `lib/screens/home_shell.dart`
  - `lib/screens/network_library_screen.dart`
  - `lib/screens/video_player_screen.dart`
  - `lib/widgets/dlna_cast_bar.dart`
  - `lib/widgets/dlna_device_sheet.dart`

---

## Phase 5: Wire UI to FFI Services

### A. `lib/widgets/dlna_cast_bar.dart`
- [ ] Replace `context.watch<DlnaCastService>()` with `context.watch<RustDlnaCastService>()`
- [ ] Update transcode panel to call `RustDmrPrefsService.upsert()` on settings change
- [ ] Update queue sheet to use FFI-backed queue (if applicable)

### B. `lib/widgets/dlna_device_sheet.dart`
- [ ] Replace `context.read<DlnaCastService>().startDiscovery()` with `context.read<RustDlnaCastService>().startDiscovery()`
- [ ] Update renderer selection to call FFI cast

### C. `lib/screens/network_library_screen.dart`
- [ ] Replace cast button logic to use `RustDlnaCastService`

### D. `lib/screens/video_player_screen.dart`
- [ ] Replace cast from video player to use `RustDlnaCastService`

### E. `lib/providers/app_state.dart`
- [ ] Remove `DlnaCastService` provider
- [ ] Add `RustDlnaCastService` provider
- [ ] Add `RustDmrPrefsService` provider

---

## Phase 6: Settings Service Cleanup

**File:** `lib/services/settings_service.dart`

- [ ] Remove keys (lines 128–130):
  ```dart
  static const _kDlnaRemuxContainer = 'dlna_remux_container';
  static const _kDlnaTranscodeVideo = 'dlna_transcode_video';
  static const _kDlnaTranscodeAudio = 'dlna_transcode_audio';
  ```

- [ ] Remove getters/setters (lines 630–648):
  ```dart
  bool get dlnaRemuxContainer => ...
  set dlnaRemuxContainer(bool v) { ... }
  // ... (same for transcodeVideo, transcodeAudio)
  ```

- [ ] **Check for lingering references:**
  ```bash
  grep -rn "dlnaRemuxContainer\|dlnaTranscodeVideo\|dlnaTranscodeAudio" lib/ --exclude-dir=generated
  ```

---

## Phase 7: Backup Integration

**File:** `lib/services/backup_service.dart`

1. **Add DMR prefs to payload:**
   ```dart
   'dmr_prefs': await _rustDmrPrefsService.exportForBackup(),
   ```

2. **Restore DMR prefs:**
   ```dart
   if (payload['dmr_prefs'] != null) {
     await _rustDmrPrefsService.importFromBackup(payload['dmr_prefs']);
   }
   ```

3. **Add `onDmrPrefsImported` callback (optional):**
   ```dart
   final Future<void> Function()? _onDmrPrefsImported;
   ```

---

## Phase 8: Testing

### A. Device Smoke Test
- [ ] Cast a video from network library to a DMR device
- [ ] Verify SSDP discovery finds devices
- [ ] Verify AVTransport SOAP cast works
- [ ] Verify proxy serves the stream (HLS or file Range)
- [ ] Verify transcode settings apply (remux / video / audio)

### B. Preference Persistence
- [ ] Set transcode settings for a device
- [ ] Restart app
- [ ] Verify settings persist for the same device (keyed by USN)

### C. Backup/Restore
- [ ] Create a backup with DMR prefs
- [ ] Restore on a fresh install
- [ ] Verify DMR prefs are restored

### D. Error Handling
- [ ] Cast to a non-existent device (error UI)
- [ ] Cast a file that cannot be transcoded (error UI)
- [ ] Stop cast mid-session (cleanup)

---

## Phase 9: Documentation

- [ ] Update `docs/feat-dlna-dmr-ui-status.md` with completion status
- [ ] Remove `docs/dmr-ffi-blocker.md` (blocker resolved)
- [ ] Create `docs/dmr-ffi-implementation-notes.md` with:
  - FFI API used
  - Files deleted vs. FFI-wired
  - Known limitations

---

## Phase 10: Commit

```bash
git add -A
git commit -m "feat(android): wire DMR UI to Rust FFI (R12)

- Delete Dart DLNA implementation (cast_service, queue_controller, stream_bridge)
- Add RustDlnaCastService FFI wrapper over wdmm_proxy_register_stream + wdmm_dlna_cast
- Add RustDmrPrefsService FFI wrapper over wdmm_dmr_prefs_*
- Wire UI widgets (cast_bar, device_sheet) to FFI services
- Remove SettingsService DLNA keys (now in Rust DB)
- Hook DMR prefs into backup pipeline
- Submodule: bump wdmm-core to HLS/ffmpeg SHA

Closes: Android DMR UI via Rust FFI (feat/dlna-dmr-ui)
Related: feat/proxy-hls-ffmpeg (core HLS API)
"
```

---

## Out of Scope (For This Branch)

- Implementing `wdmm-ffmpeg` / HLS sessions (core job on `feat/proxy-hls-ffmpeg`)
- Push / PR / workflow dispatch (per task constraints)
- DMR advanced features (multi-zone, queue reordering, custom DIDL-Lite)

---

**Status:** READY TO EXECUTE (once blocker resolves)  
**Estimated Effort:** 4–6 hours (post-blocker)
