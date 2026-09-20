import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../widgets/webdav_error_dialog.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('WebDAV 服务器')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editAccount(context),
        child: const Icon(Icons.add),
      ),
      body: accounts.accounts.isEmpty
          ? const Center(child: Text('尚未添加服务器。点击右下角添加。'))
          : ListView.builder(
              itemCount: accounts.accounts.length,
              itemBuilder: (context, i) {
                final a = accounts.accounts[i];
                final active = accounts.activeAccountId == a.id;
                return ListTile(
                  leading: Icon(
                    active ? Icons.cloud_done : Icons.cloud_outlined,
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(a.name),
                  subtitle: Text('${a.url}\n${a.username}'),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'use':
                          await context.read<AppState>().switchAccount(a.id);
                          break;
                        case 'edit':
                          await _editAccount(context, existing: a);
                          break;
                        case 'test':
                          await _test(context, a);
                          break;
                        case 'delete':
                          await _delete(context, a);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'use', child: Text('设为当前')),
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'test', child: Text('测试连接')),
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                  onTap: () => context.read<AppState>().switchAccount(a.id),
                );
              },
            ),
    );
  }

  Future<void> _test(BuildContext context, WebDavAccount a) async {
    final app = context.read<AppState>();
    final pass = await context.read<AccountsService>().passwordFor(a.id) ?? '';
    final webDav = context.read<WebDavService>();
    webDav.configure(
      accountId: a.id,
      url: a.url,
      username: a.username,
      password: pass,
    );
    final ok = await webDav.testConnection();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接成功')),
      );
    } else {
      await showWebDavErrorDialog(
        context,
        webDav.lastError ?? '连接失败',
      );
    }
    // Restore active account connection.
    await app.connectActiveAccount();
  }

  Future<void> _delete(BuildContext context, WebDavAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除「${a.name}」？本地音乐库中该账号的元数据将保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AccountsService>().deleteAccount(a.id);
    await context.read<AppState>().connectActiveAccount();
  }

  Future<void> _editAccount(
    BuildContext context, {
    WebDavAccount? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController();
    var obscure = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? '添加服务器' : '编辑服务器'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
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
                      controller: userCtrl,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText:
                            existing == null ? '密码' : '密码（留空则不修改）',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setLocal(() => obscure = !obscure),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !context.mounted) return;
    final accounts = context.read<AccountsService>();
    if (existing == null) {
      await accounts.addAccount(
        name: nameCtrl.text,
        url: urlCtrl.text,
        username: userCtrl.text,
        password: passCtrl.text,
      );
    } else {
      await accounts.updateAccount(
        id: existing.id,
        name: nameCtrl.text,
        url: urlCtrl.text,
        username: userCtrl.text,
        password: passCtrl.text.isEmpty ? null : passCtrl.text,
      );
    }
    if (context.mounted) {
      await context.read<AppState>().connectActiveAccount();
    }
  }
}
