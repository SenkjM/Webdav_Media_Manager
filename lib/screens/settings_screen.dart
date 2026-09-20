import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cache_policy.dart';
import '../providers/app_state.dart';
import '../services/library_service.dart';
import '../services/notification_permission_service.dart';
import '../services/settings_service.dart';
import 'accounts_screen.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _customDaysController;
  late final TextEditingController _customHoursController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _customDaysController = TextEditingController();
    _customHoursController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationPermissionService>().refresh();
      _syncCustomFieldsFromSettings();
    });
  }

  void _syncCustomFieldsFromSettings() {
    final settings = context.read<SettingsService>();
    final total = settings.customRetentionHours;
    final days = total ~/ 24;
    final hours = total % 24;
    _customDaysController.text = '$days';
    _customHoursController.text = '$hours';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已清理 $n 个音频缓存文件（播放中/下载中已保留）。'
          '音乐库元数据与封面缩略图仍保留（$libCount 首）。',
        ),
      ),
    );
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    if (perms.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知权限已开启，播放时会显示媒体通知')),
      );
      return;
    }
    if (perms.isPermanentlyDenied) {
      final opened = await perms.openSystemSettings();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? '请在系统设置中允许通知后返回应用'
                : '无法打开系统设置，请手动允许通知权限',
          ),
        ),
      );
      return;
    }
    final granted = await perms.request();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted ? '已授予通知权限' : '未授予通知权限，媒体通知可能无法显示',
        ),
      ),
    );
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
      return '已允许 — 播放/暂停时显示系统媒体通知';
    }
    if (perms.isPermanentlyDenied) {
      return '已拒绝 — 点此打开系统设置以开启通知';
    }
    return '未授权 — 点此请求通知权限（Android 13+）';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final library = context.watch<LibraryService>();
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
          Text('WebDAV 服务器', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: const Text('管理多服务器账号'),
            subtitle: const Text('添加 / 编辑 / 删除 WebDAV 服务器'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          Text('媒体通知', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '播放时通过 audio_service 前台服务显示系统媒体通知（通知栏 / 锁屏 / 媒体控制中心）：'
            '标题、艺术家与播放/暂停。\n'
            '请确保本应用的「通知」已开启；若曾拒绝，可点下方打开系统通知设置。'
            'Android 13+ 首次播放时也会请求 POST_NOTIFICATIONS。',
            style: Theme.of(context).textTheme.bodySmall,
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
          if (!notif.isGranted)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _onNotificationTap(context, notif),
                icon: const Icon(Icons.notification_add_outlined),
                label: Text(
                  notif.isPermanentlyDenied ? '打开系统设置' : '请求通知权限',
                ),
              ),
            ),
          const Divider(height: 40),
          Text('缓存清理', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '播放仅使用本地音频缓存。可选 1 天 / 1 周 / 自定义时长自动清理，或「永不」关闭自动清理；'
            '正在播放或正在下载的文件不会被删除。手动清空仍可用。'
            '音乐库标签与 100×100 封面缩略图不受缓存清理影响（当前库内 ${library.count} 首）。',
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
              '自定义保留时长（到期自动删除；至少 1 小时）',
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
              '已关闭自动清理。仍可通过下方按钮手动清空缓存'
              '（正在播放/下载的文件会保留）。',
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
            '说明：本应用永不从 WebDAV 流式播放。点按曲目会先下载到本地，'
            '就绪后再用本地文件播放。下载完成后读取标签并写入本地音乐库。'
            '凭证保存在 flutter_secure_storage。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
