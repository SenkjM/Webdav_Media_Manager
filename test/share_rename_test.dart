import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/services/share_rename_service.dart';

void main() {
  group('ShareRenameService.render', () {
    test('default 作者-标题 pattern', () {
      final track = TrackInfo(
        sourceName: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: '夜曲',
        artist: '周杰伦',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), '周杰伦-夜曲');
    });

    test('missing fields collapse instead of leaving dangling separators', () {
      final track = TrackInfo(
        sourceName: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: 'Solo',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), 'Solo');
    });

    test('unknown artist placeholder still yields the title', () {
      final track = TrackInfo(
        sourceName: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: 'Untitled',
        artist: '   ',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), 'Untitled');
    });

    test('falls back to the original file stem when nothing matches', () {
      final track = TrackInfo(
        sourceName: 'a',
        remotePath: '/m/songfile.mp3',
        fileName: 'songfile.mp3',
      );
      expect(ShareRenameService.render('{artist}-{title}', track), 'songfile');
    });

    test('track / year placeholders render', () {
      final track = TrackInfo(
        sourceName: 'a',
        remotePath: '/m/x.mp3',
        fileName: 'x.mp3',
        title: 'T',
        artist: 'A',
        trackNumber: 3,
        year: 1999,
      );
      expect(
        ShareRenameService.render(
          '{track}. {artist} - {title} ({year})',
          track,
        ),
        '3. A - T (1999)',
      );
    });
  });

  group('ShareRenameService.suggestedNameForTrack', () {
    test('keeps the original extension', () {
      final settings = SettingsService();
      final track = TrackInfo(
        sourceName: 'a',
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
        sourceName: 'acc',
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

  group('finalizeEditedName (分享对话框只编辑主文件名)', () {
    test('puts the source extension back', () {
      expect(
        ShareRenameService.finalizeEditedName('Ado-うっせぇわ', 'x.flac'),
        'Ado-うっせぇわ.flac',
      );
    });

    test('a dotted title is not mistaken for an extension', () {
      // The real report: `01. Also sprach Zarathustra` has a dot in the stem.
      expect(
        ShareRenameService.finalizeEditedName(
          '01. Also sprach Zarathustra',
          'track01.flac',
        ),
        '01. Also sprach Zarathustra.flac',
      );
      expect(
        ShareRenameService.finalizeEditedName(
          '2. Peer Gynt Suite No. 1',
          'a.mp3',
        ),
        '2. Peer Gynt Suite No. 1.mp3',
      );
    });

    test('never duplicates the same extension', () {
      expect(
        ShareRenameService.finalizeEditedName('song.flac', 'x.flac'),
        'song.flac',
      );
      expect(
        ShareRenameService.finalizeEditedName('song.FLAC', 'x.flac'),
        'song.FLAC',
      );
    });

    test('a typed media extension is replaced, not stacked', () {
      expect(
        ShareRenameService.finalizeEditedName('song.mp3', 'x.flac'),
        'song.flac',
      );
      expect(
        ShareRenameService.finalizeEditedName('clip.mp4', 'v.mkv'),
        'clip.mkv',
      );
    });

    test('a non-media trailing dot stays part of the stem', () {
      expect(
        ShareRenameService.finalizeEditedName('Mr.', 'x.flac'),
        'Mr..flac',
      );
    });

    test('empty input keeps the "use the original name" signal', () {
      expect(ShareRenameService.finalizeEditedName('', 'x.flac'), '');
      expect(ShareRenameService.finalizeEditedName('   ', 'x.flac'), '');
    });

    test('a source file without an extension stays without one', () {
      expect(ShareRenameService.finalizeEditedName('song', 'noext'), 'song');
    });
  });
}
