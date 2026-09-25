import 'dart:typed_data';

import 'rclone_cipher.dart';

/// 逐块流式加密器：把明文按 rclone crypt 块边界喂入、密文按块吐出，
/// 内存占用 O(kBlockDataSize)，任意大文件都不必整体驻留。
///
/// 用法（推模式，适合上传管线）：
/// ```dart
/// final enc = RcloneStreamEncrypter(cipher, nonce: fileNonce);
/// sink.add(enc.header());            // 32B：魔数 + 文件 nonce
/// for (final chunk in plaintextChunks) {
///   for (final cipherBlock in enc.push(chunk)) {
///     sink.add(cipherBlock);         // 0 或多个整块密文
///   }
/// }
/// sink.add(enc.close());             // 余数块（≤1 个），可能为空
/// ```
///
/// 块边界纪律：[push] 内部自行按 [kBlockDataSize] 切块，调用方无需对齐；
/// [header] 与第一块密文之间不可插入其他字节；每个实例只能 close 一次。
/// 换个 nonce 加密新文件必须新建实例。
class RcloneStreamEncrypter {
  RcloneStreamEncrypter(this._cipher, {Uint8List? nonce})
      : _fileNonce = nonce == null
            ? RcloneCipher.randomFileNonce()
            : Uint8List.fromList(nonce) {
    if (_fileNonce.length != 24) {
      throw const RcloneCipherException('file nonce must be 24 bytes');
    }
  }

  final RcloneCipher _cipher;
  final Uint8List _fileNonce;
  final BytesBuilder _pending = BytesBuilder(copy: true);

  int _blockIndex = 0;
  int _produced = 0;
  bool _closed = false;
  bool _headerTaken = false;

  /// 文件头（32 字节：魔数 8 + 文件 nonce 24）。必须在第一块密文前写出。
  Uint8List header() {
    if (_headerTaken) {
      throw const RcloneCipherException('header already taken');
    }
    _headerTaken = true;
    final out = BytesBuilder();
    out.add(kFileMagic);
    out.add(_fileNonce);
    return out.toBytes();
  }

  /// 本加密器的文件 nonce（续传场景需与上传任务一起持久化）。
  Uint8List get fileNonce => Uint8List.fromList(_fileNonce);

  /// 已产出的密文总字节数（header 除外）。进度上报可用。
  ///
  /// 只统计**已封块**的输出（余数未封不计入）——值单调递增且恒 ≤
  /// 最终密文长度；close 后即为最终长度（不含 32B 文件头）。
  int get cipherBytesProduced => _produced;

  /// 喂入任意长度明文，返回 0 个或多个**整块**密文
  /// （每块 = 明文块 + 16B MAC）。调用方顺序写出即可。
  List<Uint8List> push(Uint8List chunk) {
    _ensureOpen();
    if (chunk.isEmpty) return const [];
    _pending.add(chunk);
    final out = <Uint8List>[];
    while (_pending.length >= kBlockDataSize) {
      // BytesBuilder 无「取前 N 字节」API，这里一次性 takeBytes 后回填余数。
      final all = _pending.takeBytes();
      final block = Uint8List.sublistView(all, 0, kBlockDataSize);
      final sealed = _cipher.encryptBlock(_fileNonce, _blockIndex, block);
      _produced += sealed.length;
      out.add(sealed);
      _blockIndex++;
      if (all.length > kBlockDataSize) {
        _pending.add(Uint8List.sublistView(all, kBlockDataSize));
      }
    }
    return out;
  }

  /// 收尾：加密不足一块的余数。空明文文件返回空列表（合法：密文 = 仅 32B 头）。
  List<Uint8List> close() {
    _ensureOpen();
    if (_closed) {
      throw const RcloneCipherException('already closed');
    }
    _closed = true;
    final rest = _pending.takeBytes();
    if (rest.isEmpty) return const [];
    final sealed = _cipher.encryptBlock(_fileNonce, _blockIndex, rest);
    _produced += sealed.length;
    return [sealed];
  }

  void _ensureOpen() {
    if (_closed) {
      throw const RcloneCipherException('already closed');
    }
    if (!_headerTaken) {
      throw const RcloneCipherException(
          'header() must be called before pushing plaintext');
    }
  }
}
