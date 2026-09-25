// BackHandlerRegistry 的 tab 归属语义（真机反馈：下载页按返回被后台的网络库
// 消费，退完目录栈才回设定主页）。修法：处理器注册时声明所属 tab，shell 维护
// activeTabIndex，分发只考虑活跃 tab（或未声明归属）的处理器。

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/back_handler_registry.dart';

void main() {
  setUp(() => BackHandlerRegistry.resetForTest());

  test('声明归属的处理器只在自己是活跃 tab 时参与分发', () {
    var networkHandled = false;
    BackHandlerRegistry.register(() => networkHandled = true, tab: 2);

    BackHandlerRegistry.activeTabIndex = 3; // 下载页
    expect(BackHandlerRegistry.tryHandleBack(), isFalse,
        reason: '网络库在后台，不得消费下载页的返回');
    expect(networkHandled, isFalse);

    BackHandlerRegistry.activeTabIndex = 2; // 网络库
    expect(BackHandlerRegistry.tryHandleBack(), isTrue);
    expect(networkHandled, isTrue);
  });

  test('未声明归属的处理器在任意 tab 都参与分发（兼容非 tab 屏）', () {
    BackHandlerRegistry.register(() => true);
    BackHandlerRegistry.activeTabIndex = 1;
    expect(BackHandlerRegistry.tryHandleBack(), isTrue);
    BackHandlerRegistry.activeTabIndex = null; // 非 shell 上下文
    expect(BackHandlerRegistry.tryHandleBack(), isTrue);
  });

  test('活跃 tab 未设置（null）时，声明了归属的处理器一律不参与', () {
    BackHandlerRegistry.register(() => true, tab: 0);
    expect(BackHandlerRegistry.activeTabIndex, isNull);
    expect(BackHandlerRegistry.tryHandleBack(), isFalse);
  });

  test('处理器可以消费后返回 true 让后续处理器不再被询问', () {
    var secondAsked = false;
    BackHandlerRegistry.register(() => true, tab: 0);
    BackHandlerRegistry.register(() => secondAsked = true, tab: 0);
    BackHandlerRegistry.activeTabIndex = 0;
    expect(BackHandlerRegistry.tryHandleBack(), isTrue);
    expect(secondAsked, isFalse);
  });
}
