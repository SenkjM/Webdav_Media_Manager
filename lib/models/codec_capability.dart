/// 硬件编码器能力探测结果（契约 `preset-rate-control-and-codec-probe` §13.4）。
///
/// 数据来自安卓原生 `MediaCodecList` 的只读查询（Kotlin `CodecCapsProbe`），
/// **只服务 UI 置灰/隐藏**：Rust 在真正开始编码时才以「真开一次编码器」为
/// 最终判据，因此这里任何缺失的字段都按「未知」处理，不能当成「不支持」。
library;

/// Rust schema 中的硬件编码器 id → MediaCodec mime。
///
/// 与 `crates/wdmm-core` 的 `hw_video_encoder` 取值一一对应，两边必须一致。
const Map<String, String> hwCodecIdToMime = <String, String>{
  'h264_mediacodec': 'video/avc',
  'hevc_mediacodec': 'video/hevc',
  'mpeg4_mediacodec': 'video/mp4v-es',
};

/// 界面展示顺序（与 Rust schema 的三档硬编 id 一致）。
const List<String> knownHwCodecIds = <String>[
  'h264_mediacodec',
  'hevc_mediacodec',
  'mpeg4_mediacodec',
];

/// mime → Rust 编码器 id；不认识（vp8/vp9/av1/…）返回 null。
String? hwCodecIdForMime(String? mime) {
  if (mime == null || mime.isEmpty) return null;
  for (final entry in hwCodecIdToMime.entries) {
    if (entry.value == mime) return entry.key;
  }
  return null;
}

/// 一个闭区间，用于码率 / 分辨率 / 帧率范围。
class CodecRange {
  const CodecRange(this.min, this.max);

  final num min;
  final num max;

  @override
  String toString() => '$min – $max';
}

/// 单个编码器（某个 mime 下的一条 MediaCodec 实现）的能力快照。
class CodecCapability {
  const CodecCapability({
    required this.codecId,
    required this.mime,
    required this.name,
    required this.hardware,
    this.bitrateModes,
    this.bitrateRange,
    this.widthRange,
    this.heightRange,
    this.widthAlignment,
    this.heightAlignment,
    this.fpsRange,
    this.profileLevels = const <String>[],
  });

  /// Rust schema 里的编码器 id（[knownHwCodecIds] 之一）。
  final String codecId;

  /// MediaCodec mime，例如 `video/avc`。
  final String mime;

  /// 编码器实现名，例如 `c2.qti.avc.encoder`。
  final String name;

  /// `CodecCapabilities.isHardwareAccelerated()`（API < 29 用命名启发式）。
  final bool hardware;

  /// 支持的码率控制模式（`cbr` / `vbr` / `cq`）；null = 机型未报告。
  final List<String>? bitrateModes;

  /// 支持的码率区间（bps）；null = 机型未报告。
  final CodecRange? bitrateRange;

  /// 支持的分辨率区间（像素）；null = 机型未报告。
  final CodecRange? widthRange;
  final CodecRange? heightRange;

  /// 宽 / 高对齐要求（像素）；null = 机型未报告。
  final int? widthAlignment;
  final int? heightAlignment;

  /// 支持的帧率区间；null = 机型未报告。
  final CodecRange? fpsRange;

  /// Profile-Level 组合的可读标签，例如 `avc.profileHigh.level5.1`。
  final List<String> profileLevels;

  /// 该机型是否声明支持某个码率控制模式。
  ///
  /// 机型未报告 [bitrateModes] 时返回 true（保守放行），只有明确报告了
  /// 一组模式且不含 [mode] 时才返回 false。
  bool supportsRateControl(String mode) {
    final modes = bitrateModes;
    if (modes == null) return true;
    final needle = mode.toLowerCase();
    return modes.any((m) => m.toLowerCase() == needle);
  }

  /// 解析 Kotlin 侧 `listEncoders` 的单条记录；非 video 或未知 mime 返回 null。
  static CodecCapability? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final mime = raw['mime']?.toString() ?? '';
    final codecId = hwCodecIdForMime(mime);
    if (codecId == null) return null;
    return CodecCapability(
      codecId: codecId,
      mime: mime,
      name: raw['name']?.toString() ?? '',
      hardware: raw['hardware'] == true,
      bitrateModes: _stringList(raw['bitrate_modes']),
      bitrateRange: _range(raw['bitrate_range']),
      widthRange: _range(raw['width_range']),
      heightRange: _range(raw['height_range']),
      widthAlignment: _int(raw['width_alignment']),
      heightAlignment: _int(raw['height_alignment']),
      fpsRange: _range(raw['fps_range']),
      profileLevels: _stringList(raw['profile_levels']) ?? const <String>[],
    );
  }

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    final out = <String>[
      for (final item in value)
        if (item != null && item.toString().isNotEmpty) item.toString(),
    ];
    return out;
  }

  static CodecRange? _range(Object? value) {
    if (value is! List || value.length < 2) return null;
    final min = _num(value[0]);
    final max = _num(value[1]);
    if (min == null || max == null) return null;
    return CodecRange(min, max);
  }

  static num? _num(Object? value) {
    if (value is num) return value;
    return num.tryParse('$value');
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
