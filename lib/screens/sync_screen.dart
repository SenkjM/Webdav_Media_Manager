import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/sync_interval.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/platform_export_service.dart';
import '../services/settings_service.dart';
import '../services/library_sync_store.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import '../widgets/destroy_progress_dialog.dart';
import '../widgets/marquee_text.dart';

/// 同步 / 备份.
///
/// Three data kinds, three behaviours — no per-site isolation:
/// * **账号凭证** and **歌单** are true two-way syncs that also run
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
        title: Text(AppLocalizations.of(ctx)!.rebuildHintThreshold),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(ctx)!.cloudFragmentCountLabel,
            helperText: AppLocalizations.of(ctx)!.cloudFragmentCountHelper,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: Text(AppLocalizations.of(ctx)!.confirm),
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
      final l10n = AppLocalizations.of(context)!;
      AppSnack.showGlobal(
        l10n.operationFailed(SyncOutcome.describeError(e.toString(), l10n)),
        error: true,
      );
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
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.unifiedEncryptionKey,
              helperText: AppLocalizations.of(context)!
                  .unifiedEncryptionKeyHint,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
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
                      ? AppLocalizations.of(context)!.keyNotSetLong
                      : AppLocalizations.of(context)!
                            .keySetLong(_pass.trim().length),
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
                        AppSnack.showGlobal(
                          AppLocalizations.of(context)!.keySavedNotice,
                        );
                      },
                icon: const Icon(Icons.key_outlined, size: 18),
                label: Text(AppLocalizations.of(context)!.saveKey),
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

  /// 「从云端覆写音乐库」：本地索引被云端那份替换。
  Future<void> _overwriteLibraryFromCloud() async {
    final app = context.read<AppState>();
    final l10n = AppLocalizations.of(context)!;
    final ok = await _confirmDestructive(
      title: l10n.overwriteLibraryTitle,
      body: l10n.overwriteLibraryBody,
      note: l10n.overwriteLibraryNote,
      action: l10n.overwriteLibraryAction,
      phrase: l10n.overwriteLibraryPhrase,
    );
    if (ok != true || !mounted) return;
    await _guard(() async {
      final outcome = await app.overwriteLibraryFromCloud();
      if (!mounted) return;
      AppSnack.showGlobal(outcome.message, error: !outcome.ok);
    });
  }

  /// 「销毁音乐库」：对全库逐条销毁（墓碑 + 缓存 + 封面 + 行），再关掉定时同步。
  Future<void> _destroyLibrary() async {
    final app = context.read<AppState>();
    final l10n = AppLocalizations.of(context)!;
    final ok = await _confirmDestructive(
      title: l10n.destroyLibraryTitle,
      body: l10n.destroyLibraryBody,
      note: l10n.destroyLibraryNote,
      action: l10n.destroyLibraryAction,
      phrase: l10n.destroyLibraryPhrase,
    );
    if (ok != true || !mounted) return;
    await _guard(() async {
      final destroyed = await showDestroyProgress(
        context,
        total: app.library.tracks.length,
        run: (onProgress, isCancelled) => app.destroyMusicLibrary(
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      );
      if (!mounted) return;
      AppSnack.showGlobal(
        AppLocalizations.of(context)!.destroyLibraryDone(destroyed),
      );
    });
  }

  /// 不可逆动作的二次确认：正文说会发生什么，小一号字补后果，最后要求手打 YES
  /// （不区分大小写）才让确认按钮可用。
  Future<bool?> _confirmDestructive({
    required String title,
    required String body,
    required String note,
    required String action,
    required String phrase,
  }) {
    final typed = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final confirmed = typed.text.trim().toLowerCase() == 'yes';
          return AlertDialog(
            backgroundColor: AppColors.elevated,
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 12),
                Text(phrase, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: typed,
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                    hintText: 'YES',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx)!.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
                child: Text(action),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Audit the cloud library (orphans / missing parts) and offer to clean up.
  Future<void> _tidy() async {
    final sync = context.read<SyncService>();
    LibraryAudit audit;
    try {
      audit = await sync.auditLibrary();
    } catch (e) {
      AppSnack.showGlobal(
        AppLocalizations.of(context)!.readCloudLibraryFailed(e.toString()),
        error: true,
      );
      return;
    }
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(AppLocalizations.of(ctx)!.tidyCloudLibraryTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(audit.summary),
              const SizedBox(height: 8),
              if (audit.missing.isNotEmpty) ...[
                Text(
                  AppLocalizations.of(ctx)!.missingFragments,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
                const SizedBox(height: 4),
                for (final name in audit.missing.take(8))
                  Text(
                    AppLocalizations.of(ctx)!.missingFragmentName(name),
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
              if (audit.orphans.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(ctx)!.orphanFiles,
                  style: const TextStyle(fontSize: 12),
                ),
                for (final name in audit.orphans.take(8))
                  Text('• $name', style: const TextStyle(fontSize: 12)),
              ],
              if (audit.healthy)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    AppLocalizations.of(ctx)!.auditHealthy,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.close),
          ),
          if (audit.orphans.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'orphans'),
              child: Text(AppLocalizations.of(ctx)!.deleteOrphans),
            ),
          if (audit.missing.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'rebuild'),
              child: Text(AppLocalizations.of(ctx)!.rebuildFromLocal),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'orphans') {
      await _guard(() async {
        final n = await sync.tidyLibraryOrphans(audit);
        AppSnack.showGlobal(AppLocalizations.of(context)!.orphansDeleted(n));
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
      AppSnack.showGlobal(
        AppLocalizations.of(context)!.readBackupsListFailed('$e'),
        error: true,
      );
    }
  }

  Future<void> _restore() async {
    final sync = context.read<SyncService>();
    final app = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text(AppLocalizations.of(ctx)!.restoreConfirmTitle),
        content: Text(AppLocalizations.of(ctx)!.restoreConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.restore),
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
      final l10n = AppLocalizations.of(context)!;
      AppSnack.showGlobal(
        result.ok
            ? l10n.exportedTo(
                result.fileName,
                PlatformExportService.describeLocation(result.location, l10n),
              )
            : l10n.exportFailed(
                PlatformExportService.describeError(result.error ?? '', l10n),
              ),
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
      final l10n = AppLocalizations.of(context)!;
      AppSnack.showGlobal(
        l10n.pickFileFailed(
          PlatformExportService.describeError(picked.error ?? '', l10n),
        ),
        error: true,
      );
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
      AppSnack.showGlobal(AppLocalizations.of(context)!.pasteBase64First);
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
    AppSnack.showGlobal(
      AppLocalizations.of(context)!.remoteRootUpdated(settings.syncRemoteRoot),
    );
  }

  /// One row listing the four derived cloud locations, so the effect of the
  /// 路径 field above is never a guess.
  Widget _derivedPaths(SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;
    final rows = <(String, String)>[
      (l10n.derivedPathCredentials, settings.credentialsRemotePath),
      (l10n.derivedPathPlaylists, settings.playlistRemotePath),
      (l10n.derivedPathLibrary, settings.libraryRemotePath),
      (l10n.derivedPathBackups, settings.backupRemotePath),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, path) in rows)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.labelValuePair(label, path),
              style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
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
    final l10n = AppLocalizations.of(context)!;

    // Non-listening handle used by the action closures below: they must keep
    // working after this screen is gone.
    final app = context.read<AppState>();
    // The 网盘 shown in the 远端路径 dropdown: the pinned one, else the active
    // account. A stale id (account deleted) is not allowed to assert.
    var rootAccountId = settings.syncAccountId;
    if (rootAccountId == null ||
        !accounts.accounts.any(
          (a) => a.id == rootAccountId && a.providerType == 'webdav',
        )) {
      // 兜底也只认 WebDAV 类型：活跃账号是云盘时没有同步目标。
      final active = accounts.activeAccount;
      rootAccountId = active != null && active.providerType == 'webdav'
          ? active.id
          : null;
    }

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(l10n.syncAndBackup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.syncIntroLong,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const Divider(height: 28),

          // 一键同步放在最上面：这是最常用的动作。
          FilledButton.icon(
            onPressed: _running || accounts.accounts.isEmpty ? null : _syncAll,
            icon: const Icon(Icons.sync),
            label: Text(l10n.syncAll),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.schedule, size: 20),
            title: Text(
              l10n.scheduledSync,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              settings.syncInterval == SyncInterval.off
                  ? l10n.scheduledSyncOff
                  : l10n.scheduledSyncAuto(settings.syncInterval.label(l10n)),
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<SyncInterval>(
              borderRadius: BorderRadius.circular(10),
              value: settings.syncInterval,
              underline: const SizedBox.shrink(),
              items: [
                for (final v in SyncInterval.values)
                  DropdownMenuItem(value: v, child: Text(v.label(l10n))),
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
            title: Text(l10n.remotePath, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              l10n.remotePathSubtitleLong,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (accounts.accounts.isEmpty)
            Text(
              l10n.needWebdavServer,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            )
          else ...[
            DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(10),
              key: ValueKey('sync-root-account-$rootAccountId'),
              initialValue: rootAccountId,
              decoration: InputDecoration(
                labelText: l10n.selectCloudDrive,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                // 云盘账号没有写路径（上传已砍），同步目标只列 WebDAV 类型
                //（99 §7.2.8）。
                for (final a in accounts.accounts)
                  if (a.providerType == 'webdav')
                    DropdownMenuItem(
                      value: a.id,
                      child: MarqueeText(webDavAccountLabel(a, l10n)),
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
                    decoration: InputDecoration(
                      labelText: l10n.pathStep,
                      hintText: '/player/',
                      helperText: l10n.pathExampleLong,
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
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
                    child: Text(l10n.apply),
                  ),
                ),
              ],
            ),
            _derivedPaths(settings),
          ],

          const Divider(height: 28),

          _sectionTitle(l10n.credentialsSection),
          Text(
            l10n.credentialsSectionDesc(settings.credentialsRemotePath),
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          _keyField(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: Text(l10n.encryptPasswordField),
            subtitle: Text(
              settings.syncEncryptPassword
                  ? l10n.encryptPasswordOn
                  : l10n.encryptPasswordOff,
            ),
            value: settings.syncEncryptPassword,
            onChanged: (v) => settings.setSyncEncryptPassword(v),
          ),
          if (sync.lastAutoSyncAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.lastAutoScan(_fmtTime(sync.lastAutoSyncAt!)),
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
                  label: Text(l10n.uploadCredentials),
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
                  label: Text(l10n.downloadCredentials),
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          _sectionTitle(l10n.playlistsSection),
          Text(
            l10n.playlistsSectionDesc(settings.playlistRemotePath),
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
            label: Text(l10n.syncPlaylistsNow),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running || accounts.accounts.isEmpty
                ? null
                : () => _runSync(sync.compactPlaylistDeletions),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(l10n.compactPlaylistDeletions),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.compactPlaylistDeletionsHint,
            style: const TextStyle(color: AppColors.mutedText, fontSize: 11),
          ),

          const Divider(height: 32),

          _sectionTitle(l10n.librarySection),
          Text(
            l10n.librarySectionDesc(settings.libraryRemotePath),
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          if (sync.cloudFragmentCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.cloudFragmentsLine(
                  sync.cloudFragmentCount,
                  _fmtBytes(sync.cloudFragmentBytes),
                  sync.cloudFragmentCount >=
                      settings.libraryRebuildHintFragments,
                ),
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
                  label: l10n.syncAction,
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
                  label: l10n.rebuildAction,
                  onPressed: _running || accounts.accounts.isEmpty
                      ? null
                      : _rebuild,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _compactButton(
                  icon: Icons.cleaning_services_outlined,
                  label: l10n.tidyAction,
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
            title: Text(
              l10n.rebuildHintThreshold,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              sync.cloudFragmentCount > 0
                  ? l10n.rebuildHintNow(
                      sync.cloudFragmentCount,
                      settings.libraryRebuildHintFragments,
                    )
                  : l10n.rebuildHintTarget(
                      settings.libraryRebuildHintFragments,
                    ),
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<int>(
              borderRadius: BorderRadius.circular(10),
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
                        ? l10n.customThreshold
                        : l10n.customThresholdValue(
                            settings.libraryRebuildHintFragments,
                          ),
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

          const SizedBox(height: 12),

          // 两个不可逆动作：红底白字、上下各一个，都要二次确认。
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: _running || accounts.accounts.isEmpty
                  ? null
                  : _overwriteLibraryFromCloud,
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text(l10n.overwriteLibraryTitle),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: _running ? null : _destroyLibrary,
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(l10n.destroyLibraryTitle),
            ),
          ),
          const Divider(height: 32),

          _sectionTitle(l10n.allBackupsSection),
          Text(
            l10n.allBackupsSectionDesc(settings.backupRemotePath),
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          if (accounts.accounts.isEmpty)
            Text(
              l10n.needWebdavServer,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            )
          else ...[
            FilledButton.icon(
              onPressed: _running ? null : _backup,
              icon: const Icon(Icons.backup_outlined),
              label: Text(l10n.startBackup),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _guard(_loadBackupList),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.readBackupsUnderPath),
            ),
            if (_backupFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                borderRadius: BorderRadius.circular(10),
                key: ValueKey('backup-file-${_selectedBackupFile ?? ''}'),
                initialValue: _selectedBackupFile,
                decoration: InputDecoration(
                  labelText: l10n.backupToRestore,
                  border: const OutlineInputBorder(),
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
                label: Text(l10n.restoreFromSelectedBackup),
              ),
            ],
          ],

          const Divider(height: 32),

          _sectionTitle(l10n.localImportExportSection),
          Text(
            l10n.localImportExportDesc,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _running ? null : _exportLocal,
            icon: const Icon(Icons.save_alt),
            label: Text(l10n.exportToDownloads),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : () => _exportLocal(readableJson: true),
            icon: const Icon(Icons.data_object),
            label: Text(l10n.exportReadableJson),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : _importLocal,
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.importFromLocalFile),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _base64Controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.pasteBase64Label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : _importBase64,
            icon: const Icon(Icons.content_paste),
            label: Text(l10n.importFromPaste),
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
                    sync.progressLabel ?? l10n.processing,
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
      title: Text(AppLocalizations.of(context)!.rebuildCloudLibraryTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.rebuildCloudLibraryDesc),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.tracksPerShard),
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
              title: Text(AppLocalizations.of(context)!.embedCoversInShards),
              subtitle: Text(
                AppLocalizations.of(context)!.embedCoversInShardsDesc,
              ),
              value: _withCovers,
              onChanged: (v) {
                setState(() => _withCovers = v);
                _refresh();
              },
            ),
            const SizedBox(height: 4),
            Text(
              est == null
                  ? (_loading
                        ? AppLocalizations.of(context)!.estimating
                        : AppLocalizations.of(context)!.estimateUnavailable)
                  : est.label,
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
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            perShard: _perShard,
            withCovers: _withCovers,
          )),
          child: Text(AppLocalizations.of(context)!.rebuildAction),
        ),
      ],
    );
  }
}
