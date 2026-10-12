import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/account_sentinels.dart';
import '../models/webdav_account.dart';
import '../services/accounts_service.dart';

/// Temporary gate: user must delete same-name accounts before UNIQUE applies.
class AccountNameCleanupScreen extends StatelessWidget {
  const AccountNameCleanupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accounts = context.watch<AccountsService>();
    final groups = accounts.duplicateNameGroups();
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountNameCleanupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l10n.accountNameCleanupHeading,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.accountNameCleanupBody),
              const SizedBox(height: 20),
              for (final e in entries) ...[
                Text(
                  l10n.accountNameCleanupGroup(e.value.first.name),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final a in e.value)
                  _ConflictTile(account: a, activeId: accounts.activeAccountId),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({required this.account, required this.activeId});

  final WebDavAccount account;
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = account.id == activeId;
    final subtitle = [
      if (account.url.trim().isNotEmpty) account.url.trim(),
      if (account.username.trim().isNotEmpty) account.username.trim(),
      if (isActive) l10n.accountNameCleanupActive,
    ].join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(localizedAccountName(l10n, account.name)),
        subtitle: Text(subtitle),
        isThreeLine: subtitle.contains('\n'),
        trailing: IconButton(
          tooltip: l10n.delete,
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.accountNameCleanupDeleteTitle),
                content: Text(
                  l10n.accountNameCleanupDeleteContent(
                    localizedAccountName(l10n, account.name),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.delete),
                  ),
                ],
              ),
            );
            if (ok != true || !context.mounted) return;
            await context.read<AccountsService>().deleteAccount(account.id);
          },
        ),
      ),
    );
  }
}
