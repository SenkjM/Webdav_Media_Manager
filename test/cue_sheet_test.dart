import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

/// The parse itself lives in Rust (`wdmm_cue_parse`, ported from the deleted
/// `CueSheetParser`); these tests cover the model and the helpers that stay in
/// Dart. Parsing behaviour is asserted in `crates/wdmm-text/src/cue.rs`.
void main() {
  CueSheet sampleSheet() => const CueSheet(
    files: ['great.flac'],
    tracks: [
      CueTrack(
        number: 1,
        fileName: 'great.flac',
        index01: Duration.zero,
        title: 'Intro',
        performer: 'Band',
      ),
      CueTrack(
        number: 2,
        fileName: 'great.flac',
        index01: Duration(minutes: 1, seconds: 30),
        title: 'Main Song',
      ),
    ],
    title: 'Great Album',
    performer: 'Album Artist',
    remGenre: 'Rock',
    remDate: '1999',
  );

  test('cue wins tags', () {
    final s = sampleSheet();
    final m = mergeCueOverFileTags(
      sheet: s,
      cueTrack: s.tracks[0],
      fileTitle: 'X',
      fileArtist: 'Y',
    );
    expect(m.title, 'Intro');
    expect(m.artist, 'Band');
  });

  test('album performer fallback', () {
    final s = sampleSheet();
    final m = mergeCueOverFileTags(
      sheet: s,
      cueTrack: s.tracks[1],
      fileArtist: 'File',
    );
    expect(m.artist, 'Album Artist');
  });

  test('year and genre come from REM lines and beat file tags', () {
    final s = sampleSheet();
    final m = mergeCueOverFileTags(
      sheet: s,
      cueTrack: s.tracks[0],
      fileYear: 2004,
      fileGenre: 'Pop',
    );
    expect(m.year, 1999);
    expect(m.genre, 'Rock');
    expect(m.trackNumber, 1);
  });

  test('audioRemotePaths has one distinct entry per FILE', () {
    const sheet = CueSheet(
      files: ['disc.flac', 'disc.flac', 'extra.flac'],
      tracks: [],
    );
    expect(sheet.audioRemotePaths('/music/disc.cue'), [
      '/music/disc.flac',
      '/music/extra.flac',
    ]);
  });

  test('joinRemote strips directories and handles the root', () {
    expect(CueSheet.joinRemote('/music', 'sub/disc.flac'), '/music/disc.flac');
    expect(CueSheet.joinRemote('/music/', 'sub/disc.flac'), '/music/disc.flac');
    expect(CueSheet.joinRemote('/', 'disc.flac'), '/disc.flac');
    expect(CueSheet.joinRemote('', r'sub\disc.flac'), '/disc.flac');
  });

  test('cueClipRanges chains tracks per FILE and clamps the last one', () {
    const tracks = [
      CueTrack(number: 1, fileName: 'a.flac', index01: Duration.zero),
      CueTrack(
        number: 2,
        fileName: 'a.flac',
        index01: Duration(minutes: 1),
      ),
      CueTrack(number: 3, fileName: 'b.flac', index01: Duration.zero),
    ];
    final ranges = cueClipRanges(
      tracks,
      fileDurations: const {'a.flac': Duration(minutes: 5)},
    );
    expect(ranges[0].start, Duration.zero);
    expect(ranges[0].end, const Duration(minutes: 1));
    expect(ranges[1].end, const Duration(minutes: 5));
    expect(ranges[2].start, Duration.zero);
    expect(ranges[2].end, isNull);
  });

  test('virtual path', () {
    final v = cueVirtualRemotePath('/a.flac', 1);
    expect(parseCueVirtualRemotePath(v)!.cueTrackIndex, 1);
  });

  test('parseOrNull returns null when no parser can answer', () {
    // Host tests have no native library, so this also pins the "older .so"
    // contract: callers must cope with null instead of an exception.
    expect(CueSheet.parseOrNull('TITLE only'), isNull);
    expect(
      () => CueSheet.parse('TITLE only'),
      throwsA(isA<StateError>()),
    );
  });
}
