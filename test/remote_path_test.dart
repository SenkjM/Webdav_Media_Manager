import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/remote_path.dart';

void main() {
  group('remoteAncestors', () {
    test('深层路径逐级展开，不是只给一条', () {
      expect(remoteAncestors('/a/b/c'), ['/a', '/a/b', '/a/b/c']);
    });

    test('根目录没有祖先', () {
      expect(remoteAncestors('/'), isEmpty);
      expect(remoteAncestors(''), isEmpty);
    });

    test('多余分隔符与结尾斜杠被忽略', () {
      expect(remoteAncestors('/a//b/'), ['/a', '/a/b']);
    });

    test('中文与空格段原样保留', () {
      expect(remoteAncestors('/音乐/华语 流行'), ['/音乐', '/音乐/华语 流行']);
    });
  });

  group('remoteParent', () {
    test('逐级返回而不是直接回根', () {
      expect(remoteParent('/a/b/c'), '/a/b');
      expect(remoteParent('/a/b'), '/a');
      expect(remoteParent('/a'), '/');
    });

    test('根目录没有上一级', () {
      expect(remoteParent('/'), isNull);
    });
  });
}
