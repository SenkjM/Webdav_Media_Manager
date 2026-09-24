import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../cloud_driver.dart';

/// crypt 的本地流桥（99 §7.5）。
///
/// media_kit / ffmpeg 只认 URL 或本地路径，不认 Dart 的字节流，所以把
/// [CloudDriver.openContentRange] 包成一个**只监听回环地址**的 HTTP 端点：
/// 播放器发 Range 请求，桥按 rclone 的块边界精确解密并回 206。
///
/// * token 一次性映射 (accountId, path)，URL 里不含账号凭证，也不接受写请求；
/// * 同一路径复用同一 token，重复播放不会积累条目；
/// * 空闲 [idleTimeout] 后自动关服务器（播放中会被请求不断刷新）。
class CryptStreamBridge {
  CryptStreamBridge(
    this._driverFor, {
    this.idleTimeout = const Duration(minutes: 10),
  });

  final CloudDriver Function(String accountId) _driverFor;
  final Duration idleTimeout;

  final Map<String, _BridgeEntry> _byKey = <String, _BridgeEntry>{};
  final Map<String, _BridgeEntry> _byToken = <String, _BridgeEntry>{};
  final Random _random = Random.secure();

  HttpServer? _server;
  Timer? _idle;

  /// 把 [remotePath]（解密后 [size] 字节）暴露成一个可播放 URL。
  /// [name] 是解密后的文件名：按扩展名给 ffmpeg 一个像样的 Content-Type，
  /// 免得它把「未知二进制」当成不可播放的流。
  Future<Uri> expose({
    required String accountId,
    required String remotePath,
    required int size,
    String? name,
  }) async {
    final server = await _ensureServer();
    final key = '$accountId\u0000$remotePath';
    var entry = _byKey[key];
    if (entry == null || entry.size != size) {
      final old = _byKey[key];
      if (old != null) _byToken.remove(old.token);
      entry = _BridgeEntry(
        token: _newToken(),
        accountId: accountId,
        remotePath: remotePath,
        size: size,
        contentType: _contentTypeFor(name),
      );
      _byKey[key] = entry;
      _byToken[entry.token] = entry;
    }
    _touch();
    return Uri.parse('http://127.0.0.1:${server.port}/s/${entry.token}');
  }

  /// 关闭服务器并丢弃全部 token（服务销毁时）。
  Future<void> dispose() async {
    _idle?.cancel();
    _idle = null;
    _byKey.clear();
    _byToken.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle, onError: (_) {});
    _server = server;
    _touch();
    return server;
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(idleTimeout, dispose);
  }

  String _newToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _handle(HttpRequest request) async {
    _touch();
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final entry = segments.length == 2 && segments.first == 's'
          ? _byToken[segments[1]]
          : null;
      if (entry == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType.parse(entry.contentType);
      if (request.method == 'HEAD') {
        response.statusCode = HttpStatus.ok;
        response.headers.contentLength = entry.size;
        await response.close();
        return;
      }
      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        entry.size,
      );
      final driver = _driverFor(entry.accountId);
      if (range == null) {
        response.statusCode = HttpStatus.ok;
        response.headers.contentLength = entry.size;
        await response.addStream(
          driver.openContentRange(entry.remotePath, 0, entry.size - 1),
        );
      } else {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.$1}-${range.$2}/${entry.size}',
        );
        response.headers.contentLength = range.$2 - range.$1 + 1;
        await response.addStream(
          driver.openContentRange(entry.remotePath, range.$1, range.$2),
        );
      }
      await response.close();
    } catch (_) {
      // 响应头可能已经发出，这时只能断开连接，让播放器自己重试。
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// 按扩展名猜媒体类型（猜不中就 application/octet-stream）。
  String _contentTypeFor(String? name) {
    final dot = name?.lastIndexOf('.') ?? -1;
    final ext = dot < 0 ? '' : name!.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'ts':
        return 'video/mp2t';
      case 'mp3':
        return 'audio/mpeg';
      case 'flac':
        return 'audio/flac';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }

  /// `bytes=a-b` / `bytes=a-` / `bytes=-n`，越界按 HTTP 语义裁剪。
  /// 无法解析或区间无效时返回 null —— 调用方按 200 回整份内容。
  (int, int)? _parseRange(String? value, int size) {
    if (value == null || size <= 0) return null;
    final spec = value.trim();
    if (!spec.startsWith('bytes=')) return null;
    final first = spec.substring(6).split(',').first.trim();
    final dash = first.indexOf('-');
    if (dash < 0) return null;
    final startRaw = first.substring(0, dash).trim();
    final endRaw = first.substring(dash + 1).trim();
    var start = startRaw.isEmpty ? -1 : int.tryParse(startRaw) ?? -1;
    var end = endRaw.isEmpty ? -1 : int.tryParse(endRaw) ?? -1;
    if (start < 0 && end < 0) return null;
    if (start < 0) {
      start = size - end;
      end = size - 1;
    } else if (end < 0 || end >= size) {
      end = size - 1;
    }
    if (start < 0 || start >= size || start > end) return null;
    return (start, end);
  }
}

class _BridgeEntry {
  _BridgeEntry({
    required this.token,
    required this.accountId,
    required this.remotePath,
    required this.size,
    required this.contentType,
  });

  final String token;
  final String accountId;
  final String remotePath;
  final int size;
  final String contentType;
}
