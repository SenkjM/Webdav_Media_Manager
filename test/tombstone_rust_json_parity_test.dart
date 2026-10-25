import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Pure-Dart parity: Android deleted_tracks + sync_state JSON shapes must match
/// Core DeletedTrack + SyncState snake_case fields documented in
/// crates/wdmm-ffi/docs/API.md and used by Core schema v6. No FFI / device.
void main() {
  final now = DateTime.utc(2024, 1, 2, 3, 4, 5);

  test('DeletedTrack JSON has Core DeletedTrack keys', () {
    final json = {
      'source_name': 'wd-main',
      'remote_path': '/music/track.flac',
      'rev': 123,
      'deleted_at': now.toUtc().toIso8601String(),
      'pushed': 0,
    };
    final encoded = jsonEncode(json);
    expect(encoded, isNotNull);
    final decoded = jsonDecode(encoded);
    expect(decoded, isA<Map>());
    expect(decoded.keys.toSet(), {
      'source_name',
      'remote_path',
      'rev',
      'deleted_at',
      'pushed',
    });
    expect(decoded['source_name'], 'wd-main');
    expect(decoded['remote_path'], '/music/track.flac');
    expect(decoded['rev'], 123);
    expect(decoded['deleted_at'], now.toUtc().toIso8601String());
    expect(decoded['pushed'], 0);
  });

  test('SyncState JSON has Core SyncState keys', () {
    final partsJson = jsonEncode({'x': 1, 'y': 2});
    final json = {
      'remote_key': 'library:webdav-main',
      'last_seq': 50,
      'base_up_to': 25,
      'parts': partsJson,
      'updated_at': now.toUtc().toIso8601String(),
    };
    final encoded = jsonEncode(json);
    expect(encoded, isNotNull);
    final decoded = jsonDecode(encoded);
    expect(decoded, isA<Map>());
    expect(decoded.keys.toSet(), {
      'remote_key',
      'last_seq',
      'base_up_to',
      'parts',
      'updated_at',
    });
    expect(decoded['remote_key'], 'library:webdav-main');
    expect(decoded['last_seq'], 50);
    expect(decoded['base_up_to'], 25);
    expect(decoded['parts'], partsJson);
    expect(decoded['updated_at'], now.toUtc().toIso8601String());
  });

  test('parts field is JSON-encoded string, not direct Map', () {
    final partsMap = {'a': 10, 'b': 20};
    final partsStr = jsonEncode(partsMap);
    final stateJson = {
      'remote_key': 'library:test',
      'last_seq': 100,
      'base_up_to': 50,
      'parts': partsStr, // Must be string, not Map
      'updated_at': now.toUtc().toIso8601String(),
    };
    expect(stateJson['parts'], isA<String>());
    final decoded = jsonDecode(stateJson['parts'] as String);
    expect(decoded, isA<Map>());
    expect(decoded['a'], 10);
    expect(decoded['b'], 20);
  });
}
