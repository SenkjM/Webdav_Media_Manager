/// 网易云音乐 API 加密（weapi / linuxapi）。
///
/// 移植自 OpenList `drivers/netease_music/crypto.go`（语义权威）与
/// `localdev/OpenList-Worker/src/backend/drivers/netease_music/crypto.ts`
/// （TS 底稿）。两版的算法逐字节一致，只有三处细节差异，本文件按
/// **Go 版**实现（v1 语义兜底优先）：
///
/// 1. `weapi` 内层结果是 **base64 字符串**再作为第二层 AES-CBC 的明文
///    （Go 版如此，也与 NeteaseCloudMusicApi 参考实现一致）；worker TS
///    直接把内层**字节**送进第二层，属于该版的实现疏漏。
/// 2. RSA 输出补足到 128 字节（worker 行为，长度恒定 256 hex）；
///    Go 的 `c.Bytes()` 会去掉前导零，服务端按大整数解析，两者等价。
/// 3. JSON 键顺序：Go 的 map 按 key 排序，worker 保留插入顺序。
///    服务端把明文当 JSON 解析，**键顺序无语义**；本文件用 Dart 的
///    插入顺序（同 worker），测试里两种顺序的向量都锁。
///
/// 与上游相同的部分（不可改）：预设密钥、IV、linuxapi 密钥、RSA 公钥
/// 指数 65537 与 128 字节缓冲中「密钥放在末 16 字节、前 112 字节为零」
/// 的布局、以及 linuxapi 输出**大写** hex。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 预设 AES 密钥（上游 `presetKey`）。
final Uint8List kNeteasePresetKey = Uint8List.fromList(utf8.encode('0CoJUm6Qyw8W8jud'));

/// 固定 IV（上游 `iv`）。
final Uint8List kNeteaseIv = Uint8List.fromList(utf8.encode('0102030405060708'));

/// linuxapi 的 AES-ECB 密钥（上游 `linuxapiKey`）。
final Uint8List kNeteaseLinuxApiKey =
    Uint8List.fromList(utf8.encode('rFgB&h#%2?^eDg:Q'));

/// 随机密钥的字符集（上游 `stdChars`）。
const String kNeteaseStdChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// 网易 weapi RSA 公钥的 modulus（1024 位 / 128 字节，hex）。
///
/// worker TS 硬编码该值；已用 Go 版 PEM 手工解析核对为**同一把密钥**
/// （见 `test/netease_music_crypto_test.dart` 的 modulus 一致性用例）。
const String kNeteaseRsaModulusHex =
    'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152'
    'b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbd'
    'a92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813'
    'cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

/// 网易 weapi 公钥 PEM（Go 版 `publicKey`，仅测试用于核对 modulus）。
const String kNeteaseRsaPublicKeyPem =
    '-----BEGIN PUBLIC KEY-----\n'
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB\n'
    '-----END PUBLIC KEY-----';

/// RSA 公钥指数（上游固定 65537）。
const int kNeteaseRsaExponent = 65537;

/// 上游 `aesKeyPending`：密钥不足 16 / 24 / 32 字节时**补零**，
/// 超过 32 字节截断。网易的 weapi 密钥可能短于 16（如空密钥）。
Uint8List neteaseAesKeyPending(List<int> key) {
  final k = key.length;
  final int count;
  if (k <= 16) {
    count = 16 - k;
  } else if (k <= 24) {
    count = 24 - k;
  } else if (k <= 32) {
    count = 32 - k;
  } else {
    return Uint8List.fromList(key.sublist(0, 32));
  }
  if (count == 0) return Uint8List.fromList(key);
  final out = Uint8List(k + count)..setRange(0, k, key);
  return out;
}

/// 标准 PKCS7 补齐（块长 16）。
Uint8List pkcs7Pad(List<int> src, [int blockSize = 16]) {
  final padding = blockSize - (src.length % blockSize);
  final out = Uint8List(src.length + padding)..setRange(0, src.length, src);
  out.fillRange(src.length, out.length, padding);
  return out;
}

/// AES-CBC 加密（PKCS7 补齐），语义同上游 `aesCBCEncrypt`。
Uint8List aesCbcEncrypt(List<int> src, List<int> key, List<int> iv) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  )..init(
      true,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV<KeyParameter>(
          KeyParameter(neteaseAesKeyPending(key)),
          Uint8List.fromList(iv),
        ),
        null,
      ),
    );
  return cipher.process(Uint8List.fromList(src));
}

/// AES-ECB 加密（PKCS7 补齐），语义同上游 `aesECBEncrypt`（逐块手动循环）。
///
/// 不用 `PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(...))` 是因为
/// 上游 Go 版本就是手写的逐块循环；这里保持同一形态，便于与向量对照。
Uint8List aesEcbEncrypt(List<int> src, List<int> key) {
  final engine = AESEngine()
    ..init(true, KeyParameter(neteaseAesKeyPending(key)));
  final padded = pkcs7Pad(src, engine.blockSize);
  final out = Uint8List(padded.length);
  final blockSize = engine.blockSize;
  for (var i = 0; i < padded.length; i += blockSize) {
    engine.processBlock(padded, i, out, i);
  }
  return out;
}

/// 大整数 → 定长大端字节（不足左侧补零；超长抛错）。
Uint8List bigIntToBytes(BigInt n, int length) {
  final bytes = <int>[];
  var v = n;
  while (v > BigInt.zero) {
    bytes.insert(0, (v & BigInt.from(0xFF)).toInt());
    v = v >> 8;
  }
  if (bytes.length > length) {
    throw StateError('大整数超出 $length 字节');
  }
  final out = Uint8List(length);
  out.setRange(length - bytes.length, length, bytes);
  return out;
}

/// 网易 raw RSA（无填充）：128 字节缓冲，密钥放**末 16 字节**（前 112 字节
/// 为零），`c = m^65537 mod n`，输出定长 128 字节。
///
/// 上游 Go 用 `c.Bytes()`（可能短于 128），worker 补足到 128；
/// 服务端按大整数解析，二者等价，本实现取补足版（长度恒定 256 hex）。
Uint8List neteaseRsaRawEncrypt(List<int> secretKey) {
  if (secretKey.length != 16) {
    throw ArgumentError.value(
        secretKey.length, 'secretKey', '网易 raw RSA 的密钥必须是 16 字节');
  }
  final full = Uint8List(128)..setRange(128 - 16, 128, secretKey);
  var m = BigInt.zero;
  for (final b in full) {
    m = (m << 8) | BigInt.from(b);
  }
  final n = BigInt.parse(kNeteaseRsaModulusHex, radix: 16);
  var result = BigInt.one;
  var base = m % n;
  var exp = kNeteaseRsaExponent;
  while (exp > 0) {
    if (exp & 1 == 1) result = (result * base) % n;
    base = (base * base) % n;
    exp >>= 1;
  }
  return bigIntToBytes(result, 128);
}

/// 随机 16 字节密钥（字符取自 [kNeteaseStdChars]，对齐上游 `getSecretKey`）。
({Uint8List key, Uint8List reversed}) neteaseSecretKey([Random? random]) {
  final rnd = random ?? Random.secure();
  final key = Uint8List(16);
  final reversed = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    final code = kNeteaseStdChars.codeUnitAt(rnd.nextInt(kNeteaseStdChars.length));
    key[i] = code;
    reversed[15 - i] = code;
  }
  return (key: key, reversed: reversed);
}

/// weapi 加密结果（对齐上游返回的两个表单字段）。
class WeapiResult {
  const WeapiResult({required this.params, required this.encSecKey});

  /// 两层 AES-CBC 后的 base64。
  final String params;

  /// raw RSA 后的 128 字节 hex（256 字符）。
  final String encSecKey;

  /// 表单编码（`params=...&encSecKey=...`）。
  Map<String, String> toForm() => {'params': params, 'encSecKey': encSecKey};
}

/// weapi 加密：AES-CBC(预设密钥) → base64 → AES-CBC(随机密钥的**逆序**) →
/// base64；随机密钥本身经 raw RSA 得到 `encSecKey`。
///
/// [secretKey] 仅测试用：传入固定 16 字节以产出确定性向量。
WeapiResult neteaseWeapi(Map<String, String> data, {List<int>? secretKey}) {
  final text = utf8.encode(jsonEncode(data));
  final generated = secretKey == null
      ? neteaseSecretKey()
      : (
          key: Uint8List.fromList(secretKey),
          reversed: Uint8List.fromList(secretKey.reversed.toList()),
        );

  final first = aesCbcEncrypt(text, kNeteasePresetKey, kNeteaseIv);
  // 关键：第二层的明文是**内层的 base64 字符串**，不是内层原始字节。
  final firstB64 = utf8.encode(base64.encode(first));
  final second = aesCbcEncrypt(firstB64, generated.reversed, kNeteaseIv);

  return WeapiResult(
    params: base64.encode(second),
    encSecKey: _hex(neteaseRsaRawEncrypt(generated.key)),
  );
}

/// linuxapi 加密：AES-ECB(linuxapi 密钥) → **大写** hex 的 `eparams`。
///
/// [body] 是待序列化的 {url, method, params} 结构，由调用方按需要的
/// 键顺序构造（键顺序无语义，见文件头注释）。
Map<String, String> neteaseLinuxapi(Map<String, dynamic> body) {
  final text = utf8.encode(jsonEncode(body));
  return {'eparams': _hex(aesEcbEncrypt(text, kNeteaseLinuxApiKey)).toUpperCase()};
}

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// 小写 hex（测试与 RSA 字段用；linuxapi 单独大写）。
String toHex(List<int> bytes) => _hex(bytes);
