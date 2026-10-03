import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_locale.dart';
import '../models/app_theme_mode.dart';
import '../models/snack_duration.dart';
import '../services/library_actions.dart';
import '../services/library_service.dart';
import '../services/notification_permission_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import 'accounts_screen.dart';
import 'audio_stream_settings_screen.dart';
import 'cache_settings_screen.dart';
import 'download_settings_screen.dart';
import 'file_extensions_screen.dart';
import 'home_shell.dart';
import 'image_settings_screen.dart';
import 'share_settings_screen.dart';
import 'sync_screen.dart';
import 'thumbnail_settings_screen.dart';
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

  Future<void> _refreshLibraryTags(BuildContext context) async {
    final library = context.read<LibraryService>();
    if (library.tracks.isEmpty) {
      AppSnack.show(context, AppLocalizations.of(context)!.libraryEmpty);
      return;
    }
    AppSnack.show(context, AppLocalizations.of(context)!.tagRefreshStarted);
    final result = await refreshLibraryTrackTags(
      context,
      library.tracks.toList(),
      showProgressDialog: false,
    );
    if (!context.mounted) return;
    AppSnack.show(
      context,
      AppLocalizations.of(context)!
          .tagRefreshCompleted(result.updated, result.skipped, result.failed),
      error: result.failed > 0 && result.updated == 0,
    );
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
    AppSnack.show(
      context,
      '通知权限：${perms.isGranted ? '已允许' : '未允许'}｜'
      '通道「音乐播放」：${perms.channelStatusLabel}',
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: AppColors.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final notif = context.watch<NotificationPermissionService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
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
              value: settings.homeTab,
              items: [
                DropdownMenuItem(value: 0, child: Text(l10n.library)),
                DropdownMenuItem(value: 1, child: Text(l10n.playlists)),
                DropdownMenuItem(value: 2, child: Text(l10n.networkLibrary)),
                DropdownMenuItem(value: 3, child: Text(l10n.downloadQueue)),
                DropdownMenuItem(value: 4, child: Text(l10n.settings)),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_size_select_large_outlined),
            title: Text(l10n.settingsThumbnails),
            subtitle: Text(l10n.settingsThumbnailsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ThumbnailSettingsScreen(),
                ),
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
                      ? '打开系统设置'
                      : '请求通知权限',
                ),
              ),
            ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.library),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sell_outlined),
            title: Text(l10n.refreshLibraryTags),
            subtitle: Text(l10n.refreshLibraryTagsSubtitle),
            onTap: () => unawaited(_refreshLibraryTags(context)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l10n.cacheCleanup),
            subtitle: Text(l10n.cacheCleanupHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CacheSettingsScreen()),
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
            leading: const Icon(Icons.graphic_eq),
            title: Text(l10n.audioStreamingTitle),
            subtitle: Text(l10n.audioStreamingSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AudioStreamSettingsScreen(),
                ),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l10n.themeMode),
            subtitle: Text(l10n.themeModeSubtitle),
            trailing: DropdownButton<AppThemeMode>(
              value: settings.appThemeMode,
              items: [
                DropdownMenuItem(
                  value: AppThemeMode.system,
                  child: Text(l10n.themeModeSystem),
                ),
                DropdownMenuItem(
                  value: AppThemeMode.light,
                  child: Text(l10n.themeModeLight),
                ),
                DropdownMenuItem(
                  value: AppThemeMode.dark,
                  child: Text(l10n.themeModeDark),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  context.read<SettingsService>().setAppThemeMode(value);
                }
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            subtitle: Text(l10n.languageSettingSubtitle),
            trailing: DropdownButton<AppLocalePreference>(
              value: settings.appLocale,
              items: [
                DropdownMenuItem(
                  value: AppLocalePreference.system,
                  child: Text(l10n.languageSystem),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.zhCN,
                  child: Text(l10n.languageSimplifiedChinese),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.zhTW,
                  child: Text(l10n.languageTraditionalChinese),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.en,
                  child: Text(l10n.languageEnglish),
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
              '凭证 / 歌单 / 音乐库 / 备份共用一条远端路径：\n'
              '${settings.syncRemoteRoot}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SyncScreen()));
            },
          ),
          const Divider(height: 40),
          Text(
            '音乐先下载再本地播放；视频直接流式播放并按文件夹连播。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
