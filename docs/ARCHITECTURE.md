# WDMM Architecture

Last updated: 2026-10-30 (B5 cleanup complete).

---

## Layer overview

```
┌─────────────────────────────────────────────────────────┐
│  Flutter UI  (lib/)                                     │
│  screens · widgets · blocs · services (thin adapters)   │
└────────────────────┬────────────────────────────────────┘
                     │ Dart FFI  (rust_core_service.dart)
┌────────────────────▼────────────────────────────────────┐
│  wdmm-ffi  (crates/wdmm-ffi)                            │
│  single shared-library boundary; all C exports here     │
│                                                         │
│  ├─ wdmm-storage  — SQLite (library + prefs + KV)       │
│  ├─ wdmm-core     — models, sync engine, queue          │
│  ├─ wdmm-drivers  — 9 cloud driver impls (WdmmVfs)      │
│  ├─ wdmm-ffmpeg   — in-process libav transcode engine   │
│  ├─ wdmm-proxy    — local HTTP reverse proxy (Axum)     │
│  └─ wdmm-openapi  — local REST API (Axum, loopback)     │
└─────────────────────────────────────────────────────────┘
```

Single compiled artefact: **`libwdmm_ffi.so`** (arm64-v8a + x86_64).
No separate binaries for the Flutter app path.

---

## Crates

| Crate | Role |
|---|---|
| `wdmm-core` | Shared models (LibraryTrack, TranscodePreset, …), TaskQueue, SyncEngine |
| `wdmm-storage` | LibraryDatabase — SQLite v12 (tracks, accounts, presets, media-links, KV) |
| `wdmm-drivers` | WdmmVfs driver trait + 9 impls (WebDAV, OneDrive, GDrive, …, Crypt wrapper) |
| `wdmm-ffmpeg` | Hand-rolled FFmpeg 7.1 FFI; probe + open_job (remux-first, then transcode); 5 built-in presets |
| `wdmm-proxy` | Axum HTTP: stream proxy (Range/206/416), HLS serve, DLNA push proxy |
| `wdmm-openapi` | Axum REST API (loopback): /v1/library, /v1/playlists, /v1/tasks, /v1/token, /v1/media/link |
| `wdmm-ffi` | C ABI boundary; owns singletons: LIBRARY_DB, QUEUE, PROXY, API_SERVER, TOKEN_FILE_PATH |

---

## Key data-flow paths

### HLS / DLNA cast

```
Dart HLS button
  -> wdmm_proxy_register_hls(device_id, input_url, preset_id)
       -> storage.get_transcode_preset(preset_id)
       -> wdmm-proxy.register_hls(device_id, input_url, preset)
            -> wdmm-ffmpeg.open_job(input_url, preset, segment_dir)
                 remux path:    avformat copy -> HLS segments
                 transcode path: decode -> sws/swr -> encode -> HLS segments
       -> returns {token, playlist_url}
  -> DLNA SetAVTransportURI(playlist_url)   <- renderer pulls HLS
```

### Media link (direct / proxy)

```
OpenAPI POST /v1/media/link {account_id, remote_path, mode}
  -> MediaLinkFn callback (wdmm-ffi)
       direct: driver.get(remote_path) -> {raw_url, raw_headers} -> MediaLinkResponse
       proxy:  driver.get() for size -> proxy.register_driver(ranges_fn) -> stable /s/{token} URL
  -> media_links DB row (kind, proxy_token, expires_at)
  -> response {kind, url, headers, expires_at}
```

### Cloud file I/O

```
Any file operation
  -> WdmmVfs.{list,get,put,mkdir,remove}
       -> DriverRegistry::create_driver(account_id)
            -> concrete impl: WebDav | OneDrive | ...
                 Crypt wrapper: LocalStream (MustProxy) — never returns raw_url
```

---

## DB schema (wdmm-storage v12)

| Table | Purpose |
|---|---|
| library_tracks | Track metadata + cover hash |
| library_albums, library_artists | Derived from tracks |
| cloud_accounts | Account credentials (encrypted) |
| library_playlists, playlist_entries | User playlists |
| task_queue | Download / upload jobs |
| kv_store | App settings, sentinels |
| transcode_presets | 5 built-in + user-defined FFmpeg profiles |
| media_links | Short-lived direct/proxy media URLs; TTL + revoke |
| dmr_prefs | DLNA renderer preferences (separate dmr_prefs.db) |

Migration: incremental INSERT INTO _schema_version pattern; fresh-schema executes full DDL directly.

---

## Startup sequence

1. **core-init** — getApplicationDocumentsDirectory() -> wdmm_library_init(wdmm_library.db, token_dir) — opens on-disk SQLite, seeds schema if new, sets TOKEN_FILE_PATH = <db_dir>/api-token.
2. **settings** — first KV read via wdmm_kv_get.
3. **dmr-prefs** — wdmm_dmr_prefs_init(dmr_prefs.db).
4. **proxy** — wdmm_proxy_start(port, bind_mode) (loopback or LAN).
5. **openapi** — wdmm_openapi_start(port) — resolves token (file -> KV -> new UUID); binds loopback.
6. **library / accounts / queue** — standard Flutter service init.
7. **sqflite-import** — one-shot idempotent migration (sentinel-gated).

---

## Constraints and invariants

- **No :memory: in production.** All DB ops use the on-disk wdmm_library.db. Tests may use :memory:.
- **One WdmmVfs trait.** No VirtualFs, ObjectFs, or RemoteStore alias. Engines take Arc<dyn WdmmVfs>.
- **Sync FFI takes account_id + remote_dir, never url/user/pass.** Driver construction is internal to DriverRegistry.
- **Crypt content is LocalStream (MustProxy).** Never returns a plaintext raw_url; always flows through wdmm-proxy.
- **Media bytes go through /v1/media/link.** Dart must not splice upstream raw_url / raw_headers into the player or DLNA renderer directly.
- **No FFmpeg nonfree.** --enable-nonfree is forbidden in all build scripts (GPL compliance).
- **NDK r28+.** Android builds require NDK >= r28 for 16 KB page alignment.
- **armeabi-v7a unsupported.** Only arm64-v8a + x86_64 are supported (FFmpeg LP64 FFI).

---

## CI guard jobs (.github/workflows/verify.yml)

| Job | Key checks |
|---|---|
| dart | dart analyze --fatal-infos, dart test, naming guard (I9), platform dep guard (I10), grep whitelist, :memory: guard, media-link guard |
| rust | cargo clippy -D warnings, cargo test (storage/core/openapi), :memory: Rust guard, FFI symbol alignment, FFmpeg compliance |
| abi | jniLibs structure, NDK >= r28 pin |
| openapi-smoke | cargo test -p wdmm-openapi, token file + loopback bind static check |
