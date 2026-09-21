import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/rev_clock.dart';

void main() {
  group('RevClock', () {
    test('follows the wall clock when it moves forward', () {
      var now = 1000;
      final clock = RevClock(nowMs: () => now);
      expect(clock.next(), 1000);
      now = 5000;
      expect(clock.next(), 5000);
      expect(clock.last, 5000);
    });

    test('is strictly increasing inside one millisecond', () {
      final clock = RevClock(nowMs: () => 7777);
      final values = [for (var i = 0; i < 5; i++) clock.next()];
      expect(values, [7777, 7778, 7779, 7780, 7781]);
    });

    test('never goes backwards when the clock jumps back', () {
      var now = 100000;
      final clock = RevClock(nowMs: () => now);
      expect(clock.next(), 100000);
      now = 5; // NTP correction / manual clock change
      expect(clock.next(), 100001);
      expect(clock.last, 100001);
    });

    test('starts from an initial high-water mark', () {
      final clock = RevClock(nowMs: () => 10, initial: 900);
      expect(clock.next(), 901);
    });

    test('reports every advance so it can be persisted', () async {
      final seen = <int>[];
      var now = 100;
      final clock = RevClock(
        nowMs: () => now,
        onAdvance: (value) async => seen.add(value),
      );
      clock.next();
      now = 200;
      clock.next();
      await Future<void>.delayed(Duration.zero);
      expect(seen, [100, 200]);
      expect(clock.last, 200);
    });

    test('observe() adopts a newer remote value but never regresses', () {
      var now = 100;
      final clock = RevClock(nowMs: () => now);
      clock.next();
      clock.observe(50);
      expect(clock.last, 100);
      clock.observe(500);
      expect(clock.last, 500);
      expect(clock.next(), 501);
    });
  });

  group('compareRev', () {
    test('higher rev wins', () {
      expect(compareRev(10, 'a', 9, 'z'), lessThan(0));
      expect(compareRev(9, 'z', 10, 'a'), greaterThan(0));
    });

    test('ties break on device id, deterministically', () {
      expect(compareRev(10, 'd_1', 10, 'd_2'), lessThan(0));
      expect(compareRev(10, 'd_2', 10, 'd_1'), greaterThan(0));
      expect(compareRev(10, 'd_1', 10, 'd_1'), 0);
    });
  });
}
