import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/account_capabilities.dart';
import '../models/account_sentinels.dart';
import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/cloud_driver_errors.dart';
import '../services/cloud_driver.dart';
import '../services/cloud_drivers/driver_registry.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../widgets/marquee_text.dart';
import '../widgets/webdav_error_dialog.dart';

/// 解析一个「开关字段」的当前值，供可见性 / 可编辑性联动使用。
///
/// 委派给 [CloudDriverSpec.switchValue]：渲染、联动、保存三条路径共用同一
/// 份取值规则（实时值 → spec 默认值 → false），避免任何一处写死 false 导致
/// 「默认开」的开关被误判为关。spec 为空（未知类型）时按 false 处理。
bool _switchValue(
  CloudDriverSpec? spec,
  String key,
  Map<String, bool> values,
) => spec?.switchValue(key, values) ?? false;

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsService>();
    final cloudDrive = context.watch<CloudDriveService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(l10n.accountsTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editAccount(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const _BindingHint(),
          Expanded(
            child: accounts.accounts.isEmpty
                ? Center(child: Text(l10n.noAccounts))
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
                        title: Text(webDavAccountLabel(a, l10n)),
                        // WebDAV 显示地址；云盘 / crypt 显示类型名
                        // （crypt = 源类型 + Crypt，见 CloudDriveService.typeLabelFor）。
                        subtitle: Text(
                          a.url.isNotEmpty ? a.url : cloudDrive.typeLabelFor(a),
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
                            PopupMenuItem(
                              value: 'use',
                              child: Text(l10n.setCurrent),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(l10n.edit),
                            ),
                            PopupMenuItem(
                              value: 'test',
                              child: Text(l10n.testConnection),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
    final app = context.read<AppState>();
    final webDav = context.read<WebDavService>();
    if (CloudDriveService.isCloudType(a.providerType)) {
      // 云盘账号：分流缝会把 testConnection 转给 CloudDriveService。
      final ok = await webDav.testConnection(accountId: a.id);
      if (!context.mounted) return;
      if (ok) {
        AppSnack.show(context, l10n.connectionSuccess);
      } else {
        await showWebDavErrorDialog(
          context,
          webDav.lastError == null
              ? l10n.connectionFailed
              : CloudDriverErrors.describe(webDav.lastError!, l10n),
        );
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
      AppSnack.show(context, l10n.connectionSuccess);
    } else {
      await showWebDavErrorDialog(
        context,
        webDav.lastError == null
            ? l10n.connectionFailed
            : CloudDriverErrors.describe(webDav.lastError!, l10n),
      );
    }
    // Restore active account connection.
    await app.registerAllAccounts();
  }

  Future<void> _delete(BuildContext context, WebDavAccount a) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteServer),
        content: Text(
          l10n.confirmDeleteServer(localizedAccountName(l10n, a.name)),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
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
    final remotePathCtrl = TextEditingController(
      text: existing?.remotePath ?? '/',
    );
    final accounts = context.read<AccountsService>();
    final l10n = AppLocalizations.of(context)!;
    final cloudDrive = context.read<CloudDriveService>();
    var providerType = existing?.providerType ?? 'webdav';
    final existingCfg = existing == null
        ? const <String, dynamic>{}
        : (await accounts.loadDriverConfig(existing.id) ??
              const <String, dynamic>{});
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
        } else if (item is CloudDriverAccountField) {
          fieldCtrls[item.key] = TextEditingController(
            text: existingCfg[item.key] as String? ?? '',
          );
        } else if (item is CloudDriverSelectField) {
          final stored = existingCfg[item.key] as String?;
          fieldCtrls[item.key] = TextEditingController(
            text: stored?.isNotEmpty == true ? stored : item.defaultValue,
          );
        }
      }
    }

    ensureSpecControls();
    var caps = AccountCaps.normalizeStored(
      existing?.capabilities ?? AccountCaps.all,
    );

    Map<String, dynamic>? cloudConfig;

    /// 弹窗内的错误展示位：SnackBar 会被 AlertDialog 盖住（真机只露出一条边），
    /// 所以表单校验失败一律显示在弹窗内部。
    String? dialogError;
    void Function(void Function())? dialogSet;
    void fail(String message) {
      dialogError = message;
      dialogSet?.call(() {});
      // 弹窗内联文字可能落在滚动区之外（或被键盘顶出可视区），所以同时推一条
      // 最顶层横幅——它挂在 Navigator 之上，对话框盖不住（99 §7.5 真机反馈）。
      AppSnack.show(context, message, error: true);
    }

    /// 点击「保存」后在弹窗内完成全部校验（99 §7.2.7）：名称 / 重名 / 身份
    /// 变更确认 / refresh_token / 云盘真连验证。返回 false 时**不关弹窗**，
    /// 已填内容都在，保存按钮恢复可点。
    Future<bool> validateAndPrepare() async {
      final name = nameCtrl.text.trim();
      final isCloud = CloudDriveService.isCloudType(providerType);
      if (name.isEmpty) {
        fail(l10n.accountFillName);
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
          fail(l10n.accountUnknownProvider(providerType));
          return false;
        }
        // 配置的键 / 必填项 / 默认值全部来自驱动声明（99 §7.2.10）。
        final cfg = <String, dynamic>{};
        for (final item in s.form) {
          if (item is CloudDriverField) {
            final text = fieldCtrls[item.key]?.text.trim() ?? '';
            if (item.required && text.isEmpty) {
              fail(l10n.accountFillField(item.label));
              return false;
            }
            cfg[item.key] = text;
          } else if (item is CloudDriverSelectField) {
            final v = fieldCtrls[item.key]?.text.trim() ?? '';
            if (item.required && v.isEmpty) {
              fail(l10n.accountSelectField(item.label));
              return false;
            }
            cfg[item.key] = v;
          } else if (item is CloudDriverAccountField) {
            final v = fieldCtrls[item.key]?.text.trim() ?? '';
            if (item.required && v.isEmpty) {
              fail(l10n.accountSelectField(item.label));
              return false;
            }
            cfg[item.key] = v;
            // 源账号名快照：源被删后重添同名账号可按名恢复（crypt 场景）。
            cfg['${item.key}_name'] = accounts.accountById(v)?.name ?? '';
          } else if (item is CloudDriverSwitchField) {
            // 与联动渲染同源：缺键时回落到 spec 默认值，保证「界面看到的
            // 状态」与「保存下来的值」永远一致。
            cfg[item.key] = _switchValue(s, item.key, switchValues);
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
        } catch (e) {
          // 不只 CloudDriverException：驱动/网络层抛出的任何异常都必须变成
          // 用户看得见的一句提示，绝不让保存按钮默默恢复（99 §7.3.1）。
          fail(CloudDriverErrors.describeException(e, l10n));
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
              dialogSet = setLocal;
              return AlertDialog(
                title: Text(
                  existing == null
                      ? l10n.accountAddServer
                      : l10n.accountEditServer,
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.accountName,
                          // The name is not a label: it is the library's binding key.
                          helperText: l10n.accountNameHint,
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
                        Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.accountNameTaken,
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: providerType,
                        decoration: InputDecoration(
                          labelText: l10n.accountType,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'webdav',
                            child: Text('WebDAV'),
                          ),
                          // 云盘类型来自驱动注册表（99 §7.2.10），顺序即注册顺序。
                          for (final s in kCloudDriverSpecs)
                            DropdownMenuItem(
                              value: s.typeId,
                              child: Text(s.displayName),
                            ),
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
                        decoration: InputDecoration(
                          labelText: l10n.accountRemotePath,
                          helperText: l10n.accountRemotePathHint,
                          border: OutlineInputBorder(),
                        ),
                        autocorrect: false,
                      ),
                      if (providerType == 'webdav') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: urlCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.accountServerUrl,
                            hintText: 'https://example.com/dav',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: userCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.accountUsername,
                            border: OutlineInputBorder(),
                          ),
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passCtrl,
                          obscureText: obscure,
                          decoration: InputDecoration(
                            labelText: existing == null
                                ? l10n.accountPassword
                                : l10n.accountPasswordKeep,
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
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(l10n.accountPermissions),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final (label, bit) in [
                              (l10n.permissionRead, AccountCaps.read),
                              (l10n.permissionWrite, AccountCaps.write),
                              (l10n.permissionCreateFolder, AccountCaps.mkdir),
                              (l10n.permissionMove, AccountCaps.move),
                              (l10n.permissionCopy, AccountCaps.copy),
                              (l10n.permissionDelete, AccountCaps.delete),
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
                        for (final item
                            in spec?.form ?? const <CloudDriverFormItem>[]) ...[
                          if (item is CloudDriverField)
                            Builder(
                              builder: (_) {
                                final f = item;
                                // 依赖开关的取值统一走 _switchValue：(a) 缺键时
                                // 回落到该开关自己的 defaultValue，而不是写死
                                // false——否则「默认开」的开关会把它联动的字段
                                // 误判为隐藏 / 停用；(b) 与保存路径同源。
                                //
                                // 双极性：enabledWhenSwitch = 开了才可用；
                                // disabledWhenSwitch = 开了就停用（百度本地刷新
                                // 开关打开后在线续期地址变灰，99 §7.3.1）。
                                // 两者同声明时视为无依赖（防误用）。
                                final dependsEnabled =
                                    f.enabledWhenSwitch != null &&
                                    f.disabledWhenSwitch == null;
                                final dependsDisabled =
                                    f.disabledWhenSwitch != null &&
                                    f.enabledWhenSwitch == null;
                                final enabled = !dependsDisabled
                                    ? (!dependsEnabled ||
                                          _switchValue(
                                            spec,
                                            f.enabledWhenSwitch!,
                                            switchValues,
                                          ))
                                    : !_switchValue(
                                        spec,
                                        f.disabledWhenSwitch!,
                                        switchValues,
                                      );
                                final visible =
                                    f.visibleWhenSwitch == null ||
                                    _switchValue(
                                      spec,
                                      f.visibleWhenSwitch!,
                                      switchValues,
                                    );
                                if (!visible) return const SizedBox.shrink();
                                final isOff =
                                    (dependsEnabled || dependsDisabled) &&
                                    !enabled;
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
                                              () => fieldObscure[f.key] =
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
                              title: Text(
                                item.label,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                item.subtitle,
                                style: const TextStyle(fontSize: 11),
                              ),
                              // 缺省必须回落到 spec 的 defaultValue，与
                              // ensureSpecControls 的初始化保持一致；写死
                              // false 会让「默认开」的开关显示与保存值相反。
                              value: _switchValue(spec, item.key, switchValues),
                              onChanged: (v) =>
                                  setLocal(() => switchValues[item.key] = v),
                            )
                          else if (item is CloudDriverSelectField)
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue:
                                  item.options.any(
                                    (o) =>
                                        o.$1 ==
                                        (fieldCtrls[item.key]?.text ?? ''),
                                  )
                                  ? fieldCtrls[item.key]!.text
                                  : (item.defaultValue.isNotEmpty
                                        ? item.defaultValue
                                        : null),
                              decoration: InputDecoration(
                                labelText: item.label,
                                helperText: item.hint,
                                helperMaxLines: 2,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                for (final (val, lab) in item.options)
                                  DropdownMenuItem(
                                    value: val,
                                    child: Text(lab),
                                  ),
                              ],
                              onChanged: (v) => setLocal(
                                () => fieldCtrls[item.key]?.text = v ?? '',
                              ),
                            )
                          else if (item is CloudDriverAccountField)
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue:
                                  accounts.accounts.any(
                                    (a) =>
                                        a.id ==
                                        (fieldCtrls[item.key]?.text ?? ''),
                                  )
                                  ? fieldCtrls[item.key]!.text
                                  : null,
                              decoration: InputDecoration(
                                labelText: item.label,
                                helperText: item.hint,
                                helperMaxLines: 2,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                for (final a in accounts.accounts)
                                  // 包装驱动不当别人的源（防套娃）；UI 只问
                                  // spec 的 isWrapper，不认识具体类型。
                                  if (cloudDriverSpec(a.providerType)
                                          ?.isWrapper !=
                                      true)
                                    DropdownMenuItem(
                                      value: a.id,
                                      child: Text(a.name),
                                    ),
                              ],
                              onChanged: (v) => setLocal(
                                () => fieldCtrls[item.key]?.text = v ?? '',
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ],
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            dialogError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(ctx, false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setLocal(() {
                              saving = true;
                              dialogError = null;
                            });
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
                        : Text(l10n.accountSave),
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
          AppSnack.show(context, l10n.accountAdded(nameCtrl.text.trim()));
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
    final l10n = AppLocalizations.of(context)!;
    final clash = accounts.accountNamed(name, exceptId: exceptId);
    if (clash == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(l10n.accountDuplicateTitle),
        content: Text(l10n.accountDuplicateContent(clash.name, clash.url)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.accountChangeName),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.accountKeepName),
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
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(
          renamed ? l10n.accountRenameTitle : l10n.accountUsernameChangedTitle,
        ),
        content: Text(
          renamed
              ? l10n.accountRenameContent(existing.name)
              : l10n.accountUsernameChangedContent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.accountConfirmChange),
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
      child: Text(
        AppLocalizations.of(context)!.accountBindingHint,
        style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
      ),
    );
  }
}
