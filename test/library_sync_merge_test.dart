import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';

/// Mirrors LibrarySyncService LWW merge by lastTagReadAt (pure logic test).
List<LibraryTrack> mergeTracksForTest({
  required List<LibraryTrack> local,
  required List<LibraryTrack> remote,
  required String sourceName,
}) {
  final map = <String, LibraryTrack>{};
  for (final t in local) {
    if (t.sourceName != sourceName) continue;
    map[t.remotePath] = t;
  }
  for (final r in remote) {
    if (r.sourceName != sourceName) continue;
    final l = map[r.remotePath];
    if (l == null) {
      map[r.remotePath] = r;
    } else if (r.lastTagReadAt.isAfter(l.lastTagReadAt)) {
      // Sync without covers must not demote a local present/none solely
      // because the remote row carries unknown (0).
      final state = r.coverState == 0 ? l.coverState : r.coverState;
      map[r.remotePath] = LibraryTrack.fromMap({
        ...r.toMap(),
        'cover_state': state,
      });
    }
  }
  return map.values.toList();
}

LibraryTrack track({
  required String path,
  required DateTime tagAt,
  String? title,
  int coverState = 0,
  String sourceName = 'acc-a',
}) {
  return LibraryTrack(
    sourceName: sourceName,
    remotePath: path,
    fileName: path.split('/').last,
    title: title,
    coverState: coverState,
    lastDownloadedAt: tagAt,
    lastTagReadAt: tagAt,
  );
}

void main() {
  group('library sync merge', () {
    test('newer remote wins; older remote ignored', () {
      final local = [
        track(path: '/a.mp3', tagAt: DateTime.utc(2026, 1, 1), title: 'Local'),
      ];
      final remote = [
        track(path: '/a.mp3', tagAt: DateTime.utc(2026, 2, 1), title: 'Remote'),
        track(path: '/b.mp3', tagAt: DateTime.utc(2026, 2, 1), title: 'New'),
      ];
      final merged = mergeTracksForTest(
        local: local,
        remote: remote,
        sourceName: 'acc-a',
      );
      final byPath = {for (final t in merged) t.remotePath: t};
      expect(byPath['/a.mp3']!.title, 'Remote');
      expect(byPath['/b.mp3']!.title, 'New');
    });

    test('ignores other accountId tracks', () {
      final local = [track(path: '/a.mp3', tagAt: DateTime.utc(2026, 1, 1))];
      final remote = [
        track(
          path: '/a.mp3',
          tagAt: DateTime.utc(2026, 9, 1),
          title: 'Other',
          sourceName: 'acc-b',
        ),
      ];
      final merged = mergeTracksForTest(
        local: local,
        remote: remote,
        sourceName: 'acc-a',
      );
      expect(merged.single.title, isNull);
      expect(merged.single.sourceName, 'acc-a');
    });

    test('keeps local cover_state when remote unknown', () {
      final local = [
        track(
          path: '/a.mp3',
          tagAt: DateTime.utc(2026, 1, 1),
          coverState: 2,
        ),
      ];
      final remote = [
        track(
          path: '/a.mp3',
          tagAt: DateTime.utc(2026, 3, 1),
          title: 'R',
          coverState: 0,
        ),
      ];
      final merged = mergeTracksForTest(
        local: local,
        remote: remote,
        sourceName: 'acc-a',
      );
      expect(merged.single.title, 'R');
      expect(merged.single.coverState, 2);
    });
  });
}
