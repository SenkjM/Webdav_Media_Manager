import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/webdav_item.dart';
import 'package:webdav_music_player/utils/audio_extensions.dart';

void main() {
  test('audio extension detection', () {
    expect(isAudioFileName('song.mp3'), isTrue);
    expect(isAudioFileName('Song.FLAC'), isTrue);
    expect(isAudioFileName('readme.txt'), isFalse);
  });

  test('WebDavItem.isAudio uses filename only (no ID3)', () {
    const item = WebDavItem(
      name: 'track.ogg',
      path: '/music/track.ogg',
      isDirectory: false,
    );
    expect(item.isAudio, isTrue);
    const dir = WebDavItem(name: 'Album', path: '/music/Album/', isDirectory: true);
    expect(dir.isAudio, isFalse);
  });

  test('TrackInfo display falls back to filename when not downloaded', () {
    final t = TrackInfo(remotePath: '/a/b.mp3', fileName: 'b.mp3', title: 'Secret');
    expect(t.isDownloaded, isFalse);
    expect(t.displayTitle, 'b.mp3'); // no tag until downloaded
    t.localPath = '/cache/b.mp3';
    expect(t.displayTitle, 'Secret');
  });
}
