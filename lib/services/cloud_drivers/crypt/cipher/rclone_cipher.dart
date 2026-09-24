import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'eme.dart';
import 'name_codec.dart';
import 'secretbox.dart';

/// rclone crypt 文件格式（v1.75.1，OpenList 同格式）的 Dart 实现。
///
/// 内容：魔数 "RCLONE\\0\\0"(8) + 随机 nonce(24)，之后按 64KiB 明文分块，
/// 每块 secretbox（XSalsa20-Poly1305，16B MAC 前缀），块 nonce = 文件 nonce
/// + 块号（LE 64 位加法）。名字：标准 = PKCS7(16) + EME(AES-256, nameTweak)
/// + Base32（Hex 表小写去填充）；off = 原名 + '.bin'（文件）/ 原名（目录）；
/// 混淆 = rclone obfuscate 方案。
const List<int> kFileMagic = [0x52, 0x43, 0x4C, 0x4F, 0x4E, 0x45, 0x00, 0x00]; // "RCLONE\0\0"
const int kFileHeaderSize = 32;
const int kBlockHeaderSize = 16;
const int kBlockDataSize = 64 * 1024;
const int kBlockSize = kBlockHeaderSize + kBlockDataSize;
const int kNameCipherBlockSize = 16;
const String kDefaultEncryptedSuffix = '.bin';

/// rclone 内置默认盐（cipher.go defaultSalt：盐为空时使用）。
final Uint8List kDefaultSaltBytes = Uint8List.fromList(const [0xA8, 0x0D, 0xF4, 0x3A, 0x8F, 0xBD, 0x03, 0x08, 0xA7, 0xCA, 0xB8, 0x3E, 0x58, 0x1F, 0x86, 0xB1]);
class RcloneCipherException implements Exception {
  const RcloneCipherException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum NameEncryptionMode { off, standard, obfuscate }

NameEncryptionMode nameModeFromConfig(String v) {
  switch (v) {
    case 'off':
      return NameEncryptionMode.off;
    case 'obfuscate':
      return NameEncryptionMode.obfuscate;
    case 'standard':
    case '':
      return NameEncryptionMode.standard;
    default:
      throw RcloneCipherException('未知文件名加密模式：$v');
  }
}

void _nonceAdd(Uint8List nonce, int x) {
  var carry = 0;
  for (var i = 0; i < 8; i++) {
    final s = nonce[i] + ((x >> (8 * i)) & 0xFF) + carry;
    nonce[i] = s & 0xFF;
    carry = s >> 8;
  }
}

/// rclone crypt cipher。
class RcloneCipher {
  RcloneCipher({
    required String password,
    required String salt,
    this.mode = NameEncryptionMode.standard,
    this.dirNameEncrypt = true,
    this.nameEncoding = 'base32',
    this.encryptedSuffix = kDefaultEncryptedSuffix,
  }) {
    _derive(password, salt);
  }

  final NameEncryptionMode mode;
  final bool dirNameEncrypt;

  /// 名字编码：'base32'（rclone 传统）或 'base64'（OpenList 默认）。
  /// base32768 暂不支持（同名条目解密失败会按坏名透传，不丢）。
  final String nameEncoding;

  /// filename_encryption=off 时附加的后缀（OpenList encrypted_suffix）。
  final String encryptedSuffix;
  late final Uint8List _dataKey;
  late final Uint8List _nameKey;
  late final Uint8List _nameTweak;
  late final EmeCipher _eme;

  void _derive(String password, String salt) {
    // rclone：空密码 = 全零密钥（格式的一部分，测试依赖）。
    final key = Uint8List(80);
    if (password.isNotEmpty) {
      final saltBytes = salt.isEmpty ? kDefaultSaltBytes : Uint8List.fromList(salt.codeUnits.map((c) => c & 0xFF).toList());
      final derivator = KeyDerivator('scrypt');
      derivator.init(ScryptParameters(16384, 8, 1, key.length, saltBytes));
      key.setAll(0, derivator.process(Uint8List.fromList(password.codeUnits)));
    }
    _dataKey = Uint8List.sublistView(key, 0, 32);
    _nameKey = Uint8List.sublistView(key, 32, 64);
    _nameTweak = Uint8List.sublistView(key, 64, 80);
    _eme = EmeCipher(_nameKey);
  }

  // ── 名字 ──

  String _encodeName(Uint8List ct) => nameEncoding == 'base64'
      ? base64UrlNoPadEncode(ct)
      : base32HexLowerEncode(ct);

  Uint8List _decodeName(String s) => nameEncoding == 'base64'
      ? base64UrlNoPadDecode(s)
      : base32HexLowerDecode(s);

  String _encryptSegment(String plaintext) {
    if (plaintext.isEmpty) return '';
    final padded = pkcs7Pad16(Uint8List.fromList(utf8.encode(plaintext)));
    final ct = _eme.transform(_nameTweak, padded, true);
    return _encodeName(ct);
  }

  String _decryptSegment(String ciphertext) {
    if (ciphertext.isEmpty) return '';
    final raw = _decodeName(ciphertext);
    if (raw.length % kNameCipherBlockSize != 0) {
      throw const RcloneCipherException('not a multiple of blocksize');
    }
    if (raw.length > 2048) {
      throw const RcloneCipherException('too long after decode');
    }
    final padded = _eme.transform(_nameTweak, raw, false);
    return utf8.decode(pkcs7Unpad16(padded));
  }

  String _mapPath(String path, bool encrypt, bool isDir) {
    final segments = path.split('/');
    for (var i = 0; i < segments.length; i++) {
      // dirNameEncrypt=false 时目录段不动（最后一文件段总是处理）。
      if (!dirNameEncrypt && i != segments.length - 1) continue;
      if (mode == NameEncryptionMode.standard) {
        segments[i] =
            encrypt ? _encryptSegment(segments[i]) : _decryptSegment(segments[i]);
      } else {
        segments[i] = encrypt
            ? obfuscateSegment(segments[i], _nameKey)
            : deobfuscateSegment(segments[i], _nameKey);
      }
    }
    return segments.join('/');
  }

  String encryptFileName(String name) {
    if (mode == NameEncryptionMode.off) return name + encryptedSuffix;
    return _mapPath(name, true, false);
  }

  String decryptFileName(String name) {
    if (mode == NameEncryptionMode.off) {
      if (!name.endsWith(encryptedSuffix) || encryptedSuffix.isEmpty) {
        throw const RcloneCipherException('suffix missing');
      }
      return name.substring(0, name.length - encryptedSuffix.length);
    }
    return _mapPath(name, false, false);
  }

  String encryptDirName(String name) {
    if (mode == NameEncryptionMode.off || !dirNameEncrypt) return name;
    return _mapPath(name, true, true);
  }

  String decryptDirName(String name) {
    if (mode == NameEncryptionMode.off || !dirNameEncrypt) return name;
    return _mapPath(name, false, true);
  }

  // ── 大小 ──

  static int encryptedSize(int plainSize) {
    final blocks = plainSize ~/ kBlockDataSize;
    final residue = plainSize % kBlockDataSize;
    var size = kFileHeaderSize + blocks * kBlockSize;
    if (residue != 0) size += kBlockHeaderSize + residue;
    return size;
  }

  static int decryptedSize(int cipherSize) {
    if (cipherSize < kFileHeaderSize) {
      throw const RcloneCipherException('file too short');
    }
    var size = cipherSize - kFileHeaderSize;
    final blocks = size ~/ kBlockSize;
    final residue = size % kBlockSize;
    var decrypted = blocks * kBlockDataSize;
    if (residue != 0) {
      final r = residue - kBlockHeaderSize;
      if (r <= 0) throw const RcloneCipherException('bad header');
      decrypted += r;
    }
    return decrypted;
  }

  // ── 内容 ──

  Uint8List _blockNonce(Uint8List fileNonce, int blockIndex) {
    final n = Uint8List.fromList(fileNonce);
    _nonceAdd(n, blockIndex);
    return n;
  }

  /// 全量加密（测试 / 未来上传）。随机 nonce。
  Uint8List encrypt(Uint8List plain) {
    final out = BytesBuilder();
    final nonce = Uint8List(24);
    final rnd = Random.secure();
    for (var i = 0; i < 24; i++) {
      nonce[i] = rnd.nextInt(256);
    }
    out.add(kFileMagic);
    out.add(nonce);
    var off = 0;
    var block = 0;
    while (off < plain.length) {
      final n = (plain.length - off) < kBlockDataSize
          ? (plain.length - off)
          : kBlockDataSize;
      out.add(secretboxSeal(
        Uint8List.sublistView(plain, off, off + n),
        _blockNonce(nonce, block),
        _dataKey,
      ));
      off += n;
      block++;
    }
    return out.toBytes();
  }

  /// 全量解密。任一块认证失败即抛（宁报错不落坏数据）。
  Uint8List decrypt(Uint8List cipher) {
    if (cipher.length < kFileHeaderSize) {
      throw const RcloneCipherException('file too short');
    }
    for (var i = 0; i < kFileMagic.length; i++) {
      if (cipher[i] != kFileMagic[i]) {
        throw const RcloneCipherException('bad magic');
      }
    }
    final nonce = Uint8List.sublistView(cipher, 8, 32);
    final out = BytesBuilder();
    var off = kFileHeaderSize;
    var block = 0;
    while (off < cipher.length) {
      final n = (cipher.length - off) < kBlockSize
          ? (cipher.length - off)
          : kBlockSize;
      final plain = secretboxOpen(
        Uint8List.sublistView(cipher, off, off + n),
        _blockNonce(nonce, block),
        _dataKey,
      );
      if (plain == null) {
        throw RcloneCipherException('bad block #$block');
      }
      out.add(plain);
      off += n;
      block++;
    }
    return out.toBytes();
  }
}
