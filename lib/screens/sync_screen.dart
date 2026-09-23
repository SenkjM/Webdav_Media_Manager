import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sync_interval.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/platform_export_service.dart';
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
///   automatically on startup / account switch / the 定时同步 interval;
/// * the **music library** syncs incrementally with local changes and can be
///   pushed in full on demand;
/// * the **全部备份** writes credentials + library + playlists as one archive.
///
/// One 远端路径 栏 (网盘 + 路径) owns the destination of all four, so a user picks
/// it exactly once; see [SettingsService.syncRemoteRoot].
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

  /// 远端路径（总路径）输入框；提交后写入 [SettingsService.syncRemoteRoot]。
  final _rootController = TextEditingController();

  bool _running = false;
  List<String> _backupFiles = const [];
  String? _selectedBackupFile;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _rootController.text = settings.syncRemoteRoot;
    // The remembered unified decryption key, so background auto-scan and the
    // buttons below use the same one.
    _passphrase.text = settings.vaultPassphrase;
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _base64Controller.dispose();
    _rootController.dispose();
    super.dispose();
  }

  // --- Helpers ----------------------------------------------------------

  String get _pass => _passphrase.text;

  /// Runs one user-initiated action and reports its result.
  ///
  /// Everything goes through [AppSnack.showGlobal] instead of this screen's
  /// context: a 重建 of a large library can run for minutes and the user
  /// routinely backs out of 设置 while it finishes. Reporting via `context`, or
  /// gating on `mounted`, silently swallowed the outcome — the download queue
  /// posts globally for exactly the same reason.
  Future<void> _guard(Future<void> Function() body) async {
    if (mounted) setState(() => _running = true);
    try {
      await body();
    } catch (e) {
      AppSnack.showGlobal('操作失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showOutcome(SyncOutcome outcome) {
    AppSnack.showGlobal(outcome.message, error: !outcome.ok);
  }

  // --- Actions ----------------------------------------------------------

  /// Remembers the unified key, runs [action], then shows what happened — even
  /// if this screen is long gone by then.
  Future<void> _runSync(Future<SyncOutcome> Function() action) async {
    final settings = context.read<SettingsService>();
    await _guard(() async {
      await settings.setVaultPassphrase(_pass);
      _showOutcome(await action());
    });
  }

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
              helperText: '只保存在本机；留空则以明文存储。',
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
                        AppSnack.showGlobal('加密密钥已保存到本机');
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
    final app = context.read<AppState>();
    final chosen = await showDialog<({int perShard, bool withCovers})>(
      context: context,
      builder: (ctx) => _RebuildLibraryDialog(sync: sync),
    );
    if (chosen == null || !mounted) return;
    // Not gated on [mounted] any more: the rebuild keeps running (and now keeps
    // reporting) after the user leaves 设置.
    await _runSync(() async {
      final o = await sync.syncLibraryFull(
        tracksPerShard: chosen.perShard,
        withCovers: chosen.withCovers,
      );
      await app.library.refresh();
      return o;
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
      AppSnack.showGlobal('读取云端库失败：$e', error: true);
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
                  '有分片缺失，只能重建。',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
                const SizedBox(height: 4),
                for (final name in audit.missing.take(8))
                  Text('• 缺 $name', style: const TextStyle(fontSize: 12)),
              ],
              if (audit.orphans.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('孤儿文件：清单没引用，可删除。', style: TextStyle(fontSize: 12)),
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
        final n = await sync.tidyLibraryOrphans(audit);
        AppSnack.showGlobal('已删除 $n 个孤儿文件');
      });
    } else if (action == 'rebuild') {
      await _rebuild();
    }
  }

  Future<void> _syncAll() {
    final sync = context.read<SyncService>();
    final app = context.read<AppState>();
    return _runSync(() async {
      final credentials = await sync.pushCredentials(passphrase: _pass);
      if (!credentials.ok) return credentials;
      final playlists = await sync.syncPlaylistsNow();
      final library = await sync.syncLibraryIncremental();
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
      await app.library.refresh();
      return merged;
    });
  }

  Future<void> _backup() async {
    final sync = context.read<SyncService>();
    var ok = false;
    await _runSync(() async {
      final outcome = await sync.backupTo(passphrase: _pass);
      ok = outcome.ok;
      return outcome;
    });
    if (ok && mounted) await _loadBackupList();
  }

  Future<void> _loadBackupList() async {
    final sync = context.read<SyncService>();
    try {
      final files = await sync.listBackups();
      if (!mounted) return;
      setState(() {
        _backupFiles = files;
        _selectedBackupFile = files.isEmpty ? null : files.first;
      });
    } catch (e) {
      AppSnack.showGlobal('读取备份列表失败：$e', error: true);
    }
  }

  Future<void> _restore() async {
    final sync = context.read<SyncService>();
    final app = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text('确认恢复'),
        content: const Text('将用备份覆盖本机凭证、音乐库与歌单，不可撤销。'),
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
    await _runSync(() async {
      final outcome = await sync.restoreFrom(
        passphrase: _pass,
        fileName: _selectedBackupFile,
      );
      await app.registerAllAccounts();
      await app.library.refresh();
      await app.playlists.refresh();
      return outcome;
    });
  }

  Future<void> _exportLocal({bool readableJson = false}) async {
    final settings = context.read<SettingsService>();
    final sync = context.read<SyncService>();
    await _guard(() async {
      await settings.setVaultPassphrase(_pass);
      final result = await sync.exportToDownloads(
        passphrase: _pass,
        readableJson: readableJson,
      );
      AppSnack.showGlobal(
        result.ok
            ? '已导出到${result.location}：${result.fileName}'
            : '导出失败：${result.error}',
        error: !result.ok,
      );
    });
  }

  Future<void> _importLocal() async {
    final picked = await const PlatformExportService().pickFile(
      mimeType: 'application/zip',
    );
    if (!mounted) return;
    if (!picked.ok) {
      AppSnack.showGlobal('选择文件失败：${picked.error}', error: true);
      return;
    }
    if (picked.cancelled) return;
    final path = picked.path!;
    final sync = context.read<SyncService>();
    final app = context.read<AppState>();
    await _runSync(() async {
      try {
        final outcome = await sync.importLocalFile(
          file: File(path),
          passphrase: _pass,
        );
        await app.registerAllAccounts();
        return outcome;
      } finally {
        await PlatformExportService.discardPickedFile(path);
      }
    });
  }

  Future<void> _importBase64() async {
    final text = _base64Controller.text.trim();
    if (text.isEmpty) {
      AppSnack.showGlobal('请先粘贴备份内容（Base64）');
      return;
    }
    final sync = context.read<SyncService>();
    final app = context.read<AppState>();
    await _runSync(() async {
      final outcome = await sync.importLocalBase64(
        base64Text: text,
        passphrase: _pass,
      );
      await app.registerAllAccounts();
      return outcome;
    });
  }

  // --- 远端路径（唯一目的地） ---------------------------------------------

  /// Applies the 网盘 + 路径 the user typed.
  ///
  /// Writing the setting is all that is needed: `AppState` notices the change
  /// and re-points playlist sync, and every other feature reads the derived
  /// paths ([SettingsService.credentialsRemotePath] / `playlistRemotePath` /
  /// `libraryRemotePath` / `backupRemotePath`) at call time.
  Future<void> _applyRemoteRoot() async {
    final settings = context.read<SettingsService>();
    await settings.setSyncRemoteRoot(_rootController.text);
    if (!mounted) return;
    // Show the normalised value (the setter adds the leading/trailing slash).
    setState(() => _rootController.text = settings.syncRemoteRoot);
    AppSnack.showGlobal('远端路径已更新：${settings.syncRemoteRoot}');
  }

  /// One row listing the four derived cloud locations, so the effect of the
  /// 路径 field above is never a guess.
  Widget _derivedPaths(SettingsService settings) {
    final rows = <(String, String)>[
      ('WebDAV 凭证', settings.credentialsRemotePath),
      ('歌单', settings.playlistRemotePath),
      ('音乐库', settings.libraryRemotePath),
      ('全部备份', settings.backupRemotePath),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, path) in rows)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$label：$path',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedText,
              ),
            ),
          ),
      ],
    );
  }

  // --- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final accounts = context.watch<AccountsService>();
    final sync = context.watch<SyncService>();

    // Non-listening handle used by the action closures below: they must keep
    // working after this screen is gone.
    final app = context.read<AppState>();
    // The 网盘 shown in the 远端路径 dropdown: the pinned one, else the active
    // account. A stale id (account deleted) is not allowed to assert.
    var rootAccountId = settings.syncAccountId;
    if (rootAccountId == null ||
        !accounts.accounts.any((a) => a.id == rootAccountId)) {
      rootAccountId = accounts.activeAccount?.id;
    }

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('同步与备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '凭证、歌单与音乐库共用一条远端路径：在下面选网盘、填路径即可。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const Divider(height: 28),

          // 一键同步放在最上面：这是最常用的动作。
          FilledButton.icon(
            onPressed: _running || accounts.accounts.isEmpty ? null : _syncAll,
            icon: const Icon(Icons.sync),
            label: const Text('全部同步'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.schedule, size: 20),
            title: const Text('定时同步', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              settings.syncInterval == SyncInterval.off
                  ? '已关闭，仅手动同步'
                  : '${settings.syncInterval.labelZh} 自动同步',
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

          // 远端路径：凭证 / 歌单 / 音乐库 / 备份 共用的唯一目的地。
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.cloud_outlined, size: 20),
            title: const Text('远端路径', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '凭证、歌单、音乐库与备份都放在这条路径下面',
              style: TextStyle(fontSize: 11),
            ),
          ),
          if (accounts.accounts.isEmpty)
            const Text(
              '请先添加 WebDAV 服务器。',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            )
          else ...[
            DropdownButtonFormField<String>(
              key: ValueKey('sync-root-account-$rootAccountId'),
              initialValue: rootAccountId,
              decoration: const InputDecoration(
                labelText: '① 选择网盘',
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
              onChanged: _running
                  ? null
                  : (id) => settings.setSyncAccountId(id),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _rootController,
                    decoration: const InputDecoration(
                      labelText: '② 路径',
                      hintText: '/player/',
                      helperText: '例如填 /player，音乐库就在 /player/library/',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onEditingComplete: _applyRemoteRoot,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.tonal(
                    onPressed: _running ? null : _applyRemoteRoot,
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
            _derivedPaths(settings),
          ],

          const Divider(height: 28),

          _sectionTitle('WebDAV 凭证'),
          Text(
            '云端 ${settings.credentialsRemotePath}：地址与用户名明文，仅密码加密。',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          _keyField(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('加密密码'),
            subtitle: Text(
              settings.syncEncryptPassword ? '口令不匹配时密码留空' : '明文保存密码',
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
                      : () => _runSync(
                          () => sync.pushCredentials(passphrase: _pass),
                        ),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传凭证'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : () => _runSync(
                          () => sync.pullCredentials(passphrase: _pass),
                        ),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('下载凭证'),
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          _sectionTitle('歌单'),
          Text(
            '双向 M3U8 同步，改动即时上传：${settings.playlistRemotePath}',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running || accounts.accounts.isEmpty
                ? null
                : () => _runSync(sync.syncPlaylistsNow),
            icon: const Icon(Icons.playlist_play),
            label: const Text('立即同步歌单'),
          ),

          const Divider(height: 32),

          _sectionTitle('音乐库'),
          Text(
            '${settings.libraryRemotePath}index.json 清单 + lib/seg/del 分片；'
            '只传变化，删除在重建时落实。',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          if (sync.cloudFragmentCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '云端分片：${sync.cloudFragmentCount} 个'
                '（约 ${_fmtBytes(sync.cloudFragmentBytes)}）'
                '${sync.cloudFragmentCount >= settings.libraryRebuildHintFragments ? ' · 建议重建' : ''}',
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
                      : () => _runSync(() async {
                          final o = await sync.syncLibraryIncremental();
                          await app.library.refresh();
                          return o;
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
          Text(
            '把凭证 + 音乐库 + 歌单写成一个归档到 ${settings.backupRemotePath}。',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          if (accounts.accounts.isEmpty)
            const Text(
              '请先添加 WebDAV 服务器。',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            )
          else ...[
            FilledButton.icon(
              onPressed: _running ? null : _backup,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('开始备份'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _guard(_loadBackupList),
              icon: const Icon(Icons.refresh),
              label: const Text('读取该路径下的备份'),
            ),
            if (_backupFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('backup-file-${_selectedBackupFile ?? ''}'),
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
            '导出、导入同样使用上面那把密钥。',
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
            const Text('以本机为准重写全部分片，并落实删除。'),
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
              subtitle: const Text('每首歌独立存一份，不去重；关闭则云端不含封面'),
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
