import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/services/cache_service.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

void main() {
  group('music_id stability', () {
    test('normal track is hash(accountId + normalized remotePath)', () {
      final a = musicIdForRemote('acc1', '/music/song.mp3');
      final b = musicIdForRemote('acc1', '/music/song.mp3');
      final c = musicIdForRemote('acc1', 'music/song.mp3'); // missing leading /
      final d = musicIdForRemote('acc2', '/music/song.mp3');
      expect(a, b);
      expect(a, c); // normalized
      expect(a, isNot(equals(d)));
      expect(a.length, 40); // sha1 hex
      expect(a, isNot(contains('/')));
    });

    test('CUE slice is hash(accountId + cuePath + trackIndex)', () {
      final s1 = musicIdForCueSlice('acc', '/album/disc.cue', 1);
      final s2 = musicIdForCueSlice('acc', '/album/disc.cue', 2);
      final s1b = musicIdForCueSlice('acc', 'album/disc.cue', 1);
      expect(s1, s1b);
      expect(s1, isNot(equals(s2)));
      expect(s1, isNot(equals(musicIdForRemote('acc', '/album/disc.flac'))));
    });

    test('LibraryTrack.musicId uses cue formula for virtual rows', () {
      final cue = LibraryTrack(
        sourceName: 'a1',
        remotePath: '/album/disc.flac#cue:2',
        fileName: 'Track 02',
        cueRemotePath: '/album/disc.cue',
        cueTrackIndex: 2,
        audioRemotePath: '/album/disc.flac',
      );
      expect(cue.musicId, musicIdForCueSlice('a1', '/album/disc.cue', 2));
      expect(
        cue.cacheMusicId,
        musicIdForRemote('a1', '/album/disc.flac'),
      );
      expect(cue.musicId, isNot(equals(cue.cacheMusicId)));
    });

    test('same path different accounts get distinct music_ids', () {
      final t1 = LibraryTrack(
        sourceName: 'a1',
        remotePath: '/same/name.mp3',
        fileName: 'name.mp3',
      );
      final t2 = LibraryTrack(
        sourceName: 'a2',
        remotePath: '/same/name.mp3',
        fileName: 'name.mp3',
      );
      expect(t1.musicId, isNot(equals(t2.musicId)));
    });

    test('identityHashStem is stable prefix of music_id', () {
      final id = musicIdForRemote('acc', '/r/t.mp3');
      expect(identityHashStem('acc', '/r/t.mp3'), id.substring(0, 16));
    });
  });

  group('cue bidirectional relations (model)', () {
    test('slice points to cue + original audio', () {
      final slice = LibraryTrack(
        sourceName: 'acc',
        remotePath: cueVirtualRemotePath('/a/x.flac', 3),
        fileName: '03',
        cueId: cueIdFor('acc', '/a/x.cue'),
        cueRemotePath: '/a/x.cue',
        cueTrackIndex: 3,
        audioMusicId: musicIdForRemote('acc', '/a/x.flac'),
        audioRemotePath: '/a/x.flac',
      );
      expect(slice.isCueVirtual, isTrue);
      expect(slice.cueId, cueIdFor('acc', '/a/x.cue'));
      expect(slice.audioMusicId, musicIdForRemote('acc', '/a/x.flac'));
      expect(slice.effectiveAudioRemotePath, '/a/x.flac');
    });

    test('cueId is stable for account + cue path', () {
      expect(
        cueIdFor('acc', '/a/x.cue'),
        cueIdFor('acc', 'a/x.cue'),
      );
      expect(
        cueIdFor('acc', '/a/x.cue'),
        isNot(equals(cueIdFor('other', '/a/x.cue'))),
      );
    });
  });

  group('isLocal requires annex + file exists', () {
    test('policy: missing annex → not local', () {
      expect(
        CacheService.isLocalPolicy(annexLocalPath: null, fileExists: true),
        isFalse,
      );
      expect(
        CacheService.isLocalPolicy(annexLocalPath: '', fileExists: true),
        isFalse,
      );
    });

    test('policy: annex + missing file → not local', () {
      expect(
        CacheService.isLocalPolicy(
          annexLocalPath: '/cache/a.mp3',
          fileExists: false,
        ),
        isFalse,
      );
    });

    test('policy: annex + file exists → local', () {
      expect(
        CacheService.isLocalPolicy(
          annexLocalPath: '/cache/a.mp3',
          fileExists: true,
        ),
        isTrue,
      );
    });
  });

  group('CUE multi-slice UX label', () {
    test('virtual cue track exposes 多歌曲合并分片', () {
      final cue = LibraryTrack(
        sourceName: 'a',
        remotePath: '/a.flac#cue:1',
        fileName: '01',
        cueRemotePath: '/a.cue',
        cueTrackIndex: 1,
        audioRemotePath: '/a.flac',
      );
      expect(cue.cueTypeLabel, LibraryTrack.cueMultiSliceLabel);
      expect(cue.cueTypeLabel, '多歌曲合并分片');
      final plain = LibraryTrack(
        sourceName: 'a',
        remotePath: '/b.mp3',
        fileName: 'b.mp3',
      );
      expect(plain.cueTypeLabel, isNull);
    });
  });

  group('backup restore leaves uncached without files', () {
    test('library maps never carry local_path as cached truth', () {
      final t = LibraryTrack(
        sourceName: 'acc',
        remotePath: '/r/t.mp3',
        fileName: 't.mp3',
        title: 'Keep',
      );
      final map = t.toMap();
      expect(map.containsKey('local_path'), isFalse);
      expect(map['music_id'], t.musicId);
      // Restore must not invent cache from track metadata.
      expect(map['music_id'], isNotEmpty);
    });

    test('unified library payload marks cache empty', () {
      // Contract of backup formatVersion 3 library.json
      final payload = {
        'accountId': 'acc',
        'tracks': [
          LibraryTrack(
            sourceName: 'acc',
            remotePath: '/a.mp3',
            fileName: 'a.mp3',
          ).toMap(),
        ],
        'cueAlbums': <Map<String, dynamic>>[],
        'cueSlices': <Map<String, dynamic>>[],
        'cache': <Map<String, dynamic>>[],
      };
      expect(payload['cache'], isEmpty);
      final roundtrip = LibraryTrack.fromMap(
        Map<String, dynamic>.from(
          (payload['tracks'] as List).first as Map,
        ),
      );
      expect(roundtrip.musicId, musicIdForRemote('acc', '/a.mp3'));
    });
  });
}
