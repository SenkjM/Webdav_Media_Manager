import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:webdav_media_manager/main.dart' as app;
import 'package:webdav_media_manager/services/rust_core_service.dart';
import 'package:webdav_media_manager/utils/cue_sheet.dart';

/// Shared probe helpers for the on-device E2E suites.
///
/// Everything is configured through `--dart-define` (see `tool/e2e.ps1`), so
/// the repository never carries a real host, path or credential.
const e2eWebdavUrl = String.fromEnvironment('E2E_WEBDAV_URL');
const e2eWebdavUser = String.fromEnvironment('E2E_WEBDAV_USER');
const e2eWebdavPass = String.fromEnvironment('E2E_WEBDAV_PASS');
const e2eMusicRoot = String.fromEnvironment('E2E_MUSIC_ROOT');
const e2eTvRoot = String.fromEnvironment('E2E_TV_ROOT');
const e2eMangaRoot = String.fromEnvironment(
  'E2E_MANGA_ROOT',
  defaultValue: '/Local/Downloads/Manga',
);
const e2eCuePath = String.fromEnvironment('E2E_CUE_PATH');
const e2eCbzPath = String.fromEnvironment('E2E_CBZ_PATH');
const e2eDmrName = String.fromEnvironment('E2E_DMR_NAME', defaultValue: 'Kodi');
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

/// Boots the real app once and waits for the first frame.
///
/// Every suite starts from the production entry point on purpose: the E2E
/// target must exercise the same wiring (providers, FFI init, boot trace) the
/// user gets, not a test-only bootstrap.
Future<void> bootApp(WidgetTester tester) async {
  await app.main();
  await tester.pumpAndSettle(
    const Duration(milliseconds: 200),
    EnginePhase.sendSemanticsUpdate,
    const Duration(minutes: 2),
  );
}

/// The [BuildContext] below [MaterialApp], i.e. with every provider in scope.
BuildContext appContext(WidgetTester tester) =>
    tester.element(find.byType(MaterialApp).first);

/// Reads a provider that `main.dart` puts above [MaterialApp].
T appService<T>(WidgetTester tester) => appContext(tester).read<T>();

/// Pumps until [predicate] holds, letting real timers/FFI run between frames.
///
/// Integration tests run with real timers, so a bare `pumpAndSettle` does not
/// advance the queue's 200 ms poll loop — this helper does both.
Future<void> pumpUntil(
  WidgetTester tester,
  String label,
  bool Function() predicate, {
  Duration timeout = const Duration(minutes: 3),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(interval);
    await tester.pump();
  }
  fail('timed out after ${timeout.inSeconds}s waiting for $label');
}

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
  final renderers = discoverRenderers();
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

/// SSDP discovery without assertions, for suites that tolerate no renderer.
List<Map<String, dynamic>> discoverRenderers() {
  final raw = RustCoreService.dlnaDiscoverExt(timeoutMs: 4000);
  expect(raw, isNotNull, reason: 'native core must expose dlna discovery');
  expect(raw!.startsWith('error:'), isFalse, reason: 'discovery failed: $raw');
  return (jsonDecode(raw) as List<dynamic>)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

/// First audio file found under [e2eMusicRoot], searching at most 5 albums.
String findAudioFile() {
  final dirs = listDir(e2eMusicRoot).where(isDir).toList();
  expect(dirs, isNotEmpty, reason: 'no album under $e2eMusicRoot');
  for (final dir in dirs.take(5)) {
    final dirPath = joinPath(e2eMusicRoot, dir);
    for (final entry in listDir(dirPath)) {
      if (isDir(entry)) continue;
      final path = joinPath(dirPath, entry);
      if (isAudio(path)) return path;
    }
  }
  fail('no audio file under $e2eMusicRoot');
}

/// First video file under [e2eTvRoot].
String findVideoFile() {
  for (final entry in listDir(e2eTvRoot)) {
    if (isDir(entry)) continue;
    if (isVideo(entry)) return joinPath(e2eTvRoot, entry);
  }
  fail('no video file under $e2eTvRoot');
}

/// Breadth-first search for the first file whose path ends with [suffix].
///
/// Returns null when nothing matches; callers decide whether that is a skip or
/// a failure. Directory depth is bounded so a stray symlink-ish tree cannot
/// stall the suite.
String? findFileBySuffix(
  String root,
  String suffix, {
  int maxDepth = 3,
  int maxDirs = 300,
}) {
  final wanted = suffix.toLowerCase();
  final queue = <MapEntry<String, int>>[MapEntry(root, 0)];
  var dirs = 0;
  while (queue.isNotEmpty && dirs < maxDirs) {
    final current = queue.removeAt(0);
    dirs++;
    for (final entry in listDir(current.key)) {
      final name = entry['name'] as String? ?? '';
      final path = joinPath(current.key, entry);
      if (!isDir(entry)) {
        if (name.toLowerCase().endsWith(wanted)) return path;
        continue;
      }
      if (current.value < maxDepth) {
        queue.add(MapEntry(path, current.value + 1));
      }
    }
  }
  return null;
}

/// Reads up to [maxBytes] of remote [path] as raw bytes.
Uint8List readFileBytes(String path, {int maxBytes = 1 << 20}) {
  final raw = RustCoreService.accountGetContentRange(
    e2eAccountId,
    path,
    '0',
    '${maxBytes - 1}',
  );
  expect(raw, isNotNull, reason: 'accountGetContentRange returned null');
  expect(raw!.startsWith('error:'), isFalse, reason: 'range read: $raw');
  final encoded = (jsonDecode(raw) as Map<String, dynamic>)['data'] as String?;
  expect(encoded, isNotNull, reason: 'range payload has no data: $raw');
  return base64Decode(encoded!);
}

/// Reads a small text file (CUE, NFO, …) through the native driver.
String readFileText(String path, {int maxBytes = 1 << 20}) {
  final bytes = readFileBytes(path, maxBytes: maxBytes);
  return utf8.decode(bytes, allowMalformed: true);
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

/// Metadata probe: real tags from a remote audio file via `wdmm_tags_extract`.
String probeMetadata() {
  final path = findAudioFile();
  final reply = decodeReply(
    RustCoreService.tagsExtract(e2eAccountId, path),
    'tagsExtract',
  );
  expect(reply['ok'], isTrue, reason: 'tagsExtract: $reply');
  final tags = reply['tags'];
  expect(tags, isA<Map<String, dynamic>>(),
      reason: 'tagsExtract returned no tags map: $reply');
  final map = tags as Map<String, dynamic>;
  expect(reply['format'], isA<String>(),
      reason: 'tagsExtract returned no format: $reply');
  expect(reply['format'] as String, isNotEmpty);
  // A real album rip carries at least one of these; an empty result would mean
  // the Range reader or lofty wiring silently lost the tags.
  final hasText = [map['title'], map['artist'], map['album']]
      .any((v) => v is String && v.trim().isNotEmpty);
  expect(hasText, isTrue,
      reason: 'no title/artist/album parsed from $path: $map');
  final summary = '$path format=${reply['format']} title=${map['title']} '
      'artist=${map['artist']} cover=${reply['cover'] is Map ? 'yes' : 'no'}';
  debugPrint('[E2E] metadata ok: $summary');
  return summary;
}

/// CUE parser entry point, kept here so the suites share one code path.
CueSheet? cueSheetParse(String text) => CueSheet.parseOrNull(text);

/// CUE probe. Returns null (and logs a skip reason) when no sheet exists.
String? probeCue({bool required = false}) {
  final path = e2eCuePath.isNotEmpty
      ? e2eCuePath
      : findFileBySuffix(e2eMusicRoot, '.cue');
  if (path == null) {
    if (required) fail('no .cue under $e2eMusicRoot; set E2E_CUE_PATH');
    debugPrint('[E2E] cue skipped: no .cue under $e2eMusicRoot');
    return null;
  }
  final text = readFileText(path);
  expect(text, contains('TRACK'), reason: '$path does not look like a CUE');
  final sheet = cueSheetParse(text);
  expect(sheet, isNotNull, reason: 'Rust rejected $path');
  expect(sheet!.tracks, isNotEmpty, reason: '$path parsed with no tracks');
  final summary = '$path title=${sheet.title} tracks=${sheet.tracks.length}';
  debugPrint('[E2E] cue ok: $summary');
  return summary;
}

/// CBZ probe. Returns null (and logs a skip reason) when no archive exists.
String? probeCbz({bool required = false}) {
  final path = e2eCbzPath.isNotEmpty
      ? e2eCbzPath
      : findFileBySuffix(e2eMangaRoot, '.cbz');
  if (path == null) {
    if (required) fail('no .cbz under $e2eMangaRoot; set E2E_CBZ_PATH');
    debugPrint('[E2E] cbz skipped: no .cbz under $e2eMangaRoot');
    return null;
  }
  final opened = decodeReply(
    RustCoreService.zipOpen(e2eAccountId, path),
    'zipOpen',
  );
  expect(opened['ok'], isTrue, reason: 'zipOpen: $opened');
  final images = (opened['images'] as List<dynamic>? ?? const [])
      .whereType<int>()
      .toList(growable: false);
  expect(images, isNotEmpty,
      reason: 'no image entries in $path: ${opened['entries']}');
  // Rust serialises the handle as a string (it is only ever a token).
  final handle = '${opened['handle']}';
  expect(handle, isNotEmpty, reason: 'zipOpen returned no handle: $opened');

  final page = decodeReply(
    RustCoreService.zipReadEntry(handle, '${images.first}'),
    'zipReadEntry',
  );
  expect(page['ok'], isTrue, reason: 'zipReadEntry: $page');
  final bytes = base64Decode(page['bytes_b64'] as String? ?? '');
  expect(bytes, isNotEmpty, reason: 'page ${images.first} of $path is empty');
  final summary = '$path entries=${(opened['entries'] as List<dynamic>? ??
      const []).length} images=${images.length} page=${page['name']} '
      'bytes=${bytes.length}';
  debugPrint('[E2E] cbz ok: $summary');
  return summary;
}

/// Decodes a native JSON reply, failing the test on error prefixes.
Map<String, dynamic> decodeReply(String? raw, String what) {
  expect(raw, isNotNull, reason: '$what returned null (native symbol missing)');
  expect(raw!.startsWith('error:'), isFalse, reason: '$what failed: $raw');
  final decoded = jsonDecode(raw);
  expect(decoded, isA<Map<String, dynamic>>(),
      reason: '$what returned a non-object payload: $raw');
  return decoded as Map<String, dynamic>;
}
