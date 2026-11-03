import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/widgets/dlna_subtitle_switch_dialog.dart';

/// 契约 subtitle-lane-and-hwdecode §D：播放中切换字幕要先二次确认，取消时
/// 不发送任何命令。这里只验证弹窗本身：文案、确认 / 取消 / 点外部关闭的返回值。
void main() {
  Future<void> pumpLauncher(
    WidgetTester tester,
    ValueNotifier<bool?> result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  result.value = await DlnaSubtitleSwitchDialog.show(ctx);
                },
                child: const Text('switch'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders copy and returns false on cancel', (tester) async {
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await pumpLauncher(tester, result);

    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();

    expect(find.text('切换字幕'), findsOneWidget);
    expect(find.textContaining('重新加载当前播放'), findsOneWidget);
    expect(find.textContaining('跳回原播放位置'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('继续切换'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result.value, isFalse);
  });

  testWidgets('returns true only when switching is confirmed', (tester) async {
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await pumpLauncher(tester, result);

    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续切换'));
    await tester.pumpAndSettle();

    expect(result.value, isTrue);
  });

  testWidgets('tapping outside the dialog behaves like cancel', (tester) async {
    final result = ValueNotifier<bool?>(null);
    addTearDown(result.dispose);
    await pumpLauncher(tester, result);

    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();
    // 点遮罩（弹窗外的左上角）= 关闭弹窗，调用方因此不发命令。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(result.value, isFalse);
  });
}
