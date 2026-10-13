import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/app_update_service.dart';

void main() {
  test('compares release versions numerically', () {
    expect(
      AppVersion.parse('v1.10.0').compareTo(AppVersion.parse('v1.9.9')),
      greaterThan(0),
    );
    expect(AppVersion.parse('0.2.4').compareTo(AppVersion.parse('v0.2.4')), 0);
  });

  test('prefers an exact ABI APK then the universal arm APK', () {
    const arm = UpdateAsset(
      name: 'app-arm.apk',
      url: 'https://example/arm',
      sha256: null,
    );
    const arm64 = UpdateAsset(
      name: 'app-arm64-v8a.apk',
      url: 'https://example/arm64',
      sha256: null,
    );
    const x64 = UpdateAsset(
      name: 'app-x86_64.apk',
      url: 'https://example/x64',
      sha256: null,
    );
    const release = UpdateRelease(
      version: AppVersion(1, 0, 0),
      name: 'v1.0.0',
      notes: '',
      assets: [arm, arm64, x64],
      buildCode: 100000000,
    );
    expect(release.pickApk(const ['arm64-v8a']), same(arm64));
    expect(release.pickApk(const ['armeabi-v7a']), same(arm));
    expect(release.pickApk(const ['x86_64']), same(x64));
    expect(release.pickApk(const ['x86']), isNull);
  });
}
