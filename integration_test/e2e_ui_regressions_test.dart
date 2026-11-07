import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/screens/settings_screen.dart';
import 'package:webdav_media_manager/screens/transcode_presets_screen.dart';

import 'e2e_support.dart';

/// UI regression module: two red screens the user hit on the device.
///
///  * the preset editor wrapped an enabled rate chip in a `Tooltip` whose
///    `message` was null (Flutter asserts in `tooltip.dart:139`);
///  * the cache-budget dialog disposed its controller as soon as `showDialog`
///    returned, while the route was still animating out (`framework.dart:6280`).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ui: preset editor and cache budget dialog stay red-screen free',
      (tester) async {
    await bootApp(tester);
    await pumpFrames(tester, frames: 8);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    final reports = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      reports.add('${details.exceptionAsString()}\n'
          '${details.context?.toString() ?? ''}');
      debugPrint('[E2E] ui report: ${details.exceptionAsString()}');
    };

    try {
      // A) Preset editor: open a preset and toggle every rate-control chip.
      unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const TranscodePresetsScreen(),
      )));
      await pumpFrames(tester, frames: 16, label: 'presets list');
      await pumpUntil(
        tester,
        'presets list loaded',
        () => find.byType(ListTile).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      await tester.tap(find.byType(ListTile).first);
      await pumpFrames(tester, frames: 20, label: 'preset editor');
      expect(reports, isEmpty,
          reason: 'opening the preset editor threw: $reports');

      final chips = find.byType(ChoiceChip);
      final chipCount = chips.evaluate().length;
      expect(chipCount, greaterThan(0),
          reason: 'the editor should show its rate-control chips');
      for (var i = 0; i < chipCount; i++) {
        final chip = chips.at(i);
        await tester.ensureVisible(chip);
        await tester.tap(chip, warnIfMissed: false);
        await pumpFrames(tester, frames: 4);
      }
      expect(reports, isEmpty,
          reason: 'toggling rate-control chips threw: $reports');

      navigator.pop();
      await pumpFrames(tester, frames: 12);
      navigator.pop();
      await pumpFrames(tester, frames: 12);

      // B) Cache budget dialog: open it, then cancel.
      unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
      )));
      await pumpFrames(tester, frames: 16, label: 'settings screen');
      // The settings list is lazy: the tile is below the fold, so scroll the
      // primary list until it is actually built before asserting on it.
      final budget = find.byKey(const ValueKey('settings.cacheBudget'));
      for (var i = 0; i < 12 && budget.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await pumpFrames(tester, frames: 4);
      }
      expect(budget, findsOneWidget,
          reason: 'the cache budget tile is missing');
      await tester.ensureVisible(budget);
      await pumpFrames(tester, frames: 8);
      await tester.tap(budget);
      await pumpFrames(tester, frames: 16, label: 'budget dialog');
      expect(find.text('取消'), findsOneWidget,
          reason: 'the cache budget dialog did not open');
      await tester.tap(find.text('取消'));
      await pumpFrames(tester, frames: 24, label: 'budget cancel');
      expect(reports, isEmpty,
          reason: 'cancelling the cache budget dialog threw: $reports');

      debugPrint('[E2E] ui ok: preset chips=$chipCount, '
          'budget dialog cancelled cleanly');
    } finally {
      FlutterError.onError = previous;
      for (var i = 0; i < 5 && navigator.mounted && navigator.canPop(); i++) {
        navigator.pop();
        await pumpFrames(tester, frames: 4);
      }
    }
  });
}
