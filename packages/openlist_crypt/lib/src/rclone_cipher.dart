import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'eme.dart';
import 'base32768.dart';
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

/// 密钥材料长度：dataKey[32] + nameKey[32] + nameTweak[16]。
const int kKeyMaterialLength = 80;

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

/// scrypt(N=16384, r=8, p=1, dkLen=80) → dataKey[32] + nameKey[32] + nameTweak[16]。
///
/// 空密码 = 全零密钥（rclone 的格式的一部分，测试依赖）。纯计算、不碰任何
/// 共享状态，因此可以直接搬进 [Isolate.run]（见 [deriveKeyMaterial]）。
Uint8List deriveKeyMaterialSync({
  required String password,
  required String salt,
}) {
  final key = Uint8List(kKeyMaterialLength);
  if (password.isEmpty) return key;
  final saltBytes =
      salt.isEmpty ? kDefaultSaltBytes : Uint8List.fromList(utf8.encode(salt));
  final derivator = KeyDerivator('scrypt');
  derivator.init(ScryptParameters(16384, 8, 1, key.length, saltBytes));
  key.setAll(0, derivator.process(Uint8List.fromList(utf8.encode(password))));
  return key;
}

/// [deriveKeyMaterialSync] 的异步版：把 scrypt 丢进独立 isolate 跑。
///
/// 单次派生在中端安卓机上是数百毫秒级（桌面约 100ms），跑在主 isolate 上
/// 就是一次肉眼可见的卡顿。返回值与同步版逐字节相同（黄金向量见测试）。
///
/// 调用方自己决定要不要缓存结果——密钥材料是密码 + 盐的纯函数，进程内
/// 复用不会让任何映射失效（名字 / 内容加解密都是密钥的确定性函数）。
Future<Uint8List> deriveKeyMaterial({
  required String password,
  required String salt,
}) =>
    Isolate.run(
      () => deriveKeyMaterialSync(password: password, salt: salt),
    );

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
    _install(deriveKeyMaterialSync(password: password, salt: salt));
  }

  /// 用已派生的 80 字节密钥材料构造（见 [deriveKeyMaterial]）。
  ///
  /// 给两条路用：把 scrypt 放在 isolate 里派生后在主 isolate 构造；以及在
  /// 同一个 isolate 内为多份配置复用同一份密钥材料。
  RcloneCipher.fromKeyMaterial(
    Uint8List material, {
    this.mode = NameEncryptionMode.standard,
    this.dirNameEncrypt = true,
    this.nameEncoding = 'base32',
    this.encryptedSuffix = kDefaultEncryptedSuffix,
  }) {
    if (material.length != kKeyMaterialLength) {
      throw RcloneCipherException(
          'key material must be $kKeyMaterialLength bytes');
    }
    _install(material);
  }

  final NameEncryptionMode mode;
  final bool dirNameEncrypt;

  /// 名字编码：'base32'（rclone 传统）或 'base64'（OpenList 默认）。
  /// base32768 与 rclone SafeEncoding 同表，见 base32768.dart。
  final String nameEncoding;

  /// filename_encryption=off 时附加的后缀（OpenList encrypted_suffix）。
  final String encryptedSuffix;
  late final Uint8List _dataKey;
  late final Uint8List _nameKey;
  late final Uint8List _nameTweak;
  late final EmeCipher _eme;

  void _install(Uint8List key) {
    _dataKey = Uint8List.sublistView(key, 0, 32);
    _nameKey = Uint8List.sublistView(key, 32, 64);
    _nameTweak = Uint8List.sublistView(key, 64, 80);
    _eme = EmeCipher(_nameKey);
  }

  // ── 名字 ──

  String _encodeName(Uint8List ct) {
    switch (nameEncoding) {
      case 'base64':
        return base64UrlNoPadEncode(ct);
      case 'base32768':
        return Base32768Encoding.safe.encode(ct);
      default:
        return base32HexLowerEncode(ct);
    }
  }

  Uint8List _decodeName(String s) {
    switch (nameEncoding) {
      case 'base64':
        return base64UrlNoPadDecode(s);
      case 'base32768':
        return Base32768Encoding.safe.decode(s);
      default:
        return base32HexLowerDecode(s);
    }
  }

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
    final size = cipherSize - kFileHeaderSize;
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

  /// 生成 24 字节密码学随机文件 nonce（加密新文件用；断点续传场景应在
  /// 开始前生成并随任务持久化，重试时复用同一个）。
  static Uint8List randomFileNonce() {
    final n = Uint8List(24);
    final rnd = Random.secure();
    for (var i = 0; i < 24; i++) {
      n[i] = rnd.nextInt(256);
    }
    return n;
  }

  static Uint8List _validatedNonce(Uint8List? nonce) {
    if (nonce == null) return randomFileNonce();
    if (nonce.length != 24) {
      throw const RcloneCipherException('file nonce must be 24 bytes');
    }
    return Uint8List.fromList(nonce);
  }

  /// 加密单个明文块，[decryptBlock] 的逆（上传管线按块写远端用）。
  ///
  /// 块边界纪律：除最后一块外每块必须恰为 [kBlockDataSize] 字节——块号
  /// 参与块 nonce，错位会让远端密文整体不可解。[plainBlock] 上限
  /// [kBlockDataSize]；返回值 = 明文 + 16 字节 MAC 前缀。
  Uint8List encryptBlock(
    Uint8List fileNonce,
    int blockIndex,
    Uint8List plainBlock,
  ) {
    if (fileNonce.length != 24) {
      throw const RcloneCipherException('file nonce must be 24 bytes');
    }
    if (blockIndex < 0) {
      throw const RcloneCipherException('block index must be >= 0');
    }
    if (plainBlock.length > kBlockDataSize) {
      throw const RcloneCipherException('block too large');
    }
    return secretboxSeal(
      plainBlock,
      _blockNonce(fileNonce, blockIndex),
      _dataKey,
    );
  }

  /// 全量加密。[nonce] 缺省每次随机生成；指定后输出可复现
  /// （黄金向量 / 续传复用同一 nonce 的场景）。大文件流式加密用
  /// RcloneStreamEncrypter。
  Uint8List encrypt(Uint8List plain, {Uint8List? nonce}) {
    final n = _validatedNonce(nonce);
    final out = BytesBuilder();
    out.add(kFileMagic);
    out.add(n);
    var off = 0;
    var block = 0;
    while (off < plain.length) {
      final len = (plain.length - off) < kBlockDataSize
          ? (plain.length - off)
          : kBlockDataSize;
      out.add(encryptBlock(
        n,
        block,
        Uint8List.sublistView(plain, off, off + len),
      ));
      off += len;
      block++;
    }
    return out.toBytes();
  }

  /// 校验文件头并取出 24 字节文件 nonce（分段读取用）。
  static Uint8List fileNonceOf(Uint8List header) {
    if (header.length < kFileHeaderSize) {
      throw const RcloneCipherException('file too short');
    }
    for (var i = 0; i < kFileMagic.length; i++) {
      if (header[i] != kFileMagic[i]) {
        throw const RcloneCipherException('bad magic');
      }
    }
    return Uint8List.fromList(Uint8List.sublistView(header, 8, 32));
  }

  /// 解密单个密文块（[blockIndex] 从 0 起，块长 = 明文长 + 16 字节 MAC）。
  /// 分段读取用：每块独立认证，坏块立即抛错，不必等整文件。
  Uint8List decryptBlock(
    Uint8List fileNonce,
    int blockIndex,
    Uint8List cipherBlock,
  ) {
    final plain = secretboxOpen(
      cipherBlock,
      _blockNonce(fileNonce, blockIndex),
      _dataKey,
    );
    if (plain == null) {
      throw RcloneCipherException('bad block #$blockIndex');
    }
    return plain;
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
