import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Per-field passphrase encryption used by the WebDAV credential vault.
///
/// The vault keeps the WebDAV **URL and username in plain text** (so an
/// operator can still identify which server an account points at, and so the
/// file can be inspected without the passphrase) and encrypts **only the
/// password**. Wire format:
///
/// `<AESGCMv1:><base64(salt|nonce|ciphertext|mac)>`, so an encrypted value is
/// trivially distinguishable from a plaintext one.
class CredentialVaultCrypto {
  static const prefix = 'AESGCMv1:';
  static const _saltLen = 16;
  static const _nonceLen = 12;
  static const _iterations = 120000;

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  static bool isEncrypted(String? value) =>
      value != null && value.startsWith(prefix);

  /// Encrypt [plaintext] with [passphrase].
  static Future<String> encrypt({
    required String plaintext,
    required String passphrase,
  }) async {
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLen, (_) => _random.nextInt(256)),
    );
    final key = await _pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: key);
    final out = BytesBuilder()
      ..add(salt)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return '$prefix${base64Encode(out.toBytes())}';
  }

  /// Decrypt a value produced by [encrypt]. Throws when the passphrase is
  /// wrong or the payload is corrupt.
  static Future<String> decrypt({
    required String encoded,
    required String passphrase,
  }) async {
    if (!isEncrypted(encoded)) return encoded;
    final raw = base64Decode(encoded.substring(prefix.length));
    if (raw.length < _saltLen + _nonceLen + 16) {
      throw const FormatException('凭证密文损坏');
    }
    var offset = 0;
    final salt = raw.sublist(offset, offset + _saltLen);
    offset += _saltLen;
    final nonce = raw.sublist(offset, offset + _nonceLen);
    offset += _nonceLen;
    final rest = raw.sublist(offset);
    final mac = rest.sublist(rest.length - 16);
    final cipherText = rest.sublist(0, rest.length - 16);
    final key = await _pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  /// Try to decrypt, returning null instead of throwing.
  ///
  /// Used when a sync/import provides a passphrase that may not match the one
  /// that encrypted an account's password: the caller then **leaves the
  /// password empty** and restores the rest of the account.
  static Future<String?> tryDecrypt({
    required String encoded,
    required String passphrase,
  }) async {
    if (passphrase.isEmpty) return null;
    try {
      return await decrypt(encoded: encoded, passphrase: passphrase);
    } catch (_) {
      return null;
    }
  }
}
