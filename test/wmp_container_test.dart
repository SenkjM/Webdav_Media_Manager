import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';

List<int> _pattern(int length, [int seed = 7]) =>
    List<int>.generate(length, (i) => (i * 31 + seed) & 0xFF);

void main() {
  group('varint', () {
    test('round-trips across boundaries', () {
      for (final value in [
        0,
        1,
        127,
        128,
        300,
        16383,
        16384,
        1 << 20,
        1 << 31,
        1 << 45,
      ]) {
        final encoded = encodeVarint(value);
        final (decoded, next) = decodeVarint(encoded, 0);
        expect(decoded, value, reason: 'value $value');
        expect(next, encoded.length);
      }
    });

    test('rejects negative values', () {
      expect(() => encodeVarint(-1), throwsA(isA<WmpFormatException>()));
    });

    test('rejects a truncated varint', () {
      expect(
        () => decodeVarint(Uint8List.fromList([0x80, 0x80]), 0),
        throwsA(isA<WmpFormatException>()),
      );
    });
  });

  group('crc32', () {
    test('matches known vectors', () {
      expect(crc32(utf8.encode('')), 0x00000000);
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
      expect(
        crc32(utf8.encode('The quick brown fox jumps over the lazy dog')),
        0x414FA339,
      );
    });
  });

  group('records', () {
    test('round-trips ints and strings including CJK and empty', () {
      final raw = encodeRecords([
        {
          WmpTrack.sourceName: '123pan',
          WmpTrack.remotePath: '/music/日本語 タイトル.flac',
          WmpTrack.fileName: 'a.flac',
          WmpTrack.rev: 1750000004321,
          WmpTrack.title: 'うっせぇわ',
          WmpTrack.album: '',
          WmpTrack.durationMs: 0,
          WmpTrack.coverIndex: 3,
        },
        {
          WmpTrack.sourceName: '我的网盘',
          WmpTrack.remotePath: '/x.mp3',
          WmpTrack.rev: 1,
        },
      ]);

      final records = decodeRecords(raw, intTags: kTrackIntTags);
      expect(records, hasLength(2));
      expect(records[0][WmpTrack.sourceName], '123pan');
      expect(records[0][WmpTrack.remotePath], '/music/日本語 タイトル.flac');
      expect(records[0][WmpTrack.title], 'うっせぇわ');
      expect(records[0][WmpTrack.album], '');
      expect(records[0][WmpTrack.rev], 1750000004321);
      expect(records[0][WmpTrack.durationMs], 0);
      expect(records[0][WmpTrack.coverIndex], 3);
      // Absent optional fields stay absent.
      expect(records[1].containsKey(WmpTrack.album), isFalse);
      expect(records[1][WmpTrack.sourceName], '我的网盘');
    });

    test('tag numbering is per section family', () {
      // Tag 1 is META.kind (int) *and* TRACK.sourceName (string): decoding with
      // the wrong tag set must not silently produce garbage.
      final meta = encodeRecords([
        {WmpMeta.kind: WmpKind.base, WmpMeta.deviceId: 'd_1'},
      ]);
      final asMeta = decodeRecords(meta, intTags: kMetaIntTags);
      expect(asMeta.single[WmpMeta.kind], WmpKind.base);

      final track = encodeRecords([
        {WmpTrack.sourceName: '123pan'},
      ]);
      final asTrack = decodeRecords(track, intTags: kTrackIntTags);
      expect(asTrack.single[WmpTrack.sourceName], '123pan');
    });

    test('an unterminated record is rejected', () {
      final raw = Uint8List.fromList([WmpTrack.rev, 0x05]);
      expect(
        () => decodeRecords(raw, intTags: kTrackIntTags),
        throwsA(isA<WmpFormatException>()),
      );
    });

    test('an empty list encodes to nothing', () {
      expect(encodeRecords(const []), isEmpty);
      expect(decodeRecords(Uint8List(0), intTags: kTrackIntTags), isEmpty);
    });
  });

  group('container', () {
    test('round-trips raw and deflated sections', () {
      final meta = encodeRecords([
        {
          WmpMeta.kind: WmpKind.base,
          WmpMeta.seqFrom: 1000,
          WmpMeta.seqTo: 1999,
          WmpMeta.count: 1000,
          WmpMeta.deviceId: 'd_7ab1',
          WmpMeta.createdAt: '2026-01-01T00:00:00.000Z',
        },
      ]);
      final tracks = encodeRecords([
        {
          WmpTrack.sourceName: '123pan',
          WmpTrack.remotePath: '/a.flac',
          WmpTrack.rev: 5,
        },
      ]);
      final covers = buildCoverSection([
        (bytes: Uint8List.fromList(_pattern(64)), kind: WmpImageKind.webp),
      ]);

      final bytes = WmpContainer.encode(
        {
          WmpSections.meta: meta,
          WmpSections.tracks: tracks,
          WmpSections.covers: covers,
        },
        rawIds: {WmpSections.covers},
      );

      final container = WmpContainer.fromBytes(bytes);
      expect(container.sectionIds, [
        WmpSections.meta,
        WmpSections.tracks,
        WmpSections.covers,
      ]);
      expect(container.info(WmpSections.covers)!.codec, WmpCodec.raw);
      expect(container.info(WmpSections.tracks)!.codec, WmpCodec.deflate);

      expect(container.readSection(WmpSections.meta), meta);
      expect(container.readSection(WmpSections.tracks), tracks);
      expect(container.readSection(WmpSections.covers), covers);
      expect(container.readSection(WmpSections.tombs), isNull);
      expect(container.has(WmpSections.tombs), isFalse);
    });

    test('deflate actually shrinks a repetitive record block', () {
      final tracks = encodeRecords([
        for (var i = 0; i < 200; i++)
          {
            WmpTrack.sourceName: '123pan',
            WmpTrack.remotePath: '/music/album/track$i.flac',
            WmpTrack.album: '同じアルバム名が何度も出てくる',
            WmpTrack.artist: 'Ado',
            WmpTrack.rev: 1750000000000 + i,
          },
      ]);
      final bytes = WmpContainer.encode({WmpSections.tracks: tracks});
      expect(bytes.length, lessThan(tracks.length));
    });

    test('cover table keeps one own copy per track', () {
      final a = Uint8List.fromList(_pattern(40, 1));
      final b = Uint8List.fromList(_pattern(40, 2));
      final section = buildCoverSection([
        (bytes: a, kind: WmpImageKind.jpeg),
        (bytes: b, kind: WmpImageKind.png),
        // Same bytes as `a` on purpose: no dedupe, it is stored again.
        (bytes: a, kind: WmpImageKind.jpeg),
      ]);

      final entries = parseCoverSection(section);
      expect(entries, hasLength(3));
      expect(entries[0].kind, WmpImageKind.jpeg);
      expect(entries[1].kind, WmpImageKind.png);
      expect(entries[0].bytesIn(section), a);
      expect(entries[1].bytesIn(section), b);
      expect(entries[2].bytesIn(section), a);
      // Three copies on disk, not one.
      expect(section.length, 3 * 40 + 3 * 5);
    });

    test('bad magic is rejected', () {
      final bytes = WmpContainer.encode({
        WmpSections.meta: encodeRecords(const []),
      });
      bytes[0] = 0x00;
      expect(
        () => WmpContainer.fromBytes(bytes),
        throwsA(isA<WmpFormatException>()),
      );
    });

    test('a corrupt section payload fails its CRC', () {
      final bytes = WmpContainer.encode({
        WmpSections.tracks: encodeRecords([
          {WmpTrack.sourceName: '123pan', WmpTrack.remotePath: '/a.flac'},
        ]),
      });
      final container = WmpContainer.fromBytes(bytes);
      final offset = container.info(WmpSections.tracks)!.offset;
      bytes[offset] = bytes[offset] ^ 0xFF;
      expect(
        () => WmpContainer.fromBytes(bytes).readSection(WmpSections.tracks),
        throwsA(isA<WmpFormatException>()),
      );
    });

    test('image kind is detected from magic bytes', () {
      expect(
        WmpImageKind.detect(Uint8List.fromList(_pattern(16))),
        WmpImageKind.none,
      );
      expect(
        WmpImageKind.detect(
          Uint8List.fromList([
            0x52,
            0x49,
            0x46,
            0x46,
            0,
            0,
            0,
            0,
            0x57,
            0x45,
            0x42,
            0x50,
          ]),
        ),
        WmpImageKind.webp,
      );
      expect(
        WmpImageKind.detect(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        WmpImageKind.jpeg,
      );
      expect(
        WmpImageKind.detect(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        WmpImageKind.png,
      );
    });
  });
}
