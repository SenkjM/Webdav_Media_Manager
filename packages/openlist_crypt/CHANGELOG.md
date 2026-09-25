## 0.1.0

Initial extraction from Webdav Media Manager (`lib/services/cloud_drivers/crypt/cipher/`).

Content encryption/decryption (XSalsa20-Poly1305 secretbox in 64 KiB blocks,
per-file random nonce, `RCLONE\0\0` magic header), filename encryption
(EME-AES-256 standard mode, rclone obfuscate mode, off mode with configurable
suffix), filename encodings (base32-hex-lower, base64 URL-safe no padding,
base32768), scrypt key derivation with rclone default salt, and size
arithmetic helpers. Golden vectors from rclone v1.75.1 `backend/crypt`.
