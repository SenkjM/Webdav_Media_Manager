import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../services/wdmm_vfs.dart';
import '../services/rust_core_service.dart';
import 'webdav_account.dart';

/// WdmmVfs implementation that calls wdmm-core FFI (Phase 2.3).
///
/// Every driver call is a synchronous FFI entry point that `block_on`s inside
/// the Rust runtime, so running one on the UI isolate freezes Flutter for the
/// whole network round trip (observed as a 5 s+ "input dispatching timed out"
/// ANR while listing a slow share). All calls therefore hop to a worker
/// isolate through [_offMain]; the returned data crosses back either as a
/// String (control plane) or as [TransferableTypedData] (file bytes, moved
/// without a copy).
class RustWdmmVfs extends WdmmVfs {
  RustWdmmVfs(this.account);

  final WebDavAccount account;

  @override
  Future<void> init() async {
    // No initialization needed for FFI driver
  }

  /// Run a blocking FFI call on a worker isolate.
  ///
  /// The closure must only capture sendable values (`account.id` is read into a
  /// local before the call); it must never capture `this`.
  static Future<T> _offMain<T>(T Function() body) =>
      RustCoreService.runOffMain<T>(body);

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final id = account.id;
    final result = await _offMain<String?>(
      () => RustCoreService.accountListDir(id, path),
    );
    _check(result);
    final List<dynamic> entries = jsonDecode(result!);
    return entries.map((e) => _parseEntry(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final id = account.id;
    final result = await _offMain<String?>(
      () => RustCoreService.accountGetEntry(id, path),
    );
    _check(result);
    final Map<String, dynamic> entry = jsonDecode(result!);
    return _parseEntry(entry);
  }

  @override
  Future<void> mkdir(String path) async {
    final id = account.id;
    _check(await _offMain<String?>(() => RustCoreService.accountMkdir(id, path)));
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final id = account.id;
    _check(
      await _offMain<String?>(
        () => RustCoreService.accountRename(id, path, newPath),
      ),
    );
  }

  @override
  Future<void> remove(String path) async {
    final id = account.id;
    _check(
      await _offMain<String?>(() => RustCoreService.accountRemove(id, path)),
    );
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
    final id = account.id;
    _check(
      await _offMain<String?>(
        () => RustCoreService.accountCopy(id, srcPath, dstPath),
      ),
    );
  }

  @override
  Future<void> ensureDirectory(String path) async {
    final id = account.id;
    _check(
      await _offMain<String?>(
        () => RustCoreService.accountEnsureDir(id, path),
      ),
    );
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
    // Base64-encoding and the blocking FFI call both stay off the UI isolate;
    // the bytes themselves are handed over without a copy.
    final payload = TransferableTypedData.fromList([Uint8List.fromList(buffer)]);
    final id = account.id;
    _check(
      await _offMain<String?>(() => _putBytes(id, path, payload)),
    );
  }

  @override
  Stream<List<int>> openContent(String path) async* {
    final id = account.id;
    final out = await _offMain<Object>(
      () => _readBytes(id, () => RustCoreService.accountGetContent(id, path)),
    );
    yield _bytesOf(out);
  }

  @override
  Stream<List<int>> openContentRange(String path, int start, int end) async* {
    final id = account.id;
    final out = await _offMain<Object>(
      () => _readBytes(
        id,
        () => RustCoreService.accountGetContentRange(
          id,
          path,
          start.toString(),
          end.toString(),
        ),
      ),
    );
    yield _bytesOf(out);
  }

  @override
  Future<List<AccountStatusTag>> statusTags() async {
    final id = account.id;
    final result = await _offMain<String?>(
      () => RustCoreService.accountStatusTags(id),
    );
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

  /// Upload base64-encoded bytes (worker-isolate side).
  static String? _putBytes(
    String accountId,
    String path,
    TransferableTypedData payload,
  ) {
    final b64 = base64Encode(payload.materialize().asUint8List());
    return RustCoreService.accountPutContent(accountId, path, b64);
  }

  /// Read a whole file / byte range (worker-isolate side).
  ///
  /// Returns [TransferableTypedData] on success or the FFI error text as a
  /// `String`; `{}` payloads without `data` become an empty body.
  static Object _readBytes(String accountId, String? Function() call) {
    final result = call();
    if (result == null) return 'FFI unavailable';
    if (result.startsWith('error:')) return result.substring(6);
    final Map<String, dynamic> obj = jsonDecode(result);
    final data = obj['data'] as String?;
    if (data == null || data.isEmpty) {
      return TransferableTypedData.fromList([Uint8List(0)]);
    }
    return TransferableTypedData.fromList([base64Decode(data)]);
  }

  static Uint8List _bytesOf(Object out) {
    if (out is String) throw WdmmVfsException(out);
    return (out as TransferableTypedData).materialize().asUint8List();
  }

  /// Throw the driver error carried by an FFI result (`null` / `"error:…"`).
  static void _check(String? result) {
    if (result == null) {
      throw WdmmVfsException('FFI unavailable');
    }
    if (result.startsWith('error:')) {
      throw WdmmVfsException(result.substring(6));
    }
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
