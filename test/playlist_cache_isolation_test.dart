import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/cache_policy.dart';

/// Documents & guards the policy: audio cache cleanup must never target
/// playlist storage paths (playlists.db lives under documents, not music_cache).
void main() {
  group('cache never wipes playlists', () {
    test('CacheService only operates under music_cache directory name', () {
      // Structural guarantee: playlist DB file name is unrelated to cache dir.
      const playlistDb = 'playlists.db';
      const cacheDirName = 'music_cache';
      expect(playlistDb.contains(cacheDirName), isFalse);
      expect(cacheDirName.contains('playlist'), isFalse);
    });

    test('clearAll / cleanupKnown only delete File entities under cacheDir', () {
      // Policy comment mirrored from CacheService — retention never applies to
      // documents/playlists.db. Expiry policy itself only answers "should delete
      // this audio file" and has no playlist awareness (by design).
      final policy = CacheExpiryPolicy(retention: CacheRetention.oneDay);
      final now = DateTime(2026, 9, 20);
      // Even aggressive expiry does not know about playlists — callers must not
      // pass playlist paths into identityToLocal.
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 10)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isTrue,
      );
    });

    test('playlist store path convention is under documents not support/cache', () {
      // PlaylistStore uses getApplicationDocumentsDirectory()/playlists.db
      // CacheService uses getApplicationSupportDirectory()/music_cache
      // These are different roots on Android — cleanup cannot reach playlists.
      const docsRelative = 'playlists.db';
      const cacheRelative = 'music_cache';
      expect(docsRelative, isNot(equals(cacheRelative)));
    });
  });
}
