import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/directory_walk.dart';

void main() {
  group('WalkOptions', () {
    test('effectiveMaxDepth is 0 when subdirs off', () {
      const o = WalkOptions(includeSubdirs: false, maxDepth: 5);
      expect(o.effectiveMaxDepth, 0);
    });

    test('clamp depth 0–20', () {
      expect(WalkOptions.clampDepth(-3), 0);
      expect(WalkOptions.clampDepth(1), 1);
      expect(WalkOptions.clampDepth(99), 20);
    });
  });

  group('DirectoryWalker', () {
    test('root only when includeSubdirs false', () {
      final w = DirectoryWalker(
        rootPath: '/album',
        options: const WalkOptions(includeSubdirs: false, maxDepth: 5),
      );
      expect(w.nextDirectory(), '/album');
      expect(w.acceptChildren('/album', ['/album/a', '/album/b']), 0);
      expect(w.nextDirectory(), isNull);
      expect(w.listedCount, 1);
    });

    test('maxDepth 1 lists root and one level', () {
      final w = DirectoryWalker(
        rootPath: '/root',
        options: const WalkOptions(includeSubdirs: true, maxDepth: 1),
      );
      expect(w.nextDirectory(), '/root');
      w.acceptChildren('/root', ['/root/a', '/root/b']);
      expect(w.nextDirectory(), '/root/a');
      // grandchildren must not be enqueued
      expect(w.acceptChildren('/root/a', ['/root/a/deep']), 0);
      expect(w.nextDirectory(), '/root/b');
      expect(w.acceptChildren('/root/b', ['/root/b/x']), 0);
      expect(w.nextDirectory(), isNull);
      expect(w.listedCount, 3);
    });

    test('maxDepth 0 with includeSubdirs still only root', () {
      final w = DirectoryWalker(
        rootPath: '/r',
        options: const WalkOptions(includeSubdirs: true, maxDepth: 0),
      );
      expect(w.nextDirectory(), '/r');
      expect(w.acceptChildren('/r', ['/r/child']), 0);
      expect(w.nextDirectory(), isNull);
    });

    test('cycle guard via visited normalized paths', () {
      final w = DirectoryWalker(
        rootPath: '/a',
        options: const WalkOptions(includeSubdirs: true, maxDepth: 5),
      );
      expect(w.nextDirectory(), '/a');
      w.acceptChildren('/a', ['/a/b', '/a/']); // /a/ normalizes to /a — skipped
      expect(w.nextDirectory(), '/a/b');
      // point back to /a
      expect(w.acceptChildren('/a/b', ['/a', '/a/b/c']), 1);
      expect(w.nextDirectory(), '/a/b/c');
      expect(w.nextDirectory(), isNull);
      expect(w.visited.contains('/a'), isTrue);
      expect(w.visited.contains('/a/b'), isTrue);
    });

    test('trailing slash normalized for visited', () {
      final w = DirectoryWalker(
        rootPath: '/x/',
        options: const WalkOptions(includeSubdirs: true, maxDepth: 2),
      );
      expect(w.nextDirectory(), '/x');
      w.acceptChildren('/x/', ['/x/y/']);
      expect(w.nextDirectory(), '/x/y');
    });

    test('maxEntries fuse stops listing', () {
      final w = DirectoryWalker(
        rootPath: '/r',
        options: const WalkOptions(
          includeSubdirs: true,
          maxDepth: 5,
          maxEntries: 2,
        ),
      );
      expect(w.nextDirectory(), '/r');
      w.acceptChildren('/r', ['/r/1', '/r/2', '/r/3']);
      expect(w.nextDirectory(), '/r/1');
      // fuse: listed already 2
      expect(w.nextDirectory(), isNull);
      expect(w.listedCount, 2);
    });
  });
}
