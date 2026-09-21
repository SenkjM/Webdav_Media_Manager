import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:webdav_music_player/models/webdav_item.dart';
import 'package:webdav_music_player/services/music_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  group('MusicAudioHandler mediaItemFor', () {
    test('builds MediaItem with id title artist', () {
      final handler = MusicAudioHandler(player: Player());
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
      final item = handler.mediaItemFor(track);
      expect(item.id, 'acc|/m/song.mp3');
      expect(item.title, 'Hello');
      expect(item.artist, 'Artist');
      expect(item.album, 'Album');
      expect(item.duration, const Duration(seconds: 12));
      expect(item.extras?['accountId'], 'acc');
    });

    test('artUri null when cover missing', () {
      final handler = MusicAudioHandler(player: Player());
      final track = TrackInfo(
        sourceName: 'acc',
        remotePath: '/m/song.mp3',
        fileName: 'song.mp3',
        coverPath: '/no/such/cover.jpg',
      );
      expect(handler.mediaItemFor(track).artUri, isNull);
    });

    test('artUri file when cover exists', () async {
      final handler = MusicAudioHandler(player: Player());
      final tmp = File(
        '${Directory.systemTemp.path}/webdav_cover_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });
      final track = TrackInfo(
        sourceName: 'acc',
        remotePath: '/m/song.mp3',
        fileName: 'song.mp3',
        coverPath: tmp.path,
      );
      expect(handler.mediaItemFor(track).artUri, Uri.file(tmp.path));
      await handler.disposePlayer();
    });
  });
}
