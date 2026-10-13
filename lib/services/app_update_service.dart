import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks public GitHub releases. It is deliberately manual: nothing calls
/// [check] except the Settings action.
///
/// Two channels are supported:
///
/// * [UpdateChannel.stable] — the latest non-prerelease release. This is the
///   default and matches the workflow tag shape `vX.Y.Z` (no suffix).
/// * [UpdateChannel.preview] — the newest prerelease. Matches the workflow tag
///   shape `vX.Y.Z-<versionCode>`, e.g. `v0.2.2-2020004`.
///
/// Both channels hit GitHub's `type=` filter on `/releases?per_page=1`, so a
/// single response covers one release and no client-side sorting is needed.
class AppUpdateService {
  AppUpdateService({Dio? dio, MethodChannel? channel})
    : _dio = dio ?? Dio(),
      _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.senkjm.media_manager/app';

  /// GitHub `type` value: `stable` excludes prereleases and drafts;
  /// `prerelease` restricts to prereleases only. Keeping `per_page=1` makes
  /// the response one release object instead of a full page.
  static const _updateBaseUrl = 'https://update.senkjm.top';

  static String releasesUrl(UpdateChannel channel) => switch (channel) {
    UpdateChannel.stable => '$_updateBaseUrl/release?channel=stable',
    UpdateChannel.preview => '$_updateBaseUrl/release?channel=preview',
  };

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
    final response = await _dio.get<String>(
      releasesUrl(channel),
      options: Options(
        responseType: ResponseType.plain,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ),
      cancelToken: cancelToken,
    );
    final raw = response.data;
    if (raw == null || raw.isEmpty) throw StateError('Empty release response');
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty) {
      // `type=stable` on a repo with only prereleases returns `[]`.
      throw StateError('No ${channel.name} release found');
    }
    // The GitHub filter can still return a release whose tag the client cannot
    // parse (e.g. a legacy rolling tag named "prerelease" that some repos keep
    // around). Fail loudly instead of falling back silently.
    final first = decoded.first;
    final release = first is Map<String, dynamic>
        ? UpdateRelease.tryParse(first)
        : null;
    if (release == null) throw StateError('Unparsable ${channel.name} release');
    final asset = release.pickApk(native.abis);
    if (asset == null) return UpdateCheckNoCompatibleApk(release);
    final current = AppVersion.parse(package.version);
    final currentCode = int.tryParse(package.buildNumber);
    final isNewer = currentCode == null
        ? release.version.compareTo(current) > 0
        : release.buildCode > currentCode;
    return isNewer
        ? UpdateCheckAvailable(release, asset)
        : UpdateCheckUpToDate(current);
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

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.assets,
    required this.buildCode,
    required this.isPrerelease,
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
    );
  }
  final AppVersion version;
  final String name;
  final String notes;
  final List<UpdateAsset> assets;
  final int buildCode;
  final bool isPrerelease;
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
