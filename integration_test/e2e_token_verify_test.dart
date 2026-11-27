import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/services/rust_core_service.dart';

import 'e2e_support.dart';

/// Providers whose access token the app maintains itself (baidu / aliyun /
/// 115 / 123) must be creatable from the setup form without an access token:
/// verification exchanges the stored refresh material. Before this was fixed
/// every one of them failed with "missing access_token" and could not be saved.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('token providers: setup works without a pre-existing access token',
      (tester) async {
    await bootApp(tester);

    // Empty config is the worst case: no token exists yet. Verification must
    // fail on the *refresh material* the user can fix in the form, with the
    // provider's stable err.* code, never on a driver constructor that demands
    // an access token.
    const expectedCodes = <String, String>{
      '115': 'err.open115MissingRefreshToken',
      '123_open': 'err.missingRefreshToken',
      'baidu': 'err.baiduMissingRefreshToken',
      'aliyun': 'err.aliyunMissingRefreshToken',
    };
    for (final entry in expectedCodes.entries) {
      final raw = RustCoreService.accountVerify(
          entry.key, jsonEncode(<String, dynamic>{}));
      expect(raw, isNotNull, reason: entry.key);
      expect(raw!.startsWith('error:'), isTrue,
          reason: '${entry.key} should reject an empty config: $raw');
      expect(raw.contains(entry.value), isTrue,
          reason: '${entry.key} should point at the missing refresh token: $raw');
      expect(raw.contains('missing access_token'), isFalse,
          reason: '${entry.key} must not demand an access token at setup: $raw');
      debugPrint('[E2E] ${entry.key} verify without token: $raw');
    }

    // Verification must be *possible* once refresh material exists: the failure
    // then comes from the network, not from the driver configuration.
    final withRefresh = RustCoreService.accountVerify(
      '115',
      jsonEncode(<String, dynamic>{
        'refresh_token': 'e2e-not-a-real-token',
        'refresh_url': 'http://127.0.0.1:9/open/refreshToken',
      }),
    );
    expect(withRefresh, isNotNull);
    expect(withRefresh!.contains('err.open115MissingRefreshToken'), isFalse,
        reason: 'a refresh token is enough to attempt the exchange: $withRefresh');
    expect(withRefresh.contains('missing access_token'), isFalse,
        reason: withRefresh);
    debugPrint('[E2E] 115 verify with refresh token: $withRefresh');
  });
}
