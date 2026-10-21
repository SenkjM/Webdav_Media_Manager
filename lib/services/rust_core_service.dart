// ignore_for_file: unused_element, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

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
}

// ignore: avoid_classes_with_only_static_members
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

// ── Feature flags (Round 4 — not yet wired to UI) ───────────────────────────

/// When true, [RustCoreService.syncTrigger] is used alongside Dart sync.
/// Flip to true in a settings screen once the Rust sync path is validated.
// ignore: constant_identifier_names
const bool kRustSyncEnabled = false;
