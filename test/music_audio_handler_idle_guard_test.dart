import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/music_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  test('channel id is v4 (IMPORTANCE_DEFAULT fresh channel)', () {
    expect(kMediaNotificationChannelId, contains('audio.v4'));
  });

  test('stop clears queue and allows idle again', () async {
    final handler = MusicAudioHandler(player: Player());
    addTearDown(() async {
      await handler.disposePlayer();
    });
    await handler.stop();
    expect(handler.index, -1);
    expect(handler.tracks, isEmpty);
    final state = handler.playbackState.value;
    expect(state.processingState, AudioProcessingState.idle);
  });

  test('mediaItemFor never empty title', () {
    final handler = MusicAudioHandler(player: Player());
    addTearDown(() async {
      await handler.disposePlayer();
    });
    final item = handler.mediaItemFor(
      TrackInfo(
        sourceName: 'a',
        remotePath: '/x.mp3',
        fileName: 'x.mp3',
        title: '   ',
      ),
    );
    expect(item.title, 'x.mp3');
  });
}
