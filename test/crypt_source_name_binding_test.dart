// crypt 源解析的「名称唯一绑定」语义测试。
//
// 源账号名称是 Crypt 的实际绑定关系；source id 仅作为旧配置兼容字段，
// 不参与解析。源被删除并重建后，只要名称一致即可恢复。
// 这里复刻 CryptDriver._requireSource 与 CloudDriveService._resolveSourceByName 的语义。

import 'package:flutter_test/flutter_test.dart';

class _Account {
  _Account(this.id, this.name);
  final String id;
  final String name;
}

class _SourceRegistry {
  _SourceRegistry(this.accounts);
  final List<_Account> accounts;

  String? byId(String id) {
    for (final a in accounts) {
      if (a.id == id) return 'source:${a.id}';
    }
    return null;
  }

  /// 复刻 _resolveSourceByName：精确匹配账号名。
  String? byName(String name) {
    for (final a in accounts) {
      if (a.name.trim() == name.trim()) return byId(a.id);
    }
    return null;
  }

  /// 复刻 CryptDriver._requireSource 的名称唯一解析。
  String? resolve({required String id, required String name}) {
    if (name.trim().isEmpty) return null;
    return byName(name);
  }
}

void main() {
  test('名称匹配：按名称命中，不依赖 id', () {
    final r = _SourceRegistry([_Account('id-1', '我的WebDAV')]);
    expect(r.resolve(id: 'different-id', name: '我的WebDAV'), 'source:id-1');
  });

  test('id 指向另一个账号时仍以名称为准', () {
    final r = _SourceRegistry([
      _Account('id-1', '旧源'),
      _Account('id-9', '我的WebDAV'),
    ]);
    expect(r.resolve(id: 'id-1', name: '我的WebDAV'), 'source:id-9');
  });

  test('源被删后重添同名账号：按名字恢复', () {
    // 原源 id-1 已删除，用户重新添加了同名账号但 id 变了。
    final r = _SourceRegistry([_Account('id-9', '我的WebDAV')]);
    expect(
      r.resolve(id: 'id-1', name: '我的WebDAV'),
      'source:id-9',
      reason: '按保存的名字快照恢复 → 不必重建 crypt 账号',
    );
  });

  test('名字也对不上：仍然失败（不误接到别的源）', () {
    final r = _SourceRegistry([_Account('id-9', '别的盘')]);
    expect(r.resolve(id: 'id-1', name: '我的WebDAV'), isNull);
  });

  test('没有名字快照的老账号：无法按名称绑定', () {
    final r = _SourceRegistry([_Account('id-9', '我的WebDAV')]);
    expect(r.resolve(id: 'id-1', name: ''), isNull);
  });

  test('名字匹配忽略首尾空白', () {
    final r = _SourceRegistry([_Account('id-9', ' 我的WebDAV ')]);
    expect(r.resolve(id: 'x', name: '我的WebDAV'), 'source:id-9');
  });
}
