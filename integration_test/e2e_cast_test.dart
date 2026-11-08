import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/main.dart' as app;
import 'package:webdav_media_manager/services/rust_core_service.dart';

/// SSDP probe for the DMR used by the casting tests.
///
/// Kodi (or any other MediaRenderer) must be running on the same LAN as the
/// phone. Pass `--dart-define=E2E_REQUIRE_DMR=1` (see `tool/e2e.ps1 -RequireDmr`)
/// to turn "no renderer" into a failure; by default the probe only reports, so
/// a laptop with Kodi closed does not block the rest of the suite.
const _requireDmr = String.fromEnvironment('E2E_REQUIRE_DMR') == '1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dlna probe finds a media renderer', (tester) async {
    await app.main();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate,
      const Duration(minutes: 2),
    );

    final raw = RustCoreService.dlnaDiscoverExt(timeoutMs: 4000);
    expect(raw, isNotNull, reason: 'native core must expose dlna discovery');
    expect(raw!.startsWith('error:'), isFalse, reason: 'discovery failed: $raw');

    final renderers = (jsonDecode(raw) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    final described = renderers
        .map((r) =>
            '${r['friendly_name'] ?? '(unnamed)'} @ ${r['location'] ?? '?'}')
        .join(' | ');
    debugPrint('[E2E] renderers=${renderers.length} $described');

    expect(tester.takeException(), isNull);
    if (_requireDmr) {
      expect(renderers, isNotEmpty,
          reason: 'E2E_REQUIRE_DMR=1 but SSDP found no MediaRenderer '
              '(is Kodi running with UPnP enabled?)');
    }
  });
}
