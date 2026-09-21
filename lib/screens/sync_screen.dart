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

/// 同步 / 备份.
///
/// Three data kinds, three behaviours — no per-site isolation:
/// * **WebDAV 凭证** and **歌单** are true two-way syncs that also run
///   automatically on startup / account switch / every 30 minutes;
/// * the **music library** syncs incrementally with local changes and can be
///   pushed in full on demand;
/// * the **全部备份** writes credentials + library + playlists as one archive
///   to whichever server and path the user picks.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _passphrase = TextEditingController();
  final _base64Controller = TextEditingController();
  final _backupDirController = TextEditingController();

  WebDavAccount? _backupDestination;
  bool _running = false;
  List<String> _backupFiles = const [];
  String? _selectedBackupFile;

  @override
  void initState() {
    super.initState();
    _backupDirController.text = context.read<SettingsService>().backupRemotePath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _backupDestination = context.read<AccountsService>().activeAccount;
      });
    });
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _base64Controller.dispose();
    _backupDirController.dispose();
    super.dispose();
  }

  // --- Helpers ----------------------------------------------------------

  String get _pass => _passphrase.text;

  Future<void> _guard(Future<void> Function() body) async {
    setState(() => _running = true);
    try {
      await body();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e'), backgroundColor: AppColors.error),
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

  // --- Actions ----------------------------------------------------------

  Future<void> _syncAll() => _guard(() async {
        final sync = context.read<SyncService>();
        final credentials = await sync.pushCredentials();
        if (!mounted) return;
        if (!credentials.ok) {
          _showOutcome(credentials);
          return;
        }
        final playlists = await sync.syncPlaylistsNow();
        if (!mounted) return;
        final library = await sync.syncLibraryIncremental();
        if (!mounted) return;
        final merged = SyncOutcome(direction: 'sync')
          ..ok = playlists.ok && library.ok
          ..error = playlists.error ?? library.error;
        for (final s in [...credentials.steps, ...playlists.steps, ...library.steps]) {
          merged.step(s);
        }
        for (final w in [...credentials.warnings, ...playlists.warnings, ...library.warnings]) {
          merged.warn(w);
        }
        await context.read<AppState>().library.refresh();
        if (!mounted) return;
        _showOutcome(merged);
      });

  Future<void> _backup() async {
    final destination = _backupDestination;
    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要存放备份的网盘')),
      );
      return;
    }
    final dir = _backupDirController.text.trim();
    if (dir.isEmpty || dir == '/') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写备份路径')),
      );
      return;
    }
    await _guard(() async {
      await context.read<SettingsService>().setBackupRemotePath(dir);
      final outcome = await context.read<SyncService>().backupTo(
            destination: destination,
            remoteDir: dir,
            passphrase: _pass,
          );
      if (!mounted) return;
      _showOutcome(outcome);
      if (outcome.ok) await _loadBackupList();
    });
  }

  Future<void> _loadBackupList() async {
    final destination = _backupDestination;
    if (destination == null) return;
    try {
      final files = await context.read<SyncService>().listBackups(
            source: destination,
            remoteDir: _backupDirController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _backupFiles = files;
        _selectedBackupFile = files.isEmpty ? null : files.first;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取备份列表失败：$e')),
      );
    }
  }

  Future<void> _restore() async {
    final destination = _backupDestination;
    if (destination == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('确认恢复'),
        content: const Text(
          '将用备份覆盖本机的 WebDAV 凭证、音乐库与歌单。此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guard(() async {
      final outcome = await context.read<SyncService>().restoreFrom(
            source: destination,
            remoteDir: _backupDirController.text.trim(),
            passphrase: _pass,
            fileName: _selectedBackupFile,
          );
      if (!mounted) return;
      final app = context.read<AppState>();
      await app.connectActiveAccount();
      await app.library.refresh();
      await app.playlists.refresh();
      if (!mounted) return;
      _showOutcome(outcome);
    });
  }

  Future<void> _exportLocal() => _guard(() async {
        final result = await context.read<SyncService>().exportToDownloads(
              passphrase: _pass,
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
      });

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
    final path = picked.path!;
    await _guard(() async {
      try {
        final outcome = await context.read<SyncService>().importLocalFile(
              file: File(path),
              passphrase: _pass,
            );
        if (!mounted) return;
        await context.read<AppState>().connectActiveAccount();
        if (!mounted) return;
        _showOutcome(outcome);
      } finally {
        await PlatformExportService.discardPickedFile(path);
      }
    });
  }

  Future<void> _importBase64() async {
    final text = _base64Controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴备份内容（Base64）')),
      );
      return;
    }
    await _guard(() async {
      final outcome = await context.read<SyncService>().importLocalBase64(
            base64Text: text,
            passphrase: _pass,
          );
      if (!mounted) return;
      await context.read<AppState>().connectActiveAccount();
      if (!mounted) return;
      _showOutcome(outcome);
    });
  }

  // --- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final accounts = context.watch<AccountsService>();
    final sync = context.watch<SyncService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('同步与备份'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '这里只有三样东西：WebDAV 凭证、音乐库、歌单。\n'
            '凭证与歌单是真同步（双向 + 定期扫描），音乐库按本地变化增量同步、'
            '也可手动全量；「全部备份」把三者打成一个归档写到指定网盘路径。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const Divider(height: 28),

          _sectionTitle('WebDAV 凭证'),
          const Text(
            '凭证统一存放在云端 credentials.json：地址与用户名为明文，'
            '只有密码会被加密（AES-256-GCM）。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('加密密码'),
            subtitle: Text(
              settings.syncEncryptPassword
                  ? '口令不匹配时密码留空，其余字段照常恢复'
                  : '明文保存密码',
            ),
            value: settings.syncEncryptPassword,
            onChanged: (v) => settings.setSyncEncryptPassword(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('云端根目录'),
            subtitle: Text(settings.syncRemoteRoot),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editSyncRoot(settings),
          ),
          if (sync.lastAutoSyncAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '上次自动扫描：${_fmtTime(sync.lastAutoSyncAt!)}',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _guard(() async {
                            final o = await context
                                .read<SyncService>()
                                .pushCredentials();
                            if (mounted) _showOutcome(o);
                          }),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传凭证'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _guard(() async {
                            final o = await context
                                .read<SyncService>()
                                .pullCredentials();
                            if (mounted) _showOutcome(o);
                          }),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('下载凭证'),
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          _sectionTitle('歌单'),
          const Text(
            '双向 M3U8 同步，按 updatedAt 最后写入胜出。改动会立即上传，'
            '启动 / 切换账号 / 每 30 分钟自动拉取合并。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running || accounts.accounts.isEmpty
                ? null
                : () => _guard(() async {
                      final o =
                          await context.read<SyncService>().syncPlaylistsNow();
                      if (mounted) _showOutcome(o);
                    }),
            icon: const Icon(Icons.playlist_play),
            label: const Text('立即同步歌单'),
          ),

          const Divider(height: 32),

          _sectionTitle('音乐库'),
          const Text(
            '增量同步只补齐对方缺少的曲目（按 lastTagReadAt 判定新旧），不会删除；'
            '全量同步会把云端索引对齐到本机，包括你在本机删掉的曲目。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _guard(() async {
                            final o = await context
                                .read<SyncService>()
                                .syncLibraryIncremental();
                            if (!mounted) return;
                            await context.read<AppState>().library.refresh();
                            if (mounted) _showOutcome(o);
                          }),
                  icon: const Icon(Icons.sync),
                  label: const Text('增量同步'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _guard(() async {
                            final o =
                                await context.read<SyncService>().syncLibraryFull();
                            if (!mounted) return;
                            await context.read<AppState>().library.refresh();
                            if (mounted) _showOutcome(o);
                          }),
                  icon: const Icon(Icons.sync_alt),
                  label: const Text('全量同步'),
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          _sectionTitle('一键同步'),
          const Text(
            '凭证 + 歌单 + 音乐库增量，一次做完。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _running || accounts.accounts.isEmpty ? null : _syncAll,
            icon: const Icon(Icons.sync),
            label: const Text('全部同步'),
          ),

          const Divider(height: 32),

          _sectionTitle('全部备份'),
          const Text(
            '把 WebDAV 凭证 + 音乐库 + 歌单打包成一个归档，'
            '写到你自己挑选的网盘与路径（不区分站点）。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (accounts.accounts.isEmpty)
            const Text(
              '请先在「管理多服务器账号」中添加 WebDAV 服务器。',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _backupDestination?.id,
              decoration: const InputDecoration(
                labelText: '① 选择存放备份的网盘',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final a in accounts.accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: MarqueeText(webDavAccountLabel(a)),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _backupDestination =
                      accounts.accounts.firstWhere((a) => a.id == id);
                  _backupFiles = const [];
                  _selectedBackupFile = null;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _backupDirController,
              decoration: const InputDecoration(
                labelText: '② 备份路径',
                hintText: '/WebDAVMusicPlayer/backup/',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _running ? null : _backup,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('③ 开始备份'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _running || _backupDestination == null
                  ? null
                  : () => _guard(_loadBackupList),
              icon: const Icon(Icons.refresh),
              label: const Text('读取该路径下的备份'),
            ),
            if (_backupFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedBackupFile,
                decoration: const InputDecoration(
                  labelText: '要恢复的备份',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final f in _backupFiles)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() => _selectedBackupFile = v),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _running ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('从所选备份恢复'),
              ),
            ],
          ],

          const Divider(height: 32),

          _sectionTitle('口令与本地导入导出'),
          TextField(
            controller: _passphrase,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '同步 / 备份口令',
              helperText: '留空 = 不加密（密码明文写入归档）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
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

          if (sync.busy || _running) ...[
            const SizedBox(height: 20),
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
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.accent),
        ),
      );

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
