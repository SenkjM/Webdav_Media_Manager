import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_database_recovery_service.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.error, this.beforeClear});
  final String error;
  final Future<void> Function()? beforeClear;
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final recovery = const LocalDatabaseRecoveryService();
  bool busy = false;
  String? message;
  Future<void> export() async {
    setState(() => busy = true);
    try {
      final files = await recovery.exportAll();
      final ok = files.where((r) => r.ok).length;
      setState(
        () => message = files.isEmpty
            ? '未找到可导出的本地数据库'
            : '已导出 $ok/${files.length} 个数据库文件到下载目录',
      );
    } catch (e) {
      setState(() => message = '导出失败：$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> clearAndExit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本地数据库？'),
        content: const Text('建议先导出数据库。清除后请重新打开应用，网盘账号和本地索引需要重新配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除并退出'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    await widget.beforeClear?.call();
    final count = await recovery.clearAll();
    if (!mounted) return;
    setState(() {
      busy = false;
      message = '已清除 $count 个数据库文件，请重新打开应用';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('需要恢复本地数据')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '数据库初始化失败',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(widget.error),
              const SizedBox(height: 16),
              const Text('请先导出全部本地数据库，再清除并重新进入应用。'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : export,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('导出全部本地数据库'),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : clearAndExit,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('清除数据并重新进入'),
                  ),
                ],
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
