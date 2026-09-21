import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../widgets/marquee_text.dart';
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
      body: Column(
        children: [
          const _BindingHint(),
          Expanded(
            child: accounts.accounts.isEmpty
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
                        // 名称（用户名）：同一主机上多个挂载点一眼可分。
                        title: Text(webDavAccountLabel(a)),
                        subtitle: Text(
                          a.url,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'use':
                                await context.read<AppState>().switchAccount(
                                  a.id,
                                );
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
                            const PopupMenuItem(
                              value: 'use',
                              child: Text('设为当前'),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑'),
                            ),
                            const PopupMenuItem(
                              value: 'test',
                              child: Text('测试连接'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                        ),
                        onTap: () =>
                            context.read<AppState>().switchAccount(a.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _test(BuildContext context, WebDavAccount a) async {
    final app = context.read<AppState>();
    final pass = await context.read<AccountsService>().passwordFor(a.id) ?? '';
    final webDav = context.read<WebDavService>();
    // Refresh just this account's client; testing must not disturb which account
    // the network library is browsing.
    webDav.configure(
      accountId: a.id,
      url: a.url,
      username: a.username,
      password: pass,
      makeActive: false,
    );
    final ok = await webDav.testConnection(accountId: a.id);
    if (!context.mounted) return;
    if (ok) {
      AppSnack.show(context, '连接成功');
    } else {
      await showWebDavErrorDialog(context, webDav.lastError ?? '连接失败');
    }
    // Restore active account connection.
    await app.registerAllAccounts();
  }

  Future<void> _delete(BuildContext context, WebDavAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除「${a.name}」？其曲目会变成「未绑定网盘」，加回同名即可恢复。'),

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
    await context.read<AppState>().registerAllAccounts();
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
    final accounts = context.read<AccountsService>();

    /// Show the form; keeps the typed values so a rejected warning can re-open it.
    Future<bool> showForm() async {
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
                          // The name is not a label: it is the library's binding key.
                          helperText: '曲库按此名称绑定，必须唯一；改名等同换盘',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                      if (nameCtrl.text.trim().isNotEmpty &&
                          accounts.accountNamed(
                                nameCtrl.text,
                                exceptId: existing?.id,
                              ) !=
                              null)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            '该名称已被占用，建议换一个',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
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
                          labelText: existing == null ? '密码' : '密码（留空则不修改）',
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
      return saved == true;
    }

    // A name is the library's binding key, so it cannot be empty and two disks
    // must not share one: the same path on two mounts would then be the *same*
    // song and they would overwrite each other's cache and metadata.
    //
    // Every rejection re-opens the form with the typed values intact, so a
    // warning never costs the user their input.
    while (true) {
      if (!await showForm() || !context.mounted) return;
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        AppSnack.error(context, '请填写名称');
        continue;
      }
      if (!await _confirmDuplicateName(context, accounts, name, existing?.id)) {
        continue;
      }
      if (existing != null) {
        final renamed = name != existing.name.trim();
        final userChanged = userCtrl.text.trim() != existing.username.trim();
        if ((renamed || userChanged) &&
            !await _confirmIdentityChange(context, existing, name, renamed)) {
          continue;
        }
      }
      break;
    }

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
      await context.read<AppState>().registerAllAccounts();
    }
  }

  /// Warn when another disk already uses [name].
  ///
  /// Two mounts can legitimately share a URL and username (different passwords
  /// map to different trees), so the *name* is the only discriminator we have —
  /// which makes duplicates genuinely dangerous rather than cosmetic.
  Future<bool> _confirmDuplicateName(
    BuildContext context,
    AccountsService accounts,
    String name,
    String? exceptId,
  ) async {
    final clash = accounts.accountNamed(name, exceptId: exceptId);
    if (clash == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('名称已被占用'),
        content: Text(
          '已有同名网盘「${clash.name}」：\n${clash.url}\n\n'
          '同名会被当成同一来源。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('改个名字'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍然使用'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Warn that editing the name (or username) changes what the rows point at.
  Future<bool> _confirmIdentityChange(
    BuildContext context,
    WebDavAccount existing,
    String newName,
    bool renamed,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(renamed ? '改名等同于换盘' : '用户名已修改'),
        content: Text(
          renamed
              ? '「${existing.name}」的曲目将变为「未绑定网盘」，改回原名即可恢复。\n'
                    '仅改地址时请保持名称不变。'
              : '用户名不参与绑定；新用户名对应别的目录时原路径可能不存在。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// One-line reminder of what the 名称 actually does.
class _BindingHint extends StatelessWidget {
  const _BindingHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.elevated,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: const Text(
        '曲目按「名称 + 路径」绑定；改名等同于换盘。',
        style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
      ),
    );
  }
}
