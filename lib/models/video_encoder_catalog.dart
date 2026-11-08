import 'dart:convert';

/// One video encoder offered by the preset editor.
///
/// Mirrors Rust `VideoEncoderInfo` (contract `preset-editor-slimming` §2.2):
/// the editor never hard-codes encoder ids/labels, it renders this catalog.
class VideoEncoderInfo {
  /// Rust encoder id, e.g. `h264_mediacodec` / `libx264`.
  final String id;

  /// Display label from the native catalog, e.g. `H.264 硬编` / `x264（软件）`.
  final String label;

  /// `true` for MediaCodec hardware encoders.
  final bool hardware;

  /// Output codec id (`h264` / `hevc` / `mpeg4` / `mpeg2video`).
  final String outputCodec;

  /// Rate-control modes this encoder supports (`cq` / `vbr` / `cbr`).
  final List<String> rateControl;

  const VideoEncoderInfo({
    required this.id,
    required this.label,
    required this.hardware,
    this.outputCodec = '',
    this.rateControl = const [],
  });

  /// Whether this encoder advertises [mode] (`cq` / `vbr` / `cbr`).
  bool supportsRateControl(String mode) => rateControl.contains(mode);

  static VideoEncoderInfo? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final label = json['label'];
    final outputCodec = json['output_codec'];
    return VideoEncoderInfo(
      id: id,
      label: label is String && label.isNotEmpty ? label : id,
      hardware: json['hardware'] as bool? ?? false,
      outputCodec: outputCodec is String ? outputCodec : '',
      rateControl: [
        if (json['rate_control'] is List)
          for (final mode in json['rate_control'] as List)
            if (mode is String && mode.isNotEmpty) mode,
      ],
    );
  }
}

/// The video-encoder catalog returned by `wdmm_video_encoder_catalog_json()`.
///
/// The native export is optional: an older `.so` (or a malformed payload)
/// degrades to [VideoEncoderCatalog.fallback] — the same six encoders with the
/// contract §2.2 labels — so the editor never renders an empty list.
class VideoEncoderCatalog {
  /// All encoders in native order (hardware first).
  final List<VideoEncoderInfo> codecs;

  /// `true` when the installed native library predates the catalog export and
  /// the built-in fallback is being used.
  final bool isFallback;

  final Map<String, VideoEncoderInfo> _byId;

  VideoEncoderCatalog._(this.codecs, {this.isFallback = false})
      : _byId = {for (final codec in codecs) codec.id: codec};

  /// Minimal catalog used when the native export is unavailable.
  ///
  /// Labels follow contract §2.2 exactly (no “MediaCodec” wording); the rate
  /// control modes are what the encoders have always supported.
  factory VideoEncoderCatalog.fallback() {
    const hardware = [
      VideoEncoderInfo(
        id: 'h264_mediacodec',
        label: 'H.264 硬编',
        hardware: true,
        outputCodec: 'h264',
        rateControl: ['cq', 'vbr', 'cbr'],
      ),
      VideoEncoderInfo(
        id: 'hevc_mediacodec',
        label: 'H.265 硬编',
        hardware: true,
        outputCodec: 'hevc',
        rateControl: ['cq', 'vbr', 'cbr'],
      ),
      VideoEncoderInfo(
        id: 'mpeg4_mediacodec',
        label: 'MPEG-4 硬编',
        hardware: true,
        outputCodec: 'mpeg4',
        rateControl: ['cq', 'vbr', 'cbr'],
      ),
    ];
    const software = [
      VideoEncoderInfo(
        id: 'libx264',
        label: 'x264（软件）',
        hardware: false,
        outputCodec: 'h264',
        rateControl: ['cq', 'vbr', 'cbr'],
      ),
      VideoEncoderInfo(
        id: 'mpeg2video',
        label: 'MPEG-2（软件）',
        hardware: false,
        outputCodec: 'mpeg2video',
        rateControl: ['vbr', 'cbr'],
      ),
      VideoEncoderInfo(
        id: 'mpeg4',
        label: 'MPEG-4（软件）',
        hardware: false,
        outputCodec: 'mpeg4',
        rateControl: ['vbr', 'cbr'],
      ),
    ];
    return VideoEncoderCatalog._(const [...hardware, ...software],
        isFallback: true);
  }

  /// Parse the native JSON; any missing/malformed data degrades to
  /// [VideoEncoderCatalog.fallback] (never throws).
  static VideoEncoderCatalog parse(String? raw) {
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      return VideoEncoderCatalog.fallback();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return VideoEncoderCatalog.fallback();
      }
      final rawCodecs = decoded['codecs'];
      if (rawCodecs is! List) return VideoEncoderCatalog.fallback();
      final codecs = <VideoEncoderInfo>[
        for (final codec in rawCodecs)
          if (codec is Map<String, dynamic>)
            ?VideoEncoderInfo.tryFromJson(codec),
      ];
      if (codecs.isEmpty) return VideoEncoderCatalog.fallback();
      return VideoEncoderCatalog._(codecs);
    } catch (_) {
      return VideoEncoderCatalog.fallback();
    }
  }

  /// Hardware encoders (`hardware == true`).
  List<VideoEncoderInfo> get hardwareCodecs =>
      [for (final codec in codecs) if (codec.hardware) codec];

  /// Software encoders (`hardware == false`).
  List<VideoEncoderInfo> get softwareCodecs =>
      [for (final codec in codecs) if (!codec.hardware) codec];

  VideoEncoderInfo? codecById(String? id) =>
      id == null || id.isEmpty ? null : _byId[id];

  /// Display label for [id]; unknown ids fall back to the raw id.
  String labelOf(String? id) {
    if (id == null || id.isEmpty) return '';
    return codecById(id)?.label ?? id;
  }

  /// Rate-control modes advertised for [encoderId] (empty when unknown).
  List<String> rateControlFor(String? encoderId) =>
      codecById(encoderId)?.rateControl ?? const [];
}
