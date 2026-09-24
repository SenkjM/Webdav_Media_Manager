import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_capabilities.dart';
import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/cloud_driver.dart';
import '../services/cloud_drivers/baidu_netdisk_driver.dart';
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
      appBar: AppBar(title: const Text('网盘账号')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editAccount(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const _BindingHint(),
          Expanded(
            child: accounts.accounts.isEmpty
                ? const Center(child: Text('尚未添加账号。点击右下角添加。'))
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
                          a.url.isEmpty ? '百度网盘' : a.url,
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
    final webDav = context.read<WebDavService>();
    if (CloudDriveService.isCloudType(a.providerType)) {
      // 云盘账号：分流缝会把 testConnection 转给 CloudDriveService。
      final ok = await webDav.testConnection(accountId: a.id);
      if (!context.mounted) return;
      if (ok) {
        AppSnack.show(context, '连接成功');
      } else {
        await showWebDavErrorDialog(context, webDav.lastError ?? '连接失败');
      }
      return;
    }
    final pass = await context.read<AccountsService>().passwordFor(a.id) ?? '';
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
    final remotePathCtrl = TextEditingController(text: existing?.remotePath ?? '/');
    final accounts = context.read<AccountsService>();
    final cloudDrive = context.read<CloudDriveService>();
    var providerType = existing?.providerType ?? 'webdav';
    final existingCfg = existing == null
        ? const <String, dynamic>{}
        : (await accounts.loadDriverConfig(existing.id) ?? const <String, dynamic>{});
    final refreshCtrl = TextEditingController(text: existingCfg['refresh_token'] as String? ?? '');
    final renewCtrl = TextEditingController(
      text: (existingCfg['api_url_address'] as String?)?.isNotEmpty == true
          ? existingCfg['api_url_address'] as String
          : BaiduClient.defaultRenewApi,
    );
    final clientIdCtrl = TextEditingController(text: existingCfg['client_id'] as String? ?? '');
    final clientSecretCtrl = TextEditingController(text: existingCfg['client_secret'] as String? ?? '');
    var localRefresh = existingCfg['local_refresh'] as bool? ?? false;
    var obscure = true;
    var obscureToken = true;
    var caps = AccountCaps.normalizeStored(existing?.capabilities ?? AccountCaps.all);

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
                      DropdownButtonFormField<String>(
                        initialValue: providerType,
                        decoration: const InputDecoration(
                          labelText: '类型',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'webdav', child: Text('WebDAV')),
                          DropdownMenuItem(
                              value: 'baidu_netdisk', child: Text('百度网盘')),
                        ],
                        // 已建账号不改类型：换类型等于换一套实现，删了重加。
                        onChanged: existing == null
                            ? (v) => setLocal(() {
                                  if (v != null) providerType = v;
                                })
                            : null,
                      ),
                      if (providerType == 'webdav') ...[
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
                          controller: remotePathCtrl,
                          decoration: const InputDecoration(
                            labelText: '远程路径',
                            helperText: '浏览根，默认 /（空置也是 /）',
                            border: OutlineInputBorder(),
                          ),
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
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('权限'),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final (label, bit) in const [
                              ('读取', AccountCaps.read),
                              ('写入', AccountCaps.write),
                              ('创建文件夹', AccountCaps.mkdir),
                              ('移动', AccountCaps.move),
                              ('复制', AccountCaps.copy),
                              ('删除', AccountCaps.delete),
                            ])
                              FilterChip(
                                label: Text(
                                  label,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: (caps & bit) != 0,
                                onSelected: (v) => setLocal(
                                  () => caps = v ? (caps | bit) : (caps & ~bit),
                                ),
                              ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: refreshCtrl,
                          obscureText: obscureToken,
                          decoration: InputDecoration(
                            labelText: 'refresh_token',
                            helperText:
                                '必填；获取方法见 OpenList 官方文档（baidu_netdisk 驱动页）',
                            helperMaxLines: 2,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureToken
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setLocal(() => obscureToken = !obscureToken),
                            ),
                          ),
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: remotePathCtrl,
                          decoration: const InputDecoration(
                            labelText: '远程路径',
                            helperText: '浏览根，/ = 整个网盘；空置也是 /',
                            border: OutlineInputBorder(),
                          ),
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: renewCtrl,
                          enabled: !localRefresh,
                          decoration: InputDecoration(
                            labelText: '在线续期地址',
                            helperText: localRefresh
                                ? '已切到本地刷新，该地址停用'
                                : '默认用 OpenList 维护的公共服务',
                            helperMaxLines: 2,
                            border: const OutlineInputBorder(),
                            filled: localRefresh,
                          ),
                          autocorrect: false,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('在本地处理令牌刷新',
                              style: TextStyle(fontSize: 14)),
                          subtitle: const Text(
                            '开启后用自建百度应用刷新（需填 Client ID / Secret），在线续期停用',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: localRefresh,
                          onChanged: (v) => setLocal(() => localRefresh = v),
                        ),
                        if (localRefresh) ...[
                          const SizedBox(height: 4),
                          TextField(
                            controller: clientIdCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Client ID',
                              border: OutlineInputBorder(),
                            ),
                            autocorrect: false,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: clientSecretCtrl,
                            obscureText: obscure,
                            decoration: InputDecoration(
                              labelText: 'Client Secret',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () =>
                                    setLocal(() => obscure = !obscure),
                              ),
                            ),
                            autocorrect: false,
                          ),
                        ],
                      ],
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
    Map<String, dynamic>? cloudConfig;
    while (true) {
      if (!await showForm() || !context.mounted) return;
      final name = nameCtrl.text.trim();
      final isCloud = CloudDriveService.isCloudType(providerType);
      if (name.isEmpty) {
        AppSnack.error(context, '请填写名称');
        continue;
      }
      if (!await _confirmDuplicateName(context, accounts, name, existing?.id)) {
        continue;
      }
      if (existing != null) {
        final renamed = name != existing.name.trim();
        final userChanged = !isCloud &&
            userCtrl.text.trim() != existing.username.trim();
        if ((renamed || userChanged) &&
            !await _confirmIdentityChange(context, existing, name, renamed)) {
          continue;
        }
      }
      if (isCloud) {
        // 百度网盘：能换到 access_token 才保存；失败原样抛给用户（99 §7.3.1）。
        if (refreshCtrl.text.trim().isEmpty) {
          AppSnack.error(context, '请填写 refresh_token');
          continue;
        }
        cloudConfig = {
          'refresh_token': refreshCtrl.text.trim(),
          'api_url_address': renewCtrl.text.trim(),
          'local_refresh': localRefresh,
          'client_id': clientIdCtrl.text.trim(),
          'client_secret': clientSecretCtrl.text.trim(),
        };
        try {
          await cloudDrive.verifyNewAccount(
            WebDavAccount(
              id: existing?.id ?? 'pending',
              name: name,
              url: '',
              username: '',
              providerType: providerType,
            ),
            cloudConfig,
          );
        } on CloudDriverException catch (e) {
          if (context.mounted) AppSnack.error(context, e.toString());
          continue; // 回到表单，已填内容都在
        }
      }
      break;
    }

    final remotePath = WebDavAccount.normalizeRemotePath(remotePathCtrl.text);
    if (cloudConfig != null) {
      if (existing == null) {
        final account = await accounts.addAccount(
          name: nameCtrl.text,
          url: '',
          username: '',
          password: '',
          providerType: providerType,
          remotePath: remotePath,
        );
        await accounts.saveDriverConfig(account.id, cloudConfig);
      } else {
        await accounts.updateAccount(
          id: existing.id,
          name: nameCtrl.text,
          url: '',
          username: '',
          providerType: providerType,
          remotePath: remotePath,
        );
        await accounts.saveDriverConfig(existing.id, cloudConfig);
      }
    } else if (existing == null) {
      await accounts.addAccount(
        name: nameCtrl.text,
        url: urlCtrl.text,
        username: userCtrl.text,
        password: passCtrl.text,
        remotePath: remotePath,
        capabilities: caps,
      );
    } else {
      await accounts.updateAccount(
        id: existing.id,
        name: nameCtrl.text,
        url: urlCtrl.text,
        username: userCtrl.text,
        password: passCtrl.text.isEmpty ? null : passCtrl.text,
        remotePath: remotePath,
        capabilities: caps,
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
