import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/download_queue_service.dart';
import '../services/platform_export_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
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
      _ensureNomedia();
    });
  }

  /// 开关为开时，仅在下载目录里还没有 `.nomedia` 才补文件。
  /// 关着什么都不删——删除只发生在用户关掉开关、且文件还在时。
  /// 已经一致（外部放好或已经删掉）不算错误，这里也不再提示。
  Future<void> _ensureNomedia() async {
    final settings = context.read<SettingsService>();
    if (!settings.downloadNomediaEnabled) return;
    final result =
        await const PlatformExportService().setDownloadsNomedia(enabled: true);
    if (!mounted || result.error == null) return;
    AppSnack.error(context, result.error!);
  }

  Future<void> _toggleNomedia(bool value) async {
    final settings = context.read<SettingsService>();
    await settings.setDownloadNomediaEnabled(value);
    final result =
        await const PlatformExportService().setDownloadsNomedia(enabled: value);
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(l10n.downloadQueue)),
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
              style: const TextStyle(fontSize: 12, color: Colors.white70),
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
            secondary: const Icon(Icons.stream_outlined),
            title: Text(l10n.dlCryptSequential),
            subtitle: Text(l10n.dlCryptSequentialSub),
            value: settings.cryptSequentialDownloadEnabled,
            onChanged: (value) => context
                .read<SettingsService>()
                .setCryptSequentialDownloadEnabled(value),
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
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: Text(l10n.downloadNotifications),
            subtitle: Text(l10n.downloadNotificationsHint),
            value: settings.downloadNotificationsEnabled,
            onChanged: (v) async {
              await settings.setDownloadNotificationsEnabled(v);
              if (!context.mounted) return;
              await context.read<DownloadQueueService>().setNotifications(v);
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
              await context.read<DownloadQueueService>().setKeepAliveEnabled(v);
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.notifications_active_outlined, size: 20),
            title: Text(l10n.sendTestNotification, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              l10n.sendTestNotificationHint,
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () async {
              final err = await context
                  .read<DownloadQueueService>()
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
              final queue = context.read<DownloadQueueService>();
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
