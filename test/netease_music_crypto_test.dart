// 网易云音乐（netease_music）weapi / linuxapi 加密的金标向量回归。
//
// 向量来源：从 OpenList Go 版 `drivers/netease_music/crypto.go` 编译出的
// 上游工具（只把 `getSecretKey()` 换成固定密钥以获得确定性输出），
// 生成结果固化在本文件中——与 crypt 的做法一致（[11 §7] 的测试策略：
// 优先用上游生成金标向量，而不是「两边同时跑起来比对」）。
//
// 覆盖：
//   - RSA modulus：worker TS 硬编码的 N_HEX == Go 版 PEM 的 modulus；
//   - raw RSA（无填充，密钥放末 16 字节，c = m^65537 mod n）；
//   - AES-CBC（预设密钥，第二层明文是内层 base64 字符串）；
//   - AES-ECB（linuxapi，输出大写 hex）；
//   - weapi / linuxapi 的完整输出。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/cloud_drivers/netease_music_crypto.dart';

/// 固定 16 字节密钥：ASCII "0123456789abcdef"。
final List<int> kFixedSecretKey = utf8.encode('0123456789abcdef');

/// Go 上游工具产出的向量（`go run .` → golden.json）。
const String kGoldenAesCbcPreset = 'g8Uyi6RhgxZQYHHeFWYyQzNvMCpJGM4tJ35lOBGeA3I=';
const String kGoldenAesEcbLinuxapi =
    'A0D9583F4C5FF68DE851D2893A49DE98EB5ED82623DE97FC5B2C33BF822A02E3C7B5FE886E6FAE4B2DF4B83CA80414AE'
    '7863C000529ABEA139CB1B4CAAB60DD3C3750991E197E7834A1CB5A7E22C0EB06B83FAF8DBFABA3150BAB26C3BDC68'
    'F798A80CF20843207D464E64FEA39C21BEFB86A683533B1A683C375796BC6F0A3C';
const String kGoldenLinuxapiWorkerOrder =
    '3134729CC09796CB31F2FFF45684A58FCFA972FA5EA3D6247CD6247C8198CB878588AFAA94B0E0C872FF37D6781726EE'
    'B744C5CDC5914382AEC70AD44947D2F727496CC1F9B4C3FE11F193E0A3E577DC636893A25F4A1093F3C145C6323F35F7'
    '3B3FD2350E52650636E8C49EE9EDFD1ABDDF2A378F55BEE59918B2C7146A2D0E';
const String kGoldenRsaRawHex =
    'ac744caab466f1fd5a75228365d15df7add288e8982a2c8f80da5f8f22d54834b5e1eab04dde9dac7341851a98de37463'
    'd8ba01d9e9c4d2c546c0f948e3163c667785a1b9c4f160305b0fb1ec3b698de0c704719b2fbc469582654b9c2595317dc'
    '40c3ecee32baa6d9753970b66667c01bde9ad34048fa8b2b0f628e56a5bf49';
const String kGoldenWeapiGetParams =
    'lIy2fgilVhtQddtJjyhJ0lcRvibfdvY/ielCDQoJ3Y2586R1yEsEGQ6pW94S/ke4';
const String kGoldenWeapiDelParams =
    'IyhNrvDB9u7Z0+TkXLI77v66fDll2u3EIw0GPcfvJtLm5EDkGgGBvYCU0N/iy42I';
const String kGoldenModulusHex =
    'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152'
    'b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbd'
    'a92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813'
    'cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

/// 从 PKIX PEM 手工取出 RSA modulus（DER 解析）。
///
/// 结构：SEQUENCE { SEQUENCE { OID, NULL }, BIT STRING {
///   SEQUENCE { INTEGER n, INTEGER e } } }。
/// 1024 位密钥的 modulus 是 129 字节的 INTEGER（首位 0x00 符号位）。
String _modulusFromPem(String pem) {
  final body = pem
      .replaceAll('-----BEGIN PUBLIC KEY-----', '')
      .replaceAll('-----END PUBLIC KEY-----', '')
      .replaceAll('\n', '');
  final der = base64.decode(body);
  for (var i = 0; i + 3 < der.length; i++) {
    // INTEGER 标签 0x02，长度 0x81 0x81（长形式，129 字节）
    if (der[i] == 0x02 && der[i + 1] == 0x81 && der[i + 2] == 0x81) {
      final mod = der.sublist(i + 3, i + 3 + 129);
      if (mod.length == 129 && mod[0] == 0x00) {
        return toHex(mod.sublist(1));
      }
    }
  }
  throw StateError('PEM 中找不到 modulus');
}

void main() {
  group('RSA 公钥：worker 的 N_HEX 与 Go 版 PEM 是同一把密钥', () {
    test('硬编码 modulus == PEM 解析出的 modulus', () {
      expect(kNeteaseRsaModulusHex, _modulusFromPem(kNeteaseRsaPublicKeyPem));
      expect(kNeteaseRsaModulusHex, kGoldenModulusHex);
    });

    test('modulus 长度 128 字节、指数 65537（上游固定值）', () {
      expect(kNeteaseRsaModulusHex.length, 256); // 128 字节 hex
      expect(kNeteaseRsaExponent, 65537);
    });
  });

  group('AES 原语', () {
    test('AES-CBC（预设密钥 + 固定 IV）匹配上游向量', () {
      final out = aesCbcEncrypt(
        utf8.encode('{"limit":"200","offset":"0"}'),
        kNeteasePresetKey,
        kNeteaseIv,
      );
      expect(base64.encode(out), kGoldenAesCbcPreset);
    });

    test('AES-ECB（linuxapi 密钥）匹配上游向量，输出为大写 hex', () {
      final out = aesEcbEncrypt(
        utf8.encode(
            '{"method":"POST","params":{"br":"999000","ids":"[123456]"},"url":"https://music.163.com/api/song/enhance/player/url"}'),
        kNeteaseLinuxApiKey,
      );
      expect(toHex(out).toUpperCase(), kGoldenAesEcbLinuxapi);
    });

    test('PKCS7 补齐：整块输入补满一整块', () {
      expect(pkcs7Pad(List.filled(15, 0)).length, 16);
      expect(pkcs7Pad(List.filled(16, 0)).length, 32);
      expect(pkcs7Pad(const []).length, 16);
      // 补齐字节的值 = 补齐长度
      final padded = pkcs7Pad(List.filled(13, 9));
      expect(padded.sublist(13), [3, 3, 3]);
    });

    test('aesKeyPending：不足补零到 16 / 24 / 32，超长截断到 32', () {
      expect(neteaseAesKeyPending(const []).length, 16);
      expect(neteaseAesKeyPending(List.filled(16, 1)).length, 16);
      expect(neteaseAesKeyPending(List.filled(17, 1)).length, 24);
      expect(neteaseAesKeyPending(List.filled(25, 1)).length, 32);
      expect(neteaseAesKeyPending(List.filled(40, 1)).length, 32);
      // 短密钥补的是零，不是循环
      expect(neteaseAesKeyPending(const [1, 2]).sublist(2), List.filled(14, 0));
    });
  });

  group('raw RSA（无填充）', () {
    test('固定密钥匹配上游向量', () {
      expect(toHex(neteaseRsaRawEncrypt(kFixedSecretKey)), kGoldenRsaRawHex);
    });

    test('输出恒为 128 字节（worker 的补足语义，256 hex）', () {
      final out = neteaseRsaRawEncrypt(kFixedSecretKey);
      expect(out.length, 128);
      // 对随机密钥也成立（go 的 c.Bytes() 会短，本实现补足）
      for (var i = 0; i < 8; i++) {
        final k = neteaseSecretKey().key;
        expect(neteaseRsaRawEncrypt(k).length, 128);
      }
    });

    test('密钥长度不是 16 字节时报错（上游布局：末 16 字节）', () {
      expect(() => neteaseRsaRawEncrypt(List.filled(15, 1)), throwsArgumentError);
      expect(() => neteaseRsaRawEncrypt(List.filled(17, 1)), throwsArgumentError);
    });

    test('密钥放末 16 字节：前 112 字节为零等价于小整数明文', () {
      // m = 0x00...00 || key，即 m = key 的大端整数。
      // c = m^65537 mod n 与直接用小整数做模幂等价。
      final m = kFixedSecretKey
          .fold<BigInt>(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));
      final n = BigInt.parse(kNeteaseRsaModulusHex, radix: 16);
      final expected = m.modPow(BigInt.from(65537), n);
      final actual = neteaseRsaRawEncrypt(kFixedSecretKey);
      var acc = BigInt.zero;
      for (final b in actual) {
        acc = (acc << 8) | BigInt.from(b);
      }
      expect(acc, expected);
    });
  });

  group('weapi 完整输出', () {
    test('cloud/get（limit/offset）匹配上游向量', () {
      final r = neteaseWeapi(
        const {'limit': '200', 'offset': '0'},
        secretKey: kFixedSecretKey,
      );
      expect(r.params, kGoldenWeapiGetParams);
      expect(r.encSecKey, kGoldenRsaRawHex);
    });

    test('cloud/del（songIds）匹配上游向量', () {
      final r = neteaseWeapi(
        const {'songIds': '[123456]'},
        secretKey: kFixedSecretKey,
      );
      expect(r.params, kGoldenWeapiDelParams);
      expect(r.encSecKey, kGoldenRsaRawHex);
    });

    test('encSecKey 恒为 256 个小写 hex 字符', () {
      for (var i = 0; i < 8; i++) {
        final r = neteaseWeapi(const {'limit': '1', 'offset': '0'});
        expect(r.encSecKey.length, 256);
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(r.encSecKey), isTrue);
      }
    });

    test('params 是合法 base64 且长度随明文变化', () {
      final r = neteaseWeapi(const {'limit': '1', 'offset': '0'});
      expect(() => base64.decode(r.params), returnsNormally);
      // 两层 AES-CBC 后仍是 16 的整数倍
      expect(base64.decode(r.params).length % 16, 0);
    });

    test('每次调用的 params 不同（随机密钥每次重新生成）', () {
      final a = neteaseWeapi(const {'limit': '1', 'offset': '0'});
      final b = neteaseWeapi(const {'limit': '1', 'offset': '0'});
      expect(a.params, isNot(b.params));
      expect(a.encSecKey, isNot(b.encSecKey));
    });

    test('随机密钥字符集限于 stdChars（62 个，上游同）', () {
      for (var i = 0; i < 64; i++) {
        final k = neteaseSecretKey().key;
        for (final c in k) {
          expect(kNeteaseStdChars.contains(String.fromCharCode(c)), isTrue);
        }
      }
      expect(kNeteaseStdChars.length, 62);
    });

    test('逆序密钥：内层用逆序、encSecKey 用原始（上游 getSecretKey 语义）', () {
      // 固定密钥下，若误用原始密钥做第二层，params 会与向量不符。
      final r = neteaseWeapi(
        const {'limit': '200', 'offset': '0'},
        secretKey: kFixedSecretKey,
      );
      expect(r.params, kGoldenWeapiGetParams,
          reason: '第二层必须用逆序密钥（reversed）');
    });

    test('第二层明文是内层 base64 字符串（Go 语义，非 worker 原始字节）', () {
      // 手工重算：AES-CBC(base64(AES-CBC(text, preset, iv)), reversed, iv)
      final text = utf8.encode('{"limit":"200","offset":"0"}');
      final inner = base64.encode(aesCbcEncrypt(text, kNeteasePresetKey, kNeteaseIv));
      final reversed = kFixedSecretKey.reversed.toList();
      final outer = aesCbcEncrypt(utf8.encode(inner), reversed, kNeteaseIv);
      expect(base64.encode(outer), kGoldenWeapiGetParams);
    });
  });

  group('linuxapi 完整输出', () {
    test('player/url（worker 键顺序 url, method, params）匹配上游向量', () {
      final r = neteaseLinuxapi({
        'url': 'https://music.163.com/api/song/enhance/player/url',
        'method': 'POST',
        'params': {'ids': '[123456]', 'br': '999000'},
      });
      expect(r['eparams'], kGoldenLinuxapiWorkerOrder);
    });

    test('eparams 是大写 hex 且长度为块长整数倍', () {
      final r = neteaseLinuxapi({
        'url': 'https://music.163.com/api/song/enhance/player/url',
        'method': 'POST',
        'params': {'ids': '[1]', 'br': '999000'},
      });
      final e = r['eparams']!;
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(e), isTrue);
      expect(e.length % 32, 0); // 16 字节 = 32 hex
    });

    test('键顺序不同 → 密文不同（JSON 序列化按插入顺序）', () {
      final a = neteaseLinuxapi({'url': 'u', 'method': 'POST'});
      final b = neteaseLinuxapi({'method': 'POST', 'url': 'u'});
      expect(a['eparams'], isNot(b['eparams']));
    });
  });
}
