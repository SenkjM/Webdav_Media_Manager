import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/codec_capability.dart';

/// 安卓原生编码器能力探测结果的整体状态。
enum CodecCapabilityStatus {
  /// 还没探测过（首次读取时由 [CodecCapabilityService.load] 触发）。
  idle,

  /// 正在探测。
  loading,

  /// 探测成功，[CodecCapabilityService.encoders] 可用。
  ready,

  /// 探测不可用（非 Android、旧包没有通道、原生查询抛异常…）。
  ///
  /// 失败是**正常降级**：查询接口返回「放行」，UI 不置灰任何选项，
  /// 实际编码能力仍由 Rust 在开始编码时判定。
  failed,
}

/// 硬件编码器能力查询服务（契约 `preset-rate-control-and-codec-probe` §13.4）。
///
/// 只读、懒加载、全进程一份缓存：
///
/// ```dart
/// final caps = CodecCapabilityService.shared;
/// await caps.load();
/// if (!caps.supportsHw('hevc_mediacodec')) { /* 置灰 H.265 硬编 */ }
/// ```
///
/// 使用约定：
/// * 调用 [supportsHw] / [supportsRateControl] 前先 `await load()`；未加载或
///   探测失败时两者都返回 `true`（保守放行，绝不挡住投屏/转码）。
/// * 探测成功但机型**没有**某个编码器时，[supportsHw] 返回 `false`、
///   [supportsRateControl] 返回 `false`，用于置灰/隐藏对应选项。
/// * 这里的结果永远只是提示：Rust 以「真开一次编码器」为最终判据。
class CodecCapabilityService extends ChangeNotifier {
  CodecCapabilityService();

  /// 设置页与转码预设编辑器共用的实例（探测结果全进程只需一份）。
  static final CodecCapabilityService shared = CodecCapabilityService();

  /// 与 Kotlin `CodecCapsProbe.CHANNEL` 保持一致。
  static const MethodChannel _channel = MethodChannel('wdmm/codec_caps');

  /// 原生查询通常 10–40 ms；超过这个时间视为探测不可用，避免卡住 UI。
  static const Duration _probeTimeout = Duration(seconds: 3);

  CodecCapabilityStatus _status = CodecCapabilityStatus.idle;
  List<CodecCapability> _encoders = const <CodecCapability>[];
  final Map<String, List<CodecCapability>> _grouped =
      <String, List<CodecCapability>>{};
  final Map<String, CodecCapability> _preferred = <String, CodecCapability>{};
  String? _error;
  Future<void>? _inFlight;

  CodecCapabilityStatus get status => _status;

  bool get isLoading => _status == CodecCapabilityStatus.loading;

  /// 探测成功且至少拿到一个可识别的视频编码器。
  bool get isReady => _status == CodecCapabilityStatus.ready;

  /// 探测是否给出了可信答案；false 时所有查询接口保守放行。
  bool get probeUsable => isReady && _encoders.isNotEmpty;

  /// 探测失败的原因（仅用于 UI 说明行），成功时为 null。
  String? get error => _error;

  /// 已识别的编码器（只含 [knownHwCodecIds] 覆盖的三种 mime）。
  List<CodecCapability> get encoders => List<CodecCapability>.unmodifiable(_encoders);

  /// 某个编码器 id 下的全部实现（硬编优先排序）。
  List<CodecCapability> encodersFor(String codecId) =>
      List<CodecCapability>.unmodifiable(
        _grouped[codecId] ?? const <CodecCapability>[],
      );

  /// 某个编码器 id 的「代表实现」：有硬编取硬编，否则取第一个软编。
  CodecCapability? capabilitiesFor(String codecId) => _preferred[codecId];

  /// 该机型是否声明有 [codecId] 的硬件编码器。
  ///
  /// 探测不可用时返回 true（保守放行）。
  bool supportsHw(String codecId) {
    if (!probeUsable) return true;
    return capabilitiesFor(codecId)?.hardware ?? false;
  }

  /// 该机型是否声明 [codecId] 支持 [mode]（`cbr` / `vbr` / `cq`）。
  ///
  /// 探测不可用或编码器未报告码率模式时返回 true（保守放行）；
  /// 只有探测成功且机型明确不支持时才返回 false。
  bool supportsRateControl(String codecId, String mode) {
    if (!probeUsable) return true;
    final cap = capabilitiesFor(codecId);
    if (cap == null) return false;
    return cap.supportsRateControl(mode);
  }

  /// 懒加载：已就绪 / 已失败时直接返回，除非 [force]。
  Future<void> load({bool force = false}) async {
    final running = _inFlight;
    if (running != null) return running;
    if (!force && _status != CodecCapabilityStatus.idle) return;
    final future = _probe(force: force);
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }

  /// 重新探测（设置页「重新探测」按钮）。
  Future<void> refresh() => load(force: true);

  Future<void> _probe({required bool force}) async {
    _status = CodecCapabilityStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final raw = await _channel
          .invokeMethod<String>('listEncoders', force)
          .timeout(_probeTimeout);
      final decoded = _decodePayload(raw);
      if (decoded == null) {
        _fail('原生编码能力查询返回空结果');
        return;
      }
      _apply(decoded);
    } on MissingPluginException {
      // 非 Android / 旧包：正常降级，不影响任何功能。
      _fail('当前平台不支持原生编码能力查询');
    } on PlatformException catch (e) {
      _fail('${e.code}: ${e.message ?? ''}'.trim());
    } on TimeoutException {
      _fail('原生编码能力查询超时');
    } catch (e) {
      _fail('$e');
    } finally {
      _status = _status == CodecCapabilityStatus.loading
          ? CodecCapabilityStatus.failed
          : _status;
      notifyListeners();
    }
  }

  /// 解析原生返回的 JSON（对象 `{ok,encoders}` 或裸数组）。
  ///
  /// 返回 null 表示探测失败或载荷不可用；空列表是合法结果（机型没报编码器）。
  List<CodecCapability>? _decodePayload(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // 原生侧返回的不是 JSON：视为探测失败。
      return null;
    }
    Object? list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      if (decoded['ok'] == false) {
        final message = decoded['error']?.toString();
        if (message != null && message.isNotEmpty) _error = message;
        return null;
      }
      list = decoded['encoders'];
    }
    if (list is! List) return null;
    final parsed = <CodecCapability>[];
    for (final item in list) {
      final cap = CodecCapability.fromJson(item);
      if (cap != null) parsed.add(cap);
    }
    return parsed;
  }

  void _apply(List<CodecCapability> encoders) {
    _encoders = encoders;
    _grouped
      ..clear()
      ..addAll(_groupByCodec(encoders));
    _preferred
      ..clear()
      ..addAll(_preferredByCodec(_grouped));
    _status = CodecCapabilityStatus.ready;
    _error = null;
  }

  void _fail(String message) {
    _encoders = const <CodecCapability>[];
    _grouped.clear();
    _preferred.clear();
    // 原生侧回传了具体原因（`{"ok":false,"error":…}`）时优先保留它。
    _error ??= message;
    _status = CodecCapabilityStatus.failed;
  }

  static Map<String, List<CodecCapability>> _groupByCodec(
    List<CodecCapability> encoders,
  ) {
    final grouped = <String, List<CodecCapability>>{};
    for (final id in knownHwCodecIds) {
      grouped[id] = <CodecCapability>[];
    }
    for (final cap in encoders) {
      (grouped[cap.codecId] ??= <CodecCapability>[]).add(cap);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        if (a.hardware != b.hardware) return a.hardware ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    }
    return grouped;
  }

  static Map<String, CodecCapability> _preferredByCodec(
    Map<String, List<CodecCapability>> grouped,
  ) {
    final preferred = <String, CodecCapability>{};
    for (final entry in grouped.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;
      // 列表已按「硬编优先」排序，第一条即代表实现。
      preferred[entry.key] = list.first;
    }
    return preferred;
  }
}
