import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/services/rust_core_service.dart';

import 'e2e_support.dart';

/// Cast module: casts a real video to the lab renderer (Kodi) through the Rust
/// session, waits for `PLAYING`, proves the position advances, then stops.
///
/// This is the only suite that actually plays; it is skipped when no renderer
/// whose friendly name contains `E2E_DMR_NAME` (default `Kodi`) is found.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cast: a real video starts and advances on the renderer',
      (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();

    final wanted = e2eDmrName.toLowerCase();
    final renderers = discoverRenderers();
    Map<String, dynamic>? renderer;
    for (final r in renderers) {
      final name = (r['friendly_name'] as String? ?? '').toLowerCase();
      if (name.contains(wanted)) {
        renderer = r;
        break;
      }
    }
    if (renderer == null) {
      markTestSkipped(
        'no renderer matching "$e2eDmrName" (found '
        '${renderers.map((r) => r['friendly_name']).join(', ')}); '
        'start Kodi with UPnP enabled',
      );
      return;
    }

    final remotePath = findCastableVideo();
    final start = decodeReply(
      RustCoreService.dlnaSessionStart(jsonEncode({
        'renderer_location': renderer['location'],
        'renderer_usn': renderer['usn'],
        'account_id': e2eAccountId,
        'remote_path': remotePath,
        'name': remotePath.split('/').last,
        'preset_id': 'passthrough',
        'force_direct': true,
        'ui_lang': 'zh',
      })),
      'dlnaSessionStart',
    );
    expect(start['ok'], isTrue, reason: 'session start: $start');
    final handle = start['handle'];
    expect(handle, isA<int>(), reason: 'session start returned no handle');

    var position = 0;
    try {
      await pumpUntil(
        tester,
        'renderer PLAYING',
        () {
          final state = sessionState(handle as int);
          position = (state['position_ms'] as num?)?.toInt() ?? 0;
          return state['transport'] == 'PLAYING';
        },
        timeout: const Duration(minutes: 2),
      );

      final baseline = position;
      await pumpUntil(
        tester,
        'position to advance past $baseline ms',
        () {
          position = (sessionState(handle as int)['position_ms'] as num?)
                  ?.toInt() ??
              0;
          return position > baseline + 500;
        },
        timeout: const Duration(seconds: 45),
      );

      debugPrint('[E2E] cast ok: ${renderer['friendly_name']} '
          '$remotePath provider=${start['provider']} position=${position}ms');
    } finally {
      final stopped = RustCoreService.dlnaSessionCmd(
        handle as int,
        jsonEncode({'cmd': 'stop'}),
      );
      final closed = RustCoreService.dlnaSessionClose(handle);
      debugPrint('[E2E] cast teardown: stop=$stopped close=$closed');
    }
  });
}

Map<String, dynamic> sessionState(int handle) {
  final raw = RustCoreService.dlnaSessionState(handle);
  expect(raw, isNotNull, reason: 'dlnaSessionState returned null');
  expect(raw!.startsWith('error:'), isFalse, reason: 'session state: $raw');
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// Prefers an MP4 (direct play in the lab) and falls back to any video.
String findCastableVideo() {
  final entries = listDir(e2eTvRoot);
  for (final entry in entries) {
    if (isDir(entry)) continue;
    final name = (entry['name'] as String? ?? '').toLowerCase();
    if (name.endsWith('.mp4')) return joinPath(e2eTvRoot, entry);
  }
  return findVideoFile();
}
