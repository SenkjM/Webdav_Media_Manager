import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/models/webdav_item.dart';
import 'package:webdav_music_player/services/settings_service.dart';
import 'package:webdav_music_player/services/share_rename_service.dart';

void main() {
  group('ShareRenameService.render', () {
    test('default 作者-标题 pattern', () {
      final track = TrackInfo(
        accountId: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: '夜曲',
        artist: '周杰伦',
      );
      expect(
        ShareRenameService.render('{artist}-{title}', track),
        '周杰伦-夜曲',
      );
    });

    test('missing fields collapse instead of leaving dangling separators', () {
      final track = TrackInfo(
        accountId: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: 'Solo',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), 'Solo');
    });

    test('unknown artist placeholder still yields the title', () {
      final track = TrackInfo(
        accountId: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: 'Untitled',
        artist: '   ',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), 'Untitled');
    });

    test('falls back to the original file stem when nothing matches', () {
      final track = TrackInfo(
        accountId: 'a',
        remotePath: '/m/songfile.mp3',
        fileName: 'songfile.mp3',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), 'songfile');
    });

    test('track / year placeholders render', () {
      final track = TrackInfo(
        accountId: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: 'T',
        artist: 'A',
        trackNumber: 3,
        year: 1999,
      );
      expect(
        ShareRenameService.render('{track}. {artist} - {title} ({year})', track),
        '3. A - T (1999)',
      );
    });
  });

  group('ShareRenameService.suggestedNameForTrack', () {
    test('keeps the original extension', () {
      final settings = SettingsService();
      final track = TrackInfo(
        accountId: 'a',
        remotePath: '/m/x.flac',
        fileName: 'x.flac',
        title: 'Song',
        artist: 'Band',
      );
      expect(
        ShareRenameService.suggestedNameForTrack(track, settings),
        'Band-Song.flac',
      );
    });
  });

  group('ShareRenameService.trackInfoForLibrary', () {
    test('maps tags and clip metadata across', () {
      final libraryTrack = LibraryTrack(
        accountId: 'acc',
        remotePath: '/m/song.mp3',
        fileName: 'song.mp3',
        title: 'Hello',
        artist: 'Artist',
        album: 'Album',
        trackNumber: 7,
        year: 2001,
        clipStartMs: 1000,
        clipEndMs: 5000,
      );
      final info = ShareRenameService.trackInfoForLibrary(
        libraryTrack,
        localPath: '/cache/song.mp3',
      );
      expect(info.title, 'Hello');
      expect(info.artist, 'Artist');
      expect(info.trackNumber, 7);
      expect(info.clipStart, const Duration(milliseconds: 1000));
      expect(info.clipEnd, const Duration(milliseconds: 5000));
      expect(info.localPath, '/cache/song.mp3');
    });
  });

  test('default settings enable tag-based renaming with 作者-标题', () {
    final settings = SettingsService();
    expect(settings.shareTagRenameEnabled, isTrue);
    expect(settings.shareTagRenamePattern, '{artist}-{title}');
  });
}
