# WDMM Architecture

> Stub — expanded incrementally per batch.

## Layers

| Layer | Authority | Notes |
|-------|-----------|-------|
| WDMM-VFS | Rust `wdmm-ffi` / Core DB | Unique virtual file layer; cloud I/O goes through here |
| Library DB | `wdmm_library.db` (Core) | Single source of truth for tracks/artists/albums/playlists after B0 |
| DMR prefs DB | `dmr_prefs.db` (Core) | Independent USN-keyed renderer preferences |
| KV store | Library DB (Core) | App settings, sentinels, last-rev; requires `wdmm_library_init` before first read |

## Startup sequence (post-B0)

1. `core-init` — `getApplicationDocumentsDirectory()` → `wdmm_library_init(wdmm_library.db)`
2. `settings` — first KV read now hits real DB (not `:memory:`)
3. `databases` — sqflite playlists + task queue
4. `cache`
5. `dmr-prefs` — `wdmm_dmr_prefs_init(dmr_prefs.db)`
6. `sqflite-import` — one-shot migration (idempotent via KV sentinel)
7. `library`, `user-folders`, `manga-library`, `accounts`
