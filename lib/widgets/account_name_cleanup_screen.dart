import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/account_sentinels.dart';
import '../models/webdav_account.dart';
import '../services/accounts_service.dart';
import '../services/cloud_drive_service.dart';

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

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
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
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountNameCleanupDetailScreen(accountId: account.id),
      ),
    );
  }

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
        onTap: () => _openDetail(context),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Secondary screen: full credential values so duplicates can be told apart.
class AccountNameCleanupDetailScreen extends StatefulWidget {
  const AccountNameCleanupDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<AccountNameCleanupDetailScreen> createState() =>
      _AccountNameCleanupDetailScreenState();
}

class _AccountNameCleanupDetailScreenState
    extends State<AccountNameCleanupDetailScreen> {
  String? _password;
  var _passwordLoaded = false;
  var _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPassword());
  }

  Future<void> _loadPassword() async {
    final pass =
        await context.read<AccountsService>().passwordFor(widget.accountId);
    if (!mounted) return;
    setState(() {
      _password = pass;
      _passwordLoaded = true;
    });
  }

  Future<void> _confirmDelete(WebDavAccount account) async {
    final l10n = AppLocalizations.of(context)!;
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
    if (ok != true || !mounted) return;
    await context.read<AccountsService>().deleteAccount(account.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accounts = context.watch<AccountsService>();
    final cloud = context.watch<CloudDriveService>();
    WebDavAccount? account;
    for (final a in accounts.accounts) {
      if (a.id == widget.accountId) {
        account = a;
        break;
      }
    }
    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.accountNameCleanupDetailTitle)),
        body: const SizedBox.shrink(),
      );
    }
    final a = account;
    final isActive = a.id == accounts.activeAccountId;
    final typeLabel = a.url.isNotEmpty ? a.providerType : cloud.typeLabelFor(a);
    final passwordText = !_passwordLoaded
        ? '…'
        : (_password == null || _password!.isEmpty)
            ? l10n.accountNameCleanupNoPassword
            : _password!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountNameCleanupDetailTitle),
        actions: [
          IconButton(
            tooltip: l10n.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(a),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _DetailRow(
                label: l10n.accountName,
                value: localizedAccountName(l10n, a.name),
              ),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.accountNameCleanupActive,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              _DetailRow(label: l10n.accountNameCleanupId, value: a.id),
              _DetailRow(label: l10n.accountType, value: typeLabel),
              if (a.url.trim().isNotEmpty)
                _DetailRow(label: l10n.accountServerUrl, value: a.url),
              if (a.username.trim().isNotEmpty)
                _DetailRow(label: l10n.accountUsername, value: a.username),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.accountPassword),
                subtitle: Text(
                  _obscurePassword &&
                          _passwordLoaded &&
                          _password != null &&
                          _password!.isNotEmpty
                      ? '••••••••'
                      : passwordText,
                ),
                trailing: (_passwordLoaded &&
                        _password != null &&
                        _password!.isNotEmpty)
                    ? IconButton(
                        tooltip: _obscurePassword
                            ? l10n.accountNameCleanupShowPassword
                            : l10n.accountNameCleanupHidePassword,
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      )
                    : null,
              ),
              _DetailRow(label: l10n.accountRemotePath, value: a.remotePath),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}
