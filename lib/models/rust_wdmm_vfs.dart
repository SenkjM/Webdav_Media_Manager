import 'dart:convert';

import '../services/wdmm_vfs.dart';
import '../services/rust_core_service.dart';
import 'webdav_account.dart';

/// WdmmVfs implementation that calls wdmm-core FFI (Phase 2.3).
class RustWdmmVfs extends WdmmVfs {
  RustWdmmVfs(this.account);

  final WebDavAccount account;

  @override
  Future<void> init() async {
    // No initialization needed for FFI driver
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final result = RustCoreService.accountListDir(account.id, path);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
    final List<dynamic> entries = jsonDecode(result);
    return entries.map((e) => _parseEntry(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final result = RustCoreService.accountGetEntry(account.id, path);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
    final Map<String, dynamic> entry = jsonDecode(result);
    return _parseEntry(entry);
  }

  @override
  Future<void> mkdir(String path) async {
    final result = RustCoreService.accountMkdir(account.id, path);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final result = RustCoreService.accountRename(account.id, path, newPath);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
  }

  @override
  Future<void> remove(String path) async {
    final result = RustCoreService.accountRemove(account.id, path);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
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
    // Core FFI emits snake_case (is_dir / raw_url / raw_headers).
    final isDir = (e['is_dir'] ?? e['isDir']) as bool? ?? false;
    final rawUrl = (e['raw_url'] ?? e['rawUrl']) as String?;
    final rawHeadersRaw = e['raw_headers'] ?? e['rawHeaders'];
    Map<String, String>? rawHeaders;
    if (rawHeadersRaw is Map) {
      rawHeaders = rawHeadersRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
    } else if (rawHeadersRaw is List) {
      // Core get_entry may return [[k,v], ...]
      rawHeaders = {
        for (final pair in rawHeadersRaw)
          if (pair is List && pair.length >= 2) pair[0].toString(): pair[1].toString(),
      };
    }
    return CloudFileItem(
      name: e['name'] as String,
      isDir: isDir,
      size: (e['size'] as num?)?.toInt() ?? 0,
      modified: e['modified'] != null
          ? DateTime.tryParse(e['modified'] as String)
          : null,
      rawUrl: rawUrl,
      rawHeaders: rawHeaders,
    );
  }
}

/// Factory function for creating a RustWdmmVfs.
WdmmVfs createRustDriver(WebDavAccount account) {
  return RustWdmmVfs(account);
}

