import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/video_encoder_catalog.dart';

void main() {
  group('VideoEncoderCatalog.parse', () {
    test('falls back when the native export is missing or malformed', () {
      for (final raw in <String?>[
        null,
        '',
        'error: unknown',
        'not-json',
        '[]',
        '{}',
        '{"codecs":[]}',
      ]) {
        final catalog = VideoEncoderCatalog.parse(raw);
        expect(catalog.isFallback, isTrue, reason: 'input: $raw');
        expect(catalog.codecs, hasLength(6), reason: 'input: $raw');
      }
    });

    test('parses the catalog payload and splits hardware/software', () {
      const raw = '{"codecs":['
          '{"id":"h264_mediacodec","label":"H.264 硬编","hardware":true,'
          '"output_codec":"h264","rate_control":["cq","vbr","cbr"]},'
          '{"id":"libx264","label":"x264（软件）","hardware":false,'
          '"output_codec":"h264","rate_control":["vbr","cbr"]}'
          ']}';
      final catalog = VideoEncoderCatalog.parse(raw);

      expect(catalog.isFallback, isFalse);
      expect(catalog.hardwareCodecs.map((c) => c.id), ['h264_mediacodec']);
      expect(catalog.softwareCodecs.map((c) => c.id), ['libx264']);
      expect(catalog.labelOf('h264_mediacodec'), 'H.264 硬编');
      expect(catalog.labelOf('libx264'), 'x264（软件）');
      expect(catalog.labelOf('missing'), 'missing');
      expect(catalog.rateControlFor('h264_mediacodec'), ['cq', 'vbr', 'cbr']);
      expect(catalog.rateControlFor('libx264'), ['vbr', 'cbr']);
      expect(catalog.rateControlFor(null), isEmpty);
    });

    test('keeps only well-formed encoders and otherwise falls back', () {
      const raw = '{"codecs":['
          '{"label":"no id","hardware":true},'
          '{"id":"","label":"blank id","hardware":true},'
          '{"id":"mpeg4_mediacodec","label":"MPEG-4 硬编","hardware":true}'
          ']}';
      final catalog = VideoEncoderCatalog.parse(raw);

      expect(catalog.isFallback, isFalse);
      expect(catalog.codecs, hasLength(1));
      expect(catalog.codecs.single.id, 'mpeg4_mediacodec');
    });
  });

  group('VideoEncoderCatalog.fallback', () {
    test('carries the contract §2.2 labels without “MediaCodec”', () {
      final catalog = VideoEncoderCatalog.fallback();

      expect(catalog.isFallback, isTrue);
      expect(catalog.codecs.map((c) => c.label), [
        'H.264 硬编',
        'H.265 硬编',
        'MPEG-4 硬编',
        'x264（软件）',
        'MPEG-2（软件）',
        'MPEG-4（软件）',
      ]);
      for (final codec in catalog.codecs) {
        expect(codec.label.toLowerCase(), isNot(contains('mediacodec')));
      }
    });
  });

  group('VideoEncoderInfo', () {
    test('supportsRateControl only advertises listed modes', () {
      const codec = VideoEncoderInfo(
        id: 'mpeg2video',
        label: 'MPEG-2（软件）',
        hardware: false,
        rateControl: ['vbr', 'cbr'],
      );

      expect(codec.supportsRateControl('vbr'), isTrue);
      expect(codec.supportsRateControl('cbr'), isTrue);
      expect(codec.supportsRateControl('cq'), isFalse);
    });
  });
}
