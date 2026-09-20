import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/cache_policy.dart';

void main() {
  group('CacheExpiryPolicy', () {
    final now = DateTime(2026, 9, 20, 12);

    test('oneDay deletes files older than 1 day', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.oneDay);
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 1, minutes: 1)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isTrue,
      );
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(hours: 23)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isFalse,
      );
    });

    test('oneWeek deletes files older than 7 days', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.oneWeek);
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 7, seconds: 1)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isTrue,
      );
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 6, hours: 23)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isFalse,
      );
    });

    test('never deletes currently playing file even if expired', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.oneDay);
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 30)),
          now: now,
          isCurrentlyPlaying: true,
          isDownloading: false,
        ),
        isFalse,
      );
    });

    test('never deletes mid-download file even if expired', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.oneWeek);
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 30)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: true,
        ),
        isFalse,
      );
    });

    test('boundary: exactly retention duration is deletable', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.oneDay);
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 1)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isTrue,
      );
    });
  });
}
