import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/services/library_service.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

class _RecordingLibraryDatabase extends LibraryDatabase {
  int deleteCueCalls = 0;
  int replaceCueCalls = 0;

  @override
  Future<int> deleteTracksForCue(
    String sourceName,
    String cueRemotePath,
  ) async {
    deleteCueCalls++;
    return 1;
  }

  @override
  Future<void> replaceCueAlbumTracks({
    required String sourceName,
    required String cueRemotePath,
    required List<String> audioRemotePaths,
    required List<LibraryTrack> tracks,
  }) async {
    replaceCueCalls++;
  }
}

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
    final db = _RecordingLibraryDatabase();
    final library = LibraryService(db: db);
    library.debugSetTracksForTest([existing]);
    final missingPath =
        '${Directory.systemTemp.path}/wdmm-missing-${DateTime.now().microsecondsSinceEpoch}.flac';

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
    expect(db.deleteCueCalls, 0);
    expect(db.replaceCueCalls, 0);
  });
}
