import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/utils/cover_image.dart';
import 'package:webdav_music_player/utils/track_identity.dart';
import 'package:webdav_music_player/utils/webdav_errors.dart';

void main() {
  group('track identity key', () {
    test('binds accountId + remotePath uniquely', () {
      final a = trackIdentityKey('acc1', '/music/song.mp3');
      final b = trackIdentityKey('acc2', '/music/song.mp3');
      final c = trackIdentityKey('acc1', '/music/other.mp3');
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(a, contains('acc1'));
      expect(a, contains('/music/song.mp3'));
    });

    test('LibraryTrack.identityKey matches helper', () {
      final t = LibraryTrack(
        accountId: 'x',
        remotePath: '/a/b.flac',
        fileName: 'b.flac',
      );
      expect(t.identityKey, trackIdentityKey('x', '/a/b.flac'));
    });

    test('same filename different accounts are distinct library rows', () {
      final t1 = LibraryTrack(
        accountId: 'a1',
        remotePath: '/same/name.mp3',
        fileName: 'name.mp3',
        title: 'One',
      );
      final t2 = LibraryTrack(
        accountId: 'a2',
        remotePath: '/same/name.mp3',
        fileName: 'name.mp3',
        title: 'Two',
      );
      expect(t1.identityKey, isNot(equals(t2.identityKey)));
    });
  });

  group('cover thumb policy', () {
    test('resizeCoverToThumb produces ${coverThumbSize}x$coverThumbSize JPEG',
        () {
      final src = img.Image(width: 400, height: 300);
      img.fill(src, color: img.ColorRgb8(255, 0, 0));
      final bytes = Uint8List.fromList(img.encodePng(src));
      final thumb = resizeCoverToThumb(bytes);
      expect(thumb, isNotNull);
      final decoded = img.decodeJpg(thumb!);
      expect(decoded, isNotNull);
      expect(decoded!.width, coverThumbSize);
      expect(decoded.height, coverThumbSize);
      expect(isCoverThumbSize(decoded.width, decoded.height), isTrue);
    });

    test('invalid bytes return null', () {
      expect(resizeCoverToThumb(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('resizeCoverToThumb respects custom size', () {
      final src = img.Image(width: 400, height: 300);
      img.fill(src, color: img.ColorRgb8(0, 128, 255));
      final bytes = Uint8List.fromList(img.encodePng(src));
      final thumb = resizeCoverToThumb(bytes, size: coverThumbSizeLarge);
      expect(thumb, isNotNull);
      final decoded = img.decodeJpg(thumb!);
      expect(decoded!.width, coverThumbSizeLarge);
      expect(decoded.height, coverThumbSizeLarge);
    });
  });

  group('library survives cache delete (policy)', () {
    test('library record fields are independent of local audio path', () {
      // Metadata persistence does not store audio cache path — only cover thumb.
      final t = LibraryTrack(
        accountId: 'acc',
        remotePath: '/r/t.mp3',
        fileName: 't.mp3',
        title: 'Keep Me',
        artist: 'Artist',
        album: 'Album',
        coverPath: '/docs/covers/abc.jpg',
      );
      final map = t.toMap();
      expect(map.containsKey('local_path'), isFalse);
      expect(map['cover_path'], '/docs/covers/abc.jpg');
      expect(map['title'], 'Keep Me');
      expect(map.containsKey('track_number'), isTrue);
      expect(map.containsKey('disc_number'), isTrue);
      expect(map.containsKey('album_artist'), isTrue);
      expect(map.containsKey('year'), isTrue);
      expect(map.containsKey('genre'), isTrue);
      expect(map.containsKey('bitrate'), isTrue);
      expect(map.containsKey('sample_rate'), isTrue);
      final roundtrip = LibraryTrack.fromMap(map);
      expect(roundtrip.title, 'Keep Me');
      expect(roundtrip.coverPath, '/docs/covers/abc.jpg');
    });
  });

  group('webdav permission errors', () {
    test('detects 401/403', () {
      expect(isWebDavPermissionError(Exception('HTTP 401 Unauthorized')), isTrue);
      expect(isWebDavPermissionError(Exception('status: 403')), isTrue);
      expect(isWebDavPermissionError(Exception('network timeout')), isFalse);
    });
  });
}
