import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'secretbox_dart.dart' show kSecretboxOverhead;

/// Optional libsodium FFI backend for NaCl secretbox only
/// (`crypto_secretbox_easy` / `crypto_secretbox_open_easy`).
///
/// Layout matches the pure-Dart path and rclone crypt: `tag(16) || ciphertext`,
/// 24-byte nonce, 32-byte key.
///
/// Load strategy (first success wins):
/// 1. `OPENLIST_CRYPT_LIBSODIUM_PATH` absolute path (tests / custom installs)
/// 2. Android packaged `libsodium.so` (jniLibs)
/// 3. Common Linux sonames (`libsodium.so.26`, `.23`, `libsodium.so`)
///
/// On this package's Linux CI/box there is usually no Android `.so`; unit tests
/// exercise the Dart path by default and optionally the system libsodium when
/// present. On a device APK that ships `native/android/arm64-v8a/libsodium.so`
/// via the app's jniLibs, [tryLoadLibsodium] succeeds after install.

typedef _SodiumInitNative = Int32 Function();
typedef _SodiumInitDart = int Function();

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

typedef _EasyNative = Int32 Function(
  Pointer<Uint8> c,
  Pointer<Uint8> m,
  Uint64 mlen,
  Pointer<Uint8> n,
  Pointer<Uint8> k,
);
typedef _EasyDart = int Function(
  Pointer<Uint8> c,
  Pointer<Uint8> m,
  int mlen,
  Pointer<Uint8> n,
  Pointer<Uint8> k,
);

typedef _OpenEasyNative = Int32 Function(
  Pointer<Uint8> m,
  Pointer<Uint8> c,
  Uint64 clen,
  Pointer<Uint8> n,
  Pointer<Uint8> k,
);
typedef _OpenEasyDart = int Function(
  Pointer<Uint8> m,
  Pointer<Uint8> c,
  int clen,
  Pointer<Uint8> n,
  Pointer<Uint8> k,
);

DynamicLibrary? _lib;
_EasyDart? _easy;
_OpenEasyDart? _openEasy;
String? _loadedPath;
String? _loadError;
bool _loadAttempted = false;

/// Absolute path that successfully loaded, or null.
String? get libsodiumLoadedPath => _loadedPath;

/// Last load failure message (for diagnostics); null if never failed or OK.
String? get libsodiumLoadError => _loadError;

/// Whether libsodium FFI bindings are ready (`sodium_init` succeeded).
bool get libsodiumSecretboxReady => _easy != null && _openEasy != null;

List<String> _candidatePaths() {
  final env = Platform.environment['OPENLIST_CRYPT_LIBSODIUM_PATH'];
  final out = <String>[];
  if (env != null && env.isNotEmpty) out.add(env);
  if (Platform.isAndroid) {
    out.add('libsodium.so');
  }
  if (Platform.isLinux) {
    out.addAll([
      'libsodium.so.26',
      'libsodium.so.23',
      'libsodium.so',
      '/usr/lib/x86_64-linux-gnu/libsodium.so.23',
      '/usr/lib/aarch64-linux-gnu/libsodium.so.23',
    ]);
  }
  if (Platform.isMacOS) {
    out.addAll(['libsodium.dylib', '/usr/local/lib/libsodium.dylib', '/opt/homebrew/lib/libsodium.dylib']);
  }
  return out;
}

/// Attempt to load libsodium. Idempotent; returns whether bindings are ready.
bool tryLoadLibsodium({bool forceReload = false}) {
  if (!forceReload && _loadAttempted) return libsodiumSecretboxReady;
  _loadAttempted = true;
  _lib = null;
  _easy = null;
  _openEasy = null;
  _loadedPath = null;
  _loadError = null;

  Object? lastErr;
  for (final path in _candidatePaths()) {
    try {
      final lib = path.contains('/') || path.startsWith('.')
          ? DynamicLibrary.open(path)
          : DynamicLibrary.open(path);
      final init = lib.lookupFunction<_SodiumInitNative, _SodiumInitDart>('sodium_init');
      final rc = init();
      // sodium_init: 0 = success first time, 1 = already initialized, -1 = fail
      if (rc == -1) {
        lastErr = 'sodium_init returned -1 for $path';
        continue;
      }
      final easy = lib.lookupFunction<_EasyNative, _EasyDart>('crypto_secretbox_easy');
      final open = lib.lookupFunction<_OpenEasyNative, _OpenEasyDart>('crypto_secretbox_open_easy');
      _lib = lib;
      _easy = easy;
      _openEasy = open;
      _loadedPath = path;
      return true;
    } catch (e) {
      lastErr = e;
    }
  }
  _loadError = lastErr?.toString();
  return false;
}

/// libsodium version string when loaded, else null.
String? libsodiumVersionString() {
  if (!tryLoadLibsodium()) return null;
  try {
    final fn = _lib!.lookupFunction<_VersionNative, _VersionDart>('sodium_version_string');
    return fn().toDartString();
  } catch (_) {
    return null;
  }
}

Uint8List? secretboxOpenSodium(Uint8List box, Uint8List nonce24, Uint8List key32) {
  if (box.length < kSecretboxOverhead) return null;
  if (nonce24.length != 24 || key32.length != 32) return null;
  if (!tryLoadLibsodium()) {
    throw StateError('libsodium not loaded: $_loadError');
  }
  final open = _openEasy!;
  final mLen = box.length - kSecretboxOverhead;
  final mPtr = malloc<Uint8>(mLen == 0 ? 1 : mLen);
  final cPtr = malloc<Uint8>(box.length);
  final nPtr = malloc<Uint8>(24);
  final kPtr = malloc<Uint8>(32);
  try {
    cPtr.asTypedList(box.length).setAll(0, box);
    nPtr.asTypedList(24).setAll(0, nonce24);
    kPtr.asTypedList(32).setAll(0, key32);
    final rc = open(mPtr, cPtr, box.length, nPtr, kPtr);
    if (rc != 0) return null;
    return Uint8List.fromList(mPtr.asTypedList(mLen));
  } finally {
    malloc.free(mPtr);
    malloc.free(cPtr);
    malloc.free(nPtr);
    malloc.free(kPtr);
  }
}

Uint8List secretboxSealSodium(Uint8List msg, Uint8List nonce24, Uint8List key32) {
  if (nonce24.length != 24 || key32.length != 32) {
    throw ArgumentError('nonce must be 24 bytes and key 32 bytes');
  }
  if (!tryLoadLibsodium()) {
    throw StateError('libsodium not loaded: $_loadError');
  }
  final easy = _easy!;
  final cLen = msg.length + kSecretboxOverhead;
  final cPtr = malloc<Uint8>(cLen);
  final mPtr = malloc<Uint8>(msg.isEmpty ? 1 : msg.length);
  final nPtr = malloc<Uint8>(24);
  final kPtr = malloc<Uint8>(32);
  try {
    if (msg.isNotEmpty) {
      mPtr.asTypedList(msg.length).setAll(0, msg);
    }
    nPtr.asTypedList(24).setAll(0, nonce24);
    kPtr.asTypedList(32).setAll(0, key32);
    final rc = easy(cPtr, mPtr, msg.length, nPtr, kPtr);
    if (rc != 0) {
      throw StateError('crypto_secretbox_easy failed ($rc)');
    }
    return Uint8List.fromList(cPtr.asTypedList(cLen));
  } finally {
    malloc.free(cPtr);
    malloc.free(mPtr);
    malloc.free(nPtr);
    malloc.free(kPtr);
  }
}
