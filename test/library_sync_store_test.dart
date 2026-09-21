import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/library_track.dart';
import 'package:webdav_music_player/services/library_sync_store.dart';
import 'package:webdav_music_player/utils/track_identity.dart';

LibraryTrack _t(
  String path, {
  String source = '123pan',
  required int rev,
  String? title,
}) => LibraryTrack(
  sourceName: source,
  remotePath: path,
  fileName: path.split('/').last,
  title: title,
  rev: rev,
);

Map<String, dynamic> _tomb(
  String path, {
  String source = '123pan',
  required int rev,
}) => {
  'source_name': source,
  'remote_path': path,
  'rev': rev,
  'deleted_at': '2026-01-01T00:00:00.000Z',
};

void main() {
  group('mergeCloudParts', () {
    test('higher rev wins regardless of part order', () {
      final forward = mergeCloudParts(
        dataParts: [
          [_t('/a.flac', rev: 1, title: '旧')],
          [_t('/a.flac', rev: 2, title: '新')],
        ],
        tombstoneParts: const [],
      );
      final backward = mergeCloudParts(
        dataParts: [
          [_t('/a.flac', rev: 2, title: '新')],
          [_t('/a.flac', rev: 1, title: '旧')],
        ],
        tombstoneParts: const [],
      );
      expect(forward.tracks.single.title, '新');
      expect(backward.tracks.single.title, '新');
      expect(forward.tracks, hasLength(1));
    });

    test('a tombstone hides the row it names', () {
      final merged = mergeCloudParts(
        dataParts: [
          [_t('/a.flac', rev: 5), _t('/b.flac', rev: 6)],
        ],
        tombstoneParts: [
          [_tomb('/a.flac', rev: 7)],
        ],
      );
      expect(merged.tracks.map((t) => t.remotePath), ['/b.flac']);
      expect(
        merged.tombstonedKeys,
        contains(trackIdentityKey('123pan', '/a.flac')),
      );
    });

    test('a re-download after the deletion survives it', () {
      // Tombstone at rev 7, the song came back at rev 9 → it is alive again.
      final merged = mergeCloudParts(
        dataParts: [
          [_t('/a.flac', rev: 9, title: '回来了')],
        ],
        tombstoneParts: [
          [_tomb('/a.flac', rev: 7)],
        ],
      );
      expect(merged.tracks, hasLength(1));
      expect(merged.tracks.single.title, '回来了');
    });

    test('a tombstone newer than the row wins', () {
      final merged = mergeCloudParts(
        dataParts: [
          [_t('/a.flac', rev: 3)],
        ],
        tombstoneParts: [
          [_tomb('/a.flac', rev: 4)],
        ],
      );
      expect(merged.tracks, isEmpty);
    });

    test('the same path on two disks stays two songs', () {
      final merged = mergeCloudParts(
        dataParts: [
          [
            _t('/same.flac', source: '123pan', rev: 1),
            _t('/same.flac', source: 'aliyun', rev: 1),
          ],
        ],
        tombstoneParts: const [],
      );
      expect(merged.tracks, hasLength(2));
      expect(merged.tracks.map((t) => t.sourceName), ['123pan', 'aliyun']);
    });

    test('a tombstone on one disk does not hide the other disk', () {
      final merged = mergeCloudParts(
        dataParts: [
          [
            _t('/same.flac', source: '123pan', rev: 1),
            _t('/same.flac', source: 'aliyun', rev: 1),
          ],
        ],
        tombstoneParts: [
          [_tomb('/same.flac', source: '123pan', rev: 5)],
        ],
      );
      expect(merged.tracks.single.sourceName, 'aliyun');
    });

    test('first-appearance order is preserved', () {
      final merged = mergeCloudParts(
        dataParts: [
          [_t('/1.flac', rev: 1), _t('/2.flac', rev: 1)],
          [_t('/3.flac', rev: 1)],
        ],
        tombstoneParts: const [],
      );
      expect(merged.tracks.map((t) => t.remotePath), [
        '/1.flac',
        '/2.flac',
        '/3.flac',
      ]);
    });

    test('an empty cloud yields nothing', () {
      final merged = mergeCloudParts(
        dataParts: const [],
        tombstoneParts: const [],
      );
      expect(merged.tracks, isEmpty);
      expect(merged.tombstonedKeys, isEmpty);
    });
  });

  group('LibraryManifest', () {
    test('JSON round-trips base shards and parts', () {
      final manifest = LibraryManifest(
        baseUpTo: 1750000000000,
        shards: const [
          BaseShard(file: 'lib-0001-a1.wmp', count: 500, bytes: 412233),
        ],
        segments: const [
          IndexPart(file: 'seg-1-b2.wmp', from: 1, to: 9, count: 3, bytes: 700),
        ],
        tombstones: const [
          IndexPart(
            file: 'del-2-c3.wmp',
            from: 10,
            to: 10,
            count: 1,
            bytes: 220,
          ),
        ],
      );

      final back = LibraryManifest.fromJson(manifest.toJson());
      expect(back.baseUpTo, 1750000000000);
      expect(back.shards.single.file, 'lib-0001-a1.wmp');
      expect(back.shards.single.count, 500);
      expect(back.segments.single.to, 9);
      expect(back.tombstones.single.file, 'del-2-c3.wmp');
    });

    test('fragment counters drive the rebuild hint', () {
      final manifest = LibraryManifest(
        segments: const [
          IndexPart(file: 'a', from: 0, to: 1, count: 1, bytes: 100),
          IndexPart(file: 'b', from: 2, to: 3, count: 1, bytes: 150),
        ],
        tombstones: const [
          IndexPart(file: 'c', from: 4, to: 4, count: 1, bytes: 50),
        ],
      );
      expect(manifest.fragmentCount, 3);
      expect(manifest.fragmentBytes, 300);
      expect(
        manifest.fragmentCount >= LibrarySyncStore.suggestRebuildAtFragments,
        isFalse,
      );
    });

    test('a pre-container index reads as empty (no compatibility branch)', () {
      final back = LibraryManifest.fromJson({
        'format': 'webdav_music_player_library_index',
        'tracks': [
          {'remote_path': '/a.flac'},
        ],
      });
      expect(back.isEmpty, isTrue);
    });
  });

  group('libraryTrackCountForEstimate', () {
    test('scales the measured sample to the whole library', () {
      // 500 rows measured at 50 KB total → 1000 rows ≈ 100 KB.
      expect(
        libraryTrackCountForEstimate(
          shards: 2,
          perShardSampleBytes: 50000,
          sampleCount: 500,
          total: 1000,
        ),
        100000,
      );
    });

    test('an empty library estimates zero', () {
      expect(
        libraryTrackCountForEstimate(
          shards: 0,
          perShardSampleBytes: 0,
          sampleCount: 0,
          total: 0,
        ),
        0,
      );
    });
  });

  group('auditLibraryParts', () {
    LibraryManifest manifestWith({
      List<String> extraSegments = const [],
    }) => LibraryManifest(
      baseUpTo: 100,
      shards: const [BaseShard(file: 'lib-0001-aa.wmp', count: 2, bytes: 100)],
      segments: [
        const IndexPart(
          file: 'seg-1-bb.wmp',
          from: 1,
          to: 2,
          count: 1,
          bytes: 50,
        ),
        for (final f in extraSegments)
          IndexPart(file: f, from: 3, to: 4, count: 1, bytes: 50),
      ],
      tombstones: const [
        IndexPart(file: 'del-3-cc.wmp', from: 5, to: 5, count: 1, bytes: 20),
      ],
    );

    test('a consistent cloud has no orphans and no gaps', () {
      final audit = auditLibraryParts(
        present: const [
          (name: 'lib-0001-aa.wmp', size: 100),
          (name: 'seg-1-bb.wmp', size: 50),
          (name: 'del-3-cc.wmp', size: 20),
        ],
        manifest: manifestWith(),
      );
      expect(audit.healthy, isTrue);
      expect(audit.baseShards, 1);
      expect(audit.segments, 1);
      expect(audit.tombstones, 1);
      expect(audit.totalBytes, 170);
    });

    test('unreferenced part files are reported as orphans', () {
      final audit = auditLibraryParts(
        present: const [
          (name: 'lib-0001-aa.wmp', size: 100),
          (name: 'seg-1-bb.wmp', size: 50),
          (name: 'del-3-cc.wmp', size: 20),
          (name: 'seg-9-zz.wmp', size: 999),
        ],
        manifest: manifestWith(),
      );
      expect(audit.orphans, ['seg-9-zz.wmp']);
      expect(audit.missing, isEmpty);
      expect(audit.healthy, isFalse);
      expect(audit.summary, contains('孤儿文件 1 个'));
    });

    test('unrelated files (the manifest itself, covers) are not orphans', () {
      final audit = auditLibraryParts(
        present: const [
          (name: 'index.json', size: 300),
          (name: 'lib-0001-aa.wmp', size: 100),
          (name: 'seg-1-bb.wmp', size: 50),
          (name: 'del-3-cc.wmp', size: 20),
        ],
        manifest: manifestWith(),
      );
      expect(audit.orphans, isEmpty);
      expect(audit.healthy, isTrue);
    });

    test('a referenced file that is gone is a gap', () {
      final audit = auditLibraryParts(
        present: const [
          (name: 'lib-0001-aa.wmp', size: 100),
          (name: 'del-3-cc.wmp', size: 20),
        ],
        manifest: manifestWith(),
      );
      expect(audit.missing, ['seg-1-bb.wmp']);
      expect(audit.summary, contains('缺失文件 1 个'));
    });
  });
}
