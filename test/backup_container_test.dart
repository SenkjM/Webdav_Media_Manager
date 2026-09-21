import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/services/library_shard_codec.dart';
import 'package:webdav_music_player/utils/wmp_container.dart';

/// The backup archive is a container: META + TRACKS (every row, CUE slices
/// included) + raw COVERS (one own copy per row) + JSON side sections.
/// This mirrors `BackupService.buildArchiveBytes` without touching the
/// filesystem, so the *format* is pinned even though the service itself needs
/// path_provider.
LibraryTrack _track(
  String path, {
  String source = '123pan',
  int rev = 7,
  String? cueRemotePath,
  int? cueIndex,
}) => LibraryTrack(
  sourceName: source,
  remotePath: path,
  fileName: path.split('/').last,
  title: '标题',
  artist: 'Ado',
  album: '心臓',
  cueRemotePath: cueRemotePath,
  cueTrackIndex: cueIndex,
  rev: rev,
);

Uint8List _blob(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i + seed) & 0xFF));

void main() {
  group('backup container', () {
    test('round-trips rows, per-track covers and the JSON side sections', () {
      final tracks = [
        _track('/m/a.flac'),
        _track(
          '/m/disc.cue#cue:2',
          rev: 8,
          cueRemotePath: '/m/disc.cue',
          cueIndex: 2,
        ),
        _track('/m/b.flac', source: 'aliyun', rev: 9),
      ];
      final coverA = _blob(32, 1);
      final coverC = _blob(48, 3);
      final blobs = <Uint8List?>[coverA, null, coverC];

      final records = <Map<int, Object?>>[];
      var coverIndex = 0;
      for (var i = 0; i < tracks.length; i++) {
        final has = blobs[i] != null;
        records.add(
          LibraryShardCodec.trackToRecord(
            tracks[i],
            coverIndex: has ? coverIndex++ : null,
          ),
        );
      }
      final container = WmpContainer.encode(
        {
          WmpSections.meta: encodeRecords([
            {
              WmpMeta.kind: WmpKind.backup,
              WmpMeta.count: tracks.length,
              WmpMeta.deviceId: 'dev-1',
              WmpMeta.note: jsonEncode({
                'format': 'webdav_music_player_backup',
                'formatVersion': 5,
                'activeAccountId': 'acc-1',
                'passwordEncryption': 'aes-256-gcm',
              }),
            },
          ]),
          WmpSections.tracks: encodeRecords(records),
          WmpSections.covers: buildCoverSection([
            (bytes: coverA, kind: WmpImageKind.jpeg),
            (bytes: coverC, kind: WmpImageKind.webp),
          ]),
          WmpSections.credentials: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'accounts': [
                  {'id': 'acc-1', 'name': '123pan', 'password': 'AESGCMv1:x'},
                ],
              }),
            ),
          ),
          WmpSections.playlists: Uint8List.fromList(
            utf8.encode(
              jsonEncode([
                {'id': 'pl-1', 'name': '最爱'},
              ]),
            ),
          ),
          WmpSections.settings: Uint8List.fromList(
            utf8.encode(jsonEncode({'cache_retention': 'one_week'})),
          ),
          WmpSections.cueAlbums: Uint8List.fromList(
            utf8.encode(
              jsonEncode([
                {'cue_id': 'c1', 'title': '专辑'},
              ]),
            ),
          ),
        },
        rawIds: {WmpSections.covers},
      );

      // Sanity: it really is a container, not JSON.
      expect(WmpContainer.looksLikeContainer(container), isTrue);

      final parsed = WmpContainer.fromBytes(container);
      final meta = decodeRecords(
        parsed.readSection(WmpSections.meta)!,
        intTags: kMetaIntTags,
      ).single;
      expect(meta[WmpMeta.kind], WmpKind.backup);
      expect(meta[WmpMeta.count], 3);
      final header = jsonDecode(meta[WmpMeta.note] as String) as Map;
      expect(header['activeAccountId'], 'acc-1');
      expect(header['passwordEncryption'], 'aes-256-gcm');

      final rows = decodeRecords(
        parsed.readSection(WmpSections.tracks)!,
        intTags: kTrackIntTags,
      );
      expect(rows, hasLength(3));
      final coversRaw = parsed.readSection(WmpSections.covers)!;
      final coverTable = parseCoverSection(coversRaw);
      expect(coverTable, hasLength(2));

      final restored = <LibraryTrack>[];
      for (final row in rows) {
        restored.add(LibraryShardCodec.recordToTrack(row));
      }
      expect(restored[0].sourceName, '123pan');
      expect(restored[1].isCueVirtual, isTrue);
      expect(restored[2].sourceName, 'aliyun');
      // Cover indexes point at this row's own blob.
      expect(rows[0][WmpTrack.coverIndex], 0);
      expect(rows[1].containsKey(WmpTrack.coverIndex), isFalse);
      expect(rows[2][WmpTrack.coverIndex], 1);
      expect(coverTable[0].bytesIn(coversRaw), coverA);
      expect(coverTable[1].bytesIn(coversRaw), coverC);
      expect(coverTable[0].kind, WmpImageKind.jpeg);
      expect(coverTable[1].kind, WmpImageKind.webp);

      final creds = jsonDecode(
        utf8.decode(parsed.readSection(WmpSections.credentials)!),
      ) as Map;
      expect((creds['accounts'] as List).single['name'], '123pan');
      expect(
        jsonDecode(
          utf8.decode(parsed.readSection(WmpSections.playlists)!),
        )[0]['name'],
        '最爱',
      );
      expect(
        jsonDecode(
          utf8.decode(parsed.readSection(WmpSections.cueAlbums)!),
        )[0]['title'],
        '专辑',
      );
    });

    test('a readable JSON export is not mistaken for a container', () {
      final json = utf8.encode(
        jsonEncode({
          'format': 'webdav_music_player_backup',
          'formatVersion': 5,
          'library': {'tracks': <dynamic>[]},
        }),
      );
      expect(
        WmpContainer.looksLikeContainer(Uint8List.fromList(json)),
        isFalse,
      );
    });

    test('a container body survives the deflate round-trip byte for byte', () {
      final container = WmpContainer.encode({
        WmpSections.settings: Uint8List.fromList(
          utf8.encode(jsonEncode({'a': 1, 'b': '中文'})),
        ),
      });
      final parsed = WmpContainer.fromBytes(container);
      expect(
        jsonDecode(utf8.decode(parsed.readSection(WmpSections.settings)!)),
        {'a': 1, 'b': '中文'},
      );
    });
  });
}
