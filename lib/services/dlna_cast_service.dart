import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../screens/video_player_screen.dart' show VideoQueueSeed;
import 'dlna_queue_controller.dart';
import 'rust_proxy_stream_bridge.dart';
import 'webdav_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// 数据模型
// ──────────────────────────────────────────────────────────────────────────────

/// DLNA 渲染器（DMR 设备，如电视、投影仪、音箱）。
class DlnaRenderer {
  const DlnaRenderer({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.controlUrl,
    required this.connMgrControlUrl,
    required this.host,
  });

  /// 设备唯一标识（SSDP USN 字段）。
  final String usn;

  /// 用户可读名称（来自 description.xml 的 friendlyName 元素）。
  final String friendlyName;

  /// 设备描述 XML 的完整 URL。
  final String location;

  /// AVTransport 服务的 SOAP 控制 URL（绝对 URL）。
  final String controlUrl;

  /// ConnectionManager 服务的 SOAP 控制 URL（绝对 URL）。
  final String connMgrControlUrl;

  /// 渲染器 IP 地址。
  final String host;

  @override
  bool operator ==(Object other) =>
      other is DlnaRenderer && other.usn == usn;

  @override
  int get hashCode => usn.hashCode;
}

/// 兼容模式转码选项，默认全部关闭。
class DlnaTranscodeSettings {
  const DlnaTranscodeSettings({
    this.remuxContainer = false,
    this.transcodeVideo = false,
    this.transcodeAudio = false,
  });

  /// 容器重封装：MKV/AVI 等→MP4，不重新编码，CPU 开销极低。
  final bool remuxContainer;

  /// 视频流转码：任意→H.264。CPU 开销高。
  final bool transcodeVideo;

  /// 音频流转码：任意→AAC。CPU 开销中等。
  final bool transcodeAudio;

  bool get anyEnabled => remuxContainer || transcodeVideo || transcodeAudio;

  DlnaTranscodeSettings copyWith({
    bool? remuxContainer,
    bool? transcodeVideo,
    bool? transcodeAudio,
  }) => DlnaTranscodeSettings(
    remuxContainer: remuxContainer ?? this.remuxContainer,
    transcodeVideo: transcodeVideo ?? this.transcodeVideo,
    transcodeAudio: transcodeAudio ?? this.transcodeAudio,
  );
}

/// 文件兼容性提示（按扩展名快速判断，不运行 ffprobe）。
class DlnaCompatibilityHint {
  const DlnaCompatibilityHint({
    this.likelyNeedsRemux = false,
    this.likelyNeedsVideoTranscode = false,
    this.likelyNeedsAudioTranscode = false,
  });

  final bool likelyNeedsRemux;
  final bool likelyNeedsVideoTranscode;
  final bool likelyNeedsAudioTranscode;

  bool get anyLikely =>
      likelyNeedsRemux || likelyNeedsVideoTranscode || likelyNeedsAudioTranscode;
}

enum DlnaCastState { idle, discovering, casting, error }
enum DlnaPlaybackState { playing, paused, buffering, stopped }

// ──────────────────────────────────────────────────────────────────────────────
// DlnaCastService
// ──────────────────────────────────────────────────────────────────────────────

/// DLNA 投屏核心服务。
///
/// 完全独立于本地播放器（media_kit / AudioPlayerService / VideoPlaybackService），
/// 通过 WebDavService 统一访问媒体流，通过 LocalStreamBridge 建立局域网代理。
///
/// 生命周期：
/// 1. 设备选择界面调用 [startDiscovery] → [stopDiscovery]
/// 2. [startCast] 建立投屏会话
/// 3. [stop] 结束会话 → state 回到 idle
class DlnaCastService extends ChangeNotifier {
  DlnaCastService({required WebDavService webDav}) : _webDav = webDav;

  final WebDavService _webDav;

  // --- 状态 ---
  DlnaCastState _state = DlnaCastState.idle;
  DlnaPlaybackState _playbackState = DlnaPlaybackState.stopped;
  DlnaRenderer? _renderer;
  final List<DlnaRenderer> _discovered = [];
  DlnaQueueController? _queue;
  WebDavItem? _currentItem;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _error;
  DlnaTranscodeSettings _transcodeSettings = const DlnaTranscodeSettings();
  DlnaCompatibilityHint? _compatHint;

  DlnaCastState get state => _state;
  DlnaPlaybackState get playbackState => _playbackState;
  DlnaRenderer? get renderer => _renderer;
  List<DlnaRenderer> get discovered => List.unmodifiable(_discovered);
  DlnaQueueController? get queue => _queue;
  WebDavItem? get currentItem => _currentItem;
  Duration get position => _position;
  Duration? get duration => _duration;
  String? get error => _error;
  DlnaTranscodeSettings get transcodeSettings => _transcodeSettings;
  DlnaCompatibilityHint? get compatibilityHint => _compatHint;

  /// 系统 FFmpeg 是否可用（null = 尚未检测，false = 不可用，true = 可用）。
  bool? _ffmpegAvailable;
  bool get ffmpegAvailable => _ffmpegAvailable ?? false;

  // --- 内部 ---
  RawDatagramSocket? _ssdpSocket;
  Timer? _discoveryTimeout;
  /// Token for the active Rust proxy stream registration. Cleared in
  /// [_cleanupSession]. null when no cast session is active.
  String? _currentStreamToken;
  String? _localIp;
  Timer? _pollTimer;

  /// 创建一个禁用连接复用的短生命周期 HttpClient。
  ///
  /// UPnP/DLNA 渲染器（如 SmartShare）通常不支持 HTTP keep-alive，
  /// 每次响应后即关闭 TCP 连接。若复用旧连接则 Dart 报
  /// "Connection closed before full header was received"。
  /// 每次 SOAP 调用独立创建 + 销毁 HttpClient 可彻底规避此问题。
  HttpClient _newHttpClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..maxConnectionsPerHost = 1;

  // ──────────────────────────────────────────────────────────────────────────
  // SSDP 发现
  // ──────────────────────────────────────────────────────────────────────────

  /// 开始 SSDP M-SEARCH 发现，4 秒后自动停止。
  Future<void> startDiscovery() async {
    _discovered.clear();
    _state = DlnaCastState.discovering;
    notifyListeners();

    try {
      _ssdpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      _ssdpSocket!.multicastHops = 4;
      _ssdpSocket!.listen(_onSsdpDatagram, onError: (_) {});

      // 发送 M-SEARCH 组播
      const msearch = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';
      final data = utf8.encode(msearch);
      final multicast = InternetAddress('239.255.255.250');
      _ssdpSocket!.send(data, multicast, 1900);
      // 发第二次提高发现率
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _ssdpSocket!.send(data, multicast, 1900);

      _discoveryTimeout = Timer(const Duration(seconds: 4), stopDiscovery);
    } catch (e) {
      _state = DlnaCastState.idle;
      notifyListeners();
    }
  }

  void stopDiscovery() {
    _discoveryTimeout?.cancel();
    _discoveryTimeout = null;
    _ssdpSocket?.close();
    _ssdpSocket = null;
    if (_state == DlnaCastState.discovering) {
      _state = DlnaCastState.idle;
      notifyListeners();
    }
  }

  void _onSsdpDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _ssdpSocket?.receive();
    if (datagram == null) return;
    final msg = utf8.decode(datagram.data, allowMalformed: true);
    if (!msg.contains('200 OK') && !msg.contains('ssdp:alive')) return;

    // 提取 LOCATION header
    final locationMatch = RegExp(
      r'LOCATION:\s*(\S+)',
      caseSensitive: false,
    ).firstMatch(msg);
    final location = locationMatch?.group(1);
    if (location == null || location.isEmpty) return;

    // 异步拉取设备描述，不阻塞 SSDP 监听
    unawaited(_fetchDescription(location));
  }

  Future<void> _fetchDescription(String location) async {
    final client = _newHttpClient();
    try {
      final uri = Uri.parse(location);
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return;
      final body = await resp.transform(utf8.decoder).join();

      final friendlyName = _xmlText(body, 'friendlyName') ?? uri.host;
      final controlPath = _avTransportControlUrl(body, location);
      if (controlPath == null) return; // 不是 MediaRenderer

      final connMgrPath = _connMgrControlUrl(body, location) ?? '';
      final usn = _xmlText(body, 'UDN') ?? location;
      final renderer = DlnaRenderer(
        usn: usn,
        friendlyName: friendlyName,
        location: location,
        controlUrl: controlPath,
        connMgrControlUrl: connMgrPath,
        host: uri.host,
      );

      if (!_discovered.any((r) => r.usn == renderer.usn)) {
        _discovered.add(renderer);
        notifyListeners();
      }
    } catch (_) {
      // 单台设备解析失败不影响其他设备
    } finally {
      client.close(force: true);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 投屏控制
  // ──────────────────────────────────────────────────────────────────────────

  /// 开始投屏到指定渲染器。
  ///
  /// [seed] 来自视频播放器（含队列信息）；[singleItem] 来自网络库单文件。
  Future<void> startCast({
    required DlnaRenderer renderer,
    VideoQueueSeed? seed,
    WebDavItem? singleItem,
    String? accountId,
  }) async {
    assert(seed != null || (singleItem != null && accountId != null));

    // 清理旧会话
    await _cleanupSession();

    _renderer = renderer;
    _state = DlnaCastState.casting;
    _playbackState = DlnaPlaybackState.buffering;
    _error = null;
    notifyListeners();

    try {
      // 检测系统 FFmpeg 可用性（仅首次）
      _ffmpegAvailable ??= await _checkFfmpeg();
      // 选择与 DMR 同子网的本机 IP，确保 DMR 可路由到代理地址
      _localIp = await _getLocalIpFor(renderer.host);
      debugPrint('[DLNA] localIp=$_localIp rendererHost=${renderer.host}');
      // R12: stream bridge replaced by RustProxyStreamBridge; no Dart HttpServer.

      // 建立队列
      final effAccountId = accountId ?? seed!.accountId;
      final initial = singleItem ?? seed!.current;
      final siblings = seed?.siblings ?? [];
      _queue = DlnaQueueController(
        webDav: _webDav,
        accountId: effAccountId,
        rootPath: seed?.folderPath ?? _parentPath(initial.path),
        seed: siblings.isNotEmpty ? siblings : [initial],
        initialRemotePath: initial.path,
      );
      _queue!.startScan();

      // 检测兼容性（按扩展名）
      _compatHint = _detectHint(initial.name);

      // 开始投屏第一个文件
      await _castItem(initial, effAccountId);
    } catch (e, stack) {
      debugPrint('[DLNA] startCast/castItem error: $e\n$stack');
      _state = DlnaCastState.error;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _castItem(WebDavItem item, String accountId) async {
    _currentItem = item;
    _position = Duration.zero;
    _duration = null;
    _playbackState = DlnaPlaybackState.buffering;
    notifyListeners();

    // 解析流源（WebDAV Basic Auth 或云盘直链）
    final source = await _webDav.resolveStreamSource(
      remotePath: item.path,
      name: item.name,
      accountId: accountId,
    );
    if (source == null) throw Exception('无法解析流源: ${item.name}');

    // 生成代理 URL（R12：经 Rust 代理；LAN cast 受 loopback-only 限制）
    final (:uri, :token) = await RustProxyStreamBridge.expose(
      size: item.size ?? 0,
      name: item.name,
      accountId: accountId,
      remotePath: item.path,
      readRange: (start, end) async {
        final bytes = <int>[];
        await for (final chunk in _proxyRange(source, start, end)) {
          bytes.addAll(chunk);
        }
        return bytes;
      },
      lanHost: _localIp,
    );
    _currentStreamToken = token;

    final proxyUrl = uri.toString();
    final mimeType = _mimeFor(item.name);

    // 查询 DMR 支持的 SinkProtocolInfo，协商 protocolInfo
    final sinkProtocols = await _getSinkProtocolInfo(
      _renderer!.connMgrControlUrl,
    );

    // 检测 DMR 是否支持视频
    final supportsVideo = sinkProtocols.any((p) {
      final parts = p.split(':');
      return parts.length >= 3 && parts[2].startsWith('video/');
    });
    if (!supportsVideo) {
      throw Exception(
        '${_renderer!.friendlyName} 不支持视频播放'
        '（SinkProtocolInfo 无 video/* 条目）',
      );
    }

    final protocolInfo = _negotiateProtocolInfo(mimeType, sinkProtocols);
    debugPrint('[DLNA] castItem: proxyUrl=$proxyUrl mimeType=$mimeType protocolInfo=$protocolInfo');

    // SetAVTransportURI
    await _soap(
      _renderer!.controlUrl,
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>${_xmlEscape(proxyUrl)}</CurrentURI>'
      '<CurrentURIMetaData>${_xmlEscape(_didlLite(item.name, proxyUrl, protocolInfo))}</CurrentURIMetaData>',
    );

    // Play
    await _soap(
      _renderer!.controlUrl,
      'Play',
      '<InstanceID>0</InstanceID><Speed>1</Speed>',
    );

    _playbackState = DlnaPlaybackState.playing;
    notifyListeners();

    // 启动状态轮询
    _startPolling(accountId);
  }

  /// 代理 Range 请求：透明转发或转码。
  Stream<List<int>> _proxyRange(
    WebDavStreamSource source,
    int start,
    int end,
  ) {
    if (_transcodeSettings.anyEnabled && _ffmpegAvailable == true) {
      // 转码模式：忽略 Range（流式输出不支持随机访问），返回 ffmpeg stdout
      return _transcodeStream(source);
    }
    // 透明转发：通过 dart:io HttpClient 带认证转发
    return _forwardRange(source, start, end);
  }

  Stream<List<int>> _forwardRange(
    WebDavStreamSource source,
    int start,
    int end,
  ) async* {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(source.uri));
      source.headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Range', 'bytes=$start-$end');
      final resp = await req.close();
      await for (final chunk in resp) {
        yield chunk;
      }
    } finally {
      client.close(force: true);
    }
  }

  Stream<List<int>> _transcodeStream(WebDavStreamSource source) async* {
    final settings = _transcodeSettings;
    final args = <String>[
      '-loglevel', 'error',
    ];
    // 注入认证 header 给 ffmpeg（必须在 -i 之前）
    if (source.headers.isNotEmpty) {
      // ffmpeg 用单个 -headers 接受 "\r\n" 分隔的多行 header
      final headerBlock = source.headers.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\r\n');
      args.addAll(['-headers', '$headerBlock\r\n']);
    }
    args.addAll(['-i', source.uri]);
    // 视频编码
    if (settings.transcodeVideo) {
      args.addAll(['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23']);
    } else {
      args.addAll(['-c:v', 'copy']);
    }
    // 音频编码
    if (settings.transcodeAudio) {
      args.addAll(['-c:a', 'aac', '-b:a', '192k']);
    } else {
      args.addAll(['-c:a', 'copy']);
    }
    // 输出容器（MP4 流式）
    args.addAll([
      '-f', 'mp4',
      '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
      'pipe:1',
    ]);

    final process = await Process.start('ffmpeg', args);
    // stderr 静默丢弃（避免管道阻塞）
    unawaited(process.stderr.drain<List<int>>());
    await for (final chunk in process.stdout) {
      yield chunk;
    }
  }

  Future<void> stop() async {
    if (_state == DlnaCastState.idle) return;
    try {
      await _soap(
        _renderer!.controlUrl,
        'Stop',
        '<InstanceID>0</InstanceID>',
      );
    } catch (_) {}
    await _cleanupSession();
    _state = DlnaCastState.idle;
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_renderer == null) return;
    try {
      if (_playbackState == DlnaPlaybackState.playing) {
        await _soap(
          _renderer!.controlUrl,
          'Pause',
          '<InstanceID>0</InstanceID>',
        );
        _playbackState = DlnaPlaybackState.paused;
      } else {
        await _soap(
          _renderer!.controlUrl,
          'Play',
          '<InstanceID>0</InstanceID><Speed>1</Speed>',
        );
        _playbackState = DlnaPlaybackState.playing;
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> seekTo(Duration pos) async {
    if (_renderer == null) return;
    final hms = _formatHms(pos);
    try {
      await _soap(
        _renderer!.controlUrl,
        'Seek',
        '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>$hms</Target>',
      );
      _position = pos;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> playNext() async {
    final q = _queue;
    if (q == null || !q.hasNext) return;
    final next = q.next!;
    q.selectRemotePath(next.path);
    await _castItem(next, q.accountId);
  }

  Future<void> playPrevious() async {
    final q = _queue;
    if (q == null || !q.hasPrevious) return;
    final prev = q.previous!;
    q.selectRemotePath(prev.path);
    await _castItem(prev, q.accountId);
  }

  /// 跳转到队列中指定下标的文件。
  Future<void> playTrack(int index) async {
    final q = _queue;
    if (q == null || index < 0 || index >= q.length) return;
    final item = q.tracks[index];
    q.selectRemotePath(item.path);
    await _castItem(item, q.accountId);
  }

  /// 更新本次会话的转码设置（立即生效，下次代理请求时使用新设置）。
  Future<void> setTranscodeSettings(DlnaTranscodeSettings settings) async {
    _transcodeSettings = settings;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 状态轮询
  // ──────────────────────────────────────────────────────────────────────────

  void _startPolling(String accountId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _poll(accountId);
    });
  }

  Future<void> _poll(String accountId) async {
    if (_renderer == null || _state != DlnaCastState.casting) return;
    try {
      // GetPositionInfo
      final posResp = await _soap(
        _renderer!.controlUrl,
        'GetPositionInfo',
        '<InstanceID>0</InstanceID>',
      );
      if (posResp != null) {
        final relTime = _xmlText(posResp, 'RelTime');
        final trackDuration = _xmlText(posResp, 'TrackDuration');
        if (relTime != null) _position = _parseDuration(relTime);
        if (trackDuration != null && trackDuration != 'NOT_IMPLEMENTED') {
          _duration = _parseDuration(trackDuration);
        }
      }

      // GetTransportInfo（每 5 秒一次）
      if (DateTime.now().second % 5 == 0) {
        final transResp = await _soap(
          _renderer!.controlUrl,
          'GetTransportInfo',
          '<InstanceID>0</InstanceID>',
        );
        if (transResp != null) {
          final transportState = _xmlText(transResp, 'CurrentTransportState');
          if (transportState == 'STOPPED' &&
              _playbackState == DlnaPlaybackState.playing) {
            // DMR 自然播放结束，触发下一首
            _playbackState = DlnaPlaybackState.stopped;
            notifyListeners();
            if (_queue?.hasNext == true) {
              await playNext();
            }
            return;
          } else if (transportState == 'PLAYING') {
            if (_playbackState != DlnaPlaybackState.playing) {
              _playbackState = DlnaPlaybackState.playing;
            }
          } else if (transportState == 'PAUSED_PLAYBACK') {
            if (_playbackState != DlnaPlaybackState.paused) {
              _playbackState = DlnaPlaybackState.paused;
            }
          }
        }
      }
      notifyListeners();
    } catch (_) {
      // 轮询失败不崩溃，等下次重试
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SOAP
  // ──────────────────────────────────────────────────────────────────────────

  Future<String?> _soap(
    String controlUrl,
    String action,
    String bodyContent,
  ) async {
    final envelope =
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
        '$bodyContent'
        '</u:$action>'
        '</s:Body>'
        '</s:Envelope>';

    debugPrint('[DLNA] SOAP → $action @ $controlUrl');

    final uri = Uri.parse(controlUrl);
    final client = _newHttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set(
        'SOAPACTION',
        '"urn:schemas-upnp-org:service:AVTransport:1#$action"',
      );
      final encoded = utf8.encode(envelope);
      req.headers.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 300) {
        // 完整日志：状态码 + 响应 body（含 UPnP 错误码）+ 发送的 envelope
        debugPrint(
          '[DLNA] SOAP $action FAILED\n'
          '  controlUrl: $controlUrl\n'
          '  status: ${resp.statusCode}\n'
          '  response: $body\n'
          '  envelope: $envelope',
        );
        throw Exception(
          'SOAP $action 失败 (HTTP ${resp.statusCode})\n'
          'controlUrl: $controlUrl\n'
          'response: $body',
        );
      }
      debugPrint('[DLNA] SOAP ← $action OK (${resp.statusCode})');
      return body;
    } on SocketException catch (e) {
      debugPrint('[DLNA] SOAP $action 网络错误: $e\n  controlUrl: $controlUrl');
      rethrow;
    } catch (e) {
      debugPrint('[DLNA] SOAP $action 异常: $e\n  controlUrl: $controlUrl');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 工具方法
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _cleanupSession() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _queue?.dispose();
    _queue = null;
    if (_currentStreamToken != null) {
      RustProxyStreamBridge.unregister(_currentStreamToken!);
      _currentStreamToken = null;
    }
    _renderer = null;
    _currentItem = null;
    _position = Duration.zero;
    _duration = null;
    _playbackState = DlnaPlaybackState.stopped;
    _compatHint = null;
  }

  /// 检测系统 ffmpeg 是否可用（运行 ffmpeg -version）。
  /// 结果缓存在 [_ffmpegAvailable]，不重复检测。
  Future<bool> _checkFfmpeg() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 选择与 [targetIp]（DMR IP）同子网的本机 IPv4 地址。
  ///
  /// 优先返回与 targetIp 前 3 段（/24）相同的网卡 IP；
  /// 找不到同子网地址时 fallback 到第一个私有 IP；
  /// 再找不到返回 loopback。
  Future<String> _getLocalIpFor(String targetIp) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    final privateIps = <String>[];
    final targetParts = targetIp.split('.');
    // 取前三段作为 /24 前缀，e.g. "192.168.0"
    final prefix = targetParts.length == 4
        ? targetParts.take(3).join('.')
        : null;

    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final a = addr.address;
        debugPrint('[DLNA] iface=${iface.name} addr=$a');
        if (!_isPrivateIp(a)) continue;
        privateIps.add(a);
        // 优先：与 DMR 同 /24 子网
        if (prefix != null && a.startsWith('$prefix.')) {
          debugPrint('[DLNA] selected local IP (same /24): $a');
          return a;
        }
      }
    }

    // Fallback：任意私有 IP
    final result = privateIps.isNotEmpty ? privateIps.first : '127.0.0.1';
    debugPrint('[DLNA] selected local IP (fallback): $result');
    return result;
  }

  bool _isPrivateIp(String ip) {
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        (ip.startsWith('172.') && _is172Private(ip));
  }

  bool _is172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 16 && second <= 31;
  }

  String _parentPath(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : '/';
  }

  /// 按扩展名快速判断兼容性问题（不运行 ffprobe）。
  DlnaCompatibilityHint _detectHint(String name) {
    final ext = _ext(name);
    const problematicContainers = {
      'mkv', 'avi', 'mov', 'ts', 'm2ts', 'flv',
      'rmvb', 'rm', 'wmv', 'asf', '3gp', 'webm',
    };
    const definitelyBadCodec = {'rmvb', 'rm', 'wmv', 'asf', 'flv'};
    return DlnaCompatibilityHint(
      likelyNeedsRemux: problematicContainers.contains(ext),
      likelyNeedsVideoTranscode: definitelyBadCodec.contains(ext),
      likelyNeedsAudioTranscode: definitelyBadCodec.contains(ext),
    );
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// 代理层 HTTP Content-Type（按真实文件格式，供浏览器 / 调试工具识别）。
  String _mimeFor(String name) {
    switch (_ext(name)) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'ts':
      case 'm2ts':
        return 'video/mp2t';
      default:
        return 'video/mp4';
    }
  }

  String _didlLite(String title, String url, String protocolInfo) {
    final escapedTitle = _xmlEscape(title);
    final escapedUrl = _xmlEscape(url);
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>$escapedTitle</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="${_xmlEscape(protocolInfo)}">'
        '$escapedUrl'
        '</res>'
        '</item>'
        '</DIDL-Lite>';
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 从 XML 字符串中提取第一个匹配标签的文本内容。
  /// 支持带属性的开标签，如 `<Sink xmlns:dt="..." dt:dt="string">content</Sink>`。
  String? _xmlText(String xml, String tag) {
    // 匹配 <tag> 或 <tag ...attrs...>，然后捕获内容直到 </tag>
    final m = RegExp('<$tag(?:\\s[^>]*)?>([^<]*)</$tag>').firstMatch(xml);
    return m?.group(1)?.trim();
  }

  /// 从 description.xml 解析 AVTransport controlURL（返回绝对 URL）。
  String? _avTransportControlUrl(String xml, String location) {
    // 找 AVTransport serviceType 所在的 service 块
    final serviceBlocks = RegExp(
      r'<service>(.*?)</service>',
      dotAll: true,
    ).allMatches(xml);
    for (final block in serviceBlocks) {
      final content = block.group(1) ?? '';
      if (content.contains('AVTransport')) {
        final control = _xmlText(content, 'controlURL');
        if (control == null) continue;
        // 拼成绝对 URL
        final base = Uri.parse(location);
        if (control.startsWith('http')) return control;
        return base.resolve(control).toString();
      }
    }
    return null;
  }

  /// 从 description.xml 解析 ConnectionManager controlURL（返回绝对 URL）。
  String? _connMgrControlUrl(String xml, String location) {
    final serviceBlocks = RegExp(
      r'<service>(.*?)</service>',
      dotAll: true,
    ).allMatches(xml);
    for (final block in serviceBlocks) {
      final content = block.group(1) ?? '';
      if (content.contains('ConnectionManager')) {
        final control = _xmlText(content, 'controlURL');
        if (control == null) continue;
        final base = Uri.parse(location);
        if (control.startsWith('http')) return control;
        return base.resolve(control).toString();
      }
    }
    return null;
  }

  /// 发送 ConnectionManager SOAP 请求。
  Future<String?> _soapConnMgr(
    String controlUrl,
    String action,
    String bodyContent,
  ) async {
    final envelope =
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">'
        '$bodyContent'
        '</u:$action>'
        '</s:Body>'
        '</s:Envelope>';

    debugPrint('[DLNA] ConnMgr SOAP → $action @ $controlUrl');
    final uri = Uri.parse(controlUrl);
    final client = _newHttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set(
        'SOAPACTION',
        '"urn:schemas-upnp-org:service:ConnectionManager:1#$action"',
      );
      final encoded = utf8.encode(envelope);
      req.headers.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 300) {
        debugPrint('[DLNA] ConnMgr SOAP $action failed: ${resp.statusCode}\n$body');
        return null;
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  /// 查询 DMR 的 ConnectionManager.GetProtocolInfo，
  /// 返回其支持的 sink protocolInfo 列表（逗号分隔拆开后的列表）。
  /// 失败时返回空列表。
  Future<List<String>> _getSinkProtocolInfo(String connMgrControlUrl) async {
    if (connMgrControlUrl.isEmpty) return [];
    try {
      final body = await _soapConnMgr(
        connMgrControlUrl,
        'GetProtocolInfo',
        '',
      );
      if (body == null) return [];
      debugPrint('[DLNA] GetProtocolInfo response: $body');
      final sink = _xmlText(body, 'Sink') ?? '';
      debugPrint('[DLNA] SinkProtocolInfo raw: "$sink"');
      return sink.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[DLNA] GetProtocolInfo failed: $e');
      return [];
    }
  }

  /// 从 [sinkProtocols] 中为 [mimeType] 协商最合适的 protocolInfo。
  ///
  /// 返回完整的四元组字符串，例如
  /// `http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_MP_HD_1080i_AAC`。
  /// 协商失败时返回 `http-get:*:$mimeType:DLNA.ORG_OP=01`。
  String _negotiateProtocolInfo(String mimeType, List<String> sinkProtocols) {
    // 精确匹配 contentFormat（第三字段）
    final exact = sinkProtocols.where((p) {
      final parts = p.split(':');
      return parts.length >= 3 && parts[2] == mimeType;
    }).toList();
    if (exact.isNotEmpty) {
      debugPrint('[DLNA] protocolInfo exact match: ${exact.first}');
      return exact.first;
    }

    // 主类型匹配（如 mimeType=video/x-matroska，匹配 video/*）
    final mainType = mimeType.split('/').first;
    final wildcard = sinkProtocols.where((p) {
      final parts = p.split(':');
      if (parts.length < 3) return false;
      final cf = parts[2];
      return cf == '$mainType/*' || cf == '*/*';
    }).toList();
    if (wildcard.isNotEmpty) {
      // 用匹配的协议但替换 contentFormat 为实际 MIME
      final base = wildcard.first.split(':');
      final result = '${base[0]}:${base[1]}:$mimeType:${base.length > 3 ? base.sublist(3).join(':') : 'DLNA.ORG_OP=01'}';
      debugPrint('[DLNA] protocolInfo wildcard match: $result');
      return result;
    }

    // 协商失败：用基本格式
    final fallback = 'http-get:*:$mimeType:DLNA.ORG_OP=01';
    debugPrint('[DLNA] protocolInfo no match, using fallback: $fallback');
    return fallback;
  }

  Duration _parseDuration(String hms) {
    // 格式：HH:MM:SS 或 HH:MM:SS.mmm
    try {
      final parts = hms.split(':');
      if (parts.length != 3) return Duration.zero;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final sParts = parts[2].split('.');
      final s = int.parse(sParts[0]);
      final ms = sParts.length > 1
          ? int.parse(sParts[1].padRight(3, '0').substring(0, 3))
          : 0;
      return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
    } catch (_) {
      return Duration.zero;
    }
  }

  String _formatHms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Future<void> dispose() async {
    stopDiscovery();
    await _cleanupSession();
    super.dispose();
  }
}
