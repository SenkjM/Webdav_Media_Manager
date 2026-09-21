import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/utils/audio_extensions.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  const sample = """
REM GENRE Rock
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
""";

  test('decodeCueText accepts strict UTF-8', () {
    final text = decodeCueText(utf8.encode(sample));
    final sheet = CueSheetParser.tryParse(text);
    expect(sheet, isNotNull);
    expect(sheet!.tracks, hasLength(2));
  });

  test('decodeCueText does not throw on GBK-like high bytes', () {
    // ASCII structure + high bytes where a Chinese title would be (GBK).
    final bytes = <int>[
      ...utf8.encode('PERFORMER "'),
      0xD6, 0xD0, 0xCE, 0xC4, // GBK-ish bytes
      ...utf8.encode('"\nTITLE "Album"\nFILE "a.flac" WAVE\n'
          '  TRACK 01 AUDIO\n    TITLE "T1"\n    INDEX 01 00:00:00\n'
          '  TRACK 02 AUDIO\n    TITLE "T2"\n    INDEX 01 01:00:00\n'),
    ];
    // Must not throw (File.readAsString would).
    final text = decodeCueText(bytes);
    final sheet = CueSheetParser.tryParse(text);
    expect(sheet, isNotNull);
    expect(sheet!.tracks, hasLength(2));
    expect(sheet.audioRemotePaths('/music/disc.cue'), ['/music/a.flac']);
  });

  test('decodeCueText handles UTF-16 LE BOM', () {
    final units = sample.codeUnits;
    final bytes = <int>[0xFF, 0xFE];
    for (final u in units) {
      bytes.add(u & 0xFF);
      bytes.add((u >> 8) & 0xFF);
    }
    final sheet = CueSheetParser.tryParse(decodeCueText(bytes));
    expect(sheet, isNotNull);
    expect(sheet!.tracks.length, 2);
  });

  test('raw .cue is not a library song; virtual slices are', () {
    final plainCue = LibraryTrack(
      sourceName: 'a',
      remotePath: '/album/disc.cue',
      fileName: 'disc.cue',
    );
    expect(plainCue.isCueVirtual, isFalse);

    final slice = LibraryTrack(
      sourceName: 'a',
      remotePath: cueVirtualRemotePath('/album/disc.flac', 1),
      fileName: '01',
      cueRemotePath: '/album/disc.cue',
      cueTrackIndex: 1,
      audioRemotePath: '/album/disc.flac',
    );
    expect(slice.isCueVirtual, isTrue);
    expect(slice.cueTypeLabel, LibraryTrack.cueMultiSliceLabel);
    expect(isCueFileName('disc.cue'), isTrue);
    // Virtual marker means remotePath is not a plain audio filename.
    expect(isAudioFileName(slice.remotePath), isFalse);
  });
}
