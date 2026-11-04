import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/encoder_options_schema.dart';

/// 契约 `preset-rate-control-and-codec-probe` §13.4：schema 由 Rust 提供，
/// Dart 只负责渲染；任何缺失/畸形载荷都必须降级到 fallback 而不是抛异常。
void main() {
  group('EncoderOptionsSchema.parse', () {
    test('null / error / 非法 JSON 都降级到 fallback', () {
      for (final raw in [null, '', 'error: boom', 'not-json', '[]', '{}']) {
        final schema = EncoderOptionsSchema.parse(raw);
        expect(schema.isFallback, isTrue, reason: 'raw=$raw');
        expect(schema.hardwareCodecs.map((c) => c.id), contains('h264_mediacodec'));
        expect(schema.softwareCodecs.map((c) => c.id), contains('libx264'));
      }
    });

    test('解析合法 schema：hw/sw 分组、rate_control、options 类型', () {
      const raw = '{"codecs":['
          '{"id":"h264_mediacodec","kind":"hw","label":"H.264 硬编",'
          '"output_codec":"h264","rate_control":["vbr","cq"],"options":['
          '{"key":"profile","label":"Profile","type":"enum",'
          '"values":["baseline","high"],"advanced":false},'
          '{"key":"bf","label":"B 帧","type":"bool","advanced":true},'
          '{"key":"bitrate","label":"码率","type":"int",'
          '"min":100000,"max":8000000,"default":2000000,"advanced":true},'
          '{"key":"gop","label":"GOP","type":"float","min":0.5,"max":4,"advanced":true},'
          '{"key":"","label":"bad","type":"enum"},'
          '{"key":"badtype","label":"bad","type":"nope"}'
          ']},'
          '{"id":"libx264","kind":"sw","label":"x264",'
          '"output_codec":"h264","rate_control":["vbr"],"options":[]},'
          '{"id":"","kind":"hw","label":"bad"}'
          ']}';

      final schema = EncoderOptionsSchema.parse(raw);
      expect(schema.isFallback, isFalse);
      expect(schema.hardwareCodecs.map((c) => c.id), ['h264_mediacodec']);
      expect(schema.softwareCodecs.map((c) => c.id), ['libx264']);

      final hw = schema.codecById('h264_mediacodec')!;
      expect(hw.isHardware, isTrue);
      expect(hw.outputCodec, 'h264');
      expect(hw.rateControl, ['vbr', 'cq']);

      // 非法 option（缺 key / 未知 type）被丢弃，只剩 4 条合法项。
      expect(hw.options.length, 4);
      expect(schema.inlineOptionsFor('h264_mediacodec').map((o) => o.key),
          ['profile']);
      expect(schema.advancedOptionsFor('h264_mediacodec').map((o) => o.key),
          ['bf', 'bitrate', 'gop']);
      expect(schema.optionKeysFor('h264_mediacodec'),
          {'profile', 'bf', 'bitrate', 'gop'});
      expect(schema.hasOptions('libx264'), isFalse);
      expect(schema.rateControlFor('libx264'), ['vbr']);
      expect(schema.rateControlFor('unknown'), isEmpty);
    });
  });

  group('EncoderOptionSchema', () {
    test('initialValue 按类型取默认值', () {
      const enumOption = EncoderOptionSchema(
        key: 'profile',
        label: 'Profile',
        type: EncoderOptionType.enumValue,
        values: ['baseline', 'high'],
      );
      expect(enumOption.initialValue(), 'baseline');

      const boolOption = EncoderOptionSchema(
        key: 'bf',
        label: 'B 帧',
        type: EncoderOptionType.boolValue,
      );
      expect(boolOption.initialValue(), 'false');

      const intOption = EncoderOptionSchema(
        key: 'bitrate',
        label: '码率',
        type: EncoderOptionType.intValue,
        min: 100000,
        max: 8000000,
      );
      expect(intOption.initialValue(), '100000');
      expect(intOption.hasRange, isTrue);

      const floatOption = EncoderOptionSchema(
        key: 'gop',
        label: 'GOP',
        type: EncoderOptionType.floatValue,
      );
      expect(floatOption.initialValue(), '0.0');
      expect(floatOption.hasRange, isFalse);
    });

    test('default=null 表示默认不传，defaultValue 为 null', () {
      final option = EncoderOptionSchema.tryFromJson(const {
        'key': 'x264-params',
        'label': 'x264 参数',
        'type': 'enum',
        'values': ['a', 'b'],
        'default': null,
      })!;
      expect(option.defaultValue, isNull);
    });
  });
}
