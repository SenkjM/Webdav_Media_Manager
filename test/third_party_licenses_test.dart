import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/third_party_licenses.dart';

void main() {
  test('license page lists the bundled libsodium ISC notice', () async {
    registerThirdPartyLicenses();
    registerThirdPartyLicenses(); // idempotent

    final entries = await LicenseRegistry.licenses
        .where((e) => e.packages.contains('libsodium'))
        .toList();
    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('ISC License'));
    expect(text, contains('Frank Denis'));
    expect(text, contains('libsodium 1.0.20'));
  });
}
