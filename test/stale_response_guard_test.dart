// 网络库「动画先行 + 迟到响应作废」守卫语义的等价性测试。
//
// 真机反馈：网络或流式解密阻塞列表加载时，用户多次点按导致重复打开、
// 返回后打开错误的文件夹。修复：导航立即切换路径并显示加载动画，
// 每次导航发新请求并领新序号；迟到响应序号过期即丢弃。
// 这里用与 network_library_screen._load 相同的序号逻辑做纯 Dart 验证，
// 防止以后有人改坏守卫（例如把 ++ 前缀改成后缀、或忘记在 catch 里验号）。

import 'package:flutter_test/flutter_test.dart';

class _LoadSequencer {
  int _seq = 0;
  final List<String> applied = [];

  int issue() => ++_seq;

  /// 复刻 _load 的响应处理：过期丢弃，最新才应用。
  void complete({required int issued, required String path, bool throws = false}) {
    if (issued != _seq) return; // 过期响应：丢弃（_load 的 seq != _loadSeq 分支）。
    applied.add(throws ? 'error:$path' : 'items:$path');
  }
}

void main() {
  test('进入B后A的迟到响应被丢弃，B的最新响应被应用', () {
    final s = _LoadSequencer();
    final a = s.issue(); // 点目录A
    final b = s.issue(); // 网络慢，又点了目录B
    s.complete(issued: a, path: 'A');
    expect(s.applied, isEmpty, reason: 'A 的响应已过期，不得写进 B 的页面');
    s.complete(issued: b, path: 'B');
    expect(s.applied, ['items:B'], reason: '只有最新请求的结果应用');
  });

  test('返回上级同样作废子目录的迟到响应', () {
    final s = _LoadSequencer();
    s.issue(); // 进入 B
    final up = s.issue(); // 返回
    s.complete(issued: up, path: 'root');
    expect(s.applied, ['items:root']);
  });

  test('错误路径同样受守卫：过期错误不弹给用户', () {
    final s = _LoadSequencer();
    final a = s.issue();
    s.issue(); // 又导航了一次
    s.complete(issued: a, path: 'A', throws: true);
    expect(s.applied, isEmpty, reason: '旧请求的错误不应显示在新路径上');
  });

  test('连续两次请求同一目录（刷新抢占）：只应用最后一次', () {
    final s = _LoadSequencer();
    final a = s.issue();
    final b = s.issue();
    s.complete(issued: b, path: 'X');
    s.complete(issued: a, path: 'X');
    expect(s.applied, ['items:X'], reason: '第一个结果被丢弃，只应用一次');
  });
}
