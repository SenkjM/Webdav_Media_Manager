// 网络库不能在启动时列目录：HomeShell 的 IndexedStack 会立刻挂上这一页，
// initState 里拉列表会在用户打开标签前打到 WebDAV / 云盘并弹出 401/403。
// 只在第一次选中该标签时放行；再切回不重新列。

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/screens/home_shell.dart';
import 'package:webdav_media_manager/screens/network_library_screen.dart';

void main() {
  test('启动时停在别的标签，不列网络库', () {
    expect(
      shouldOpenNetworkLibrary(shellTab: 0, alreadyOpened: false),
      isFalse,
    );
    expect(
      shouldOpenNetworkLibrary(shellTab: 1, alreadyOpened: false),
      isFalse,
    );
    expect(
      shouldOpenNetworkLibrary(shellTab: null, alreadyOpened: false),
      isFalse,
      reason: '不在壳里不能当成已经选中',
    );
  });

  test('第一次选中网络库标签才列目录', () {
    expect(
      shouldOpenNetworkLibrary(
        shellTab: kNetworkLibraryTabIndex,
        alreadyOpened: false,
      ),
      isTrue,
    );
  });

  test('切回网络库标签不重新列', () {
    expect(
      shouldOpenNetworkLibrary(
        shellTab: kNetworkLibraryTabIndex,
        alreadyOpened: true,
      ),
      isFalse,
    );
  });
}
