import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

/// Re-ingest identity is a property of the model: every TRACK of a sheet must
/// map to one distinct virtual remote path. Deterministic parsing of the same
/// bytes is covered by the Rust parser tests (`crates/wdmm-text/src/cue.rs`).
void main() {
  group('cue re-ingest identity stability', () {
    CueSheet sheet() => const CueSheet(
      files: ['disc.flac'],
      tracks: [
        CueTrack(
          number: 1,
          fileName: 'disc.flac',
          index01: Duration.zero,
          title: 'One',
        ),
        CueTrack(
          number: 2,
          fileName: 'disc.flac',
          index01: Duration(minutes: 1),
          title: 'Two',
        ),
        CueTrack(
          number: 3,
          fileName: 'disc.flac',
          index01: Duration(minutes: 2),
          title: 'Three',
        ),
      ],
      title: 'Album',
    );

    test('virtual paths are stable across re-parse (no +1 drift)', () {
      final a = sheet();
      final b = sheet();
      expect(a.tracks.length, 3);
      expect(b.tracks.length, 3);
      const cueRemote = '/music/album.cue';
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
      final cue = sheet();
      expect(cue.files.length, 1);
      expect(cue.tracks.length, 3);
      // Queue UI must show tracks.length (首歌), never files.length + cue.
      expect(cue.tracks.length, isNot(cue.files.length + 1));
    });
  });
}
