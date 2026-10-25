import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/rust_library_probe.dart';

/// Pure-Dart unit tests for the v9b RustLibraryProbe helpers. No FFI / device:
/// [RustLibraryProbe.countPairFromCompare] and
/// [RustLibraryProbe.formatImportSummary] are total functions over JSON
/// strings, so they can be exercised on the host.
void main() {
  group('countPairFromCompare', () {
    test('extracts left/right counts (left=sqflite, right=rusqlite)', () {
      final report = jsonEncode({
        'tracks': {
          'left_count': 142,
          'right_count': 138,
          'only_left': [],
          'only_right': [],
          'field_mismatches': [],
        },
        'deleted_tracks': {'left_count': 5, 'right_count': 5},
        'sync_state': {'left_count': 2, 'right_count': 3},
        'ok': true,
      });

      final tracks = RustLibraryProbe.countPairFromCompare(report, 'tracks');
      expect(tracks, isNotNull);
      expect(tracks!.sqflite, 142);
      expect(tracks.rusqlite, 138);

      final deleted =
          RustLibraryProbe.countPairFromCompare(report, 'deleted_tracks')!;
      expect(deleted.sqflite, 5);
      expect(deleted.rusqlite, 5);

      final sync = RustLibraryProbe.countPairFromCompare(report, 'sync_state')!;
      expect(sync.sqflite, 2);
      expect(sync.rusqlite, 3);
    });

    test('null / error: / malformed / missing surface → null (never throws)',
        () {
      expect(RustLibraryProbe.countPairFromCompare(null, 'tracks'), isNull);
      expect(
        RustLibraryProbe.countPairFromCompare('error:boom', 'tracks'),
        isNull,
      );
      expect(
        RustLibraryProbe.countPairFromCompare('not json', 'tracks'),
        isNull,
      );
      expect(
        RustLibraryProbe.countPairFromCompare('[]', 'tracks'),
        isNull,
      );
      expect(
        RustLibraryProbe.countPairFromCompare('{"ok":true}', 'tracks'),
        isNull,
      );
    });

    test('non-int counts degrade to null sides', () {
      final report = jsonEncode({
        'tracks': {'left_count': 'x', 'right_count': 7},
      });
      final pair = RustLibraryProbe.countPairFromCompare(report, 'tracks')!;
      expect(pair.sqflite, isNull);
      expect(pair.rusqlite, 7);
    });
  });

  group('formatImportSummary', () {
    test('formats all present v6 fields in a stable order', () {
      final summary = jsonEncode({
        'already_done': false,
        'tracks': 42,
        'playlists': 3,
        'entries': 120,
        'deleted_tracks': 5,
        'sync_state': 2,
      });
      expect(
        RustLibraryProbe.formatImportSummary(summary),
        '[RustLibraryProbe] import — already_done: false, tracks: 42, '
        'playlists: 3, entries: 120, deleted_tracks: 5, sync_state: 2',
      );
    });

    test('omits absent fields', () {
      final summary = jsonEncode({'already_done': true, 'tracks': 0});
      expect(
        RustLibraryProbe.formatImportSummary(summary),
        '[RustLibraryProbe] import — already_done: true, tracks: 0',
      );
    });

    test('null / error: / malformed / non-object → null', () {
      expect(RustLibraryProbe.formatImportSummary(null), isNull);
      expect(RustLibraryProbe.formatImportSummary('error:boom'), isNull);
      expect(RustLibraryProbe.formatImportSummary('nope'), isNull);
      expect(RustLibraryProbe.formatImportSummary('[1,2]'), isNull);
    });
  });
}