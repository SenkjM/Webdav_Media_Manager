import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/play_open_mode.dart';
import 'package:webdav_media_manager/models/playback_queue_source.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/playback_queue_store.dart';

void main() {
  test('queue snapshot round-trips identities, cursor, mode and source', () async {
    final dir = await Directory.systemTemp.createTemp('wdmm_queue_store_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = PlaybackQueueStore(directoryProvider: () async => dir);

    final entries = [
      TrackInfo(
        sourceName: 'webdav-A',
        remotePath: '/Music/a.mp3',
        fileName: 'a.mp3',
      ),
      TrackInfo(
        sourceName: 'webdav-A',
        remotePath: '/Music/album/track02.flac',
        fileName: 'track02.flac',
        cueRemotePath: '/Music/album/disc.cue',
        cueTrackIndex: 2,
        audioRemotePath: '/Music/album/whole.flac',
        clipStart: const Duration(seconds: 65),
        clipEnd: const Duration(seconds: 130),
        cacheGroupId: 'g1',
      ),
    ];
    await store.save(
      PlaybackQueueSnapshot(
        entries: entries,
        index: 1,
        mode: PlayOpenMode.stream,
        source: PlaybackQueueSource.networkFolder(
          accountId: 'acc-1',
          folderPath: '/Music',
          includeSubdirs: true,
          maxDepth: 2,
        ),
      ),
    );

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.index, 1);
    expect(loaded.mode, PlayOpenMode.stream);
    expect(loaded.source?.kind, PlaybackQueueSourceKind.networkFolder);
    expect(loaded.source?.folderPath, '/Music');
    expect(loaded.source?.includeSubdirs, isTrue);
    expect(loaded.source?.maxDepth, 2);
    expect(loaded.entries, hasLength(2));
    expect(loaded.entries[0].remotePath, '/Music/a.mp3');
    // Metadata is intentionally not persisted: library resolves it on restore.
    expect(loaded.entries[0].title, isNull);
    expect(loaded.entries[1].isCueVirtual, isTrue);
    expect(loaded.entries[1].cueTrackIndex, 2);
    expect(loaded.entries[1].clipStart, const Duration(seconds: 65));
    expect(loaded.entries[1].clipEnd, const Duration(seconds: 130));

    await store.clear();
    expect(await store.load(), isNull);
  });
}
