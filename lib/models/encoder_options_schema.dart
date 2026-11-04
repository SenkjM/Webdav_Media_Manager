import 'dart:convert';

/// Option value types exposed by the Rust encoder-options schema
/// (contract `preset-rate-control-and-codec-probe` §13.4).
enum EncoderOptionType {
  enumValue('enum'),
  intValue('int'),
  floatValue('float'),
  boolValue('bool');

  const EncoderOptionType(this.wireName);

  /// Literal `type` string used in the FFI JSON.
  final String wireName;

  static EncoderOptionType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// One configurable `AVDictionary` option of an encoder.
///
/// The schema comes from Rust ([RustCoreService.encoderOptionsSchemaJson]); the
/// UI must render it — option keys/values are never hard-coded in Dart.
class EncoderOptionSchema {
  /// Exact `AVDictionary` key passed to `avcodec_open2`.
  final String key;

  /// Human-readable label (already localised by the Rust side).
  final String label;

  /// Value type; decides which editor control is shown.
  final EncoderOptionType type;

  /// Union of allowed values for [EncoderOptionType.enumValue].
  final List<String> values;

  /// Inclusive lower bound for numeric types, when the codec declares one.
  final num? min;

  /// Inclusive upper bound for numeric types, when the codec declares one.
  final num? max;

  /// Default value; `null` means "not passed unless the user opts in".
  final String? defaultValue;

  /// `true` = render inside the collapsed “高级编码器设置” section; `false` =
  /// render inline next to the encoder selector.
  final bool advanced;

  const EncoderOptionSchema({
    required this.key,
    required this.label,
    required this.type,
    this.values = const [],
    this.min,
    this.max,
    this.defaultValue,
    this.advanced = true,
  });

  static EncoderOptionSchema? tryFromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final type = EncoderOptionType.fromWire(json['type']);
    if (key is! String || key.isEmpty || type == null) return null;
    final label = json['label'];
    return EncoderOptionSchema(
      key: key,
      label: label is String && label.isNotEmpty ? label : key,
      type: type,
      values: [
        if (json['values'] is List)
          for (final value in json['values'] as List)
            if (value != null) value.toString(),
      ],
      min: json['min'] is num ? json['min'] as num : null,
      max: json['max'] is num ? json['max'] as num : null,
      defaultValue: json['default']?.toString(),
      advanced: json['advanced'] as bool? ?? true,
    );
  }

  /// The value to start from when the user enables this option.
  String initialValue() {
    switch (type) {
      case EncoderOptionType.enumValue:
        if (values.isNotEmpty) return values.first;
        return '';
      case EncoderOptionType.boolValue:
        return 'false';
      case EncoderOptionType.intValue:
      case EncoderOptionType.floatValue:
        final minValue = min;
        if (minValue != null) {
          return type == EncoderOptionType.intValue
              ? minValue.round().toString()
              : minValue.toString();
        }
        return type == EncoderOptionType.intValue ? '0' : '0.0';
    }
  }

  /// Numeric slider support: bounded numeric options get a slider, unbounded
  /// ones a numeric text field.
  bool get hasRange => min != null && max != null && (max! > min!);
}

/// One encoder (hardware or software) with its rate-control modes and
/// configurable options.
class EncoderCodecSchema {
  /// Encoder id, e.g. `h264_mediacodec` / `libx264`.
  final String id;

  /// `hw` or `sw`.
  final String kind;

  /// Display label (already localised by Rust).
  final String label;

  /// Output codec id (`h264`, `hevc`, `mpeg4`).
  final String outputCodec;

  /// Rate-control modes this encoder supports (`vbr`, `cbr`, `cq`; `auto` is
  /// always allowed and added by the UI).
  final List<String> rateControl;

  /// Configurable options for this encoder.
  final List<EncoderOptionSchema> options;

  const EncoderCodecSchema({
    required this.id,
    required this.kind,
    required this.label,
    required this.outputCodec,
    this.rateControl = const [],
    this.options = const [],
  });

  bool get isHardware => kind == 'hw';

  static EncoderCodecSchema? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = json['kind'];
    if (id is! String || id.isEmpty || kind is! String) return null;
    final label = json['label'];
    final outputCodec = json['output_codec'];
    return EncoderCodecSchema(
      id: id,
      kind: kind,
      label: label is String && label.isNotEmpty ? label : id,
      outputCodec: outputCodec is String ? outputCodec : '',
      rateControl: [
        if (json['rate_control'] is List)
          for (final mode in json['rate_control'] as List)
            if (mode is String && mode.isNotEmpty) mode,
      ],
      options: [
        if (json['options'] is List)
          for (final option in json['options'] as List)
            if (option is Map<String, dynamic>)
              ?EncoderOptionSchema.tryFromJson(option),
      ],
    );
  }
}

/// The whole encoder-options schema returned by
/// `wdmm_encoder_options_schema_json()`.
class EncoderOptionsSchema {
  /// All known encoders (hardware and software).
  final List<EncoderCodecSchema> codecs;

  /// `true` when the native library predates the schema export and we are
  /// rendering the built-in minimal fallback.
  final bool isFallback;

  final Map<String, EncoderCodecSchema> _byId;

  EncoderOptionsSchema._(this.codecs, {this.isFallback = false})
      : _byId = {for (final codec in codecs) codec.id: codec};

  /// Minimal fallback used when the installed `.so` has no
  /// `wdmm_encoder_options_schema_json` export: the encoders the app has always
  /// shipped with, without any advanced options (the editor explains how to get
  /// them back by updating the native library).
  factory EncoderOptionsSchema.fallback() {
    const hardware = [
      EncoderCodecSchema(
        id: 'h264_mediacodec',
        kind: 'hw',
        label: 'H.264 硬编',
        outputCodec: 'h264',
        rateControl: ['vbr', 'cbr', 'cq'],
      ),
      EncoderCodecSchema(
        id: 'hevc_mediacodec',
        kind: 'hw',
        label: 'H.265 硬编',
        outputCodec: 'hevc',
        rateControl: ['vbr', 'cbr', 'cq'],
      ),
      EncoderCodecSchema(
        id: 'mpeg4_mediacodec',
        kind: 'hw',
        label: 'MPEG-4 硬编',
        outputCodec: 'mpeg4',
        rateControl: ['vbr', 'cbr', 'cq'],
      ),
    ];
    const software = [
      EncoderCodecSchema(
        id: 'libx264',
        kind: 'sw',
        label: 'x264',
        outputCodec: 'h264',
        rateControl: ['vbr', 'cbr', 'cq'],
      ),
      EncoderCodecSchema(
        id: 'mpeg2video',
        kind: 'sw',
        label: 'MPEG-2',
        outputCodec: 'mpeg2video',
        rateControl: ['vbr', 'cbr', 'cq'],
      ),
      EncoderCodecSchema(
        id: 'mpeg4',
        kind: 'sw',
        label: 'MPEG-4',
        outputCodec: 'mpeg4',
        rateControl: ['vbr', 'cbr', 'cq'],
      ),
    ];
    return EncoderOptionsSchema._(const [...hardware, ...software],
        isFallback: true);
  }

  /// Parse the FFI payload; any missing/malformed data degrades to
  /// [EncoderOptionsSchema.fallback] (never throws).
  static EncoderOptionsSchema parse(String? raw) {
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      return EncoderOptionsSchema.fallback();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return EncoderOptionsSchema.fallback();
      }
      final rawCodecs = decoded['codecs'];
      if (rawCodecs is! List) return EncoderOptionsSchema.fallback();
      final codecs = <EncoderCodecSchema>[
        for (final codec in rawCodecs)
          if (codec is Map<String, dynamic>) ?EncoderCodecSchema.tryFromJson(codec),
      ];
      if (codecs.isEmpty) return EncoderOptionsSchema.fallback();
      return EncoderOptionsSchema._(codecs);
    } catch (_) {
      return EncoderOptionsSchema.fallback();
    }
  }

  /// Hardware encoders (`kind == "hw"`).
  List<EncoderCodecSchema> get hardwareCodecs =>
      [for (final codec in codecs) if (codec.isHardware) codec];

  /// Software encoders (`kind == "sw"`).
  List<EncoderCodecSchema> get softwareCodecs =>
      [for (final codec in codecs) if (!codec.isHardware) codec];

  EncoderCodecSchema? codecById(String? id) =>
      id == null || id.isEmpty ? null : _byId[id];

  /// Rate-control modes advertised for [encoderId] (without `auto`).
  List<String> rateControlFor(String encoderId) =>
      codecById(encoderId)?.rateControl ?? const [];

  /// Advanced options (rendered in the collapsed section).
  List<EncoderOptionSchema> advancedOptionsFor(String encoderId) => [
        for (final option in codecById(encoderId)?.options ?? const
            <EncoderOptionSchema>[])
          if (option.advanced) option,
      ];

  /// Non-advanced options (rendered inline next to the encoder selector).
  List<EncoderOptionSchema> inlineOptionsFor(String encoderId) => [
        for (final option in codecById(encoderId)?.options ?? const
            <EncoderOptionSchema>[])
          if (!option.advanced) option,
      ];

  /// Whether [encoderId] has any options at all.
  bool hasOptions(String encoderId) =>
      (codecById(encoderId)?.options ?? const []).isNotEmpty;

  /// Option keys understood by [encoderId] (used to prune stale overrides when
  /// the user switches encoder).
  Set<String> optionKeysFor(String encoderId) => {
        for (final option in codecById(encoderId)?.options ??
            const <EncoderOptionSchema>[])
          option.key,
      };
}
