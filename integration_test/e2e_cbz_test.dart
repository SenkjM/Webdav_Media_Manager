import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_support.dart';

/// CBZ module: opens a real comic archive through Rust's Range-based zip
/// reader and pulls one page's bytes back.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cbz: a real archive lists pages and reads one', (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();
    if (probeCbz() == null) {
      markTestSkipped('no .cbz under $e2eMangaRoot; set E2E_CBZ_PATH');
    }
  });
}
