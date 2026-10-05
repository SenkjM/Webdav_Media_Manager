## 0.2.0

Write-side encryption API:

- `RcloneCipher.encryptBlock(fileNonce, blockIndex, plainBlock)` — inverse
  of `decryptBlock`; per-block sealing for upload pipelines with strict
  block-boundary and size validation.
- `RcloneCipher.encrypt(plain, {nonce})` — optional explicit nonce for
  deterministic output (golden vectors / resume scenarios); random by default.
- `RcloneCipher.randomFileNonce()` — 24-byte CSPRNG file nonce.
- `RcloneStreamEncrypter` — push-mode streaming encrypter (O(64 KiB) memory,
  arbitrary chunk sizes, `cipherBytesProduced` progress counter).
- 14 new tests: block round-trips, cross-checks against whole-buffer encrypt,
  random-chunk streaming equivalence, empty file, misuse guards, fixed-nonce
  golden vector. Suite total 45/45.

## 0.1.0

Initial extraction from Webdav Media Manager (`lib/services/cloud_drivers/crypt/cipher/`).

Content encryption/decryption (XSalsa20-Poly1305 secretbox in 64 KiB blocks,
per-file random nonce, `RCLONE\0\0` magic header), filename encryption
(EME-AES-256 standard mode, rclone obfuscate mode, off mode with configurable
suffix), filename encodings (base32-hex-lower, base64 URL-safe no padding,
base32768), scrypt key derivation with rclone default salt, and size
arithmetic helpers. Golden vectors from rclone v1.75.1 `backend/crypt`.

## 0.2.1 (unreleased experiment)

* Optional libsodium FFI backend for content secretbox only (`preferLibsodiumSecretbox`,
  `--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`). Pure-Dart path remains default.
* Vendored Android `arm64-v8a` libsodium 1.0.20 under `native/` (ISC notice retained).
