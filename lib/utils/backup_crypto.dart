import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Passphrase-based AES-256-GCM encryption for backup archives.
///
/// Wire format (bytes):
/// `WMPB1` (5) | salt(16) | nonce(12) | ciphertext+mac
class BackupCrypto {
  static const magic = 'WMPB1';
  static const _saltLen = 16;
  static const _nonceLen = 12;
  static const _iterations = 120000;

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  static final _aes = AesGcm.with256bits();

  static Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required String passphrase,
  }) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final secretKey = await _pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final secretBox = await _aes.encrypt(
      plaintext,
      secretKey: secretKey,
    );
    final out = BytesBuilder();
    out.add(utf8.encode(magic));
    out.add(salt);
    out.add(secretBox.nonce);
    out.add(secretBox.cipherText);
    out.add(secretBox.mac.bytes);
    return out.toBytes();
  }

  static Future<Uint8List> decrypt({
    required Uint8List data,
    required String passphrase,
  }) async {
    if (data.length < 5 + _saltLen + _nonceLen + 16) {
      throw FormatException('备份文件过短或损坏');
    }
    final magicBytes = utf8.encode(magic);
    for (var i = 0; i < magicBytes.length; i++) {
      if (data[i] != magicBytes[i]) {
        throw FormatException('不是加密备份（缺少 WMPB1 头）');
      }
    }
    var offset = 5;
    final salt = data.sublist(offset, offset + _saltLen);
    offset += _saltLen;
    final nonce = data.sublist(offset, offset + _nonceLen);
    offset += _nonceLen;
    final rest = data.sublist(offset);
    if (rest.length < 16) throw FormatException('备份密文损坏');
    final macBytes = rest.sublist(rest.length - 16);
    final cipherText = rest.sublist(0, rest.length - 16);
    final secretKey = await _pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final box = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    final clear = await _aes.decrypt(box, secretKey: secretKey);
    return Uint8List.fromList(clear);
  }

  static bool looksEncrypted(Uint8List data) {
    if (data.length < 5) return false;
    final m = utf8.encode(magic);
    for (var i = 0; i < m.length; i++) {
      if (data[i] != m[i]) return false;
    }
    return true;
  }
}
