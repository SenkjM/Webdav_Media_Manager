/// Model for transcode presets, matching the Rust `TranscodePreset` struct
/// (contract `preset-encoder-tiers` §1, DB schema v13).
///
/// A preset describes a three-tier plan: stream copy → hardware encoder →
/// software encoder (the latter two are the fallback order). All parameters
/// are resolved in Rust; this model is a transport/UI mirror only.
class TranscodePreset {
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

  /// Hardware encoder tier: `"fast"`, `"balanced"`, or `"quality"`.
  final String hwVideoTier;

  /// Software video encoder: `"libx264"`, `"mpeg2video"`, `"mpeg4"`, or `""`
  /// (disabled).
  final String swVideoEncoder;

  /// Software encoder tier: `"fast"`, `"balanced"`, or `"quality"`.
  final String swVideoTier;

  /// Max output width px (scale-down only). `null` = no limit.
  final int? videoMaxW;

  /// Max output height px. `null` = no limit.
  final int? videoMaxH;

  /// Max video bitrate bits/s. `null` = derive from resolution/fps.
  final int? videoMaxBitrate;

  /// Frame-rate cap (e.g. 30). `null` = no cap.
  final int? videoFpsCap;

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
    this.hwVideoTier = 'balanced',
    this.swVideoEncoder = '',
    this.swVideoTier = 'balanced',
    this.videoMaxW,
    this.videoMaxH,
    this.videoMaxBitrate,
    this.videoFpsCap,
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

  factory TranscodePreset.fromJson(Map<String, dynamic> json) {
    return TranscodePreset(
      id: json['id'] as String,
      label: json['label'] as String,
      videoCopy: json['video_copy'] as bool? ?? false,
      audioCopy: json['audio_copy'] as bool? ?? false,
      hwVideoEncoder: json['hw_video_encoder'] as String? ?? '',
      hwVideoTier: json['hw_video_tier'] as String? ?? 'balanced',
      swVideoEncoder: json['sw_video_encoder'] as String? ?? '',
      swVideoTier: json['sw_video_tier'] as String? ?? 'balanced',
      videoMaxW: json['video_max_w'] as int?,
      videoMaxH: json['video_max_h'] as int?,
      videoMaxBitrate: json['video_max_bitrate'] as int?,
      videoFpsCap: json['video_fps_cap'] as int?,
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
      'hw_video_tier': hwVideoTier,
      'sw_video_encoder': swVideoEncoder,
      'sw_video_tier': swVideoTier,
      if (videoMaxW != null) 'video_max_w': videoMaxW,
      if (videoMaxH != null) 'video_max_h': videoMaxH,
      if (videoMaxBitrate != null) 'video_max_bitrate': videoMaxBitrate,
      if (videoFpsCap != null) 'video_fps_cap': videoFpsCap,
      'audio_codec': audioCodec,
      'audio_bitrate': audioBitrate,
      'audio_channels': audioChannels,
      if (audioSampleRate != null) 'audio_sample_rate': audioSampleRate,
      'hls_segment_secs': hlsSegmentSecs,
      'sort_order': sortOrder,
      'is_builtin': isBuiltin,
    };
  }
}
