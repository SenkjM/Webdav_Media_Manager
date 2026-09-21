import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cache_policy.dart';
import '../providers/app_state.dart';
import '../services/backup_service.dart';
import '../services/library_sync_service.dart';
import '../services/accounts_service.dart';
import '../models/webdav_account.dart';
import '../widgets/marquee_text.dart';
import '../services/library_service.dart';
import '../services/notification_permission_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import 'accounts_screen.dart';
import '../theme/app_theme.dart';
import '../utils/cover_image.dart';
import '../utils/audio_extensions.dart';
import 'file_extensions_screen.dart';
import 'home_shell.dart';
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



  Future<String?> _askPassphrase(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    bool requireNonEmpty = false,
  }) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '加密口令（可留空则不加密，含明文密码）',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = c.text;
              if (requireNonEmpty && v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

    Future<void> _runBackup(BuildContext context, {bool fullMultiAccount = false}) async {
    final accounts = context.read<AccountsService>();
    WebDavAccount? selected = accounts.activeAccount;
    if (!fullMultiAccount) {
      if (accounts.accounts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先添加 WebDAV 账号')),
        );
        return;
      }
      selected = await showDialog<WebDavAccount>(
        context: context,
        builder: (ctx) {
          WebDavAccount? current = accounts.activeAccount ?? accounts.accounts.first;
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: const Text('选择要备份的 WebDAV 站点'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '默认按站点分别备份（账号凭证 + 该站曲库 + 相关歌单）。'
                    '备份目录：/WebDAVMusicPlayer/backup/<站点>/',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: current?.id,
                    items: [
                      for (final a in accounts.accounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: SizedBox(
                            width: 240,
                            child: MarqueeText(webDavAccountLabel(a)),
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      setLocal(() {
                        current = accounts.accounts.firstWhere((a) => a.id == id);
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, current),
                  child: const Text('下一步'),
                ),
              ],
            ),
          );
        },
      );
      if (selected == null || !context.mounted) return;
    }

    final pass = await _askPassphrase(
      context,
      title: fullMultiAccount ? '全部账号备份口令' : '站点备份加密口令',
      confirmLabel: '开始备份',
    );
    if (pass == null || !context.mounted) return;
    final backup = context.read<BackupService>();
    try {
      await backup.uploadBackup(
        passphrase: pass,
        account: selected,
        fullMultiAccount: fullMultiAccount,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(backup.lastMessage ?? '备份完成')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败：$e')),
      );
    }
  }

    Future<void> _runRestore(BuildContext context) async {
    final accounts = context.read<AccountsService>();
    final selected = await showDialog<WebDavAccount?>(
      context: context,
      builder: (ctx) {
        WebDavAccount? current = accounts.activeAccount ??
            (accounts.accounts.isEmpty ? null : accounts.accounts.first);
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('选择恢复来源站点'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '将从该站点的 per-account 备份目录下载 latest 并恢复到对应账号'
                  '（不会把站点 A 的凭证写入站点 B）。'
                  '若备份是旧版「全部账号」格式，恢复时会覆盖全部本地挂载。',
                ),
                const SizedBox(height: 12),
                if (accounts.accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: current?.id,
                    items: [
                      for (final a in accounts.accounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: SizedBox(
                            width: 240,
                            child: MarqueeText(webDavAccountLabel(a)),
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      setLocal(() {
                        current = accounts.accounts.firstWhere((a) => a.id == id);
                      });
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, current),
                child: const Text('继续'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null && accounts.accounts.isNotEmpty) return;
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text(
          selected == null
              ? '将从 WebDAV 下载备份。按站点备份仅恢复对应账号；全部账号备份会覆盖本机音乐库、歌单、设置与全部 WebDAV 账号。此操作不可撤销。'
              : '将从站点「${selected.name}」下载备份并恢复该站点的凭证、曲库与相关歌单。其他 WebDAV 站点不受影响（除非是旧版全量备份）。确定继续？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final pass = await _askPassphrase(
      context,
      title: '备份解密口令',
      confirmLabel: '开始恢复',
    );
    if (pass == null || !context.mounted) return;
    final backup = context.read<BackupService>();
    final app = context.read<AppState>();
    try {
      await backup.restoreFromWebDav(passphrase: pass, account: selected);
      await app.library.refresh();
      await app.playlists.refresh();
      await app.connectActiveAccount();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(backup.lastMessage ?? '恢复完成')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：$e')),
      );
    }
  }

  Future<void> _runLibrarySync(BuildContext context) async {
    final accounts = context.read<AccountsService>();
    if (accounts.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加并连接 WebDAV 账号')),
      );
      return;
    }
    final selected = await showDialog<WebDavAccount>(
      context: context,
      builder: (ctx) {
        WebDavAccount? current = accounts.activeAccount ?? accounts.accounts.first;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('同步歌曲库'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '双向同步所选站点的歌曲索引（JSON）、封面缩略图与歌单 M3U8。'
                  '不会上传音频缓存文件。身份键：accountId + remotePath。',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: current?.id,
                  items: [
                    for (final a in accounts.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: SizedBox(
                            width: 240,
                            child: MarqueeText(webDavAccountLabel(a)),
                          ),
                      ),
                  ],
                  onChanged: (id) {
                    setLocal(() {
                      current = accounts.accounts.firstWhere((a) => a.id == id);
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, current),
                child: const Text('开始同步'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    final sync = context.read<LibrarySyncService>();
    try {
      await sync.syncLibrary(account: selected);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sync.lastMessage ?? '同步完成')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步失败：${sync.lastError ?? e}')),
      );
    }
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
          Text('歌单同步', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '本地歌单保存在独立数据库 playlists.db，音频缓存清理不会删除。'
            '开启同步后，修改会上传为所选 WebDAV 账号下的 M3U8；启动/切换账号时拉取并按 updatedAt 最后写入胜出合并。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同步歌单到 WebDAV'),
            value: settings.playlistSyncEnabled,
            onChanged: (v) async {
              await settings.setPlaylistSyncEnabled(v);
              context.read<PlaylistService>().configureSync(
                    remotePath: settings.playlistRemotePath,
                    enabled: v,
                  );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('歌单远程目录'),
            subtitle: Text(settings.playlistRemotePath),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final c = TextEditingController(text: settings.playlistRemotePath);
              final path = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('歌单 WebDAV 路径'),
                  content: TextField(
                    controller: c,
                    decoration: const InputDecoration(
                      hintText: '/Playlists/',
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
              if (path != null && context.mounted) {
                await settings.setPlaylistRemotePath(path);
                context.read<PlaylistService>().configureSync(
                      remotePath: settings.playlistRemotePath,
                      enabled: settings.playlistSyncEnabled,
                    );
              }
            },
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清空本地歌单'),
                  content: const Text('仅清除本机歌单数据库，不会删除 WebDAV 上的 M3U8。确定？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<PlaylistService>().clearAllLocal();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空本地歌单')),
                );
              }
            },
            icon: const Icon(Icons.playlist_remove),
            label: const Text('清空本地歌单'),
          ),
          const Divider(height: 40),
                    Text('歌曲库同步', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '按所选 WebDAV 站点双向同步歌曲索引（library_index.json）、封面缩略图与歌单。'
            '不同步音频缓存。默认目录：${settings.librarySyncRemotePath}<accountId>/',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('歌曲库同步远程目录'),
            subtitle: Text(settings.librarySyncRemotePath),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final c = TextEditingController(text: settings.librarySyncRemotePath);
              final path = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('歌曲库同步路径'),
                  content: TextField(controller: c),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
              if (path != null && context.mounted) {
                await settings.setLibrarySyncRemotePath(path);
              }
            },
          ),
          FilledButton.tonalIcon(
            onPressed: () => _runLibrarySync(context),
            icon: const Icon(Icons.sync),
            label: const Text('同步歌曲库'),
          ),
          const Divider(height: 40),
          Text('WebDAV 备份（按站点）', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent)),
          const SizedBox(height: 4),
          Text(
            '默认按 WebDAV 站点分别备份：该站凭证 + 该站曲库曲目 + 相关歌单 + 封面缩略图 + 设置。\n'
            '远程路径：${settings.backupRemotePath}<accountId_站点名>/backup-<时间戳>.wmpbak（并写 latest）。\n'
            '恢复时写回对应账号，不会把站点 A 的密码合并进站点 B。\n'
            '可选「全部账号」备份仍可用，但非默认。强烈建议加密口令（AES-256-GCM）。不含音频缓存与下载队列。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('备份远程根目录'),
            subtitle: Text(settings.backupRemotePath),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final c = TextEditingController(text: settings.backupRemotePath);
              final path = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('备份 WebDAV 路径'),
                  content: TextField(controller: c),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
              if (path != null && context.mounted) {
                await settings.setBackupRemotePath(path);
              }
            },
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _runBackup(context),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('备份当前站点到 WebDAV'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _runBackup(context, fullMultiAccount: true),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('备份全部账号（可选）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _runRestore(context),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('从 WebDAV 恢复…'),
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
