import 'dart:typed_data';

/// Salsa20 / HSalsa20 核心。
///
/// 字面移植 golang.org/x/crypto/salsa20/salsa（rclone crypt 格式依赖它）：
/// state = [Sigma0, k0..k3, Sigma1, in0..in3, Sigma2, k4..k7, Sigma3]，
/// 20 轮（10 个 double round），Salsa20 末尾做 feedforward，HSalsa20 不做。
const List<int> kSigmaWords = <int>[
  0x61707865, 0x3320646e, 0x79622d32, 0x6b206574, // "expand 32-byte k"
];

int _le32(Uint8List b, int i) =>
    b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

void _w32(Uint8List b, int i, int v) {
  b[i] = v & 0xFF;
  b[i + 1] = (v >> 8) & 0xFF;
  b[i + 2] = (v >> 16) & 0xFF;
  b[i + 3] = (v >> 24) & 0xFF;
}

int _rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF;

/// Salsa20 核心：64 字节块。feedforward=true 为 Salsa20（加密流），
/// false 为 HSalsa20 的中间态（配合 [hsalsa20Out] 取字）。
Uint32List _coreWords(Uint8List in16, Uint8List key32) {
  final j = Uint32List(16);
  j[0] = kSigmaWords[0];
  j[1] = _le32(key32, 0);
  j[2] = _le32(key32, 4);
  j[3] = _le32(key32, 8);
  j[4] = _le32(key32, 12);
  j[5] = kSigmaWords[1];
  j[6] = _le32(in16, 0);
  j[7] = _le32(in16, 4);
  j[8] = _le32(in16, 8);
  j[9] = _le32(in16, 12);
  j[10] = kSigmaWords[2];
  j[11] = _le32(key32, 16);
  j[12] = _le32(key32, 20);
  j[13] = _le32(key32, 24);
  j[14] = _le32(key32, 28);
  j[15] = kSigmaWords[3];
  final x = Uint32List.fromList(j);
  for (var i = 0; i < 20; i += 2) {
    var u = (x[0] + x[12]) & 0xFFFFFFFF;
    x[4] ^= _rotl(u, 7);
    u = (x[4] + x[0]) & 0xFFFFFFFF;
    x[8] ^= _rotl(u, 9);
    u = (x[8] + x[4]) & 0xFFFFFFFF;
    x[12] ^= _rotl(u, 13);
    u = (x[12] + x[8]) & 0xFFFFFFFF;
    x[0] ^= _rotl(u, 18);

    u = (x[5] + x[1]) & 0xFFFFFFFF;
    x[9] ^= _rotl(u, 7);
    u = (x[9] + x[5]) & 0xFFFFFFFF;
    x[13] ^= _rotl(u, 9);
    u = (x[13] + x[9]) & 0xFFFFFFFF;
    x[1] ^= _rotl(u, 13);
    u = (x[1] + x[13]) & 0xFFFFFFFF;
    x[5] ^= _rotl(u, 18);

    u = (x[10] + x[6]) & 0xFFFFFFFF;
    x[14] ^= _rotl(u, 7);
    u = (x[14] + x[10]) & 0xFFFFFFFF;
    x[2] ^= _rotl(u, 9);
    u = (x[2] + x[14]) & 0xFFFFFFFF;
    x[6] ^= _rotl(u, 13);
    u = (x[6] + x[2]) & 0xFFFFFFFF;
    x[10] ^= _rotl(u, 18);

    u = (x[15] + x[11]) & 0xFFFFFFFF;
    x[3] ^= _rotl(u, 7);
    u = (x[3] + x[15]) & 0xFFFFFFFF;
    x[7] ^= _rotl(u, 9);
    u = (x[7] + x[3]) & 0xFFFFFFFF;
    x[11] ^= _rotl(u, 13);
    u = (x[11] + x[7]) & 0xFFFFFFFF;
    x[15] ^= _rotl(u, 18);

    u = (x[0] + x[3]) & 0xFFFFFFFF;
    x[1] ^= _rotl(u, 7);
    u = (x[1] + x[0]) & 0xFFFFFFFF;
    x[2] ^= _rotl(u, 9);
    u = (x[2] + x[1]) & 0xFFFFFFFF;
    x[3] ^= _rotl(u, 13);
    u = (x[3] + x[2]) & 0xFFFFFFFF;
    x[0] ^= _rotl(u, 18);

    u = (x[5] + x[4]) & 0xFFFFFFFF;
    x[6] ^= _rotl(u, 7);
    u = (x[6] + x[5]) & 0xFFFFFFFF;
    x[7] ^= _rotl(u, 9);
    u = (x[7] + x[6]) & 0xFFFFFFFF;
    x[4] ^= _rotl(u, 13);
    u = (x[4] + x[7]) & 0xFFFFFFFF;
    x[5] ^= _rotl(u, 18);

    u = (x[10] + x[9]) & 0xFFFFFFFF;
    x[11] ^= _rotl(u, 7);
    u = (x[11] + x[10]) & 0xFFFFFFFF;
    x[8] ^= _rotl(u, 9);
    u = (x[8] + x[11]) & 0xFFFFFFFF;
    x[9] ^= _rotl(u, 13);
    u = (x[9] + x[8]) & 0xFFFFFFFF;
    x[10] ^= _rotl(u, 18);

    u = (x[15] + x[14]) & 0xFFFFFFFF;
    x[12] ^= _rotl(u, 7);
    u = (x[12] + x[15]) & 0xFFFFFFFF;
    x[13] ^= _rotl(u, 9);
    u = (x[13] + x[12]) & 0xFFFFFFFF;
    x[14] ^= _rotl(u, 13);
    u = (x[14] + x[13]) & 0xFFFFFFFF;
    x[15] ^= _rotl(u, 18);
  }
  return x;
}

/// Salsa20 keystream 块（feedforward 版）。
Uint8List salsa20Block(Uint8List in16, Uint8List key32) {
  final j = Uint32List(16);
  j[0] = kSigmaWords[0];
  j[1] = _le32(key32, 0);
  j[2] = _le32(key32, 4);
  j[3] = _le32(key32, 8);
  j[4] = _le32(key32, 12);
  j[5] = kSigmaWords[1];
  j[6] = _le32(in16, 0);
  j[7] = _le32(in16, 4);
  j[8] = _le32(in16, 8);
  j[9] = _le32(in16, 12);
  j[10] = kSigmaWords[2];
  j[11] = _le32(key32, 16);
  j[12] = _le32(key32, 20);
  j[13] = _le32(key32, 24);
  j[14] = _le32(key32, 28);
  j[15] = kSigmaWords[3];
  final x = _coreWords(in16, key32);
  final out = Uint8List(64);
  for (var i = 0; i < 16; i++) {
    _w32(out, i * 4, (x[i] + j[i]) & 0xFFFFFFFF);
  }
  return out;
}

/// HSalsa20：无 feedforward，输出字 z0, z5, z10, z15, z6, z7, z8, z9。
Uint8List hsalsa20(Uint8List in16, Uint8List key32) {
  final z = _coreWords(in16, key32);
  final out = Uint8List(32);
  for (var i = 0; i < 8; i++) {
    _w32(out, i * 4, z[<int>[0, 5, 10, 15, 6, 7, 8, 9][i]]);
  }
  return out;
}

/// Salsa20 流 XOR（Go genericXORKeyStream 语义）：[counter16] 是
/// 8 字节 nonce + 8 字节块计数器（LE，每 64 字节块递增）。
void salsa20Xor(
  Uint8List out,
  Uint8List input,
  int outOff,
  int inOff,
  int len,
  Uint8List counter16,
  Uint8List key32,
) {
  final c = Uint8List.fromList(counter16);
  var done = 0;
  while (done < len) {
    final block = salsa20Block(c, key32);
    final n = (len - done) < 64 ? (len - done) : 64;
    for (var i = 0; i < n; i++) {
      out[outOff + done + i] = input[inOff + done + i] ^ block[i];
    }
    var u = 1;
    for (var i = 8; i < 16; i++) {
      u += c[i];
      c[i] = u & 0xFF;
      u >>= 8;
    }
    done += n;
  }
}
