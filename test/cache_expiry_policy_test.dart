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

    test('never retention never auto-deletes even if very old', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.never);
      expect(policy.effectiveDuration, isNull);
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 3650)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isFalse,
      );
    });

    test('custom retention uses provided duration', () {
      final policy = CacheExpiryPolicy(
        retention: CacheRetention.custom,
        customDuration: const Duration(days: 3),
      );
      expect(policy.effectiveDuration, const Duration(days: 3));
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 3, minutes: 1)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isTrue,
      );
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 2, hours: 23)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isFalse,
      );
    });

    test('custom retention supports hours-only window', () {
      final policy = CacheExpiryPolicy(
        retention: CacheRetention.custom,
        customDuration: const Duration(hours: 12),
      );
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(hours: 12)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isTrue,
      );
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(hours: 11)),
          now: now,
          isCurrentlyPlaying: false,
          isDownloading: false,
        ),
        isFalse,
      );
    });

    test('custom without duration falls back to 7 days', () {
      final policy = CacheExpiryPolicy(retention: CacheRetention.custom);
      expect(policy.effectiveDuration, const Duration(days: 7));
    });

    test('protects currently playing file even if expired', () {
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

    test('protects mid-download file even if expired', () {
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

    test('custom still protects playing and downloading files', () {
      final policy = CacheExpiryPolicy(
        retention: CacheRetention.custom,
        customDuration: const Duration(hours: 1),
      );
      expect(
        policy.shouldDelete(
          lastAccessed: now.subtract(const Duration(days: 30)),
          now: now,
          isCurrentlyPlaying: true,
          isDownloading: false,
        ),
        isFalse,
      );
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

    test('storage keys round-trip for never and custom', () {
      expect(
        CacheRetentionX.fromStorageKey(CacheRetention.never.storageKey),
        CacheRetention.never,
      );
      expect(
        CacheRetentionX.fromStorageKey(CacheRetention.custom.storageKey),
        CacheRetention.custom,
      );
      expect(
        CacheRetentionX.fromStorageKey(null),
        CacheRetention.oneWeek,
      );
    });
  });
}
