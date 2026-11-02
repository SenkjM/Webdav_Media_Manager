import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/app_locale.dart';
import '../models/webdav_item.dart';
import '../screens/video_player_screen.dart' show VideoQueueSeed;
import '../utils/subtitle_sidecar.dart';
import 'dlna_cast_channel.dart';
import 'dlna_queue_controller.dart';
import 'rust_core_service.dart';
import 'rust_dmr_prefs_service.dart';
import 'settings_service.dart';
import 'transcode_preset_catalog.dart';
import 'webdav_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// 数据模型
// ──────────────────────────────────────────────────────────────────────────────

/// DLNA 渲染器（DMR 设备，如电视、投影仪、音箱）。
///
/// DLNA 协议层已整体移入 Rust，Dart 只在设备列表与详情页展示这些字段。
class DlnaRenderer {
  const DlnaRenderer({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.controlUrl,
    required this.connMgrControlUrl,
    required this.host,
    this.modelName,
    this.manufacturer,
    this.modelNumber,
    this.sinkProtocolInfo,
  });

  /// 设备唯一标识（SSDP USN 字段）。
  final String usn;

  /// 用户可读名称（Rust 端从 description.xml 的 friendlyName 解析）。
  final String friendlyName;

  /// 设备描述 XML 的完整 URL。
  final String location;

  /// 历史字段：AVTransport SOAP 控制 URL。
  ///
  /// 控制层在 Rust，Dart 不再自行发 SOAP；通过 FFI 发现的设备该字段为空串。
  final String controlUrl;

  /// 历史字段：ConnectionManager SOAP 控制 URL。理由同 [controlUrl]。
  final String connMgrControlUrl;

  /// 渲染器 IP 地址。
  final String host;

  /// 设备型号名称（description.xml 的 modelName 元素）。
  final String? modelName;

  /// 制造商（description.xml 的 manufacturer 元素）。
  final String? manufacturer;

  /// 型号编号（description.xml 的 modelNumber 元素）。
  final String? modelNumber;

  /// 支持的协议信息（Rust 会话协商出的 SinkProtocolInfo）。
  final List<String>? sinkProtocolInfo;

  @override
  bool operator ==(Object other) =>
      other is DlnaRenderer && other.usn == usn;

  @override
  int get hashCode => usn.hashCode;

  DlnaRenderer copyWith({
    String? usn,
    String? friendlyName,
    String? location,
    String? controlUrl,
    String? connMgrControlUrl,
    String? host,
    String? modelName,
    String? manufacturer,
    String? modelNumber,
    List<String>? sinkProtocolInfo,
  }) => DlnaRenderer(
    usn: usn ?? this.usn,
    friendlyName: friendlyName ?? this.friendlyName,
    location: location ?? this.location,
    controlUrl: controlUrl ?? this.controlUrl,
    connMgrControlUrl: connMgrControlUrl ?? this.connMgrControlUrl,
    host: host ?? this.host,
    modelName: modelName ?? this.modelName,
    manufacturer: manufacturer ?? this.manufacturer,
    modelNumber: modelNumber ?? this.modelNumber,
    sinkProtocolInfo: sinkProtocolInfo ?? this.sinkProtocolInfo,
  );
}

/// 文件兼容性提示。
///
/// 判断已由 Rust 在会话启动/状态同步时给出（`compat.requires_transcode` /
/// `compat.reason`），Dart 不再按扩展名猜测。
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

/// 内部异常，携带给用户看的消息。
class _CastError implements Exception {
  const _CastError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ──────────────────────────────────────────────────────────────────────────────
// DlnaCastService
// ──────────────────────────────────────────────────────────────────────────────

/// DLNA 投屏服务（薄 FFI 门面）。
///
/// 定位：**Rust 是执行层，Dart 只是显示层 + 用户级控制层。**
///
/// * SSDP / 设备描述 / SOAP / DIDL-Lite / ConnectionManager / 传输状态机 /
///   字幕匹配 / 媒体字节代理全部在 Rust；
/// * Dart 只做三件事：把用户操作翻译成会话命令 JSON、按 1 秒节拍拉取状态
///   JSON 渲染 UI、维护用户可见的播放队列（[DlnaQueueController]）与
///   Android 前台服务 / MulticastLock（[DlnaCastChannel]）。
///
/// FFI 绑定统一在 [RustCoreService]，不在此文件直接持有 `DynamicLibrary`。
///
/// 生命周期：
/// 1. 设备选择界面调用 [startDiscovery] → [stopDiscovery]
/// 2. [startCast] 建立投屏会话（Rust `wdmm_dlna_session_start`）
/// 3. [stop] 结束会话 → state 回到 idle
class DlnaCastService extends ChangeNotifier {
  DlnaCastService({
    required WebDavService webDav,
    required RustDmrPrefsService dmrPrefs,
    required SettingsService settings,
  }) : _webDav = webDav,
       _dmrPrefs = dmrPrefs,
       _settings = settings;

  final WebDavService _webDav;
  final RustDmrPrefsService _dmrPrefs;
  final SettingsService _settings;

  /// 状态轮询间隔。Rust 内部每个 tick 只做一次轻量状态同步。
  static const Duration _statePollInterval = Duration(seconds: 1);

  /// SSDP 发现窗口。需短于设备选择页的 4 秒超时，让结果先于超时提示到达。
  static const int _discoveryWindowMs = 3000;

  // --- 对外状态 ---
  DlnaCastState _state = DlnaCastState.idle;
  DlnaPlaybackState _playbackState = DlnaPlaybackState.stopped;
  DlnaRenderer? _renderer;
  final List<DlnaRenderer> _discovered = [];
  DlnaQueueController? _queue;
  WebDavItem? _currentItem;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _error;
  DlnaCompatibilityHint? _compatHint;

  // --- 字幕状态 ---
  /// 当前视频的候选字幕（由 Rust 匹配同级目录后回传）。
  List<SidecarHit> _subtitleCandidates = const [];
  /// 当前选中的字幕（null = 无字幕）。
  SidecarHit? _selectedSubtitle;

  DlnaCastState get state => _state;
  DlnaPlaybackState get playbackState => _playbackState;
  DlnaRenderer? get renderer => _renderer;
  List<DlnaRenderer> get discovered => List.unmodifiable(_discovered);
  DlnaQueueController? get queue => _queue;
  WebDavItem? get currentItem => _currentItem;
  Duration get position => _position;
  Duration? get duration => _duration;
  String? get error => _error;
  DlnaCompatibilityHint? get compatibilityHint => _compatHint;

  /// Rust 协商出的协议信息（会话建立 / 状态 tick 时更新）。
  ///
  /// 设备详情页优先展示它；为 null 表示当前没有活动会话。
  String? get protocolInfo => _protocolInfo;

  /// 转码阶段（契约 §3）：`warming` / `playing` / `ended` / `failed` / `idle`。
  ///
  /// 旧版 `.so` 不返回该字段时按 `playing` 处理，绝不把用户困在预热界面里。
  String get phase => _phase;

  /// 实测转码速度（内容时间 / 墙钟时间）；direct 模式或未知时为 0。
  double get encodeSpeed => _encodeSpeed;

  /// 已编码的媒体时间（毫秒），UI 显示「已编码 x.x 秒」。
  int get encodeContentMs => _encodeContentMs;

  /// 播放列表是否已就绪；只有就绪后 `{"cmd":"cast"}` 才合法。
  bool get playlistReady => _playlistReady;

  /// 已落盘的分段数量（播放列表就绪时显示）。
  int get segments => _segments;

  /// 转码速度估算：`null` 表示还在测速，`true/false` 表示能否实时。
  bool? get estimatedRealtime => _estimatedRealtime;

  /// `phase == "failed"` 时的失败原因（投屏会话级错误见 [error]）。
  String? get errorText => _warmupError;

  /// `remux` / `transcode`；旧版 `.so` 或直通模式为空串。
  String get encodeMode => _encodeMode;

  /// 实际使用的视频编码器名；remux / 直通 / 未知为 null。
  String? get videoEncoder => _videoEncoder;

  /// 实际使用的音频编码名，`copy` 表示直拷；未知为 null。
  String? get audioEncoder => _audioEncoder;

  /// Rust 上报的转码警告（橙色提示，契约 §7.4 最多 8 条）。
  List<String> get encodeWarnings => List.unmodifiable(_encodeWarnings);

  /// Rust 诊断环形缓冲（最旧在前），用于「诊断日志」折叠区。
  List<String> get diagnostics => List.unmodifiable(_diagnostics);

  /// 当前视频的字幕候选列表（Rust 匹配结果）。
  List<SidecarHit> get subtitleCandidates =>
      List.unmodifiable(_subtitleCandidates);

  /// 当前选中的字幕，null 表示无字幕。
  SidecarHit? get selectedSubtitle => _selectedSubtitle;

  // --- 内部：Rust 会话 ---
  int? _handle;
  Timer? _stateTimer;
  bool _stateTickInFlight = false;
  bool _stateUnavailableLogged = false;
  /// 已处理过 `ended` 的条目路径，避免每秒 tick 重复触发自动下一集。
  String? _endedForPath;
  /// 本次会话是否真的播起来过（用来区分「播完/用户停」与「压根没播起来」）。
  bool _everPlaying = false;
  /// Rust 协商出的协议信息（只用于设备详情页展示）。
  String? _protocolInfo;

  // --- 内部：HLS 预热 / 转码遥测（契约 dlna-warmup-ffi §4、§7.5）---
  /// 转码阶段：`warming` / `playing` / `ended` / `failed` / `idle`。
  ///
  /// 旧版 `.so` 不返回 `phase` 字段，此时按 `playing` 降级（见 [_applyWarmupFields]）。
  String _phase = 'idle';
  /// 实测转码速度（已编码媒体时间 / 墙钟时间）。
  double _encodeSpeed = 0;
  /// 已写入 muxer 的媒体时间（毫秒），UI 用来显示「已编码 x.x 秒」。
  int _encodeContentMs = 0;
  /// 播放列表（index.m3u8）是否已生成。
  bool _playlistReady = false;
  /// 已落盘的分段数量。
  int _segments = 0;
  /// 转码速度估算：`null` = 采样不足（`encode_content_ms < 3000`）。
  bool? _estimatedRealtime;
  /// `phase == "failed"` 时的失败原因；与投屏会话级错误 [error] 分开。
  String? _warmupError;
  /// `remux` / `transcode`；未知（旧 `.so` / direct）为空串。
  String _encodeMode = '';
  /// 实际使用的视频编码器名（remux 时为 null）。
  String? _videoEncoder;
  /// 实际使用的音频编码名，`copy` 表示直拷。
  String? _audioEncoder;
  /// Rust 上报的转码警告（硬件回退等），最多 8 条。
  List<String> _encodeWarnings = const [];
  /// Rust 诊断环形缓冲（最旧在前，最多 40 行）。
  List<String> _diagnostics = const [];
  /// 「投送」命令进行中，避免连点重复下发。
  bool _castInFlight = false;

  // --- 内部：发现 / 生命周期 ---
  int _discoveryEpoch = 0;
  bool _disposed = false;

  // ── 发现 ──────────────────────────────────────────────────────────────────

  /// 通过 Rust 发起一次 SSDP 发现（阻塞窗口 [_discoveryWindowMs]）。
  Future<void> startDiscovery() async {
    if (_disposed) return;
    final epoch = ++_discoveryEpoch;
    _discovered.clear();
    _state = DlnaCastState.discovering;
    _notify();
    unawaited(DlnaCastChannel.start());

    String? raw = await _runOnWorker<String?>(
      () => RustCoreService.dlnaDiscoverExt(timeoutMs: _discoveryWindowMs),
    );
    // 旧版 .so 没有 extended 发现符号：退化为 legacy 设备列表
    // （只有 usn/location/server，没有 friendly_name）。
    raw ??= await _runOnWorker<String?>(
      () => RustCoreService.dlnaDiscover(timeoutMs: _discoveryWindowMs),
    );
    if (_disposed || epoch != _discoveryEpoch) return;

    final renderers = _parseDiscovered(raw);
    if (renderers.isNotEmpty) {
      _discovered
        ..clear()
        ..addAll(renderers);
    }
    if (_state == DlnaCastState.discovering) {
      _state = DlnaCastState.idle;
    }
    unawaited(DlnaCastChannel.stop());
    _notify();
  }

  /// 结束发现（用户选择设备、关闭面板或重试时调用）。
  ///
  /// 不递增 [_discoveryEpoch]：仍在关闭窗口内的 Rust 发现结果照常回填，
  /// 只把 UI 状态收回 idle。
  void stopDiscovery() {
    unawaited(DlnaCastChannel.stop());
    if (_state == DlnaCastState.discovering) {
      _state = DlnaCastState.idle;
      _notify();
    }
  }

  /// 发布当前会话协商出的 protocolInfo。
  ///
  /// 协议层在 Rust：Dart 不再发 GetProtocolInfo / 做 DIDL 协商，这里只是把
  /// 会话状态里带回的 `protocol_info` 挂到设备列表上供详情页展示。
  Future<void> fetchProtocolInfo(DlnaRenderer renderer) async {
    final info = _protocolInfo;
    if (info == null || info.isEmpty) return;
    final index = _discovered.indexWhere((r) => r.usn == renderer.usn);
    if (index < 0) return;
    _discovered[index] = _discovered[index].copyWith(
      sinkProtocolInfo: [info],
    );
    _notify();
  }

  // ── 投屏会话 ──────────────────────────────────────────────────────────────

  /// 开始投屏到 [renderer]。
  ///
  /// 媒体字节与协议交互全部由 Rust 完成；Dart 只把渲染器标识、账号、远端
  /// 路径与用户偏好（强制直连 / 转码预设）打包成会话配置。
  Future<void> startCast({
    required DlnaRenderer renderer,
    VideoQueueSeed? seed,
    WebDavItem? singleItem,
    String? accountId,
  }) async {
    assert(seed != null || (singleItem != null && accountId != null));
    await _cleanupSession();
    _renderer = renderer;
    _error = null;

    final effAccountId = accountId ?? seed!.accountId;
    final initial = singleItem ?? seed!.current;
    final siblings = seed?.siblings ?? const <WebDavItem>[];
    _queue = DlnaQueueController(
      webDav: _webDav,
      accountId: effAccountId,
      rootPath: seed?.folderPath ?? _parentPath(initial.path),
      seed: siblings.isNotEmpty ? siblings : [initial],
      initialRemotePath: initial.path,
    )..startScan();

    _state = DlnaCastState.casting;
    _notify();

    try {
      await _beginItem(initial, effAccountId, first: true);
    } catch (e) {
      await _failWith(e);
    }
  }

  /// 结束投屏并回到 idle。
  ///
  /// 预热（`phase == "warming"`）中调用时，Rust 侧 `{"cmd":"stop"}` 会取消转码
  /// 任务并清理分段目录（契约 §3），不会操作渲染器。
  Future<void> stop() async {
    _stateTimer?.cancel();
    _stateTimer = null;
    final handle = _handle;
    if (handle != null) {
      final cmdJson = jsonEncode(<String, Object?>{'cmd': 'stop'});
      await _runOnWorker(
        () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
      );
    }
    // 已发过 stop，避免 _cleanupSession 在 warming 时重复发送。
    _phase = 'idle';
    await _cleanupSession();
    if (_disposed) return;
    _state = DlnaCastState.idle;
    _notify();
  }

  /// 预热完成后把 HLS 会话投送到渲染器（契约 §3 `{"cmd":"cast"}`）。
  ///
  /// 只有 Rust 报告 `phase == "warming"` 且 `playlist_ready == true` 时才合法；
  /// 失败时把原因写进 [error] 供 UI 提示，不抛异常（用户可点「取消」重来）。
  Future<void> castNow() async {
    final handle = _handle;
    if (handle == null || _phase != 'warming' || _castInFlight) return;
    _castInFlight = true;
    try {
      final cmdJson = jsonEncode(<String, Object?>{'cmd': 'cast'});
      final raw = await _runOnWorker(
        () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
      );
      if (_disposed || _handle != handle) return;
      if (!_isOk(raw)) {
        debugPrint('[DLNA] cast rejected: $raw');
        _error = _cmdError(raw);
        _notify();
        return;
      }
      _phase = 'playing';
      _error = null;
      _warmupError = null;
      _playbackState = DlnaPlaybackState.playing;
      _notify();
    } finally {
      _castInFlight = false;
    }
  }

  /// 切换播放 / 暂停。
  Future<void> playPause() async {
    final handle = _handle;
    if (handle == null) return;
    final wantPlay = _playbackState != DlnaPlaybackState.playing;
    final cmdJson = jsonEncode(<String, Object?>{
      'cmd': wantPlay ? 'play' : 'pause',
    });
    final raw = await _runOnWorker(
      () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
    );
    if (!_isOk(raw)) {
      _error = _cmdError(raw);
      _notify();
      return;
    }
    _playbackState =
        wantPlay ? DlnaPlaybackState.playing : DlnaPlaybackState.paused;
    _notify();
  }

  /// 跳转到指定播放位置。
  Future<void> seekTo(Duration position) async {
    final handle = _handle;
    if (handle == null) return;
    final cmdJson = jsonEncode(<String, Object?>{
      'cmd': 'seek',
      'position_ms': position.inMilliseconds,
    });
    final raw = await _runOnWorker(
      () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
    );
    if (!_isOk(raw)) {
      // 渲染器拒收 seek 很常见，保持与旧实现一致的静默处理。
      debugPrint('[DLNA] seek rejected: $raw');
      return;
    }
    _position = position;
    _notify();
  }

  /// 播放队列下一集。
  Future<void> playNext() async {
    final q = _queue;
    if (q == null || !q.hasNext) return;
    final next = q.next!;
    q.selectRemotePath(next.path);
    await _castQueuedItem(next, q.accountId);
  }

  /// 播放队列上一集。
  Future<void> playPrevious() async {
    final q = _queue;
    if (q == null || !q.hasPrevious) return;
    final previous = q.previous!;
    q.selectRemotePath(previous.path);
    await _castQueuedItem(previous, q.accountId);
  }

  /// 播放队列中第 [index] 个条目。
  Future<void> playTrack(int index) async {
    final q = _queue;
    if (q == null) return;
    final item = q.selectIndex(index);
    if (item == null) return;
    await _castQueuedItem(item, q.accountId);
  }

  /// 选择字幕（null = 关闭字幕）。
  Future<void> selectSubtitle(SidecarHit? hit) async {
    final handle = _handle;
    if (handle == null || _currentItem == null) return;
    final cmdJson = jsonEncode(<String, Object?>{
      'cmd': 'subtitle',
      'path': hit?.path,
    });
    final raw = await _runOnWorker(
      () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
    );
    if (!_isOk(raw)) {
      _error = _cmdError(raw);
      _notify();
      return;
    }
    _selectedSubtitle = hit;
    _notify();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _discoveryEpoch++;
    unawaited(DlnaCastChannel.stop());
    await _cleanupSession();
    _discovered.clear();
    super.dispose();
  }

  // ── 内部：会话推进 ────────────────────────────────────────────────────────

  /// 把队列中的条目切到当前投屏（首次 = 新建会话，之后 = `select` 命令）。
  Future<void> _castQueuedItem(WebDavItem item, String accountId) async {
    if (_renderer == null) return;
    try {
      await _beginItem(item, accountId, first: false);
    } catch (e) {
      await _failWith(e);
    }
  }

  /// 解析转码路径下真正发给 Rust 的预设 id。
  ///
  /// 设备级覆盖优先于全局默认；直通（`passthrough`）与空值一律忽略，
  /// 保证「直通」永远不会作为转码预设穿过 FFI。
  String _effectivePresetId(String? devicePresetId) {
    final override = devicePresetId?.trim();
    if (override != null &&
        override.isNotEmpty &&
        override != TranscodePresetCatalog.passthroughId) {
      return override;
    }
    final global = _settings.dlnaDefaultTranscodePreset.trim();
    if (global.isEmpty || global == TranscodePresetCatalog.passthroughId) {
      return 'balanced';
    }
    return global;
  }

  Future<void> _beginItem(
    WebDavItem item,
    String accountId, {
    required bool first,
  }) async {
    final renderer = _renderer;
    if (renderer == null) return;

    _currentItem = item;
    _position = Duration.zero;
    _duration = null;
    _playbackState = DlnaPlaybackState.buffering;
    _endedForPath = null;
    _everPlaying = false;
    _subtitleCandidates = const [];
    _selectedSubtitle = null;
    _resetWarmupState();
    _notify();

    final prefs = _dmrPrefs[renderer.usn];
    final forceDirect = prefs?.forceDirect ?? true;
    // 直通（不转码）只由 forceDirect 开关表达：`passthrough` 不是转码预设，
    // 不允许经 `preset_id` 偷偷走直通，否则就绕过了兼容开关。
    final presetId =
        forceDirect ? null : _effectivePresetId(prefs?.presetId);

    final handle = _handle;
    if (first || handle == null) {
      final configJson = jsonEncode(<String, Object?>{
        'renderer_location': renderer.location,
        'renderer_usn': renderer.usn,
        'account_id': accountId,
        'remote_path': item.path,
        'name': item.name,
        'size': item.size ?? 0,
        'preset_id': presetId,
        'force_direct': forceDirect,
        // §3 预热：HLS 起转码后立即返回 `phase:"warming"`，Dart 不再干等 20s。
        // 旧版 `.so` 不认识该键（直接忽略），行为与之前一致。
        'warmup': true,
        'ui_lang': _settings.appLocale.locale?.languageCode ?? '',
      });
      final raw = await _runOnWorker(
        () => RustCoreService.dlnaSessionStart(configJson),
      );
      final json = _decodeJson(raw);
      final newHandle = _asInt(json?['handle']);
      final started = json != null && json['ok'] != false && newHandle != null;
      if (started) {
        debugPrint('[DLNA] start ok: $raw');
      } else {
        debugPrint('[DLNA] start failed: $raw');
      }
      if (!started) {
        throw _CastError(_sessionError(raw, json));
      }
      _handle = newHandle;
      final info = json['protocol_info']?.toString();
      if (info != null && info.isNotEmpty) _protocolInfo = info;
      final compat = _compatFrom(json['compat']);
      if (compat != null) _compatHint = compat;
      // 启动响应里的 `phase`（旧版 `.so` 没有 → 降级为 playing）。
      _applyWarmupFields(json);
      _startStateTimer();
    } else {
      final cmdJson = jsonEncode(<String, Object?>{
        'cmd': 'select',
        'remote_path': item.path,
        'name': item.name,
        'size': item.size ?? 0,
        'preset_id': presetId,
      });
      final raw = await _runOnWorker(
        () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
      );
      if (!_isOk(raw)) {
        debugPrint('[DLNA] select failed: $raw');
        throw _CastError(_cmdError(raw));
      }
    }

    if (_disposed) return;
    // 预热阶段（§3）还没投送：保持 buffering，UI 由「预热/预检」面板接管。
    _playbackState = _phase == 'warming'
        ? DlnaPlaybackState.buffering
        : DlnaPlaybackState.playing;
    _notify();
  }

  void _startStateTimer() {
    _stateTimer?.cancel();
    _stateTimer = Timer.periodic(
      _statePollInterval,
      (_) => unawaited(_tickState()),
    );
  }

  /// 每次 tick 都向 Rust 要一次状态；Dart 不再解析 SOAP。
  Future<void> _tickState() async {
    final handle = _handle;
    if (handle == null || _stateTickInFlight || _disposed) return;
    if (_state != DlnaCastState.casting) return;
    _stateTickInFlight = true;
    try {
      final raw = await _runOnWorker(
        () => RustCoreService.dlnaSessionState(handle),
      );
      if (_disposed || _handle != handle) return;
      final json = _decodeJson(raw);
      if (json == null) {
        if (!_stateUnavailableLogged) {
          _stateUnavailableLogged = true;
          debugPrint('[DLNA] session state unavailable: $raw');
        }
        return;
      }
      await _applyState(json);
    } finally {
      _stateTickInFlight = false;
    }
  }

  Future<void> _applyState(Map<String, dynamic> json) async {
    if (json['ok'] == false) {
      await _failWith(
        _CastError(json['error']?.toString() ?? '投屏会话异常结束'),
      );
      return;
    }

    // §3 / §7.5 预热遥测：缺失的字段保持原值，不抛异常。
    _applyWarmupFields(json);

    // 预热 / 预热失败阶段还没投送到渲染器：此时传输层通常是 STOPPED，
    // 但用户可见状态应由预热面板接管，所以不覆盖 playbackState。
    final inWarmup = _phase == 'warming' || _phase == 'failed';
    if (!inWarmup) {
      final mapped = _playbackFromTransport(json['transport']?.toString());
      if (mapped != null) {
        if (mapped == DlnaPlaybackState.playing) _everPlaying = true;
        _playbackState = mapped;
      }
    }

    final positionMs = _asInt(json['position_ms']);
    if (positionMs != null && positionMs >= 0) {
      _position = Duration(milliseconds: positionMs);
    }
    final durationMs = _asInt(json['duration_ms']);
    if (durationMs != null && durationMs > 0) {
      _duration = Duration(milliseconds: durationMs);
    }

    final info = json['protocol_info']?.toString();
    if (info != null && info.isNotEmpty) _protocolInfo = info;

    final compat = _compatFrom(json['compat']);
    if (compat != null) _compatHint = compat;

    if (json.containsKey('subtitle_candidates')) {
      _subtitleCandidates = _candidatesFrom(json['subtitle_candidates']);
    }
    final selected = _hitFromJson(json['selected_subtitle']);
    _selectedSubtitle = selected == null
        ? null
        : _findCandidate(selected.path) ?? selected;

    _notify();

    // 预热 / 预热失败期间 Rust 可能报 ended（转码结束时内部状态机收尾），
    // 这不是用户可见的播放结束，忽略即可。
    if (json['ended'] == true && !inWarmup) {
      await _handleEnded(
        json['ended_reason']?.toString(),
        json['current_path']?.toString(),
      );
    }
  }

  /// 处理 Rust 报告的播放结束事件。
  ///
  /// 这是 Dart 侧的用户级决策，不推给 Rust：
  /// * `ended_reason == "eof"`：自然播完 → 队列有下一集就自动续播，否则收尾；
  /// * `"stopped_by_device"`（以及 key 缺失 / null / 未知原因）：用户在 DMR
  ///   端主动停止，保守处理 —— 只收尾，**不**自动播下一集。
  Future<void> _handleEnded(String? reason, String? path) async {
    final id = (path != null && path.isNotEmpty)
        ? path
        : (_currentItem?.path ?? '');
    if (_endedForPath == id) return;
    _endedForPath = id;
    _playbackState = DlnaPlaybackState.stopped;
    _notify();

    if (reason == 'eof') {
      final q = _queue;
      if (q != null && q.hasNext) {
        await playNext();
        return;
      }
    } else if (!_everPlaying) {
      // 设备从未进入过 PLAYING 就报 STOPPED：这不是"播完"，也不是用户主动停，
      // 而是设备打不开流（转码未就绪、编码不支持、代理不可达）。以前这种情况
      // 只会静默收起投屏条，用户以为"安卓直接退出投屏"。
      await _failWith(
        _CastError('设备没能开始播放（可能是转码未就绪或编码不被支持）'),
      );
      return;
    }
    await _windDown();
  }

  Future<void> _windDown() async {
    await _cleanupSession();
    if (_disposed) return;
    _state = DlnaCastState.idle;
    _notify();
  }

  Future<void> _failWith(Object error) async {
    final text = _errorText(error);
    // 用户报「投屏完全无响应」时，唯一可用的线索就是这条原始错误。
    debugPrint('[DLNA] cast failed: $text');
    await _cleanupSession();
    if (_disposed) return;
    _state = DlnaCastState.error;
    _error = text;
    _notify();
  }

  Future<void> _cleanupSession() async {
    _stateTimer?.cancel();
    _stateTimer = null;
    final handle = _handle;
    _handle = null;
    // 预热中直接收尾（返回键 / 切歌 / 报错）：先让 Rust 取消转码任务并清理
    // 分段目录（§3），再 close。旧版 `.so` 没有 warming 阶段，不会走到这里。
    final wasWarming = _phase == 'warming' || _phase == 'failed';
    if (handle != null && wasWarming) {
      final cmdJson = jsonEncode(<String, Object?>{'cmd': 'stop'});
      await _runOnWorker(
        () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
      );
    }
    _queue?.dispose();
    _queue = null;
    _renderer = null;
    _currentItem = null;
    _position = Duration.zero;
    _duration = null;
    _playbackState = DlnaPlaybackState.stopped;
    _compatHint = null;
    _subtitleCandidates = const [];
    _selectedSubtitle = null;
    _protocolInfo = null;
    _endedForPath = null;
    _everPlaying = false;
    _error = null;
    _resetWarmupState();
    if (handle != null) {
      await _runOnWorker(() => RustCoreService.dlnaSessionClose(handle));
    }
  }

  // ── 内部：FFI 调度 ────────────────────────────────────────────────────────

  /// 在临时 isolate 中执行 [body] 并返回结果。
  ///
  /// Rust 会话门面是**同步** FFI 调用，内部包含 SSDP / SOAP 网络往返
  /// （单次 100–300 ms）。直接在主 isolate 调用会卡住帧循环（1 秒轮询尤甚），
  /// 因此所有 FFI 调用都通过 [Isolate.run] 搬到后台 isolate。
  ///
  /// [body] 只能捕获可跨 isolate 传递的值（String / int 等），不能引用 `this`。
  Future<T?> _runOnWorker<T>(FutureOr<T> Function() body) async {
    try {
      return await Isolate.run<T>(body);
    } catch (e) {
      debugPrint('[DLNA] FFI worker error: $e');
      return null;
    }
  }

  // ── 内部：状态解析 ────────────────────────────────────────────────────────

  List<DlnaRenderer> _parseDiscovered(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    if (raw.startsWith('error:')) {
      debugPrint('[DLNA] discovery failed: $raw');
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final renderers = <DlnaRenderer>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final usn = entry['usn']?.toString() ?? '';
        final location = entry['location']?.toString() ?? '';
        if (usn.isEmpty || location.isEmpty) continue;
        // Rust 只会返回 MediaRenderer；显式过滤以兼容旧版发现结果。
        if (entry['has_avtransport'] == false) continue;
        final host = Uri.tryParse(location)?.host ?? '';
        final friendlyName =
            _nonEmpty(entry['friendly_name']) ??
            (host.isNotEmpty ? host : usn);
        renderers.add(
          DlnaRenderer(
            usn: usn,
            friendlyName: friendlyName,
            location: location,
            controlUrl: '',
            connMgrControlUrl: '',
            host: host,
            modelName: _nonEmpty(entry['model_name']),
            manufacturer: _nonEmpty(entry['manufacturer']),
            modelNumber: _nonEmpty(entry['model_number']),
            sinkProtocolInfo: _stringList(entry['sink_protocol_info']),
          ),
        );
      }
      return renderers;
    } catch (e) {
      debugPrint('[DLNA] discovery JSON parse failed: $e');
      return const [];
    }
  }

  DlnaCompatibilityHint? _compatFrom(Object? raw) {
    if (raw is! Map) return null;
    if (raw['requires_transcode'] != true) {
      return const DlnaCompatibilityHint();
    }
    final reason = (raw['reason']?.toString() ?? '').toLowerCase();
    final needsAudio = reason.contains('audio');
    final needsVideo = reason.contains('video');
    final needsRemux =
        reason.contains('container') || reason.contains('remux');
    if (!needsAudio && !needsVideo && !needsRemux) {
      // 原因未知但对端确实需要转码：保守地提示全部维度。
      return const DlnaCompatibilityHint(
        likelyNeedsRemux: true,
        likelyNeedsVideoTranscode: true,
        likelyNeedsAudioTranscode: true,
      );
    }
    return DlnaCompatibilityHint(
      likelyNeedsRemux: needsRemux,
      likelyNeedsVideoTranscode: needsVideo,
      likelyNeedsAudioTranscode: needsAudio,
    );
  }

  List<SidecarHit> _candidatesFrom(Object? raw) {
    if (raw is! List) return const [];
    final videoName = _currentItem?.name;
    final hits = <SidecarHit>[];
    for (final entry in raw) {
      final hit = _hitFromJson(entry, videoName: videoName);
      if (hit != null) hits.add(hit);
    }
    return hits;
  }

  /// 把 Rust 回传的 `{name,path,lang}` 还原成 UI 需要的 [SidecarHit]。
  SidecarHit? _hitFromJson(Object? raw, {String? videoName}) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString() ?? '';
    final path = raw['path']?.toString() ?? '';
    if (name.isEmpty || path.isEmpty) return null;
    final lang = raw['lang']?.toString() ?? '';
    final match = videoName == null
        ? null
        : matchSubtitleFileName(
            videoFileName: videoName,
            subtitleFileName: name,
          );
    return SidecarHit(
      name: name,
      path: path,
      language: match?.language ??
          (lang.trim().isEmpty ? '默认' : displaySubtitleLanguage(lang)),
      languageKey: match?.languageKey ?? uiSubtitleLanguageKey(lang),
      format: match?.format ?? _extensionOf(name),
      exact: match?.exact ?? false,
      size: _asInt(raw['size']),
    );
  }

  SidecarHit? _findCandidate(String path) {
    for (final hit in _subtitleCandidates) {
      if (hit.path == path) return hit;
    }
    return null;
  }

  DlnaPlaybackState? _playbackFromTransport(String? transport) {
    switch (transport) {
      case 'PLAYING':
        return DlnaPlaybackState.playing;
      case 'PAUSED_PLAYBACK':
        return DlnaPlaybackState.paused;
      case 'TRANSITIONING':
        return DlnaPlaybackState.buffering;
      case 'STOPPED':
      case 'NO_MEDIA_PRESENT':
        return DlnaPlaybackState.stopped;
      default:
        return null;
    }
  }

  // ── 内部：预热 / 转码遥测（契约 §3、§7.5）────────────────────────────────

  /// 重置 §3 预热字段与 §7.5 遥测字段（新会话 / 切歌 / 收尾时调用）。
  void _resetWarmupState() {
    _phase = 'idle';
    _encodeSpeed = 0;
    _encodeContentMs = 0;
    _playlistReady = false;
    _segments = 0;
    _estimatedRealtime = null;
    _warmupError = null;
    _encodeMode = '';
    _videoEncoder = null;
    _audioEncoder = null;
    _encodeWarnings = const [];
    _diagnostics = const [];
    _castInFlight = false;
  }

  /// 合并一次 Rust 会话 JSON（start 响应 / state tick）里的预热字段。
  ///
  /// 所有字段都可缺失，**绝不**抛异常：
  /// * `phase` 缺失（旧版 `.so`）或为 null → 按 `playing` 降级，不把用户困在
  ///   预热界面里；
  /// * 速度 / 播放列表就绪 / 编码器 / 警告 / 诊断缺省时保持原值，UI 自动隐藏。
  void _applyWarmupFields(Map<String, dynamic> json) {
    final phase = _nonEmpty(json['phase']);
    // 旧版 `.so` 不返回 phase：直接当作已在播放。
    _phase = phase ?? 'playing';

    final speed = _asDouble(json['encode_speed']);
    if (speed != null && speed >= 0) _encodeSpeed = speed;

    final contentMs = _asInt(json['encode_content_ms']);
    if (contentMs != null && contentMs >= 0) _encodeContentMs = contentMs;

    final segments = _asInt(json['segments']);
    if (segments != null && segments >= 0) _segments = segments;

    if (json.containsKey('playlist_ready')) {
      _playlistReady = json['playlist_ready'] == true;
    }
    // null = 采样不足（encode_content_ms < 3000），必须保留 null 让 UI 显示「测速中」。
    if (json.containsKey('estimated_realtime')) {
      _estimatedRealtime = _asBool(json['estimated_realtime']);
    }

    final mode = _nonEmpty(json['encode_mode']);
    if (mode != null) _encodeMode = mode;
    if (json.containsKey('video_encoder')) {
      _videoEncoder = _nonEmpty(json['video_encoder']);
    }
    if (json.containsKey('audio_encoder')) {
      _audioEncoder = _nonEmpty(json['audio_encoder']);
    }
    if (json.containsKey('encode_warnings')) {
      _encodeWarnings = _stringList(json['encode_warnings']) ?? const [];
    }
    if (json.containsKey('diagnostics')) {
      _diagnostics = _stringList(json['diagnostics']) ?? const [];
    }
    if (json.containsKey('error')) {
      _warmupError = _nonEmpty(json['error']);
    }
  }

  Map<String, dynamic>? _decodeJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('error:')) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('[DLNA] invalid JSON from Rust: $e');
      return null;
    }
  }

  /// 会话命令是否成功。
  ///
  /// Rust 成功时返回字面量 `"ok"`；失败时返回 `{"ok":false,"error":"…"}`
  /// JSON（**不是** `"error:…"` 前缀）。为兼容旧版 `.so` 仍接受后者。
  bool _isOk(String? raw) {
    if (raw == null) return false;
    if (raw == 'ok') return true;
    final json = _decodeJson(raw);
    if (json != null) return json['ok'] == true;
    return !raw.startsWith('error:');
  }

  String _cmdError(String? raw) {
    if (raw == null) return '原生投屏模块不可用';
    final err = _decodeJson(raw)?['error']?.toString();
    if (err != null && err.isNotEmpty) return err;
    if (raw.startsWith('error:')) return raw.substring('error:'.length);
    return raw;
  }

  String _sessionError(String? raw, Map<String, dynamic>? json) {
    final err = json?['error']?.toString();
    if (err != null && err.isNotEmpty) return err;
    if (raw == null || raw.isEmpty) {
      return '原生投屏模块不可用（libwdmm_ffi 缺少 DLNA 会话接口）';
    }
    return raw;
  }

  String _errorText(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  String? _nonEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    final out = <String>[];
    for (final item in value) {
      final text = item?.toString() ?? '';
      if (text.isNotEmpty) out.add(text);
    }
    return out.isEmpty ? null : out;
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _parentPath(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : '/';
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
