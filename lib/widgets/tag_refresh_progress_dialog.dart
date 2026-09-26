import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TagRefreshProgressDialog extends StatelessWidget {
  const TagRefreshProgressDialog({
    super.key,
    required this.progress,
    required this.total,
    required this.currentName,
    required this.onStop,
  });

  final ValueListenable<int> progress;
  final int total;
  final ValueListenable<String> currentName;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.elevated,
    title: const Text('正在更新标签'),
    content: ValueListenableBuilder<int>(
      valueListenable: progress,
      builder: (context, processed, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: total == 0 ? 0 : processed / total),
          const SizedBox(height: 10),
          Text('已处理 $processed / $total 首'),
          const SizedBox(height: 6),
          ValueListenableBuilder<String>(
            valueListenable: currentName,
            builder: (context, name, _) => Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '只读取本地缓存；终止后保留已更新的曲目。',
            style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
          ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: onStop, child: const Text('终止'))],
  );
}

Future<({int updated, int skipped, int failed, bool cancelled})>
showTagRefreshProgress(
  BuildContext context, {
  required List<String> names,
  required Future<({int updated, int skipped, int failed})> Function(
    void Function(int processed, String currentName) onProgress,
    bool Function() isCancelled,
  )
  run,
}) async {
  final progress = ValueNotifier<int>(0);
  final currentName = ValueNotifier<String>('准备中');
  var cancelled = false;
  var open = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TagRefreshProgressDialog(
        progress: progress,
        total: names.length,
        currentName: currentName,
        onStop: () {
          cancelled = true;
          open = false;
          Navigator.of(ctx).pop();
        },
      ),
    ).then((_) {
      cancelled = true;
      open = false;
    }),
  );
  try {
    final result = await run((n, name) {
      progress.value = n;
      currentName.value = name;
    }, () => cancelled);
    return (
      updated: result.updated,
      skipped: result.skipped,
      failed: result.failed,
      cancelled: cancelled,
    );
  } finally {
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    currentName.dispose();
  }
}
