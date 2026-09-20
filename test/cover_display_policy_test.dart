import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webdav_music_player/utils/cover_image.dart';
import 'package:webdav_music_player/widgets/cover_art.dart';
import 'package:webdav_music_player/services/tag_service.dart';

void main() {
  group('resolveLibraryCoverPath', () {
    test('local + full path → full art', () {
      expect(
        resolveLibraryCoverPath(
          audioIsLocal: true,
          fullCoverPath: '/docs/covers_full/a.png',
          thumbPath: '/docs/covers/a.jpg',
        ),
        '/docs/covers_full/a.png',
      );
    });

    test('missing local → thumb only', () {
      expect(
        resolveLibraryCoverPath(
          audioIsLocal: false,
          fullCoverPath: '/docs/covers_full/a.png',
          thumbPath: '/docs/covers/a.jpg',
        ),
        '/docs/covers/a.jpg',
      );
    });

    test('local without full path → null (caller uses tag bytes)', () {
      expect(
        resolveLibraryCoverPath(
          audioIsLocal: true,
          fullCoverPath: null,
          thumbPath: '/docs/covers/a.jpg',
        ),
        isNull,
      );
    });
  });

  group('shouldEnqueueMissingAudio', () {
    test('enqueue when missing and not queued', () {
      expect(
        shouldEnqueueMissingAudio(
          audioIsLocal: false,
          alreadyQueuedOrDownloading: false,
        ),
        isTrue,
      );
    });

    test('do not enqueue when local or already queued', () {
      expect(
        shouldEnqueueMissingAudio(
          audioIsLocal: true,
          alreadyQueuedOrDownloading: false,
        ),
        isFalse,
      );
      expect(
        shouldEnqueueMissingAudio(
          audioIsLocal: false,
          alreadyQueuedOrDownloading: true,
        ),
        isFalse,
      );
    });
  });

  group('CoverArt local full vs thumb', () {
    testWidgets('shows Image.memory for full bytes (local full art)',
        (tester) async {
      final src = img.Image(width: 200, height: 200);
      img.fill(src, color: img.ColorRgb8(10, 20, 30));
      final bytes = Uint8List.fromList(img.encodePng(src));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverArt(bytes: bytes, size: 80),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      // Placeholder icon should not appear when bytes decode.
      expect(find.byIcon(Icons.music_note), findsNothing);
    });

    testWidgets('shows placeholder when no path/bytes (missing cover)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoverArt(size: 80),
          ),
        ),
      );
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });

  group('ReadTags display map', () {
    test('includes extended fields when present', () {
      final map = const ReadTags(
        title: 'T',
        artist: 'A',
        albumArtist: 'AA',
        album: 'Alb',
        trackNumber: 2,
        trackTotal: 10,
        discNumber: 1,
        year: 2020,
        genre: 'Rock',
        bitrate: 320000,
        sampleRate: 44100,
        durationMs: 125000,
      ).toDisplayMap();
      expect(map['标题'], 'T');
      expect(map['专辑艺术家'], 'AA');
      expect(map['曲目'], '2 / 10');
      expect(map['年份'], '2020');
      expect(map['流派'], 'Rock');
      expect(map['比特率'], '320 kbps');
      expect(map['采样率'], '44100 Hz');
    });
  });

  group('player cover hard rule', () {
    test('local without full path must not resolve to thumb', () {
      expect(
        resolveLibraryCoverPath(
          audioIsLocal: true,
          fullCoverPath: null,
          thumbPath: '/docs/covers/thumb.jpg',
        ),
        isNull,
      );
    });
  });
}
