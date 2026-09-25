/// Pure-Dart implementation of the rclone/OpenList **crypt** encrypted-storage
/// format.
///
/// Everything needed to read (and write) remote directories whose contents are
/// encrypted by rclone's `crypt` backend or OpenList/Alist's crypt storage —
/// byte-for-byte wire compatible, verified against rclone v1.75.1 golden
/// vectors.
///
/// ```dart
/// import 'package:openlist_crypt/openlist_crypt.dart';
///
/// final cipher = RcloneCipher(
///   password: 'testpass',
///   salt: 'testsalt',
///   mode: NameEncryptionMode.standard,
///   dirNameEncrypt: true,
/// );
///
/// // Filenames: plaintext path <-> encrypted path segment.
/// final encryptedName = cipher.encryptFileName('hello.txt'); // e.g. 9ph489...
/// final plain = cipher.decryptFileName(encryptedName);       // hello.txt
///
/// // File contents: full-buffer decrypt.
/// final bytes = cipher.decrypt(cipherBytes); // throws on bad block/MAC
/// ```
///
/// The format (rclone v1.75.1 `backend/crypt`, unchanged in OpenList):
///
/// * **Content** — `RCLONE\0\0` magic (8 B) + random file nonce (24 B), then
///   the plaintext split into 64 KiB blocks, each sealed as a NaCl secretbox
///   (XSalsa20-Poly1305, 16 B MAC prefix per block). Block nonce = file nonce
///   + block index (little-endian 64-bit addition), so any block can be
///   decrypted independently — that is what makes range requests cheap.
/// * **Names (standard)** — PKCS7(16) pad + EME wide-block AES-256 under
///   nameTweak, then base32 (hex table, lowercase, unpadded) / base64
///   (URL-safe, unpadded) / base32768 encoding.
/// * **Names (obfuscate)** — rclone's rotation cipher keyed by nameKey.
/// * **Names (off)** — plaintext name + `encryptedSuffix` (`.bin` by default)
///   for files; directories keep their plain names.
/// * **Keys** — scrypt(N=16384, r=8, p=1, dkLen=80) over password and salt
///   (a built-in default salt when empty), split into dataKey[32] +
///   nameKey[32] + nameTweak[16].
library;

export 'src/rclone_cipher.dart';
export 'src/secretbox.dart';
export 'src/base32768.dart';
export 'src/name_codec.dart';
