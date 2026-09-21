import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/music_audio_handler.dart';

/// Contract of the media-session item.
///
/// Deliberately free of `media_kit`: these are pure mapping rules, and needing a
/// native mpv player here meant the file could not even load on machines without
/// libmpv (it silently never ran in CI either).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mediaItemForTrack', () {
    test('keys the id on 网盘名 + path and carries it in extras', () {
      final track = TrackInfo(
        sourceName: 'acc',
        remotePath: '/m/song.mp3',
        fileName: 'song.mp3',
        localPath: '/tmp/song.mp3',
        title: 'Hello',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 12),
      );
      final item = mediaItemForTrack(track);
      // Identity is the app's binding key — not the resolved account id, which
      // playlists never carry (that produced `|/path` ids).
      expect(item.id, 'acc|/m/song.mp3');
      expect(item.extras?['sourceName'], 'acc');
      expect(item.extras?['remotePath'], '/m/song.mp3');
      expect(item.title, 'Hello');
      expect(item.artist, 'Artist');
      expect(item.album, 'Album');
      expect(item.duration, const Duration(seconds: 12));
    });

    test('id stays usable when no account id was resolved', () {
      final item = mediaItemForTrack(
        TrackInfo(sourceName: 'nas', remotePath: '/a/b.flac', fileName: 'b.flac'),
      );
      expect(item.id, 'nas|/a/b.flac');
      expect(item.id.startsWith('|'), isFalse);
    });

    test('empty title falls back to the file name', () {
      final item = mediaItemForTrack(
        TrackInfo(
          sourceName: 'a',
          remotePath: '/x.mp3',
          fileName: 'x.mp3',
          title: '   ',
        ),
      );
      expect(item.title, 'x.mp3');
    });

    test('CUE clip end shortens the reported duration', () {
      final item = mediaItemForTrack(
        TrackInfo(
          sourceName: 'a',
          remotePath: '/cd.flac',
          fileName: 'cd.flac',
          duration: const Duration(minutes: 60),
          clipStart: const Duration(seconds: 10),
          clipEnd: const Duration(seconds: 40),
        ),
      );
      expect(item.duration, const Duration(seconds: 30));
    });

    test('artUri null when cover missing', () {
      final item = mediaItemForTrack(
        TrackInfo(
          sourceName: 'acc',
          remotePath: '/m/song.mp3',
          fileName: 'song.mp3',
          coverPath: '/no/such/cover.jpg',
        ),
      );
      expect(item.artUri, isNull);
    });

    test('artUri file when cover exists', () async {
      final tmp = File(
        '${Directory.systemTemp.path}/webdav_cover_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });
      final item = mediaItemForTrack(
        TrackInfo(
          sourceName: 'acc',
          remotePath: '/m/song.mp3',
          fileName: 'song.mp3',
          coverPath: tmp.path,
        ),
      );
      expect(item.artUri, Uri.file(tmp.path));
    });
  });
}
