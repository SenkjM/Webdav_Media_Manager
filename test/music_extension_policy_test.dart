import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/file_type_config.dart';

/// Regression guard: the download queue used to gate library ingest on a
/// hard-coded extension list that omitted `.m4a` / `.aac`, so those downloads
/// threw inside `LibraryService.ingestDownloaded` and showed up as failed.
///
/// The queue now classifies with the configured sets, which is what the network
/// library uses too. These tests pin the configured-list behavior.
void main() {
  group('configured music extensions are the source of truth', () {
    final config = FileTypeConfig();

    test('.m4a and .aac count as music (regression)', () {
      expect(config.categoryFor('song.m4a'), FileCategory.music);
      expect(config.categoryFor('song.aac'), FileCategory.music);
    });

    test('all default music extensions classify as music', () {
      for (final ext in FileTypeConfig.defaultMusicExtensions) {
        expect(
          config.categoryFor('track.$ext'),
          FileCategory.music,
          reason: '.$ext should be music',
        );
      }
    });

    test('custom extension added by the user counts as music', () {
      final custom = FileTypeConfig(
        musicExtensions: ['mp3', 'tak'],
      );
      expect(custom.categoryFor('song.tak'), FileCategory.music);
      expect(custom.categoryFor('song.mp3'), FileCategory.music);
      // Removed from the set → no longer music.
      expect(custom.categoryFor('song.flac'), FileCategory.other);
    });

    test('video and cue are never classified as music', () {
      expect(config.categoryFor('movie.mkv'), FileCategory.video);
      expect(config.categoryFor('album.cue'), FileCategory.cue);
      expect(config.categoryFor('notes.txt'), FileCategory.other);
    });
  });
}
