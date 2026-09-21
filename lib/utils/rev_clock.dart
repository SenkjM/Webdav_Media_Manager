import 'package:flutter/foundation.dart';

/// Monotonic version clock for library rows and tombstones.
///
/// Every row carries one `rev` — the single field sync compares (it replaces
/// `lastTagReadAt` as the merge version, because wall-clock comparison breaks on
/// clock skew and on two edits inside the same millisecond).
///
/// Rules:
/// * `rev = max(nowMs, last + 1)` — the value is **strictly increasing** and
///   still roughly time-ordered;
/// * a clock that jumps backwards (timezone/NTP/manual change) cannot produce a
///   duplicate or a smaller value;
/// * a burst of edits inside one millisecond gets distinct, increasing values.
///
/// The clock is **not** shared across devices: two devices pick numbers from the
/// same wall-clock scale, so values stay comparable, and an exact tie is broken
/// by comparing the device id (see [compareRev]).
class RevClock {
  RevClock({required int Function() nowMs, int initial = 0, this.onAdvance})
    : _nowMs = nowMs,
      _last = initial;

  /// Wall clock in milliseconds (injectable for tests).
  final int Function() _nowMs;

  /// Called with the new high-water mark so the caller can persist it.
  final Future<void> Function(int value)? onAdvance;

  int _last;

  /// Highest value handed out so far.
  int get last => _last;

  /// Next strictly-increasing value.
  int next() {
    final now = _nowMs();
    _last = now > _last ? now : _last + 1;
    final persist = onAdvance;
    if (persist != null) {
      // Persisting is fire-and-forget: a lost write only costs us a repeat of a
      // value we would have handed out again anyway after a restart.
      persist(_last).catchError((Object e) {
        debugPrint('RevClock: persist failed: $e');
      });
    }
    return _last;
  }

  /// Adopt an externally observed value (a pulled row with a newer `rev`) so the
  /// next local write cannot go backwards relative to the cloud.
  void observe(int value) {
    if (value <= _last) return;
    _last = value;
    final persist = onAdvance;
    if (persist != null) {
      persist(_last).catchError((Object e) {
        debugPrint('RevClock: persist failed: $e');
      });
    }
  }
}

/// Total order over `(rev, deviceId)` pairs.
///
/// Returns a negative number when [aRev] wins (is newer), positive when [bRev]
/// wins, 0 when both rows are the same version.
int compareRev(int aRev, String aDevice, int bRev, String bDevice) {
  if (aRev != bRev) return aRev > bRev ? -1 : 1;
  return aDevice.compareTo(bDevice);
}
