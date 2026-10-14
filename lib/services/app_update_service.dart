import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks releases. It is deliberately manual: nothing calls [check] except
/// the About action.
///
/// The Worker is the channel-aware path. GitHub is only a fallback: its list
/// endpoint ignores `type=`, so a fallback must not be treated as a channel
/// result. It fetches the single newest release and the UI points at the
/// releases page.
///
/// * [UpdateChannel.stable] — the latest non-prerelease. Tag `vX.Y.Z`.
/// * [UpdateChannel.preview] — the newest prerelease. Tag `vX.Y.Z-<versionCode>`.
class AppUpdateService {
  AppUpdateService({Dio? dio, MethodChannel? channel})
    : _dio = dio ?? Dio(),
      _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.senkjm.media_manager/app';

  /// Cloudflare Worker proxy URL. Primary path — avoids GitHub API rate limits.
  static const _updateBaseUrl = 'https://update.senkjm.top';

  /// GitHub API direct URL. Fallback only: no `type=` filter, newest release.
  static const _githubReleasesUrl =
      'https://api.github.com/repos/SenkjM/Webdav_Media_Manager/releases';

  static const releasesPageUrl =
      'https://github.com/SenkjM/Webdav_Media_Manager/releases';

  static String workerUrl(UpdateChannel channel) => switch (channel) {
    UpdateChannel.stable => '$_updateBaseUrl/release?channel=stable',
    UpdateChannel.preview => '$_updateBaseUrl/release?channel=preview',
  };

  /// Newest release only. GitHub ignores `type=`, so this is not a channel.
  static String githubLatestUrl() => '$_githubReleasesUrl?per_page=1';

  final Dio _dio;
  final MethodChannel _channel;

  Future<UpdateCheckResult> check({
    CancelToken? cancelToken,
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return const UpdateCheckUnsupported();
    final package = await PackageInfo.fromPlatform();
    final native = await _installInfo();
    if (native.packageName != 'com.senkjm.media_manager') {
      return const UpdateCheckUnsupported();
    }

    // Worker knows the channel. GitHub's list endpoint ignores type=, so a
    // failed Worker call must not be compared as if it were that channel.
    final workerRaw = await _getPlain(workerUrl(channel), cancelToken);
    if (workerRaw != null) {
      return _resultFromChannel(
        workerRaw,
        channel: channel,
        package: package,
        abis: native.abis,
      );
    }
    final githubRaw = await _getPlain(githubLatestUrl(), cancelToken);
    if (githubRaw == null || githubRaw.isEmpty) {
      throw StateError('Empty release response');
    }
    final latest = _firstRelease(githubRaw);
    return UpdateCheckGithubFallback(
      latestName: latest?.name ?? '',
      releasesUrl: latest?.htmlUrl ?? releasesPageUrl,
    );
  }

  Future<String?> _getPlain(String url, CancelToken? cancelToken) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {
            'Accept': 'application/json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        ),
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return data;
    } on DioException {
      return null;
    }
  }

  UpdateCheckResult _resultFromChannel(
    String raw, {
    required UpdateChannel channel,
    required PackageInfo package,
    required List<String> abis,
  }) {
    final release = _firstRelease(raw);
    if (release == null) {
      throw StateError('No ${channel.name} release found');
    }
    final verdict = compareUpdate(
      channel: channel,
      localVersionName: package.version,
      localBuildNumber: package.buildNumber,
      remote: release,
    );
    switch (verdict) {
      case UpdateVerdict.channelMismatch:
        return UpdateCheckChannelMismatch(channel);
      case UpdateVerdict.current:
        return UpdateCheckUpToDate(AppVersion.parse(package.version));
      case UpdateVerdict.newer:
        final asset = release.pickApk(abis);
        if (asset == null) return UpdateCheckNoCompatibleApk(release);
        return UpdateCheckAvailable(release, asset);
    }
  }

  UpdateRelease? _firstRelease(String raw) {
    final decoded = jsonDecode(raw);
    final map = switch (decoded) {
      List(isNotEmpty: true) when decoded.first is Map =>
        Map<String, dynamic>.from(decoded.first as Map),
      Map() => Map<String, dynamic>.from(decoded),
      _ => null,
    };
    if (map == null) return null;
    return UpdateRelease.tryParse(map);
  }

  Future<bool> openUrl(String url) async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final opened = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return opened ?? false;
    }
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else {
        return false;
      }
      return true;
    } on ProcessException {
      return false;
    }
  }

  Future<File> download(
    UpdateAsset asset, {
    ValueChanged<double>? onProgress,
  }) async {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    final safeName = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = File('$dir${Platform.pathSeparator}$safeName');
    if (await target.exists()) await target.delete();
    await _dio.download(
      asset.url,
      target.path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
      options: Options(headers: const {'Accept': 'application/octet-stream'}),
    );
    if (!await target.exists() || await target.length() <= 0) {
      throw StateError('APK download did not produce a file');
    }
    final expected = asset.sha256;
    if (expected != null) {
      final actual = (await sha256.bind(target.openRead()).first).toString();
      if (actual.toLowerCase() != expected.toLowerCase()) {
        await target.delete();
        throw StateError('APK SHA-256 mismatch');
      }
    }
    return target;
  }

  Future<UpdateInstallResult> install(File apk) async {
    if (kIsWeb || !Platform.isAndroid) return UpdateInstallResult.unsupported;
    final raw = await _channel.invokeMapMethod<String, dynamic>('installApk', {
      'path': apk.path,
    });
    return UpdateInstallResult.fromWire(raw?['state'] as String?);
  }

  Future<void> openInstallPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<_InstallInfo> _installInfo() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'updateInstallInfo',
    );
    return _InstallInfo(
      packageName: raw?['packageName'] as String? ?? '',
      abis: (raw?['abis'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }
}

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateCheckAvailable extends UpdateCheckResult {
  const UpdateCheckAvailable(this.release, this.asset);
  final UpdateRelease release;
  final UpdateAsset asset;
}

class UpdateCheckUpToDate extends UpdateCheckResult {
  const UpdateCheckUpToDate(this.version);
  final AppVersion version;
}

class UpdateCheckNoCompatibleApk extends UpdateCheckResult {
  const UpdateCheckNoCompatibleApk(this.release);
  final UpdateRelease release;
}

class UpdateCheckUnsupported extends UpdateCheckResult {
  const UpdateCheckUnsupported();
}

/// Worker returned a release for the other channel. Do not call that "up to
/// date": a stable buildCode can be lower than the installed preview code.
class UpdateCheckChannelMismatch extends UpdateCheckResult {
  const UpdateCheckChannelMismatch(this.channel);
  final UpdateChannel channel;
}

/// Worker was unreachable. [latestName] is GitHub's newest release, not a
/// channel result. [releasesUrl] opens the releases page.
class UpdateCheckGithubFallback extends UpdateCheckResult {
  const UpdateCheckGithubFallback({
    required this.latestName,
    required this.releasesUrl,
  });
  final String latestName;
  final String releasesUrl;
}

enum UpdateVerdict { newer, current, channelMismatch }

/// Channel-aware compare. A preview request must not treat a stable release as
/// current just because its synthetic buildCode is smaller.
UpdateVerdict compareUpdate({
  required UpdateChannel channel,
  required String localVersionName,
  required String localBuildNumber,
  required UpdateRelease remote,
}) {
  final wantsPreview = channel == UpdateChannel.preview;
  if (remote.isPrerelease != wantsPreview) {
    return UpdateVerdict.channelMismatch;
  }
  final localCode = int.tryParse(localBuildNumber);
  if (localCode != null) {
    return remote.buildCode > localCode
        ? UpdateVerdict.newer
        : UpdateVerdict.current;
  }
  final local = AppVersion.parse(localVersionName);
  return remote.version.compareTo(local) > 0
      ? UpdateVerdict.newer
      : UpdateVerdict.current;
}

enum InstalledEdition { stable, preview }

/// Prod builds: a versionCode other than the stable formula, or a
/// `vX.Y.Z-<code>` name, is a preview. Stable tags are `vX.Y.Z` with code
/// `major*1e8 + minor*1e6 + patch*1e4`.
InstalledEdition editionFromVersion({
  required String versionName,
  required String buildNumber,
}) {
  final code = int.tryParse(buildNumber);
  AppVersion? version;
  try {
    version = AppVersion.parse(versionName);
  } on FormatException {
    version = null;
  }
  if (version != null && code != null && code != version.releaseBuildCode) {
    return InstalledEdition.preview;
  }
  if (RegExp(r'-\d+$').hasMatch(versionName.trim())) {
    return InstalledEdition.preview;
  }
  return InstalledEdition.stable;
}

/// Check channel selected before the user touches the segmented button.
UpdateChannel channelForInstalledEdition(InstalledEdition edition) =>
    switch (edition) {
      InstalledEdition.preview => UpdateChannel.preview,
      InstalledEdition.stable => UpdateChannel.stable,
    };

enum AppInstallFlavor { prod, dev, sandbox }

AppInstallFlavor flavorFromPackageName(String packageName) {
  if (packageName.endsWith('.dev')) return AppInstallFlavor.dev;
  if (packageName.endsWith('.test')) return AppInstallFlavor.sandbox;
  return AppInstallFlavor.prod;
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.assets,
    required this.buildCode,
    required this.isPrerelease,
    this.htmlUrl,
  });
  static UpdateRelease? tryParse(Map<String, dynamic> json) {
    try {
      return UpdateRelease.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final version = AppVersion.parse(tag);
    final encodedCode = RegExp(r'-(\d+)$').firstMatch(tag)?.group(1);
    return UpdateRelease(
      version: version,
      name: json['name'] as String? ?? tag,
      notes: json['body'] as String? ?? '',
      assets: [
        for (final value in json['assets'] as List<dynamic>? ?? const [])
          UpdateAsset.fromJson(value as Map<String, dynamic>),
      ],
      buildCode: int.tryParse(encodedCode ?? '') ?? version.releaseBuildCode,
      isPrerelease: json['prerelease'] == true,
      htmlUrl: json['html_url'] as String?,
    );
  }
  final AppVersion version;
  final String name;
  final String notes;
  final List<UpdateAsset> assets;
  final int buildCode;
  final bool isPrerelease;
  final String? htmlUrl;
  UpdateAsset? pickApk(List<String> abis) {
    final apkAssets = assets.where(
      (e) => e.name.toLowerCase().endsWith('.apk'),
    );
    for (final abi in abis) {
      for (final asset in apkAssets) {
        if (asset.name.contains('-$abi.apk')) return asset;
      }
      if (abi == 'arm64-v8a' || abi == 'armeabi-v7a') {
        for (final asset in apkAssets) {
          if (asset.name.endsWith('-arm.apk')) return asset;
        }
      }
    }
    return null;
  }
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.sha256,
  });
  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    final digest = json['digest'] as String?;
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      url: json['browser_download_url'] as String? ?? '',
      sha256: digest?.startsWith('sha256:') == true
          ? digest!.substring(7)
          : null,
    );
  }
  final String name;
  final String url;
  final String? sha256;
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);
  factory AppVersion.parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(value.trim());
    if (match == null) throw FormatException('Invalid version: $value');
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
  final int major;
  final int minor;
  final int patch;
  int get releaseBuildCode =>
      major * 100000000 + minor * 1000000 + patch * 10000;
  @override
  int compareTo(AppVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    return minorResult != 0 ? minorResult : patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// Which GitHub release channel to check. Maps 1:1 to GitHub's `/releases`
/// `type=` parameter so the server does the filtering.
enum UpdateChannel {
  /// Non-prerelease, non-draft. Matches workflow tag `vX.Y.Z`.
  stable,
  /// Prereleases only. Matches workflow tag `vX.Y.Z-<versionCode>`.
  preview,
}

enum UpdateInstallResult {
  started,
  permissionRequired,
  unsupported,
  failed;

  static UpdateInstallResult fromWire(String? value) => switch (value) {
    'started' => started,
    'permission_required' => permissionRequired,
    'unsupported' => unsupported,
    _ => failed,
  };
}

class _InstallInfo {
  const _InstallInfo({required this.packageName, required this.abis});
  final String packageName;
  final List<String> abis;
}
