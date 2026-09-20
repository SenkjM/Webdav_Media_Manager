import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/utils/share_export_clip.dart';

void main() {
  group('buildCueClipFfmpegArgs', () {
    test('crops with start/end and writes tags', () {
      final args = buildCueClipFfmpegArgs(
        inputPath: '/cache/album.flac',
        outputPath: '/tmp/out.mp3',
        startMs: 12500,
        endMs: 18500,
        title: 'Track One',
        artist: 'Artist',
        album: 'Album',
        albumArtist: 'Album Artist',
        trackNumber: 3,
        trackTotal: 12,
        year: 2020,
        genre: 'Jazz',
      );
      expect(args, containsAllInOrder(['-ss', '12.500']));
      expect(args, containsAllInOrder(['-t', '6.000']));
      expect(args, contains('-i'));
      expect(args, contains('/cache/album.flac'));
      expect(args, containsAllInOrder(['-metadata', 'title=Track One']));
      expect(args, containsAllInOrder(['-metadata', 'artist=Artist']));
      expect(args, containsAllInOrder(['-metadata', 'album=Album']));
      expect(args, containsAllInOrder(['-metadata', 'track=3/12']));
      expect(args, containsAllInOrder(['-metadata', 'genre=Jazz']));
      expect(args, containsAllInOrder(['-c:a', 'libmp3lame']));
      expect(args.last, '/tmp/out.mp3');
    });

    test('rejects inverted range', () {
      expect(
        () => buildCueClipFfmpegArgs(
          inputPath: 'a.mp3',
          outputPath: 'b.mp3',
          startMs: 10,
          endMs: 5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('sanitizeShareFileStem', () {
    test('strips unsafe characters', () {
      expect(sanitizeShareFileStem('a/b:c*?.mp3'), 'a_b_c__.mp3');
      expect(sanitizeShareFileStem('   '), 'track');
    });
  });
}
