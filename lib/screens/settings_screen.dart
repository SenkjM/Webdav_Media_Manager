import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_locale.dart';
import '../models/codec_capability.dart';
import '../models/snack_duration.dart';
import '../services/codec_capability_service.dart';
import '../services/notification_permission_service.dart';
import '../services/rust_core_service.dart';
import '../services/settings_service.dart';
import '../services/transcode_preset_catalog.dart';
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
import 'openapi_settings_screen.dart';
import 'share_settings_screen.dart';
import 'sync_screen.dart';
import 'transcode_presets_screen.dart';
import 'video_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// DLNA 转码预设选项：来自 Core 数据库（已排除直通），管理页返回后刷新。
  List<TranscodePresetOption> _dlnaPresets = TranscodePresetCatalog.fallback;

  /// 转码缓存统计（Rust `wdmm_transcode_cache_stats_json`）。
  /// null 且 [_transcodeCacheStatsLoaded] 为 true 表示旧版 `.so` 不支持。
  _TranscodeCacheStats? _transcodeCacheStats;
  bool _transcodeCacheStatsLoaded = false;

  /// 统计读取失败时的可读原因（如「本地代理未启动」），成功时为 null。
  String? _transcodeCacheStatsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dlnaPresets = TranscodePresetCatalog.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationPermissionService>().refresh();
      unawaited(_refreshTranscodeCacheStats());
    });
  }

  /// 重新读取数据库里的转码预设（从「管理转码预设」返回后调用）。
  void _reloadDlnaPresets() {
    final presets = TranscodePresetCatalog.load();
    if (!mounted) return;
    setState(() => _dlnaPresets = presets);
  }

  // ── 转码缓存（契约 hls-vod-transcode-cache §3.5、§4）────────────────────

  /// 读取转码缓存统计。轻量本地 FFI（只读内存里的统计），直接调用即可。
  Future<void> _refreshTranscodeCacheStats() async {
    final raw = RustCoreService.transcodeCacheStatsJson();
    final stats = _TranscodeCacheStats.parse(raw);
    final error =
        stats == null && raw != null ? _decodeCacheError(raw) : null;
    if (!mounted) return;
    setState(() {
      _transcodeCacheStats = stats;
      _transcodeCacheStatsLoaded = true;
      _transcodeCacheStatsError = error;
    });
  }

  /// 清理全部转码缓存，然后刷新用量。
  Future<void> _clearTranscodeCache() async {
    final raw = RustCoreService.transcodeCacheClear();
    if (!mounted) return;
    final ok = _cacheClearSucceeded(raw);
    final String message;
    if (ok) {
      message = '转码缓存已清理';
    } else if (raw == null) {
      message = '当前原生库不支持清理转码缓存';
    } else {
      final error = _decodeCacheError(raw);
      message = error == null ? '清理失败' : '清理失败：$error';
    }
    AppSnack.show(context, message, error: !ok);
    await _refreshTranscodeCacheStats();
  }

  /// Rust 清理命令的成功判定：字面量 `ok` 或 `{"ok":true,…}` 都算成功。
  static bool _cacheClearSucceeded(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    if (raw == 'ok') return true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded['ok'] == true;
    } catch (_) {
      // 非 JSON：旧版 `.so` 的 `error:…` 前缀走下面的兜底判定。
    }
    return !raw.startsWith('error:');
  }

  /// 从命令回包里取错误文本（`error:` 前缀或 `{"error":…}`）。
  ///
  /// Rust 的 `proxy not started` 在 UI 上换成中文，其余保持原样便于排查。
  static String? _decodeCacheError(String raw) {
    String? message;
    if (raw.startsWith('error:')) {
      message = raw.substring(6);
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final error = decoded['error']?.toString();
          if (error != null && error.isNotEmpty) message = error;
        }
      } catch (_) {}
    }
    if (message == null) return null;
    if (message.contains('proxy not started')) return '本地代理未启动';
    return message;
  }

  /// 编辑缓存预算（MB）。非法值不落盘。
  Future<void> _editTranscodeCacheBudget() async {
    final settings = context.read<SettingsService>();
    final controller = TextEditingController(
      text: settings.transcodeCacheBudgetMb.toString(),
    );
    final saved = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('转码缓存预算'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '预算（MB）',
            helperText: '默认 2048 MB；超出后按最久未使用淘汰',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || saved == null) return;
    if (saved <= 0) {
      AppSnack.show(context, '缓存预算必须大于 0 MB', error: true);
      return;
    }
    settings.transcodeCacheBudgetMb = saved;
    AppSnack.show(context, '缓存预算已设为 $saved MB，新投屏会话生效');
    await _refreshTranscodeCacheStats();
  }

  /// 缓存用量副标题：读取中 / 不可用原因 / 旧版不支持 / 已用 + 预算 + 文件数。
  String _cacheStatsSubtitle() {
    if (!_transcodeCacheStatsLoaded) return '读取中…';
    final stats = _transcodeCacheStats;
    if (stats == null) {
      final error = _transcodeCacheStatsError;
      return error == null ? '当前原生库不提供缓存统计' : '暂不可用：$error';
    }
    final parts = <String>[
      '已用 ${_formatCacheBytes(stats.bytes)} / '
          '${stats.budget > 0 ? _formatCacheBytes(stats.budget) : '未知'}',
      '${stats.entries} 个文件',
    ];
    if (stats.hits > 0) parts.add('命中 ${stats.hits} 次');
    if (stats.overBudget) parts.add('超出预算');
    return parts.join(' · ');
  }

  static String _formatCacheBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
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

    // DLNA 转码预设选项来自 Core 数据库（不含直通）。
    final dlnaPresetIds = [for (final preset in _dlnaPresets) preset.id];

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
                DropdownMenuItem(value: 5, child: Text(l10n.taskQueue)),
                DropdownMenuItem(value: 6, child: Text(l10n.settings)),
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
          // ── DLNA 投屏 ──────────────────────────────────────────────────────
          _sectionTitle(context, 'DLNA 投屏'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cast_outlined),
            title: const Text('转码预设'),
            trailing: DropdownButton<String>(
              borderRadius: BorderRadius.circular(10),
              value: dlnaPresetIds.contains(settings.dlnaDefaultTranscodePreset)
                  ? settings.dlnaDefaultTranscodePreset
                  : _dlnaPresets.first.id,
              items: [
                for (final preset in _dlnaPresets)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text(preset.label),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  context
                      .read<SettingsService>()
                      .dlnaDefaultTranscodePreset = v;
                }
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: const Text('管理转码预设'),
            subtitle: const Text('添加、编辑或删除自定义转码预设'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TranscodePresetsScreen(),
                ),
              );
              if (!mounted) return;
              _reloadDlnaPresets();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.bolt_outlined),
            title: const Text('默认直通'),
            subtitle: const Text('投屏时默认不转码，直接播放原文件'),
            value: settings.dlnaDefaultDirect,
            onChanged: (v) {
              context.read<SettingsService>().dlnaDefaultDirect = v;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.movie_filter_outlined),
            title: const Text('MKV 直通（不转码）'),
            subtitle: const Text(
              'MKV 包含内嵌字幕，转码会丢失；开启后 MKV 一律直通，'
              '接收端不支持其编码时可能无法播放',
            ),
            value: settings.dlnaMkvPassthrough,
            onChanged: (v) {
              context.read<SettingsService>().dlnaMkvPassthrough = v;
            },
          ),
          // ── 转码缓存（VOD 点播化 §3.5）────────────────────────────────
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('转码缓存'),
            subtitle: Text(_cacheStatsSubtitle()),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => unawaited(_refreshTranscodeCacheStats()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.data_usage),
            title: const Text('缓存预算'),
            subtitle: const Text('超出后按最久未使用淘汰；新投屏会话生效'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${settings.transcodeCacheBudgetMb} MB'),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => unawaited(_editTranscodeCacheBudget()),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清理缓存'),
            subtitle: const Text('删除所有已缓存的分片，下次投屏会重新转码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_clearTranscodeCache()),
          ),
          // ── 设备编码能力（契约 preset-rate-control-and-codec-probe §13.4）──
          const Divider(height: 40),
          _sectionTitle(context, l10n.codecCapsSectionTitle),
          const SizedBox(height: 8),
          const _CodecCapabilitySection(),
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
          const Divider(height: 40),
          // ── OpenAPI ────────────────────────────────────────────────────────
          _sectionTitle(context, 'OpenAPI'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.api_outlined),
            title: const Text('OpenAPI 设置'),
            subtitle: const Text('配置外部 API 访问与鉴权'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OpenApiSettingsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            l10n.settingsPlaybackFooter,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// `wdmm_transcode_cache_stats_json()` 的解析结果。
///
/// 只用于设置页展示；旧版 `.so` 缺符号时解析为 null，页面显示「不支持」。
class _TranscodeCacheStats {
  const _TranscodeCacheStats({
    required this.bytes,
    required this.budget,
    required this.entries,
    required this.hits,
    required this.overBudget,
  });

  final int bytes;
  final int budget;
  final int entries;
  final int hits;
  final bool overBudget;

  /// 解析 Rust 回传的 JSON；null / `error:` 前缀 / 非法 JSON / `ok:false` → null。
  static _TranscodeCacheStats? parse(String? raw) {
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['ok'] == false) return null;
      return _TranscodeCacheStats(
        bytes: _int(decoded['bytes']) ?? 0,
        budget: _int(decoded['budget']) ?? 0,
        entries: _int(decoded['entries']) ?? 0,
        hits: _int(decoded['hits']) ?? 0,
        overBudget: decoded['over_budget'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}

/// 只读的「设备编码能力」区块（契约 `preset-rate-control-and-codec-probe` §13.4）。
///
/// 数据来自安卓原生 `MediaCodecList` 的只读查询（Kotlin `CodecCapsProbe`），
/// 只用于提示机型上有哪些编码器 / 码率控制模式可用；实际编码能力仍由 Rust
/// 在转码开始时以「真开一次编码器」判定。因此探测不可用时这里只显示一行
/// 说明，不隐藏、不禁用任何功能。
class _CodecCapabilitySection extends StatefulWidget {
  const _CodecCapabilitySection();

  @override
  State<_CodecCapabilitySection> createState() =>
      _CodecCapabilitySectionState();
}

class _CodecCapabilitySectionState extends State<_CodecCapabilitySection> {
  CodecCapabilityService get _service => CodecCapabilityService.shared;

  @override
  void initState() {
    super.initState();
    // 懒加载：进入设置页才探测一次（全进程缓存，重复进入不重复查询）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_service.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = _service;

    if (service.status == CodecCapabilityStatus.idle || service.isLoading) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(l10n.codecCapsLoading),
        subtitle: Text(l10n.codecCapsSectionSubtitle),
      );
    }

    if (service.status == CodecCapabilityStatus.failed) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.codecCapsUnavailable),
        subtitle: Text(l10n.codecCapsSectionSubtitle),
        trailing: TextButton(
          onPressed: () => unawaited(service.refresh()),
          child: Text(l10n.codecCapsRetry),
        ),
      );
    }

    if (service.encoders.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.codecCapsEmpty),
        subtitle: Text(l10n.codecCapsSectionSubtitle),
        trailing: TextButton(
          onPressed: () => unawaited(service.refresh()),
          child: Text(l10n.codecCapsRetry),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.codecCapsSectionSubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (final codecId in knownHwCodecIds)
          _CodecCapabilityTile(
            codecId: codecId,
            capability: service.capabilitiesFor(codecId),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(service.refresh()),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.codecCapsRetry),
          ),
        ),
      ],
    );
  }
}

/// 单个硬件编码器（H.264 / H.265 / MPEG-4）的能力明细。
class _CodecCapabilityTile extends StatelessWidget {
  const _CodecCapabilityTile({required this.codecId, this.capability});

  final String codecId;
  final CodecCapability? capability;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cap = capability;
    final title = Text(_codecLabel(l10n));

    if (cap == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.memory),
        title: title,
        subtitle: Text(l10n.codecCapsNotReported),
      );
    }

    final subtitleParts = <String>[
      cap.hardware ? l10n.codecCapsHardware : l10n.codecCapsSoftware,
      if (cap.name.isNotEmpty) cap.name,
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.memory),
      title: title,
      subtitle: Text(subtitleParts.join(' · ')),
      children: [
        _row(
          context,
          l10n.codecCapsRateControl,
          _rateControlLabel(l10n, cap),
        ),
        _row(
          context,
          l10n.codecCapsBitrateRange,
          _bitrateLabel(l10n, cap.bitrateRange),
        ),
        _row(context, l10n.codecCapsResolutionRange, _resolutionLabel(l10n, cap)),
        _row(context, l10n.codecCapsAlignment, _alignmentLabel(l10n, cap)),
        _row(context, l10n.codecCapsFpsRange, _fpsLabel(l10n, cap.fpsRange)),
        _row(
          context,
          l10n.codecCapsProfileLevels,
          _profileLevelsLabel(l10n, cap.profileLevels),
        ),
      ],
    );
  }

  String _codecLabel(AppLocalizations l10n) => switch (codecId) {
        'h264_mediacodec' => l10n.codecCapsCodecH264,
        'hevc_mediacodec' => l10n.codecCapsCodecHevc,
        _ => l10n.codecCapsCodecMpeg4,
      };

  String _rateControlLabel(AppLocalizations l10n, CodecCapability cap) {
    final modes = cap.bitrateModes;
    if (modes == null) return l10n.codecCapsNotReported;
    return modes.map((m) => m.toUpperCase()).join(' / ');
  }

  String _bitrateLabel(AppLocalizations l10n, CodecRange? range) {
    if (range == null) return l10n.codecCapsNotReported;
    return '${_bps(range.min)} – ${_bps(range.max)}';
  }

  String _resolutionLabel(AppLocalizations l10n, CodecCapability cap) {
    final width = cap.widthRange;
    final height = cap.heightRange;
    if (width == null || height == null) return l10n.codecCapsNotReported;
    return '${width.min.toInt()}×${height.min.toInt()} – '
        '${width.max.toInt()}×${height.max.toInt()}';
  }

  String _alignmentLabel(AppLocalizations l10n, CodecCapability cap) {
    final width = cap.widthAlignment;
    final height = cap.heightAlignment;
    if (width == null && height == null) return l10n.codecCapsNotReported;
    return '${width ?? '?'}×${height ?? '?'} px';
  }

  String _fpsLabel(AppLocalizations l10n, CodecRange? range) {
    if (range == null) return l10n.codecCapsNotReported;
    return '${_short(range.min)} – ${_short(range.max)} fps';
  }

  String _profileLevelsLabel(AppLocalizations l10n, List<String> levels) {
    if (levels.isEmpty) return l10n.codecCapsNotReported;
    const maxShown = 8;
    final shown = levels.take(maxShown).join(' · ');
    return levels.length > maxShown ? '$shown …' : shown;
  }

  static String _bps(num bitsPerSecond) {
    final value = bitsPerSecond.toDouble();
    if (value >= 1000000) {
      return '${_short(value / 1000000)} Mbps';
    }
    if (value >= 1000) {
      return '${_short(value / 1000)} kbps';
    }
    return '${value.toStringAsFixed(0)} bps';
  }

  /// 整数值不带小数点，例如 `4` / `4.5`。
  static String _short(num value) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.round().toString();
    }
    return asDouble.toStringAsFixed(1);
  }

  Widget _row(BuildContext context, String label, String value) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: style)),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}
