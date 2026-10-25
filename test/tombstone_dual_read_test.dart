import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/library_service.dart';

/// Pure-Dart decode helper test: LibraryService.decodeDeletedTracksForTest
/// converts Rust JSON array → sqflite-compatible Map list. No FFI / device.
void main() {
  test('_decodeDeletedTracks parses valid Rust JSON array', () {
    final json = jsonEncode([
      {
        'source_name': 'wd-main',
        'remote_path': '/music/track1.flac',
        'rev': 100,
        'deleted_at': '2024-01-02T03:04:05.000Z',
        'pushed': 0,
      },
      {
        'source_name': 'wd-backup',
        'remote_path': '/music/track2.mp3',
        'rev': 200,
        'deleted_at': '2024-01-03T00:00:00.000Z',
        'pushed': 1,
      },
    ]);

    final result = LibraryService.decodeDeletedTracksForTest(json);
    expect(result, isNotNull);
    expect(result!.length, 2);

    final first = result[0];
    expect(first['source_name'], 'wd-main');
    expect(first['remote_path'], '/music/track1.flac');
    expect(first['rev'], 100);
    expect(first['deleted_at'], '2024-01-02T03:04:05.000Z');
    expect(first['pushed'], 0);

    final second = result[1];
    expect(second['source_name'], 'wd-backup');
    expect(second['remote_path'], '/music/track2.mp3');
    expect(second['rev'], 200);
    expect(second['deleted_at'], '2024-01-03T00:00:00.000Z');
    expect(second['pushed'], 1);
  });

  test('_decodeDeletedTracks returns empty list for empty array', () {
    final json = jsonEncode([]);
    final result = LibraryService.decodeDeletedTracksForTest(json);
    expect(result, isNotNull);
    expect(result!.isEmpty, true);
  });

  test('_decodeDeletedTracks returns null for invalid JSON', () {
    final result = LibraryService.decodeDeletedTracksForTest('not json');
    expect(result, isNull);
  });

  test('_decodeDeletedTracks returns null for non-array JSON', () {
    final json = jsonEncode({'key': 'value'});
    final result = LibraryService.decodeDeletedTracksForTest(json);
    expect(result, isNull);
  });

  test('_decodeDeletedTracks handles missing fields gracefully', () {
    final json = jsonEncode([
      {
        'source_name': 'wd-main',
        // missing remote_path, rev, deleted_at, pushed
      },
      {
        'remote_path': '/track.flac',
        // missing source_name
        'rev': 42,
      },
    ]);

    final result = LibraryService.decodeDeletedTracksForTest(json);
    expect(result, isNotNull);
    expect(result!.length, 2);

    final first = result[0];
    expect(first['source_name'], 'wd-main');
    expect(first['remote_path'], '');
    expect(first['rev'], 0);
    expect(first['deleted_at'], '');
    expect(first['pushed'], 0);

    final second = result[1];
    expect(second['source_name'], '');
    expect(second['remote_path'], '/track.flac');
    expect(second['rev'], 42);
    expect(second['deleted_at'], '');
    expect(second['pushed'], 0);
  });

  test('_decodeDeletedTracks converts num to int for rev/pushed', () {
    final json = jsonEncode([
      {
        'source_name': 'wd-main',
        'remote_path': '/track.flac',
        'rev': 100.5, // num, not int
        'deleted_at': '2024-01-02T03:04:05.000Z',
        'pushed': 1.0,
      },
    ]);

    final result = LibraryService.decodeDeletedTracksForTest(json);
    expect(result, isNotNull);
    expect(result!.length, 1);
    expect(result[0]['rev'], isA<int>());
    expect(result[0]['rev'], 100);
    expect(result[0]['pushed'], isA<int>());
    expect(result[0]['pushed'], 1);
  });
}
