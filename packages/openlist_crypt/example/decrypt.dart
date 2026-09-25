// Example: decrypt a file produced by `rclone crypt` / OpenList crypt
// storage, and print a directory listing translated back to plaintext names.
//
// Run with: dart run example/decrypt.dart <password> <salt> <file.bin>
// (salt may be empty to use rclone's built-in default salt)

import 'dart:io';
import 'dart:typed_data';

import 'package:openlist_crypt/openlist_crypt.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
        'usage: dart run example/decrypt.dart <password> <file> [salt]');
    exitCode = 64;
    return;
  }
  final password = args[0];
  final file = File(args[1]);
  final salt = args.length > 2 ? args[2] : '';

  final cipher = RcloneCipher(
    password: password,
    salt: salt,
    mode: NameEncryptionMode.standard,
    dirNameEncrypt: true,
  );

  final cipherBytes = Uint8List.fromList(file.readAsBytesSync());
  try {
    final plain = cipher.decrypt(cipherBytes);
    stdout.add(plain);
  } on RcloneCipherException catch (e) {
    stderr.writeln('decrypt failed: $e');
    exitCode = 1;
  }
}
