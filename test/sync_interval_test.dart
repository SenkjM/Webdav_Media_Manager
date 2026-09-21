import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/sync_interval.dart';

void main() {
  group('SyncInterval', () {
    test('off means no timer at all', () {
      expect(SyncInterval.off.duration, isNull);
      expect(SyncInterval.off.labelZh, contains('关闭'));
    });

    test('every option that runs has a positive period', () {
      for (final v in SyncInterval.values) {
        if (v == SyncInterval.off) continue;
        expect(v.duration, isNotNull, reason: v.labelZh);
        expect(v.duration!.inMinutes, greaterThan(0));
      }
    });

    test('storage keys round-trip, unknown falls back to 30 minutes', () {
      for (final v in SyncInterval.values) {
        expect(SyncIntervalX.fromStorageKey(v.storageKey), v);
      }
      expect(SyncIntervalX.fromStorageKey('nonsense'), SyncInterval.every30m);
      expect(SyncIntervalX.fromStorageKey(null), SyncInterval.every30m);
    });

    test('periods are ordered shortest to longest', () {
      final minutes = [
        for (final v in SyncInterval.values)
          if (v.duration != null) v.duration!.inMinutes,
      ];
      for (var i = 1; i < minutes.length; i++) {
        expect(minutes[i], greaterThan(minutes[i - 1]));
      }
    });
  });
}
