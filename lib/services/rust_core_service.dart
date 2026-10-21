// ignore_for_file: unused_element, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Rust FFI bridge to WDMM-core via wdmm-ffi.
///
/// Currently loads only `wdmm_version` until flutter_rust_bridge codegen
/// is wired up. See android/app/build.gradle.kts for cargo-ndk build hook.
class RustCoreService {
  static ffi.DynamicLibrary? _lib;

  /// Load the native library once.
  static ffi.DynamicLibrary get lib {
    if (_lib != null) return _lib!;

    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libwdmm_ffi.so');
    } else if (Platform.isIOS) {
      // iOS: static linking or dylib path TBD
      throw UnsupportedError('iOS not yet configured');
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} not supported');
    }

    return _lib!;
  }

  // --- FFI function signatures (manually written until FRB codegen) ---

  /// Returns WDMM core version string pointer (caller must free).
  static ffi.Pointer<Utf8> Function() get _wdmm_version {
    return lib
        .lookup<ffi.NativeFunction<ffi.Pointer<Utf8> Function()>>('wdmm_version')
        .asFunction();
  }

  // --- Public API ---

  /// Get WDMM core version.
  static String getVersion() {
    final ptr = _wdmm_version();
    final version = ptr.toDartString();
    // TODO: call rust_free(ptr) once the FFI exports a free function
    return version;
  }
}
