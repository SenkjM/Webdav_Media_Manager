import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cache_policy.dart';
import '../providers/app_state.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import 'accounts_screen.dart';
import 'home_shell.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final library = context.watch<LibraryService>();

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('WebDAV 服务器', style: Theme.of(context).textTheme.titleMedium),
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
          Text('缓存清理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '播放仅使用本地音频缓存。超过保留期的音频文件会自动删除；'
            '正在播放或正在下载的文件不会被删除。'
            '音乐库标签与 100×100 封面缩略图不受缓存清理影响（当前库内 ${library.count} 首）。',
          ),
          const SizedBox(height: 8),
          SegmentedButton<CacheRetention>(
            segments: [
              ButtonSegment(
                value: CacheRetention.oneDay,
                label: Text(CacheRetention.oneDay.labelZh),
              ),
              ButtonSegment(
                value: CacheRetention.oneWeek,
                label: Text(CacheRetention.oneWeek.labelZh),
              ),
            ],
            selected: {settings.retention},
            onSelectionChanged: (s) {
              context.read<AppState>().setRetention(s.first);
            },
          ),
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
