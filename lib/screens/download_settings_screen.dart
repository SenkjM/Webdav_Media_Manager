import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/download_queue_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';

/// 设置 → 下载队列。
///
/// 断点续传靠保留半截文件（`.part`，见 services/resumable_download.dart），
/// 但失败任务堆着不放会吃满磁盘，所以保留时长与总体积上限在这里可配；
/// 「立即清理」按当前设置跑一次（启动时也会顺手跑一次同样的清理）。
class DownloadSettingsScreen extends StatelessWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('下载队列')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '断点续传的临时文件',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '网络中断重试时会从半截文件接着下。文件留着才续得上，所以这里配的是上限：'
              '超过上限的部分会被自动清掉（没有对应下载任务的孤儿文件也会清）。',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          _NumberField(
            key: const ValueKey('part-max-age'),
            title: '保留时长',
            unit: '小时',
            value: settings.downloadPartMaxAgeHours,
            min: 1,
            max: 720,
            onCommit: (v) => context
                .read<SettingsService>()
                .setDownloadPartMaxAgeHours(v),
          ),
          _NumberField(
            key: const ValueKey('part-max-size'),
            title: '总体积上限',
            unit: 'MB',
            value: settings.downloadPartMaxMb,
            min: 64,
            max: 65536,
            onCommit: (v) =>
                context.read<SettingsService>().setDownloadPartMaxMb(v),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('立即清理'),
            subtitle: const Text('按上面的上限删掉过期的半截文件'),
            onTap: () async {
              final queue = context.read<DownloadQueueService>();
              final removed = await queue.cleanupStaleParts();
              if (!context.mounted) return;
              AppSnack.show(
                context,
                removed == 0 ? '没有需要清理的半截文件' : '已清理 $removed 个半截文件',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 手输数字 + 上下限：超出范围按边界保存，非数字退回原值。
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.title,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
  });

  final String title;
  final String unit;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onCommit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final field = widget.title;
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      AppSnack.show(context, '$field请填数字', error: true);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    if (clamped != parsed) {
      AppSnack.show(
        context,
        '$field只能在 ${widget.min}~${widget.max}${widget.unit} 之间，已按 $clamped 保存',
      );
    }
    _controller.text = '$clamped';
    if (clamped != widget.value) widget.onCommit(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(
          labelText: widget.title,
          suffixText: widget.unit,
          helperText:
              '范围 ${widget.min} ~ ${widget.max} ${widget.unit}，超范围按边界保存',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          _commit();
        },
      ),
    );
  }
}
