import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_support.dart';

/// One boot, one install, every read-only probe.
///
/// `flutter test` still runs Gradle once per target, so the combined target
/// keeps the whole smoke to a single install. Suites that mutate the queue or
/// start a cast session live in their own targets on purpose.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('e2e full: boot, webdav, metadata, cue, cbz, cast discovery',
      (tester) async {
    await bootApp(tester);

    // --- boot -------------------------------------------------------------
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);
    debugPrint('[E2E] boot ok');

    if (!webdavConfigured) {
      debugPrint('[E2E] webdav skipped: no E2E_WEBDAV_* dart-defines');
      return;
    }

    // --- webdav -----------------------------------------------------------
    probeWebdav();
    // --- metadata ---------------------------------------------------------
    probeMetadata();
    // --- cue / cbz --------------------------------------------------------
    probeCue();
    probeCbz();
    // --- cast -------------------------------------------------------------
    probeRenderers();

    expect(tester.takeException(), isNull);
    debugPrint('[E2E] full suite done');
  });
}
