import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_support.dart';

/// Metadata module: the very same `wdmm_tags_extract` the player uses must read
/// real tags straight from a remote audio file over a Range request.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('metadata: tags are read from a remote audio file',
      (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();
    probeMetadata();
  });
}
