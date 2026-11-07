import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/services/accounts_service.dart';

import 'e2e_support.dart';

/// Crypt module: a wrapper account keeps its source configuration across a
/// save and a reload (the settings page used to lose it on the way to Rust).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('crypt: the source configuration survives save and reload',
      (tester) async {
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    await bootApp(tester);
    ensureE2eAccount();

    final accounts = appService<AccountsService>(tester);
    final source = accounts.accountForSource(e2eAccountName);
    expect(source, isNotNull, reason: 'the e2e account is missing');

    final name = 'E2E Crypt ${DateTime.now().millisecondsSinceEpoch}';
    final config = <String, dynamic>{
      'source_account_id': source!.id,
      'source_account_id_name': source.name,
      'source_dir': '/',
      'filename_encoding': 'base64',
      'encrypted_suffix': '.bin',
      'password': 'e2e-crypt-pass',
      'filename_encryption': 'off',
      'directory_name_encryption': false,
    };

    String? createdId;
    try {
      final created = await accounts.addAccount(
        name: name,
        url: '',
        username: '',
        password: '',
        providerType: 'crypt',
      );
      createdId = created.id;
      expect(created.providerType, 'crypt');

      await accounts.saveDriverConfig(created.id, config);

      final loaded = await accounts.loadDriverConfig(created.id);
      expect(loaded, isNotNull, reason: 'the crypt config did not come back');
      expect(loaded!['source_account_id'], source.id,
          reason: 'the source account must round-trip');
      expect(loaded['source_dir'], '/');
      expect(loaded['password'], 'e2e-crypt-pass',
          reason: 'the wrapper password must round-trip');
      expect(loaded['filename_encoding'], 'base64');
      expect(loaded['encrypted_suffix'], '.bin');
      expect(loaded['filename_encryption'], 'off');

      final listed =
          accounts.accounts.where((a) => a.id == created.id).toList();
      expect(listed.length, 1,
          reason: 'the crypt account should appear exactly once');
      expect(listed.single.providerType, 'crypt');
      expect(listed.single.name, name);
      debugPrint('[E2E] crypt ok: saved and reloaded source=${source.name}');
    } finally {
      if (createdId != null) {
        try {
          await accounts.deleteAccount(createdId);
        } catch (_) {
          // cleanup path: an extra account row is harmless
        }
      }
    }
  });
}
