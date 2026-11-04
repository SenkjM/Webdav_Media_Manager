import 'dart:convert';

/// Model for transcode presets, matching the Rust `TranscodePreset` struct
/// (contract `preset-rate-control-and-codec-probe` §13 / DB schema v14).
///
/// A preset describes the video pipeline in three layers — copy → hardware
/// encoder → software encoder — plus the rate-control knobs shared by the two
/// encode layers. All parameters are resolved in Rust; this model is a
/// transport/UI mirror only.
class TranscodePreset {
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

  /// Audio codecs a preset may select when `audio_copy` is off.
  static const List<String> audioCodecs = ['aac', 'ac3', 'eac3', 'mp2'];

  /// Stable identifier (`"h264"`, `"hevc"`, or a user preset id).
  final String id;

  /// Human-readable label shown in the UI.
  final String label;

  /// Try to copy the video stream without re-encoding.
  final bool videoCopy;

  /// Try to copy the audio stream without re-encoding.
  final bool audioCopy;

  /// Hardware video encoder: `"h264_mediacodec"`, `"hevc_mediacodec"`,
  /// `"mpeg4_mediacodec"`, or `""` (disabled).
  final String hwVideoEncoder;

  /// Advanced `AVDictionary` options for the hardware encoder, keyed by the
  /// exact option name passed to `avcodec_open2` (contract §13.4). Empty = none.
  final Map<String, String> hwVideoOptions;

  /// Software video encoder: `"libx264"`, `"mpeg2video"`, `"mpeg4"`, or `""`
  /// (disabled).
  final String swVideoEncoder;

  /// libx264 `preset` name (`veryfast`, `medium`, …); `""` when the selected
  /// software encoder has no preset ladder (`mpeg2video` / `mpeg4`).
  final String swVideoPreset;

  /// Advanced `AVDictionary` options for the software encoder. Empty = none.
  final Map<String, String> swVideoOptions;

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
    required this.videoCopy,
    required this.audioCopy,
    this.hwVideoEncoder = '',
    this.hwVideoOptions = const {},
    this.swVideoEncoder = '',
    this.swVideoPreset = '',
    this.swVideoOptions = const {},
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

  /// At least one video path must be configured: copy, hardware, or software.
  bool get hasVideoPath =>
      videoCopy || hwVideoEncoder.isNotEmpty || swVideoEncoder.isNotEmpty;

  /// Whether the constant-quality value applies to the current mode.
  bool get usesConstantQuality => videoRateControl == 'cq';

  factory TranscodePreset.fromJson(Map<String, dynamic> json) {
    return TranscodePreset(
      id: json['id'] as String,
      label: json['label'] as String,
      videoCopy: json['video_copy'] as bool? ?? false,
      audioCopy: json['audio_copy'] as bool? ?? false,
      hwVideoEncoder: json['hw_video_encoder'] as String? ?? '',
      hwVideoOptions: _optionsFromJson(json['hw_video_options']),
      swVideoEncoder: json['sw_video_encoder'] as String? ?? '',
      swVideoPreset: json['sw_video_preset'] as String? ?? '',
      swVideoOptions: _optionsFromJson(json['sw_video_options']),
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
      'video_copy': videoCopy,
      'audio_copy': audioCopy,
      'hw_video_encoder': hwVideoEncoder,
      'hw_video_options': hwVideoOptions,
      'sw_video_encoder': swVideoEncoder,
      'sw_video_preset': swVideoPreset,
      'sw_video_options': swVideoOptions,
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

  /// Parse the options map from either a JSON object (current FFI shape) or a
  /// JSON object encoded as text (older hand-written payloads).
  static Map<String, String> _optionsFromJson(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.value != null) entry.key.toString(): entry.value.toString(),
      };
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return {
            for (final entry in decoded.entries)
              if (entry.value != null)
                entry.key.toString(): entry.value.toString(),
          };
        }
      } catch (_) {
        // Malformed options text from an old row: treat as "no overrides".
      }
    }
    return const {};
  }
}
