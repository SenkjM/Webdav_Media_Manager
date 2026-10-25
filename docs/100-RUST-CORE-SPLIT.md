# 100 — Rust Core Split: WDMM-core Integration

**Status**: **Round 5** — serial queue, storage schema v2, library FFI/OpenAPI landed. DB cutover + Dart driver deletion remain (Round 6).

---

## Motivation & Architecture

WebDAV Media Manager's business logic (cloud drivers, DB, sync, crypto, DLNA) is being extracted into a **separate Rust workspace** [WDMM-core](https://github.com/SenkjM/WDMM-core) to enable:

1. **Windows Desktop** support (WinUI 3 GUI + same core via csbindgen P/Invoke).
2. **Unified local proxy** + DLNA cast logic owned by Rust (remove per-platform duplication).
3. **Long-term maintainability** — business logic once, two UIs.

This Android Flutter repo (`Webdav_Media_Manager`) becomes:
- **UI + platform adapters** (playback stack, SAF, MediaStore, notifications, foreground service, `.nomedia`)
- **FFI bridge** to WDMM-core via `flutter_rust_bridge`.

**Coupling strategy**: **Source-level FFI** is primary; OpenAPI (optional Rust HTTP server) is toggleable in settings for external clients (e.g. Electron app, testing). Native Android path uses FFI only.

---

## Workspace Overview (WDMM-core)

| Crate | Responsibility |
|-------|----------------|
| `wdmm-core` | Pure data models; track identity (SHA-1); zero platform deps |
| `wdmm-crypto` | AES-256-GCM credential vault (PBKDF2 600k iterations) |
| `wdmm-drivers` | `CloudDriver` trait; **WebDAV working**; baidu/aliyundrive/ctfile/etc. stubbed |
| `wdmm-storage` | rusqlite library DB (**schema v2**: tracks+albums+artists+playlists+manga-stubs; full CRUD + search) |
| `wdmm-queue` | Task-queue FIFO state machine; **`SerialPump`** (single-worker, concurrency=1, mirrors Dart `_pump`) |
| `wdmm-sync` | Incremental sync engine stubs |
| `wdmm-dlna` | DLNA/UPnP SSDP discovery + AVTransport SOAP; **owns local proxy** |
| `wdmm-platform` | Adapter traits (keychain, notification, FS, wakelock) + std default impl |
| `wdmm-openapi` | Toggleable axum HTTP server (`/v1/` routes; bind modes; token auth) |
| `wdmm-ffi` | C ABI surface (`cdylib`) for `flutter_rust_bridge` |

All crates: `publish = false` (see `WDMM-core/docs/CONSTRAINTS.md §5` — service ToS / key leakage risk / no crates.io).

---

## Migration Map (Phased)

### Phase 1 (First Bootstrap — done)

- ✅ WDMM-core workspace exists with all 10 crates.
- ✅ `wdmm-ffi` exports `wdmm_version()` / `wdmm_hello()` / `wdmm_openapi_status()`.
- ✅ This doc (`100-RUST-CORE-SPLIT.md`) lands.
- ✅ `pubspec.yaml` updated with `flutter_rust_bridge` dep + README notes.
- ✅ Minimal Dart FFI stub (call `wdmm_version()` and log it).
- ⚠️ Existing Dart services **remain untouched** (coexistence path; no deletion this round).

### Phase 2 (DB Migration — schema ready; device cutover pending Round 6)

- ✅ `wdmm-storage` at **schema v2**: `tracks` (+ v2 columns: album_id/artist_id/duration_ms/genre/track_number/disc_number/year/mime_type), `albums`, `artists`, `playlists`, `playlist_entries`, `accounts`, `kv_store`, `manga_series`/`manga_chapters` (stubs).
- ✅ Full CRUD: `upsert_track`, `get_track`, `list_tracks`, `search_tracks`, `delete_track`; artists/albums CRUD; playlist+entries CRUD.
- ✅ FFI surface: `wdmm_library_init`, `wdmm_track_upsert/get/list/search/delete`.
- ✅ OpenAPI: `/v1/library/tracks` (list, `?q=` search, get, upsert, delete) + `/v1/playlists` + `/v1/playlists/:id/entries`.
- ⏳ **Remaining (Round 6)**: one-shot sqflite→rusqlite import script on device; flip Dart DB calls to FFI; delete `music_library_database_impl.dart` when green. Dual-read probe (log counts) OK before the flip.

### Phase 3 (Cloud Drivers — **Phase 2.3 complete: FFI cutover landed**)

- ✅ WebDAV: list/get/mkdir/rename/remove/put_content/get_content + **`get_content_range`** (Range header).
- ✅ CtFile: list + download_url (fetch_url) with id-prefix dual strategy, throttle, retry.
- ✅ **All cloud drivers**: baidu/aliyundrive/115/terabox/netease/123/crypt — full `CloudDriver` impl in Core; FFI via `wdmm_account_list_dir` etc.; **Dart drivers retired** (Wave C).
- ✅ **Phase 2.3 (Android FFI cutover)**: `CloudDriveService._createDriver` now returns `RustCloudDriver` for all cloud types; `spec.create()` Dart constructors no longer used.
- ⏳ **Remaining (Phase 2.4)**: delete Dart driver files (`lib/services/cloud_drivers/*.dart`) after verification; remove `driver_registry.dart` once no references remain.

### Phase 4 (Queue + Sync + DLNA — done)

- ✅ **`SerialPump`**: single-worker FIFO (concurrency = 1, matching Dart `_pump`). No concurrent download workers. Tests assert max 1 active task at any instant.
- ✅ sync↔WebDAV codec; DLNA AVTransport + SSDP discovery.

### Phase 5 (Cleanup — pending Round 6+)

- Remove all Dart business logic files.
- UI code + platform adapters remain.
- Project tree becomes: `lib/` = UI + FFI bridge; `rust/` = submodule or sibling path to WDMM-core.

---

## FFI Integration (flutter_rust_bridge)

### Dependencies

`pubspec.yaml`:

```yaml
dependencies:
  flutter_rust_bridge: ^2.7.0   # bindings generator
  # (add others per FRB docs: ffi, freezed_annotation, etc.)
```

`build.gradle.kts` / Android native build:

- `cargo-ndk` integration (similar to existing `openlist_crypt` native assets workflow).
- Build `wdmm-ffi` as `libwdmm_ffi.so` for each ABI (`armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`).
- Place in `android/app/src/main/jniLibs/<abi>/`.

### Directory Layout Convention

**Option A** (submodule) — ✅ **ADOPTED (2026-10-23)**:

```
Webdav_Media_Manager/
├── lib/
├── rust/
│   └── wdmm-core/ (git submodule → https://github.com/SenkjM/WDMM-core.git)
└── pubspec.yaml
```

Submodule pinned to `b7d798098c7a04c2cbff4fcb1ee3ca3bfc7ea691` (WDMM-core `main` tip, 2026-10-23).

Initialise after clone:
```bash
git submodule update --init rust/wdmm-core
```

> **CI note**: No GitHub Actions workflow currently builds native/FFI code, so `submodules: recursive` is not yet required. When a Rust build job is added, set `submodules: true` (or `recursive`) on its `actions/checkout` step.

**Option B** (sibling path) — superseded by Option A:

```
/your/projects/
├── Webdav_Media_Manager/
└── WDMM-core/
```

Dart bindings generator points at `rust/wdmm-core/crates/wdmm-ffi/src/lib.rs`.

### Generating Bindings

```bash
flutter_rust_bridge_codegen generate \
  --rust-input rust/wdmm-core/crates/wdmm-ffi/src/lib.rs \
  --dart-output lib/generated/ffi_bindings.dart
```

### Example Usage

`lib/services/rust_core_service.dart`:

```dart
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'generated/ffi_bindings.dart';

class RustCoreService {
  late final WdmmCore _api;

  RustCoreService() {
    _api = WdmmCore(dylib: loadDylib());
  }

  Future<String> getCoreVersion() async {
    final ffiStr = await _api.wdmmVersion();
    return ffiStr; // FRB auto-converts FfiString to Dart String
  }

  Future<int> getOpenApiStatus() async {
    return await _api.wdmmOpenapiStatus();
  }
}

DynamicLibrary loadDylib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libwdmm_ffi.so');
  }
  // Windows: 'wdmm_ffi.dll', macOS: 'libwdmm_ffi.dylib'
  throw UnsupportedError('Platform not supported');
}
```

Call from UI:

```dart
final rustCore = RustCoreService();
final version = await rustCore.getCoreVersion();
print('WDMM Core version: $version');
```

---

## Coexistence Strategy (This Round)

- **No deletion of existing Dart services** yet.
- FFI calls are **additive** — run alongside existing sqflite / webdav_client / etc.
- Enables incremental testing: compare Rust driver output vs. Dart driver output for the same operation.
- DB cutover = **one-shot** (no long window of dual-write).

---

## OpenAPI (Optional)

WDMM-core includes `wdmm-openapi` crate (axum HTTP server). **Not used by Android native FFI path**. Optional toggle in settings for:

- External clients (Electron app, web UI, testing scripts).
- LAN access (bind `0.0.0.0`; requires token for non-localhost clients).

Android settings UI (future):
- Toggle "Enable OpenAPI Server" on/off.
- Bind mode dropdown: Local (127.0.0.1) / Global (0.0.0.0) / Custom IP.
- Display token (read-only; for external clients).

FFI call: `wdmm_openapi_start(config)` / `wdmm_openapi_stop()`.

---

## Known Gaps (Round 5 → Round 6)

- DB cutover script (sqflite→rusqlite one-shot import) not yet run on device.
- Six cloud drivers still stubbed (baidu/aliyundrive/115/terabox/netease/123); CtFile write ops TODO.
- Dart services/drivers not yet deleted (coexistence phase).
- Manga library is schema stubs only (no FFI/OpenAPI surface).
- Android Dart wrappers (`RustLibraryProbe` / `RustCoreService`) for the new track CRUD exports not yet written.

Full implementation continues in subsequent phased rounds per `saf_work/wdmm-split-round5-brief.md`.

---

## References

- **Rust Core Repo**: https://github.com/SenkjM/WDMM-core
- **Windows Desktop Repo**: https://github.com/SenkjM/WDMM-desktop
- **Constraints**: `WDMM-core/docs/CONSTRAINTS.md`
- **Brief**: `/workspace/saf_work/wdmm-split-impl-brief.md`
- **flutter_rust_bridge Docs**: https://cjycode.com/flutter_rust_bridge/

---

## Next Steps (Post-Bootstrap)

1. Add `flutter_rust_bridge` to `pubspec.yaml` + `build.gradle.kts` cargo-ndk integration.
2. Build `wdmm-ffi` as `cdylib` for Android ABIs.
3. Generate Dart bindings with `flutter_rust_bridge_codegen`.
4. Implement `RustCoreService` + smoke test (call `wdmm_version()` on app start).
5. Phase 2: DB migration (sqflite → rusqlite via FFI).
6. Phases 3-5: drivers, queue, sync, DLNA, cleanup.

---

*Author: Claude Code (Grok Bot supervision) — 2026-10-21*
