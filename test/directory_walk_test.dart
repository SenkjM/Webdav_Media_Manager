import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/utils/directory_walk.dart';

void main() {
  group('WalkOptions', () {
    test('effectiveMaxDepth is 0 when subdirs off', () {
      const o = WalkOptions(includeSubdirs: false, maxDepth: 5);
      expect(o.effectiveMaxDepth, 0);
    });

    test('effectiveMaxDepth honours maxDepth when subdirs on', () {
      const o = WalkOptions(includeSubdirs: true, maxDepth: 3);
      expect(o.effectiveMaxDepth, 3);
    });

    test('clamp depth 0–20', () {
      expect(WalkOptions.clampDepth(-3), 0);
      expect(WalkOptions.clampDepth(1), 1);
      expect(WalkOptions.clampDepth(99), 20);
    });

    test('maxEntries is clamped to the fuse range', () {
      expect(WalkOptions.clampMaxEntries(0), 1);
      expect(WalkOptions.clampMaxEntries(500), 500);
      expect(WalkOptions.clampMaxEntries(999999), 50000);
    });

    test('copyWith keeps untouched fields', () {
      const base = WalkOptions(includeSubdirs: true, maxDepth: 2, maxEntries: 9);
      final copy = base.copyWith(maxDepth: 4);
      expect(copy.includeSubdirs, isTrue);
      expect(copy.maxDepth, 4);
      expect(copy.maxEntries, 9);
    });
  });

  group('WalkEntry', () {
    test('decodes the Rust reply fields', () {
      final entry = WalkEntry.fromJson({
        'path': '/music/a.mp3',
        'name': 'a.mp3',
        'size': 1234,
        'mtime': 1700000000000,
        'is_dir': false,
      });
      expect(entry.path, '/music/a.mp3');
      expect(entry.name, 'a.mp3');
      expect(entry.size, 1234);
      expect(entry.isDirectory, isFalse);
      expect(
        entry.modified,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
    });

    test('missing mtime decodes to null', () {
      final entry = WalkEntry.fromJson({
        'path': '/dir',
        'name': 'dir',
        'is_dir': true,
      });
      expect(entry.modified, isNull);
      expect(entry.isDirectory, isTrue);
    });

    test('directory getter returns the parent', () {
      const file = WalkEntry(
        path: '/music/album/a.mp3',
        name: 'a.mp3',
        size: 1,
        isDirectory: false,
      );
      expect(file.directory, '/music/album');
      const root = WalkEntry(
        path: '/a.mp3',
        name: 'a.mp3',
        size: 1,
        isDirectory: false,
      );
      expect(root.directory, '/');
      const relative = WalkEntry(
        path: 'music/b.flac',
        name: 'b.flac',
        size: 1,
        isDirectory: false,
      );
      expect(relative.directory, 'music');
    });

    test('toItem classifies files and leaves directories unclassified', () {
      final types = FileTypeConfig();
      final video = WalkEntry(
        path: '/v/movie.mkv',
        name: 'movie.mkv',
        size: 1,
        isDirectory: false,
      ).toItem(types);
      expect(video.category, FileCategory.video);
      expect(video.isVideo, isTrue);
      expect(video.isDirectory, isFalse);

      final dir = WalkEntry(
        path: '/v',
        name: 'v',
        size: 0,
        isDirectory: true,
      ).toItem(types);
      expect(dir.isDirectory, isTrue);
      expect(dir.category, FileCategory.other);
    });
  });

  group('DirectoryWalker', () {
    test('legacy planner throws instead of walking on the Dart side', () {
      expect(
        () => DirectoryWalker(rootPath: '/album'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
