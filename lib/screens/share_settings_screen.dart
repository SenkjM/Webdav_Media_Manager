import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';

/// 分享重命名：开关 + 模板。要填模板，所以从设置主页收进二级页。
class ShareSettingsScreen extends StatelessWidget {
  const ShareSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l10n.shareAction)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.shareRenameHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.drive_file_rename_outline),
            title: Text(l10n.shareRenameTitle),
            subtitle: Text(l10n.shareRenameSubtitle),
            value: settings.shareTagRenameEnabled,
            onChanged: (v) => settings.setShareTagRenameEnabled(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: Text(l10n.renameTemplate),
            subtitle: Text(
              '${settings.shareTagRenamePattern}\n'
              '占位符：{artist} {title} {album} {albumArtist} '
              '{track} {year} {genre} {fileName}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editPattern(context, settings),
          ),
        ],
      ),
    );
  }

  Future<void> _editPattern(
    BuildContext context,
    SettingsService settings,
  ) async {
    final controller = TextEditingController(
      text: settings.shareTagRenamePattern,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(AppLocalizations.of(context)!.shareRenameTemplate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.shareRenameTemplateHint,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (value != null) await settings.setShareTagRenamePattern(value);
  }
}
