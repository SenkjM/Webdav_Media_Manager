import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_locale.dart';
import '../models/cache_policy.dart';
import '../models/snack_duration.dart';
import '../providers/app_state.dart';
import '../services/download_queue_service.dart';
import '../services/library_service.dart';
import '../services/library_actions.dart';
import '../services/notification_permission_service.dart';
import '../services/settings_service.dart';
import 'accounts_screen.dart';
import 'audio_stream_settings_screen.dart';
import 'image_settings_screen.dart';
import '../theme/app_theme.dart';
import '../utils/cover_image.dart';
import '../utils/audio_extensions.dart';
import 'file_extensions_screen.dart';
import 'home_shell.dart';
import 'sync_screen.dart';
import 'video_settings_screen.dart';
import '../utils/app_snack.dart';
import 'download_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _customDaysController;
  late final TextEditingController _customHoursController;
  late final TextEditingController _coverSizeController;

  /// When non-null, overrides derived preset (lets user open 「自定义」 before applying).
  String? _coverUiMode;
  int? _cacheBytes;
  bool _cacheSizeLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _customDaysController = TextEditingController();
    _customHoursController = TextEditingController();
    _coverSizeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationPermissionService>().refresh();
      _syncCustomFieldsFromSettings();
      _refreshCacheSize();
    });
  }

  Future<void> _refreshCacheSize() async {
    setState(() => _cacheSizeLoading = true);
    try {
      final bytes = await context.read<AppState>().cache.cacheSizeBytes();
      if (!mounted) return;
      setState(() {
        _cacheBytes = bytes;
        _cacheSizeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheSizeLoading = false);
    }
  }

  void _syncCustomFieldsFromSettings() {
    final settings = context.read<SettingsService>();
    final total = settings.customRetentionHours;
    final days = total ~/ 24;
    final hours = total % 24;
    _customDaysController.text = '$days';
    _customHoursController.text = '$hours';
    final edge = settings.coverThumbSizePx;
    if (edge != coverThumbSize && edge != coverThumbSizeLarge) {
      _coverSizeController.text = '$edge';
    }
  }

  String _coverPresetKey(int edge) {
    if (edge == coverThumbSize) return '100';
    if (edge == coverThumbSizeLarge) return '300';
    return 'custom';
  }

  String _coverMode(SettingsService settings) =>
      _coverUiMode ?? _coverPresetKey(settings.coverThumbSizePx);

  Future<void> _applyCustomCoverSize() async {
    final parsed = int.tryParse(_coverSizeController.text.trim());
    if (parsed == null) return;
    await context.read<AppState>().setCoverThumbSize(parsed);
    if (!mounted) return;
    setState(() => _coverUiMode = 'custom');
    _syncCustomFieldsFromSettings();
  }

  Future<void> _applyCustomRetention() async {
    final days = int.tryParse(_customDaysController.text.trim()) ?? 0;
    final hours = int.tryParse(_customHoursController.text.trim()) ?? 0;
    var totalHours = days * 24 + hours;
    if (totalHours < 1) totalHours = 1;
    await context.read<AppState>().setCustomRetentionDuration(
      Duration(hours: totalHours),
    );
    if (!mounted) return;
    _syncCustomFieldsFromSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _customDaysController.dispose();
    _customHoursController.dispose();
    _coverSizeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NotificationPermissionService>().refresh();
    }
  }

  Future<void> _clearCache(BuildContext context) async {
    final n = await context.read<AppState>().manualClearCache();
    if (!context.mounted) return;
    final libCount = context.read<LibraryService>().count;
    await _refreshCacheSize();
    if (!context.mounted) return;
    AppSnack.show(context, AppLocalizations.of(context)!.cacheCleared(n, libCount));
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
      AppLocalizations.of(context)!.tagRefreshCompleted(result.updated, result.skipped, result.failed),
      error: result.failed > 0 && result.updated == 0,
    );
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    if (perms.isGranted) {
      AppSnack.show(context, AppLocalizations.of(context)!.notificationEnabled);
      return;
    }
    if (perms.isChannelBlocked || perms.isPermanentlyDenied) {
      final opened = await perms.openSystemSettings();
      if (!context.mounted) return;
      AppSnack.show(
        context,
        opened ? AppLocalizations.of(context)!.notificationOpenSettings : AppLocalizations.of(context)!.notificationOpenSettingsFailed,
      );
      return;
    }
    final granted = await perms.request();
    if (!context.mounted) return;
    AppSnack.show(context, granted ? AppLocalizations.of(context)!.notificationGranted : AppLocalizations.of(context)!.notificationDenied);
  }

  String _customRetentionSummary(SettingsService settings) {
    final total = settings.customRetentionHours;
    final days = total ~/ 24;
    final hours = total % 24;
    if (days > 0 && hours > 0) {
      return AppLocalizations.of(context)!.retentionDaysHours(days, hours);
    }
    if (days > 0) {
      return AppLocalizations.of(context)!.retentionDays(days);
    }
    return AppLocalizations.of(context)!.retentionHours(hours);
  }

  String _notificationSubtitle(NotificationPermissionService perms) {
    if (!perms.loaded) return AppLocalizations.of(context)!.notificationChecking;
    if (perms.isGranted) {
      return AppLocalizations.of(context)!.notificationStatusAllowed;
    }
    if (perms.isChannelBlocked) {
      return AppLocalizations.of(context)!.notificationChannelBlocked;
    }
    if (perms.isPermanentlyDenied) {
      return AppLocalizations.of(context)!.notificationStatusDenied;
    }
    if (perms.isChannelMissing) {
      return AppLocalizations.of(context)!.notificationChannelMissing;
    }
    return AppLocalizations.of(context)!.notificationNotGranted;
  }

  /// Re-reads permission +「音乐播放」channel state from the system and
  /// reports what flutter_local_notifications currently sees.
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final notif = context.watch<NotificationPermissionService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(AppLocalizations.of(context)!.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
           ListTile(
             contentPadding: EdgeInsets.zero,
             leading: const Icon(Icons.language),
             title: Text(AppLocalizations.of(context)!.language),
             subtitle: Text(AppLocalizations.of(context)!.languageSettingSubtitle),
             trailing: DropdownButton<AppLocalePreference>(
               value: settings.appLocale,
               items: [
                 DropdownMenuItem(value: AppLocalePreference.system, child: Text(AppLocalizations.of(context)!.languageSystem)),
                 DropdownMenuItem(value: AppLocalePreference.zhCN, child: Text(AppLocalizations.of(context)!.languageSimplifiedChinese)),
                 DropdownMenuItem(value: AppLocalePreference.zhTW, child: Text(AppLocalizations.of(context)!.languageTraditionalChinese)),
                 DropdownMenuItem(value: AppLocalePreference.en, child: Text(AppLocalizations.of(context)!.languageEnglish)),
               ],
               onChanged: (value) {
                 if (value != null) {
                   context.read<SettingsService>().setAppLocale(value);
                 }
               },
             ),
           ),
           const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.webdavServer,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: Text(AppLocalizations.of(context)!.accountsTitle),
            subtitle: Text(AppLocalizations.of(context)!.accountsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
            },
          ),
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.download,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(AppLocalizations.of(context)!.downloadQueue),
            subtitle: Text(AppLocalizations.of(context)!.downloadQueueSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DownloadSettingsScreen(),
                ),
              );
            },
          ),
          Text(
            AppLocalizations.of(context)!.homeAndNavigation,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text(AppLocalizations.of(context)!.customHome),
            subtitle: Text(AppLocalizations.of(context)!.customHomeSubtitle),
            trailing: DropdownButton<int>(
              value: settings.homeTab,
              items: [
                DropdownMenuItem(value: 0, child: Text(AppLocalizations.of(context)!.library)),
                DropdownMenuItem(value: 1, child: Text(AppLocalizations.of(context)!.playlists)),
                DropdownMenuItem(value: 2, child: Text(AppLocalizations.of(context)!.networkLibrary)),
                DropdownMenuItem(value: 3, child: Text(AppLocalizations.of(context)!.downloadQueue)),
                DropdownMenuItem(value: 4, child: Text(AppLocalizations.of(context)!.settings)),
              ],
              onChanged: (v) {
                if (v != null) context.read<SettingsService>().setHomeTab(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.history),
            title: Text(AppLocalizations.of(context)!.rememberNetworkPath),
            subtitle: Text(AppLocalizations.of(context)!.rememberNetworkPathSubtitle),
            value: settings.networkRememberLastPath,
            onChanged: (v) =>
                context.read<SettingsService>().setNetworkRememberLastPath(v),
          ),
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.streamingSection,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_library_outlined),
            title: Text(AppLocalizations.of(context)!.videoSettings),
            subtitle: Text(AppLocalizations.of(context)!.videoSettingsSubtitle),
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
            title: Text(AppLocalizations.of(context)!.audioStreamingTitle),
            subtitle: Text(AppLocalizations.of(context)!.audioStreamingSubtitle),
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
            title: Text(AppLocalizations.of(context)!.imageViewer),
            subtitle: Text(AppLocalizations.of(context)!.imageViewerSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImageSettingsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.fileTypes,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: Text(AppLocalizations.of(context)!.fileTypesManage),
            subtitle: Text(AppLocalizations.of(context)!.fileTypesManageSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FileExtensionsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sell_outlined),
            title: Text(AppLocalizations.of(context)!.refreshLibraryTags),
            subtitle: Text(AppLocalizations.of(context)!.refreshLibraryTagsSubtitle),
            onTap: () => unawaited(_refreshLibraryTags(context)),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.mediaNotifications,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              notif.isGranted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(AppLocalizations.of(context)!.mediaNotifications),
            subtitle: Text(_notificationSubtitle(notif)),
            value: notif.isGranted,
            onChanged: (_) => _onNotificationTap(context, notif),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq),
            title: Text(AppLocalizations.of(context)!.ntfMediaChannelName),
            subtitle: Text(notif.channelStatusLabel),
            trailing: TextButton(
              onPressed: () => _refreshNotificationState(context, notif),
              child: Text(AppLocalizations.of(context)!.refresh),
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
          Text(
            AppLocalizations.of(context)!.coverThumbSize,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.coverThumbHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: '100', label: Text('100×100')),
              ButtonSegment(value: '300', label: Text('300×300')),
              ButtonSegment(value: 'custom', label: Text('自定义')),
            ],
            selected: {_coverMode(settings)},
            onSelectionChanged: (sel) async {
              final v = sel.first;
              if (v == '100') {
                setState(() => _coverUiMode = null);
                await context.read<AppState>().setCoverThumbSize(
                  coverThumbSize,
                );
              } else if (v == '300') {
                setState(() => _coverUiMode = null);
                await context.read<AppState>().setCoverThumbSize(
                  coverThumbSizeLarge,
                );
              } else {
                setState(() {
                  _coverUiMode = 'custom';
                  if (_coverSizeController.text.trim().isEmpty) {
                    _coverSizeController.text = '${settings.coverThumbSizePx}';
                  }
                });
              }
            },
          ),
          if (_coverMode(settings) == 'custom') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _coverSizeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: AppLocalizations.of(context)!.coverSize,
                      border: const OutlineInputBorder(),
                      helperText: '$minCoverThumbSize–$maxCoverThumbSize',
                    ),
                    onEditingComplete: _applyCustomCoverSize,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _applyCustomCoverSize,
                  child: Text(AppLocalizations.of(context)!.apply),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '当前：${settings.coverThumbSizePx}×${settings.coverThumbSizePx}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.cacheCleanup,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context)!.cacheCleanupHint),
          const SizedBox(height: 12),
          Card(
            color: AppColors.elevated,
            child: ListTile(
              leading: const Icon(
                Icons.sd_storage_outlined,
                color: AppColors.accent,
              ),
              title: Text(AppLocalizations.of(context)!.currentCacheUsage),
              subtitle: Text(
                _cacheSizeLoading
                    ? AppLocalizations.of(context)!.calculating
                    : (_cacheBytes == null
                          ? AppLocalizations.of(context)!.unknown
                          : formatByteSize(_cacheBytes!)),
              ),
              trailing: IconButton(
                tooltip: AppLocalizations.of(context)!.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: _cacheSizeLoading ? null : _refreshCacheSize,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CacheRetention>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: CacheRetention.oneDay,
                label: Text(CacheRetention.oneDay.label(AppLocalizations.of(context)!)),
              ),
              ButtonSegment(
                value: CacheRetention.oneWeek,
                label: Text(CacheRetention.oneWeek.label(AppLocalizations.of(context)!)),
              ),
              ButtonSegment(
                value: CacheRetention.custom,
                label: Text(CacheRetention.custom.label(AppLocalizations.of(context)!)),
              ),
              ButtonSegment(
                value: CacheRetention.never,
                label: Text(CacheRetention.never.label(AppLocalizations.of(context)!)),
              ),
            ],
            selected: {settings.retention},
            onSelectionChanged: (s) {
              final next = s.first;
              context.read<AppState>().setRetention(next);
              if (next == CacheRetention.custom) {
                _syncCustomFieldsFromSettings();
              }
            },
          ),
          if (settings.retention == CacheRetention.custom) ...[
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.customRetentionHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _customDaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: AppLocalizations.of(context)!.days,
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: _applyCustomRetention,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _customHoursController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: AppLocalizations.of(context)!.hours,
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: _applyCustomRetention,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _applyCustomRetention,
                  child: Text(AppLocalizations.of(context)!.apply),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _customRetentionSummary(settings),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (settings.retention == CacheRetention.never) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.autoCleanupDisabled,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _clearCache(context),
            icon: const Icon(Icons.delete_outline),
            label: Text(AppLocalizations.of(context)!.clearAudioCache),
          ),

          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.hintsAndNotifications,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.hintsSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: Text(AppLocalizations.of(context)!.hintDuration),
            subtitle: Text(settings.snackMode.label(AppLocalizations.of(context)!)),
            trailing: DropdownButton<SnackDuration>(
              value: settings.snackMode,
              items: [
                for (final m in SnackDuration.values)
                  DropdownMenuItem(value: m, child: Text(m.label(AppLocalizations.of(context)!))),
              ],
              onChanged: (v) {
                if (v != null) settings.setSnackMode(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.download_outlined),
            title: Text(AppLocalizations.of(context)!.downloadNotifications),
            subtitle: Text(AppLocalizations.of(context)!.downloadNotificationsHint),
            value: settings.downloadNotificationsEnabled,
            onChanged: (v) async {
              await settings.setDownloadNotificationsEnabled(v);
              if (!context.mounted) return;
              await context.read<DownloadQueueService>().setNotifications(v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.downloading_outlined),
            title: Text(AppLocalizations.of(context)!.downloadKeepAlive),
            subtitle: Text(AppLocalizations.of(context)!.downloadKeepAliveHint),
            value: settings.downloadKeepAliveEnabled,
            onChanged: (v) async {
              await settings.setDownloadKeepAliveEnabled(v);
              if (!context.mounted) return;
              await context.read<DownloadQueueService>().setKeepAliveEnabled(v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.notifications_active_outlined, size: 20),
            title: Text(AppLocalizations.of(context)!.sendTestNotification, style: TextStyle(fontSize: 14)),
            subtitle: Text(
              AppLocalizations.of(context)!.sendTestNotificationHint,
              style: TextStyle(fontSize: 11),
            ),
            onTap: () async {
              final err = await context
                  .read<DownloadQueueService>()
                  .notificationService
                  .selfTest();
              if (!context.mounted) return;
              if (err == null) {
                AppSnack.show(context, AppLocalizations.of(context)!.testNotificationSent);
              } else {
                AppSnack.error(context, AppLocalizations.of(context)!.testNotificationFailed(err));
              }
            },
          ),

          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.shareAction,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context)!.shareRenameHint, style: Theme.of(context).textTheme.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.drive_file_rename_outline),
            title: Text(AppLocalizations.of(context)!.shareRenameTitle),
            subtitle: Text(AppLocalizations.of(context)!.shareRenameSubtitle),
            value: settings.shareTagRenameEnabled,
            onChanged: (v) => settings.setShareTagRenameEnabled(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: Text(AppLocalizations.of(context)!.renameTemplate),
            subtitle: Text(
              '${settings.shareTagRenamePattern}\n'
              '占位符：{artist} {title} {album} {albumArtist} '
              '{track} {year} {genre} {fileName}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editShareRenamePattern(settings),
          ),

          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.syncAndBackup,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          // Same shape as 视频播放 / 文件类型 above: a row with a chevron, not a
          // button — this opens another screen, it does not run an action.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: Text(AppLocalizations.of(context)!.syncSettings),
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

  Future<void> _editShareRenamePattern(SettingsService settings) async {
    final controller = TextEditingController(
      text: settings.shareTagRenamePattern,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(AppLocalizations.of(context)!.shareRenameTemplate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            const Text(
              '留空字段自动去掉多余分隔符，扩展名始终保留。',
              style: TextStyle(color: AppColors.mutedText, fontSize: 11),
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
