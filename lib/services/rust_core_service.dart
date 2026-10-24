// ignore_for_file: unused_element, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ── FFI typedefs ─────────────────────────────────────────────────────────────

typedef _VersionNative = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

typedef _QueueStatusNative = ffi.Pointer<Utf8> Function();
typedef _QueueStatusDart = ffi.Pointer<Utf8> Function();

typedef _IntResultNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _IntResultDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _IntNative = ffi.Int32 Function();
typedef _IntDart = int Function();

typedef _OpenApiStartNative = ffi.Pointer<Utf8> Function(ffi.Uint16);
typedef _OpenApiStartDart = ffi.Pointer<Utf8> Function(int);

typedef _CryptoEncryptNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _CryptoEncryptDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>, int);

typedef _TwoStrToOneStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _TwoStrToOneStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _FourStrToOneStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _FourStrToOneStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _Uint32ToStrNative = ffi.Pointer<Utf8> Function(ffi.Uint32);
typedef _Uint32ToStrDart = ffi.Pointer<Utf8> Function(int);

typedef _OneStrToStrNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _OneStrToStrDart   = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _NoArgToStrNative  = ffi.Pointer<Utf8> Function();
typedef _NoArgToStrDart    = ffi.Pointer<Utf8> Function();

typedef _ProxyStartNative = ffi.Pointer<Utf8> Function(ffi.Uint16);
typedef _ProxyStartDart   = ffi.Pointer<Utf8> Function(int);
typedef _ProxyNoArgStrNative = ffi.Pointer<Utf8> Function();
typedef _ProxyNoArgStrDart   = ffi.Pointer<Utf8> Function();
typedef _ProxyPortNative  = ffi.Int32 Function();
typedef _ProxyPortDart    = int Function();
typedef _ProxyTwoStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _ProxyTwoStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

/// Rust FFI bridge to WDMM-core via wdmm-ffi.
///
/// Dart services remain **source of truth** until the full DB cutover in
/// round 4. This service is called at app startup for a debug smoke-test log
/// only; no Dart service is replaced yet.
///
/// Build: cargo-ndk builds `libwdmm_ffi.so` into
/// `android/app/src/main/jniLibs/<abi>/` before the Flutter build runs.
/// See android/app/build.gradle.kts for the hook comment.
class RustCoreService {
  static ffi.DynamicLibrary? _lib;
  static bool _loadFailed = false;

  // ── Library loading ──────────────────────────────────────────────────────

  /// Load the native library once.  Returns null on any platform where the
  /// library is not yet available (e.g. debug host runs on macOS/Linux).
  static ffi.DynamicLibrary? get _tryLib {
    if (_loadFailed) return null;
    if (_lib != null) return _lib!;
    try {
      if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libwdmm_ffi.so');
      } else {
        // Not Android — library not shipped for this platform yet.
        return null;
      }
    } catch (e) {
      _loadFailed = true;
      debugPrint('[RustCore] library load failed (non-fatal): $e');
      return null;
    }
    return _lib!;
  }

  // ── FFI bindings ─────────────────────────────────────────────────────────

  static _FreeStringDart? _freeString;
  static _VersionDart? _version;
  static _QueueStatusDart? _queueStatus;
  static _IntResultDart? _queueCancel;
  static _IntDart? _queuePendingCount;
  static _OpenApiStartDart? _openApiStart;
  static _FreeStringDart? _openApiStop;
  static _IntDart? _openApiIsRunning;
  static _IntDart? _openApiPort;

  // ── Round 4 FFI binding types ──────────────────────────────────────────────

  static _CryptoEncryptDart? _cryptoEncrypt;
  static _TwoStrToOneStrDart? _cryptoDecrypt;
  static _FourStrToOneStrDart? _syncTrigger;
  static _Uint32ToStrDart? _dlnaDiscover;
  static _TwoStrToOneStrDart? _dlnaCast;
  static _VersionDart? _tokenGet; // no-arg → Utf8, same shape as version
  static _VersionDart? _tokenRotate; // no-arg → Utf8

  static void _loadSymbols(ffi.DynamicLibrary lib) {
    _freeString = lib
        .lookup<ffi.NativeFunction<_FreeStringNative>>('wdmm_ffi_free_string')
        .asFunction();
    _version = lib
        .lookup<ffi.NativeFunction<_VersionNative>>('wdmm_version')
        .asFunction();
    _queueStatus = lib
        .lookup<ffi.NativeFunction<_QueueStatusNative>>('wdmm_queue_status_json')
        .asFunction();
    _queueCancel = lib
        .lookup<ffi.NativeFunction<_IntResultNative>>('wdmm_queue_cancel')
        .asFunction();
    _queuePendingCount = lib
        .lookup<ffi.NativeFunction<_IntNative>>('wdmm_queue_pending_count')
        .asFunction();
    _openApiStart = lib
        .lookup<ffi.NativeFunction<_OpenApiStartNative>>('wdmm_openapi_start')
        .asFunction();
    _openApiStop = lib
        .lookup<ffi.NativeFunction<_FreeStringNative>>('wdmm_openapi_stop')
        .asFunction();
    _openApiIsRunning = lib
        .lookup<ffi.NativeFunction<_IntNative>>('wdmm_openapi_is_running')
        .asFunction();
    _openApiPort = lib
        .lookup<ffi.NativeFunction<_IntNative>>('wdmm_openapi_port')
        .asFunction();
    // Round 4 exports
    _cryptoEncrypt = lib
        .lookup<ffi.NativeFunction<_CryptoEncryptNative>>('wdmm_crypto_encrypt')
        .asFunction();
    _cryptoDecrypt = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_crypto_decrypt')
        .asFunction();
    _syncTrigger = lib
        .lookup<ffi.NativeFunction<_FourStrToOneStrNative>>('wdmm_sync_trigger')
        .asFunction();
    _dlnaDiscover = lib
        .lookup<ffi.NativeFunction<_Uint32ToStrNative>>('wdmm_dlna_discover_json')
        .asFunction();
    _dlnaCast = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_dlna_cast')
        .asFunction();
    _tokenGet = lib
        .lookup<ffi.NativeFunction<_VersionNative>>('wdmm_token_get')
        .asFunction();
    _tokenRotate = lib
        .lookup<ffi.NativeFunction<_VersionNative>>('wdmm_token_rotate')
        .asFunction();
  }

  static bool _symbolsLoaded = false;

  static bool _ensureSymbols() {
    if (_symbolsLoaded) return true;
    final lib = _tryLib;
    if (lib == null) return false;
    try {
      _loadSymbols(lib);
      _symbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] symbol lookup failed: $e');
      return false;
    }
    return true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _readAndFreeString(ffi.Pointer<Utf8> ptr) {
    final s = ptr.toDartString();
    _freeString?.call(ptr);
    return s;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns WDMM core version, or null if the library is not available.
  static String? getVersion() {
    if (!_ensureSymbols()) return null;
    return _readAndFreeString(_version!());
  }

  /// Returns queue tasks as a JSON string, or '[]' if library unavailable.
  static String getQueueStatusJson() {
    if (!_ensureSymbols()) return '[]';
    return _readAndFreeString(_queueStatus!());
  }

  /// Cancel a queue task by id. Returns 'ok' or an error message.
  static String cancelTask(String taskId) {
    if (!_ensureSymbols()) return 'library not available';
    return taskId.toNativeUtf8().let((ptr) {
      final result = _readAndFreeString(_queueCancel!(ptr));
      calloc.free(ptr);
      return result;
    });
  }

  /// Number of pending queue tasks.
  static int queuePendingCount() {
    if (!_ensureSymbols()) return 0;
    return _queuePendingCount!();
  }

  /// Start the OpenAPI server on the given port (0 = OS-assigned).
  /// Returns the bearer token on success or an error message.
  /// Dart services remain source of truth — this is for external clients only.
  static String startOpenApi({int port = 0}) {
    if (!_ensureSymbols()) return 'library not available';
    return _readAndFreeString(_openApiStart!(port));
  }

  /// Stop the OpenAPI server.
  static void stopOpenApi() {
    if (!_ensureSymbols()) return;
    final ptr = _openApiStop as ffi.Pointer<Utf8> Function()?;
    // openapi_stop returns FfiString — free it
    final lib = _tryLib;
    if (lib == null) return;
    final stopFn = lib
        .lookup<ffi.NativeFunction<_QueueStatusNative>>('wdmm_openapi_stop')
        .asFunction<_QueueStatusDart>();
    _readAndFreeString(stopFn());
  }

  /// Returns true if the OpenAPI server is running.
  static bool isOpenApiRunning() {
    if (!_ensureSymbols()) return false;
    return _openApiIsRunning!() == 1;
  }

  /// Returns the port the OpenAPI server is bound to, or -1 if not running.
  static int openApiPort() {
    if (!_ensureSymbols()) return -1;
    return _openApiPort!();
  }

  // ── Startup smoke-test ────────────────────────────────────────────────────

  /// Call once at app startup (debug builds only). Logs the core version.
  /// Never throws; any failure is swallowed with a debug log.
  static void debugLogVersion() {
    if (!kDebugMode) return;
    try {
      final v = getVersion();
      if (v != null) {
        debugPrint('[RustCore] wdmm-core version: $v');
      } else {
        debugPrint('[RustCore] library not available on this platform/build');
      }
    } catch (e) {
      debugPrint('[RustCore] startup probe failed (non-fatal): $e');
    }
  }

  // ── Round 4 — Crypto FFI probes ────────────────────────────────────────────
  //
  // Dart services are still the source of truth for encryption.  These are
  // **parallel FFI probes**: they run alongside the Dart vault, so you can
  // compare outputs before cutover.  Guarded by `kDebugMode` in the caller.

  /// Encrypt [plaintext] bytes with [passphrase] via the Rust AES-256-GCM
  /// vault.  Returns base64-encoded ciphertext, or 'error:...' on failure.
  /// Returns null if the native library is not available.
  ///
  /// Dart `CredentialVaultService` remains source of truth until cutover.
  static String? cryptoEncrypt(String passphrase, Uint8List plaintext) {
    if (!_ensureSymbols() || _cryptoEncrypt == null) return null;
    final passPtr = passphrase.toNativeUtf8();
    final dataPtr = calloc<ffi.Uint8>(plaintext.length);
    try {
      for (var i = 0; i < plaintext.length; i++) {
        dataPtr[i] = plaintext[i];
      }
      final result = _readAndFreeString(_cryptoEncrypt!(passPtr, dataPtr, plaintext.length));
      return result;
    } finally {
      calloc.free(passPtr);
      calloc.free(dataPtr);
    }
  }

  /// Decrypt base64-encoded [ciphertext] with [passphrase] via the Rust vault.
  /// Returns plaintext string, or 'error:...' on failure.
  /// Returns null if the native library is not available.
  ///
  /// Dart `CredentialVaultService` remains source of truth until cutover.
  static String? cryptoDecrypt(String passphrase, String ciphertextB64) {
    if (!_ensureSymbols() || _cryptoDecrypt == null) return null;
    final passPtr = passphrase.toNativeUtf8();
    final dataPtr = ciphertextB64.toNativeUtf8();
    try {
      return _readAndFreeString(_cryptoDecrypt!(passPtr, dataPtr));
    } finally {
      calloc.free(passPtr);
      calloc.free(dataPtr);
    }
  }

  // ── Round 4 — Sync FFI probe ───────────────────────────────────────────────

  /// Trigger a Rust sync run (credentials + library + playlists).
  ///
  /// Returns a JSON summary string on success or 'error:...' on failure.
  /// Returns null if the native library is not available.
  ///
  /// **Feature flag**: only call this if the feature flag
  /// `kRustSyncEnabled` is true (not yet wired to UI; defaults to false).
  /// Dart sync services remain source of truth until the feature flag is
  /// flipped for release.
  static String? syncTrigger({
    required String webdavUrl,
    required String username,
    required String password,
    String remoteDir = '/wdmm_sync',
  }) {
    if (!_ensureSymbols() || _syncTrigger == null) return null;
    final urlPtr = webdavUrl.toNativeUtf8();
    final userPtr = username.toNativeUtf8();
    final passPtr = password.toNativeUtf8();
    final dirPtr = remoteDir.toNativeUtf8();
    try {
      return _readAndFreeString(_syncTrigger!(urlPtr, userPtr, passPtr, dirPtr));
    } finally {
      calloc.free(urlPtr);
      calloc.free(userPtr);
      calloc.free(passPtr);
      calloc.free(dirPtr);
    }
  }

  // ── Round 4 — DLNA FFI probes ─────────────────────────────────────────────

  /// Discover DLNA renderers via SSDP.
  ///
  /// Returns a JSON array of renderer objects or 'error:...' on failure.
  /// Returns null if the native library is not available.
  ///
  /// **Parallel probe**: Dart `DlnaCastService` remains source of truth;
  /// compare outputs before cutover.
  static String? dlnaDiscover({int timeoutMs = 2000}) {
    if (!_ensureSymbols() || _dlnaDiscover == null) return null;
    return _readAndFreeString(_dlnaDiscover!(timeoutMs));
  }

  /// Cast [mediaUrl] to the renderer at [rendererLocation] via AVTransport SOAP.
  ///
  /// Returns 'ok' on success or 'error:...' on failure.
  /// Returns null if the native library is not available.
  ///
  /// **Parallel probe**: Dart `DlnaCastService` remains source of truth.
  static String? dlnaCast(String rendererLocation, String mediaUrl) {
    if (!_ensureSymbols() || _dlnaCast == null) return null;
    final locPtr = rendererLocation.toNativeUtf8();
    final urlPtr = mediaUrl.toNativeUtf8();
    try {
      return _readAndFreeString(_dlnaCast!(locPtr, urlPtr));
    } finally {
      calloc.free(locPtr);
      calloc.free(urlPtr);
    }
  }

  // ── Round 4 — Token FFI ───────────────────────────────────────────────────

  /// Get the current OpenAPI bearer token.
  ///
  /// Returns the token string, or '' if the server is not running.
  /// Returns null if the native library is not available.
  /// Native UI may display this token per constraints §2.
  static String? tokenGet() {
    if (!_ensureSymbols() || _tokenGet == null) return null;
    return _readAndFreeString(_tokenGet!());
  }

  /// Rotate the OpenAPI bearer token.  The old token is immediately
  /// invalidated.  Returns the new token, or 'error:...' on failure.
  /// Returns null if the native library is not available.
  static String? tokenRotate() {
    if (!_ensureSymbols() || _tokenRotate == null) return null;
    return _readAndFreeString(_tokenRotate!());
  }

  // ── Round 6 — Library FFI bindings ────────────────────────────────────────
  //
  // These bindings talk to the Rust library DB (rusqlite) via the wdmm-ffi
  // exports landed in Round 5.  The Dart sqflite DB is NOT deleted yet —
  // this is the coexistence / dual-read probe phase.

  static _OneStrToStrDart? _libraryInit;
  static _OneStrToStrDart? _trackUpsert;
  static _OneStrToStrDart? _trackGet;
  static _NoArgToStrDart?  _trackList;
  static _OneStrToStrDart? _trackSearch;
  static _OneStrToStrDart? _trackDelete;
  static _OneStrToStrDart? _libraryImport;

  static void _loadLibrarySymbols(ffi.DynamicLibrary lib) {
    _libraryInit = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_library_init')
        .asFunction();
    _trackUpsert = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_track_upsert')
        .asFunction();
    _trackGet = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_track_get')
        .asFunction();
    _trackList = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_track_list')
        .asFunction();
    _trackSearch = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_track_search')
        .asFunction();
    _trackDelete = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_track_delete')
        .asFunction();
    _libraryImport = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_library_import_from_sqflite')
        .asFunction();
  }

  // ── Round 6 — Library public API ──────────────────────────────────────────

  /// Initialise the Rust library DB at [dbPath].
  ///
  /// Must be called once at app startup before any other library FFI calls.
  /// Idempotent — safe to call multiple times (subsequent calls are no-ops in
  /// Rust since the DB is a global singleton).
  ///
  /// Returns 'ok' on success, 'error:...' on failure, or null if library
  /// unavailable.
  static String? libraryInit(String dbPath) {
    if (!_ensureSymbols()) return null;
    if (_libraryInit == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryInit == null) return null;
    }
    final pathPtr = dbPath.toNativeUtf8();
    try {
      return _readAndFreeString(_libraryInit!(pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Upsert a track into the Rust library DB.
  ///
  /// [json] must be a JSON object matching the LibraryTrack schema.
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  ///
  /// **Dart sqflite DB is still the source of truth** — do not remove Dart
  /// calls yet.  This is a parallel write for the dual-read probe phase.
  static String? trackUpsert(String json) {
    if (!_ensureSymbols()) return null;
    if (_trackUpsert == null) {
      _loadLibrarySymbolsSafe();
      if (_trackUpsert == null) return null;
    }
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_trackUpsert!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Get a track by id from the Rust library DB.
  ///
  /// Returns the track as a JSON string, 'null' if not found, or
  /// 'error:...' on failure.  Returns null if library unavailable.
  static String? trackGet(String id) {
    if (!_ensureSymbols()) return null;
    if (_trackGet == null) {
      _loadLibrarySymbolsSafe();
      if (_trackGet == null) return null;
    }
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_trackGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List all tracks from the Rust library DB.
  ///
  /// Returns a JSON array string, or '[]' / 'error:...' on failure.
  /// Returns null if library unavailable.
  static String? trackList() {
    if (!_ensureSymbols()) return null;
    if (_trackList == null) {
      _loadLibrarySymbolsSafe();
      if (_trackList == null) return null;
    }
    return _readAndFreeString(_trackList!());
  }

  /// Search tracks by title/artist substring in the Rust library DB.
  ///
  /// Returns a JSON array string.  Returns null if library unavailable.
  static String? trackSearch(String query) {
    if (!_ensureSymbols()) return null;
    if (_trackSearch == null) {
      _loadLibrarySymbolsSafe();
      if (_trackSearch == null) return null;
    }
    final ptr = query.toNativeUtf8();
    try {
      return _readAndFreeString(_trackSearch!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Delete a track by id from the Rust library DB.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? trackDelete(String id) {
    if (!_ensureSymbols()) return null;
    if (_trackDelete == null) {
      _loadLibrarySymbolsSafe();
      if (_trackDelete == null) return null;
    }
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_trackDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Trigger a one-shot import from an old sqflite DB at [oldDbPath] into
  /// the Rust library DB.  Idempotent — the Rust side sets a KV flag
  /// `sqflite_imported = 1` after the first successful run and skips
  /// subsequent calls.
  ///
  /// Call this from a first-run migration helper, NOT on every app start.
  ///
  /// Returns a JSON summary:
  /// `{"already_done":false,"tracks":42,"playlists":3,"entries":120}`
  /// or 'error:...' on failure.  Returns null if library unavailable.
  static String? libraryImportFromSqflite(String oldDbPath) {
    if (!_ensureSymbols()) return null;
    if (_libraryImport == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryImport == null) return null;
    }
    final ptr = oldDbPath.toNativeUtf8();
    try {
      return _readAndFreeString(_libraryImport!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── private: lazy library symbol loader ───────────────────────────────────

  static bool _librarySymbolsLoaded = false;

  /// Load Round 6 library symbols lazily.  No-op if already loaded or if the
  /// native library is unavailable.  Swallows errors so callers can check for
  /// null function pointers instead of catching.
  static void _loadLibrarySymbolsSafe() {
    if (_librarySymbolsLoaded) return;
    final lib = _tryLib;
    if (lib == null) return;
    try {
      _loadLibrarySymbols(lib);
      _librarySymbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] library symbol lookup failed (non-fatal): $e');
    }
  }

  // ── Round 7 — Queue enqueue FFI ───────────────────────────────────────────
  //
  // Wires to `wdmm_queue_enqueue` added in Round 7. Gated by
  // [kRustQueueEnabled] in rust_queue_bridge.dart — default `false` so the
  // Dart TaskQueueService remains the live download engine.

  static _OneStrToStrDart? _queueEnqueue;
  static bool _queueSymbolsLoaded = false;

  static void _loadQueueSymbolsSafe() {
    if (_queueSymbolsLoaded) return;
    final lib = _tryLib;
    if (lib == null) return;
    try {
      _queueEnqueue = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_queue_enqueue')
          .asFunction();
      _queueSymbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] queue symbol lookup failed (non-fatal): $e');
    }
  }

  /// Enqueue a download task in the Rust SerialPump.
  ///
  /// [taskJson] must be a JSON object with at minimum `"id"` and `"kind"`.
  /// Returns `'ok'` on success, `'error:…'` on failure, or `null` if the
  /// native library is unavailable.
  ///
  /// This is the backing call for [RustQueueBridge.enqueue]. Do not call
  /// directly — use [RustQueueBridge] which enforces the feature flag.
  static String? queueEnqueue(String taskJson) {
    if (!_ensureSymbols()) return null;
    _loadQueueSymbolsSafe();
    if (_queueEnqueue == null) return null;
    final ptr = taskJson.toNativeUtf8();
    try {
      return _readAndFreeString(_queueEnqueue!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }
  // ── Round 9 — Proxy FFI ───────────────────────────────────────────────────
  //
  // Thin Dart bindings for the wdmm_proxy_* exports added in the proxy-extract
  // round. Gated by `kRustProxyEnabled` in rust_proxy_bridge.dart (default
  // false). Do NOT delete LocalStreamBridge yet.

  static _ProxyStartDart?   _proxyStart;
  static _ProxyNoArgStrDart? _proxyStop;
  static _ProxyPortDart?    _proxyPort;
  static _ProxyTwoStrDart?  _proxyRegisterFile;
  static _OneStrToStrDart?  _proxyUnregister;

  static bool _proxySymbolsLoaded = false;

  static void _loadProxySymbolsSafe() {
    if (_proxySymbolsLoaded) return;
    final lib = _tryLib;
    if (lib == null) return;
    try {
      _proxyStart = lib
          .lookup<ffi.NativeFunction<_ProxyStartNative>>('wdmm_proxy_start')
          .asFunction();
      _proxyStop = lib
          .lookup<ffi.NativeFunction<_ProxyNoArgStrNative>>('wdmm_proxy_stop')
          .asFunction();
      _proxyPort = lib
          .lookup<ffi.NativeFunction<_ProxyPortNative>>('wdmm_proxy_port')
          .asFunction();
      _proxyRegisterFile = lib
          .lookup<ffi.NativeFunction<_ProxyTwoStrNative>>('wdmm_proxy_register_file')
          .asFunction();
      _proxyUnregister = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_proxy_unregister')
          .asFunction();
      _proxySymbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] proxy symbol lookup failed (non-fatal): $e');
    }
  }

  /// Start the local HTTP proxy on `127.0.0.1` at [port] (0 = OS-assigned).
  ///
  /// Returns the bound port as a decimal string, or `'error:…'` on failure.
  /// Idempotent — if already running, returns the existing port.
  /// Returns null if the native library is unavailable.
  ///
  /// Do NOT call directly — use [RustProxyBridge] which enforces the flag.
  static String? proxyStart({int port = 0}) {
    if (!_ensureSymbols()) return null;
    _loadProxySymbolsSafe();
    if (_proxyStart == null) return null;
    return _readAndFreeString(_proxyStart!(port));
  }

  /// Stop the local HTTP proxy. No-op if not running.
  /// Returns null if the native library is unavailable.
  static String? proxyStop() {
    if (!_ensureSymbols()) return null;
    _loadProxySymbolsSafe();
    if (_proxyStop == null) return null;
    return _readAndFreeString(_proxyStop!());
  }

  /// Returns the bound proxy port, or -1 if not running.
  static int proxyPort() {
    if (!_ensureSymbols()) return -1;
    _loadProxySymbolsSafe();
    if (_proxyPort == null) return -1;
    return _proxyPort!();
  }

  /// Register a local file with the proxy.
  ///
  /// [filePath] is the absolute path to the local file.
  /// [name] is an optional display name used for Content-Type guessing
  /// (e.g. `"movie.mp4"`); pass null to omit.
  ///
  /// Returns a JSON string:
  /// `{"token":"…","path_template":"/s/…","port":N}` or `'error:…'`.
  /// Build the URL as `http://127.0.0.1:{port}{path_template}`.
  /// Returns null if the library is unavailable.
  static String? proxyRegisterFile(String filePath, {String? name}) {
    if (!_ensureSymbols()) return null;
    _loadProxySymbolsSafe();
    if (_proxyRegisterFile == null) return null;
    final pathPtr = filePath.toNativeUtf8();
    // Pass null pointer for optional name.
    final namePtr = name != null ? name.toNativeUtf8() : ffi.nullptr.cast<Utf8>();
    try {
      return _readAndFreeString(_proxyRegisterFile!(pathPtr, namePtr));
    } finally {
      calloc.free(pathPtr);
      if (name != null) calloc.free(namePtr);
    }
  }

  /// Unregister a proxy token previously returned by [proxyRegisterFile].
  ///
  /// Returns `'ok'`, or null if the library is unavailable.
  static String? proxyUnregister(String token) {
    if (!_ensureSymbols()) return null;
    _loadProxySymbolsSafe();
    if (_proxyUnregister == null) return null;
    final ptr = token.toNativeUtf8();
    try {
      return _readAndFreeString(_proxyUnregister!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }
}

// ignore: avoid_classes_with_only_static_members
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

// ── Feature flags (Round 4 — not yet wired to UI) ───────────────────────────

/// When true, [RustCoreService.syncTrigger] is used alongside Dart sync.
/// Flip to true in a settings screen once the Rust sync path is validated.
// ignore: constant_identifier_names
const bool kRustSyncEnabled = true;
