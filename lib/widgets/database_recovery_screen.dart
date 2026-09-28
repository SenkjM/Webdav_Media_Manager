import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    setState(() => busy = true);
    try {
      final files = await recovery.exportAll();
      final ok = files.where((r) => r.ok).length;
      setState(
        () => message = files.isEmpty
            ? l10n.recoveryNothingToExport
            : l10n.recoveryExportedCount(ok, files.length),
      );
    } catch (e) {
      setState(() => message = l10n.recoveryExportFailed('$e'));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> clearAndExit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(AppLocalizations.of(dialogCtx)!.recoveryClearTitle),
        content: Text(AppLocalizations.of(dialogCtx)!.recoveryClearContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(AppLocalizations.of(dialogCtx)!.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(AppLocalizations.of(dialogCtx)!.recoveryClearAndExit),
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
      message = AppLocalizations.of(context)!.recoveryClearedCount(count);
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context)!.recoveryTitle)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.recoveryHeading,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(widget.error),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(context)!.recoveryBody),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : export,
                    icon: const Icon(Icons.save_alt),
                    label: Text(
                      AppLocalizations.of(context)!.recoveryExportAll,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : clearAndExit,
                    icon: const Icon(Icons.delete_forever),
                    label: Text(
                      AppLocalizations.of(context)!.recoveryClearAndReenter,
                    ),
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
