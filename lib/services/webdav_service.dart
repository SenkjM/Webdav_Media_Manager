import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../utils/audio_extensions.dart';

/// Thin WebDAV client wrapper.
///
/// Music playback NEVER uses remote streams — only [downloadToFile] /
/// [readAsBytes] for cache population. Video playback *does* stream: it uses
/// [buildStreamSource] to hand media_kit a direct URL + Basic auth headers.
class WebDavService extends ChangeNotifier {
  webdav.Client? _client;
  String? _baseUrl;
  String? _accountId;
  String? _username;
  String? _password;
  String? _lastError;

  bool get isConnected => _client != null;
  String? get lastError => _lastError;
  String? get baseUrl => _baseUrl;
  String? get accountId => _accountId;

  void configure({
    required String accountId,
    required String url,
    required String username,
    required String password,
  }) {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    _accountId = accountId;
    _baseUrl = normalized;
    _username = username;
    _password = password;
    _client = webdav.newClient(
      normalized,
      user: username,
      password: password,
      debug: false,
    );
    _client!.setHeaders({
      'accept-charset': 'utf-8',
      'user-agent': 'WEBDAV-music-player/1.0',
    });
    _client!.setConnectTimeout(15000);
    _client!.setSendTimeout(30000);
    _client!.setReceiveTimeout(120000);
    _lastError = null;
    notifyListeners();
  }

  void disconnect() {
    _client = null;
    _baseUrl = null;
    _accountId = null;
    _username = null;
    _password = null;
    notifyListeners();
  }

  /// Build a streaming source for media_kit. Returns null when disconnected.
  ///
  /// Uses HTTP Basic auth (the same credentials the WebDAV client uses); some
  /// servers also accept a bearer/token flow, but Basic is what
  /// `webdav_client`'s `BasicAuth` sends, so we mirror it for parity.
  WebDavStreamSource? buildStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
  }) {
    final base = _baseUrl;
    if (base == null) return null;
    final uri = '$base${encodeWebDavPath(remotePath)}';
    final headers = <String, String>{
      'User-Agent': 'WEBDAV-music-player/1.0',
    };
    final user = _username ?? '';
    final pass = _password ?? '';
    if (user.isNotEmpty || pass.isNotEmpty) {
      final token = base64Encode(utf8.encode('$user:$pass'));
      headers['Authorization'] = 'Basic $token';
    }
    return WebDavStreamSource(
      uri: uri,
      headers: headers,
      name: name,
      remotePath: remotePath,
      accountId: accountId,
    );
  }

  /// PROPFIND / ping to verify credentials.
  Future<bool> testConnection() async {
    final client = _client;
    if (client == null) {
      _lastError = '未配置 WebDAV';
      notifyListeners();
      return false;
    }
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

  Future<List<WebDavItem>> listDirectory(
    String path, {
    FileTypeConfig? fileTypes,
  }) async {
    final client = _requireClient();
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

  /// Download remote file into [localFile]. Never used for streaming playback.
  Future<void> downloadToFile(
    String remotePath,
    File localFile, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final client = _requireClient();
    await localFile.parent.create(recursive: true);
    await client.read2File(
      remotePath,
      localFile.path,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> readAsBytes(String remotePath) async {
    final client = _requireClient();
    final data = await client.read(remotePath);
    return Uint8List.fromList(data);
  }


  /// Upload bytes to remote path (creates/overwrites file).
  Future<void> writeBytes(String remotePath, Uint8List data) async {
    final client = _requireClient();
    await client.write(remotePath, data);
  }

  /// Ensure directory exists (mkdirAll).
  Future<void> ensureDirectory(String path) async {
    final client = _requireClient();
    var normalized = path.trim();
    if (normalized.isEmpty) return;
    if (!normalized.endsWith('/')) normalized = '$normalized/';
    await client.mkdirAll(normalized);
  }

  Future<void> createFolder(String path) async {
    final client = _requireClient();
    await client.mkdir(path);
  }

  Future<void> deletePath(String path) async {
    final client = _requireClient();
    await client.remove(path);
  }

  Future<void> renamePath(String oldPath, String newPath,
      {bool overwrite = false}) async {
    final client = _requireClient();
    await client.rename(oldPath, newPath, overwrite);
  }

  /// Recursively collect audio file paths under [folderPath].
  Future<List<WebDavItem>> collectAudioRecursive(
    String folderPath, {
    FileTypeConfig? fileTypes,
  }) async {
    final result = <WebDavItem>[];
    final queue = <String>[folderPath];
    while (queue.isNotEmpty) {
      final dir = queue.removeAt(0);
      final items = await listDirectory(dir, fileTypes: fileTypes);
      for (final item in items) {
        if (item.isDirectory) {
          queue.add(item.path);
        } else if (item.isAudio) {
          result.add(item);
        }
      }
    }
    return result;
  }

  webdav.Client _requireClient() {
    final client = _client;
    if (client == null) throw StateError('WebDAV 未配置');
    return client;
  }
}

/// Cancel token for in-flight downloads (dio).
typedef DownloadCancelToken = CancelToken;
