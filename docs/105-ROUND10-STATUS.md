# Round 10 Status

## SHAs at round start

| Repo | Branch | SHA |
|------|--------|-----|
| WDMM-core | main | `57672bf` (Round 9 tag) |
| WDMM-desktop | main | `2543674` (submodule pin 57672bf) |
| Webdav_Media_Manager | refactor/rust-core | `10fd99e` (submodule pin 57672bf) |

## What landed (Round 10)

| # | Item | File(s) | Notes |
|---|------|---------|-------|
| 1 | **Baidu write ops** — `mkdir`, `rename`, `remove` | `crates/wdmm-drivers/src/baidu.rs` | POST form-encoded via `/rest/2.0/xpan/file?method={create,rename,delete}`; `access_token` as query param. |
| 2 | **Baidu write-op mock tests** | same | 6 new tests: `mkdir_succeeds`, `mkdir_maps_errno_to_auth_error`, `rename_succeeds`, `rename_empty_new_name_is_config_error`, `remove_succeeds`, `remove_maps_errno_to_network_error`. |
| 3 | **123 Pan write ops** — `mkdir`, `rename`, `remove` | `crates/wdmm-drivers/src/pan123.rs` | JSON POST via `/api/v1/upload/mkdir`, `/api/v1/file/rename`, `/api/v1/file/trash`; resolves path → fileId before POST. |
| 4 | **123 Pan write-op mock tests** | same | 7 new tests: `mkdir_root_level`, `mkdir_empty_name_is_config_error`, `mkdir_maps_auth_code`, `rename_root_file`, `rename_empty_new_name_is_config_error`, `remove_root_file`, `remove_maps_not_found`. |
| 5 | **API.md updated** | `crates/wdmm-drivers/docs/API.md` | `BaiduDriver` and `Pan123Driver` entries now document the three write ops each. |
| 6 | **This status doc** | `docs/105-ROUND10-STATUS.md` | — |

## Test counts

| Crate | Round 9 | Round 10 | Δ |
|-------|---------|---------|---|
| wdmm-drivers | 77 | 90 | +13 |
| wdmm-dlna / wdmm-proxy | 9 | 9 | — |
| wdmm-storage | 5 | 5 | — |
| wdmm-sync | 10 | 10 | — |
| wdmm-openapi | 15 | 15 | — |
| wdmm-queue | 9 | 9 | — |
| wdmm-ffi | 4 | 4 | — |
| wdmm-platform | 8 | 8 | — |
| **workspace total** | **150** | **163** | **+13** |

All 163 tests green, 0 failed, 1 ignored (pre-existing).

## Remaining parity gaps

| Item | Priority | Blocker |
|------|----------|---------|
| Flip `kRustLibrary*` / `kRustQueueEnabled` / `kRustProxyEnabled` defaults to `true` in desktop | P1 | Requires device smoke test on user's machine — **not flipped this round** |
| Delete Dart SQLite DB + DB migration to rusqlite | P1 | Coordinated cut-over; not this round |
| Delete Dart drivers (CloudDriver Dart impls) | P1 | After Rust drivers verified on device |
| Delete `LocalStreamBridge` (Dart) | P1 | After proxy verified on device |
| Terabox driver | blocked | Upstream API unstable |
| Netease Cloud Music driver | excluded | Policy decision |
| Dual-write probe logging helper (runtime) | P2 optional | No blocker; deferred |
| `Tasks` / settings copy for device smoke of Round 9 flags | P2 optional | No blocker; deferred |
| crates.io publish | deferred | Policy decision (constraints §5) |
| Manga support | out-of-scope | — |
