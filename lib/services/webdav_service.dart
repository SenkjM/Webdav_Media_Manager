import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../services/cloud_drive_service.dart';
import '../utils/audio_extensions.dart';

/// Thin WebDAV client wrapper.
///
/// Music playback NEVER uses remote streams — only [downloadToFile] /
/// [readAsBytes] for cache population. Video playback *does* stream: it uses
/// [buildStreamSource] to hand media_kit a direct URL + Basic auth headers.
class WebDavService extends ChangeNotifier {
  /// One live client per configured account.
  ///
  /// The music library must be able to fetch a track from **its own** source
  /// account even while a different account is selected for browsing — switching
  /// the network library's account used to drop the previous client, which broke
  /// library downloads/streams whose files live on the other server.
  final Map<String, _WebDavConn> _conns = {};

  /// Account selected by the network library (browsing only).
  String? _activeAccountId;
  String? _lastError;

  /// 云盘账号分流（99 §7.2.2）：非 'webdav' 的账号不在 _conns，
  /// 对外方法先经 [_cloudOf] 转调 CloudDriveService。签名与对外行为不变。
  final CloudDriveService? _cloudDrive;

  WebDavService({CloudDriveService? cloudDrive}) : _cloudDrive = cloudDrive;

  /// Whether the active account has a usable client.
  bool get isConnected => _connFor(_activeAccountId) != null;
  String? get lastError => _lastError;

  /// Base URL / id of the **active** account (browsing target).
  String? get baseUrl => _connFor(_activeAccountId)?.url;
  String? get accountId => _activeAccountId;

  /// All registered account ids.
  List<String> get registeredAccountIds => _conns.keys.toList();

  /// Whether [accountId] has a registered client.
  bool hasAccount(String accountId) => _conns.containsKey(accountId);

  _WebDavConn? _connFor(String? accountId) {
    if (accountId == null) return null;
    return _conns[accountId];
  }

  /// Resolve the client for [accountId], falling back to the active account when
  /// no id is given (old call sites) or the requested account is unknown.
  _WebDavConn? _resolve(String? accountId) {
    if (accountId != null) return _conns[accountId];
    return _conns[_activeAccountId];
  }

  /// Register/refresh a WebDAV account. Registers the client **without**
  /// disturbing other accounts; pass [makeActive] to also select it for browsing.
  void configure({
    required String accountId,
    required String url,
    required String username,
    required String password,
    bool makeActive = true,
  }) {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    final client = webdav.newClient(
      normalized,
      user: username,
      password: password,
      debug: false,
    );
    client.setHeaders({
      'accept-charset': 'utf-8',
      'user-agent': 'WebdavMediaManager/1.0',
    });
    client.setConnectTimeout(15000);
    client.setSendTimeout(30000);
    client.setReceiveTimeout(120000);
    _conns[accountId] = _WebDavConn(
      accountId: accountId,
      url: normalized,
      username: username,
      password: password,
      client: client,
    );
    if (makeActive || _activeAccountId == null) _activeAccountId = accountId;
    _lastError = null;
    notifyListeners();
  }

  /// Drop one account (deleted from settings) or everything when [accountId] is
  /// null.
  void disconnect({String? accountId}) {
    if (accountId == null) {
      _conns.clear();
      _activeAccountId = null;
    } else {
      _conns.remove(accountId);
      if (_activeAccountId == accountId) {
        _activeAccountId = _conns.keys.isEmpty ? null : _conns.keys.first;
      }
    }
    notifyListeners();
  }

  /// Select the account the network library browses. Does not affect the music
  /// library, whose rows carry their own accountId.
  void setActiveAccount(String accountId) {
    if (_activeAccountId == accountId) return;
    _activeAccountId = accountId;
    notifyListeners();
  }

  /// Build a streaming source for media_kit. Returns null when the account has no
  /// registered client.
  ///
  /// Uses HTTP Basic auth (the same credentials the WebDAV client uses); some
  /// servers also accept a bearer/token flow, but Basic is what
  /// `webdav_client`'s `BasicAuth` sends, so we mirror it for parity.
  /// [kind] 决定这条流被媒体会话当成视频还是音乐。
  ///
  /// 默认按**网络库那套后缀配置**判定：命中音乐后缀（含用户在设置里加进去
  /// 的）就是 music，其余一律 video。视频是这条管线的原始用途，不该因为某
  /// 个后缀没被认出来就换成音乐用法。调用方也可以显式指定。
  WebDavStreamSource? buildStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
    StreamKind? kind,
  }) {
    final streamKind = kind ??
        (FileTypeConfig().categoryFor(name) == FileCategory.music
            ? StreamKind.music
            : StreamKind.video);
    // 云盘账号：直链要异步取（驱动 get），请走 [resolveStreamSource]；这里 null。
    if (_cloudOf(accountId) != null) return null;
    final conn = _resolve(accountId);
    if (conn == null) return null;
    final uri = '${conn.url}${encodeWebDavPath(remotePath)}';
    final headers = <String, String>{
      'User-Agent': 'WebdavMediaManager/1.0',
    };
    if (conn.username.isNotEmpty || conn.password.isNotEmpty) {
      final token = base64Encode(utf8.encode('${conn.username}:${conn.password}'));
      headers['Authorization'] = 'Basic $token';
    }
    return WebDavStreamSource(
      uri: uri,
      headers: headers,
      name: name,
      remotePath: remotePath,
      accountId: accountId,
      kind: streamKind,
    );
  }

  /// 流式源的异步统一入口：云盘账号要先取直链（驱动 get），
  /// WebDAV 账号沿用同步 [buildStreamSource]。新代码一律用这个。
  Future<WebDavStreamSource?> resolveStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
    StreamKind? kind,
  }) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) {
      return cloud.resolveStreamSource(
        remotePath: remotePath,
        name: name,
        accountId: accountId,
        kind: kind,
      );
    }
    return buildStreamSource(
      remotePath: remotePath,
      name: name,
      accountId: accountId,
      kind: kind,
    );
  }

  /// PROPFIND / ping to verify credentials of one account.
  Future<bool> testConnection({required String accountId}) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) {
      final ok = await cloud.testConnection(accountId);
      _lastError = ok ? null : '云盘驱动尚未接入';
      notifyListeners();
      return ok;
    }
    final conn = _resolve(accountId);
    if (conn == null) {
      _lastError = '未配置 WebDAV';
      notifyListeners();
      return false;
    }
    final client = conn.client;
    try {
      await client.ping();
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      try {
        await client.readDir('/');
        _lastError = null;
        notifyListeners();
        return true;
      } catch (e2) {
        _lastError = e2.toString();
        notifyListeners();
        return false;
      }
    }
  }

  /// List a directory on a specific account.
  Future<List<WebDavItem>> listDirectory(
    String accountId,
    String path, {
    FileTypeConfig? fileTypes,
  }) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.listDirectory(accountId, path, fileTypes: fileTypes);
    final client = _requireClient(accountId);
    final types = fileTypes ?? FileTypeConfig();
    final normalized = path.isEmpty ? '/' : path;
    final files = await client.readDir(normalized);
    final items = <WebDavItem>[];
    for (final f in files) {
      final name = f.name ?? '';
      if (name.isEmpty || name == '.' || name == '..') continue;
      var itemPath = f.path ?? '';
      if (itemPath.isEmpty) {
        itemPath = normalized.endsWith('/')
            ? '$normalized$name'
            : '$normalized/$name';
      }
      if (!itemPath.startsWith('/')) itemPath = '/$itemPath';
      final isDir = f.isDir ?? false;
      items.add(WebDavItem(
        name: name,
        path: isDir && !itemPath.endsWith('/') ? '$itemPath/' : itemPath,
        isDirectory: isDir,
        size: f.size,
        modified: f.mTime,
        category: isDir ? FileCategory.other : types.categoryFor(name),
      ));
    }
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// Download a remote file into [localFile] **from a specific account**.
  /// Never used for streaming playback.
  Future<void> downloadToFile(
    String accountId,
    String remotePath,
    File localFile, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.downloadToFile(accountId, remotePath, localFile, onProgress: onProgress, cancelToken: cancelToken);
    final client = _requireClient(accountId);
    await localFile.parent.create(recursive: true);
    await client.read2File(
      remotePath,
      localFile.path,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> readAsBytes(String accountId, String remotePath) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.readAsBytes(accountId, remotePath);
    final client = _requireClient(accountId);
    final data = await client.read(remotePath);
    return Uint8List.fromList(data);
  }

  /// Upload bytes to remote path on a specific account.
  Future<void> writeBytes(
    String accountId,
    String remotePath,
    Uint8List data,
  ) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.writeBytes(accountId, remotePath, data);
    final client = _requireClient(accountId);
    await client.write(remotePath, data);
  }

  /// Ensure directory exists (mkdirAll) on a specific account.
  Future<void> ensureDirectory(String accountId, String path) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.ensureDirectory(accountId, path);
    final client = _requireClient(accountId);
    var normalized = path.trim();
    if (normalized.isEmpty) return;
    if (!normalized.endsWith('/')) normalized = '$normalized/';
    await client.mkdirAll(normalized);
  }

  Future<void> createFolder(String accountId, String path) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.createFolder(accountId, path);
    final client = _requireClient(accountId);
    await client.mkdir(path);
  }

  Future<void> deletePath(String accountId, String path) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.deletePath(accountId, path);
    final client = _requireClient(accountId);
    await client.remove(path);
  }

  /// 复制到另一个路径（WebDAV COPY）。文件夹会被整棵复制。
  Future<void> renamePath(
    String accountId,
    String oldPath,
    String newPath, {
    bool overwrite = false,
  }) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.renamePath(accountId, oldPath, newPath, overwrite: overwrite);
    final client = _requireClient(accountId);
    await client.rename(oldPath, newPath, overwrite);
  }

  Future<void> copyPath(String accountId, String oldPath, String newPath) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.copyPath(accountId, oldPath, newPath);
    final client = _requireClient(accountId);
    // Overwrite=false：目标已存在时让服务端报错（412 / 409），由上层先算好不冲突的名字。
    await client.copy(oldPath, newPath, false);
  }

  /// 移动（WebDAV MOVE）。语义等同重命名，但可以跨目录。
  Future<void> movePath(String accountId, String oldPath, String newPath) async {
    final cloud = _cloudOf(accountId);
    if (cloud != null) return cloud.movePath(accountId, oldPath, newPath);
    final client = _requireClient(accountId);
    await client.rename(oldPath, newPath, false);
  }

  /// Recursively collect **every** file under [folderPath] (directories are not
  /// returned, they are only walked).
  ///
  /// [onlyAudio] keeps the old audio-only behaviour for the cache path; the
  /// plain download path needs everything, because 「下载整个文件夹」 means all
  /// of it, not just the tracks.
  Future<List<WebDavItem>> collectFilesRecursive(
    String accountId,
    String folderPath, {
    FileTypeConfig? fileTypes,
    bool onlyAudio = false,
  }) async {
    final result = <WebDavItem>[];
    final queue = <String>[folderPath];
    while (queue.isNotEmpty) {
      final dir = queue.removeAt(0);
      final items =
          await listDirectory(accountId, dir, fileTypes: fileTypes);
      for (final item in items) {
        if (item.isDirectory) {
          queue.add(item.path);
        } else if (!onlyAudio || item.isAudio) {
          result.add(item);
        }
      }
    }
    return result;
  }

  /// 分流缝：云盘账号返回 [CloudDriveService]，WebDAV 账号返回 null。
  CloudDriveService? _cloudOf(String? accountId) {
    final cd = _cloudDrive;
    if (cd == null || accountId == null) return null;
    return cd.handles(accountId) ? cd : null;
  }

  webdav.Client _requireClient(String accountId) {
    final conn = _conns[accountId];
    if (conn == null) {
      throw UnknownWebDavAccountException(accountId);
    }
    return conn.client;
  }
}

/// Thrown when an operation targets an account that is no longer configured.
///
/// Distinct from a WebDAV 404: it means the *server* is missing (deleted
/// account), so the UI can say "来源网盘已移除" instead of showing a confusing
/// "file not found" from whatever account happened to be selected.
class UnknownWebDavAccountException implements Exception {
  const UnknownWebDavAccountException(this.accountId);

  final String accountId;

  @override
  String toString() => '来源网盘已移除或未配置（$accountId）';
}

/// Cancel token for in-flight downloads (dio).
typedef DownloadCancelToken = CancelToken;

/// One configured WebDAV account: its client plus the credentials needed to
/// build a streaming URL / Basic auth header for it.
///
/// Kept per account because the same file can live on several servers and the
/// music library must be able to reach **its own** source account regardless of
/// which account the network library is currently browsing.
class _WebDavConn {
  const _WebDavConn({
    required this.accountId,
    required this.url,
    required this.username,
    required this.password,
    required this.client,
  });

  final String accountId;
  final String url;
  final String username;
  final String password;
  final webdav.Client client;
}
