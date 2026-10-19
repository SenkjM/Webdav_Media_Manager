import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_locale.dart';
import '../models/snack_duration.dart';
import '../services/notification_permission_service.dart';
import '../services/settings_service.dart';
import '../widgets/theme_settings_section.dart';
import '../utils/app_snack.dart';
import 'accounts_screen.dart';
import 'download_settings_screen.dart';
import 'encryption_settings_screen.dart';
import 'file_extensions_screen.dart';
import 'home_shell.dart';
import 'image_settings_screen.dart';
import 'manga_library_settings_screen.dart';
import 'media_library_settings_screen.dart';
import 'share_settings_screen.dart';
import 'sync_screen.dart';
import 'video_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationPermissionService>().refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NotificationPermissionService>().refresh();
    }
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (perms.isGranted) {
      AppSnack.show(context, l10n.notificationEnabled);
      return;
    }
    if (perms.isChannelBlocked || perms.isPermanentlyDenied) {
      final opened = await perms.openSystemSettings();
      if (!context.mounted) return;
      AppSnack.show(
        context,
        opened
            ? l10n.notificationOpenSettings
            : l10n.notificationOpenSettingsFailed,
      );
      return;
    }
    final granted = await perms.request();
    if (!context.mounted) return;
    AppSnack.show(
      context,
      granted ? l10n.notificationGranted : l10n.notificationDenied,
    );
  }

  String _notificationSubtitle(NotificationPermissionService perms) {
    final l10n = AppLocalizations.of(context)!;
    if (!perms.loaded) return l10n.notificationChecking;
    if (perms.isGranted) return l10n.notificationStatusAllowed;
    if (perms.isChannelBlocked) return l10n.notificationChannelBlocked;
    if (perms.isPermanentlyDenied) return l10n.notificationStatusDenied;
    if (perms.isChannelMissing) return l10n.notificationChannelMissing;
    return l10n.notificationNotGranted;
  }

  Future<void> _refreshNotificationState(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    await perms.refresh();
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final channel = l10n.ntfMediaChannelName;
    final status = perms.channelStatusLabel;
    AppSnack.show(
      context,
      perms.isGranted
          ? l10n.notificationDiagnosticAllowed(channel, status)
          : l10n.notificationDiagnosticDenied(channel, status),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final notif = context.watch<NotificationPermissionService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(l10n.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, l10n.homeAndNavigation),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text(l10n.customHome),
            subtitle: Text(l10n.customHomeSubtitle),
            trailing: DropdownButton<int>(
              borderRadius: BorderRadius.circular(10),
              value: settings.homeTab,
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(l10n.librarySectionFolders),
                ),
                DropdownMenuItem(value: 1, child: Text(l10n.library)),
                DropdownMenuItem(value: 2, child: Text(l10n.playlists)),
                DropdownMenuItem(value: 3, child: Text(l10n.mangaLibrary)),
                DropdownMenuItem(value: 4, child: Text(l10n.networkLibrary)),
                // Emby 标签固定英文（99 §21 Emby 媒体库），插入索引 5。
                const DropdownMenuItem(value: 5, child: Text('Emby')),
                DropdownMenuItem(value: 6, child: Text(l10n.taskQueue)),
                DropdownMenuItem(value: 7, child: Text(l10n.settings)),
              ],
              onChanged: (v) {
                if (v != null) context.read<SettingsService>().setHomeTab(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.history),
            title: Text(l10n.rememberNetworkPath),
            subtitle: Text(l10n.rememberNetworkPathSubtitle),
            value: settings.networkRememberLastPath,
            onChanged: (v) =>
                context.read<SettingsService>().setNetworkRememberLastPath(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.share_outlined),
            title: Text(l10n.shareAction),
            subtitle: Text(l10n.settingsShareSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ShareSettingsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              notif.isGranted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(l10n.mediaNotifications),
            subtitle: Text(_notificationSubtitle(notif)),
            value: notif.isGranted,
            onChanged: (_) => _onNotificationTap(context, notif),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq),
            title: Text(l10n.ntfMediaChannelName),
            subtitle: Text(notif.channelStatusLabel),
            trailing: TextButton(
              onPressed: () => _refreshNotificationState(context, notif),
              child: Text(l10n.refresh),
            ),
          ),
          if (!notif.isGranted)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _onNotificationTap(context, notif),
                icon: const Icon(Icons.notification_add_outlined),
                label: Text(
                  (notif.isPermanentlyDenied || notif.isChannelBlocked)
                      ? l10n.openSystemSettings
                      : l10n.requestNotificationPermission,
                ),
              ),
            ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.mediaLibrarySection),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_music_outlined),
            title: Text(l10n.mediaLibrarySettings),
            subtitle: Text(l10n.mediaLibrarySettingsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MediaLibrarySettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.mangaLibrarySettingsSection),
            subtitle: Text(l10n.mangaLibrarySettingsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MangaLibrarySettingsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.networkLibrary),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: Text(l10n.accountsTitle),
            subtitle: Text(l10n.accountsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.download),
            subtitle: Text(l10n.downloadQueueSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DownloadSettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.encryptionSettings),
            subtitle: Text(l10n.encryptionSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EncryptionSettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_library_outlined),
            title: Text(l10n.videoSettings),
            subtitle: Text(l10n.videoSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoSettingsScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.imageViewer),
            subtitle: Text(l10n.imageViewerSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImageSettingsScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: Text(l10n.fileTypesManage),
            subtitle: Text(l10n.fileTypesManageSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FileExtensionsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.settingsMisc),
          const SizedBox(height: 8),
          ThemeSettingsSection(
            mode: settings.appThemeMode,
            onModeChanged: (value) {
              context.read<SettingsService>().setAppThemeMode(value);
            },
            seed: settings.themeSeed,
            onSeedChanged: (color) {
              context.read<SettingsService>().setThemeSeed(color);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            subtitle: Text(l10n.languageSettingSubtitle),
            trailing: DropdownButton<AppLocalePreference>(
              borderRadius: BorderRadius.circular(10),
              value: settings.appLocale,
              items: [
                DropdownMenuItem(
                  value: AppLocalePreference.system,
                  child: Text(l10n.languageSystem),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.zhCN,
                  child: Text(AppLocalePreference.zhCN.nativeName!),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.zhTW,
                  child: Text(AppLocalePreference.zhTW.nativeName!),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.en,
                  child: Text(AppLocalePreference.en.nativeName!),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  context.read<SettingsService>().setAppLocale(value);
                }
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.hintDuration),
            subtitle: Text(settings.snackMode.label(l10n)),
            trailing: DropdownButton<SnackDuration>(
              borderRadius: BorderRadius.circular(10),
              value: settings.snackMode,
              items: [
                for (final m in SnackDuration.values)
                  DropdownMenuItem(value: m, child: Text(m.label(l10n))),
              ],
              onChanged: (v) {
                if (v != null) settings.setSnackMode(v);
              },
            ),
          ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.syncAndBackup),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: Text(l10n.syncSettings),
            subtitle: Text(
              '${l10n.settingsSyncSharedPath}\n'
              '${settings.syncRemoteRoot}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SyncScreen()));
            },
          ),

          Text(
            l10n.settingsPlaybackFooter,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
