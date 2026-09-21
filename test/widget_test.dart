import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/utils/audio_extensions.dart';

void main() {
  test('audio extension detection', () {
    expect(isAudioFileName('song.mp3'), isTrue);
    expect(isAudioFileName('Song.FLAC'), isTrue);
    expect(isAudioFileName('readme.txt'), isFalse);
  });

  test('WebDavItem.isAudio derives from assigned category', () {
    const item = WebDavItem(
      name: 'track.ogg',
      path: '/music/track.ogg',
      isDirectory: false,
      category: FileCategory.music,
    );
    expect(item.isAudio, isTrue);
    expect(item.isVideo, isFalse);
    const dir =
        WebDavItem(name: 'Album', path: '/music/Album/', isDirectory: true);
    expect(dir.isAudio, isFalse);
  });

  test('FileTypeConfig classifies by extension', () {
    final config = FileTypeConfig();
    expect(config.categoryFor('song.mp3'), FileCategory.music);
    expect(config.categoryFor('movie.MKV'), FileCategory.video);
    expect(config.categoryFor('album.cue'), FileCategory.cue);
    expect(config.categoryFor('readme.txt'), FileCategory.other);
  });

  test('TrackInfo display prefers title when known (library metadata)', () {
    final t = TrackInfo(
      sourceName: 'acc1',
      remotePath: '/a/b.mp3',
      fileName: 'b.mp3',
      title: 'Secret',
    );
    expect(t.isDownloaded, isFalse);
    // Library may retain tags after cache cleanup — show title when present.
    expect(t.displayTitle, 'Secret');
    expect(t.displayArtist, '未知艺术家');
    final bare = TrackInfo(
      sourceName: 'acc1',
      remotePath: '/a/c.mp3',
      fileName: 'c.mp3',
    );
    expect(bare.displayTitle, 'c.mp3');
  });

  test('folderDisplayName shows only current folder', () {
    expect(folderDisplayName('/'), '根目录');
    expect(folderDisplayName('/music/Album/'), 'Album');
    expect(folderDisplayName('/music/Album'), 'Album');
  });
}
