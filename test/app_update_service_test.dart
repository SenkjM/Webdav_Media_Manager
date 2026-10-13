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

  test(
    'skips unparsable release tags such as the legacy rolling prerelease',
    () {
      expect(
        UpdateRelease.tryParse({'tag_name': 'prerelease', 'assets': []}),
        isNull,
      );
      final ok = UpdateRelease.tryParse({
        'tag_name': 'v0.2.5-2050001',
        'prerelease': true,
        'assets': [],
      })!;
      expect(ok.isPrerelease, isTrue);
      expect(ok.buildCode, 2050001);
    },
  );

  test('stable tag yields release buildCode; preview suffix overrides it', () {
    // workflow tag v0.2.2 -> code 0*1e8 + 2*1e6 + 2*1e4 + 0 = 2020000
    final stable = UpdateRelease.tryParse({
      'tag_name': 'v0.2.2',
      'prerelease': false,
      'assets': [],
    })!;
    expect(stable.buildCode, 2020000);
    expect(stable.isPrerelease, isFalse);

    // workflow tag v0.2.2-2020004 -> code 2020004
    final preview = UpdateRelease.tryParse({
      'tag_name': 'v0.2.2-2020004',
      'prerelease': true,
      'assets': [],
    })!;
    expect(preview.buildCode, 2020004);
    expect(preview.isPrerelease, isTrue);

    // Same version, but preview buildCode > stable buildCode.
    expect(preview.buildCode, greaterThan(stable.buildCode));
  });

  test('githubUrl routes each channel to the right GitHub type filter', () {
    expect(AppUpdateService.githubUrl(UpdateChannel.stable), contains('type=stable'));
    expect(AppUpdateService.githubUrl(UpdateChannel.stable), contains('per_page=1'));
    expect(AppUpdateService.githubUrl(UpdateChannel.preview), contains('type=prerelease'));
    expect(AppUpdateService.githubUrl(UpdateChannel.preview), contains('per_page=1'));
    expect(
      AppUpdateService.githubUrl(UpdateChannel.stable),
      contains('SenkjM/Webdav_Media_Manager/releases'),
    );
  });

  test('workerUrl routes each channel to the right Worker path', () {
    expect(AppUpdateService.workerUrl(UpdateChannel.stable), contains('channel=stable'));
    expect(AppUpdateService.workerUrl(UpdateChannel.preview), contains('channel=preview'));
    expect(
      AppUpdateService.workerUrl(UpdateChannel.stable),
      contains('update.senkjm.top'),
    );
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
      isPrerelease: false,
    );
    expect(release.pickApk(const ['arm64-v8a']), same(arm64));
    expect(release.pickApk(const ['armeabi-v7a']), same(arm));
    expect(release.pickApk(const ['x86_64']), same(x64));
    expect(release.pickApk(const ['x86']), isNull);
  });
}
