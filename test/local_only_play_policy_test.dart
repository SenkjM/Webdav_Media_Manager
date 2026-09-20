import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/theme/app_theme.dart';

void main() {
  test('local vs remote indicator colors are distinct and light-friendly', () {
    expect(AppColors.localReady, isNot(equals(AppColors.remotePlaceholder)));
    // Green and soft gray should both be readable on light backgrounds.
    expect(AppColors.localReady.computeLuminance(), lessThan(0.5));
    expect(AppColors.remotePlaceholder.computeLuminance(), greaterThan(0.3));
  });

  test('library track identity uses effective audio path for cue members', () {
    final cue = LibraryTrack(
      accountId: 'a1',
      remotePath: '/album/disc.cue#cue:2',
      fileName: 'Track 02',
      cueRemotePath: '/album/disc.cue',
      cueTrackIndex: 2,
      audioRemotePath: '/album/disc.flac',
    );
    expect(cue.isCueVirtual, isTrue);
    expect(cue.effectiveAudioRemotePath, '/album/disc.flac');

    final plain = LibraryTrack(
      accountId: 'a1',
      remotePath: '/album/song.mp3',
      fileName: 'song.mp3',
    );
    expect(plain.isCueVirtual, isFalse);
    expect(plain.effectiveAudioRemotePath, '/album/song.mp3');
  });
}
