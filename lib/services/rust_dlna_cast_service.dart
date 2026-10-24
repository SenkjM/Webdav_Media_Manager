import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../screens/video_player_screen.dart' show VideoQueueSeed;
import '../utils/directory_walk.dart';
import 'cache_service.dart';
import 'accounts_service.dart';
import 'rust_core_service.dart';
import 'rust_dmr_prefs_service.dart';
import 'webdav_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Models
// ──────────────────────────────────────────────────────────────────────────────

/// DLNA renderer (DMR device such as a smart TV, projector, or speaker).
class DlnaRenderer {
  const DlnaRenderer({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.controlUrl,
    required this.connMgrControlUrl,
    required this.host,
  });

  /// Device unique identifier (SSDP USN field).
  final String usn;

  /// User-visible name (from the description XML `friendlyName` element).
  final String friendlyName;

  /// Full URL to the device description XML.
  final String location;

  /// AVTransport service SOAP control URL (absolute URL).
  final String controlUrl;

  /// ConnectionManager service SOAP control URL (absolute URL).
  final String connMgrControlUrl;

  /// Renderer IP address.
  final String host;

  @override
  bool operator ==(Object other) => other is DlnaRenderer && other.usn == usn;

  @override
  int get hashCode => usn.hashCode;
}

/// Transcode / compat mode options for a cast session.
///
/// Maps directly to the `wdmm_proxy_register_hls` `mode_json` parameter.
/// [remuxContainer] → `direct_copy` mode; [transcodeVideo]/[transcodeAudio]
/// → `compat` mode with libx264 / aac codecs.
/// The UI enforces a mutex: you cannot enable remux AND transcode
/// simultaneously (direct_copy pipes the original mux, compat re-encodes).
class DlnaTranscodeSettings {
  const DlnaTranscodeSettings({
    this.remuxContainer = false,
    this.transcodeVideo = false,
    this.transcodeAudio = false,
  });

  /// Container remux: MKV/AVI/… → MP4, no re-encode. Low CPU.
  final bool remuxContainer;

  /// Video transcode to H.264 via libx264. High CPU.
  final bool transcodeVideo;

  /// Audio transcode to AAC. Medium CPU.
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

  /// Converts to the `mode_json` string expected by `wdmm_proxy_register_hls`.
  /// Returns null for the default `direct_copy` no-op mode.
  String? toHlsModeJson() {
    if (transcodeVideo || transcodeAudio) {
      return jsonEncode({
        'mode': 'compat',
        if (transcodeVideo) 'video_codec': 'libx264',
        if (transcodeAudio) 'audio_codec': 'aac',
      });
    }
    // remuxContainer = direct_copy in the proxy (re-mux into TS segments).
    return null; // proxy default
  }
}

/// Quick extension hint from filename — no ffprobe needed.
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
// Typed cast error
// ──────────────────────────────────────────────────────────────────────────────

/// Structured error codes for [RustDlnaCastService] failures.
///
/// The cast bar displays [userMessage] to the user and includes [techDetail]
/// in the "Copy all" dump so developers can diagnose without cluttering the UI.
enum DlnaCastErrorCode {
  /// File not in local cache — user must download it first.
  /// Blocker: `wdmm_proxy_register_stream` absent at SHA 4a37aa4
  /// (and absent in dirty WDMM-core-hls R12).
  notCached,

  /// Rust FFI library could not be loaded or the proxy did not start.
  proxyUnavailable,

  /// `wdmm_proxy_register_hls` returned an error or null.
  hlsRegisterFailed,

  /// The renderer's SinkProtocolInfo contains no `video/*` entry.
  rendererNoVideo,

  /// AVTransport SOAP call failed (HTTP error, network, or UPnP fault).
  soapFailed,

  /// Unexpected / unclassified failure.
  unknown,
}

/// A typed cast error that carries a user-facing Chinese [userMessage] and
/// a developer-facing [techDetail] for the "Copy all" action.
class DlnaCastError implements Exception {
  const DlnaCastError({
    required this.code,
    required this.userMessage,
    required this.techDetail,
  });

  final DlnaCastErrorCode code;

  /// Short, friendly Chinese message shown in the cast bar.
  final String userMessage;

  /// Technical detail included in "Copy all" but kept out of the main UI.
  final String techDetail;

  /// Full text for clipboard / log: user message + tech detail.
  String get fullText => '$userMessage\n[技术详情] $techDetail';

  @override
  String toString() => fullText;
}

// ──────────────────────────────────────────────────────────────────────────────
// Inline queue (replaces deleted DlnaQueueController)
// ──────────────────────────────────────────────────────────────────────────────

/// Progressive playlist queue for a DLNA cast session.
///
/// Seeds from known siblings immediately; background-scans the folder
/// directory to fill in the rest. Mirrors [VideoQueueController] shape.
class _DlnaQueue {
  _DlnaQueue({
    required WebDavService webDav,
    required this.accountId,
    required this.rootPath,
    required List<WebDavItem> seed,
    required String initialRemotePath,
    FileTypeConfig? fileTypes,
  }) : _webDav = webDav,
       _fileTypes = fileTypes ?? FileTypeConfig() {
    _merge(seed);
    _currentRemotePath = _resolveCurrent(initialRemotePath);
  }

  final WebDavService _webDav;
  final FileTypeConfig _fileTypes;
  final String accountId;
  final String rootPath;

  final List<WebDavItem> _tracks = [];
  final Set<String> _knownPaths = {};
  String? _currentRemotePath;
  bool _scanning = false;
  bool _scanComplete = false;
  bool _cancelled = false;
  String? _scanError;
  int _discovered = 0;

  // Listener list (mirrors ChangeNotifier but lightweight).
  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback fn) => _listeners.add(fn);
  void removeListener(VoidCallback fn) => _listeners.remove(fn);
  void _notify() { for (final fn in List.of(_listeners)) fn(); }

  List<WebDavItem> get tracks => List.unmodifiable(_tracks);
  bool get scanning => _scanning;
  bool get scanComplete => _scanComplete;
  String? get scanError => _scanError;
  int get discovered => _discovered;
  String get currentRemotePath => _currentRemotePath ?? '';
  int get length => _tracks.length;
  int get index => _tracks.indexWhere((t) => t.path == _currentRemotePath);
  WebDavItem? get current { final i = index; return i >= 0 ? _tracks[i] : null; }
  bool get hasPrevious => index > 0;
  bool get hasNext { final i = index; return i >= 0 && i + 1 < _tracks.length; }
  WebDavItem? get next { final i = index; if (i < 0 || i + 1 >= _tracks.length) return null; return _tracks[i + 1]; }
  WebDavItem? get previous { final i = index; if (i <= 0) return null; return _tracks[i - 1]; }

  WebDavItem? selectIndex(int i) {
    if (i < 0 || i >= _tracks.length) return null;
    _currentRemotePath = _tracks[i].path;
    _notify();
    return _tracks[i];
  }

  WebDavItem? selectRemotePath(String remotePath) =>
      selectIndex(_tracks.indexWhere((t) => t.path == remotePath));

  void startScan() {
    if (_scanning || _scanComplete) return;
    _scanning = true;
    _notify();
    unawaited(_scan());
  }

  void cancel() { _cancelled = true; _scanning = false; }

  Future<void> _scan() async {
    final walker = DirectoryWalker(rootPath: rootPath, options: const WalkOptions());
    var failed = 0;
    try {
      while (!_cancelled) {
        final dir = walker.nextDirectory();
        if (dir == null) break;
        try {
          final items = await _webDav.listDirectory(accountId, dir, fileTypes: _fileTypes);
          final media = items.where((e) => e.category == FileCategory.video).toList();
          walker.acceptChildren(dir, items.where((e) => e.isDirectory).map((e) => e.path));
          if (media.isNotEmpty) _merge(media);
        } catch (e) {
          failed++;
          if (failed == 1) _scanError = e.toString();
        }
      }
    } finally {
      if (!_cancelled) {
        _scanning = false;
        _scanComplete = true;
        _notify();
      }
    }
  }

  void _merge(List<WebDavItem> items) {
    var added = 0;
    for (final item in items) {
      if (!_knownPaths.add(item.path)) continue;
      _tracks.add(item);
      added++;
    }
    if (added == 0) return;
    _tracks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _discovered += added;
    _notify();
  }

  String _resolveCurrent(String remotePath) {
    if (_knownPaths.contains(remotePath)) return remotePath;
    final name = remotePath.split('/').last;
    final item = WebDavItem(name: name, path: remotePath, isDirectory: false, category: FileCategory.video);
    _tracks.add(item);
    _knownPaths.add(remotePath);
    _tracks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return remotePath;
  }

  void dispose() { cancel(); _listeners.clear(); }
}

// ──────────────────────────────────────────────────────────────────────────────
// RustDlnaCastService
// ──────────────────────────────────────────────────────────────────────────────

/// DLNA cast service wired to Rust FFI.
///
/// ## What runs in Rust
/// - Stream proxy: `wdmm_proxy_start` + `wdmm_proxy_register_hls` (SHA 4a37aa4)
///   serves local/cached files as HLS over the LAN so a DMR can pull them.
///
/// ## What stays in Dart (no FFI equivalent yet)
/// - SSDP discovery: async UDP is non-blocking; the Rust `wdmm_dlna_discover_json`
///   call blocks for the whole timeout window and would freeze the UI.
/// - AVTransport SOAP control (play/pause/seek/stop/position): no FFI equivalent
///   yet. TODO(r12-dlna-transport-ffi): replace with Rust once exported.
/// - DIDL-Lite / protocolInfo negotiation: same.
///
/// ## Cast flow
/// 1. `startDiscovery()` → async SSDP M-SEARCH, fills [discovered].
/// 2. `startCast(renderer, ...)` →
///    a. Ensure Rust proxy is running (`wdmm_proxy_start`).
///    b. Resolve/locate the local cache file for the item.
///    c. `wdmm_proxy_register_hls` → HLS playlist URL on LAN.
///    d. `wdmm_dlna_cast` (SetAVTransportURI + Play via Rust SOAP).
///    e. Start Dart 2-second polling timer.
/// 3. Control (pause/seek/stop) via Dart SOAP.
/// 4. DMR prefs (transcode settings) persisted via [RustDmrPrefsService].
class RustDlnaCastService extends ChangeNotifier {
  RustDlnaCastService({
    required WebDavService webDav,
    required CacheService cache,
    required AccountsService accounts,
    required RustDmrPrefsService dmrPrefs,
  }) : _webDav = webDav,
       _cache = cache,
       _accounts = accounts,
       _dmrPrefs = dmrPrefs;

  final WebDavService _webDav;
  final CacheService _cache;
  final AccountsService _accounts;
  final RustDmrPrefsService _dmrPrefs;

  // ── State ─────────────────────────────────────────────────────────────────

  DlnaCastState _state = DlnaCastState.idle;
  DlnaPlaybackState _playbackState = DlnaPlaybackState.stopped;
  DlnaRenderer? _renderer;
  final List<DlnaRenderer> _discovered = [];
  _DlnaQueue? _queue;
  WebDavItem? _currentItem;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _error;
  DlnaCastError? _castError;
  DlnaTranscodeSettings _transcodeSettings = const DlnaTranscodeSettings();
  DlnaCompatibilityHint? _compatHint;
  String? _activeHlsToken; // HLS session token to unregister on stop

  DlnaCastState get state => _state;
  DlnaPlaybackState get playbackState => _playbackState;
  DlnaRenderer? get renderer => _renderer;
  List<DlnaRenderer> get discovered => List.unmodifiable(_discovered);
  _DlnaQueue? get queue => _queue;
  WebDavItem? get currentItem => _currentItem;
  Duration get position => _position;
  Duration? get duration => _duration;
  String? get error => _error;
  DlnaCastError? get castError => _castError;
  DlnaCastErrorCode? get errorCode => _castError?.code;
  DlnaTranscodeSettings get transcodeSettings => _transcodeSettings;
  DlnaCompatibilityHint? get compatibilityHint => _compatHint;

  // ── Internal ──────────────────────────────────────────────────────────────

  RawDatagramSocket? _ssdpSocket;
  Timer? _discoveryTimeout;
  String? _localIp;
  Timer? _pollTimer;

  HttpClient _newHttpClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..maxConnectionsPerHost = 1;

  // ── SSDP Discovery (Dart, non-blocking) ──────────────────────────────────

  /// Begin SSDP M-SEARCH discovery. Auto-stops after 4 seconds.
  Future<void> startDiscovery() async {
    _discovered.clear();
    _state = DlnaCastState.discovering;
    notifyListeners();
    try {
      _ssdpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 0, reuseAddress: true,
      );
      _ssdpSocket!.multicastHops = 4;
      _ssdpSocket!.listen(_onSsdpDatagram, onError: (_) {});
      const msearch = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';
      final data = utf8.encode(msearch);
      final multicast = InternetAddress('239.255.255.250');
      _ssdpSocket!.send(data, multicast, 1900);
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
    final locationMatch = RegExp(r'LOCATION:\s*(\S+)', caseSensitive: false).firstMatch(msg);
    final location = locationMatch?.group(1);
    if (location == null || location.isEmpty) return;
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
      if (controlPath == null) return;
      final connMgrPath = _connMgrControlUrl(body, location) ?? '';
      final usn = _xmlText(body, 'UDN') ?? location;
      final renderer = DlnaRenderer(
        usn: usn, friendlyName: friendlyName, location: location,
        controlUrl: controlPath, connMgrControlUrl: connMgrPath, host: uri.host,
      );
      if (!_discovered.any((r) => r.usn == renderer.usn)) {
        _discovered.add(renderer);
        notifyListeners();
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  // ── Cast control ──────────────────────────────────────────────────────────

  /// Start casting. Supply either [seed] (from video player) or [singleItem]
  /// + [accountId] (from network library).
  Future<void> startCast({
    required DlnaRenderer renderer,
    VideoQueueSeed? seed,
    WebDavItem? singleItem,
    String? accountId,
  }) async {
    assert(seed != null || (singleItem != null && accountId != null));
    await _cleanupSession();

    _renderer = renderer;
    _state = DlnaCastState.casting;
    _playbackState = DlnaPlaybackState.buffering;
    _error = null;
    notifyListeners();

    // Load persisted DMR prefs for this device.
    final prefs = _dmrPrefs.get(renderer.usn);
    if (prefs != null) {
      _transcodeSettings = DlnaTranscodeSettings(
        remuxContainer: prefs.remuxContainer,
        transcodeVideo: prefs.transcodeVideo,
        transcodeAudio: prefs.transcodeAudio,
      );
    }

    try {
      _localIp = await _getLocalIpFor(renderer.host);
      final effAccountId = accountId ?? seed!.accountId;
      final initial = singleItem ?? seed!.current;
      final siblings = seed?.siblings ?? [];
      _queue = _DlnaQueue(
        webDav: _webDav,
        accountId: effAccountId,
        rootPath: seed?.folderPath ?? _parentPath(initial.path),
        seed: siblings.isNotEmpty ? siblings : [initial],
        initialRemotePath: initial.path,
      );
      _queue!.addListener(() => notifyListeners());
      _queue!.startScan();
      _compatHint = _detectHint(initial.name);
      await _castItem(initial, effAccountId);
    } catch (e, stack) {
      debugPrint('[DlnaCast] startCast error: $e\n$stack');
      _state = DlnaCastState.error;
      if (e is DlnaCastError) {
        _castError = e;
        _error = e.userMessage;
      } else {
        _castError = DlnaCastError(
          code: DlnaCastErrorCode.unknown,
          userMessage: '投屏出错，请重试。',
          techDetail: e.toString(),
        );
        _error = _castError!.userMessage;
      }
      notifyListeners();
    }
  }

  Future<void> _castItem(WebDavItem item, String accountId) async {
    _currentItem = item;
    _position = Duration.zero;
    _duration = null;
    _playbackState = DlnaPlaybackState.buffering;
    notifyListeners();

    // 1. Ensure Rust proxy is running.
    final proxyPortStr = RustCoreService.proxyStart(port: 0);
    if (proxyPortStr == null || proxyPortStr.startsWith('error:')) {
      throw DlnaCastError(
        code: DlnaCastErrorCode.proxyUnavailable,
        userMessage: '投屏引擎不可用，请在 Android 设备上运行（需要 wdmm-ffi）。',
        techDetail: 'wdmm_proxy_start returned: ${proxyPortStr ?? "library not loaded"}',
      );
    }
    final proxyPort = int.tryParse(proxyPortStr) ?? 0;
    if (proxyPort == 0) {
      throw DlnaCastError(
        code: DlnaCastErrorCode.proxyUnavailable,
        userMessage: '投屏引擎启动失败：代理未绑定端口。',
        techDetail: 'wdmm_proxy_start returned "$proxyPortStr" — port parse = 0',
      );
    }

    // 2. Locate local cache file.
    // Cloud-stream cast (wdmm_proxy_register_stream) is NOT available at
    // submodule SHA 4a37aa4, nor in dirty WDMM-core-hls R12. The file must be
    // in the local cache. Inform the user clearly and name the blocker.
    final sourceName = _resolveSourceName(accountId);
    final localFile = _cache.fileForRemote(item.path, sourceName: sourceName);
    if (!localFile.existsSync()) {
      throw DlnaCastError(
        code: DlnaCastErrorCode.notCached,
        userMessage: '文件尚未缓存，请先下载后再投屏。',
        techDetail: '云端直投功能被阻塞（wdmm_proxy_register_stream 在 SHA 4a37aa4 中不存在），'
            '文件：${item.name}',
      );
    }

    // 3. Register as HLS session with the Rust proxy.
    final modeJson = _transcodeSettings.toHlsModeJson();
    final regJson = RustCoreService.proxyRegisterHls(
      localFile.path, modeJson: modeJson,
    );
    if (regJson == null || regJson.startsWith('error:')) {
      throw DlnaCastError(
        code: DlnaCastErrorCode.hlsRegisterFailed,
        userMessage: 'HLS 代理注册失败，请确认 wdmm-ffi 已为此设备编译（SHA 4a37aa4）。',
        techDetail: 'wdmm_proxy_register_hls returned: ${regJson ?? "null (HLS FFI unavailable)"}',
      );
    }
    final regData = jsonDecode(regJson) as Map<String, dynamic>;
    final token = regData['token'] as String;
    final playlistTemplate = regData['playlist_template'] as String;
    _activeHlsToken = token;

    // LAN-accessible HLS playlist URL. DMR pulls HLS segments from here.
    final hlsUrl = 'http://$_localIp:$proxyPort$playlistTemplate';
    debugPrint('[DlnaCast] HLS URL: $hlsUrl token=$token');

    // 4. Negotiate protocolInfo + SetAVTransportURI + Play via Dart SOAP.
    //    TODO(r12-dlna-transport-ffi): replace with Rust SOAP once exported.
    final sinkProtocols = await _getSinkProtocolInfo(_renderer!.connMgrControlUrl);
    final supportsVideo = sinkProtocols.isEmpty ||
        sinkProtocols.any((p) {
          final parts = p.split(':');
          return parts.length >= 3 && parts[2].startsWith('video/');
        });
    if (!supportsVideo) {
      throw DlnaCastError(
        code: DlnaCastErrorCode.rendererNoVideo,
        userMessage: '${_renderer!.friendlyName} 不支持视频播放，请检查设备是否支持 DLNA 视频投屏。',
        techDetail: 'GetProtocolInfo SinkProtocolInfo 无 video/* 条目',
      );
    }
    final mimeType = _mimeFor(item.name);
    final protocolInfo = _negotiateProtocolInfo(mimeType, sinkProtocols);

    try {
      await _soap(
        _renderer!.controlUrl, 'SetAVTransportURI',
        '<InstanceID>0</InstanceID>'
        '<CurrentURI>${_xmlEscape(hlsUrl)}</CurrentURI>'
        '<CurrentURIMetaData>${_xmlEscape(_didlLite(item.name, hlsUrl, protocolInfo))}</CurrentURIMetaData>',
      );
      await _soap(
        _renderer!.controlUrl, 'Play',
        '<InstanceID>0</InstanceID><Speed>1</Speed>',
      );
    } on DlnaCastError {
      rethrow;
    } catch (e) {
      throw DlnaCastError(
        code: DlnaCastErrorCode.soapFailed,
        userMessage: '投屏控制失败，请检查设备是否在线或重启后重试。',
        techDetail: 'AVTransport SOAP failed: $e',
      );
    }

    _playbackState = DlnaPlaybackState.playing;
    notifyListeners();
    _startPolling(accountId);
  }

  Future<void> stop() async {
    if (_state == DlnaCastState.idle) return;
    try {
      await _soap(_renderer!.controlUrl, 'Stop', '<InstanceID>0</InstanceID>');
    } catch (_) {}
    await _cleanupSession();
    _state = DlnaCastState.idle;
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_renderer == null) return;
    try {
      if (_playbackState == DlnaPlaybackState.playing) {
        await _soap(_renderer!.controlUrl, 'Pause', '<InstanceID>0</InstanceID>');
        _playbackState = DlnaPlaybackState.paused;
      } else {
        await _soap(_renderer!.controlUrl, 'Play',
            '<InstanceID>0</InstanceID><Speed>1</Speed>');
        _playbackState = DlnaPlaybackState.playing;
      }
      notifyListeners();
    } catch (e) {
      final ce = e is DlnaCastError
          ? e
          : DlnaCastError(
              code: DlnaCastErrorCode.soapFailed,
              userMessage: '控制指令失败，请检查设备是否在线。',
              techDetail: 'playPause SOAP: $e',
            );
      _castError = ce;
      _error = ce.userMessage;
      notifyListeners();
    }
  }

  Future<void> seekTo(Duration pos) async {
    if (_renderer == null) return;
    try {
      await _soap(_renderer!.controlUrl, 'Seek',
          '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>${_formatHms(pos)}</Target>');
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

  Future<void> playTrack(int index) async {
    final q = _queue;
    if (q == null || index < 0 || index >= q.length) return;
    final item = q.tracks[index];
    q.selectRemotePath(item.path);
    await _castItem(item, q.accountId);
  }

  /// Update transcode settings and persist to [RustDmrPrefsService].
  Future<void> setTranscodeSettings(DlnaTranscodeSettings settings) async {
    _transcodeSettings = settings;
    final renderer = _renderer;
    if (renderer != null) {
      final existing = _dmrPrefs.get(renderer.usn) ?? const DmrDevicePrefs();
      await _dmrPrefs.upsert(
        renderer.usn,
        existing.copyWith(
          remuxContainer: settings.remuxContainer,
          transcodeVideo: settings.transcodeVideo,
          transcodeAudio: settings.transcodeAudio,
        ),
      );
    }
    notifyListeners();
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling(String accountId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _poll(accountId);
    });
  }

  Future<void> _poll(String accountId) async {
    if (_renderer == null || _state != DlnaCastState.casting) return;
    try {
      final posResp = await _soap(
        _renderer!.controlUrl, 'GetPositionInfo', '<InstanceID>0</InstanceID>',
      );
      if (posResp != null) {
        final relTime = _xmlText(posResp, 'RelTime');
        final trackDuration = _xmlText(posResp, 'TrackDuration');
        if (relTime != null) _position = _parseDuration(relTime);
        if (trackDuration != null && trackDuration != 'NOT_IMPLEMENTED') {
          _duration = _parseDuration(trackDuration);
        }
      }
      if (DateTime.now().second % 5 == 0) {
        final transResp = await _soap(
          _renderer!.controlUrl, 'GetTransportInfo', '<InstanceID>0</InstanceID>',
        );
        if (transResp != null) {
          final transportState = _xmlText(transResp, 'CurrentTransportState');
          if (transportState == 'STOPPED' && _playbackState == DlnaPlaybackState.playing) {
            _playbackState = DlnaPlaybackState.stopped;
            notifyListeners();
            if (_queue?.hasNext == true) await playNext();
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
    } catch (_) {}
  }

  // ── Session cleanup ───────────────────────────────────────────────────────

  Future<void> _cleanupSession() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _queue?.dispose();
    _queue = null;
    final tok = _activeHlsToken;
    if (tok != null) {
      RustCoreService.proxyUnregisterHls(tok);
      _activeHlsToken = null;
    }
    _renderer = null;
    _currentItem = null;
    _position = Duration.zero;
    _duration = null;
    _error = null;
    _castError = null;
    _playbackState = DlnaPlaybackState.stopped;
    _compatHint = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Resolve the source name (WebDav account display name) for [accountId].
  /// The cache path is keyed by source name, not account id.
  String _resolveSourceName(String accountId) {
    final name = _accounts.nameForAccount(accountId);
    if (name != null && name.isNotEmpty) return name;
    // Fallback: use accountId directly. If it differs from the display name
    // the file-not-found check below surfaces a clear error.
    return accountId;
  }

  Future<String> _getLocalIpFor(String targetIp) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLinkLocal: false,
    );
    final privateIps = <String>[];
    final targetParts = targetIp.split('.');
    final prefix = targetParts.length == 4 ? targetParts.take(3).join('.') : null;
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final a = addr.address;
        if (!_isPrivateIp(a)) continue;
        privateIps.add(a);
        if (prefix != null && a.startsWith('$prefix.')) return a;
      }
    }
    return privateIps.isNotEmpty ? privateIps.first : '127.0.0.1';
  }

  bool _isPrivateIp(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      (ip.startsWith('172.') && _is172Private(ip));

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

  DlnaCompatibilityHint _detectHint(String name) {
    final ext = _ext(name);
    const problematicContainers = {
      'mkv', 'avi', 'mov', 'ts', 'm2ts', 'flv', 'rmvb', 'rm', 'wmv', 'asf', '3gp', 'webm',
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

  String _mimeFor(String name) {
    switch (_ext(name)) {
      case 'mp4': case 'm4v': return 'video/mp4';
      case 'mkv': return 'video/x-matroska';
      case 'avi': return 'video/x-msvideo';
      case 'mov': return 'video/quicktime';
      case 'webm': return 'video/webm';
      case 'ts': case 'm2ts': return 'video/mp2t';
      default: return 'video/mp4';
    }
  }

  String _didlLite(String title, String url, String protocolInfo) =>
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${_xmlEscape(title)}</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="${_xmlEscape(protocolInfo)}">${_xmlEscape(url)}</res>'
      '</item>'
      '</DIDL-Lite>';

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String? _xmlText(String xml, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>([^<]*)</$tag>').firstMatch(xml);
    return m?.group(1)?.trim();
  }

  String? _avTransportControlUrl(String xml, String location) {
    for (final block in RegExp(r'<service>(.*?)</service>', dotAll: true).allMatches(xml)) {
      final content = block.group(1) ?? '';
      if (!content.contains('AVTransport')) continue;
      final control = _xmlText(content, 'controlURL');
      if (control == null) continue;
      final base = Uri.parse(location);
      return control.startsWith('http') ? control : base.resolve(control).toString();
    }
    return null;
  }

  String? _connMgrControlUrl(String xml, String location) {
    for (final block in RegExp(r'<service>(.*?)</service>', dotAll: true).allMatches(xml)) {
      final content = block.group(1) ?? '';
      if (!content.contains('ConnectionManager')) continue;
      final control = _xmlText(content, 'controlURL');
      if (control == null) continue;
      final base = Uri.parse(location);
      return control.startsWith('http') ? control : base.resolve(control).toString();
    }
    return null;
  }

  Future<List<String>> _getSinkProtocolInfo(String connMgrControlUrl) async {
    if (connMgrControlUrl.isEmpty) return [];
    try {
      final body = await _soapConnMgr(connMgrControlUrl, 'GetProtocolInfo', '');
      if (body == null) return [];
      final sink = _xmlText(body, 'Sink') ?? '';
      return sink.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[DlnaCast] GetProtocolInfo failed: $e');
      return [];
    }
  }

  String _negotiateProtocolInfo(String mimeType, List<String> sinkProtocols) {
    final exact = sinkProtocols.where((p) {
      final parts = p.split(':');
      return parts.length >= 3 && parts[2] == mimeType;
    }).toList();
    if (exact.isNotEmpty) return exact.first;
    final mainType = mimeType.split('/').first;
    final wildcard = sinkProtocols.where((p) {
      final parts = p.split(':');
      if (parts.length < 3) return false;
      final cf = parts[2];
      return cf == '$mainType/*' || cf == '*/*';
    }).toList();
    if (wildcard.isNotEmpty) {
      final base = wildcard.first.split(':');
      return '${base[0]}:${base[1]}:$mimeType:'
          '${base.length > 3 ? base.sublist(3).join(':') : 'DLNA.ORG_OP=01'}';
    }
    return 'http-get:*:$mimeType:DLNA.ORG_OP=01';
  }

  // ── SOAP ──────────────────────────────────────────────────────────────────

  Future<String?> _soap(String controlUrl, String action, String bodyContent) async {
    final envelope = '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
        '$bodyContent'
        '</u:$action>'
        '</s:Body>'
        '</s:Envelope>';
    debugPrint('[DlnaCast] SOAP -> $action @ $controlUrl');
    final client = _newHttpClient();
    try {
      final req = await client.postUrl(Uri.parse(controlUrl));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPACTION',
          '"urn:schemas-upnp-org:service:AVTransport:1#$action"');
      final encoded = utf8.encode(envelope);
      req.headers.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 300) {
        throw Exception('SOAP $action failed (HTTP ${resp.statusCode})\n$body');
      }
      return body;
    } on SocketException catch (e) {
      debugPrint('[DlnaCast] SOAP $action network error: $e');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _soapConnMgr(
      String controlUrl, String action, String bodyContent) async {
    final envelope = '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">'
        '$bodyContent'
        '</u:$action>'
        '</s:Body>'
        '</s:Envelope>';
    final client = _newHttpClient();
    try {
      final req = await client.postUrl(Uri.parse(controlUrl));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPACTION',
          '"urn:schemas-upnp-org:service:ConnectionManager:1#$action"');
      final encoded = utf8.encode(envelope);
      req.headers.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      return resp.statusCode < 300 ? body : null;
    } finally {
      client.close(force: true);
    }
  }

  // ── Time helpers ──────────────────────────────────────────────────────────

  Duration _parseDuration(String hms) {
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
