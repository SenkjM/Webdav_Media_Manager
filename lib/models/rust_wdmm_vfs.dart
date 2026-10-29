import 'dart:convert';

import 'package:dio/dio.dart';

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
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final dstPath = dstDir.endsWith('/')
        ? '$dstDir$newName'
        : '$dstDir/$newName';
    final result = RustCoreService.accountCopy(account.id, srcPath, dstPath);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
  }

  @override
  Future<void> ensureDirectory(String path) async {
    final result = RustCoreService.accountEnsureDir(account.id, path);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
  }

  @override
  Future<void> uploadStream(
    String path,
    Stream<List<int>> stream,
    int size, {
    void Function(int sent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Collect the stream to bytes, then upload via put_content (base64-encoded).
    // Note: this buffers the entire file in memory. For large files (B3+),
    // a streaming upload path will be added via a dedicated FFI export.
    final buffer = <int>[];
    int sent = 0;
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      sent += chunk.length;
      onProgress?.call(sent);
    }
    final b64 = base64Encode(buffer);
    final result = RustCoreService.accountPutContent(account.id, path, b64);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
  }

  @override
  Stream<List<int>> openContent(String path) async* {
    final result = RustCoreService.accountGetContent(account.id, path);
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
    final Map<String, dynamic> obj = jsonDecode(result);
    final bytes = base64Decode(obj['data'] as String);
    yield bytes;
  }

  @override
  Stream<List<int>> openContentRange(String path, int start, int end) async* {
    final result = RustCoreService.accountGetContentRange(
      account.id,
      path,
      start.toString(),
      end.toString(),
    );
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
    final Map<String, dynamic> obj = jsonDecode(result);
    final bytes = base64Decode(obj['data'] as String);
    yield bytes;
  }

  @override
  Future<List<AccountStatusTag>> statusTags() async {
    final result = RustCoreService.accountStatusTags(account.id);
    if (result == null || result.startsWith('error:')) {
      // Fail-soft per WdmmVfs contract: never block the accounts list.
      return const [];
    }
    final List<dynamic> raw = jsonDecode(result);
    return raw
        .whereType<Map<String, dynamic>>()
        .map((m) => AccountStatusTag(
              key: m['key'] as String? ?? '',
              label: m['label'] as String? ?? '',
            ))
        .toList();
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

