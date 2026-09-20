import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';

/// Mirrors LibrarySyncService LWW merge by lastTagReadAt (pure logic test).
List<LibraryTrack> mergeTracksForTest({
  required List<LibraryTrack> local,
  required List<LibraryTrack> remote,
  required String accountId,
}) {
  final map = <String, LibraryTrack>{};
  for (final t in local) {
    if (t.accountId != accountId) continue;
    map[t.remotePath] = t;
  }
  for (final r in remote) {
    if (r.accountId != accountId) continue;
    final l = map[r.remotePath];
    if (l == null) {
      map[r.remotePath] = r;
    } else if (r.lastTagReadAt.isAfter(l.lastTagReadAt)) {
      final cover = (r.coverPath != null && r.coverPath!.isNotEmpty)
          ? r.coverPath
          : l.coverPath;
      map[r.remotePath] = LibraryTrack.fromMap({
        ...r.toMap(),
        'cover_path': cover,
      });
    }
  }
  return map.values.toList();
}

LibraryTrack track({
  required String path,
  required DateTime tagAt,
  String? title,
  String? cover,
  String accountId = 'acc-a',
}) {
  return LibraryTrack(
    accountId: accountId,
    remotePath: path,
    fileName: path.split('/').last,
    title: title,
    coverPath: cover,
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
        accountId: 'acc-a',
      );
      final byPath = {for (final t in merged) t.remotePath: t};
      expect(byPath['/a.mp3']!.title, 'Remote');
      expect(byPath['/b.mp3']!.title, 'New');
    });

    test('ignores other accountId tracks', () {
      final local = [
        track(path: '/a.mp3', tagAt: DateTime.utc(2026, 1, 1)),
      ];
      final remote = [
        track(
          path: '/a.mp3',
          tagAt: DateTime.utc(2026, 9, 1),
          title: 'Other',
          accountId: 'acc-b',
        ),
      ];
      final merged = mergeTracksForTest(
        local: local,
        remote: remote,
        accountId: 'acc-a',
      );
      expect(merged.single.title, isNull);
      expect(merged.single.accountId, 'acc-a');
    });

    test('keeps local cover when remote cover empty', () {
      final local = [
        track(
          path: '/a.mp3',
          tagAt: DateTime.utc(2026, 1, 1),
          cover: '/docs/covers/x.jpg',
        ),
      ];
      final remote = [
        track(
          path: '/a.mp3',
          tagAt: DateTime.utc(2026, 3, 1),
          title: 'R',
          cover: null,
        ),
      ];
      final merged = mergeTracksForTest(
        local: local,
        remote: remote,
        accountId: 'acc-a',
      );
      expect(merged.single.title, 'R');
      expect(merged.single.coverPath, '/docs/covers/x.jpg');
    });
  });
}
