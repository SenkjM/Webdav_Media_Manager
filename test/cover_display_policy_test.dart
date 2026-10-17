import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webdav_media_manager/widgets/cover_art.dart';
import 'package:webdav_media_manager/services/tag_service.dart';
import 'package:webdav_media_manager/l10n/generated/app_localizations.dart';

void main() {
  group('CoverArt bytes vs placeholder', () {
    testWidgets('shows Image.memory for full bytes (local full art)', (
      tester,
    ) async {
      final src = img.Image(width: 200, height: 200);
      img.fill(src, color: img.ColorRgb8(10, 20, 30));
      final bytes = Uint8List.fromList(img.encodePng(src));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoverArt(bytes: bytes, size: 80)),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      // Placeholder icon should not appear when bytes decode.
      expect(find.byIcon(Icons.music_note), findsNothing);
    });

    testWidgets('shows placeholder when no path/bytes (missing cover)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CoverArt(size: 80))),
      );
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });

  group('ReadTags display map', () {
    test('includes extended fields when present', () async {
      final l10n = await AppLocalizations.delegate.load(
        const Locale('zh', 'CN'),
      );
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
      ).toDisplayMap(l10n);
      expect(map[l10n.tagTitle], 'T');
      expect(map[l10n.tagAlbumArtist], 'AA');
      expect(map[l10n.tagTrack], '2 / 10');
      expect(map[l10n.tagYear], '2020');
      expect(map[l10n.tagGenre], 'Rock');
      expect(map[l10n.tagBitrate], '320 kbps');
      expect(map[l10n.tagSampleRate], '44100 Hz');
    });
  });
}
