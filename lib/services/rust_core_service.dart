// ignore_for_file: unused_element, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
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
}

// ignore: avoid_classes_with_only_static_members
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
