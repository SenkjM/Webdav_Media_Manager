import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cache_policy.dart';
import '../providers/app_state.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsService>();
    _url = TextEditingController(text: s.url);
    _user = TextEditingController(text: s.username);
    _pass = TextEditingController(text: s.password);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().applyWebDavSettings(
            url: _url.text,
            username: _user.text,
            password: _pass.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final app = context.read<AppState>();
    await app.applyWebDavSettings(
      url: _url.text,
      username: _user.text,
      password: _pass.text,
    );
    final webDav = context.read<WebDavService>();
    final ok = await webDav.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok
          ? '连接成功'
          : '连接失败：${webDav.lastError ?? "未知错误"}';
    });
  }

  Future<void> _clearCache() async {
    final n = await context.read<AppState>().manualClearCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清理 $n 个缓存文件（播放中/下载中已保留）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('WebDAV', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: '服务器 URL',
              hintText: 'https://example.com/dav',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _testing ? null : _test,
                child: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _testResult!,
              style: TextStyle(
                color: _testResult!.startsWith('连接成功')
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const Divider(height: 40),
          Text('缓存清理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '播放仅使用本地缓存文件。超过保留期的文件会自动删除；'
            '正在播放或正在下载的文件不会被删除。',
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
            onPressed: _clearCache,
            icon: const Icon(Icons.delete_outline),
            label: const Text('手动清空缓存'),
          ),
          const Divider(height: 40),
          Text(
            '说明：本应用永不从 WebDAV 流式播放。点按曲目会先下载到本地，'
            '就绪后再用本地文件播放。凭证保存在 flutter_secure_storage。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
