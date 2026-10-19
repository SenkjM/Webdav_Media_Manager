import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/download_destination_service.dart';
import '../services/task_queue_service.dart';
import '../services/settings_service.dart';
import '../utils/app_snack.dart';
import '../l10n/generated/app_localizations.dart';

/// 设置 → 网络库 → 下载。
///
/// 断点续传靠保留半截文件（`.part`，见 services/resumable_download.dart），
/// 但失败任务堆着不放会吃满磁盘，所以保留时长与总体积上限在这里可配；
/// 「立即清理」按当前设置跑一次（启动时也会顺手跑一次同样的清理）。
class DownloadSettingsScreen extends StatefulWidget {
  const DownloadSettingsScreen({super.key});

  @override
  State<DownloadSettingsScreen> createState() => _DownloadSettingsScreenState();
}

class _DownloadSettingsScreenState extends State<DownloadSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyAndAlignNomedia();
    });
  }

  /// 设置页打开时：校验自定义目录可用性 + 双向对齐 .nomedia。
  Future<void> _verifyAndAlignNomedia() async {
    final destination = context.read<DownloadDestinationService>();
    await destination.verifyOnOpen();
    await destination.alignNomedia(reportAlready: true);
  }

  Future<void> _toggleNomedia(bool value) async {
    final settings = context.read<SettingsService>();
    final destination = context.read<DownloadDestinationService>();
    await settings.setDownloadNomediaEnabled(value);
    final result = await destination.alignNomedia(reportAlready: true);
    if (!mounted) return;
    if (result.error != null) {
      await settings.setDownloadNomediaEnabled(!value);
      if (!mounted) return;
      AppSnack.error(context, result.error!);
      return;
    }
    if (!result.alreadyMatched) return;
    final l10n = AppLocalizations.of(context)!;
    AppSnack.show(
      context,
      value
          ? l10n.downloadNomediaAlreadyPresent
          : l10n.downloadNomediaAlreadyAbsent,
    );
  }

  Future<void> _toggleCustomDownloadDir(bool value) async {
    final destination = context.read<DownloadDestinationService>();
    if (value) {
      // 开启：选择目录
      final result = await destination.pickCustomDir();
      if (!mounted) return;
      if (result.cancelled == true) {
        // 取消：保持关闭状态
        AppSnack.show(context, AppLocalizations.of(context)!.customDownloadDirPickCancelled);
      } else if (result.error != null) {
        // 失败：提示错误
        AppSnack.error(context, result.error!);
      }
      // 成功时 pickCustomDir 已经更新了设置，不需要额外操作
    } else {
      // 关闭：禁用自定义目录
      await destination.disableCustomDir();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l10n.taskQueue)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.dlPartFilesTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              l10n.dlPartFilesIntro,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _NumberField(
            key: const ValueKey('part-max-age'),
            title: l10n.dlRetainDuration,
            unit: l10n.unitHours,
            value: settings.downloadPartMaxAgeHours,
            min: 1,
            max: 720,
            onCommit: (v) =>
                context.read<SettingsService>().setDownloadPartMaxAgeHours(v),
          ),
          _NumberField(
            key: const ValueKey('part-max-size'),
            title: l10n.dlTotalSizeLimit,
            unit: 'MB',
            value: settings.downloadPartMaxMb,
            min: 64,
            max: 65536,
            onCommit: (v) =>
                context.read<SettingsService>().setDownloadPartMaxMb(v),
          ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Icon(Icons.hide_image_outlined),
            title: Text(l10n.downloadNomedia),
            subtitle: Text(l10n.downloadNomediaSubtitle),
            value: settings.downloadNomediaEnabled,
            onChanged: (value) => _toggleNomedia(value),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.customDownloadDir,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.folder_outlined),
            title: Text(l10n.customDownloadDir),
            subtitle: Text(l10n.customDownloadDirSubtitle),
            value: settings.useCustomDownloadDir,
            onChanged: (value) => _toggleCustomDownloadDir(value),
          ),
          if (settings.customDownloadDirActive)
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(l10n.customDownloadDirCurrent(
                settings.customDownloadDisplayName ?? l10n.customDownloadDirDefault,
              )),
              dense: true,
            ),
          if (settings.customDownloadDirActive)
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(l10n.customDownloadDirRepick),
              trailing: const Icon(Icons.folder_open_outlined),
              onTap: () async {
                final destination = context.read<DownloadDestinationService>();
                final result = await destination.pickCustomDir();
                if (!mounted) return;
                if (result.error != null) {
                  AppSnack.error(context, result.error!);
                }
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.customDownloadDirAndroid11Note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.customDownloadDirSafNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: Text(l10n.downloadNotifications),
            subtitle: Text(l10n.downloadNotificationsHint),
            value: settings.downloadNotificationsEnabled,
            onChanged: (v) async {
              await settings.setDownloadNotificationsEnabled(v);
              if (!context.mounted) return;
              await context.read<TaskQueueService>().setNotifications(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.downloading_outlined),
            title: Text(l10n.downloadKeepAlive),
            subtitle: Text(l10n.downloadKeepAliveHint),
            value: settings.downloadKeepAliveEnabled,
            onChanged: (v) async {
              await settings.setDownloadKeepAliveEnabled(v);
              if (!context.mounted) return;
              await context.read<TaskQueueService>().setKeepAliveEnabled(v);
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.notifications_active_outlined, size: 20),
            title: Text(
              l10n.sendTestNotification,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              l10n.sendTestNotificationHint,
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () async {
              final err = await context
                  .read<TaskQueueService>()
                  .notificationService
                  .selfTest();
              if (!context.mounted) return;
              if (err == null) {
                AppSnack.show(context, l10n.testNotificationSent);
              } else {
                AppSnack.error(context, l10n.testNotificationFailed(err));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(l10n.dlCleanNow),
            subtitle: Text(l10n.dlCleanNowSub),
            onTap: () async {
              final queue = context.read<TaskQueueService>();
              final removed = await queue.cleanupStaleParts();
              if (!context.mounted) return;
              AppSnack.show(
                context,
                removed == 0
                    ? l10n.dlNothingToClean
                    : l10n.dlCleanedCount(removed),
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
    final l10n = AppLocalizations.of(context)!;
    final field = widget.title;
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      AppSnack.show(context, l10n.dlFieldNotNumber(field), error: true);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    if (clamped != parsed) {
      AppSnack.show(
        context,
        l10n.dlFieldClamped(
          field,
          widget.min,
          widget.max,
          widget.unit,
          clamped,
        ),
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
          helperText: AppLocalizations.of(context)!
              .dlRangeHint(widget.min, widget.max, widget.unit),
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
