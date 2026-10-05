import 'dart:typed_data';

import 'secretbox_dart.dart';
import 'secretbox_sodium.dart';

export 'secretbox_dart.dart' show kSecretboxOverhead, secretboxOpenDart, secretboxSealDart;
export 'secretbox_sodium.dart'
    show
        libsodiumLoadError,
        libsodiumLoadedPath,
        libsodiumSecretboxReady,
        libsodiumVersionString,
        tryLoadLibsodium;

/// Which engine implements [secretboxOpen] / [secretboxSeal].
///
/// EME / filename codecs stay pure Dart regardless of this flag.
enum SecretboxBackend {
  /// Pure Dart XSalsa20-Poly1305 (default; always available).
  dart,

  /// libsodium `crypto_secretbox_*_easy` via FFI when the shared library loads.
  libsodium,
}

/// Active secretbox backend. Default [SecretboxBackend.dart].
///
/// Compile-time preference: `--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`
/// sets the initial value to [SecretboxBackend.libsodium] (still falls back
/// to Dart if the library cannot load, unless [secretboxRequireLibsodium]
/// is true).
SecretboxBackend secretboxBackend = const bool.fromEnvironment(
      'OPENLIST_CRYPT_LIBSODIUM',
      defaultValue: false,
    )
    ? SecretboxBackend.libsodium
    : SecretboxBackend.dart;

/// When true and backend is libsodium, missing FFI is an error instead of
/// silently using Dart. Useful for device experiments.
bool secretboxRequireLibsodium = false;

/// Prefer libsodium for content secretbox when the shared library is available.
/// Returns whether libsodium is ready after the call.
bool preferLibsodiumSecretbox({bool require = false}) {
  secretboxRequireLibsodium = require;
  final ok = tryLoadLibsodium();
  secretboxBackend = ok || require
      ? SecretboxBackend.libsodium
      : SecretboxBackend.dart;
  return ok;
}

/// Force the pure-Dart secretbox path (EME/name codecs unchanged).
void preferDartSecretbox() {
  secretboxRequireLibsodium = false;
  secretboxBackend = SecretboxBackend.dart;
}

bool _useSodium() {
  if (secretboxBackend != SecretboxBackend.libsodium) return false;
  if (tryLoadLibsodium()) return true;
  if (secretboxRequireLibsodium) {
    throw StateError(
      'libsodium secretbox required but library failed to load: $libsodiumLoadError',
    );
  }
  return false;
}

/// 密文认证失败返回 null；成功返回明文。
Uint8List? secretboxOpen(Uint8List box, Uint8List nonce24, Uint8List key32) {
  if (_useSodium()) {
    return secretboxOpenSodium(box, nonce24, key32);
  }
  return secretboxOpenDart(box, nonce24, key32);
}

/// box = tag(16) || ciphertext。
Uint8List secretboxSeal(Uint8List msg, Uint8List nonce24, Uint8List key32) {
  if (_useSodium()) {
    return secretboxSealSodium(msg, nonce24, key32);
  }
  return secretboxSealDart(msg, nonce24, key32);
}
