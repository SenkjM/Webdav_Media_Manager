import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks public production releases. It is deliberately manual: nothing calls
/// [check] except the Settings action.
class AppUpdateService {
  AppUpdateService({Dio? dio, MethodChannel? channel})
    : _dio = dio ?? Dio(),
      _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.senkjm.media_manager/app';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/SenkjM/Webdav_Media_Manager/releases/latest';

  final Dio _dio;
  final MethodChannel _channel;

  Future<UpdateCheckResult> check() async {
    if (kIsWeb || !Platform.isAndroid) return const UpdateCheckUnsupported();
    final package = await PackageInfo.fromPlatform();
    final native = await _installInfo();
    if (native.packageName != 'com.senkjm.media_manager') {
      return const UpdateCheckUnsupported();
    }
    final response = await _dio.get<String>(
      _latestReleaseUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ),
    );
    final raw = response.data;
    if (raw == null || raw.isEmpty) throw StateError('Empty release response');
    final release = UpdateRelease.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final asset = release.pickApk(native.abis);
    if (asset == null) return UpdateCheckNoCompatibleApk(release);
    final current = AppVersion.parse(package.version);
    return release.version.compareTo(current) > 0
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
  });
  factory UpdateRelease.fromJson(Map<String, dynamic> json) => UpdateRelease(
    version: AppVersion.parse(json['tag_name'] as String? ?? ''),
    name: json['name'] as String? ?? json['tag_name'] as String? ?? '',
    notes: json['body'] as String? ?? '',
    assets: [
      for (final value in json['assets'] as List<dynamic>? ?? const [])
        UpdateAsset.fromJson(value as Map<String, dynamic>),
    ],
  );
  final AppVersion version;
  final String name;
  final String notes;
  final List<UpdateAsset> assets;
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
