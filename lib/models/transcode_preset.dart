/// Model for transcode presets, matching the Rust `TranscodePreset` struct.
class TranscodePreset {
  /// Stable identifier (e.g. `"dlna-compat"`, `"passthrough"`).
  final String id;

  /// Human-readable label shown in the UI.
  final String label;

  /// Output container: `"mpegts"`, `"mp4"`, or `"original"`.
  final String container;

  /// Video codec: `"h264"` → tries `h264_mediacodec`, then `libx264`.
  /// `null` = audio-only.
  final String? videoCodec;

  /// Prefer hardware encoder (`h264_mediacodek`) before `libx264`.
  final bool videoHwPreferred;

  /// Max output width px (scale-down only). `null` = no limit.
  final int? videoMaxW;

  /// Max output height px. `null` = no limit.
  final int? videoMaxH;

  /// Max video bitrate bits/s. `null` = no limit.
  final int? videoMaxBitrate;

  /// Frame-rate cap (e.g. 30). `null` = no cap.
  final int? videoFpsCap;

  /// Audio codec: `"aac"`, `"mp3"`, or `"copy"`.
  final String audioCodec;

  /// Audio bitrate bits/s (e.g. `128_000`).
  final int audioBitrate;

  /// Output channel count (1 = mono, 2 = stereo).
  final int audioChannels;

  /// Output sample rate Hz. `null` = keep source.
  final int? audioSampleRate;

  /// HLS segment duration in seconds.
  final int hlsSegmentSecs;

  /// Try remux (copy streams) before falling back to transcode.
  final bool remuxFirst;

  /// UI sort order (lower = earlier).
  final int sortOrder;

  /// `true` for the 5 factory presets.
  final bool isBuiltin;

  const TranscodePreset({
    required this.id,
    required this.label,
    required this.container,
    this.videoCodec,
    required this.videoHwPreferred,
    this.videoMaxW,
    this.videoMaxH,
    this.videoMaxBitrate,
    this.videoFpsCap,
    required this.audioCodec,
    required this.audioBitrate,
    required this.audioChannels,
    this.audioSampleRate,
    required this.hlsSegmentSecs,
    required this.remuxFirst,
    required this.sortOrder,
    required this.isBuiltin,
  });

  factory TranscodePreset.fromJson(Map<String, dynamic> json) {
    return TranscodePreset(
      id: json['id'] as String,
      label: json['label'] as String,
      container: json['container'] as String,
      videoCodec: json['video_codec'] as String?,
      videoHwPreferred: json['video_hw_preferred'] as bool? ?? true,
      videoMaxW: json['video_max_w'] as int?,
      videoMaxH: json['video_max_h'] as int?,
      videoMaxBitrate: json['video_max_bitrate'] as int?,
      videoFpsCap: json['video_fps_cap'] as int?,
      audioCodec: json['audio_codec'] as String,
      audioBitrate: json['audio_bitrate'] as int,
      audioChannels: json['audio_channels'] as int,
      audioSampleRate: json['audio_sample_rate'] as int?,
      hlsSegmentSecs: json['hls_segment_secs'] as int,
      remuxFirst: json['remux_first'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
      isBuiltin: json['is_builtin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'container': container,
      if (videoCodec != null) 'video_codec': videoCodec,
      'video_hw_preferred': videoHwPreferred,
      if (videoMaxW != null) 'video_max_w': videoMaxW,
      if (videoMaxH != null) 'video_max_h': videoMaxH,
      if (videoMaxBitrate != null) 'video_max_bitrate': videoMaxBitrate,
      if (videoFpsCap != null) 'video_fps_cap': videoFpsCap,
      'audio_codec': audioCodec,
      'audio_bitrate': audioBitrate,
      'audio_channels': audioChannels,
      if (audioSampleRate != null) 'audio_sample_rate': audioSampleRate,
      'hls_segment_secs': hlsSegmentSecs,
      'remux_first': remuxFirst,
      'sort_order': sortOrder,
      'is_builtin': isBuiltin,
    };
  }

  TranscodePreset copyWith({
    String? id,
    String? label,
    String? container,
    String? videoCodec,
    bool? videoHwPreferred,
    int? videoMaxW,
    int? videoMaxH,
    int? videoMaxBitrate,
    int? videoFpsCap,
    String? audioCodec,
    int? audioBitrate,
    int? audioChannels,
    int? audioSampleRate,
    int? hlsSegmentSecs,
    bool? remuxFirst,
    int? sortOrder,
    bool? isBuiltin,
  }) {
    return TranscodePreset(
      id: id ?? this.id,
      label: label ?? this.label,
      container: container ?? this.container,
      videoCodec: videoCodec ?? this.videoCodec,
      videoHwPreferred: videoHwPreferred ?? this.videoHwPreferred,
      videoMaxW: videoMaxW ?? this.videoMaxW,
      videoMaxH: videoMaxH ?? this.videoMaxH,
      videoMaxBitrate: videoMaxBitrate ?? this.videoMaxBitrate,
      videoFpsCap: videoFpsCap ?? this.videoFpsCap,
      audioCodec: audioCodec ?? this.audioCodec,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      audioChannels: audioChannels ?? this.audioChannels,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      hlsSegmentSecs: hlsSegmentSecs ?? this.hlsSegmentSecs,
      remuxFirst: remuxFirst ?? this.remuxFirst,
      sortOrder: sortOrder ?? this.sortOrder,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }
}
