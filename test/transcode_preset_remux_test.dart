import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/transcode_preset.dart';

void main() {
  group('TranscodePreset remux modes', () {
    test('missing remux keys default to on', () {
      final preset = TranscodePreset.fromJson(const {
        'id': 'h264',
        'label': 'H.264',
      });

      expect(preset.videoRemux, 'on');
      expect(preset.audioRemux, 'on');
    });

    test('reads every documented value', () {
      for (final mode in TranscodePreset.remuxModes) {
        final preset = TranscodePreset.fromJson({
          'id': 'p',
          'label': 'P',
          'video_remux': mode,
          'audio_remux': mode,
        });
        expect(preset.videoRemux, mode);
        expect(preset.audioRemux, mode);
      }
    });

    test('unknown values fall back to on instead of failing', () {
      final preset = TranscodePreset.fromJson(const {
        'id': 'p',
        'label': 'P',
        'video_remux': 'hybrid',
        'audio_remux': 42,
      });

      expect(preset.videoRemux, 'on');
      expect(preset.audioRemux, 'on');
    });

    test('serializes remux keys and drops the legacy boolean keys', () {
      final json = const TranscodePreset(
        id: 'p',
        label: 'P',
        videoRemux: 'strict',
        audioRemux: 'off',
        audioCodec: 'aac',
        audioBitrate: 128000,
        audioChannels: 2,
        hlsSegmentSecs: 4,
        sortOrder: 10,
        isBuiltin: false,
      ).toJson();

      expect(json['video_remux'], 'strict');
      expect(json['audio_remux'], 'off');
      expect(json.containsKey('video_copy'), isFalse);
      expect(json.containsKey('audio_copy'), isFalse);
    });

    test('hasVideoPath honours remux + encoder layers', () {
      TranscodePreset build({String remux = 'off', String hw = '', String sw = ''}) {
        return TranscodePreset(
          id: 'p',
          label: 'P',
          videoRemux: remux,
          audioRemux: 'on',
          hwVideoEncoder: hw,
          swVideoEncoder: sw,
          audioCodec: 'aac',
          audioBitrate: 128000,
          audioChannels: 2,
          hlsSegmentSecs: 4,
          sortOrder: 10,
          isBuiltin: false,
        );
      }

      expect(build().hasVideoPath, isFalse);
      expect(build(remux: 'on').hasVideoPath, isTrue);
      expect(build(remux: 'strict').hasVideoPath, isTrue);
      expect(build(hw: 'h264_mediacodec').hasVideoPath, isTrue);
      expect(build(sw: 'libx264').hasVideoPath, isTrue);
    });
  });

  group('TranscodePreset.normalizeSpeedPreset', () {
    const expected = {
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

    test('covers the whole x264 ladder', () {
      for (final preset in TranscodePreset.x264Presets) {
        expect(expected.containsKey(preset), isTrue, reason: preset);
        expect(
          TranscodePreset.normalizeSpeedPreset(preset),
          expected[preset],
          reason: preset,
        );
      }
    });

    test('unknown names fall back to medium', () {
      expect(TranscodePreset.normalizeSpeedPreset(''), 'medium');
      expect(TranscodePreset.normalizeSpeedPreset('turbo'), 'medium');
    });

    test('every normalized value is one of the five UI tiers', () {
      for (final preset in TranscodePreset.x264Presets) {
        expect(
          TranscodePreset.speedPresets,
          contains(TranscodePreset.normalizeSpeedPreset(preset)),
          reason: preset,
        );
      }
    });
  });
}
