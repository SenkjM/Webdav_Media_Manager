import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/music_audio_handler.dart';

/// Idle-guard behaviour of the handler.
///
/// Only [MusicAudioHandler.stop] needs a live player, so it is skipped (instead
/// of exploding) on hosts without libmpv; the pure mapping rules live in
/// `music_audio_handler_test.dart` and run everywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var mpvReady = true;
  try {
    MediaKit.ensureInitialized();
  } catch (_) {
    mpvReady = false;
  }
  final skipReason = mpvReady ? null : '需要 libmpv / media_kit 原生库（本机未提供）';

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
  }, skip: skipReason);

  test('mediaItemFor never empty title', () {
    final item = mediaItemForTrack(
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
