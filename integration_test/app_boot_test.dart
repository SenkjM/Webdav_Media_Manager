import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/main.dart' as app;

/// Smallest possible on-device smoke: boot the real app and prove the Flutter
/// surface plus the native core came up without an exception.
///
/// Deliberately touches no business code: it only mounts `main()` and asserts
/// what the shell always renders.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots on a device and shows its shell', (tester) async {
    await app.main();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate,
      const Duration(minutes: 2),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
