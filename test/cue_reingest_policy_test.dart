import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  group('cue re-ingest identity stability', () {
    const sample = '''
TITLE "Album"
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Two"
    INDEX 01 01:00:00
  TRACK 03 AUDIO
    TITLE "Three"
    INDEX 01 02:00:00
''';

    test('virtual paths are stable across re-parse (no +1 drift)', () {
      final a = CueSheetParser.parse(sample);
      final b = CueSheetParser.parse(sample);
      expect(a.tracks.length, 3);
      expect(b.tracks.length, 3);
      final cueRemote = '/music/album.cue';
      final audio = a.audioRemotePaths(cueRemote).single;
      final pathsA = [
        for (final t in a.tracks) cueVirtualRemotePath(audio, t.number),
      ];
      final pathsB = [
        for (final t in b.tracks) cueVirtualRemotePath(audio, t.number),
      ];
      expect(pathsA, pathsB);
      expect(pathsA.toSet().length, 3);
    });

    test('song count is TRACK count not FILE count', () {
      final sheet = CueSheetParser.parse(sample);
      expect(sheet.files.length, 1);
      expect(sheet.tracks.length, 3);
      // Queue UI must show tracks.length (首歌), never files.length + cue.
      expect(sheet.tracks.length, isNot(sheet.files.length + 1));
    });
  });
}
