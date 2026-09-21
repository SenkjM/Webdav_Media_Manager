import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/music_audio_handler.dart';

void main() {
  test('channel id bumped to v4 for ColorOS fresh IMPORTANCE_DEFAULT', () {
    expect(kMediaNotificationChannelId, contains('audio.v4'));
    expect(kMediaNotificationChannelId, isNot(contains('audio.v3')));
  });
}
