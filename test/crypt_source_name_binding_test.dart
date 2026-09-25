// crypt 源解析的「id 优先、名字兜底」语义测试。
//
// 真机反馈：crypt 账号只绑源 id，源被删除后报错界面只显示一长串源 id，
// 用户即使重新添加同名源账号也无法恢复 crypt（新账号 id 不同）。
// 修复：保存时快照源账号名；解析时先按 id，找不到再按名字精确匹配。
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

  /// 复刻 _resolveSource：按 id 查，存在才给源。
  String? byId(String id) {
    for (final a in accounts) {
      if (a.id == id) return 'source:${ a.id }';
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

  /// 复刻 CryptDriver._requireSource 的两级解析。
  String? resolve({required String id, required String name}) {
    var s = byId(id);
    if (s == null && name.isNotEmpty) s = byName(name);
    return s;
  }
}

void main() {
  test('源 id 仍在：按 id 直接命中', () {
    final r = _SourceRegistry([_Account('id-1', '我的WebDAV')]);
    expect(r.resolve(id: 'id-1', name: '我的WebDAV'), 'source:id-1');
  });

  test('源被删后重添同名账号：按名字恢复', () {
    // 原源 id-1 已删除，用户重新添加了同名账号但 id 变了。
    final r = _SourceRegistry([_Account('id-9', '我的WebDAV')]);
    expect(r.resolve(id: 'id-1', name: '我的WebDAV'), 'source:id-9',
        reason: 'id 找不到时按保存的名字快照恢复 → 不必重建 crypt 账号');
  });

  test('名字也对不上：仍然失败（不误接到别的源）', () {
    final r = _SourceRegistry([_Account('id-9', '别的盘')]);
    expect(r.resolve(id: 'id-1', name: '我的WebDAV'), isNull);
  });

  test('没有名字快照的老账号：只认 id（行为不回归）', () {
    final r = _SourceRegistry([_Account('id-9', '我的WebDAV')]);
    expect(r.resolve(id: 'id-1', name: ''), isNull);
  });

  test('名字匹配忽略首尾空白', () {
    final r = _SourceRegistry([_Account('id-9', ' 我的WebDAV ')]);
    expect(r.resolve(id: 'x', name: '我的WebDAV'), 'source:id-9');
  });
}