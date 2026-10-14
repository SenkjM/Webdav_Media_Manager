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

  test('github fallback fetches only the newest release, with no type filter', () {
    final url = AppUpdateService.githubLatestUrl();
    expect(url, contains('per_page=1'));
    expect(url, isNot(contains('type=')));
    expect(url, contains('SenkjM/Webdav_Media_Manager/releases'));
    expect(
      AppUpdateService.releasesPageUrl,
      'https://github.com/SenkjM/Webdav_Media_Manager/releases',
    );
  });

  test('preview 2050004 is not up to date against preview 2050005', () {
    final remote = UpdateRelease.tryParse({
      'tag_name': 'v0.2.5-2050005',
      'prerelease': true,
      'assets': [],
    })!;
    expect(
      compareUpdate(
        channel: UpdateChannel.preview,
        localVersionName: 'v0.2.5-2050004',
        localBuildNumber: '2050004',
        remote: remote,
      ),
      UpdateVerdict.newer,
    );
  });

  test('a stable release must not count as up to date for a preview check', () {
    final stable = UpdateRelease.tryParse({
      'tag_name': 'v0.2.5',
      'prerelease': false,
      'assets': [],
    })!;
    expect(stable.buildCode, 2050000);
    expect(
      compareUpdate(
        channel: UpdateChannel.preview,
        localVersionName: 'v0.2.5-2050004',
        localBuildNumber: '2050004',
        remote: stable,
      ),
      UpdateVerdict.channelMismatch,
    );
  });

  test('default check channel follows the installed edition', () {
    expect(
      channelForInstalledEdition(InstalledEdition.preview),
      UpdateChannel.preview,
    );
    expect(
      channelForInstalledEdition(InstalledEdition.stable),
      UpdateChannel.stable,
    );
  });

  test('edition follows the version code, not the channel button', () {
    expect(
      editionFromVersion(
        versionName: 'v0.2.5-2050004',
        buildNumber: '2050004',
      ),
      InstalledEdition.preview,
    );
    expect(
      editionFromVersion(versionName: 'v0.2.5', buildNumber: '2050000'),
      InstalledEdition.stable,
    );
    expect(flavorFromPackageName('com.senkjm.media_manager'), AppInstallFlavor.prod);
    expect(
      flavorFromPackageName('com.senkjm.media_manager.dev'),
      AppInstallFlavor.dev,
    );
    expect(
      flavorFromPackageName('com.senkjm.media_manager.test'),
      AppInstallFlavor.sandbox,
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
