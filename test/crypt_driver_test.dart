import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/crypt/crypt_driver.dart';

/// 内存内容源：条目名用真实 cipher 预加密，模拟源账号上的密文状态。
class FakeCloudSource implements CloudSource {
  FakeCloudSource(this.cipher, {this.capabilities = AccountCaps.all});

  final RcloneCipher cipher;

  @override
  final int capabilities;

  @override
  String get basePath => '/src456';

  final Map<String, (bool, int)> entries = {};
  final Map<String, Uint8List> contents = {};
  final List<String> mkdirCalls = [];
  final List<(String, String)> renameCalls = [];

  String addPlainFile(String innerPath, String content) {
    final data = Uint8List.fromList(utf8.encode(content));
    final enc = cipher.encrypt(data);
    final name = innerPath.split('/').last;
    final encName = cipher.encryptFileName(name);
    final dir = innerPath.contains('/')
        ? innerPath.substring(0, innerPath.lastIndexOf('/'))
        : '';
    final full = dir.isEmpty ? encName : '$dir/$encName';
    entries[full] = (false, enc.length);
    contents[full] = enc;
    return full;
  }

  String addPlainDir(String innerPath) {
    final name = innerPath.split('/').last;
    final encName = cipher.encryptDirName(name);
    final dir = innerPath.contains('/')
        ? innerPath.substring(0, innerPath.lastIndexOf('/'))
        : '';
    final full = dir.isEmpty ? encName : '$dir/$encName';
    entries[full] = (true, 0);
    return full;
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final p = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final out = <CloudFileItem>[];
    entries.forEach((full, v) {
      final idx = full.lastIndexOf('/');
      final parent = idx <= 0 ? '/' : full.substring(0, idx);
      if (parent == p) {
        out.add(CloudFileItem(
          name: full.substring(idx + 1),
          isDir: v.$1,
          size: v.$2,
          rawUrl: null,
        ));
      }
    });
    return out;
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final v = entries[path];
    if (v == null) throw CloudDriverException('not found: $path');
    return CloudFileItem(
      name: path.split('/').last,
      isDir: v.$1,
      size: v.$2,
      rawUrl: v.$1 ? null : 'https://inner.example/${path.hashCode}',
      rawHeaders: const {'User-Agent': 'test'},
    );
  }

  @override
  Future<void> mkdir(String path) async => mkdirCalls.add(path);

  @override
  Future<void> rename(String path, String newPath) async {
    if (!entries.containsKey(path)) {
      throw const CloudDriverException('not found');
    }
    final v = entries.remove(path)!;
    entries[newPath] = v;
    renameCalls.add((path, newPath));
    if (contents.containsKey(path)) {
      contents[newPath] = contents.remove(path)!;
    }
  }

  @override
  Future<void> remove(String path) async => entries.remove(path);

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final v = entries.remove(srcPath);
    if (v == null) throw const CloudDriverException('not found');
    entries['$dstDir/$newName'.replaceFirst('//', '/')] = v;
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final v = entries[srcPath];
    if (v == null) throw const CloudDriverException('not found');
    entries['$dstDir/$newName'.replaceFirst('//', '/')] = v;
  }
}

CryptDriver buildDriver(FakeCloudSource source) {
  // 源条目按 crypt 语义预置：/789 下有 photos/（目录）与 song.flac。
  source.addPlainDir('/src456/789');
  source.addPlainDir('/src456/789/photos');
  source.addPlainFile('/src456/789/song.flac', 'hello crypt 你好');
  final env = CloudDriverEnv(resolveSource: (id) => id == 'src1' ? source : null);
  final driver = CryptDriver(config: {
    'source_account_id': 'src1',
    'source_dir': '/789',
    'password': 'testpass',
    'salt': 'testsalt',
    'filename_encryption': 'standard',
    'directory_name_encryption': true,
    'filename_encoding': 'base32',
  }, env: env);
  return driver;
}

void main() {
  test('list decrypts names and hides raw url', () async {
    final source = FakeCloudSource(RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
    ));
    final driver = buildDriver(source);
    await driver.init();
    final items = await driver.list('/');
    final names = items.map((e) => e.name).toSet();
    expect(names, contains('photos'));
    expect(names, contains('song.flac'));
    expect(items.every((e) => e.rawUrl == null), isTrue,
        reason: 'crypt 是 MustProxy：密文直链不外泄');
    final song = items.firstWhere((e) => e.name == 'song.flac');
    expect(song.size, utf8.encode('hello crypt 你好').length);
  });

  test('missing source surfaces a clear error on browse', () async {
    final driver = CryptDriver(config: {
      'source_account_id': 'gone',
      'source_dir': '/',
      'password': 'testpass',
      'salt': 'testsalt',
      'filename_encryption': 'standard',
      'filename_encoding': 'base32',
    }, env: CloudDriverEnv(resolveSource: (_) => null));
    await expectLater(driver.list('/'), throwsA(isA<CloudDriverException>()));
  });

  test('runtime capabilities inherit source but never write', () async {
    final source = FakeCloudSource(
      RcloneCipher(
        password: 'testpass',
        salt: 'testsalt',
        mode: NameEncryptionMode.standard,
      ),
      capabilities: AccountCaps.all, // 源有 write（WebDAV 配置）
    );
    final driver = buildDriver(source);
    await driver.init();
    final caps = driver.runtimeCapabilities!;
    expect(AccountCaps.has(caps, AccountCaps.write), isFalse,
        reason: '上传权限传递隔离（99 §7.5）');
    expect(AccountCaps.has(caps, AccountCaps.read), isTrue);
    expect(AccountCaps.has(caps, AccountCaps.mkdir), isTrue);
  });

  test('runtime capabilities null when source missing', () {
    final driver = CryptDriver(config: {
      'source_account_id': 'gone',
      'password': 'p',
    }, env: CloudDriverEnv(resolveSource: (_) => null));
    expect(driver.runtimeCapabilities, isNull);
  });

  test('mkdir encrypts the directory name toward the source', () async {
    final cipher = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
    );
    final source = FakeCloudSource(cipher);
    final driver = buildDriver(source);
    await driver.init();
    await driver.mkdir('/新专辑');
    expect(source.mkdirCalls, hasLength(1));
    final inner = source.mkdirCalls.single;
    expect(inner.startsWith('/src456/789/'), isTrue);
    final created = inner.split('/').last;
    expect(cipher.decryptDirName(created), '新专辑');
  });

  test('rename re-encrypts names both sides', () async {
    final cipher = RcloneCipher(
      password: 'testpass',
      salt: 'testsalt',
      mode: NameEncryptionMode.standard,
      dirNameEncrypt: true,
    );
    final source = FakeCloudSource(cipher);
    final driver = buildDriver(source);
    await driver.init();
    await driver.rename('/song.flac', 'renamed.flac');
    expect(source.renameCalls, hasLength(1));
    final call = source.renameCalls.single;
    expect(cipher.decryptFileName(call.$1.split('/').last), 'song.flac');
    expect(cipher.decryptFileName(call.$2.split('/').last), 'renamed.flac');
  });

  test('spec declares required fields', () {
    final spec = CryptSpec();
    final keys = spec.form
        .map((f) => switch (f) {
              CloudDriverField() => f.key,
              CloudDriverSelectField() => f.key,
              CloudDriverAccountField() => f.key,
              CloudDriverSwitchField() => f.key,
            })
        .toSet();
    expect(
        keys,
        containsAll([
          'source_account_id',
          'source_dir',
          'password',
          'salt',
          'filename_encryption',
          'directory_name_encryption',
        ]));
    expect(AccountCaps.has(spec.capabilities, AccountCaps.write), isFalse);
  });
}
