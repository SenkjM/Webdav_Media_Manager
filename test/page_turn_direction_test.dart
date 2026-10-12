// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/page_turn_direction.dart';

void main() {
  group('PageTurnDirection', () {
    test('normalize', () {
      expect(PageTurnDirection.normalize(null), PageTurnDirection.ltr);
      expect(PageTurnDirection.normalize(''), PageTurnDirection.ltr);
      expect(PageTurnDirection.normalize('RTL'), PageTurnDirection.rtl);
      expect(PageTurnDirection.normalize('ltr'), PageTurnDirection.ltr);
      expect(PageTurnDirection.normalize('nope', fallback: PageTurnDirection.rtl),
          PageTurnDirection.rtl);
    });

    test('indexDeltaForEdge LTR', () {
      expect(
        PageTurnDirection.indexDeltaForEdge(1, PageTurnDirection.ltr),
        1,
      );
      expect(
        PageTurnDirection.indexDeltaForEdge(-1, PageTurnDirection.ltr),
        -1,
      );
    });

    test('indexDeltaForEdge RTL mirrors', () {
      expect(
        PageTurnDirection.indexDeltaForEdge(1, PageTurnDirection.rtl),
        -1,
      );
      expect(
        PageTurnDirection.indexDeltaForEdge(-1, PageTurnDirection.rtl),
        1,
      );
    });
  });
}
