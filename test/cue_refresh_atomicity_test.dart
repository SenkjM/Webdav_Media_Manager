import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/services/library_service.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  test('missing CUE audio leaves previous library group intact', () async {
    const source = 'webdav';
    const cuePath = '/album/disc.cue';
    const audioPath = '/album/disc.flac';
    final sheet = CueSheetParser.parse('''
TITLE "Album"
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Song"
    INDEX 01 00:00:00
''');
    final existing = LibraryTrack(
      sourceName: source,
      remotePath: cueVirtualRemotePath(audioPath, 1),
      fileName: 'Song',
      cueRemotePath: cuePath,
      cueTrackIndex: 1,
      audioRemotePath: audioPath,
      title: 'Existing metadata',
    );
    final library = LibraryService();
    library.debugSetTracksForTest([existing]);
    final missingPath =
        '${Directory.systemTemp.path}/wdmm-missing-${DateTime.now().microsecondsSinceEpoch}.flac';

    // Core-only: the per-audio File(localPath).exists() check throws before any
    // CUE album/slice write reaches Core, so the in-memory projection is intact.
    await expectLater(
      library.ingestCueAlbum(
        sourceName: source,
        cueRemotePath: cuePath,
        sheet: sheet,
        cacheGroupId: 'cue-test',
        localPathFor: (_) => missingPath,
      ),
      throwsA(isA<StateError>()),
    );

    expect(library.tracks, [same(existing)]);
  });
}
