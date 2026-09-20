import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:webdav_music_player/models/webdav_item.dart';
import 'package:webdav_music_player/services/music_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('channel id is v3 (IMPORTANCE_DEFAULT fresh channel)', () {
    expect(kMediaNotificationChannelId, contains('audio.v3'));
  });

  test('stop clears queue and allows idle again', () async {
    final handler = MusicAudioHandler(player: AudioPlayer());
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
    final handler = MusicAudioHandler(player: AudioPlayer());
    addTearDown(() async {
      await handler.disposePlayer();
    });
    final item = handler.mediaItemFor(
      TrackInfo(
        accountId: 'a',
        remotePath: '/x.mp3',
        fileName: 'x.mp3',
        title: '   ',
      ),
    );
    expect(item.title, 'x.mp3');
  });
}
