import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/main.dart' as app;

import 'e2e_support.dart';

/// One boot, one install, all probes.
///
/// `flutter drive` installs the APK for every target; running each probe as a
/// separate target reinstalls the app repeatedly, and on this lab phone an
/// uninstall/reinstall forces the user to re-confirm the install and re-grant
/// runtime permissions. Keeping the whole smoke in one target means one
/// `adb install -r` per run and no data loss.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('e2e full: boot, webdav, cast discovery', (tester) async {
    await app.main();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate,
      const Duration(minutes: 2),
    );

    // --- boot -------------------------------------------------------------
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);
    debugPrint('[E2E] boot ok');

    // --- webdav -----------------------------------------------------------
    if (webdavConfigured) {
      probeWebdav();
    } else {
      debugPrint('[E2E] webdav skipped: no E2E_WEBDAV_* dart-defines');
    }

    // --- cast -------------------------------------------------------------
    probeRenderers();

    expect(tester.takeException(), isNull);
    debugPrint('[E2E] full suite done');
  });
}
