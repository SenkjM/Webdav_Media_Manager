import 'dart:convert';

import '../services/cloud_driver.dart';
import '../services/rust_core_service.dart';
import 'webdav_account.dart';

/// CloudDriver implementation that calls wdmm-core FFI (Phase 2.3).
class RustCloudDriver implements CloudDriver {
  RustCloudDriver(this.account);

  final WebDavAccount account;

  @override
  Future<void> init() async {
    // No initialization needed for FFI driver
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final result = RustCoreService.accountListDir(account.id, path);
    if (result == null) {
      throw CloudDriverException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw CloudDriverException(result.substring(6));
    }
    final List<dynamic> entries = jsonDecode(result);
    return entries.map((e) => _parseEntry(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final result = RustCoreService.accountGetEntry(account.id, path);
    if (result == null) {
      throw CloudDriverException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw CloudDriverException(result.substring(6));
    }
    final Map<String, dynamic> entry = jsonDecode(result);
    return _parseEntry(entry);
  }

  @override
  Future<void> mkdir(String path) async {
    final result = RustCoreService.accountMkdir(account.id, path);
    if (result == null) {
      throw CloudDriverException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw CloudDriverException(result.substring(6));
    }
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final result = RustCoreService.accountRename(account.id, path, newPath);
    if (result == null) {
      throw CloudDriverException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw CloudDriverException(result.substring(6));
    }
  }

  @override
  Future<void> remove(String path) async {
    final result = RustCoreService.accountRemove(account.id, path);
    if (result == null) {
      throw CloudDriverException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw CloudDriverException(result.substring(6));
    }
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final newPath = dstDir.endsWith('/')
        ? '$dstDir$newName'
        : '$dstDir/$newName';
    await rename(srcPath, newPath);
  }

  @override
  Future<void> copy(String srcPath, String dstDir, String newName) {
    throw UnsupportedError('copy not yet wired to FFI');
  }

  CloudFileItem _parseEntry(Map<String, dynamic> e) {
    return CloudFileItem(
      name: e['name'] as String,
      isDir: e['isDir'] as bool,
      size: (e['size'] as num?)?.toInt() ?? 0,
      modified: e['modified'] != null
          ? DateTime.tryParse(e['modified'] as String)
          : null,
      rawUrl: e['rawUrl'] as String?,
      rawHeaders: (e['rawHeaders'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Factory function for creating a RustCloudDriver.
CloudDriver createRustDriver(WebDavAccount account) {
  return RustCloudDriver(account);
}

/// Exception thrown by cloud driver operations.
class CloudDriverException implements Exception {
  CloudDriverException(this.message);
  final String message;

  @override
  String toString() => 'CloudDriverException: $message';
}
