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

## Backup Interop (Android ↔ Core)

**Status (2026-10-26)**: Restore is dual-path on **both** sides. Android **create** remains Dart/binary (sqflite is still SoT). See Core `docs/107-BACKUP-LIBRARY-SOT.md` and `docs/ANDROID-BINARY-BACKUP-COMPAT.md`.

### Encoding Differences

| Producer | Section 2 (tracks) | Section 5 (credentials) | Envelope |
|----------|-------------------|------------------------|----------|
| Android `BackupService.buildArchiveBytes` | binary Wmp track records + covers (often deflated) | nested `WDMMCV01` vault bytes | WDMMEN01 optional |
| Core `wdmm_sync::build_backup_bytes` | **UTF-8 JSON** track array | **UTF-8 JSON** accounts (`credentials_b64`) | WDMMEN01 optional |
| Desktop | uses Core FFI only | Core JSON create; dual-read restore | Core |

Both use the same magic `WDMMBK01` / section ids; only the **payload codecs** differ. Core restore now **dual-reads** Android binary sections (codec 0/1 inflate, WDMMCV01 / Wmp tracks / WDMMPL01) as well as Core JSON.

### Current State

- **Create**: Android stays on `BackupService.buildArchiveBytes` (Dart) while sqflite `LibraryDatabase` is the source of truth. Do **not** half-cut create to Core FFI yet.
- **Restore (Android)**: `BackupService.restoreFromBytes` peeks section 2 — JSON → `RustCoreService.backupRestore`; else Android binary `_decodeContainer`.
- **Restore (Core / Desktop)**: `restore_backup_bytes` dual-reads Android binary BK (credentials/tracks/playlists) and Core JSON. Desktop inherits via FFI after submodule bump.
- **Round-trip that works without device**: Core JSON ↔ Desktop; Core JSON → Android restore; **Android binary BK → Core/Desktop restore** (unit-tested in `wdmm-sync`). Full device round-trip still needs library SoT migration + on-device check.

### FFI Bindings

`RustCoreService` now exposes:
- `backupUpload(url, user, pass, remoteDir, passphrase)` — upload via Core
- `backupList(url, user, pass, remoteDir)` → JSON string — list available backups
- `backupDownloadRestore(url, user, pass, remoteFile, passphrase)` — download + restore in one call

These enable full WebDAV backup workflows without Dart HTTP drivers when used with Core JSON backups; Android-made binary archives are also restorable on Desktop through Core.

---

## Account Sync (Core DB is SoT)

**Status (2026-10-27)**: Core DB (`wdmm-core` via FFI) is the **sole source of truth** for account metadata. Android sqflite is no longer written for accounts after the one-shot migrate. Matches Desktop `AccountStore.cs`.

### FFI Bindings

`RustCoreService` exposes account CRUD:
- `accountList()` → JSON array of accounts (or `"error:..."`)
- `accountGet(String id)` → JSON object, `"null"` if absent, or `"error:..."`
- `accountUpsert(String coreJson)` → `"ok"` or `"error:..."` — core JSON = `{id, provider_type, display_name, base_url, credentials}`
- `accountDelete(String id)` → `"ok"` or `"error:..."`

All return `String?` (null if FFI unavailable / non-Android).

### Credentials Structure

| Provider Type | Credentials Map |
|--------------|----------------|
| `webdav` | `{username, password, remote_dir}` |
| Cloud drivers | driver config (tokens/cookies from `AccountsService.loadDriverConfig`) |
| `crypt` | driver config + nested `source: {provider_type, config}` resolved at upsert time |

Passwords and driver configs are **also** kept in `FlutterSecureStorage` so Dart-side drivers can access them without FFI round-trips. On every `_loadFromCore()` call, missing secure-storage keys are back-filled from the Core credentials payload.

### Init + One-Shot Migrate

`AccountsService.init()` order:
1. **Load from Core** via `accountList()` → parse JSON → fill `_accounts`; back-fill secure-storage keys (passwords, driver configs) if missing.
2. If Core is empty: **one-shot sqflite→Core migrate** — create a temporary `LibraryDatabase()`, read existing rows, upsert each to Core via `_upsertToCore`. **Fail hard** on any upsert error (throws `StateError`). After migrate, sqflite is never read for accounts again.
3. If still empty: **legacy flutter_secure migrate** — read old single-server `webdav_url/username/password` keys, upsert to Core, delete legacy keys.

After a successful migrate the prefs key `active_webdav_account_id` is preserved; Core is non-empty on every subsequent launch so steps 2–3 are skipped.

### CRUD — Core Only, Fail Hard

All write operations (`addAccount`, `updateAccount`, `deleteAccount`, `saveDriverConfig`) call `_upsertToCore` / `accountDelete` and **throw `StateError`** on FFI null or `"error:..."`. There is no fallback to sqflite and no silent swallowing of Core errors.

`deleteAccount`: Core delete first; if Core returns an error, the in-memory list is **not** updated (transactional intent preserved). Secure-storage keys are cleaned up after a successful Core delete.

### Cloud Driver Integration

`CloudDriveService.registerAccounts` ensures Core has the account row before driver instantiation:
1. Call `RustCoreService.accountGet(a.id)`.
2. If absent or error, call `AccountsService.ensureAccountInCore(a.id)` — **throws on failure**.
3. Verify the row landed with a second `accountGet`; throw if still missing.
4. Proceed with `_createDriver`. `CloudDriverException` is caught per-account (driver skipped, `complete = false`); `StateError` from Core propagates up.

### Rationale

- Single authority: Core owns account metadata + credentials; Dart SecureStorage is a read-cache for the Dart driver layer.
- Desktop parity: mirrors `AccountStore.cs` (`List()` / `Upsert()` / `Delete()` / `MigrateFromLocalJsonIfNeeded()`).
- Fail-hard keeps the app state consistent: a half-written account (in memory but not Core) would cause silent driver failures later.

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
