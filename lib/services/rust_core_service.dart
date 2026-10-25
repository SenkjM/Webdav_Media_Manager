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
  static _Uint32ToStrDart? _dlnaDiscover;
  static _TwoStrToOneStrDart? _dlnaCast;
  static _VersionDart? _tokenGet; // no-arg → Utf8, same shape as version
  static _VersionDart? _tokenRotate; // no-arg → Utf8
  static _OneStrToStrDart? _dmrPrefsInit;
  static _NoArgToStrDart? _dmrPrefsList;
  static _OneStrToStrDart? _dmrPrefsGet;
  static _OneStrToStrDart? _dmrPrefsUpsert;
  static _OneStrToStrDart? _dmrPrefsDelete;
  static _StrStrToStrDart? _backupCreate;
  static _StrStrToStrDart? _backupRestore;

  // ── Wave C driver/account FFI ──────────────────────────────────────────────
  static _ThreeStrToOneStrDart? _driverList;
  static _ThreeStrToOneStrDart? _driverMkdir;
  static _FourStrToOneStrDart? _driverRename;
  static _ThreeStrToOneStrDart? _driverRemove;
  static _ThreeStrToOneStrDart? _driverGet;
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

// ── Feature flags (Round 4 — not yet wired to UI) ───────────────────────────

/// When true, [RustCoreService.syncTrigger] is used alongside Dart sync.
/// Flip to true in a settings screen once the Rust sync path is validated.
// ignore: constant_identifier_names
const bool kRustSyncEnabled = true;

/// When true, [MangaLibraryService] routes manga index CRUD and reading
/// progress through the Rust FFI (wdmm_manga_* symbols, Wave D) instead of
/// sqflite. [LibraryDatabase] remains the home of sync tombstones
/// (`deleted_mangas`) which [SyncService] still reads directly.
// ignore: constant_identifier_names
const bool kRustMangaEnabled = true;
