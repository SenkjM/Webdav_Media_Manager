import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 「正在销毁」的进度框：一首一首地走，中途可以按「终止」，也可以直接返回。
///
/// 三种取消方式（终止按钮 / 点外部 / 返回键）都只把取消标志置起来，真正的停止
/// 发生在**两首之间**——当前这一首一定会走完，不会留下半首。
class DestroyProgressDialog extends StatelessWidget {
  const DestroyProgressDialog({
    super.key,
    required this.progress,
    required this.total,
    required this.onStop,
  });

  /// 已处理数，逐首刷新。
  final ValueListenable<int> progress;
  final int total;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.elevated,
      title: const Text('正在销毁'),
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (context, processed, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: total == 0 ? 0 : processed / total,
            ),
            const SizedBox(height: 10),
            Text(
              '已处理 $processed / $total 首',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              '「终止」或直接返回都会停在当前这首之后；已经销毁的不会恢复。',
              style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onStop, child: const Text('终止')),
      ],
    );
  }
}

/// 边销毁边显示进度。返回真正销毁的曲目数。
///
/// [run] 拿到的两个回调：`onProgress(processed, total)` 刷新进度条，
/// `isCancelled()` 在两首之间决定要不要停。
Future<int> showDestroyProgress(
  BuildContext context, {
  required int total,
  required Future<int> Function(
    void Function(int processed, int total) onProgress,
    bool Function() isCancelled,
  )
  run,
}) async {
  final progress = ValueNotifier<int>(0);
  var cancelled = false;
  var open = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DestroyProgressDialog(
        progress: progress,
        total: total,
        onStop: () {
          cancelled = true;
          open = false;
          Navigator.of(ctx).pop();
        },
      ),
    ).then((_) {
      // 终止按钮、点外部、返回键都会走到这里。
      cancelled = true;
      open = false;
    }),
  );
  try {
    return await run(
      (processed, _) => progress.value = processed,
      () => cancelled,
    );
  } finally {
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
