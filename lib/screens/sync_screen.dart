import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/platform_export_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/marquee_text.dart';
import 'home_shell.dart';

/// Unified「同步」screen.
///
/// Merges what used to be three separate entries — 歌单同步 / 歌曲库同步 /
/// WebDAV 备份 — into one page with two directions plus local import/export.
///
/// Credential handling follows the same rule everywhere: the WebDAV **地址与
/// 用户名以明文**保存在云端 `credentials.json`，**只加密密码**。If a sync or
/// import cannot decrypt a password (no matching key) the account is still
/// restored and the password is left empty for the user to fill in.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _passphrase = TextEditingController();
  final _base64Controller = TextEditingController();

  bool _doCredentials = true;
  bool _doLibrary = true;
  bool _doPlaylists = true;
  bool _doBackup = true;
  bool _restoreBackup = false;

  bool _running = false;

  @override
  void dispose() {
    _passphrase.dispose();
    _base64Controller.dispose();
    super.dispose();
  }

  Future<String?> _askPassphrase({
    required String title,
    String? hint,
    bool allowEmpty = true,
  }) async {
    final controller = TextEditingController(text: allowEmpty ? '' : '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '口令',
                helperText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _runCloud({
    required bool push,
  }) async {
    final pass = await _askPassphrase(
      title: push ? '同步到云端 · 加密口令' : '从云端同步 · 解密口令',
      hint: push
          ? '留空则凭证密码明文保存'
          : '凭证已加密时需输入同一口令；无法提供时密码将留空',
    );
    if (pass == null || !mounted) return;
    final sync = context.read<SyncService>();
    setState(() => _running = true);
    try {
      final outcome = push
          ? await sync.push(
              passphrase: pass,
              includeCredentials: _doCredentials,
              includeLibrary: _doLibrary,
              includePlaylists: _doPlaylists,
              includeBackup: _doBackup,
            )
          : await sync.pull(
              passphrase: pass,
              includeCredentials: _doCredentials,
              includeLibrary: _doLibrary,
              includePlaylists: _doPlaylists,
              restoreBackup: _restoreBackup,
            );
      if (!mounted) return;
      await context.read<AppState>().library.refresh();
      if (!mounted) return;
      _showOutcome(outcome);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步失败：$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showOutcome(SyncOutcome outcome) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.message),
        duration: const Duration(seconds: 8),
        backgroundColor: outcome.ok ? null : AppColors.error,
      ),
    );
    if (outcome.warnings.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.elevated,
          title: const Text('同步完成，但有需要处理的项'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in outcome.warnings) Text('• $w\n'),
                const SizedBox(height: 8),
                const Text(
                  '提示：缺少统一解密密钥时，WebDAV 地址与用户名仍会恢复，'
                  '只需在网络库/账号管理中为该服务器重新填写密码。',
                  style: TextStyle(color: AppColors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _exportLocal() async {
    final pass = await _askPassphrase(
      title: '导出到下载目录 · 加密口令',
      hint: '留空则导出未加密的备份文件',
    );
    if (pass == null || !mounted) return;
    setState(() => _running = true);
    try {
      final result = await context.read<SyncService>().exportToDownloads(
            passphrase: pass,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? '已导出到${result.location}：${result.fileName}'
                : '导出失败：${result.error}',
          ),
          backgroundColor: result.ok ? null : AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _importLocal() async {
    final picked = await const PlatformExportService().pickFile(
      mimeType: 'application/zip',
    );
    if (!mounted) return;
    if (!picked.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择文件失败：${picked.error}'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (picked.cancelled) return;
    await _importPicked(picked.path!, picked.fileName ?? '备份文件');
  }

  Future<void> _importBase64() async {
    final text = _base64Controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴备份内容（Base64）')),
      );
      return;
    }
    final pass = await _askPassphrase(
      title: '导入备份 · 解密口令',
      hint: '未加密的备份可留空',
    );
    if (pass == null || !mounted) return;
    setState(() => _running = true);
    try {
      final outcome = await context.read<SyncService>().importLocalBase64(
            base64Text: text,
            passphrase: pass,
          );
      if (!mounted) return;
      await context.read<AppState>().connectActiveAccount();
      if (!mounted) return;
      _showOutcome(outcome);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _importPicked(String path, String fileName) async {
    final pass = await _askPassphrase(
      title: '导入「$fileName」',
      hint: '加密备份需输入导出口令；未加密可留空',
    );
    if (pass == null || !mounted) return;
    setState(() => _running = true);
    try {
      final outcome = await context.read<SyncService>().importLocalFile(
            file: File(path),
            passphrase: pass,
          );
      if (!mounted) return;
      await context.read<AppState>().connectActiveAccount();
      if (!mounted) return;
      _showOutcome(outcome);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e'), backgroundColor: AppColors.error),
      );
    } finally {
      await PlatformExportService.discardPickedFile(path);
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _editSyncRoot(SettingsService settings) async {
    final controller = TextEditingController(text: settings.syncRemoteRoot);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('同步根目录'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: SettingsService.defaultSyncRemoteRoot,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null) await settings.setSyncRemoteRoot(value);
  }

  Future<void> _editEditRenamePattern(SettingsService settings) async {
    final controller =
        TextEditingController(text: settings.shareTagRenamePattern);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('分享重命名模板'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            const Text(
              '可用占位符：{artist} 作者、{title} 标题、{album} 专辑、'
              '{albumArtist} 专辑作者、{track} 音轨号、{year} 年份、'
              '{genre} 流派、{fileName} 原文件名',
              style: TextStyle(color: AppColors.mutedText, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null) await settings.setShareTagRenamePattern(value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final accounts = context.watch<AccountsService>();
    final sync = context.watch<SyncService>();
    final active = accounts.activeAccount;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('同步'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '同步说明',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '「同步」把原来的歌单同步、歌曲库同步与 WebDAV 备份合并为一次操作：\n'
            '• WebDAV 凭证（地址 / 用户名 / 密码）保存在云端 credentials.json\n'
            '• 歌曲库索引 + 封面缩略图\n'
            '• 歌单 M3U8\n'
            '• 站点备份 .wmpbak（可选口令加密）\n'
            '可选「从本地导入 / 导出」把同一份数据写到系统下载目录或从文件恢复。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const Divider(height: 32),
          Text(
            'WebDAV 凭证存储',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '凭证统一存放在 WebDAV 云端：地址与用户名为明文，只有密码会被加密'
            '（AES-256-GCM）。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('加密密码'),
            subtitle: Text(
              settings.syncEncryptPassword
                  ? '用同步口令加密密码（推荐）；口令不匹配时密码留空'
                  : '明文保存密码（等同旧版备份的信任级别）',
            ),
            value: settings.syncEncryptPassword,
            onChanged: (v) => settings.setSyncEncryptPassword(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同步根目录'),
            subtitle: Text(
              '${settings.syncRemoteRoot}\n'
              '当前服务器：${active == null ? '未选择' : active.name}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editSyncRoot(settings),
          ),
          if (sync.busy || _running) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sync.progressLabel ?? '处理中…',
                    style: const TextStyle(color: AppColors.mutedText),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 32),
          Text(
            '同步范围',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('WebDAV 凭证'),
            value: _doCredentials,
            onChanged: (v) => setState(() => _doCredentials = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('歌曲库与封面'),
            value: _doLibrary,
            onChanged: (v) => setState(() => _doLibrary = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('歌单'),
            value: _doPlaylists,
            onChanged: (v) => setState(() => _doPlaylists = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('站点备份（.wmpbak）'),
            subtitle: Text(
              _doBackup
                  ? '同时在 ${settings.backupRemotePath} 写入 latest 备份'
                  : '不写入完整备份',
            ),
            value: _doBackup,
            onChanged: (v) => setState(() => _doBackup = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('拉取时同时恢复站点备份'),
            subtitle: const Text('会按站点写回凭证、曲库、歌单与封面'),
            value: _restoreBackup,
            onChanged: (v) => setState(() => _restoreBackup = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _runCloud(push: true),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('同步到云端'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _runCloud(push: false),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('从云端同步'),
                ),
              ),
            ],
          ),
          if (accounts.accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '请先在「管理多服务器账号」中添加 WebDAV 服务器。',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          const Divider(height: 32),
          Text(
            '从本地导入 / 导出',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            '导出写入系统下载目录：下载/${SyncService.localExportSubdir}/。'
            '导入可选择系统文件管理器中任意 .wmpbak / .zip 备份。',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : _exportLocal,
            icon: const Icon(Icons.save_alt),
            label: const Text('导出到系统下载目录'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : _importLocal,
            icon: const Icon(Icons.folder_open),
            label: const Text('从本地文件导入…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _base64Controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '或粘贴备份内容（Base64）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : _importBase64,
            icon: const Icon(Icons.content_paste),
            label: const Text('从粘贴内容导入'),
          ),
          const Divider(height: 32),
          Text(
            '分享文件重命名',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.drive_file_rename_outline),
            title: const Text('分享时按标签重命名'),
            subtitle: const Text('默认开启；分享单个文件时可再修改文件名'),
            value: settings.shareTagRenameEnabled,
            onChanged: (v) => settings.setShareTagRenameEnabled(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('重命名模板'),
            subtitle: Text(settings.shareTagRenamePattern),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editEditRenamePattern(settings),
          ),
          if (active != null) _accountSummary(active),
        ],
      ),
    );
  }

  Widget _accountSummary(WebDavAccount account) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前站点',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          MarqueeText(webDavAccountLabel(account)),
          const SizedBox(height: 4),
          const Text(
            '站点备份恢复时只会写回该账号，不会把站点 A 的凭证合并到站点 B。',
            style: TextStyle(color: AppColors.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
