import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/main.dart' as app;
import 'package:webdav_media_manager/services/rust_core_service.dart';

/// End-to-end probe of a real WebDAV box, executed inside the app process.
///
/// Configured entirely through `--dart-define` (see `tool/e2e.ps1`), so no
/// host, path or credential is ever committed:
///
///   E2E_WEBDAV_URL / E2E_WEBDAV_USER / E2E_WEBDAV_PASS
///   E2E_MUSIC_ROOT / E2E_TV_ROOT
///
/// The test drives the same FFI surface the app uses (`accountUpsert`,
/// `accountListDir`, `accountGetContentRange`), so a pass means the native core
/// can authenticate, list and stream from the server.
const _url = String.fromEnvironment('E2E_WEBDAV_URL');
const _user = String.fromEnvironment('E2E_WEBDAV_USER');
const _pass = String.fromEnvironment('E2E_WEBDAV_PASS');
const _musicRoot = String.fromEnvironment('E2E_MUSIC_ROOT');
const _tvRoot = String.fromEnvironment('E2E_TV_ROOT');

const _accountId = 'e2e-local';
const _accountName = 'E2E Local';

const _audioExtensions = {
  '.flac',
  '.mp3',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.wav',
  '.ape',
  '.wv',
};
const _videoExtensions = {'.mp4', '.mkv', '.avi', '.webm', '.ts', '.m2ts'};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('webdav probe lists music and video roots', (tester) async {
    if (_url.isEmpty || _musicRoot.isEmpty || _tvRoot.isEmpty) {
      debugPrint('[E2E] skipped: E2E_WEBDAV_URL / E2E_MUSIC_ROOT / '
          'E2E_TV_ROOT are not set');
      return;
    }

    await app.main();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate,
      const Duration(minutes: 2),
    );

    final upserted = RustCoreService.accountUpsert(
      jsonEncode({
        'id': _accountId,
        'provider_type': 'webdav',
        'display_name': _accountName,
        'base_url': _url,
        'credentials': {
          'username': _user,
          'password': _pass,
          'remote_dir': _musicRoot,
        },
      }),
    );
    expect(upserted, isNotNull, reason: 'native core must be loaded');
    expect(upserted!.startsWith('error:'), isFalse,
        reason: 'accountUpsert failed: $upserted');
    debugPrint('[E2E] account ready: $_accountId -> $_url');

    // --- music -------------------------------------------------------------
    final musicRootEntries = _listDir(_musicRoot);
    final musicDirs = musicRootEntries.where(_isDir).toList();
    expect(musicDirs, isNotEmpty,
        reason: 'no sub-directory under $_musicRoot: '
            '${_names(musicRootEntries)}');
    debugPrint('[E2E] music root dirs=${musicDirs.length} '
        'files=${musicRootEntries.length - musicDirs.length}');

    String? musicFile;
    var albumsScanned = 0;
    for (final dir in musicDirs) {
      if (musicFile != null || albumsScanned >= 5) break;
      albumsScanned++;
      final dirPath = _join(_musicRoot, dir);
      final entries = _listDir(dirPath);
      musicFile = entries
          .where((e) => !_isDir(e))
          .map((e) => _join(dirPath, e))
          .firstWhereOrNull(_isAudio);
    }
    expect(musicFile, isNotNull,
        reason: 'no audio file found in the first $albumsScanned albums '
            'under $_musicRoot');
    debugPrint('[E2E] music sample: $musicFile');

    // --- video -------------------------------------------------------------
    final tvEntries = _listDir(_tvRoot);
    final videos = tvEntries
        .where((e) => !_isDir(e) && _isVideo(e))
        .map((e) => _join(_tvRoot, e))
        .toList();
    expect(videos, isNotEmpty,
        reason: 'no video file under $_tvRoot: ${_names(tvEntries)}');
    debugPrint('[E2E] video root files=${videos.length} '
        'sample=${videos.first}');

    // --- byte range --------------------------------------------------------
    final range = RustCoreService.accountGetContentRange(
      _accountId,
      musicFile!,
      '0',
      '65535',
    );
    expect(range, isNotNull);
    expect(range!.startsWith('error:'), isFalse,
        reason: 'range read failed: $range');
    final decoded = jsonDecode(range) as Map<String, dynamic>;
    final bytes = base64Decode(decoded['data'] as String? ?? '');
    expect(bytes, isNotEmpty, reason: 'range read returned no bytes');
    debugPrint('[E2E] range ok: ${bytes.length} bytes from $musicFile');

    expect(tester.takeException(), isNull);
  });
}

List<Map<String, dynamic>> _listDir(String path) {
  final raw = RustCoreService.accountListDir(_accountId, path);
  expect(raw, isNotNull, reason: 'accountListDir returned null for $path');
  expect(raw!.startsWith('error:'), isFalse,
      reason: 'accountListDir failed for $path: $raw');
  final decoded = jsonDecode(raw);
  expect(decoded, isA<List<dynamic>>(),
      reason: 'unexpected list payload for $path: $raw');
  return decoded
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

bool _isDir(Map<String, dynamic> entry) =>
    (entry['is_dir'] ?? entry['isDir']) as bool? ?? false;

bool _isAudio(String path) {
  final lower = path.toLowerCase();
  return _audioExtensions.any(lower.endsWith);
}

bool _isVideo(Map<String, dynamic> entry) {
  final name = (entry['name'] as String? ?? '').toLowerCase();
  return _videoExtensions.any(name.endsWith);
}

String _join(String root, Map<String, dynamic> entry) {
  final base = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  final name = entry['name'] as String? ?? '';
  return '$base/$name';
}

String _names(List<Map<String, dynamic>> entries) =>
    entries.map((e) => e['name']).take(8).join(', ');

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
