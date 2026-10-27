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

typedef _StrStrToStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _StrStrToStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

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

typedef _ThreeStrToOneStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _ThreeStrToOneStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _Int32ToStrNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _Int32ToStrDart = ffi.Pointer<Utf8> Function(int);

typedef _Int64ToStrNative = ffi.Pointer<Utf8> Function(ffi.Int64);
typedef _Int64ToStrDart = ffi.Pointer<Utf8> Function(int);

typedef _FiveStrToOneStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _FiveStrToOneStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

// wdmm_sync_full(url, user, pass, dir, with_covers: c_int) → FfiString
typedef _FourStrOneIntToStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32);
typedef _FourStrOneIntToStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int);

// Wave D — wdmm_manga_set_progress(manga_id, page_index: i64)
typedef _StrInt64ToStrNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Int64);
typedef _StrInt64ToStrDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, int);

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

// ── R12 — Proxy stream callback + symbol typedefs ────────────────────────────

/// Native type of the Range callback passed to [wdmm_proxy_register_stream] and
/// [wdmm_proxy_renew_stream_callback].
///
/// Public so [RustProxyStreamBridge] can type its [NativeCallable] with it.
/// With Dart SDK >= 3.4, [NativeCallable.listener] supports non-void native
/// return types: the native thunk returns `0` for [Int32] immediately and posts
/// the Dart callback asynchronously to the isolate event queue.
typedef WdmmProxyRangeCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,                       // user_data  (opaque)
  ffi.Int64,                                   // start      (inclusive byte offset)
  ffi.Int64,                                   // end        (inclusive; -1 = EOF)
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,         // out_buf    (sync: fill via alloc_buf; async: leave null)
  ffi.Pointer<ffi.Size>,                       // out_len    (sync: fill; async: ignore)
  ffi.Uint64,                                  // request_id (pass to set_result on async path)
);

// wdmm_proxy_register_stream(size, name?, cb, user_data) → FfiString (JSON / error)
typedef _ProxyRegisterStreamNative = ffi.Pointer<Utf8> Function(
  ffi.Uint64,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef _ProxyRegisterStreamDart = ffi.Pointer<Utf8> Function(
  int,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

// wdmm_proxy_renew_stream_callback(token, cb, user_data) → FfiString
typedef _ProxyRenewStreamCbNative = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef _ProxyRenewStreamCbDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.NativeFunction<WdmmProxyRangeCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

// wdmm_proxy_stream_alloc_buf(len) → *mut u8
typedef _ProxyStreamAllocBufNative = ffi.Pointer<ffi.Uint8> Function(ffi.Size);
typedef _ProxyStreamAllocBufDart   = ffi.Pointer<ffi.Uint8> Function(int);

// wdmm_proxy_stream_free_buf(buf, len)
typedef _ProxyStreamFreeBufNative = ffi.Void Function(
    ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _ProxyStreamFreeBufDart   = void Function(
    ffi.Pointer<ffi.Uint8>, int);

// wdmm_proxy_stream_set_result(request_id, buf, len, status)
typedef _ProxyStreamSetResultNative = ffi.Void Function(
    ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Int32);
typedef _ProxyStreamSetResultDart   = void Function(
    int, ffi.Pointer<ffi.Uint8>, int, int);

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
  static _FourStrOneIntToStrDart? _syncFull;
  static _Uint32ToStrDart? _dlnaDiscover;
  static _TwoStrToOneStrDart? _dlnaCast;
  static _VersionDart? _tokenGet; // no-arg → Utf8, same shape as version
  static _VersionDart? _tokenRotate; // no-arg → Utf8
  static _OneStrToStrDart? _dmrPrefsInit;
  static _NoArgToStrDart? _dmrPrefsList;
  static _OneStrToStrDart? _dmrPrefsGet;
  static _OneStrToStrDart? _dmrPrefsUpsert;
  static _OneStrToStrDart? _dmrPrefsDelete;
  static _StrStrToStrDart? _coversConfigure;
  static _StrStrToStrDart? _backupCreate;
  static _StrStrToStrDart? _backupRestore;
  static _FiveStrToOneStrDart? _backupUpload;
  static _FourStrToOneStrDart? _backupList;
  static _FiveStrToOneStrDart? _backupDownloadRestore;

  // ── Wave C driver/account FFI ──────────────────────────────────────────────
  static _ThreeStrToOneStrDart? _driverList;
  static _ThreeStrToOneStrDart? _driverMkdir;
  static _FourStrToOneStrDart? _driverRename;
  static _ThreeStrToOneStrDart? _driverRemove;
  static _ThreeStrToOneStrDart? _driverGet;
  static _NoArgToStrDart? _accountList;
  static _OneStrToStrDart? _accountGet;
  static _OneStrToStrDart? _accountUpsert;
  static _OneStrToStrDart? _accountDelete;
  static _TwoStrToOneStrDart? _accountListDir;
  static _TwoStrToOneStrDart? _accountMkdir;
  static _ThreeStrToOneStrDart? _accountRename;
  static _TwoStrToOneStrDart? _accountRemove;
  static _TwoStrToOneStrDart? _accountGetEntry;

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
    _syncFull = lib
        .lookup<ffi.NativeFunction<_FourStrOneIntToStrNative>>('wdmm_sync_full')
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
    // Wave C driver/account FFI
    _driverList = lib
        .lookup<ffi.NativeFunction<_ThreeStrToOneStrNative>>('wdmm_driver_list')
        .asFunction();
    _driverMkdir = lib
        .lookup<ffi.NativeFunction<_ThreeStrToOneStrNative>>('wdmm_driver_mkdir')
        .asFunction();
    _driverRename = lib
        .lookup<ffi.NativeFunction<_FourStrToOneStrNative>>('wdmm_driver_rename')
        .asFunction();
    _driverRemove = lib
        .lookup<ffi.NativeFunction<_ThreeStrToOneStrNative>>('wdmm_driver_remove')
        .asFunction();
    _driverGet = lib
        .lookup<ffi.NativeFunction<_ThreeStrToOneStrNative>>('wdmm_driver_get')
        .asFunction();
    _accountList = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_account_list')
        .asFunction();
    _accountGet = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_account_get')
        .asFunction();
    _accountUpsert = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_account_upsert')
        .asFunction();
    _accountDelete = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_account_delete')
        .asFunction();
    _accountListDir = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_account_list_dir')
        .asFunction();
    _accountMkdir = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_account_mkdir')
        .asFunction();
    _accountRename = lib
        .lookup<ffi.NativeFunction<_ThreeStrToOneStrNative>>('wdmm_account_rename')
        .asFunction();
    _accountRemove = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_account_remove')
        .asFunction();
    _accountGetEntry = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_account_get_entry')
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

  // ── Round 4 — Sync FFI ────────────────────────────────────────────────────

  /// Trigger an incremental Rust sync run (credentials + music library +
  /// manga + playlists via `run_sync_all`).
  ///
  /// Returns a JSON summary string on success or 'error:...' on failure.
  /// Returns null if the native library is not available.
  ///
  /// Semantics: `run_sync_all` runs every engine's `sync_incremental`.
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

  /// Full-rebuild Rust sync run (credentials + music library + manga +
  /// playlists via `run_sync_full`).
  ///
  /// Triggers `sync_full` on every engine — base-shard rebuild for music
  /// and manga. Use after a device reset or to compact a fragmented remote.
  ///
  /// [withCovers]: when true, the rebuilt `lib-*` base shards embed
  /// `SEC_COVERS` (3) cover blobs from the configured cover roots.
  /// Default false — covers stay cover-free.
  ///
  /// Returns a JSON summary string on success or 'error:...' on failure.
  /// Returns null if the native library is not available.
  static String? syncFull({
    required String webdavUrl,
    required String username,
    required String password,
    String remoteDir = '/wdmm_sync',
    bool withCovers = false,
  }) {
    if (!_ensureSymbols() || _syncFull == null) return null;
    final urlPtr = webdavUrl.toNativeUtf8();
    final userPtr = username.toNativeUtf8();
    final passPtr = password.toNativeUtf8();
    final dirPtr = remoteDir.toNativeUtf8();
    try {
      return _readAndFreeString(_syncFull!(urlPtr, userPtr, passPtr, dirPtr, withCovers ? 1 : 0));
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

  static bool _ensureDmrSymbols() {
    final lib = _tryLib;
    if (lib == null) return false;
    try {
      _dmrPrefsInit ??= lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_dmr_prefs_init')
          .asFunction();
      _dmrPrefsList ??= lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_dmr_prefs_list')
          .asFunction();
      _dmrPrefsGet ??= lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_dmr_prefs_get')
          .asFunction();
      _dmrPrefsUpsert ??= lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_dmr_prefs_upsert')
          .asFunction();
      _dmrPrefsDelete ??= lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_dmr_prefs_delete')
          .asFunction();
      _backupCreate ??= lib
          .lookup<ffi.NativeFunction<_StrStrToStrNative>>('wdmm_backup_create')
          .asFunction();
      _backupRestore ??= lib
          .lookup<ffi.NativeFunction<_StrStrToStrNative>>('wdmm_backup_restore')
          .asFunction();
      _backupUpload ??= lib
          .lookup<ffi.NativeFunction<_FiveStrToOneStrNative>>('wdmm_backup_upload')
          .asFunction();
      _backupList ??= lib
          .lookup<ffi.NativeFunction<_FourStrToOneStrNative>>('wdmm_backup_list')
          .asFunction();
      _backupDownloadRestore ??= lib
          .lookup<ffi.NativeFunction<_FiveStrToOneStrNative>>('wdmm_backup_download_restore')
          .asFunction();
      _coversConfigure ??= lib
          .lookup<ffi.NativeFunction<_StrStrToStrNative>>('wdmm_covers_configure')
          .asFunction();
      return true;
    } catch (e) {
      debugPrint('[RustCore] DMR symbol lookup failed: $e');
      return false;
    }
  }

  static String? dmrPrefsInit(String path) {
    if (!_ensureDmrSymbols()) return null;
    final ptr = path.toNativeUtf8();
    try {
      return _readAndFreeString(_dmrPrefsInit!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  static String? dmrPrefsList() {
    if (!_ensureDmrSymbols()) return null;
    return _readAndFreeString(_dmrPrefsList!());
  }

  static String? dmrPrefsGet(String usn) => _callOneString(_dmrPrefsGet, usn);
  static String? dmrPrefsUpsert(String json) => _callOneString(_dmrPrefsUpsert, json);
  static String? dmrPrefsDelete(String usn) => _callOneString(_dmrPrefsDelete, usn);

  static String? backupCreate(String passphrase, String outputPath) =>
      _callTwoStrings(_backupCreate, passphrase, outputPath);

  static String? backupRestore(String passphrase, String path) =>
      _callTwoStrings(_backupRestore, passphrase, path);

  /// Upload a backup to WebDAV.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, or null if the native
  /// library is not available.
  static String? backupUpload({
    required String url,
    required String user,
    required String pass,
    required String remoteDir,
    required String passphrase,
  }) =>
      _callFiveStrings(_backupUpload, url, user, pass, remoteDir, passphrase);

  /// List backups in a WebDAV directory.
  ///
  /// Returns a JSON array of backup metadata, or 'error:...' on failure.
  /// Returns null if the native library is not available.
  static String? backupList({
    required String url,
    required String user,
    required String pass,
    required String remoteDir,
  }) =>
      _callFourStrings(_backupList, url, user, pass, remoteDir);

  /// Download a backup from WebDAV and restore it.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, or null if the native
  /// library is not available.
  static String? backupDownloadRestore({
    required String url,
    required String user,
    required String pass,
    required String remoteFile,
    required String passphrase,
  }) =>
      _callFiveStrings(_backupDownloadRestore, url, user, pass, remoteFile, passphrase);

  /// Configure the cover image directories used during backup create/restore.
  ///
  /// Both paths must be non-empty UTF-8. Returns 'ok' on success or 'error:...'
  /// on failure. Returns null if the native library is not available.
  static String? coversConfigure(String musicCoversDir, String mangaCoversDir) =>
      _callTwoStrings(_coversConfigure, musicCoversDir, mangaCoversDir);

  static String? _callOneString(_OneStrToStrDart? fn, String value) {
    if (!_ensureDmrSymbols()) return null;
    final ptr = value.toNativeUtf8();
    try {
      return _readAndFreeString(fn!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  static String? _callTwoStrings(_StrStrToStrDart? fn, String first, String second) {
    if (!_ensureDmrSymbols()) return null;
    final a = first.toNativeUtf8();
    final b = second.toNativeUtf8();
    try {
      return _readAndFreeString(fn!(a, b));
    } finally {
      calloc.free(a);
      calloc.free(b);
    }
  }

  static String? _callFourStrings(_FourStrToOneStrDart? fn, String s1, String s2, String s3, String s4) {
    if (!_ensureDmrSymbols()) return null;
    final a = s1.toNativeUtf8();
    final b = s2.toNativeUtf8();
    final c = s3.toNativeUtf8();
    final d = s4.toNativeUtf8();
    try {
      return _readAndFreeString(fn!(a, b, c, d));
    } finally {
      calloc.free(a);
      calloc.free(b);
      calloc.free(c);
      calloc.free(d);
    }
  }

  static String? _callFiveStrings(_FiveStrToOneStrDart? fn, String s1, String s2, String s3, String s4, String s5) {
    if (!_ensureDmrSymbols()) return null;
    final a = s1.toNativeUtf8();
    final b = s2.toNativeUtf8();
    final c = s3.toNativeUtf8();
    final d = s4.toNativeUtf8();
    final e = s5.toNativeUtf8();
    try {
      return _readAndFreeString(fn!(a, b, c, d, e));
    } finally {
      calloc.free(a);
      calloc.free(b);
      calloc.free(c);
      calloc.free(d);
      calloc.free(e);
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
  static _OneStrToStrDart? _trackDeleteBySource;
  static _NoArgToStrDart?  _libraryClearAll;
  static _NoArgToStrDart?  _libraryClearIndex;
  static _OneStrToStrDart? _cueSliceDelete;
  static _TwoStrToOneStrDart? _cueAlbumDelete;
  static _TwoStrToOneStrDart? _cueRemainingSlices;
  static _OneStrToStrDart? _cueSliceUpsert;
  static _OneStrToStrDart? _cueAlbumUpsert;
  static _OneStrToStrDart? _libraryImport;
  static _OneStrToStrDart? _libraryCompare;

  // ── Class B reads — getTrack by source+path + CUE album/slices reads ──────
  static _TwoStrToOneStrDart? _trackGetBySourcePath;
  static _OneStrToStrDart? _cueAlbumForSlice;
  static _OneStrToStrDart? _cueSlicesForCue;

  // ── Schema v6 — deleted_tracks + sync_state ───────────────────────────────
  static _OneStrToStrDart? _deletedTrackUpsert;
  static _TwoStrToOneStrDart? _deletedTrackClear;
  static _NoArgToStrDart? _deletedTracksList;
  static _NoArgToStrDart? _deletedTracksUnpushed;
  static _OneStrToStrDart? _deletedTracksMarkPushed;
  static _Int64ToStrDart? _deletedTracksPurgeUpTo;
  static _OneStrToStrDart? _tombstonedRemotePaths;
  static _OneStrToStrDart? _syncStateGet;
  static _OneStrToStrDart? _syncStateSave;
  static _OneStrToStrDart? _syncStateClear;

  // ── Schema v7+v8 — aggregates + FTS5 ───────────────────────────────────────
  static _NoArgToStrDart? _artistList;
  static _OneStrToStrDart? _artistGet;
  static _NoArgToStrDart? _albumList;
  static _OneStrToStrDart? _albumGet;
  static _OneStrToStrDart? _tracksByArtist;
  static _OneStrToStrDart? _tracksByAlbum;
  static _NoArgToStrDart? _libraryRebuildAggregates;
  static _NoArgToStrDart? _libraryRebuildFts;

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
    _trackDeleteBySource = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_track_delete_by_source')
        .asFunction();
    _libraryClearAll = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_library_clear_all')
        .asFunction();
    _libraryClearIndex = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_library_clear_index')
        .asFunction();
    _cueSliceDelete = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_cue_slice_delete')
        .asFunction();
    _cueAlbumDelete = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_cue_album_delete')
        .asFunction();
    _cueRemainingSlices = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_cue_remaining_slices')
        .asFunction();
    _cueSliceUpsert = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_cue_slice_upsert')
        .asFunction();
    _cueAlbumUpsert = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_cue_album_upsert')
        .asFunction();
    _libraryImport = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_library_import_from_sqflite')
        .asFunction();
    _libraryCompare = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_library_compare_with_sqflite')
        .asFunction();

    // Class B reads — track get by source+path + CUE album/slices
    _trackGetBySourcePath = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_track_get_by_source_path')
        .asFunction();
    _cueAlbumForSlice = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_cue_album_for_slice')
        .asFunction();
    _cueSlicesForCue = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_cue_slices_for_cue')
        .asFunction();

    // Schema v6
    _deletedTrackUpsert = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_deleted_track_upsert')
        .asFunction();
    _deletedTrackClear = lib
        .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_deleted_track_clear')
        .asFunction();
    _deletedTracksList = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_deleted_tracks_list')
        .asFunction();
    _deletedTracksUnpushed = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_deleted_tracks_unpushed')
        .asFunction();
    _deletedTracksMarkPushed = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_deleted_tracks_mark_pushed')
        .asFunction();
    _deletedTracksPurgeUpTo = lib
        .lookup<ffi.NativeFunction<_Int64ToStrNative>>('wdmm_deleted_tracks_purge_up_to')
        .asFunction();
    _tombstonedRemotePaths = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_tombstoned_remote_paths')
        .asFunction();
    _syncStateGet = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_sync_state_get')
        .asFunction();
    _syncStateSave = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_sync_state_save')
        .asFunction();
    _syncStateClear = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_sync_state_clear')
        .asFunction();

    // Schema v7+v8 aggregates + FTS5
    _artistList = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_artist_list')
        .asFunction();
    _artistGet = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_artist_get')
        .asFunction();
    _albumList = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_album_list')
        .asFunction();
    _albumGet = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_album_get')
        .asFunction();
    _tracksByArtist = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_tracks_by_artist')
        .asFunction();
    _tracksByAlbum = lib
        .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_tracks_by_album')
        .asFunction();
    _libraryRebuildAggregates = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_library_rebuild_aggregates')
        .asFunction();
    _libraryRebuildFts = lib
        .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_library_rebuild_fts')
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

  static String? trackDeleteBySource(String accountId) {
    if (!_ensureSymbols()) return null;
    if (_trackDeleteBySource == null) {
      _loadLibrarySymbolsSafe();
      if (_trackDeleteBySource == null) return null;
    }
    final ptr = accountId.toNativeUtf8();
    try {
      return _readAndFreeString(_trackDeleteBySource!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  static String? libraryClearAll() {
    if (!_ensureSymbols()) return null;
    if (_libraryClearAll == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryClearAll == null) return null;
    }
    return _readAndFreeString(_libraryClearAll!());
  }

  static String? libraryClearIndex() {
    if (!_ensureSymbols()) return null;
    if (_libraryClearIndex == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryClearIndex == null) return null;
    }
    return _readAndFreeString(_libraryClearIndex!());
  }

  static String? cueSliceDelete(String musicId) {
    if (!_ensureSymbols()) return null;
    if (_cueSliceDelete == null) {
      _loadLibrarySymbolsSafe();
      if (_cueSliceDelete == null) return null;
    }
    final ptr = musicId.toNativeUtf8();
    try {
      return _readAndFreeString(_cueSliceDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  static String? cueAlbumDelete(String sourceName, String cueRemotePath) {
    if (!_ensureSymbols()) return null;
    if (_cueAlbumDelete == null) {
      _loadLibrarySymbolsSafe();
      if (_cueAlbumDelete == null) return null;
    }
    final source = sourceName.toNativeUtf8();
    final path = cueRemotePath.toNativeUtf8();
    try {
      return _readAndFreeString(_cueAlbumDelete!(source, path));
    } finally {
      calloc.free(source);
      calloc.free(path);
    }
  }

  static String? cueRemainingSlices(String sourceName, String cueRemotePath) {
    if (!_ensureSymbols()) return null;
    if (_cueRemainingSlices == null) {
      _loadLibrarySymbolsSafe();
      if (_cueRemainingSlices == null) return null;
    }
    final source = sourceName.toNativeUtf8();
    final path = cueRemotePath.toNativeUtf8();
    try {
      return _readAndFreeString(_cueRemainingSlices!(source, path));
    } finally {
      calloc.free(source);
      calloc.free(path);
    }
  }

  /// Get a track or CUE slice by source name and remote path.
  ///
  /// Returns `LibraryTrack` JSON (keys: `id`, `account_id`) if a track matches,
  /// `CueSlice` JSON (keys: `music_id`, `cue_id`) if a CUE slice matches,
  /// literal `"null"` if neither found, or `"error:..."` on failure.
  /// Returns null if the library is unavailable.
  static String? trackGetBySourcePath(String accountId, String remotePath) {
    if (!_ensureSymbols()) return null;
    if (_trackGetBySourcePath == null) {
      _loadLibrarySymbolsSafe();
      if (_trackGetBySourcePath == null) return null;
    }
    final acct = accountId.toNativeUtf8();
    final path = remotePath.toNativeUtf8();
    try {
      return _readAndFreeString(_trackGetBySourcePath!(acct, path));
    } finally {
      calloc.free(acct);
      calloc.free(path);
    }
  }

  /// Get the CUE album that owns the slice with [musicId].
  ///
  /// Returns `CueAlbum` JSON, `"null"` if not found, or `"error:..."`.
  /// Returns null if the library is unavailable.
  static String? cueAlbumForSlice(String musicId) {
    if (!_ensureSymbols()) return null;
    if (_cueAlbumForSlice == null) {
      _loadLibrarySymbolsSafe();
      if (_cueAlbumForSlice == null) return null;
    }
    final ptr = musicId.toNativeUtf8();
    try {
      return _readAndFreeString(_cueAlbumForSlice!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List all CUE slices for [cueId], ordered by track_index ASC.
  ///
  /// Returns a JSON array (may be `[]`), or `"error:..."`.
  /// Returns null if the library is unavailable.
  static String? cueSlicesForCue(String cueId) {
    if (!_ensureSymbols()) return null;
    if (_cueSlicesForCue == null) {
      _loadLibrarySymbolsSafe();
      if (_cueSlicesForCue == null) return null;
    }
    final ptr = cueId.toNativeUtf8();
    try {
      return _readAndFreeString(_cueSlicesForCue!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  static String? cueSliceUpsert(String sliceJson) {
    if (!_ensureSymbols()) return null;
    if (_cueSliceUpsert == null) {
      _loadLibrarySymbolsSafe();
      if (_cueSliceUpsert == null) return null;
    }
    final ptr = sliceJson.toNativeUtf8();
    try {
      return _readAndFreeString(_cueSliceUpsert!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  static String? cueAlbumUpsert(String albumJson) {
    if (!_ensureSymbols()) return null;
    if (_cueAlbumUpsert == null) {
      _loadLibrarySymbolsSafe();
      if (_cueAlbumUpsert == null) return null;
    }
    final ptr = albumJson.toNativeUtf8();
    try {
      return _readAndFreeString(_cueAlbumUpsert!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Trigger a one-shot import from an old sqflite DB at [oldDbPath] into
  /// the Rust library DB.  Copies tracks, playlists, playlist_entries, and the
  /// v6 surfaces (deleted_tracks tombstones + sync_state cursors).  Idempotent
  /// via the KV flags `sqflite_imported` / `sqflite_imported_v6`; a device that
  /// already ran the legacy import gets a v6 backfill of the two new surfaces.
  ///
  /// Call this from a first-run migration helper, NOT on every app start.
  ///
  /// Returns a JSON summary:
  /// `{"already_done":false,"tracks":42,"playlists":3,"entries":120,"deleted_tracks":5,"sync_state":2}`
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

  /// Compare the Rust library DB against an old sqflite DB at [oldDbPath].
  /// Neither DB is mutated.
  ///
  /// Returns a JSON CompareReport
  /// `{"tracks":{...},"deleted_tracks":{...},"sync_state":{...},"ok":true}`
  /// or 'error:...' on failure.  Returns null if library unavailable.
  static String? libraryCompareWithSqflite(String oldDbPath) {
    if (!_ensureSymbols()) return null;
    if (_libraryCompare == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryCompare == null) return null;
    }
    final ptr = oldDbPath.toNativeUtf8();
    try {
      return _readAndFreeString(_libraryCompare!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── Schema v6 — deleted_tracks + sync_state public API ────────────────────

  /// Upsert a deleted track tombstone from JSON.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? deletedTrackUpsert(String json) {
    if (!_ensureSymbols()) return null;
    if (_deletedTrackUpsert == null) {
      _loadLibrarySymbolsSafe();
      if (_deletedTrackUpsert == null) return null;
    }
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_deletedTrackUpsert!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Clear a deleted track tombstone by source and remote path.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? deletedTrackClear(String sourceName, String remotePath) {
    if (!_ensureSymbols()) return null;
    if (_deletedTrackClear == null) {
      _loadLibrarySymbolsSafe();
      if (_deletedTrackClear == null) return null;
    }
    final srcPtr = sourceName.toNativeUtf8();
    final pathPtr = remotePath.toNativeUtf8();
    try {
      return _readAndFreeString(_deletedTrackClear!(srcPtr, pathPtr));
    } finally {
      calloc.free(srcPtr);
      calloc.free(pathPtr);
    }
  }

  /// List all deleted tracks.
  ///
  /// Returns JSON array or 'error:...' on failure, null if unavailable.
  static String? deletedTracksList() {
    if (!_ensureSymbols()) return null;
    if (_deletedTracksList == null) {
      _loadLibrarySymbolsSafe();
      if (_deletedTracksList == null) return null;
    }
    return _readAndFreeString(_deletedTracksList!());
  }

  /// List unpushed deleted tracks (pushed=0).
  ///
  /// Returns JSON array or 'error:...' on failure, null if unavailable.
  static String? deletedTracksUnpushed() {
    if (!_ensureSymbols()) return null;
    if (_deletedTracksUnpushed == null) {
      _loadLibrarySymbolsSafe();
      if (_deletedTracksUnpushed == null) return null;
    }
    return _readAndFreeString(_deletedTracksUnpushed!());
  }

  /// Mark deleted tracks as pushed by revision numbers.
  ///
  /// [revsJson] is a JSON array of integers. Returns 'ok' on success,
  /// 'error:...' on failure, null if unavailable.
  static String? deletedTracksMarkPushed(String revsJson) {
    if (!_ensureSymbols()) return null;
    if (_deletedTracksMarkPushed == null) {
      _loadLibrarySymbolsSafe();
      if (_deletedTracksMarkPushed == null) return null;
    }
    final ptr = revsJson.toNativeUtf8();
    try {
      return _readAndFreeString(_deletedTracksMarkPushed!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Purge pushed deleted tracks up to and including the given revision.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? deletedTracksPurgeUpTo(int upTo) {
    if (!_ensureSymbols()) return null;
    if (_deletedTracksPurgeUpTo == null) {
      _loadLibrarySymbolsSafe();
      if (_deletedTracksPurgeUpTo == null) return null;
    }
    return _readAndFreeString(_deletedTracksPurgeUpTo!(upTo));
  }

  /// Get tombstoned remote paths for a source.
  ///
  /// Returns JSON array of strings or 'error:...' on failure, null if unavailable.
  static String? tombstonedRemotePaths(String sourceName) {
    if (!_ensureSymbols()) return null;
    if (_tombstonedRemotePaths == null) {
      _loadLibrarySymbolsSafe();
      if (_tombstonedRemotePaths == null) return null;
    }
    final ptr = sourceName.toNativeUtf8();
    try {
      return _readAndFreeString(_tombstonedRemotePaths!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Get sync state by remote key.
  ///
  /// Returns JSON object, 'null', or 'error:...' on failure, null if unavailable.
  static String? syncStateGet(String remoteKey) {
    if (!_ensureSymbols()) return null;
    if (_syncStateGet == null) {
      _loadLibrarySymbolsSafe();
      if (_syncStateGet == null) return null;
    }
    final ptr = remoteKey.toNativeUtf8();
    try {
      return _readAndFreeString(_syncStateGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Save sync state from JSON.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? syncStateSave(String json) {
    if (!_ensureSymbols()) return null;
    if (_syncStateSave == null) {
      _loadLibrarySymbolsSafe();
      if (_syncStateSave == null) return null;
    }
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_syncStateSave!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Clear sync state by optional prefix.
  ///
  /// Pass empty string or null to clear all. Returns 'ok' on success,
  /// 'error:...' on failure, null if unavailable.
  static String? syncStateClear(String? prefix) {
    if (!_ensureSymbols()) return null;
    if (_syncStateClear == null) {
      _loadLibrarySymbolsSafe();
      if (_syncStateClear == null) return null;
    }
    final ptr = (prefix ?? '').toNativeUtf8();
    try {
      return _readAndFreeString(_syncStateClear!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── Schema v7+v8 — Aggregates + FTS5 public API ────────────────────────────

  /// List all artists (schema v7 aggregate).
  ///
  /// Returns JSON array of `{"name":"...","track_count":N}` objects,
  /// or 'error:...' on failure, null if unavailable.
  static String? artistList() {
    if (!_ensureSymbols()) return null;
    if (_artistList == null) {
      _loadLibrarySymbolsSafe();
      if (_artistList == null) return null;
    }
    return _readAndFreeString(_artistList!());
  }

  /// Get one artist by name (schema v7 aggregate).
  ///
  /// Returns JSON object `{"name":"...","track_count":N}`, "null" if absent,
  /// or 'error:...' on failure, null if unavailable.
  static String? artistGet(String name) {
    if (!_ensureSymbols()) return null;
    if (_artistGet == null) {
      _loadLibrarySymbolsSafe();
      if (_artistGet == null) return null;
    }
    final ptr = name.toNativeUtf8();
    try {
      return _readAndFreeString(_artistGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List all albums (schema v7 aggregate).
  ///
  /// Returns JSON array of `{"title":"...","album_artist":"...","track_count":N}` objects,
  /// or 'error:...' on failure, null if unavailable.
  static String? albumList() {
    if (!_ensureSymbols()) return null;
    if (_albumList == null) {
      _loadLibrarySymbolsSafe();
      if (_albumList == null) return null;
    }
    return _readAndFreeString(_albumList!());
  }

  /// Get one album by title (schema v7 aggregate).
  ///
  /// Returns JSON object `{"title":"...","album_artist":"...","track_count":N}`, "null" if absent,
  /// or 'error:...' on failure, null if unavailable.
  static String? albumGet(String title) {
    if (!_ensureSymbols()) return null;
    if (_albumGet == null) {
      _loadLibrarySymbolsSafe();
      if (_albumGet == null) return null;
    }
    final ptr = title.toNativeUtf8();
    try {
      return _readAndFreeString(_albumGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List tracks by artist name (schema v7 aggregate).
  ///
  /// Returns JSON array of track objects, or 'error:...' on failure, null if unavailable.
  static String? tracksByArtist(String name) {
    if (!_ensureSymbols()) return null;
    if (_tracksByArtist == null) {
      _loadLibrarySymbolsSafe();
      if (_tracksByArtist == null) return null;
    }
    final ptr = name.toNativeUtf8();
    try {
      return _readAndFreeString(_tracksByArtist!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List tracks by album title (schema v7 aggregate).
  ///
  /// Returns JSON array of track objects, or 'error:...' on failure, null if unavailable.
  static String? tracksByAlbum(String title) {
    if (!_ensureSymbols()) return null;
    if (_tracksByAlbum == null) {
      _loadLibrarySymbolsSafe();
      if (_tracksByAlbum == null) return null;
    }
    final ptr = title.toNativeUtf8();
    try {
      return _readAndFreeString(_tracksByAlbum!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Rebuild artist and album aggregates from the tracks table.
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? libraryRebuildAggregates() {
    if (!_ensureSymbols()) return null;
    if (_libraryRebuildAggregates == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryRebuildAggregates == null) return null;
    }
    return _readAndFreeString(_libraryRebuildAggregates!());
  }

  /// Rebuild FTS5 search index from the tracks table (schema v8).
  ///
  /// Returns 'ok' on success, 'error:...' on failure, null if unavailable.
  static String? libraryRebuildFts() {
    if (!_ensureSymbols()) return null;
    if (_libraryRebuildFts == null) {
      _loadLibrarySymbolsSafe();
      if (_libraryRebuildFts == null) return null;
    }
    return _readAndFreeString(_libraryRebuildFts!());
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
  // round. Gated by `kRustProxyEnabled` in rust_proxy_bridge.dart.
  // R12: LocalStreamBridge deleted — MustProxy + DLNA cast route through
  // RustProxyStreamBridge (wdmm_proxy_register_stream / set_result).

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

  // ── Wave B — KV / settings / user-folder / playlist FFI ───────────────────
  //
  // Round B cutover: these exports replace the sqflite user_folder tables, the
  // sqflite playlist store, and the SharedPreferences keys for the network path
  // + the well-known KV settings. Dart services call these directly — the old
  // stores/prefs are no longer written.

  static _OneStrToStrDart? _kvGet;
  static _TwoStrToOneStrDart? _kvSet;
  static _OneStrToStrDart? _kvDelete;
  static _NoArgToStrDart? _settingsGetNetworkRememberLastPath;
  static _Int32ToStrDart? _settingsSetNetworkRememberLastPath;
  static _NoArgToStrDart? _settingsGetNetworkLastPath;
  static _OneStrToStrDart? _settingsSetNetworkLastPath;
  static _OneStrToStrDart? _userFolderListChildren;
  static _OneStrToStrDart? _userFolderCreate;
  static _TwoStrToOneStrDart? _userFolderRename;
  static _TwoStrToOneStrDart? _userFolderMove;
  static _OneStrToStrDart? _userFolderDelete;
  static _OneStrToStrDart? _userFolderListItems;
  static _OneStrToStrDart? _userFolderAddItem;
  static _ThreeStrToOneStrDart? _userFolderRemoveItem;
  static _TwoStrToOneStrDart? _userFolderSetItems;
  static _OneStrToStrDart? _userFolderReplaceSnapshot;
  static _NoArgToStrDart? _playlistList;
  static _OneStrToStrDart? _playlistCreate;
  static _OneStrToStrDart? _playlistDelete;
  static _OneStrToStrDart? _playlistListEntries;
  static _TwoStrToOneStrDart? _playlistSetEntries;

  static bool _bSymbolsLoaded = false;

  static void _loadBSymbolsSafe() {
    if (_bSymbolsLoaded) return;
    final lib = _tryLib;
    if (lib == null) return;
    try {
      _kvGet = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_kv_get')
          .asFunction();
      _kvSet = lib
          .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>('wdmm_kv_set')
          .asFunction();
      _kvDelete = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_kv_delete')
          .asFunction();
      _settingsGetNetworkRememberLastPath = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>(
              'wdmm_settings_get_network_remember_last_path')
          .asFunction();
      _settingsSetNetworkRememberLastPath = lib
          .lookup<ffi.NativeFunction<_Int32ToStrNative>>(
              'wdmm_settings_set_network_remember_last_path')
          .asFunction();
      _settingsGetNetworkLastPath = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>(
              'wdmm_settings_get_network_last_path')
          .asFunction();
      _settingsSetNetworkLastPath = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_settings_set_network_last_path')
          .asFunction();
      _userFolderListChildren = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_user_folder_list_children')
          .asFunction();
      _userFolderCreate = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_user_folder_create')
          .asFunction();
      _userFolderRename = lib
          .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>(
              'wdmm_user_folder_rename')
          .asFunction();
      _userFolderMove = lib
          .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>(
              'wdmm_user_folder_move')
          .asFunction();
      _userFolderDelete = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_user_folder_delete')
          .asFunction();
      _userFolderListItems = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_user_folder_list_items')
          .asFunction();
      _userFolderAddItem = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_user_folder_add_item')
          .asFunction();
      _userFolderRemoveItem = lib
          .lookup<ffi.NativeFunction<_ThreeStrToOneStrNative>>(
              'wdmm_user_folder_remove_item')
          .asFunction();
      _userFolderSetItems = lib
          .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>(
              'wdmm_user_folder_set_items')
          .asFunction();
      _userFolderReplaceSnapshot = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_user_folder_replace_snapshot')
          .asFunction();
      _playlistList = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_playlist_list')
          .asFunction();
      _playlistCreate = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_playlist_create')
          .asFunction();
      _playlistDelete = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_playlist_delete')
          .asFunction();
      _playlistListEntries = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_playlist_list_entries')
          .asFunction();
      _playlistSetEntries = lib
          .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>(
              'wdmm_playlist_set_entries')
          .asFunction();
      _bSymbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] Wave B symbol lookup failed (non-fatal): $e');
    }
  }

  /// Ensure Wave B symbols are loaded. Returns true if usable.
  static bool _ensureBSymbols() {
    if (!_ensureSymbols()) return false;
    if (_bSymbolsLoaded) return true;
    _loadBSymbolsSafe();
    return _bSymbolsLoaded;
  }

  // ── KV store ─────────────────────────────────────────────────────────────

  /// Get a KV value by [key]. Returns the value string, '' if the key is
  /// absent, 'error:...' on failure, or null if the library is unavailable.
  static String? kvGet(String key) {
    if (!_ensureBSymbols() || _kvGet == null) return null;
    final ptr = key.toNativeUtf8();
    try {
      return _readAndFreeString(_kvGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Set a KV [key] = [value]. Returns 'ok' or 'error:...', null if unavailable.
  static String? kvSet(String key, String value) {
    if (!_ensureBSymbols() || _kvSet == null) return null;
    final k = key.toNativeUtf8();
    final v = value.toNativeUtf8();
    try {
      return _readAndFreeString(_kvSet!(k, v));
    } finally {
      calloc.free(k);
      calloc.free(v);
    }
  }

  /// Delete a KV [key]. Returns 'ok' or 'error:...', null if unavailable.
  static String? kvDelete(String key) {
    if (!_ensureBSymbols() || _kvDelete == null) return null;
    final ptr = key.toNativeUtf8();
    try {
      return _readAndFreeString(_kvDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── Network path settings ────────────────────────────────────────────────

  /// Returns true if the network library should remember the last browse
  /// path. Returns null if the library is unavailable.
  static bool? settingsGetNetworkRememberLastPath() {
    if (!_ensureBSymbols() || _settingsGetNetworkRememberLastPath == null) {
      return null;
    }
    final s = _readAndFreeString(_settingsGetNetworkRememberLastPath!());
    return s == 'true';
  }

  /// Enable/disable remembering the last network browse path.
  /// Returns 'ok' or 'error:...', null if unavailable.
  static String? settingsSetNetworkRememberLastPath(bool enabled) {
    if (!_ensureBSymbols() || _settingsSetNetworkRememberLastPath == null) {
      return null;
    }
    return _readAndFreeString(_settingsSetNetworkRememberLastPath!(enabled ? 1 : 0));
  }

  /// Get the session-only last network browse path.
  /// Returns the path (or ''/'/'), null if unavailable.
  static String? settingsGetNetworkLastPath() {
    if (!_ensureBSymbols() || _settingsGetNetworkLastPath == null) return null;
    return _readAndFreeString(_settingsGetNetworkLastPath!());
  }

  /// Set the session-only last network browse path.
  /// Returns 'ok' or 'error:...', null if unavailable.
  static String? settingsSetNetworkLastPath(String path) {
    if (!_ensureBSymbols() || _settingsSetNetworkLastPath == null) return null;
    final ptr = path.toNativeUtf8();
    try {
      return _readAndFreeString(_settingsSetNetworkLastPath!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── User folder store ────────────────────────────────────────────────────

  /// List children of [parentId]. Pass `kUserFolderRootId` (or `''`/`null`
  /// equivalent) for the virtual root 「我的文件夹」.
  /// Returns a JSON array string, or null if unavailable.
  static String? userFolderListChildren(String parentId) {
    if (!_ensureBSymbols() || _userFolderListChildren == null) return null;
    final ptr = parentId.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderListChildren!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Create a user folder. [json] must match the folder schema
  /// (`{id,name,parent_id,sort_order,created_at}`).
  /// Returns 'ok' or 'error:...', null if unavailable.
  static String? userFolderCreate(String json) {
    if (!_ensureBSymbols() || _userFolderCreate == null) return null;
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderCreate!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Rename folder [id] to [name]. Returns 'ok'/'error:...', null if unavailable.
  static String? userFolderRename(String id, String name) {
    if (!_ensureBSymbols() || _userFolderRename == null) return null;
    final i = id.toNativeUtf8();
    final n = name.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderRename!(i, n));
    } finally {
      calloc.free(i);
      calloc.free(n);
    }
  }

  /// Move folder [id] under [newParentId]. Returns 'ok'/'error:...', null if
  /// unavailable.
  static String? userFolderMove(String id, String newParentId) {
    if (!_ensureBSymbols() || _userFolderMove == null) return null;
    final i = id.toNativeUtf8();
    final p = newParentId.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderMove!(i, p));
    } finally {
      calloc.free(i);
      calloc.free(p);
    }
  }

  /// Delete folder [id] (cascades to descendants/items).
  /// Returns 'ok'/'error:...', null if unavailable.
  static String? userFolderDelete(String id) {
    if (!_ensureBSymbols() || _userFolderDelete == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List items in folder [folderId]. Returns a JSON array string, null if
  /// unavailable.
  static String? userFolderListItems(String folderId) {
    if (!_ensureBSymbols() || _userFolderListItems == null) return null;
    final ptr = folderId.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderListItems!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Add an item to a folder. [json] matches the item schema
  /// (`{folder_id,ref_kind,ref_key,sort_order,added_at}`).
  /// Returns 'ok'/'error:...', null if unavailable.
  static String? userFolderAddItem(String json) {
    if (!_ensureBSymbols() || _userFolderAddItem == null) return null;
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderAddItem!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Remove an item identified by (folder_id, ref_kind, ref_key).
  /// Returns 'ok'/'error:...', null if unavailable.
  static String? userFolderRemoveItem(
      String folderId, String refKind, String refKey) {
    if (!_ensureBSymbols() || _userFolderRemoveItem == null) return null;
    final f = folderId.toNativeUtf8();
    final k = refKind.toNativeUtf8();
    final r = refKey.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderRemoveItem!(f, k, r));
    } finally {
      calloc.free(f);
      calloc.free(k);
      calloc.free(r);
    }
  }

  /// Replace the full ordered item set of folder [folderId].
  /// [jsonArray] is a JSON array of item objects.
  /// Returns 'ok'/'error:...', null if unavailable.
  static String? userFolderSetItems(String folderId, String jsonArray) {
    if (!_ensureBSymbols() || _userFolderSetItems == null) return null;
    final f = folderId.toNativeUtf8();
    final a = jsonArray.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderSetItems!(f, a));
    } finally {
      calloc.free(f);
      calloc.free(a);
    }
  }

  /// Replace the whole user-folder snapshot atomically.
  /// [json] is `{"folders":[…],"items":[…]}`; timestamps accept unix i64 or ISO8601.
  /// Returns `"ok"` on success, `"error:…"` on failure, null if unavailable.
  static String? userFolderReplaceSnapshot(String json) {
    if (!_ensureBSymbols() || _userFolderReplaceSnapshot == null) return null;
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_userFolderReplaceSnapshot!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── Playlist store ────────────────────────────────────────────────────────

  /// List all playlists. Returns a JSON array string, null if unavailable.
  static String? playlistList() {
    if (!_ensureBSymbols() || _playlistList == null) return null;
    return _readAndFreeString(_playlistList!());
  }

  /// Create a playlist. [json] matches the playlist schema
  /// (`{id,name,created_at,updated_at}`).
  /// Returns 'ok'/'error:...', null if unavailable.
  static String? playlistCreate(String json) {
    if (!_ensureBSymbols() || _playlistCreate == null) return null;
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_playlistCreate!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Delete playlist [id]. Returns 'ok'/'error:...', null if unavailable.
  static String? playlistDelete(String id) {
    if (!_ensureBSymbols() || _playlistDelete == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_playlistDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List entries of playlist [id]. Returns a JSON array string, null if
  /// unavailable.
  static String? playlistListEntries(String id) {
    if (!_ensureBSymbols() || _playlistListEntries == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_playlistListEntries!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Replace the full ordered entry set of playlist [id].
  /// [jsonArray] is a JSON array of entry objects.
  /// Returns 'ok'/'error:...', null if unavailable.
  static String? playlistSetEntries(String id, String jsonArray) {
    if (!_ensureBSymbols() || _playlistSetEntries == null) return null;
    final i = id.toNativeUtf8();
    final a = jsonArray.toNativeUtf8();
    try {
      return _readAndFreeString(_playlistSetEntries!(i, a));
    } finally {
      calloc.free(i);
      calloc.free(a);
    }
  }

  // ── R12 — Proxy stream FFI ─────────────────────────────────────────────────
  //
  // Bindings for wdmm_proxy_register_stream / renew_stream_callback /
  // stream_alloc_buf / stream_free_buf / stream_set_result. Used by
  // [RustProxyStreamBridge] to route Dart-driver Range reads through the Rust
  // local HTTP proxy. Do NOT call these directly — go through the bridge.

  static _ProxyRegisterStreamDart?  _proxyRegisterStream;
  static _ProxyRenewStreamCbDart?   _proxyRenewStreamCb;
  static _ProxyStreamAllocBufDart?  _proxyStreamAllocBuf;
  static _ProxyStreamFreeBufDart?   _proxyStreamFreeBuf;
  static _ProxyStreamSetResultDart? _proxyStreamSetResult;
  static bool _streamSymbolsLoaded = false;

  static void _loadStreamSymbolsSafe() {
    if (_streamSymbolsLoaded) return;
    final lib = _tryLib;
    if (lib == null) return;
    try {
      _proxyRegisterStream = lib
          .lookup<ffi.NativeFunction<_ProxyRegisterStreamNative>>(
              'wdmm_proxy_register_stream')
          .asFunction();
      _proxyRenewStreamCb = lib
          .lookup<ffi.NativeFunction<_ProxyRenewStreamCbNative>>(
              'wdmm_proxy_renew_stream_callback')
          .asFunction();
      _proxyStreamAllocBuf = lib
          .lookup<ffi.NativeFunction<_ProxyStreamAllocBufNative>>(
              'wdmm_proxy_stream_alloc_buf')
          .asFunction();
      _proxyStreamFreeBuf = lib
          .lookup<ffi.NativeFunction<_ProxyStreamFreeBufNative>>(
              'wdmm_proxy_stream_free_buf')
          .asFunction();
      _proxyStreamSetResult = lib
          .lookup<ffi.NativeFunction<_ProxyStreamSetResultNative>>(
              'wdmm_proxy_stream_set_result')
          .asFunction();
      _streamSymbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] stream symbol lookup failed (non-fatal): $e');
    }
  }

  /// Register an in-process Range-callback stream with the proxy.
  ///
  /// - [size]     — known content length in bytes; `0` if unknown.
  /// - [name]     — optional; used for Content-Type guessing (pass `null` to
  ///   omit, e.g. for crypt-wrapped names).
  /// - [cb]       — native function pointer for the Range callback.
  /// - [userData] — opaque pointer passed back to every [cb] invocation.
  ///
  /// Returns JSON `{"token":"…","path_template":"/s/…","port":N}` on success,
  /// `"error:…"` on failure, or null if the native library is unavailable.
  /// Requires the proxy to be started first.
  static String? proxyRegisterStream({
    required int size,
    required String? name,
    required ffi.Pointer<ffi.NativeFunction<WdmmProxyRangeCallbackNative>> cb,
    required ffi.Pointer<ffi.Void> userData,
  }) {
    if (!_ensureSymbols()) return null;
    _loadStreamSymbolsSafe();
    if (_proxyRegisterStream == null) return null;
    final namePtr =
        name != null ? name.toNativeUtf8() : ffi.nullptr.cast<Utf8>();
    try {
      return _readAndFreeString(_proxyRegisterStream!(size, namePtr, cb, userData));
    } finally {
      if (name != null) calloc.free(namePtr);
    }
  }

  /// Replace the Range callback for an existing stream registration.
  ///
  /// Returns `"ok"` on success, `"error:…"` on failure, or null if the native
  /// library is unavailable. No-op if [token] is unknown or is a file
  /// registration.
  static String? proxyRenewStreamCallback(
    String token,
    ffi.Pointer<ffi.NativeFunction<WdmmProxyRangeCallbackNative>> cb,
    ffi.Pointer<ffi.Void> userData,
  ) {
    if (!_ensureSymbols()) return null;
    _loadStreamSymbolsSafe();
    if (_proxyRenewStreamCb == null) return null;
    final ptr = token.toNativeUtf8();
    try {
      return _readAndFreeString(_proxyRenewStreamCb!(ptr, cb, userData));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Allocate [len] bytes in Rust's heap for use as a Range-callback output
  /// buffer.
  ///
  /// **Must** use this to allocate the buffer passed to [proxyStreamSetResult]
  /// on the success path. Returns null (`ffi.nullptr`) if [len] is `0` or the
  /// library is unavailable.
  static ffi.Pointer<ffi.Uint8> proxyStreamAllocBuf(int len) {
    if (len <= 0) return ffi.nullptr;
    if (!_ensureSymbols()) return ffi.nullptr;
    _loadStreamSymbolsSafe();
    if (_proxyStreamAllocBuf == null) return ffi.nullptr;
    return _proxyStreamAllocBuf!(len);
  }

  /// Free a buffer previously returned by [proxyStreamAllocBuf].
  ///
  /// No-op if [buf] is null or [len] is `0`. Use only on error paths — on the
  /// success path, Rust reclaims the buffer after consuming it.
  static void proxyStreamFreeBuf(ffi.Pointer<ffi.Uint8> buf, int len) {
    if (buf == ffi.nullptr || len <= 0) return;
    if (!_ensureSymbols()) return;
    _loadStreamSymbolsSafe();
    _proxyStreamFreeBuf?.call(buf, len);
  }

  /// Deliver async Range bytes to a parked Rust request handler.
  ///
  /// - [requestId] — the id received in the [WdmmProxyRangeCallbackNative].
  /// - [buf]       — buffer from [proxyStreamAllocBuf]; Rust takes ownership on
  ///   success (status `0`).
  /// - [len]       — byte count in [buf].
  /// - [status]    — `0` = success; negative = error (pass null buf + `0` len).
  ///
  /// Safe to call from any thread. No-op if [requestId] is already timed out
  /// or unknown (30 s timeout → Rust returns a TimedOut IO error to the client).
  static void proxyStreamSetResult(
    int requestId,
    ffi.Pointer<ffi.Uint8> buf,
    int len,
    int status,
  ) {
    if (!_ensureSymbols()) return;
    _loadStreamSymbolsSafe();
    _proxyStreamSetResult?.call(requestId, buf, len, status);
  }

  // ── Wave D — Manga FFI ───────────────────────────────────────────────────
  //
  // Binds wdmm_manga_* exports landed in Wave D (fdb05df).
  // [MangaLibraryService] routes index CRUD and progress through these;
  // sqflite is no longer written for manga once [kRustMangaEnabled] is true.

  static _NoArgToStrDart?     _mangaList;
  static _OneStrToStrDart?    _mangaGet;
  static _OneStrToStrDart?    _mangaUpsert;
  static _OneStrToStrDart?    _mangaDelete;
  static _OneStrToStrDart?    _deletedMangaClear;
  static _NoArgToStrDart?     _mangaClearIndex;
  static _OneStrToStrDart?    _mangaListPages;
  static _TwoStrToOneStrDart? _mangaSetPages;
  static _OneStrToStrDart?    _mangaGetProgress;
  static _StrInt64ToStrDart?  _mangaSetProgress;
  static _NoArgToStrDart?     _mangaListProgress;
  static _NoArgToStrDart?     _mangaListSeries;

  static bool _mangaSymbolsLoaded = false;

  static void _loadMangaSymbolsSafe() {
    if (_mangaSymbolsLoaded) return;
    final lib = _tryLib;
    if (lib == null) return;
    try {
      _mangaList = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>('wdmm_manga_list')
          .asFunction();
      _mangaGet = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_manga_get')
          .asFunction();
      _mangaUpsert = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_manga_upsert')
          .asFunction();
      _mangaDelete = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>('wdmm_manga_delete')
          .asFunction();
      _deletedMangaClear = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_deleted_manga_clear')
          .asFunction();
      _mangaClearIndex = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>(
              'wdmm_manga_clear_index')
          .asFunction();
      _mangaListPages = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_manga_list_pages')
          .asFunction();
      _mangaSetPages = lib
          .lookup<ffi.NativeFunction<_TwoStrToOneStrNative>>(
              'wdmm_manga_set_pages')
          .asFunction();
      _mangaGetProgress = lib
          .lookup<ffi.NativeFunction<_OneStrToStrNative>>(
              'wdmm_manga_get_progress')
          .asFunction();
      _mangaSetProgress = lib
          .lookup<ffi.NativeFunction<_StrInt64ToStrNative>>(
              'wdmm_manga_set_progress')
          .asFunction();
      _mangaListProgress = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>(
              'wdmm_manga_list_progress')
          .asFunction();
      _mangaListSeries = lib
          .lookup<ffi.NativeFunction<_NoArgToStrNative>>(
              'wdmm_manga_list_series')
          .asFunction();
      _mangaSymbolsLoaded = true;
    } catch (e) {
      debugPrint('[RustCore] Wave D manga symbol lookup failed (non-fatal): $e');
    }
  }

  /// Ensure Wave D manga symbols are loaded. Returns true if usable.
  static bool _ensureMangaSymbols() {
    if (!_ensureSymbols()) return false;
    if (_mangaSymbolsLoaded) return true;
    _loadMangaSymbolsSafe();
    return _mangaSymbolsLoaded;
  }

  // ── Manga public API ──────────────────────────────────────────────────────

  /// List all manga rows as a JSON array string, or null if FFI unavailable.
  static String? mangaList() {
    if (!_ensureMangaSymbols() || _mangaList == null) return null;
    return _readAndFreeString(_mangaList!());
  }

  /// Get one manga by [id]. Returns a JSON object, `"null"` if absent, or
  /// `"error:…"` on failure. Returns null if FFI unavailable.
  static String? mangaGet(String id) {
    if (!_ensureMangaSymbols() || _mangaGet == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Upsert one manga. [json] is the manga serialised to a JSON object.
  /// Returns `"ok"` or `"error:…"`, null if FFI unavailable.
  static String? mangaUpsert(String json) {
    if (!_ensureMangaSymbols() || _mangaUpsert == null) return null;
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaUpsert!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Delete a manga by [id] (cascades to pages + progress; writes tombstone).
  /// Returns `"ok"`, `"not_found"`, or `"error:…"`. Null if FFI unavailable.
  static String? mangaDelete(String id) {
    if (!_ensureMangaSymbols() || _mangaDelete == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Clear a single `deleted_mangas` tombstone by [syncKey].
  /// Returns `"ok"` or `"error:…"`. Null if FFI unavailable.
  static String? deletedMangaClear(String syncKey) {
    if (!_ensureMangaSymbols() || _deletedMangaClear == null) return null;
    final ptr = syncKey.toNativeUtf8();
    try {
      return _readAndFreeString(_deletedMangaClear!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Wipe manga index (mangas / pages / deleted_mangas / manga sync cursors).
  /// Keeps manga_progress. Returns `"ok"` or `"error:…"`. Null if FFI unavailable.
  static String? mangaClearIndex() {
    if (!_ensureMangaSymbols() || _mangaClearIndex == null) return null;
    try {
      return _readAndFreeString(_mangaClearIndex!());
    } catch (e) {
      debugPrint('[RustCore] mangaClearIndex exception: $e');
      return null;
    }
  }

  /// List pages for [mangaId] as a JSON array. Null if FFI unavailable.
  static String? mangaListPages(String mangaId) {
    if (!_ensureMangaSymbols() || _mangaListPages == null) return null;
    final ptr = mangaId.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaListPages!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Replace all pages for [mangaId]. [jsonArray] is a JSON array of
  /// `{"manga_id","page_index","rel_path"}` objects.
  /// Returns `"ok"` or `"error:…"`, null if FFI unavailable.
  static String? mangaSetPages(String mangaId, String jsonArray) {
    if (!_ensureMangaSymbols() || _mangaSetPages == null) return null;
    final mid = mangaId.toNativeUtf8();
    final arr = jsonArray.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaSetPages!(mid, arr));
    } finally {
      calloc.free(mid);
      calloc.free(arr);
    }
  }

  /// Get reading progress for [mangaId]. Returns a JSON object, `"null"`, or
  /// `"error:…"`. Null if FFI unavailable.
  static String? mangaGetProgress(String mangaId) {
    if (!_ensureMangaSymbols() || _mangaGetProgress == null) return null;
    final ptr = mangaId.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaGetProgress!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Set reading progress for [mangaId] to [pageIndex] (0-based).
  /// Returns `"ok"` or `"error:…"`, null if FFI unavailable.
  static String? mangaSetProgress(String mangaId, int pageIndex) {
    if (!_ensureMangaSymbols() || _mangaSetProgress == null) return null;
    final ptr = mangaId.toNativeUtf8();
    try {
      return _readAndFreeString(_mangaSetProgress!(ptr, pageIndex));
    } finally {
      calloc.free(ptr);
    }
  }

  /// List reading progress for all mangas as a JSON array. Null if unavailable.
  static String? mangaListProgress() {
    if (!_ensureMangaSymbols() || _mangaListProgress == null) return null;
    return _readAndFreeString(_mangaListProgress!());
  }

  /// List distinct series tags as a JSON array of `{"id","title"}` objects.
  /// Null if FFI unavailable.
  static String? mangaListSeries() {
    if (!_ensureMangaSymbols() || _mangaListSeries == null) return null;
    return _readAndFreeString(_mangaListSeries!());
  }

  // ── Wave C driver/account API ────────────────────────────────────────────────

  // ── Account CRUD ─────────────────────────────────────────────────────────────

  /// List all accounts. Returns JSON array or `"error:…"`. Null if FFI unavailable.
  static String? accountList() {
    if (!_ensureSymbols() || _accountList == null) return null;
    return _readAndFreeString(_accountList!());
  }

  /// Get account by [id]. Returns JSON object, `"null"` if absent, or `"error:…"`.
  /// Null if FFI unavailable.
  static String? accountGet(String id) {
    if (!_ensureSymbols() || _accountGet == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_accountGet!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Upsert account. [json] is the account JSON object.
  /// Returns `"ok"` or `"error:…"`. Null if FFI unavailable.
  static String? accountUpsert(String json) {
    if (!_ensureSymbols() || _accountUpsert == null) return null;
    final ptr = json.toNativeUtf8();
    try {
      return _readAndFreeString(_accountUpsert!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Delete account by [id]. Returns `"ok"` or `"error:…"`. Null if FFI unavailable.
  static String? accountDelete(String id) {
    if (!_ensureSymbols() || _accountDelete == null) return null;
    final ptr = id.toNativeUtf8();
    try {
      return _readAndFreeString(_accountDelete!(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  // ── Account file operations ──────────────────────────────────────────────────

  /// List entries at [path] using the driver for [providerType] with [configJson].
  /// Returns JSON array of entries or `"error:…"`. Null if FFI unavailable.
  static String? driverList(String providerType, String configJson, String path) {
    if (!_ensureSymbols() || _driverList == null) return null;
    final pType = providerType.toNativeUtf8();
    final pConf = configJson.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_driverList!(pType, pConf, pPath));
    } finally {
      calloc.free(pType);
      calloc.free(pConf);
      calloc.free(pPath);
    }
  }

  /// Create directory at [path]. Returns `"ok"` or `"error:…"`. Null if unavailable.
  static String? driverMkdir(String providerType, String configJson, String path) {
    if (!_ensureSymbols() || _driverMkdir == null) return null;
    final pType = providerType.toNativeUtf8();
    final pConf = configJson.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_driverMkdir!(pType, pConf, pPath));
    } finally {
      calloc.free(pType);
      calloc.free(pConf);
      calloc.free(pPath);
    }
  }

  /// Rename [oldPath] to [newPath]. Returns `"ok"` or `"error:…"`. Null if unavailable.
  static String? driverRename(String providerType, String configJson, String oldPath, String newPath) {
    if (!_ensureSymbols() || _driverRename == null) return null;
    final pType = providerType.toNativeUtf8();
    final pConf = configJson.toNativeUtf8();
    final pOld = oldPath.toNativeUtf8();
    final pNew = newPath.toNativeUtf8();
    try {
      return _readAndFreeString(_driverRename!(pType, pConf, pOld, pNew));
    } finally {
      calloc.free(pType);
      calloc.free(pConf);
      calloc.free(pOld);
      calloc.free(pNew);
    }
  }

  /// Remove entry at [path]. Returns `"ok"` or `"error:…"`. Null if unavailable.
  static String? driverRemove(String providerType, String configJson, String path) {
    if (!_ensureSymbols() || _driverRemove == null) return null;
    final pType = providerType.toNativeUtf8();
    final pConf = configJson.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_driverRemove!(pType, pConf, pPath));
    } finally {
      calloc.free(pType);
      calloc.free(pConf);
      calloc.free(pPath);
    }
  }

  /// Get metadata for entry at [path]. Returns JSON entry or `"error:…"`. Null if unavailable.
  static String? driverGet(String providerType, String configJson, String path) {
    if (!_ensureSymbols() || _driverGet == null) return null;
    final pType = providerType.toNativeUtf8();
    final pConf = configJson.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_driverGet!(pType, pConf, pPath));
    } finally {
      calloc.free(pType);
      calloc.free(pConf);
      calloc.free(pPath);
    }
  }

  /// List entries at [path] for [accountId]. Returns JSON array or `"error:…"`. Null if unavailable.
  static String? accountListDir(String accountId, String path) {
    if (!_ensureSymbols() || _accountListDir == null) return null;
    final pAcc = accountId.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_accountListDir!(pAcc, pPath));
    } finally {
      calloc.free(pAcc);
      calloc.free(pPath);
    }
  }

  /// Create directory at [path] for [accountId]. Returns `"ok"` or `"error:…"`. Null if unavailable.
  static String? accountMkdir(String accountId, String path) {
    if (!_ensureSymbols() || _accountMkdir == null) return null;
    final pAcc = accountId.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_accountMkdir!(pAcc, pPath));
    } finally {
      calloc.free(pAcc);
      calloc.free(pPath);
    }
  }

  /// Rename [oldPath] to [newPath] for [accountId]. Returns `"ok"` or `"error:…"`. Null if unavailable.
  static String? accountRename(String accountId, String oldPath, String newPath) {
    if (!_ensureSymbols() || _accountRename == null) return null;
    final pAcc = accountId.toNativeUtf8();
    final pOld = oldPath.toNativeUtf8();
    final pNew = newPath.toNativeUtf8();
    try {
      return _readAndFreeString(_accountRename!(pAcc, pOld, pNew));
    } finally {
      calloc.free(pAcc);
      calloc.free(pOld);
      calloc.free(pNew);
    }
  }

  /// Remove entry at [path] for [accountId]. Returns `"ok"` or `"error:…"`. Null if unavailable.
  static String? accountRemove(String accountId, String path) {
    if (!_ensureSymbols() || _accountRemove == null) return null;
    final pAcc = accountId.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_accountRemove!(pAcc, pPath));
    } finally {
      calloc.free(pAcc);
      calloc.free(pPath);
    }
  }

  /// Get metadata for entry at [path] for [accountId]. Returns JSON entry or `"error:…"`. Null if unavailable.
  static String? accountGetEntry(String accountId, String path) {
    if (!_ensureSymbols() || _accountGetEntry == null) return null;
    final pAcc = accountId.toNativeUtf8();
    final pPath = path.toNativeUtf8();
    try {
      return _readAndFreeString(_accountGetEntry!(pAcc, pPath));
    } finally {
      calloc.free(pAcc);
      calloc.free(pPath);
    }
  }
}

// ignore: avoid_classes_with_only_static_members
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

// ── Feature flags ───────────────────────────────────────────────────────────

/// When true, [MangaLibraryService] routes manga index CRUD, reading progress,
/// and tombstones through the Rust FFI (wdmm_manga_* / wdmm_deleted_manga_clear).
/// Class B unload (2026-10-27): SyncService no longer reads sqflite
/// `deleted_mangas` — manga sync is Core-only (`MangaSyncEngine` via
/// `wdmm_sync_trigger` / `wdmm_sync_full`).
/// Accounts SoT is Core FFI; [LibraryDatabase] may still open for cache/etc.
// ignore: constant_identifier_names
const bool kRustMangaEnabled = true;
