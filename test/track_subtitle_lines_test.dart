import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/l10n/generated/app_localizations_zh.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/utils/track_subtitle_lines.dart';

void main() {
  final l10n = AppLocalizationsZh();

  LibraryTrack track({
    String? artist,
    String? albumArtist,
    String? album,
    int? disc,
    int? trackNo,
  }) =>
      LibraryTrack(
        musicId: 'id',
        sourceName: 's',
        remotePath: '/a.mp3',
        fileName: 'a.mp3',
        title: 'Song',
        artist: artist,
        albumArtist: albumArtist,
        album: album,
        discNumber: disc,
        trackNumber: trackNo,
        lastTagReadAt: DateTime.utc(2026),
      );

  test('line1 joins album disc track; line2 prefers artist', () {
    final s = TrackSubtitleLines.of(
      track(artist: 'A', album: 'Alb', disc: 2, trackNo: 5),
      l10n,
    );
    expect(s.line1, contains('Alb'));
    expect(s.line1, contains('2'));
    expect(s.line1, contains('5'));
    expect(s.line2, 'A');
  });

  test('line2 falls back to albumArtist then omits', () {
    expect(
      TrackSubtitleLines.of(
        track(albumArtist: 'AA', album: 'Alb', trackNo: 1),
        l10n,
      ).line2,
      'AA',
    );
    expect(
      TrackSubtitleLines.of(
        track(album: 'Alb', trackNo: 1),
        l10n,
      ).line2,
      isNull,
    );
  });
}
