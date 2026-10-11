import 'package:flutter/material.dart';
import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';

/// 设置 → 网络库 → 加密设置。
///
/// Crypt 顺序流下载与 content secretbox 引擎（Dart / libsodium）放在这里。
/// libsodium 由 openlist_crypt 的构建 hook 按目标 ABI 随包；开关只看库是否
/// 真的加载成功（[SettingsService.libsodiumSecretboxAvailable]），加载不了就
/// 禁用并提示走 Dart，不按 ABI 判断。
class EncryptionSettingsScreen extends StatelessWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final sodiumAvailable = settings.libsodiumSecretboxAvailable;
    final preferSodium = settings.preferLibsodiumSecretboxEnabled;
    final backend = secretboxBackend;
    final version = libsodiumVersionString();

    final String statusText;
    if (backend == SecretboxBackend.libsodium && version != null) {
      statusText = l10n.cryptLibsodiumStatusSodium(version);
    } else if (backend == SecretboxBackend.libsodium) {
      statusText = l10n.cryptLibsodiumStatusSodium('?');
    } else {
      statusText = l10n.cryptLibsodiumStatusDart;
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text(l10n.encryptionSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.encryptionCryptSection,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                  ),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.encryptionSecretboxSection,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.cryptLibsodiumPreferSub,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(l10n.cryptLibsodiumPrefer),
            subtitle: Text(
              sodiumAvailable
                  ? statusText
                  : l10n.cryptLibsodiumUnavailable,
            ),
            value: preferSodium && sodiumAvailable,
            onChanged: sodiumAvailable
                ? (value) => context
                    .read<SettingsService>()
                    .setPreferLibsodiumSecretboxEnabled(value)
                : null,
          ),
        ],
      ),
    );
  }
}
