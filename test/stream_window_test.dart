import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/stream_cover_reader.dart';
import 'package:webdav_media_manager/services/stream_window.dart';

void main() {
  group('sniffEmbeddedAudio', () {
    Uint8List bytes(List<int> data) => Uint8List.fromList(data);

    test('magic, not the file suffix', () {
      expect(
        sniffEmbeddedAudio(
          bytes([0x49, 0x44, 0x33, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        EmbeddedAudio.mp3,
      );
      expect(
        sniffEmbeddedAudio(
          bytes([0xff, 0xfb, 0x90, 0x00, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        EmbeddedAudio.mp3,
      );
      expect(
        sniffEmbeddedAudio(bytes('fLaC........'.codeUnits)),
        EmbeddedAudio.flac,
      );
      final ftyp = bytes(List<int>.filled(12, 0));
      ftyp.setRange(4, 8, 'ftyp'.codeUnits);
      expect(sniffEmbeddedAudio(ftyp), EmbeddedAudio.mp4);
      expect(
        sniffEmbeddedAudio(bytes('OggS........'.codeUnits)),
        EmbeddedAudio.ogg,
      );
      final wav = bytes(List<int>.filled(12, 0));
      wav.setRange(0, 4, 'RIFF'.codeUnits);
      wav.setRange(8, 12, 'WAVE'.codeUnits);
      expect(sniffEmbeddedAudio(wav), EmbeddedAudio.wav);
      expect(
        sniffEmbeddedAudio(bytes('AAC!........'.codeUnits)),
        EmbeddedAudio.none,
      );
      expect(sniffEmbeddedAudio(bytes([1, 2, 3])), EmbeddedAudio.none);
    });
  });

  group('matchSidecarCover', () {
    const names = [
      'cover.png',
      'cover.jpg',
      'cover.gif',
      'notes.txt',
      'Folder.JPEG',
      'song.webp',
      'poster.png',
    ];

    test('default names, jpg over other extensions, ignore the rest', () {
      expect(
        matchSidecarCover(names, 'other.flac', 'cover, folder, front, album'),
        'cover.jpg',
      );
    });

    test('edited list still always tries the audio stem', () {
      expect(matchSidecarCover(names, 'Song.mp3', 'poster'), 'poster.png');
      expect(matchSidecarCover(names, 'Song.mp3', ''), 'song.webp');
    });

    test('user order wins, and slashes cannot select a subdirectory', () {
      expect(
        matchSidecarCover(names, 'track.ogg', 'folder, cover'),
        'Folder.JPEG',
      );
      expect(
        matchSidecarCover(['sub/cover.jpg', 'cover.jpg'], 'a.mp3', 'sub/cover'),
        isNull,
      );
    });
  });

  group('nextPrefetchIndex', () {
    test('backward first, then forward, no wrap, zero disables a side', () {
      expect(
        nextPrefetchIndex(
          current: 2,
          length: 6,
          backward: 2,
          forward: 2,
          skip: (_) => false,
        ),
        1,
      );
      expect(
        nextPrefetchIndex(
          current: 2,
          length: 6,
          backward: 2,
          forward: 2,
          skip: (i) => i == 1 || i == 0,
        ),
        3,
      );
      expect(
        nextPrefetchIndex(
          current: 0,
          length: 4,
          backward: 2,
          forward: 1,
          skip: (_) => false,
        ),
        1,
      );
      expect(
        nextPrefetchIndex(
          current: 3,
          length: 4,
          backward: 0,
          forward: 2,
          skip: (_) => false,
        ),
        isNull,
      );
      expect(
        nextPrefetchIndex(
          current: 1,
          length: 4,
          backward: 0,
          forward: 1,
          skip: (i) => i == 2,
        ),
        isNull,
      );
    });
  });

  group('cover prefetch plan', () {
    test('neighbors stay in backward-then-forward order, ends do not wrap', () {
      expect(
        prefetchNeighborIndexes(current: 2, length: 6, backward: 2, forward: 2),
        [1, 0, 3, 4],
      );
      expect(
        prefetchNeighborIndexes(current: 0, length: 4, backward: 2, forward: 0),
        isEmpty,
      );
      expect(
        prefetchNeighborIndexes(current: 1, length: 4, backward: 0, forward: 2),
        [2, 3],
      );
      expect(
        prefetchNeighborIndexes(
          current: -1,
          length: 4,
          backward: 1,
          forward: 1,
        ),
        isEmpty,
      );
    });

    test('window covers precede audio, including cached audio', () {
      final neighbors = prefetchNeighborIndexes(
        current: 2,
        length: 5,
        backward: 1,
        forward: 2,
      );
      // Index 1 is already cached or in the player. Its cover is still due.
      final plan = prefetchPlan(
        neighbors: neighbors,
        coverDone: (i) => i == 3,
        audioSkip: (i) => i == 1,
      );
      expect(
        plan.map((step) => '${step.cover ? 'cover' : 'audio'}:${step.index}'),
        ['cover:1', 'cover:4', 'audio:3', 'audio:4'],
      );
    });
  });

  test('playlistInsertAt keeps queue order', () {
    expect(
      playlistInsertAt(
        order: ['a', 'c'],
        queue: ['a', 'b', 'c', 'd'],
        path: 'b',
      ),
      1,
    );
    expect(
      playlistInsertAt(
        order: ['a', 'c'],
        queue: ['a', 'b', 'c', 'd'],
        path: 'd',
      ),
      2,
    );
  });

  test('picture blocks and covr boxes', () {
    final image = [0xff, 0xd8, 0xff, 0xd9];
    final block = BytesBuilder();
    void put(BytesBuilder target, int value) {
      target.add([
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ]);
    }

    put(block, 3);
    put(block, 10);
    block.add('image/jpeg'.codeUnits);
    put(block, 0);
    block.add(List<int>.filled(16, 0));
    put(block, image.length);
    block.add(image);
    expect(decodePictureBlock(block.toBytes()), image);

    final covr = BytesBuilder();
    final dataSize = 16 + image.length;
    put(covr, 8 + dataSize);
    covr.add('covr'.codeUnits);
    put(covr, dataSize);
    covr.add('data'.codeUnits);
    covr.add(List<int>.filled(8, 0));
    covr.add(image);
    expect(imageFromCovrBox(covr.toBytes()), image);
  });
}
