import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/snack_duration.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/app_snack.dart';

/// The user-facing contract of in-app messages:
/// * every message carries 知道了;
/// * tapping either the text or the button removes it **immediately**;
/// * otherwise it disappears on its own after the duration chosen in
///   设置 → 提示与通知 (this is what "不点就不消失" was about);
/// * a message the user just closed is not resurrected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: AppSnack.hostBuilder,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => AppSnack.show(ctx, '下载成功'),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    AppSnack.resetForTest();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows 知道了 and auto-dismisses after the configured duration', (
    tester,
  ) async {
    final settings = SettingsService();
    AppSnack.attach(settings);

    await pumpHost(tester);
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('下载成功'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);

    // Still there just before the 3s (`normal`) deadline…
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('下载成功'), findsOneWidget);

    // …and gone without any tap afterwards.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('下载成功'), findsNothing);
  });

  testWidgets('the 知道了 button removes it at once', (tester) async {
    AppSnack.attach(SettingsService());

    await pumpHost(tester);
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('下载成功'), findsNothing);
  });

  testWidgets('tapping the message text removes it too', (tester) async {
    AppSnack.attach(SettingsService());

    await pumpHost(tester);
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('下载成功'));
    await tester.pumpAndSettle();
    expect(find.text('下载成功'), findsNothing);
  });

  testWidgets('a message the user closed is not shown again unchanged', (
    tester,
  ) async {
    AppSnack.attach(SettingsService());

    await pumpHost(tester);
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    // Re-trigger the *same* text without anything else in between.
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('下载成功'), findsNothing);
  });

  testWidgets('「关闭」stops messages entirely', (tester) async {
    final settings = SettingsService();
    AppSnack.attach(settings);
    await settings.setSnackMode(SnackDuration.off);

    await pumpHost(tester);
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('下载成功'), findsNothing);
  });

  testWidgets('「点击才消失」stays until tapped', (tester) async {
    final settings = SettingsService();
    AppSnack.attach(settings);
    await settings.setSnackMode(SnackDuration.untilDismissed);

    await pumpHost(tester);
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('下载成功'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('下载成功'), findsNothing);
  });
}
