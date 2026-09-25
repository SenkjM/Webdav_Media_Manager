# openlist_crypt

Pure-Dart implementation of the **rclone / OpenList `crypt` encrypted-storage
format**. Read and write remote directories whose contents and filenames are
encrypted by rclone's `crypt` backend or OpenList/Alist's crypt storage —
byte-for-byte wire compatible, verified against rclone v1.75.1 golden
vectors (`backend/crypt`).

No Flutter dependency: usable from any Dart 3.5+ project — Flutter apps,
CLI tools, or servers.

## What it implements

| Layer | Algorithm |
|---|---|
| Key derivation | scrypt (N=16384, r=8, p=1, dkLen=80) → dataKey[32] + nameKey[32] + nameTweak[16]; rclone's built-in default salt when salt is empty; empty password = all-zero keys (part of the format) |
| File content | `RCLONE\0\0` magic (8 B) + random file nonce (24 B) + 64 KiB plaintext blocks, each a NaCl secretbox (XSalsa20-Poly1305, 16 B MAC prefix). Block nonce = file nonce + block index (LE 64-bit add) |
| Filenames, standard mode | PKCS7(16) pad + EME wide-block AES-256 under nameTweak |
| Filenames, obfuscate mode | rclone's rotation cipher keyed by nameKey |
| Filenames, off mode | plaintext + configurable suffix (`.bin` default, OpenList `encrypted_suffix`) |
| Filename encoding | base32 (hex table, lowercase, unpadded) · base64 (URL-safe, no padding, OpenList default) · base32768 (rclone SafeEncoding) |
| Range access | per-block decrypt — random access without touching preceding blocks |

## Usage

```dart
import 'package:openlist_crypt/openlist_crypt.dart';

final cipher = RcloneCipher(
  password: 'testpass',
  salt: 'testsalt',          // '' → rclone default salt
  mode: NameEncryptionMode.standard,
  dirNameEncrypt: true,
  nameEncoding: 'base32',    // 'base32' | 'base64' | 'base32768'
);

// Filenames
final enc = cipher.encryptFileName('hello.txt'); // 9ph489uqiu6hppkcbp0g4328c4
final dir = cipher.encryptDirName('photos');     // ghd9crjufd2a4sartqaskk87rc
print(cipher.decryptFileName(enc));               // hello.txt

// File contents (whole buffer)
final plain = cipher.decrypt(cipherBytes);        // throws RcloneCipherException
final cipherBytes2 = cipher.encrypt(plain);       // random nonce per call

// Range access: read block #k only (the stream bridge in the host app
// serves media players this way — seek without re-downloading).
final header = cipherBytes.sublistView(0, kFileHeaderSize);
final nonce = RcloneCipher.fileNonceOf(header);
final block = cipher.decryptBlock(nonce, 3, cipherBytes.sublistView(
    kFileHeaderSize + 3 * kBlockSize,
    kFileHeaderSize + 4 * kBlockSize));

// Size arithmetic (no full decrypt needed for listings)
final cipherLen = RcloneCipher.encryptedSize(plainLen);
final plainLen2 = RcloneCipher.decryptedSize(cipherLen);
```

## Compatibility notes

* **base32768** — ported from [`github.com/Max-Sum/base32768`][base32768]
  (the Go library rclone itself depends on). The 1028-codepoint alphabet
  table (`lib/src/base32768_table.dart`) is generated from upstream; it is
  committed verbatim so the package has no codegen step.
* Golden vectors covering names, obfuscation, base64 encoding, suffixes, and
  content blocks come from rclone v1.75.1 `backend/crypt/cipher_test.go`,
  plus full-length base32768 round-trips (0–200 bytes) and NaCl secretbox
  reference vectors.
* OpenList/Alist use the same format; `filename_encoding=base64` is
  OpenList's default, `suffix`/`encrypted_suffix` and
  `directory_name_encryption` map 1:1.

## Testing

```bash
cd packages/openlist_crypt
dart pub get
dart test        # 31 tests, all golden-vector backed
```

## Credits & licensing

MIT. A Dart port of algorithms from [rclone][rclone] (MIT), and
[Max-Sum/base32768][base32768] (MIT); the secretbox/salsa20 layout follows
golang.org/x/crypto (BSD-3-Clause). See [LICENSE](LICENSE) for the full
text and attribution.

[rclone]: https://github.com/rclone/rclone
[base32768]: https://github.com/Max-Sum/base32768
