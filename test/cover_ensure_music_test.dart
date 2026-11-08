import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:webdav_media_manager/services/cover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wdmm_cover_ensure_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tmp.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Uint8List jpegBytes() {
    final src = img.Image(width: 32, height: 32);
    img.fill(src, color: img.ColorRgb8(20, 40, 60));
    return Uint8List.fromList(img.encodeJpg(src));
  }

  group('ensureMusicCoverFile', () {
    test('short-circuits when deterministic file already exists', () async {
      final covers = CoverService();
      await covers.coversDir;
      final path = await covers.saveThumb(
        sourceName: 'acc',
        remotePath: '/a.mp3',
        bytes: jpegBytes(),
      );
      expect(path, isNotNull);
      var fetches = 0;
      final again = await covers.ensureMusicCoverFile(
        sourceName: 'acc',
        remotePath: '/a.mp3',
        fetchBytes: () async {
          fetches++;
          return jpegBytes();
        },
      );
      expect(again, path);
      expect(fetches, 0);
      expect(File(again!).existsSync(), isTrue);
    });

    test('missing file calls fetch and saves thumb', () async {
      final covers = CoverService();
      await covers.coversDir;
      var fetches = 0;
      final saved = await covers.ensureMusicCoverFile(
        sourceName: 'acc',
        remotePath: '/missing.mp3',
        fetchBytes: () async {
          fetches++;
          return jpegBytes();
        },
      );
      expect(fetches, 1);
      expect(saved, isNotNull);
      expect(File(saved!).existsSync(), isTrue);
      expect(p.basename(saved), covers.coverFileName('acc', '/missing.mp3'));
    });

    test('missing file + empty fetch returns null (no state write)', () async {
      final covers = CoverService();
      await covers.coversDir;
      final saved = await covers.ensureMusicCoverFile(
        sourceName: 'acc',
        remotePath: '/empty.mp3',
        fetchBytes: () async => null,
      );
      expect(saved, isNull);
      final file = await covers.coverFile('acc', '/empty.mp3');
      expect(await file.exists(), isFalse);
    });
  });
}
