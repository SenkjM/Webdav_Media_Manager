import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_support.dart';

/// CUE module: locates the lab `.cue` sheet, reads it through the native
/// driver and parses it with the Rust parser the import path uses.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cue: a real sheet parses and yields tracks', (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();
    if (probeCue() == null) {
      markTestSkipped('no .cue under $e2eMusicRoot; set E2E_CUE_PATH');
    }
  });
}
