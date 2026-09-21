import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cache_policy.dart';
import '../providers/app_state.dart';
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
      setState(() { _cacheBytes = bytes; _cacheSizeLoading = false; });
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
    if (perms.isChannelBlocked || perms.isPermanentlyDenied) {
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
    if (perms.isChannelBlocked) {
      return '通知权限已开启，但「音乐播放」通道被关闭 — 点此打开系统设置';
    }
    if (perms.isPermanentlyDenied) {
      return '已拒绝 — 点此打开系统设置以开启通知';
    }
    if (perms.isChannelMissing) {
      return '「音乐播放」通道未创建 — 播放一次或点「刷新」重试';
    }
    return '未授权 — 点此请求通知权限（Android 13+）';
  }

  /// Re-reads permission +「音乐播放」channel state from the system and
  /// reports what flutter_local_notifications currently sees.
  Future<void> _refreshNotificationState(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    await perms.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '通知权限：${perms.isGranted ? '已允许' : '未允许'}｜'
          '通道「音乐播放」：${perms.channelStatusLabel}',
        ),
      ),
    );
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
          Text('主页与导航', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
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
          Text('视频播放', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('视频播放设置'),
            subtitle: const Text('流式参数 / 手势 / 后台播放 / 画中画'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const VideoSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 40),
          Text('文件类型', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: const Text('文件后缀管理'),
            subtitle: const Text('音乐 / 视频 / CUE 后缀与默认操作'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FileExtensionsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 40),
          Text('媒体通知', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
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
          Text('封面缩略图尺寸', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '新下载/重新写入标签时按此边长生成正方形压缩封面。'
            '已有缩略图保持原尺寸，需重新下载/写入标签或「销毁」音乐库后再下载才会按新尺寸生成。',
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
                await context.read<AppState>().setCoverThumbSize(coverThumbSize);
              } else if (v == '300') {
                setState(() => _coverUiMode = null);
                await context.read<AppState>().setCoverThumbSize(coverThumbSizeLarge);
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
          Text('缓存清理', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '播放仅使用本地音频缓存。可选 1 天 / 1 周 / 自定义时长自动清理，或「永不」关闭自动清理；'
            '正在播放或正在下载的文件不会被删除。手动清空仍可用。'
            '音乐库标签与封面缩略图不受缓存清理影响（当前库内 ${library.count} 首）。'
            '销毁音乐库（音乐库页菜单）才会清除标签与封面。',
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.elevated,
            child: ListTile(
              leading: const Icon(Icons.sd_storage_outlined, color: AppColors.accent),
              title: const Text('当前缓存占用'),
              subtitle: Text(_cacheSizeLoading ? '计算中…' : (_cacheBytes == null ? '未知' : formatByteSize(_cacheBytes!))),
              trailing: IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _cacheSizeLoading ? null : _refreshCacheSize),
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
          Text('同步与备份', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '歌单同步、歌曲库同步与 WebDAV 备份已合并为「同步」。\n'
            'WebDAV 凭证统一存放在云端（地址与用户名明文，仅密码可选加密）；'
            '同步与导入/导出都在同一页面完成。\n'
            '远程根目录：${settings.syncRemoteRoot}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              );
            },
            icon: const Icon(Icons.sync),
            label: const Text('打开同步'),
          ),
          const SizedBox(height: 8),
          Text(
            '分享重命名：${settings.shareTagRenameEnabled ? '开启' : '关闭'}'
            '（模板 ${settings.shareTagRenamePattern}），可在「同步」页调整。',
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const Divider(height: 40),
          Text(
            '说明：音乐不流式播放——点按曲目会先下载到本地，就绪后再用本地文件'
            '播放，下载完成后读取标签并写入本地音乐库。视频则通过 media_kit '
            '直接从 WebDAV 流式播放。凭证保存在 flutter_secure_storage。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
