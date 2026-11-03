import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Rust 回传的 `subtitle_status`（契约 task-11 §6）。
///
/// 字幕准备状态：源文件里有多少内置文本 / 位图字幕轨，以及被降级时给用户看
/// 的提示。旧版 `.so` 不返回该字段，此时 getter 为 null，UI 不显示任何提示。
class DlnaSubtitleStatus {
  const DlnaSubtitleStatus({
    this.textTracks = 0,
    this.bitmapTracks = 0,
    this.bitmapNote,
    this.message,
  });

  /// 源文件中的内置**文本**字幕轨数量（direct 模式不探测，恒为 0）。
  final int textTracks;

  /// 源文件中的内置**位图**字幕轨数量（direct 模式不探测，恒为 0）。
  final int bitmapTracks;

  /// 位图字幕被丢弃的说明（HLS 投屏无法显示 PGS/DVD）；null = 无。
  final String? bitmapNote;

  /// 字幕准备降级说明（侧车扫描超时 / 提取失败等）；null = 无。
  final String? message;

  /// 是否有需要展示给用户的提示。
  bool get hasNotice => message != null || bitmapNote != null;
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
  /// Rust 回传的字幕准备状态（契约 task-11 §6）；旧版 `.so` 为 null。
  DlnaSubtitleStatus? _subtitleStatus;

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

  /// 会话类型：`hls`（转码）/ `direct`（直通）；未知时为空串。
  ///
  /// 直通会话没有转码作业（Rust 仍会报 `run_state:"idle"`），播放态遥测行
  /// 因此按它隐藏，避免在直通投屏上显示「闲置」这种误导性状态。
  String get provider => _provider;

  /// 是否正在建立投屏会话（已点投送、Rust 尚未返回 `phase:"warming"`）。
  ///
  /// UI 用它立刻渲染预热面板的「正在准备缓存预热…」状态（契约 task-21 §1）。
  bool get preparing => _preparing;

  /// Rust 上报的媒体类型：`audio` 为纯音频投送；空串/未知按视频处理。
  String get mediaKind => _mediaKind;

  /// 纯音频投送（契约 task-21 §3）：字幕等视频专属控件应隐藏。
  bool get isAudioOnly => _mediaKind == 'audio';

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

  // --- HLS 点播化遥测（契约 hls-vod-transcode-cache §4）---

  /// 转码速度（内容时间 / 墙钟时间）；>= 1 表示能实时产出，0 = 无数据。
  double get transcodeSpeed => _encodeSpeed;

  /// 按需转码运行状态：`active` / `idle` / `error`；空串 = 旧版 `.so` 或直通。
  String get runState => _runState;

  /// 定位对齐方式的中文标签（精确网格 / 关键帧）；未知为空串。
  ///
  /// Rust 只会上报 `exact` / `keyframe`：整份计划在会话建立前就由
  /// `source_plan` 固定，没有测量标定或近似网格这两档了。
  String get alignmentLabel {
    switch (_alignment) {
      case 'exact':
        return '精确网格';
      case 'keyframe':
        return '关键帧';
      default:
        return '';
    }
  }

  /// 当前会话已用的转码缓存字节数。
  int get cacheBytes => _cacheBytes;

  /// 分段计划：总片段数 / 每段秒数（旧版 `.so` 为 0）。
  int get segCount => _segCount;
  double get segSecs => _segSecs;

  /// 已落盘分片数 / 预转窗口分片数 / 缓存命中次数 / 是否超出预算。
  int get readySegments => _readySegments;
  int get lookaheadSegments => _lookaheadSegments;
  int get cacheHits => _cacheHits;
  bool get cacheOverBudget => _cacheOverBudget;

  /// 本次运行的产出位置与计划网格的偏差（毫秒，绝对值不超过一个分片）。
  int get driftMs => _driftMs;

  /// 当前视频的字幕候选列表（Rust 匹配结果）。
  List<SidecarHit> get subtitleCandidates =>
      List.unmodifiable(_subtitleCandidates);

  /// 当前选中的字幕，null 表示无字幕。
  SidecarHit? get selectedSubtitle => _selectedSubtitle;

  /// 字幕准备状态 / 降级提示；null 表示旧版 `.so` 未提供或当前无会话。
  DlnaSubtitleStatus? get subtitleStatus => _subtitleStatus;

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
  /// 会话类型：`hls` / `direct`（来自 start / state 的 `provider`）。
  String _provider = '';

  /// 用户刚点「投送」、会话尚未建立完成的乐观状态（契约 task-21 §1）。
  ///
  /// 真正的阶段仍以 Rust 的 `phase` 为准；这个标志只是让预热面板立刻出现，
  /// 不必对着一个裸转圈等 driver / 代理 / 时长探测 / 字幕扫描。
  bool _preparing = false;

  /// 会话代次：每次 `_cleanupSession()` 自增，用来丢弃「取消后才返回」的句柄。
  int _castEpoch = 0;

  /// Rust 上报的媒体类型：`video` / `audio`（契约 task-21 §3）。
  ///
  /// 旧版 `.so` 不返回该字段，保持空串 → 按视频处理。
  String _mediaKind = '';

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

  // --- 内部：HLS 点播化遥测（契约 hls-vod-transcode-cache §4）---
  /// 按需转码运行状态：`active`（正在转码）/ `idle`（已追平，等播放推进）/
  /// `error`；旧版 `.so` 或直通会话为空串。
  String _runState = '';
  /// 分段计划：总片段数与每段秒数（旧版 `.so` 为 0）。
  int _segCount = 0;
  double _segSecs = 0;
  /// 已落盘分片数 / 预转窗口分片数。
  int _readySegments = 0;
  int _lookaheadSegments = 0;
  /// 定位对齐方式：`exact` / `keyframe`；旧版 `.so` 为空串。
  String _alignment = '';
  /// 产出位置与计划网格的偏差（毫秒），正负都可能。
  int _driftMs = 0;
  /// 本次会话的转码缓存命中次数 / 缓存字节数 / 是否超出预算。
  int _cacheHits = 0;
  int _cacheBytes = 0;
  bool _cacheOverBudget = false;
  /// 会话配置里的缓存父目录（`<平台 cache_dir>`），首次会话时解析一次。
  String? _resolvedCacheDir;

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
    // 乐观 UI（契约 task-21 §1）：点下去立刻显示预热面板。会话建立要等
    // driver / 代理 / 时长探测 / 字幕扫描，不能让用户对着裸转圈干等；
    // 随后由 Rust 的 `phase:"warming"` 接管。
    _state = DlnaCastState.casting;
    _renderer = renderer;
    _error = null;
    _preparing = true;
    _notify();

    await _cleanupSession();
    if (_disposed) return;

    // cleanup 会把预热状态清空，重新建立乐观状态。
    _preparing = true;
    _renderer = renderer;
    _error = null;
    final epoch = _castEpoch;

    final effAccountId = accountId ?? seed!.accountId;
    final initial = singleItem ?? seed!.current;
    final siblings = seed?.siblings ?? const <WebDavItem>[];
    final queue = DlnaQueueController(
      webDav: _webDav,
      accountId: effAccountId,
      rootPath: seed?.folderPath ?? _parentPath(initial.path),
      seed: siblings.isNotEmpty ? siblings : [initial],
      initialRemotePath: initial.path,
      // 音频投送也走同一个队列：只按当前条目的类别过滤同名扫描结果。
      category: initial.category,
    );
    _queue = queue;
    _state = DlnaCastState.casting;
    _notify();
    if (epoch != _castEpoch) {
      queue.dispose();
      return;
    }
    queue.startScan();

    try {
      await _beginItem(initial, effAccountId, first: true, epoch: epoch);
    } catch (e) {
      if (epoch != _castEpoch) return;
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

  /// 进入「选择投屏设备」搜索前调用：销毁上一次投屏残留的会话与 UI 状态。
  ///
  /// 复用 [stop] 的既有收尾路径（`{"cmd":"stop"}` → `dlnaSessionClose` →
  /// 代次自增），再把设备列表与本地状态收回 idle：搜索面板出现的那一刻就
  /// 不应该还看到上一次投屏的小窗 / 底部投屏条 / 预热面板 / 进度条 / 队列。
  Future<void> prepareForDeviceSearch() async {
    if (_disposed) return;
    await stop();
    if (_disposed) return;
    // 进行中的旧发现窗口不再需要，避免搜索面板闪回上一次的设备列表。
    _discoveryEpoch++;
    unawaited(DlnaCastChannel.stop());
    _discovered.clear();
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
      final message = _cmdError(raw);
      debugPrint('[DLNA] seek rejected: $raw');
      // 会话已经不存在说明投屏整体已经结束（本机代理/渲染器这边都没了），
      // 静默返回会让用户以为进度条坏了，所以明确报错并收尾。
      if (message.contains('session')) {
        await _failWith(_CastError('投屏会话已结束，请重新投屏'));
        return;
      }
      // 其余情况是渲染器暂时拒收（例如还在预热/切段），保持旧实现的静默处理。
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
  ///
  /// 返回 `null` 表示成功；返回非空字符串表示失败原因，调用方（字幕弹窗）
  /// 用 SnackBar 展示，**不再静默失败**。位图字幕（PGS/DVD）Rust 会明确拒绝
  /// （`{"ok":false,"error":…,"support":"bitmap-unsupported"}`，契约 §5），
  /// 这里翻译成中文提示；即使 UI 已禁用该行也要有兜底。
  Future<String?> selectSubtitle(SidecarHit? hit) async {
    final handle = _handle;
    if (handle == null || _currentItem == null) {
      return '投屏会话已结束';
    }
    // path 必须原样回传：内置字幕是 `<remote_path>#embedded:<index>`，
    // 不要重新推导或做 URL 编码（契约 §4）。
    final cmdJson = jsonEncode(<String, Object?>{
      'cmd': 'subtitle',
      'path': hit?.path,
    });
    final raw = await _runOnWorker(
      () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
    );
    if (!_isOk(raw)) {
      final message = _subtitleErrorText(raw);
      debugPrint('[DLNA] subtitle select failed: $raw');
      _error = message;
      _notify();
      return message;
    }
    _selectedSubtitle = hit;
    _error = null;
    _notify();
    return null;
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

  /// 解析会话配置里的缓存根目录（`<平台 cache_dir>/transcode`，契约 §3.5）。
  ///
  /// Rust 的 `cache_dir` 就是缓存根目录本身（缺省 `<temp>/wdmm-transcode`），
  /// 所以这里显式加上 `transcode` 叶子目录，避免把分片直接撒在应用缓存根上。
  /// 只解析一次；失败返回 null，让 Rust 用自己的默认目录（旧 `.so` 忽略该键）。
  Future<String?> _resolveCacheDir() async {
    final cached = _resolvedCacheDir;
    if (cached != null) return cached;
    try {
      final dir = await getApplicationCacheDirectory();
      final root = p.join(dir.path, 'transcode');
      _resolvedCacheDir = root;
      return root;
    } catch (e) {
      debugPrint('[DLNA] cache dir unavailable: $e');
      return null;
    }
  }

  Future<void> _beginItem(
    WebDavItem item,
    String accountId, {
    required bool first,
    int? epoch,
  }) async {
    final renderer = _renderer;
    if (renderer == null) return;
    final token = epoch ?? _castEpoch;

    _currentItem = item;
    _position = Duration.zero;
    _duration = null;
    _playbackState = DlnaPlaybackState.buffering;
    _endedForPath = null;
    _everPlaying = false;
    _subtitleCandidates = const [];
    _selectedSubtitle = null;
    _subtitleStatus = null;
    _resetWarmupState();
    // 切到新条目同样要先亮「正在准备缓存预热…」，等 Rust 返回 phase 再切走。
    _preparing = true;
    _notify();

    final prefs = _dmrPrefs[renderer.usn];
    final forceDirect = prefs?.forceDirect ?? true;
    // 直通（不转码）只由 forceDirect 开关表达：`passthrough` 不是转码预设，
    // 不允许经 `preset_id` 偷偷走直通，否则就绕过了兼容开关。
    final presetId =
        forceDirect ? null : _effectivePresetId(prefs?.presetId);

    final handle = _handle;
    if (first || handle == null) {
      // §3.5 转码缓存：Dart 传缓存根目录（`<cache>/transcode`），预算随会话
      // 下发；`cache_ident`（mtime）让同一源文件的第二次投屏直接复用分片。
      final cacheDir = await _resolveCacheDir();
      final cacheIdent = item.modified?.millisecondsSinceEpoch.toString() ?? '';
      final config = <String, Object?>{
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
        'cache_budget_mb': _settings.transcodeCacheBudgetMb,
        'cache_ident': cacheIdent,
        'ui_lang': _settings.appLocale.locale?.languageCode ?? '',
      };
      if (cacheDir != null && cacheDir.isNotEmpty) {
        config['cache_dir'] = cacheDir;
      }
      final configJson = jsonEncode(config);
      final raw = await _runOnWorker(
        () => RustCoreService.dlnaSessionStart(configJson),
      );
      final json = _decodeJson(raw);
      if (token != _castEpoch) {
        // 建立会话期间用户已取消（点「取消」/ 断开 / 切歌）：把晚到的 Rust
        // 会话收掉，否则预热作业会在后台继续跑。
        final lateHandle = _asInt(json?['handle']);
        if (lateHandle != null) await _discardSession(lateHandle);
        return;
      }
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
      final provider = _nonEmpty(json['provider']);
      if (provider != null) _provider = provider;
      final compat = _compatFrom(json['compat']);
      if (compat != null) _compatHint = compat;
      // 启动响应里的 `phase`（旧版 `.so` 没有 → 降级为 playing）。
      _applyWarmupFields(json);
      _applySubtitleStatus(json);
      _startStateTimer();
    } else {
      // §3.5：切集时缓存标识跟着新文件走，否则 Rust 把该文件当一次性条目。
      final cmdJson = jsonEncode(<String, Object?>{
        'cmd': 'select',
        'remote_path': item.path,
        'name': item.name,
        'size': item.size ?? 0,
        'preset_id': presetId,
        'cache_ident': item.modified?.millisecondsSinceEpoch.toString() ?? '',
      });
      final raw = await _runOnWorker(
        () => RustCoreService.dlnaSessionCmd(handle, cmdJson),
      );
      if (token != _castEpoch) return;
      if (!_isOk(raw)) {
        debugPrint('[DLNA] select failed: $raw');
        throw _CastError(_cmdError(raw));
      }
    }

    if (_disposed || token != _castEpoch) return;
    // 预热阶段（§3）还没投送：保持 buffering，UI 由「预热/预检」面板接管。
    _playbackState = _phase == 'warming'
        ? DlnaPlaybackState.buffering
        : DlnaPlaybackState.playing;
    _preparing = false;
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
    _applySubtitleStatus(json);

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

    final provider = _nonEmpty(json['provider']);
    if (provider != null) _provider = provider;

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
    await _windDown(reason: 'ended: ${reason ?? 'unknown'}');
  }

  Future<void> _windDown({String reason = 'wind-down'}) async {
    await _cleanupSession(reason: reason);
    if (_disposed) return;
    _state = DlnaCastState.idle;
    _notify();
  }

  Future<void> _failWith(Object error) async {
    final text = _errorText(error);
    // 用户报「投屏完全无响应」时，唯一可用的线索就是这条原始错误。
    debugPrint('[DLNA] cast failed: $text');
    await _cleanupSession(reason: 'failed: $text');
    if (_disposed) return;
    _state = DlnaCastState.error;
    _error = text;
    _notify();
  }

  Future<void> _cleanupSession({String reason = 'unspecified'}) async {
    // 代次自增：正在建立会话的 startCast/_beginItem 会在 await 之后发现
    // 代次已变，丢弃晚到的句柄（见 _discardSession）。
    _castEpoch++;
    _stateTimer?.cancel();
    _stateTimer = null;
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      // 「seek 时报 unknown session handle」这类丢失会话现场的问题，只能靠这条
      // 日志定位是谁先收的尾（失败 / 播完 / 用户停止）。
      debugPrint('[DLNA] session teardown: handle=$handle reason=$reason');
    }
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
    _subtitleStatus = null;
    _protocolInfo = null;
    _provider = '';
    _endedForPath = null;
    _everPlaying = false;
    _error = null;
    _resetWarmupState();
    if (handle != null) {
      await _runOnWorker(() => RustCoreService.dlnaSessionClose(handle));
    }
  }

  /// 丢弃一个「取消后才返回」的 Rust 会话（`start` 在用户取消之后才完成）。
  ///
  /// 先 `{"cmd":"stop"}` 让 Rust 取消预热作业并清理分段（§3），再 close，
  /// 避免取消投屏后后台还在转码。
  Future<void> _discardSession(int handle) async {
    debugPrint('[DLNA] discarding late session: handle=$handle');
    final cmdJson = jsonEncode(<String, Object?>{'cmd': 'stop'});
    await _runOnWorker(() => RustCoreService.dlnaSessionCmd(handle, cmdJson));
    await _runOnWorker(() => RustCoreService.dlnaSessionClose(handle));
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

  /// 把 Rust 回传的候选字幕还原成 UI 需要的 [SidecarHit]。
  ///
  /// 契约 task-11 §3：外置字幕带 `embedded:false`、`track`/`codec` 为 null、
  /// `support:"external"`；HLS 内置轨带 `embedded:true` + `track`/`codec`，
  /// `support` 为 `webvtt` 或 `bitmap-unsupported`。旧版 `.so` 只有
  /// `{name,path,lang,size}`，此时按外置字幕降级（support 为 null = 可投送）。
  ///
  /// 契约 task-21 §2：内置轨新增 `title`（容器标题）与 `language`（ISO-639
  /// 语言码）；33 条轨道时两者是唯一的人类可读区分，缺失时退回 `lang`。
  SidecarHit? _hitFromJson(Object? raw, {String? videoName}) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString() ?? '';
    final path = raw['path']?.toString() ?? '';
    if (name.isEmpty || path.isEmpty) return null;
    final lang = raw['lang']?.toString() ?? '';
    final embedded = raw['embedded'] == true;
    final codec = _nonEmpty(raw['codec']);
    final support = _nonEmpty(raw['support']);
    final title = _nonEmpty(raw['title']);
    final languageCode =
        _nonEmpty(raw['language']) ?? _nonEmpty(raw['language_code']);
    // 内置轨优先展示中文语言名（ISO-639 码 → 中文），外置字幕仍用文件名解析。
    final languageLabel =
        subtitleLanguageName(languageCode ?? lang) ??
            (lang.trim().isEmpty ? null : displaySubtitleLanguage(lang));
    // 内置轨的 name 形如 `zh (ass, embedded)`，不能拿去匹配 sidecar 文件名；
    // 语言直接用 Rust 的 `lang`，展示格式用 codec。
    final match = (embedded || videoName == null)
        ? null
        : matchSubtitleFileName(
            videoFileName: videoName,
            subtitleFileName: name,
          );
    return SidecarHit(
      name: name,
      path: path,
      language: match?.language ?? languageLabel ?? '默认',
      languageKey: match?.languageKey ?? uiSubtitleLanguageKey(lang),
      format: embedded
          ? (codec ?? _extensionOf(name))
          : (match?.format ?? _extensionOf(name)),
      exact: match?.exact ?? false,
      size: _asInt(raw['size']),
      embedded: embedded,
      track: _asInt(raw['track']),
      codec: codec,
      support: support,
      title: title,
      languageCode: languageCode,
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
    // §4 HLS 点播化遥测。
    _runState = '';
    _segCount = 0;
    _segSecs = 0;
    _readySegments = 0;
    _lookaheadSegments = 0;
    _alignment = '';
    _driftMs = 0;
    _cacheHits = 0;
    _cacheBytes = 0;
    _cacheOverBudget = false;
    // 乐观 UI：预热面板由真实 phase 接管；媒体类型等 Rust 下一次上报。
    _preparing = false;
    _mediaKind = '';
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
    // Rust 已经报告真实阶段，乐观的「准备预热」状态让位。
    _preparing = false;

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

    // §4 HLS 点播化遥测：按需运行状态 / 定位对齐 / 缓存统计；缺失保持原值。
    final runState = _nonEmpty(json['run_state']);
    if (runState != null) _runState = runState;
    final alignment = _nonEmpty(json['alignment']);
    if (alignment != null) _alignment = alignment;
    final driftMs = _asInt(json['drift_ms']);
    if (driftMs != null && driftMs >= 0) _driftMs = driftMs;
    final segCount = _asInt(json['seg_count']);
    if (segCount != null && segCount >= 0) _segCount = segCount;
    final segSecs = _asDouble(json['seg_secs']);
    if (segSecs != null && segSecs > 0) _segSecs = segSecs;
    final readySegments = _asInt(json['ready_segments']);
    if (readySegments != null && readySegments >= 0) {
      _readySegments = readySegments;
    }
    final lookahead = _asInt(json['lookahead_segments']);
    if (lookahead != null && lookahead >= 0) _lookaheadSegments = lookahead;
    final cacheHits = _asInt(json['cache_hits']);
    if (cacheHits != null && cacheHits >= 0) _cacheHits = cacheHits;
    final cacheBytes = _asInt(json['cache_bytes']);
    if (cacheBytes != null && cacheBytes >= 0) _cacheBytes = cacheBytes;
    if (json.containsKey('cache_over_budget')) {
      _cacheOverBudget = json['cache_over_budget'] == true;
    }

    if (json.containsKey('error')) {
      _warmupError = _nonEmpty(json['error']);
    }

    // §3 音频投送：`media_kind:"audio"` 时 UI 隐藏字幕等视频专属控件。
    final mediaKind = _nonEmpty(json['media_kind']);
    if (mediaKind != null) _mediaKind = mediaKind;
  }

  /// 合并 `subtitle_status`（契约 task-11 §6）。
  ///
  /// 旧版 `.so` 不返回该键 → 保持 null，UI 不显示字幕提示；
  /// 非 Map 的脏值同样降级为 null，绝不抛异常。
  void _applySubtitleStatus(Map<String, dynamic> json) {
    if (!json.containsKey('subtitle_status')) return;
    final raw = json['subtitle_status'];
    if (raw is! Map) {
      _subtitleStatus = null;
      return;
    }
    _subtitleStatus = DlnaSubtitleStatus(
      textTracks: _asInt(raw['text_tracks']) ?? 0,
      bitmapTracks: _asInt(raw['bitmap_tracks']) ?? 0,
      bitmapNote: _nonEmpty(raw['bitmap_note']),
      message: _nonEmpty(raw['message']),
    );
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

  /// 字幕命令失败原因：位图字幕（PGS/DVD）给出中文解释，其余沿用 Rust 文本。
  String _subtitleErrorText(String? raw) {
    final support = _nonEmpty(_decodeJson(raw)?['support']);
    if (support == 'bitmap-unsupported') {
      return '位图字幕（PGS/DVD）无法通过投屏显示，请改用文本字幕或直通模式';
    }
    return _cmdError(raw);
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
