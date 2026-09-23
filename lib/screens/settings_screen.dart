import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cache_policy.dart';
import '../models/snack_duration.dart';
import '../providers/app_state.dart';
import '../services/download_queue_service.dart';
import '../services/library_service.dart';
import '../services/notification_permission_service.dart';
import '../services/settings_service.dart';
import 'accounts_screen.dart';
import '../theme/app_theme.dart';
import '../utils/cover_image.dart';
import '../utils/audio_extensions.dart';
import 'file_extensions_screen.dart';
import 'home_shell.dart';
import 'sync_screen.dart';
import 'video_settings_screen.dart';
import '../utils/app_snack.dart';

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
    AppSnack.show(
      context,
      '已清理 $n 个缓存文件（$libCount 首元数据保留）',
    );
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    if (perms.isGranted) {
      AppSnack.show(context, '通知权限已开启，播放时会显示媒体通知');
      return;
    }
    if (perms.isChannelBlocked || perms.isPermanentlyDenied) {
      final opened = await perms.openSystemSettings();
      if (!context.mounted) return;
      AppSnack.show(
        context,
        opened ? '请在系统设置中允许通知后返回应用' : '无法打开系统设置，请手动允许通知权限',
      );
      return;
    }
    final granted = await perms.request();
    if (!context.mounted) return;
    AppSnack.show(context, granted ? '已授予通知权限' : '未授予通知权限，媒体通知可能无法显示');
  }

  String _customRetentionSummary(SettingsService settings) {
    final total = settings.customRetentionHours;
    final days = total ~/ 24;
    final hours = total % 24;
    if (days > 0 && hours > 0) {
      return '当前：保留 $days 天 $hours 小时未访问的音频';
    }
    if (days > 0) {
      return '当前：保留 $days 天未访问的音频';
    }
    return '当前：保留 $hours 小时未访问的音频';
  }

  String _notificationSubtitle(NotificationPermissionService perms) {
    if (!perms.loaded) return '正在检查…';
    if (perms.isGranted) {
      return '已允许，播放/暂停时显示媒体通知';
    }
    if (perms.isChannelBlocked) {
      return '「音乐播放」通道被关闭，点此打开系统设置';
    }
    if (perms.isPermanentlyDenied) {
      return '已拒绝，点此打开系统设置';
    }
    if (perms.isChannelMissing) {
      return '「音乐播放」通道未创建，播放一次或点「刷新」重试';
    }
    return '未授权，点此请求通知权限';
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
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'WebDAV 服务器',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: const Text('管理多服务器账号'),
            subtitle: const Text('添加 / 编辑 / 删除 WebDAV 服务器'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
            },
          ),
          const Divider(height: 40),
          Text(
            '主页与导航',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: const Text('自定义主页'),
            subtitle: const Text('从其他界面返回时回到此主页'),
            trailing: DropdownButton<int>(
              value: settings.homeTab,
              items: const [
                DropdownMenuItem(value: 0, child: Text('音乐库')),
                DropdownMenuItem(value: 1, child: Text('歌单')),
                DropdownMenuItem(value: 2, child: Text('网络库')),
                DropdownMenuItem(value: 3, child: Text('下载队列')),
                DropdownMenuItem(value: 4, child: Text('设置')),
              ],
              onChanged: (v) {
                if (v != null) context.read<SettingsService>().setHomeTab(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.history),
            title: const Text('网络库记住上次路径'),
            subtitle: const Text('下次进入网络库时恢复上次浏览的目录'),
            value: settings.networkRememberLastPath,
            onChanged: (v) =>
                context.read<SettingsService>().setNetworkRememberLastPath(v),
          ),
          const Divider(height: 40),
          Text(
            '视频播放',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('视频播放设置'),
            subtitle: const Text('流式参数 / 手势 / 后台播放 / 画中画'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoSettingsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          Text(
            '文件类型',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: const Text('文件后缀管理'),
            subtitle: const Text('音乐 / 视频 / CUE 后缀与默认操作'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FileExtensionsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          Text(
            '媒体通知',
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
            title: const Text('播放通知权限'),
            subtitle: Text(_notificationSubtitle(notif)),
            value: notif.isGranted,
            onChanged: (_) => _onNotificationTap(context, notif),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq),
            title: const Text('「音乐播放」通道'),
            subtitle: Text(notif.channelStatusLabel),
            trailing: TextButton(
              onPressed: () => _refreshNotificationState(context, notif),
              child: const Text('刷新'),
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
            '封面缩略图尺寸',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            '新封面按此边长生成；已有封面需重新生成。',
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
                      labelText: '边长 (px)',
                      border: const OutlineInputBorder(),
                      helperText: '$minCoverThumbSize–$maxCoverThumbSize',
                    ),
                    onEditingComplete: _applyCustomCoverSize,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _applyCustomCoverSize,
                  child: const Text('应用'),
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
            '缓存清理',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            '仅清理音频缓存（播放/下载中的保留），标签与封面不受影响。',
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.elevated,
            child: ListTile(
              leading: const Icon(
                Icons.sd_storage_outlined,
                color: AppColors.accent,
              ),
              title: const Text('当前缓存占用'),
              subtitle: Text(
                _cacheSizeLoading
                    ? '计算中…'
                    : (_cacheBytes == null
                          ? '未知'
                          : formatByteSize(_cacheBytes!)),
              ),
              trailing: IconButton(
                tooltip: '刷新',
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
                label: Text(CacheRetention.oneDay.labelZh),
              ),
              ButtonSegment(
                value: CacheRetention.oneWeek,
                label: Text(CacheRetention.oneWeek.labelZh),
              ),
              ButtonSegment(
                value: CacheRetention.custom,
                label: Text(CacheRetention.custom.labelZh),
              ),
              ButtonSegment(
                value: CacheRetention.never,
                label: Text(CacheRetention.never.labelZh),
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
              '自定义保留时长（至少 1 小时）',
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
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '天',
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
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '小时',
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: _applyCustomRetention,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _applyCustomRetention,
                  child: const Text('应用'),
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
              '已关闭自动清理，可用下方按钮手动清空。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _clearCache(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('手动清空音频缓存'),
          ),

          const Divider(height: 40),
          Text(
            '提示与通知',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            '屏幕底部提示同时只显示一条，点「知道了」立即关闭。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: const Text('提示显示时长'),
            subtitle: Text(settings.snackMode.labelZh),
            trailing: DropdownButton<SnackDuration>(
              value: settings.snackMode,
              items: [
                for (final m in SnackDuration.values)
                  DropdownMenuItem(value: m, child: Text(m.labelZh)),
              ],
              onChanged: (v) {
                if (v != null) settings.setSnackMode(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.download_outlined),
            title: const Text('下载队列系统通知'),
            subtitle: const Text('下载进度与完成结果显示在通知栏'),
            value: settings.downloadNotificationsEnabled,
            onChanged: (v) async {
              await settings.setDownloadNotificationsEnabled(v);
              if (!context.mounted) return;
              await context.read<DownloadQueueService>().setNotifications(v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.notifications_active_outlined, size: 20),
            title: const Text('发送测试通知', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '立即发一条进度与一条完成通知，用来排查系统是否拦截',
              style: TextStyle(fontSize: 11),
            ),
            onTap: () async {
              final err = await context
                  .read<DownloadQueueService>()
                  .notificationService
                  .selfTest();
              if (!context.mounted) return;
              if (err == null) {
                AppSnack.show(context, '测试通知已发送（进度 + 完成各一条）');
              } else {
                AppSnack.error(context, '测试通知失败：$err');
              }
            },
          ),

          const Divider(height: 40),
          Text(
            '分享',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            '分享时按标签重命名文件名。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.drive_file_rename_outline),
            title: const Text('分享时按标签重命名'),
            subtitle: const Text('默认开启；分享单个文件时仍可再修改文件名'),
            value: settings.shareTagRenameEnabled,
            onChanged: (v) => settings.setShareTagRenameEnabled(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: const Text('重命名模板'),
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
            '同步与备份',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          // Same shape as 视频播放 / 文件类型 above: a row with a chevron, not a
          // button — this opens another screen, it does not run an action.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: const Text('同步与备份设置'),
            subtitle: Text(
              '凭证 / 歌单 / 音乐库 / 备份共用一条远端路径：\n'
              '${settings.syncRemoteRoot}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              );
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
        title: const Text('分享重命名模板'),
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
            const Text(
              '留空字段自动去掉多余分隔符，扩展名始终保留。',
              style: TextStyle(color: AppColors.mutedText, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null) await settings.setShareTagRenamePattern(value);
  }
}
