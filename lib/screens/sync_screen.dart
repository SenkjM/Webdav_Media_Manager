import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sync_interval.dart';
import '../models/webdav_account.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/platform_export_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../services/library_sync_store.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import '../widgets/marquee_text.dart';

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
  /// Sentinel for the「自定义…」entry of the rebuild-hint dropdown.
  static const int _customThreshold = -1;

  static int _thresholdChoice(int current) =>
      SettingsService.rebuildHintPresets.contains(current)
      ? current
      : _customThreshold;

  /// Ask for an exact fragment count (the presets are only conveniences).
  Future<int?> _askCustomThreshold(int current) async {
    final ctrl = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('重建提示阈值'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '云端分片数',
            helperText: '达到这个数量时提示重建（2–500）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return value;
  }

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
    final settings = context.read<SettingsService>();
    _backupDirController.text = settings.backupRemotePath;
    // The remembered unified decryption key, so background auto-scan and the
    // buttons below use the same one.
    _passphrase.text = settings.vaultPassphrase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        // Restore the remembered backup destination, else fall back to the
        // active account.
        final accounts = context.read<AccountsService>();
        final remembered = context.read<SettingsService>().backupAccountId;
        WebDavAccount? match;
        for (final a in accounts.accounts) {
          if (a.id == remembered) match = a;
        }
        _backupDestination = match ?? accounts.activeAccount;
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
      AppSnack.error(context, '操作失败：$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showOutcome(SyncOutcome outcome) {
    AppSnack.error(context, outcome.message);
  }

  // --- Actions ----------------------------------------------------------

  /// Remember the key before an action uses it, so the background auto-scan and
  /// the next launch use the same one.
  Future<void> _rememberKey() =>
      context.read<SettingsService>().setVaultPassphrase(_pass);

  /// The user-chosen key that encrypts every password this app sends anywhere
  /// (cloud credential vault, backup archives, local exports).
  ///
  /// It is deliberately independent of the WebDAV accounts: deriving it from the
  /// destination account's own login password meant that changing that password
  /// — or choosing another destination disk — silently made previously synced
  /// passwords undecryptable.
  Widget _keyField() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _passphrase,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '统一加密密钥（由你指定）',
              helperText: '只保存在本机，和网盘密码无关；留空 = 密码明文存储。',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
            onEditingComplete: _rememberKey,
            onTapOutside: (_) => _rememberKey(),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _pass.trim().isEmpty
                      ? '当前：未设置（凭证与备份里的密码为明文）'
                      : '当前：已设置（长度 ${_pass.trim().length}）',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _running
                    ? null
                    : () async {
                        await _rememberKey();
                        if (!mounted) return;
                        AppSnack.show(context, '加密密钥已保存到本机');
                      },
                icon: const Icon(Icons.key_outlined, size: 18),
                label: const Text('保存密钥'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Rebuild the cloud library: choose tracks per shard, see the resulting size,
  /// then confirm. This is the only action that **materialises deletions**.
  Future<void> _rebuild() async {
    final sync = context.read<SyncService>();
    final chosen = await showDialog<({int perShard, bool withCovers})>(
      context: context,
      builder: (ctx) => _RebuildLibraryDialog(sync: sync),
    );
    if (chosen == null || !mounted) return;
    await _guard(() async {
      final o = await sync.syncLibraryFull(
        tracksPerShard: chosen.perShard,
        withCovers: chosen.withCovers,
      );
      if (!mounted) return;
      await context.read<AppState>().library.refresh();
      if (mounted) _showOutcome(o);
    });
  }

  /// Bytes in a human-readable unit (shared by the fragment hint + dialog).
  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Audit the cloud library (orphans / missing parts) and offer to clean up.
  Future<void> _tidy() async {
    final sync = context.read<SyncService>();
    LibraryAudit audit;
    try {
      audit = await sync.auditLibrary();
    } catch (e) {
      if (mounted) AppSnack.error(context, '读取云端库失败：$e');
      return;
    }
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('整理云端音乐库'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(audit.summary),
              const SizedBox(height: 8),
              if (audit.missing.isNotEmpty) ...[
                const Text(
                  '有分片缺失：这一段无法重放，只能重建云端库。',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
                const SizedBox(height: 4),
                for (final name in audit.missing.take(8))
                  Text('• 缺 $name', style: const TextStyle(fontSize: 12)),
              ],
              if (audit.orphans.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  '孤儿文件：清单没引用（上传中断或并发重建的输家），可安全删除。',
                  style: TextStyle(fontSize: 12),
                ),
                for (final name in audit.orphans.take(8))
                  Text('• $name', style: const TextStyle(fontSize: 12)),
              ],
              if (audit.healthy)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('一切一致，无需处理。', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          if (audit.orphans.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'orphans'),
              child: const Text('删除孤儿文件'),
            ),
          if (audit.missing.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'rebuild'),
              child: const Text('以本机为准重建'),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'orphans') {
      await _guard(() async {
        final n = await context.read<SyncService>().tidyLibraryOrphans(audit);
        if (mounted) AppSnack.show(context, '已删除 $n 个孤儿文件');
      });
    } else if (action == 'rebuild') {
      await _rebuild();
    }
  }

  Future<void> _syncAll() => _guard(() async {
    await _rememberKey();
    if (!mounted) return;
    final sync = context.read<SyncService>();
    final credentials = await sync.pushCredentials(passphrase: _pass);
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
    for (final s in [
      ...credentials.steps,
      ...playlists.steps,
      ...library.steps,
    ]) {
      merged.step(s);
    }
    for (final w in [
      ...credentials.warnings,
      ...playlists.warnings,
      ...library.warnings,
    ]) {
      merged.warn(w);
    }
    await context.read<AppState>().library.refresh();
    if (!mounted) return;
    _showOutcome(merged);
  });

  Future<void> _backup() async {
    final destination = _backupDestination;
    if (destination == null) {
      AppSnack.show(context, '请先选择要存放备份的网盘');
      return;
    }
    final dir = _backupDirController.text.trim();
    if (dir.isEmpty || dir == '/') {
      AppSnack.show(context, '请填写备份路径');
      return;
    }
    await _guard(() async {
      await _rememberKey();
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
      AppSnack.show(context, '读取备份列表失败：$e');
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
        content: const Text('将用备份覆盖本机的 WebDAV 凭证、音乐库与歌单。此操作不可撤销。'),
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
      await _rememberKey();
      final outcome = await context.read<SyncService>().restoreFrom(
        source: destination,
        remoteDir: _backupDirController.text.trim(),
        passphrase: _pass,
        fileName: _selectedBackupFile,
      );
      if (!mounted) return;
      final app = context.read<AppState>();
      await app.registerAllAccounts();
      await app.library.refresh();
      await app.playlists.refresh();
      if (!mounted) return;
      _showOutcome(outcome);
    });
  }

  Future<void> _exportLocal({bool readableJson = false}) => _guard(() async {
    await _rememberKey();
    final result = await context.read<SyncService>().exportToDownloads(
      passphrase: _pass,
      readableJson: readableJson,
    );
    if (!mounted) return;
    AppSnack.error(
      context,
      result.ok
          ? '已导出到${result.location}：${result.fileName}'
          : '导出失败：${result.error}',
    );
  });

  Future<void> _importLocal() async {
    final picked = await const PlatformExportService().pickFile(
      mimeType: 'application/zip',
    );
    if (!mounted) return;
    if (!picked.ok) {
      AppSnack.error(context, '选择文件失败：${picked.error}');
      return;
    }
    if (picked.cancelled) return;
    final path = picked.path!;
    await _guard(() async {
      await _rememberKey();
      try {
        final outcome = await context.read<SyncService>().importLocalFile(
          file: File(path),
          passphrase: _pass,
        );
        if (!mounted) return;
        await context.read<AppState>().registerAllAccounts();
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
      AppSnack.show(context, '请先粘贴备份内容（Base64）');
      return;
    }
    await _guard(() async {
      await _rememberKey();
      final outcome = await context.read<SyncService>().importLocalBase64(
        base64Text: text,
        passphrase: _pass,
      );
      if (!mounted) return;
      await context.read<AppState>().registerAllAccounts();
      if (!mounted) return;
      _showOutcome(outcome);
    });
  }

  // --- Destination picker ------------------------------------------------

  /// One row: which server this feature syncs to, plus its remote path.
  ///
  /// Each feature (credentials / playlists / library / backup) has its **own**
  /// destination, so nothing depends on which account the network library
  /// happens to be browsing.
  Widget _destinationTile({
    required SettingsService settings,
    required List<WebDavAccount> accounts,
    required String feature,
    required String label,
    required String? selectedId,
    required String path,
    required VoidCallback onEditPath,
  }) {
    WebDavAccount? selected;
    for (final a in accounts) {
      if (a.id == selectedId) selected = a;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cloud_outlined),
      title: Text('$label 目的地'),
      subtitle: Text(
        selected == null
            ? '跟随当前选中的网盘\n$path'
            : '${webDavAccountLabel(selected)}\n$path',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            backgroundColor: AppColors.elevated,
            title: Text('$label 同步到哪个网盘'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('跟随当前选中的网盘'),
              ),
              const Divider(height: 1, color: AppColors.divider),
              for (final a in accounts)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, a.id),
                  child: Text(webDavAccountLabel(a)),
                ),
            ],
          ),
        );
        if (picked == null) return;
        await settings.setSyncAccount(feature, picked.isEmpty ? null : picked);
        if (!mounted) return;
        onEditPath();
      },
    );
  }

  /// Prompts for a remote directory and persists it via [apply].
  Future<void> _editPath({
    required String title,
    required String current,
    required Future<void> Function(String) apply,
  }) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
    if (value == null) return;
    await apply(value);
    if (mounted) setState(() {});
  }

  // --- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final accounts = context.watch<AccountsService>();
    final sync = context.watch<SyncService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('同步与备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '这里只有三样东西：WebDAV 凭证、音乐库、歌单。\n'
            '凭证与歌单是真同步（双向 + 定期扫描），音乐库按本地变化增量同步、'
            '也可手动重写；「全部备份」把三者打成一个归档写到指定网盘路径。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const Divider(height: 28),

          // 一键同步放在最上面：这是最常用的动作。
          FilledButton.icon(
            onPressed: _running || accounts.accounts.isEmpty ? null : _syncAll,
            icon: const Icon(Icons.sync),
            label: const Text('全部同步（凭证 + 歌单 + 音乐库）'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.schedule, size: 20),
            title: const Text('定时同步', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              settings.syncInterval == SyncInterval.off
                  ? '已关闭：只在手动点「全部同步」时同步'
                  : '${settings.syncInterval.labelZh} 后台自动跑一遍：'
                        '凭证 + 歌单合并 + 音乐库增量（无变化不上传）',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<SyncInterval>(
              value: settings.syncInterval,
              underline: const SizedBox.shrink(),
              items: [
                for (final v in SyncInterval.values)
                  DropdownMenuItem(value: v, child: Text(v.labelZh)),
              ],
              onChanged: (v) {
                if (v != null) settings.setSyncInterval(v);
              },
            ),
          ),

          const Divider(height: 28),

          _sectionTitle('WebDAV 凭证'),
          const Text(
            '凭证统一存放在云端 credentials.json：地址与用户名为明文，'
            '只有密码会被加密（AES-256-GCM）。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          _destinationTile(
            settings: settings,
            accounts: accounts.accounts,
            feature: 'credentials',
            label: '凭证',
            selectedId: settings.credentialsAccountId,
            path: settings.syncRemoteRoot,
            onEditPath: () => _editPath(
              title: '凭证云端根目录',
              current: settings.syncRemoteRoot,
              apply: (v) => settings.setSyncRemoteRoot(v),
            ),
          ),
          _keyField(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('加密密码'),
            subtitle: Text(
              settings.syncEncryptPassword ? '口令不匹配时密码留空，其余字段照常恢复' : '明文保存密码',
            ),
            value: settings.syncEncryptPassword,
            onChanged: (v) => settings.setSyncEncryptPassword(v),
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
                          await _rememberKey();
                          if (!mounted) return;
                          final o = await context
                              .read<SyncService>()
                              .pushCredentials(passphrase: _pass);
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
                          await _rememberKey();
                          if (!mounted) return;
                          final o = await context
                              .read<SyncService>()
                              .pullCredentials(passphrase: _pass);
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
          _destinationTile(
            settings: settings,
            accounts: accounts.accounts,
            feature: 'playlists',
            label: '歌单',
            selectedId: settings.playlistsAccountId,
            path: settings.playlistRemotePath,
            onEditPath: () => _editPath(
              title: '歌单远程目录',
              current: settings.playlistRemotePath,
              apply: (v) async {
                await settings.setPlaylistRemotePath(v);
                context.read<PlaylistService>().configureSync(
                  remotePath: settings.playlistRemotePath,
                  enabled: settings.playlistSyncEnabled,
                  accountId:
                      settings.playlistsAccountId ?? accounts.activeAccountId,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running || accounts.accounts.isEmpty
                ? null
                : () => _guard(() async {
                    final o = await context
                        .read<SyncService>()
                        .syncPlaylistsNow();
                    if (mounted) _showOutcome(o);
                  }),
            icon: const Icon(Icons.playlist_play),
            label: const Text('立即同步歌单'),
          ),

          const Divider(height: 32),

          _sectionTitle('音乐库'),
          const Text(
            '云端一个库 = 一个 index.json 清单 + 若干二进制分片（.wmp）：\n'
            '• lib-*.wmp 基础分片，按每片歌曲数切片（不按专辑分组）\n'
            '• seg-*.wmp 增量分片，每下载一首只追加一个小片\n'
            '• del-*.wmp 墓碑分片，记录删除，**重建时才真正落实**\n'
            '只有本地有变化才会上传，没变化一个字节都不传；不会自动合并。'
            '曲目按「网盘名 + 路径」绑定，行内不含地址/用户名。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          _destinationTile(
            settings: settings,
            accounts: accounts.accounts,
            feature: 'library',
            label: '音乐库',
            selectedId: settings.libraryAccountId,
            path: settings.librarySyncRemotePath,
            onEditPath: () => _editPath(
              title: '音乐库同步根目录',
              current: settings.librarySyncRemotePath,
              apply: (v) => settings.setLibrarySyncRemotePath(v),
            ),
          ),
          if (sync.cloudFragmentCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '云端分片：${sync.cloudFragmentCount} 个'
                '（约 ${_fmtBytes(sync.cloudFragmentBytes)}）'
                '${sync.cloudFragmentCount >= settings.libraryRebuildHintFragments ? ' —— 建议重建一次' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      sync.cloudFragmentCount >=
                          settings.libraryRebuildHintFragments
                      ? AppColors.accent
                      : AppColors.mutedText,
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Three compact buttons: 同步 = 只传变化；重建 = 以本机为准整体重写并落实删除；
          // 整理 = 只读体检 + 清孤儿文件。
          Row(
            children: [
              Expanded(
                child: _compactButton(
                  icon: Icons.sync,
                  label: '同步',
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
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _compactButton(
                  icon: Icons.auto_awesome_motion,
                  label: '重建',
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : _rebuild,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _compactButton(
                  icon: Icons.cleaning_services_outlined,
                  label: '整理',
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : _tidy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.notifications_active_outlined, size: 20),
            title: const Text('重建提示阈值', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              sync.cloudFragmentCount > 0
                  ? '当前云端分片 ${sync.cloudFragmentCount} 个，'
                        '达到 ${settings.libraryRebuildHintFragments} 个时提示重建'
                  : '云端分片达到 ${settings.libraryRebuildHintFragments} 个时提示重建',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<int>(
              value: _thresholdChoice(settings.libraryRebuildHintFragments),
              underline: const SizedBox.shrink(),
              items: [
                for (final n in SettingsService.rebuildHintPresets)
                  DropdownMenuItem(value: n, child: Text('$n')),
                DropdownMenuItem(
                  value: _customThreshold,
                  child: Text(
                    SettingsService.rebuildHintPresets.contains(
                          settings.libraryRebuildHintFragments,
                        )
                        ? '自定义…'
                        : '自定义（${settings.libraryRebuildHintFragments}）',
                  ),
                ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                if (v == _customThreshold) {
                  final picked = await _askCustomThreshold(
                    settings.libraryRebuildHintFragments,
                  );
                  if (picked != null) {
                    await settings.setLibraryRebuildHintFragments(picked);
                  }
                  return;
                }
                await settings.setLibraryRebuildHintFragments(v);
              },
            ),
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
                  _backupDestination = accounts.accounts.firstWhere(
                    (a) => a.id == id,
                  );
                  _backupFiles = const [];
                  _selectedBackupFile = null;
                });
                // Remember the choice so the next visit starts from it.
                settings.setSyncAccount('backup', id);
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

          _sectionTitle('本地导入导出'),
          const Text(
            '导出 / 导入同样使用上面那把「统一加密密钥」。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _running ? null : _exportLocal,
            icon: const Icon(Icons.save_alt),
            label: const Text('导出到系统下载目录'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : () => _exportLocal(readableJson: true),
            icon: const Icon(Icons.data_object),
            label: const Text('导出可读 JSON（排障，不含封面）'),
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

  /// Small, icon+label button so three actions fit one row without crowding.
  Widget _compactButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 40),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: AppColors.accent),
    ),
  );

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// Rebuild dialog: pick tracks per shard (with a live size estimate) and whether
/// to embed covers, then confirm — rebuilding materialises every deletion.
class _RebuildLibraryDialog extends StatefulWidget {
  const _RebuildLibraryDialog({required this.sync});

  final SyncService sync;

  @override
  State<_RebuildLibraryDialog> createState() => _RebuildLibraryDialogState();
}

class _RebuildLibraryDialogState extends State<_RebuildLibraryDialog> {
  static const _presets = [200, 500, 1000, 2000];

  int _perShard = LibrarySyncStore.defaultTracksPerShard;
  bool _withCovers = true;
  RebuildEstimate? _estimate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final est = await widget.sync.estimateLibraryRebuild(
        tracksPerShard: _perShard,
        withCovers: _withCovers,
      );
      if (!mounted) return;
      setState(() {
        _estimate = est;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = _estimate;
    return AlertDialog(
      backgroundColor: AppColors.elevated,
      title: const Text('重建云端音乐库'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '会把本机曲库重新切成固定的二进制分片，并**真正落实删除**'
              '（墓碑行不再写入新库），随后清掉旧的增量/墓碑分片。',
            ),
            const SizedBox(height: 12),
            const Text('每个分片包含歌曲数'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final n in _presets)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _perShard == n,
                    onSelected: (_) {
                      setState(() => _perShard = n);
                      _refresh();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('把封面缩略图写进分片'),
              subtitle: const Text('每首歌各存一份（不去重）；关掉则云端不含封面'),
              value: _withCovers,
              onChanged: (v) {
                setState(() => _withCovers = v);
                _refresh();
              },
            ),
            const SizedBox(height: 4),
            Text(
              est == null ? (_loading ? '正在估算…' : '估算不可用') : est.label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            perShard: _perShard,
            withCovers: _withCovers,
          )),
          child: const Text('重建'),
        ),
      ],
    );
  }
}
