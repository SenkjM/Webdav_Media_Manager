import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/services/library_shard_codec.dart';
import 'package:webdav_music_player/utils/wmp_container.dart';

LibraryTrack _track(
  String path, {
  String source = '123pan',
  int rev = 100,
  String? title,
  String? album,
  String? cueRemotePath,
  int? cueIndex,
}) {
  return LibraryTrack(
    sourceName: source,
    remotePath: path,
    fileName: path.split('/').last,
    title: title,
    artist: 'Ado',
    album: album,
    durationMs: 215000,
    trackNumber: 3,
    year: 2024,
    genre: 'J-Pop',
    cueRemotePath: cueRemotePath,
    cueTrackIndex: cueIndex,
    rev: rev,
  );
}

Uint8List _pattern(int length, [int seed = 3]) => Uint8List.fromList(
  List<int>.generate(length, (i) => (i * 17 + seed) & 0xFF),
);

void main() {
  group('LibraryShardCodec.trackToRecord / recordToTrack', () {
    test('round-trips every field a row carries', () {
      final track = _track(
        '/music/alb/01.flac',
        rev: 1750000004321,
        title: 'うっせぇわ',
        album: '心臓',
      );
      final back = LibraryShardCodec.recordToTrack(
        LibraryShardCodec.trackToRecord(track, coverIndex: 0),
        coverPath: '/local/covers/x.jpg',
      );

      expect(back.sourceName, '123pan');
      expect(back.remotePath, '/music/alb/01.flac');
      expect(back.fileName, '01.flac');
      expect(back.rev, 1750000004321);
      expect(back.title, 'うっせぇわ');
      expect(back.artist, 'Ado');
      expect(back.album, '心臓');
      expect(back.durationMs, 215000);
      expect(back.trackNumber, 3);
      expect(back.year, 2024);
      expect(back.genre, 'J-Pop');
      expect(back.coverPath, '/local/covers/x.jpg');
      // Identity is derived from the disk name + path, never stored.
      expect(back.musicId, track.musicId);
    });

    test('CUE slice identity survives', () {
      final track = _track(
        '/music/alb/disc.cue#cue:2',
        cueRemotePath: '/music/alb/disc.cue',
        cueIndex: 2,
      );
      final back = LibraryShardCodec.recordToTrack(
        LibraryShardCodec.trackToRecord(track),
      );
      expect(back.isCueVirtual, isTrue);
      expect(back.cueTrackIndex, 2);
      expect(back.musicId, track.musicId);
    });

    test('absent optional tags stay null', () {
      final back = LibraryShardCodec.recordToTrack(
        LibraryShardCodec.trackToRecord(_track('/a.mp3')),
      );
      expect(back.title, isNull);
      expect(back.album, isNull);
      expect(back.cueRemotePath, isNull);
      expect(back.coverPath, isNull);
    });
  });

  group('shard round-trip', () {
    test('tracks + their own covers survive encode/decode', () {
      final tracks = [
        _track('/music/a.flac', rev: 10),
        _track('/music/b.flac', rev: 20, title: 'B'),
      ];
      final coverA = _pattern(64, 1);
      final coverB = _pattern(48, 2);
      final bytes = LibraryShardCodec.encodeTrackShard(
        kind: WmpKind.base,
        deviceId: 'd_1',
        revFrom: 10,
        revTo: 20,
        tracks: tracks,
        coverBlobs: [coverA, coverB],
      );

      final decoded = LibraryShardCodec.decode(bytes);
      expect(decoded.kind, WmpKind.base);
      expect(decoded.deviceId, 'd_1');
      expect(decoded.revFrom, 10);
      expect(decoded.revTo, 20);
      expect(decoded.tracks.map((t) => t.remotePath), [
        '/music/a.flac',
        '/music/b.flac',
      ]);
      expect(decoded.coverCount, 2);
      expect(decoded.coverFor(0), coverA);
      expect(decoded.coverFor(1), coverB);
    });

    test('identical album covers are stored once per track (no dedupe)', () {
      final cover = _pattern(100, 9);
      final tracks = [
        for (var i = 0; i < 3; i++) _track('/music/$i.flac', rev: i + 1),
      ];
      final bytes = LibraryShardCodec.encodeTrackShard(
        kind: WmpKind.base,
        deviceId: 'd_1',
        revFrom: 1,
        revTo: 3,
        tracks: tracks,
        coverBlobs: [cover, cover, cover],
      );

      final decoded = LibraryShardCodec.decode(bytes);
      expect(decoded.coverCount, 3);
      expect(decoded.coverFor(0), cover);
      expect(decoded.coverFor(1), cover);
      expect(decoded.coverFor(2), cover);
      // Three copies really are on disk.
      final coverSectionLength = WmpContainer.fromBytes(bytes)
          .readSection(WmpSections.covers)!
          .length;
      expect(coverSectionLength, 3 * (100 + 5));
    });

    test('a row without a cover reports none', () {
      final bytes = LibraryShardCodec.encodeTrackShard(
        kind: WmpKind.seg,
        deviceId: 'd_1',
        revFrom: 5,
        revTo: 5,
        tracks: [_track('/music/x.flac', rev: 5)],
        coverBlobs: [null],
      );
      final decoded = LibraryShardCodec.decode(bytes);
      expect(decoded.coverCount, 0);
      expect(decoded.coverFor(0), isNull);
    });

    test('tombstone shard round-trips', () {
      final bytes = LibraryShardCodec.encodeTombShard(
        deviceId: 'd_7ab1',
        revFrom: 100,
        revTo: 105,
        tombstones: [
          (
            sourceName: '123pan',
            remotePath: '/music/gone.flac',
            rev: 105,
            deletedAt: DateTime.utc(2026, 3, 1),
          ),
        ],
      );

      final decoded = LibraryShardCodec.decode(bytes);
      expect(decoded.kind, WmpKind.tomb);
      expect(decoded.trackCount, 0);
      expect(decoded.tombstoneCount, 1);
      expect(decoded.tombstones.single['source_name'], '123pan');
      expect(decoded.tombstones.single['remote_path'], '/music/gone.flac');
      expect(decoded.tombstones.single['rev'], 105);
      expect(
        decoded.tombstones.single['deleted_at'],
        '2026-03-01T00:00:00.000Z',
      );
    });

    test('an empty shard decodes to nothing rather than throwing', () {
      final bytes = LibraryShardCodec.encodeTrackShard(
        kind: WmpKind.seg,
        deviceId: 'd_1',
        revFrom: 0,
        revTo: 0,
        tracks: const [],
        coverBlobs: const [],
      );
      final decoded = LibraryShardCodec.decode(bytes);
      expect(decoded.tracks, isEmpty);
      expect(decoded.coverCount, 0);
    });

    test('a shard mixes sources (one library, per-track disk name)', () {
      final bytes = LibraryShardCodec.encodeTrackShard(
        kind: WmpKind.base,
        deviceId: 'd_1',
        revFrom: 1,
        revTo: 2,
        tracks: [
          _track('/a.flac', source: '123pan', rev: 1),
          _track('/a.flac', source: 'aliyun', rev: 2),
        ],
        coverBlobs: [null, null],
      );
      final decoded = LibraryShardCodec.decode(bytes);
      expect(decoded.tracks.map((t) => t.sourceName), ['123pan', 'aliyun']);
      // Same path on different disks = different songs.
      expect(decoded.tracks[0].musicId, isNot(decoded.tracks[1].musicId));
    });
  });
}
