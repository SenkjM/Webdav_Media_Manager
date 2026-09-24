import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_capabilities.dart';
import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/cloud_driver.dart';
import '../services/cloud_drivers/driver_registry.dart';
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
    var obscure = true;
    // 云盘动态控件按驱动 spec 生成（99 §7.2.10）：控制器 / 开关值 / 明暗态
    // 三个映射，键都是驱动声明的字段 key；切换类型（仅新增时）重建。
    CloudDriverSpec? spec = cloudDriverSpec(providerType);
    var fieldCtrls = <String, TextEditingController>{};
    var switchValues = <String, bool>{};
    var fieldObscure = <String, bool>{};
    void ensureSpecControls() {
      final s = cloudDriverSpec(providerType);
      if (identical(s, spec) && fieldCtrls.isNotEmpty) return;
      spec = s;
      fieldCtrls = <String, TextEditingController>{};
      switchValues = <String, bool>{};
      fieldObscure = <String, bool>{};
      for (final item in s?.form ?? const <CloudDriverFormItem>[]) {
        if (item is CloudDriverField) {
          final stored = existingCfg[item.key] as String?;
          fieldCtrls[item.key] = TextEditingController(
            text: stored?.isNotEmpty == true ? stored : item.defaultValue,
          );
          fieldObscure[item.key] = item.obscure;
        } else if (item is CloudDriverSwitchField) {
          switchValues[item.key] =
              existingCfg[item.key] as bool? ?? item.defaultValue;
        }
      }
    }
    ensureSpecControls();
    var caps = AccountCaps.normalizeStored(existing?.capabilities ?? AccountCaps.all);

    Map<String, dynamic>? cloudConfig;

    /// 点击「保存」后在弹窗内完成全部校验（99 §7.2.7）：名称 / 重名 / 身份
    /// 变更确认 / refresh_token / 云盘真连验证。返回 false 时**不关弹窗**，
    /// 已填内容都在，保存按钮恢复可点。
    Future<bool> validateAndPrepare() async {
      final name = nameCtrl.text.trim();
      final isCloud = CloudDriveService.isCloudType(providerType);
      if (name.isEmpty) {
        AppSnack.error(context, '请填写名称');
        return false;
      }
      if (!await _confirmDuplicateName(context, accounts, name, existing?.id)) {
        return false;
      }
      if (existing != null) {
        final renamed = name != existing.name.trim();
        final userChanged =
            !isCloud && userCtrl.text.trim() != existing.username.trim();
        if ((renamed || userChanged) &&
            !await _confirmIdentityChange(context, existing, name, renamed)) {
          return false;
        }
      }
      if (isCloud) {
        final s = spec;
        if (s == null) {
          AppSnack.error(context, '未知云盘类型：$providerType');
          return false;
        }
        // 配置的键 / 必填项 / 默认值全部来自驱动声明（99 §7.2.10）。
        final cfg = <String, dynamic>{};
        for (final item in s.form) {
          if (item is CloudDriverField) {
            final text = fieldCtrls[item.key]?.text.trim() ?? '';
            if (item.required && text.isEmpty) {
              AppSnack.error(context, '请填写 ${item.label}');
              return false;
            }
            cfg[item.key] = text;
          } else if (item is CloudDriverSwitchField) {
            cfg[item.key] = switchValues[item.key] ?? false;
          }
        }
        // 云盘：能换到 access_token 才保存；失败原样抛给用户（99 §7.3.1）。
        cloudConfig = cfg;
        try {
          await cloudDrive.verifyNewAccount(
            WebDavAccount(
              id: existing?.id ?? 'pending',
              name: name,
              url: '',
              username: '',
              providerType: providerType,
            ),
            cloudConfig!,
          );
        } on CloudDriverException catch (e) {
          if (context.mounted) AppSnack.error(context, e.toString());
          return false;
        }
      }
      return true;
    }

    /// Show the form. 点击保存后按钮变圈等待，校验通过才关弹窗。
    Future<bool> showForm() async {
      var saving = false;
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
                        items: [
                          const DropdownMenuItem(
                              value: 'webdav', child: Text('WebDAV')),
                          // 云盘类型来自驱动注册表（99 §7.2.10），顺序即注册顺序。
                          for (final s in kCloudDriverSpecs)
                            DropdownMenuItem(
                                value: s.typeId, child: Text(s.displayName)),
                        ],
                        // 已建账号不改类型：换类型等于换一套实现，删了重加。
                        onChanged: existing == null
                            ? (v) => setLocal(() {
                                  if (v != null) providerType = v;
                                  ensureSpecControls();
                                })
                            : null,
                      ),
                      // 远程路径（浏览根）是通用字段：WebDAV 与云盘同语义，
                      // 都放在类型之后（99 §7.2.7 / §7.2.10）。
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
                        // 云盘动态区完全按驱动 spec 渲染（99 §7.2.10）：
                        // 表单不含任何具体盘的知识，新增盘零改动。
                        for (final item in spec?.form ??
                            const <CloudDriverFormItem>[]) ...[
                          if (item is CloudDriverField)
                            Builder(
                              builder: (_) {
                                final f = item;
                                final enabled = f.enabledWhenSwitch == null ||
                                    (switchValues[f.enabledWhenSwitch] ??
                                        false);
                                final visible = f.visibleWhenSwitch == null ||
                                    (switchValues[f.visibleWhenSwitch] ??
                                        false);
                                if (!visible) return const SizedBox.shrink();
                                final isOff =
                                    f.enabledWhenSwitch != null && !enabled;
                                return TextField(
                                  controller: fieldCtrls[f.key],
                                  obscureText: fieldObscure[f.key] ?? false,
                                  enabled: enabled,
                                  decoration: InputDecoration(
                                    labelText: f.label,
                                    helperText: isOff
                                        ? (f.disabledHint ?? f.hint)
                                        : f.hint,
                                    helperMaxLines: 2,
                                    border: const OutlineInputBorder(),
                                    filled: isOff,
                                    suffixIcon: f.obscure
                                        ? IconButton(
                                            icon: Icon(
                                              (fieldObscure[f.key] ?? false)
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                            ),
                                            onPressed: () => setLocal(
                                              () =>
                                                  fieldObscure[f.key] =
                                                      !(fieldObscure[f.key] ??
                                                          false),
                                            ),
                                          )
                                        : null,
                                  ),
                                  autocorrect: false,
                                );
                              },
                            )
                          else if (item is CloudDriverSwitchField)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.label,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(item.subtitle,
                                  style: const TextStyle(fontSize: 11)),
                              value: switchValues[item.key] ?? false,
                              onChanged: (v) =>
                                  setLocal(() => switchValues[item.key] = v),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setLocal(() => saving = true);
                            final ok = await validateAndPrepare();
                            if (!ok) {
                              setLocal(() => saving = false);
                              return;
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          },
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
      return saved == true;
    }

    if (!await showForm() || !context.mounted) return;

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
        await accounts.saveDriverConfig(account.id, cloudConfig!);
        // 云盘添加成功：提示后随表单一起关闭（99 §7.2.7）。
        if (context.mounted) {
          AppSnack.show(context, '成功添加（\${nameCtrl.text.trim()}）');
        }
      } else {
        await accounts.updateAccount(
          id: existing.id,
          name: nameCtrl.text,
          url: '',
          username: '',
          providerType: providerType,
          remotePath: remotePath,
        );
        await accounts.saveDriverConfig(existing.id, cloudConfig!);
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
