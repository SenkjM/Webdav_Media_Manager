import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  const sample = '''
REM GENRE "Rock"
REM DATE 1999
PERFORMER "Album Artist"
TITLE "Great Album"
FILE "great.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Intro"
    PERFORMER "Band"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Main Song"
    INDEX 01 01:30:00
''';
  test('parses standard cue', () {
    final s = CueSheetParser.parse(sample);
    expect(s.tracks, hasLength(2));
    expect(s.title, 'Great Album');
  });
  test('cue wins tags', () {
    final s = CueSheetParser.parse(sample);
    final m = mergeCueOverFileTags(sheet: s, cueTrack: s.tracks[0], fileTitle: 'X', fileArtist: 'Y');
    expect(m.title, 'Intro');
    expect(m.artist, 'Band');
  });
  test('album performer fallback', () {
    final s = CueSheetParser.parse(sample);
    final m = mergeCueOverFileTags(sheet: s, cueTrack: s.tracks[1], fileArtist: 'File');
    expect(m.artist, 'Album Artist');
  });
  test('virtual path', () {
    final v = cueVirtualRemotePath('/a.flac', 1);
    expect(parseCueVirtualRemotePath(v)!.cueTrackIndex, 1);
  });
  test('rejects bad cue', () {
    expect(CueSheetParser.tryParse('TITLE only'), isNull);
  });
}
