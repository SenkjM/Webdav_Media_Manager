// ═══════════════════════════════════════════════════════════════════
// CtFile (城通网盘) CloudDriver implementation
// ═══════════════════════════════════════════════════════════════════
//
// Authoritative spec: /workspace/saf_work/ctfile-wdmm-spec.md
// Reference: Worker localdev/OpenList-Worker/src/backend/drivers/ctfile/
//
// Key behaviors:
// - Session auth (OpenAPI token from 开放接口登录密钥管理).
// - Id-prefix dual strategy: d/f-prefixed ids stripped-first, raw-fallback.
// - Path→id cache with d/f keys; root = "0".
// - Upload: md5-size checksum → instant-upload check → multipart presigned URL.
// - mkdir: 403+folder_id = success (folder exists).
// - list: merged folder/list + file/list; auto-paging guarded.
// - list cache + request throttle (account form, defaults 60s / 400ms).
// - 429/5xx → retry with backoff; 401 → session expired.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../models/account_capabilities.dart';
import '../../utils/l10n_host.dart';
import '../cloud_driver.dart';

// ═══════════════════════════════════════════════════════════════════
// Addition / Client / types
// ═══════════════════════════════════════════════════════════════════

/// Root folder ID (d0 or 0, API accepts both).
const kCtFileRootId = '0';

const kDefaultBaseUrl = 'https://rest.ctfile.com/v1';
const kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
const kMaxListPages = 500;

/// Default list cache TTL (seconds). 0 = disabled.
const kDefaultListCacheSec = 60;

/// Default minimum gap between API calls (milliseconds). 0 = no throttle.
const kDefaultRequestIntervalMs = 400;

/// Driver config (aligned with Worker CtFileAddition).
class CtFileAddition {
  CtFileAddition({
    required this.session,
    this.cloudType = 'public',
    this.baseUrl = kDefaultBaseUrl,
    this.orderBy = 'name',
    this.orderDirection = 'asc',
    this.userAgent = kDefaultUserAgent,
    this.listCacheSec = kDefaultListCacheSec,
    this.requestIntervalMs = kDefaultRequestIntervalMs,
  });

  factory CtFileAddition.fromJson(Map<String, dynamic> json) => CtFileAddition(
    session: (json['session'] as String? ?? '').trim(),
    cloudType: (json['cloud_type'] as String?) == 'private' ? 'private' : 'public',
    baseUrl: (json['base_url'] as String? ?? kDefaultBaseUrl).trim(),
    orderBy: json['order_by'] as String? ?? 'name',
    orderDirection: json['order_direction'] as String? ?? 'asc',
    userAgent: json['user_agent'] as String? ?? kDefaultUserAgent,
    listCacheSec: _parseNonNegInt(json['list_cache_sec'], kDefaultListCacheSec),
    requestIntervalMs: _parseNonNegInt(
      json['request_interval_ms'],
      kDefaultRequestIntervalMs,
    ),
  );

  Map<String, dynamic> toJson() => {
    'session': session,
    'cloud_type': cloudType,
    'base_url': baseUrl,
    'order_by': orderBy,
    'order_direction': orderDirection,
    'user_agent': userAgent,
    'list_cache_sec': listCacheSec,
    'request_interval_ms': requestIntervalMs,
  };

  /// OpenAPI Session token (backend "开放接口登录密钥").
  String session;
  String cloudType;
  String baseUrl;
  String orderBy;
  String orderDirection;
  String userAgent;

  /// Seconds to cache folder/file list results for a folder id. 0 disables.
  int listCacheSec;

  /// Minimum milliseconds between REST calls. 0 disables throttling.
  int requestIntervalMs;
}

int _parseNonNegInt(Object? raw, int fallback) {
  if (raw == null) return fallback;
  final n = raw is num ? raw.toInt() : int.tryParse(raw.toString().trim());
  if (n == null || n < 0) return fallback;
  return n;
}

/// Folder entry from /folder/list.
class CtFileFolder {
  CtFileFolder({required this.key, required this.name, this.date});

  factory CtFileFolder.fromMap(Map<String, dynamic> m) => CtFileFolder(
    key: m['key'] as String? ?? m['folder_id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    date: m['date'],
  );

  final String key; // d-prefixed id.
  final String name;
  final Object? date; // unix sec or "YYYY-MM-DD HH:mm:ss".
}

/// File entry from /file/list.
class CtFileFile {
  CtFileFile({
    required this.key,
    required this.name,
    this.size = 0,
    this.date,
    this.imgsrc,
  });

  factory CtFileFile.fromMap(Map<String, dynamic> m) => CtFileFile(
    key: m['key'] as String? ?? m['file_id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    size: (m['size'] as num?)?.toInt() ?? 0,
    date: m['date'],
    imgsrc: m['imgsrc'] as String?,
  );

  final String key; // f-prefixed id.
  final String name;
  final int size;
  final Object? date; // unix sec or "YYYY-MM-DD HH:mm:ss".
  final String? imgsrc;
}

/// Unified API response wrapper.
class CtFileResp {
  CtFileResp(this.raw)
    : code = (raw['code'] as num?)?.toInt(),
      message = raw['message'] as String?,
      results = raw['results'];

  factory CtFileResp.fromText(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return CtFileResp(decoded);
    } catch (_) {}
    return CtFileResp(<String, dynamic>{});
  }

  final Map<String, dynamic> raw;
  final int? code;
  final String? message;
  final Object? results;

  bool get isOk => code == 200 || code == null;
}

/// Parse CtFile date (unix sec or "YYYY-MM-DD HH:mm:ss" UTC+8 wallclock).
DateTime? parseCtFileDate(Object? date) {
  if (date == null) return null;
  final raw = date.toString().trim();
  if (raw.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(raw)) {
    final n = int.tryParse(raw);
    if (n != null && n > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        n > 1e12 ? n.toInt() : (n * 1000).toInt(),
      );
    }
  }
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (parsed != null) return parsed;
  return null;
}

// ═══════════════════════════════════════════════════════════════════
// CtFileClient — OpenAPI session auth + retry + id-prefix dual strategy
// ═══════════════════════════════════════════════════════════════════

String _stripIdPrefix(String id) => id.replaceFirst(RegExp(r'^([df])(?=\d)'), '');

class _CtFileListCacheEntry<T> {
  _CtFileListCacheEntry(this.items, this.expiresAt);
  final List<T> items;
  final DateTime expiresAt;
  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class CtFileClient {
  CtFileClient(this.addition, {Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'Accept': 'application/json'},
        validateStatus: (_) => true,
      ));

  final CtFileAddition addition;
  final Dio _dio;

  String get _baseUrl => addition.baseUrl.isEmpty
      ? kDefaultBaseUrl
      : addition.baseUrl.replaceAll(RegExp(r'/+$'), '');
  String get _ns => addition.cloudType == 'private' ? 'private' : 'public';
  String get _session => addition.session.trim();

  /// Profile check (init validation).
  final Map<String, _CtFileListCacheEntry<CtFileFolder>> _folderListCache = {};
  final Map<String, _CtFileListCacheEntry<CtFileFile>> _fileListCache = {};
  Future<void>? _throttleGate;
  DateTime? _lastRequestAt;

  /// Drop cached folder/file listings (call after mutations).
  void clearListCache() {
    _folderListCache.clear();
    _fileListCache.clear();
  }

  Future<Map<String, dynamic>> profile() async {
    final resp = await _call('/user/info/profile', {});
    return resp.raw;
  }

  /// Bandwidth query (POST /user/info/bandwidth).
  /// Returns keys: bandwidth_total / bandwidth_remaining / bandwidth_used / max_yun.
  Future<Map<String, dynamic>> bandwidth() async {
    final resp = await _call('/user/info/bandwidth', {});
    return resp.raw;
  }

  /// List folders under [folderId].
  Future<List<CtFileFolder>> listFolders(String folderId) async {
    final id = folderId.isEmpty ? kCtFileRootId : folderId;
    final ttl = addition.listCacheSec;
    if (ttl > 0) {
      final hit = _folderListCache[id];
      if (hit != null && hit.isFresh) return hit.items;
    }
    final resp = await _call(
      '/$_ns/folder/list',
      {..._orderParams(), 'folder_id': id},
    );
    final list = resp.results is List ? resp.results as List : <dynamic>[];
    final items = [
      for (final e in list)
        if (e is Map) CtFileFolder.fromMap(e as Map<String, dynamic>),
    ];
    if (ttl > 0) {
      _folderListCache[id] = _CtFileListCacheEntry(
        items,
        DateTime.now().add(Duration(seconds: ttl)),
      );
    }
    return items;
  }

  /// List files under [folderId] with auto-pagination.
  Future<List<CtFileFile>> listFiles(String folderId) async {
    final id = folderId.isEmpty ? kCtFileRootId : folderId;
    final ttl = addition.listCacheSec;
    if (ttl > 0) {
      final hit = _fileListCache[id];
      if (hit != null && hit.isFresh) return hit.items;
    }
    final all = <CtFileFile>[];
    var start = 0;
    var prevFirstKey = '';
    for (var page = 0; page < kMaxListPages; page++) {
      final resp = await _call(
        '/$_ns/file/list',
        {..._orderParams(), 'folder_id': id, 'start': '$start'},
      );
      final results = resp.results is List ? resp.results as List : <dynamic>[];
      if (results.isEmpty) break;
      final firstKey = results.first is Map ? (results.first as Map)['key'] as String? ?? '' : '';
      if (page > 0 && firstKey == prevFirstKey) break;
      prevFirstKey = firstKey;
      for (final e in results) {
        if (e is Map) all.add(CtFileFile.fromMap(e as Map<String, dynamic>));
      }
      start += results.length;
    }
    if (ttl > 0) {
      _fileListCache[id] = _CtFileListCacheEntry(
        all,
        DateTime.now().add(Duration(seconds: ttl)),
      );
    }
    return all;
  }

  /// Folder meta (raw first, 400/404 retry stripped).
  Future<Map<String, dynamic>> folderMeta(String folderId) async {
    return _callWithId('/$_ns/folder/meta', 'folder_id', folderId, {}, prefer: 'raw');
  }

  /// File meta (stripped first, 400/404 retry raw).
  Future<Map<String, dynamic>> fileMeta(String fileId) async {
    return _callWithId('/$_ns/file/meta', 'file_id', fileId, {}, prefer: 'stripped');
  }

  /// Get download URL (fetch_url).
  Future<String> fetchDownloadUrl(String fileId) async {
    final body = await _callWithId('/$_ns/file/fetch_url', 'file_id', fileId, {}, prefer: 'stripped');
    final url = body['download_url'] as String?;
    if (url == null || url.isEmpty) {
      throw CloudDriverException('[CtFile] fetch_url returned empty download_url');
    }
    return url;
  }

  /// Create folder.
  Future<String> mkdir(String parentId, String name) async {
    try {
      final resp = await _call('/$_ns/folder/create', {
        'folder_id': parentId.isEmpty ? kCtFileRootId : parentId,
        'name': name,
        'description': '',
        'is_hidden': false,
      });
      return (resp.raw['folder_id'] ?? resp.raw['folder_path'] ?? '').toString();
    } on CloudDriverException catch (e) {
      if (e.message.contains('403')) {
        final existing = e.cause is CtFileResp ? (e.cause as CtFileResp).raw['folder_id'] : null;
        if (existing != null) return existing.toString();
      }
      rethrow;
    }
  }

  /// Rename file.
  Future<void> renameFile(String fileId, String newName) async {
    await _callWithId('/$_ns/file/modify_meta', 'file_id', fileId, {'name': newName}, prefer: 'stripped');
  }

  /// Rename folder.
  Future<void> renameFolder(String folderId, String newName) async {
    await _callWithId('/$_ns/folder/modify_meta', 'folder_id', folderId, {'name': newName, 'is_rename': true}, prefer: 'raw');
  }

  /// Delete (move to trash).
  Future<void> remove(List<String> ids) async {
    if (ids.isEmpty) return;
    await _callWithIds('/$_ns/file/delete', ids, {});
  }

  /// Move to target folder.
  Future<void> move(List<String> ids, String targetFolderId) async {
    if (ids.isEmpty) return;
    await _callWithIds('/$_ns/file/move', ids, {'folder_id': targetFolderId.isEmpty ? kCtFileRootId : targetFolderId});
  }

  /// Copy to target folder (spec §实现要点 #6).
  Future<void> copy(List<String> ids, String targetFolderId) async {
    if (ids.isEmpty) return;
    await _callWithIds('/$_ns/file/copy', ids, {'folder_id': targetFolderId.isEmpty ? kCtFileRootId : targetFolderId});
  }

  /// Upload ticket + multipart POST.
  Future<void> upload({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final checksum = '${md5.convert(bytes).toString()}-${bytes.length}';
    final resp = await _call('/$_ns/file/upload', {
      'folder_id': folderId.isEmpty ? kCtFileRootId : folderId,
      'checksum': checksum,
      'name': fileName,
    });
    final exists = (resp.raw['exists'] as num?)?.toInt() ?? 0;
    if (exists > 0) return;
    final uploadUrl = resp.raw['upload_url'] as String?;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw CloudDriverException('[CtFile] upload: no upload_url in ticket');
    }
    final formData = FormData.fromMap({
      'name': fileName,
      'filesize': '${bytes.length}',
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final uploadResp = await _dio.postUri(Uri.parse(uploadUrl), data: formData);
    if (uploadResp.statusCode != 200) {
      throw CloudDriverException(
        '[CtFile] multipart upload failed: ${uploadResp.statusCode}',
      );
    }
  }

  Map<String, dynamic> _orderParams() => {
    'orderby': addition.orderBy,
    'order': addition.orderDirection,
  };

  Future<void> _awaitThrottle() async {
    final gapMs = addition.requestIntervalMs;
    if (gapMs <= 0) return;
    final prev = _throttleGate;
    late final Future<void> mine;
    mine = () async {
      if (prev != null) await prev;
      final last = _lastRequestAt;
      if (last != null) {
        final wait = gapMs - DateTime.now().difference(last).inMilliseconds;
        if (wait > 0) {
          await Future<void>.delayed(Duration(milliseconds: wait));
        }
      }
      _lastRequestAt = DateTime.now();
    }();
    _throttleGate = mine;
    await mine;
  }

  Future<CtFileResp> _call(String path, Map<String, dynamic> body) async {
    final session = _session;
    if (session.isEmpty) {
      throw CloudDriverException('[CtFile] Session missing (no token)');
    }
    await _awaitThrottle();
    final fullUrl = '$_baseUrl$path';
    Response<String>? response;
    CloudDriverException? lastErr;
    for (var retry = 0; retry < 3; retry++) {
      try {
        response = await _dio.postUri(
          Uri.parse(fullUrl),
          data: jsonEncode({...body, 'session': session}),
          options: Options(
            contentType: 'application/json',
            headers: {'User-Agent': addition.userAgent},
          ),
        );
        final resp = CtFileResp.fromText(response.data ?? '');
        if (resp.code == 401) {
          throw CloudDriverException(
            '[CtFile] Session expired (401). Generate new session in backend 开放接口登录密钥管理.',
          );
        }
        if (resp.code == 429 || (resp.code != null && resp.code! >= 500)) {
          lastErr = CloudDriverException(
            '[CtFile] ${resp.code ?? response.statusCode}: ${resp.message ?? 'network error'}',
            resp,
          );
          if (retry < 2) {
            await Future<void>.delayed(Duration(milliseconds: 300 * (retry + 1)));
            continue;
          }
        }
        if (!resp.isOk) {
          throw CloudDriverException(
            '[CtFile] API error ${resp.code}: ${resp.message ?? ''}',
            resp,
          );
        }
        return resp;
      } catch (e) {
        if (e is CloudDriverException) rethrow;
        lastErr = CloudDriverException('[CtFile] Network: ${e.toString()}', e);
        if (retry < 2 && response?.statusCode != null && response!.statusCode! >= 500) {
          await Future<void>.delayed(Duration(milliseconds: 300 * (retry + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw lastErr ?? CloudDriverException('[CtFile] Unknown error');
  }

  Future<Map<String, dynamic>> _callWithId(
    String path,
    String paramKey,
    String id,
    Map<String, dynamic> extra, {
    required String prefer,
  }) async {
    final stripped = _stripIdPrefix(id);
    final primary = prefer == 'raw' ? id : stripped;
    final fallback = prefer == 'raw' ? stripped : id;
    try {
      final resp = await _call(path, {paramKey: primary, ...extra});
      return resp.raw;
    } on CloudDriverException catch (e) {
      if (e.cause is CtFileResp) {
        final code = (e.cause as CtFileResp).code;
        if (code == 400 || code == 404) {
          final resp2 = await _call(path, {paramKey: fallback, ...extra});
          return resp2.raw;
        }
      }
      rethrow;
    }
  }

  Future<void> _callWithIds(
    String path,
    List<String> ids,
    Map<String, dynamic> extra,
  ) async {
    try {
      await _call(path, {'ids': ids.join(','), ...extra});
    } on CloudDriverException catch (e) {
      if (e.cause is CtFileResp) {
        final code = (e.cause as CtFileResp).code;
        if (code == 400 || code == 404 || code == 405) {
          await _call(path, {'ids': ids, ...extra});
          return;
        }
      }
      rethrow;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// CtFileDriver — CloudDriver implementation
// ═══════════════════════════════════════════════════════════════════

class CtFileDriver extends CloudDriver {
  CtFileDriver({required this.addition, Dio? dio})
    : _client = CtFileClient(addition, dio: dio);

  final CtFileAddition addition;
  final CtFileClient _client;
  final Map<String, String> _pathCache = {};

  @override
  Future<void> init() async {
    try {
      await _client.profile();
    } catch (e) {
      if (e is CloudDriverException) rethrow;
      throw CloudDriverException('[CtFile] Init failed: ${e.toString()}', e);
    }
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final normalized = _normalizePath(path);
    final id = await _pathToId(normalized);
    final folders = await _client.listFolders(id);
    final files = await _client.listFiles(id);

    // Merge folder/list + file/list, then decide isDir by key prefix
    // (file/list also returns d…-prefixed directory entries with size=0, so we
    // cannot trust which endpoint returned an item). Dedupe by key: same key
    // keeps one entry; directories (key starts with 'd') win on conflict —
    // processing folders first makes first-seen-win == prefer-dir.
    final seen = <String, CloudFileItem>{};
    void addEntry(String key, String name, int size, Object? date) {
      if (seen.containsKey(key)) return; // first seen wins (folders processed first)
      final isDir = key.startsWith('d');
      seen[key] = CloudFileItem(
        name: name,
        isDir: isDir,
        size: isDir ? 0 : size,
        modified: parseCtFileDate(date),
      );
    }

    for (final f in folders) {
      addEntry(f.key, f.name, 0, f.date);
    }
    for (final f in files) {
      addEntry(f.key, f.name, f.size, f.date);
    }
    return seen.values.toList();
  }

  /// get() returns real size + rawUrl (fetch_url) + rawHeaders with UA.
  @override
  Future<CloudFileItem> get(String path) async {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return CloudFileItem(name: '/', isDir: true);
    }
    final name = _fileName(normalized);
    final id = await _pathToId(normalized, expectDir: false);
    // f-prefixed id = file; d-prefixed or '0' = directory
    if (!id.startsWith('f')) {
      return CloudFileItem(name: name, isDir: true);
    }
    final meta = await _client.fileMeta(id);
    final size = (meta['size'] as num?)?.toInt() ?? 0;
    final url = await _client.fetchDownloadUrl(id);
    return CloudFileItem(
      name: name,
      isDir: false,
      size: size,
      rawUrl: url,
      rawHeaders: <String, String>{'User-Agent': addition.userAgent},
    );
  }

  @override
  Future<void> mkdir(String path) async {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return;
    await _ensureDirectory(normalized);
    _pathCache.clear();
    _client.clearListCache();
  }

  /// rename: [newPath] is the full target path. Cross-dir move is handled
  /// as move + rename (same as other drivers).
  @override
  Future<void> rename(String path, String newPath) async {
    final srcNorm = _normalizePath(path);
    final dstNorm = _normalizePath(newPath);
    if (srcNorm == dstNorm) return;
    if (srcNorm.isEmpty) throw CloudDriverException('[CtFile] Cannot rename root');
    final id = await _pathToId(srcNorm, expectDir: false);
    final srcName = _fileName(srcNorm);
    final newName = _fileName(dstNorm);
    final srcDir = _parentPath(srcNorm);
    final dstDir = _parentPath(dstNorm);
    if (srcDir == dstDir) {
      // Same directory: rename only
      if (id.startsWith('f')) {
        await _client.renameFile(id, newName);
      } else {
        await _client.renameFolder(id, newName);
      }
    } else {
      // Cross-directory: move then rename if needed
      final dstId = await _pathToId(_normalizePath(dstDir));
      await _client.move([id], dstId);
      if (newName.isNotEmpty && newName != srcName) {
        if (id.startsWith('f')) {
          await _client.renameFile(id, newName);
        } else {
          await _client.renameFolder(id, newName);
        }
      }
    }
    _pathCache.clear();
    _client.clearListCache();
  }

  @override
  Future<void> remove(String path) async {
    final normalized = _normalizePath(path);
    final id = await _pathToId(normalized, expectDir: false);
    await _client.remove([id]);
    _pathCache.clear();
    _client.clearListCache();
  }

  @override
  Future<void> move(String srcPath, String dstDir, String newName) async {
    final srcNorm = _normalizePath(srcPath);
    final srcId = await _pathToId(srcNorm, expectDir: false);
    final dstId = await _pathToId(_normalizePath(dstDir));
    await _client.move([srcId], dstId);
    final srcName = _fileName(srcNorm);
    if (newName.isNotEmpty && newName != srcName) {
      if (srcId.startsWith('f')) {
        await _client.renameFile(srcId, newName);
      } else {
        await _client.renameFolder(srcId, newName);
      }
    }
    _pathCache.clear();
    _client.clearListCache();
  }

  /// copy: copies srcPath to dstDir; if newName differs from original name,
  /// finds the copy in dstDir by original name and renames it.
  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async {
    final srcNorm = _normalizePath(srcPath);
    final srcId = await _pathToId(srcNorm, expectDir: false);
    final dstId = await _pathToId(_normalizePath(dstDir));
    await _client.copy([srcId], dstId);
    final srcName = _fileName(srcNorm);
    if (newName.isNotEmpty && newName != srcName) {
      if (srcId.startsWith('f')) {
        final files = await _client.listFiles(dstId);
        final copied = files.where((f) => f.name == srcName).firstOrNull;
        if (copied != null) await _client.renameFile(copied.key, newName);
      } else {
        final folders = await _client.listFolders(dstId);
        final copied = folders.where((f) => f.name == srcName).firstOrNull;
        if (copied != null) await _client.renameFolder(copied.key, newName);
      }
    }
    _pathCache.clear();
    _client.clearListCache();
  }

  @override
  Future<void> uploadStream(
    String path,
    Stream<List<int>> stream,
    int size, {
    void Function(int sent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final normalized = _normalizePath(path);
    final parentPath = _parentPath(normalized);
    final fileName = _fileName(normalized);
    final parentId = await _ensureDirectory(parentPath);
    final bytes = await _streamToBytes(stream);
    if (bytes.length != size) {
      throw CloudDriverException(
        '[CtFile] uploadStream: buffered ${bytes.length} != declared $size',
      );
    }
    await _client.upload(folderId: parentId, fileName: fileName, bytes: bytes);
    onProgress?.call(bytes.length);
    _pathCache.clear();
    _client.clearListCache();
  }

  @override
  Future<void> ensureDirectory(String path) async {
    await _ensureDirectory(_normalizePath(path));
  }

  @override
  Future<void> dispose() async {
    _pathCache.clear();
    _client.clearListCache();
  }

  /// 会员 + 带宽状态标签（账号列表展示）。两路独立 fail-soft：任一失败都返回
  /// 已拿到的部分，绝不阻塞账号列表。VIP 非 VIP 且无剩余带宽时不显示带宽标签。
  @override
  Future<List<AccountStatusTag>> statusTags() async {
    final l10n = L10nHost.current;
    final tags = <AccountStatusTag>[];

    // 会员标签：优先 group_name，否则 is_vip 时用通用「会员」。
    try {
      final prof = await _client.profile();
      final groupName = (prof['group_name'] as String? ?? '').trim();
      // Worker types: is_vip may be number or boolean.
      final rawVip = prof['is_vip'];
      final isVip = rawVip == true ||
          rawVip == 1 ||
          (rawVip is num && rawVip.toInt() == 1);
      if (groupName.isNotEmpty) {
        tags.add(AccountStatusTag(key: 'vip', label: groupName));
      } else if (isVip) {
        tags.add(AccountStatusTag(key: 'vip', label: l10n.tagVip));
      }
    } catch (_) {
      // fail-soft：profile 拿不到就不显示会员标签
    }

    // 带宽标签：remaining/total 全 0（非 VIP 常见）则不显示。
    try {
      final bw = await _client.bandwidth();
      final remaining = (bw['bandwidth_remaining'] as num?)?.toInt() ?? 0;
      final total = (bw['bandwidth_total'] as num?)?.toInt() ?? 0;
      if (remaining > 0 || total > 0) {
        tags.add(AccountStatusTag(
          key: 'bw_remaining',
          label: l10n.tagBwRemaining(_formatBandwidth(remaining)),
        ));
      }
    } catch (_) {
      // fail-soft：带宽拿不到就不显示带宽标签
    }

    return tags;
  }

  /// 带宽短格式：GiB 保留一位小数，否则用 MiB 整数。
  static String _formatBandwidth(int bytes) {
    const gib = 1 << 30; // 1024^3
    const mib = 1 << 20; // 1024^2
    const kib = 1 << 10;
    if (bytes >= gib) return '${(bytes / gib).toStringAsFixed(1)} GiB';
    if (bytes >= mib) return '${(bytes / mib).round()} MiB';
    if (bytes >= kib) return '${(bytes / kib).round()} KiB';
    return '$bytes B';
  }

  String _normalizePath(String path) {
    if (path.isEmpty || path == '/') return '';
    var p = path.trim().replaceAll(RegExp(r'/+'), '/');
    if (p.startsWith('/')) p = p.substring(1);
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p.isEmpty ? '' : '/$p';
  }

  String _parentPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty || !normalized.contains('/')) return '';
    final lastSlash = normalized.lastIndexOf('/');
    return normalized.substring(0, lastSlash);
  }

  String _fileName(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return '';
    final lastSlash = normalized.lastIndexOf('/');
    return lastSlash < 0 ? normalized : normalized.substring(lastSlash + 1);
  }

  Future<String> _pathToId(String normalized, {bool? expectDir}) async {
    if (normalized.isEmpty || normalized == '/') return kCtFileRootId;
    if (_pathCache.containsKey(normalized)) return _pathCache[normalized]!;
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    var current = kCtFileRootId;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final isLast = i == segments.length - 1;
      final folders = await _client.listFolders(current);
      final match = folders.where((f) => f.name == seg).firstOrNull;
      if (match != null) {
        current = match.key;
        final builtPath = '/${segments.take(i + 1).join('/')}';
        _pathCache[builtPath] = current;
        continue;
      }
      if (isLast && expectDir == false) {
        final files = await _client.listFiles(current);
        final fileMatch = files.where((f) => f.name == seg).firstOrNull;
        if (fileMatch != null) return fileMatch.key;
      }
      throw CloudDriverException('[CtFile] Path not found: $normalized');
    }
    return current;
  }

  Future<String> _ensureDirectory(String normalized) async {
    if (normalized.isEmpty || normalized == '/') return kCtFileRootId;
    if (_pathCache.containsKey(normalized)) return _pathCache[normalized]!;
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    var current = kCtFileRootId;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final builtPath = '/${segments.take(i + 1).join('/')}';
      if (_pathCache.containsKey(builtPath)) {
        current = _pathCache[builtPath]!;
        continue;
      }
      final folders = await _client.listFolders(current);
      final match = folders.where((f) => f.name == seg).firstOrNull;
      if (match != null) {
        current = match.key;
        _pathCache[builtPath] = current;
      } else {
        final newId = await _client.mkdir(current, seg);
        if (newId.isEmpty) {
          throw CloudDriverException('[CtFile] mkdir returned empty id: $seg');
        }
        current = newId;
        _pathCache[builtPath] = current;
      }
    }
    return current;
  }

  Future<Uint8List> _streamToBytes(Stream<List<int>> stream) async {
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final bytes = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }
}

// ═══════════════════════════════════════════════════════════════════
// CtFileSpec — CloudDriverSpec implementation (form + registry hook)
// ═══════════════════════════════════════════════════════════════════

class CtFileSpec extends CloudDriverSpec {
  const CtFileSpec();

  @override
  String get typeId => 'ctfile';

  @override
  String get displayName => L10nHost.current.driverNameCtFile;

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    return CtFileDriver(addition: CtFileAddition.fromJson(config));
  }

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.write |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  Set<String> get runtimeSecretKeys => const {};

  @override
  List<CloudDriverFormItem> get form => [
    CloudDriverField(
      key: 'session',
      label: 'Session',
      hint: L10nHost.current.formHintCtFileSession,
      required: true,
      obscure: true,
    ),
    CloudDriverSelectField(
      key: 'cloud_type',
      label: L10nHost.current.formLabelCloudType,
      defaultValue: 'public',
      options: [
        ('public', L10nHost.current.formOptionCtFilePublic),
        ('private', L10nHost.current.formOptionCtFilePrivate),
      ],
    ),
    CloudDriverField(
      key: 'list_cache_sec',
      label: L10nHost.current.formLabelCtFileListCacheSec,
      hint: L10nHost.current.formHintCtFileListCacheSec,
      defaultValue: '$kDefaultListCacheSec',
    ),
    CloudDriverField(
      key: 'request_interval_ms',
      label: L10nHost.current.formLabelCtFileRequestIntervalMs,
      hint: L10nHost.current.formHintCtFileRequestIntervalMs,
      defaultValue: '$kDefaultRequestIntervalMs',
    ),
  ];
}

