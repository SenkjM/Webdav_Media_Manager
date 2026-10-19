# CtFile (城通网盘) Driver Reference

**Authoritative spec**: `/workspace/saf_work/ctfile-wdmm-spec.md`  
**Worker reference**: `localdev/OpenList-Worker/src/backend/drivers/ctfile/`

This document captures ctfile-specific implementation details and maintenance notes for WDMM contributors.

---

## 1. Authentication

**Session-only (OpenAPI token).**

- User generates session token from CtFile backend admin panel: **开放接口登录密钥管理** (Open API session management).
- No OAuth, no client password login.
- Session stored in `addition.session` (marked `obscure: true` in form schema).
- Token expiration: API returns `code: 401` → clear error message directs user to regenerate token.

**No automatic token rotation**: `CtFileSpec.runtimeSecretKeys` is empty. Session persists until user regenerates in backend.

---

## 2. API Behavior & Quirks

### 2.1 Id-prefix dual strategy

**Folder ids** are d-prefixed (e.g., `d123`); **file ids** are f-prefixed (e.g., `f456`). Some endpoints accept stripped ids (`123`), others require prefixed (`d123`).

**Worker pattern**: `callWithId` with `prefer: 'raw'` or `prefer: 'stripped'` — tries primary format first, on 400/404 retries secondary.

- `folder/meta`: prefer `raw` (d-prefixed).
- `file/meta`, `file/fetch_url`: prefer `stripped` (no prefix).
- `callWithIds` (move/delete): tries comma-string first, on 400/404/405 retries array.

**WDMM impl**: `CtFileClient._callWithId` and `_callWithIds` encode this; driver methods call client with locked preference. Do not expose both to driver-level retry.

### 2.2 Upload flow

1. **Ticket init**: POST `/public/file/upload` with `checksum` (format `md5hex-bytesize`, e.g., `d41d8cd...6f-1024`).
2. **Instant upload check**: if `exists > 0` in response, file already uploaded → done.
3. **Presigned URL**: extract `upload_url` from ticket.
4. **Multipart POST**: send file as `multipart/form-data` with fields `name`, `filesize`, `file`.

**WDMM pattern**: `uploadStream` buffers full stream to compute md5-size; no true streaming upload (API constraint).

### 2.3 mkdir 403 = success

**POST `/folder/create`** returns `code: 403` if folder already exists, **but** response includes `folder_id` — treat as success, return folder_id.

### 2.4 Pagination

**POST `/file/list`** with `start` offset. No explicit page-size param (API decides chunk size).

**Loop termination**:  
- Empty `results[]` → end.  
- Or `results[0].key` identical to previous page's first key → stuck (API bug when file count exactly divisible by chunk size).

Guard: `kMaxListPages = 500` hard cap.

### 2.5 Retry & error handling

- **401**: session expired → throw clear message (no retry).
- **429**, **5xx**: retry up to 3 times with backoff (`300ms * retry`).
- **400/404** on id-based calls: retry with alternate id format.
- All other non-200 codes: throw `CloudDriverException`.

**POST-only API**: all business endpoints are POST with JSON body (session included in every request).

---

## 3. Path→id cache

**Driver-local map** `_pathCache: Map<String, String>` caches resolved folder ids (d-prefixed keys stored).

- Cleared on any mutation (`mkdir`, `rename`, `move`).
- Cache keys are normalized paths (`/a/b/c`).
- Root folder: id `"0"` (also accepts `"d0"`).

**ensureDirectory**: incremental mkdir + cache build (one pass).

---

## 4. Capabilities

```dart
list | read | mkdir | move | copy | delete | write
```

**Copy** declared but throws `CloudDriverException` (OpenAPI does not provide copy endpoint). Declared to match Worker behavior; UI may show copy option but will fail with clear error.

---

## 5. L10n

**zh**: `driverNameCtFile`: `"城通网盘"`  
**zh_TW**: `"城通網盤"`  
**en**: `"CtFile"`

**Session hint** (all locales): directs to backend admin panel, references OpenList docs (ctfile driver page).

---

## 6. Form schema

1. **session** (string, required, obscure):  
   OpenAPI token from backend 开放接口登录密钥管理.

2. **cloud_type** (select, default `public`):  
   - `public`: 公有云  
   - `private`: 私有云  
   Determines API path prefix (`/public/...` vs `/private/...`).

**Advanced fields** (not exposed in WDMM form, kept for Worker alignment):  
- `base_url`, `order_by`, `order_direction`, `user_agent` — retained in `CtFileAddition` for future extensibility.

---

## 7. Testing

**Unit test**: `test/ctfile_driver_test.dart`

- Dio mock adapter + local HttpServer.
- Validates: session auth, 401 handling, id-prefix fallback, upload checksum, mkdir 403+folder_id, list merge+pagination.

**Secret scope test**: `test/driver_secret_scope_test.dart`

- Verifies `runtimeSecretKeys` empty, `secretFieldKeys = ['session']`.

**Run**: `flutter test test/ctfile_driver_test.dart` (requires Flutter SDK in environment).

---

## 8. Maintenance notes

- **No breaking changes to Worker API patterns**: WDMM driver must stay compatible with Worker's OpenAPI contract (id-prefix strategies, upload flow, 403-mkdir).
- **Do not expose path-based API**: CtFile OpenAPI is id-based only; WDMM driver synthesizes path→id resolution internally. WebDAV layer above driver handles path translation.
- **No client password login**: spec explicitly forbids crack/client login. Only session auth is supported.

---

## 9. Registry

**File**: `lib/services/cloud_drivers/driver_registry.dart`  
**Entry**: `CtFileSpec()` inserted before `CryptSpec()` (crypt always last).

**Removal test** (if driver is ever deprecated):  
```bash
git rm lib/services/cloud_drivers/ctfile_driver.dart
# Remove CtFileSpec line + import from driver_registry.dart
flutter analyze lib  # Must pass with zero errors
```

---

## 10. References

- Worker impl: `localdev/OpenList-Worker/src/backend/drivers/ctfile/{driver,util,types}.ts`
- Worker tests: `localdev/OpenList-Worker/src/backend/drivers/ctfile/util.test.ts`
- WDMM porting guide: `docs/11-CLOUD-DRIVER-PORTING.md`
- Spec: `/workspace/saf_work/ctfile-wdmm-spec.md`
