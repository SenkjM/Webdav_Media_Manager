import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/services/rust_core_service.dart';

/// Shared probe helpers for the on-device E2E suites.
///
/// Everything is configured through `--dart-define` (see `tool/e2e.ps1`), so
/// the repository never carries a real host, path or credential.
const e2eWebdavUrl = String.fromEnvironment('E2E_WEBDAV_URL');
const e2eWebdavUser = String.fromEnvironment('E2E_WEBDAV_USER');
const e2eWebdavPass = String.fromEnvironment('E2E_WEBDAV_PASS');
const e2eMusicRoot = String.fromEnvironment('E2E_MUSIC_ROOT');
const e2eTvRoot = String.fromEnvironment('E2E_TV_ROOT');
const e2eRequireDmr = String.fromEnvironment('E2E_REQUIRE_DMR') == '1';

const e2eAccountId = 'e2e-local';
const e2eAccountName = 'E2E Local';

const audioExtensions = {
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
const videoExtensions = {'.mp4', '.mkv', '.avi', '.webm', '.ts', '.m2ts'};

bool get webdavConfigured =>
    e2eWebdavUrl.isNotEmpty &&
    e2eMusicRoot.isNotEmpty &&
    e2eTvRoot.isNotEmpty;

/// Upserts the lab account so the native core can reach the server.
void ensureE2eAccount() {
  final upserted = RustCoreService.accountUpsert(
    jsonEncode({
      'id': e2eAccountId,
      'provider_type': 'webdav',
      'display_name': e2eAccountName,
      'base_url': e2eWebdavUrl,
      'credentials': {
        'username': e2eWebdavUser,
        'password': e2eWebdavPass,
        'remote_dir': e2eMusicRoot,
      },
    }),
  );
  expect(upserted, isNotNull, reason: 'native core must be loaded');
  expect(upserted!.startsWith('error:'), isFalse,
      reason: 'accountUpsert failed: $upserted');
}

/// Lists music albums (a few) and videos, then reads a 64 KiB range.
///
/// Returns a human readable summary; throws through `expect` on failure.
String probeWebdav() {
  expect(webdavConfigured, isTrue,
      reason: 'E2E_WEBDAV_URL / E2E_MUSIC_ROOT / E2E_TV_ROOT are not set');
  ensureE2eAccount();

  final musicRootEntries = listDir(e2eMusicRoot);
  final musicDirs = musicRootEntries.where(isDir).toList();
  expect(musicDirs, isNotEmpty,
      reason: 'no sub-directory under $e2eMusicRoot: '
          '${entryNames(musicRootEntries)}');

  String? musicFile;
  var albumsScanned = 0;
  for (final dir in musicDirs) {
    if (musicFile != null || albumsScanned >= 5) break;
    albumsScanned++;
    final dirPath = joinPath(e2eMusicRoot, dir);
    final entries = listDir(dirPath);
    for (final entry in entries) {
      if (isDir(entry)) continue;
      final path = joinPath(dirPath, entry);
      if (isAudio(path)) {
        musicFile = path;
        break;
      }
    }
  }
  expect(musicFile, isNotNull,
      reason: 'no audio file in the first $albumsScanned albums under '
          '$e2eMusicRoot');

  final tvEntries = listDir(e2eTvRoot);
  final videos = tvEntries
      .where((e) => !isDir(e) && isVideo(e))
      .map((e) => joinPath(e2eTvRoot, e))
      .toList();
  expect(videos, isNotEmpty,
      reason: 'no video file under $e2eTvRoot: ${entryNames(tvEntries)}');

  final range = RustCoreService.accountGetContentRange(
    e2eAccountId,
    musicFile!,
    '0',
    '65535',
  );
  expect(range, isNotNull);
  expect(range!.startsWith('error:'), isFalse,
      reason: 'range read failed: $range');
  final bytes = base64Decode(
    (jsonDecode(range) as Map<String, dynamic>)['data'] as String? ?? '',
  );
  expect(bytes, isNotEmpty, reason: 'range read returned no bytes');

  final summary = 'music dirs=${musicDirs.length} sample=$musicFile | '
      'videos=${videos.length} sample=${videos.first} | '
      'range=${bytes.length}B';
  debugPrint('[E2E] webdav ok: $summary');
  return summary;
}

/// SSDP discovery. Returns the renderer descriptions found.
List<Map<String, dynamic>> probeRenderers() {
  final raw = RustCoreService.dlnaDiscoverExt(timeoutMs: 4000);
  expect(raw, isNotNull, reason: 'native core must expose dlna discovery');
  expect(raw!.startsWith('error:'), isFalse, reason: 'discovery failed: $raw');
  final renderers = (jsonDecode(raw) as List<dynamic>)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  final described = renderers
      .map((r) => '${r['friendly_name'] ?? '(unnamed)'} @ ${r['location'] ?? '?'}')
      .join(' | ');
  debugPrint('[E2E] renderers=${renderers.length} $described');

  if (e2eRequireDmr) {
    expect(renderers, isNotEmpty,
        reason: 'E2E_REQUIRE_DMR=1 but SSDP found no MediaRenderer '
            '(is Kodi running with UPnP enabled?)');
  }
  return renderers;
}

List<Map<String, dynamic>> listDir(String path) {
  final raw = RustCoreService.accountListDir(e2eAccountId, path);
  expect(raw, isNotNull, reason: 'accountListDir returned null for $path');
  expect(raw!.startsWith('error:'), isFalse,
      reason: 'accountListDir failed for $path: $raw');
  final decoded = jsonDecode(raw);
  expect(decoded, isA<List<dynamic>>(),
      reason: 'unexpected list payload for $path: $raw');
  return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
}

bool isDir(Map<String, dynamic> entry) =>
    (entry['is_dir'] ?? entry['isDir']) as bool? ?? false;

bool isAudio(String path) {
  final lower = path.toLowerCase();
  return audioExtensions.any(lower.endsWith);
}

bool isVideo(Map<String, dynamic> entry) {
  final name = (entry['name'] as String? ?? '').toLowerCase();
  return videoExtensions.any(name.endsWith);
}

String joinPath(String root, Map<String, dynamic> entry) {
  final base = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  return '$base/${entry['name'] as String? ?? ''}';
}

String entryNames(List<Map<String, dynamic>> entries) =>
    entries.map((e) => e['name']).take(8).join(', ');
