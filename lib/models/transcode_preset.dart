/// Model for transcode presets, matching the Rust `TranscodePreset` struct
/// (contract `remux-modes` §1 / DB schema v16).
///
/// A preset describes the video pipeline in three layers — remux (stream copy)
/// → hardware encoder → software encoder — plus the rate-control knobs shared
/// by the two encode layers. All parameters are resolved in Rust; this model is
/// a transport/UI mirror only.
class TranscodePreset {
  /// `video_remux` / `audio_remux` values (contract `remux-modes` §1).
  static const List<String> remuxModes = ['off', 'strict', 'on'];

  /// `video_rate_control` values (contract §13.5).
  static const List<String> rateControlModes = ['auto', 'vbr', 'cbr', 'cq'];

  /// x264 preset ladder (`sw_video_preset`), only meaningful for `libx264`.
  static const List<String> x264Presets = [
    'ultrafast',
    'superfast',
    'veryfast',
    'faster',
    'fast',
    'medium',
    'slow',
    'slower',
    'veryslow',
    'placebo',
  ];

  /// Audio codecs a preset may select when audio is encoded (remux off/strict).
  static const List<String> audioCodecs = ['aac', 'ac3', 'eac3', 'mp2'];

  /// UI 五档速度预设（x264 十档阶梯的对数投影）。
  static const List<String> speedPresets = [
    'superfast',
    'veryfast',
    'medium',
    'slow',
    'veryslow',
  ];

  /// 十档 x264 preset → 五档 UI 投影的别名表。
  static const Map<String, String> _speedPresetAliases = {
    'ultrafast': 'superfast',
    'superfast': 'superfast',
    'veryfast': 'veryfast',
    'faster': 'veryfast',
    'fast': 'medium',
    'medium': 'medium',
    'slow': 'slow',
    'slower': 'veryslow',
    'veryslow': 'veryslow',
    'placebo': 'veryslow',
  };

  /// 把历史/未知的 x264 preset 名投影到五档之一（未知值回落 `medium`）。
  static String normalizeSpeedPreset(String raw) =>
      _speedPresetAliases[raw] ?? 'medium';

  /// Stable identifier (`"h264"`, `"hevc"`, or a user preset id).
  final String id;

  /// Human-readable label shown in the UI.
  final String label;

  /// Video remux mode: `off` (always encode), `strict` (remux only when the
  /// runtime target codec matches the source), `on` (remux whenever MPEG-TS
  /// accepts the source codec).
  final String videoRemux;

  /// Audio remux mode, same three values as [videoRemux].
  final String audioRemux;

  /// Hardware video encoder: `"h264_mediacodec"`, `"hevc_mediacodec"`,
  /// `"mpeg4_mediacodec"`, or `""` (disabled).
  final String hwVideoEncoder;

  /// Software video encoder: `"libx264"`, `"mpeg2video"`, `"mpeg4"`, or `""`
  /// (disabled).
  final String swVideoEncoder;

  /// libx264 `preset` name (`veryfast`, `medium`, …); `""` when the selected
  /// software encoder has no preset ladder (`mpeg2video` / `mpeg4`).
  final String swVideoPreset;

  /// Max output width px (scale-down only). `null` = no limit.
  final int? videoMaxW;

  /// Max output height px. `null` = no limit.
  final int? videoMaxH;

  /// Max video bitrate bits/s. `null` = derive from the envelope.
  final int? videoMaxBitrate;

  /// Frame-rate cap (e.g. 30). `null` = no cap.
  final int? videoFpsCap;

  /// Video rate-control mode: `auto`, `vbr`, `cbr`, or `cq` (contract §13.5).
  final String videoRateControl;

  /// Constant-quality value when [videoRateControl] is `cq` (libx264 CRF 0–51,
  /// MediaCodec `global_quality` 0–100). `null` for the other modes.
  final int? videoQuality;

  /// Audio codec: `"aac"`, `"ac3"`, `"eac3"`, or `"mp2"`.
  final String audioCodec;

  /// Audio bitrate bits/s (e.g. `128_000`).
  final int audioBitrate;

  /// Output channel count (1 = mono, 2 = stereo).
  final int audioChannels;

  /// Output sample rate Hz. `null` = keep source.
  final int? audioSampleRate;

  /// HLS segment duration in seconds.
  final int hlsSegmentSecs;

  /// UI sort order (lower = earlier).
  final int sortOrder;

  /// `true` for the factory presets (`h264`, `hevc`).
  final bool isBuiltin;

  const TranscodePreset({
    required this.id,
    required this.label,
    required this.videoRemux,
    required this.audioRemux,
    this.hwVideoEncoder = '',
    this.swVideoEncoder = '',
    this.swVideoPreset = '',
    this.videoMaxW,
    this.videoMaxH,
    this.videoMaxBitrate,
    this.videoFpsCap,
    this.videoRateControl = 'vbr',
    this.videoQuality,
    required this.audioCodec,
    required this.audioBitrate,
    required this.audioChannels,
    this.audioSampleRate,
    required this.hlsSegmentSecs,
    required this.sortOrder,
    required this.isBuiltin,
  });

  /// At least one video path must be configured: remux, hardware, or software.
  bool get hasVideoPath =>
      videoRemux != 'off' || hwVideoEncoder.isNotEmpty || swVideoEncoder.isNotEmpty;

  /// Whether the constant-quality value applies to the current mode.
  bool get usesConstantQuality => videoRateControl == 'cq';

  factory TranscodePreset.fromJson(Map<String, dynamic> json) {
    return TranscodePreset(
      id: json['id'] as String,
      label: json['label'] as String,
      videoRemux: _remuxMode(json['video_remux']),
      audioRemux: _remuxMode(json['audio_remux']),
      hwVideoEncoder: json['hw_video_encoder'] as String? ?? '',
      swVideoEncoder: json['sw_video_encoder'] as String? ?? '',
      swVideoPreset: json['sw_video_preset'] as String? ?? '',
      videoMaxW: json['video_max_w'] as int?,
      videoMaxH: json['video_max_h'] as int?,
      videoMaxBitrate: json['video_max_bitrate'] as int?,
      videoFpsCap: json['video_fps_cap'] as int?,
      videoRateControl: json['video_rate_control'] as String? ?? 'vbr',
      videoQuality: json['video_quality'] as int?,
      audioCodec: json['audio_codec'] as String? ?? 'aac',
      audioBitrate: json['audio_bitrate'] as int? ?? 128000,
      audioChannels: json['audio_channels'] as int? ?? 2,
      audioSampleRate: json['audio_sample_rate'] as int?,
      hlsSegmentSecs: json['hls_segment_secs'] as int? ?? 4,
      sortOrder: json['sort_order'] as int? ?? 100,
      isBuiltin: json['is_builtin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'video_remux': videoRemux,
      'audio_remux': audioRemux,
      'hw_video_encoder': hwVideoEncoder,
      'sw_video_encoder': swVideoEncoder,
      'sw_video_preset': swVideoPreset,
      if (videoMaxW != null) 'video_max_w': videoMaxW,
      if (videoMaxH != null) 'video_max_h': videoMaxH,
      if (videoMaxBitrate != null) 'video_max_bitrate': videoMaxBitrate,
      if (videoFpsCap != null) 'video_fps_cap': videoFpsCap,
      'video_rate_control': videoRateControl,
      if (videoQuality != null) 'video_quality': videoQuality,
      'audio_codec': audioCodec,
      'audio_bitrate': audioBitrate,
      'audio_channels': audioChannels,
      if (audioSampleRate != null) 'audio_sample_rate': audioSampleRate,
      'hls_segment_secs': hlsSegmentSecs,
      'sort_order': sortOrder,
      'is_builtin': isBuiltin,
    };
  }

  /// Missing or unknown remux values fall back to `on` (Rust default).
  static String _remuxMode(Object? value) =>
      value is String && remuxModes.contains(value) ? value : 'on';
}
