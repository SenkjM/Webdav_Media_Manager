// SPDX-License-Identifier: AGPL-3.0-or-later

/// Page-turn direction for image / manga viewer.
///
/// [ltr]: left edge / swipe-right → previous; right edge / swipe-left → next.
/// [rtl]: left edge → next; right edge → previous (manga-style).
abstract final class PageTurnDirection {
  static const ltr = 'ltr';
  static const rtl = 'rtl';

  static const values = [ltr, rtl];

  static String normalize(String? raw, {String fallback = ltr}) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == rtl) return rtl;
    if (v == ltr) return ltr;
    return fallback;
  }

  /// Map UI edge delta (-1 = left tap / swipe right, +1 = right tap / swipe left)
  /// to album index delta under [direction].
  static int indexDeltaForEdge(int edgeDelta, String direction) {
    final d = edgeDelta == 0 ? 0 : (edgeDelta > 0 ? 1 : -1);
    if (normalize(direction) == rtl) return -d;
    return d;
  }
}
