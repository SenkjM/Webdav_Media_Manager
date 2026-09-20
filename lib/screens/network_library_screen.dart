import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/download_queue_service.dart';
import '../services/webdav_service.dart';
import '../utils/audio_extensions.dart';
import '../utils/cue_sheet.dart';
import '../widgets/track_status_chip.dart';
import '../utils/webdav_errors.dart';
import '../widgets/webdav_error_dialog.dart';
import 'accounts_screen.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

/// 网络库：multi-WebDAV browse. Shows entry names only (no full remote paths).
class NetworkLibraryScreen extends StatefulWidget {
  const NetworkLibraryScreen({super.key});

  @override
  State<NetworkLibraryScreen> createState() => _NetworkLibraryScreenState();
}

class _NetworkLibraryScreenState extends State<NetworkLibraryScreen> {
  final List<String> _stack = ['/'];
  List<WebDavItem> _items = [];
  bool _loading = false;
  String? _error;
  String? _boundAccountId;

  String get _path => _stack.last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAndLoad());
  }

  Future<void> _ensureAndLoad() async {
    final app = context.read<AppState>();
    final accounts = context.read<AccountsService>();
    if (!accounts.hasAccounts) {
      setState(() {
        _error = '请先添加 WebDAV 服务器';
        _items = [];
      });
      return;
    }
    if (app.webDav.accountId != accounts.activeAccountId) {
      await app.connectActiveAccount();
    }
    _boundAccountId = accounts.activeAccountId;
    await _load();
  }

  Future<void> _load() async {
    final webDav = context.read<WebDavService>();
    final accounts = context.read<AccountsService>();
    if (!accounts.hasAccounts) {
      setState(() {
        _error = '请先添加 WebDAV 服务器';
        _items = [];
        _loading = false;
      });
      return;
    }
    if (!webDav.isConnected) {
      await context.read<AppState>().connectActiveAccount();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await webDav.listDirectory(_path);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _boundAccountId = accounts.activeAccountId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _items = [];
      });
      if (isWebDavPermissionError(e)) {
        await showWebDavErrorDialog(context, e);
      }
    }
  }

  Future<void> _onAccountChanged(String? id) async {
    if (id == null) return;
    await context.read<AppState>().switchAccount(id);
    _stack
      ..clear()
      ..add('/');
    await _load();
  }

  void _enterDir(WebDavItem item) {
    _stack.add(item.path);
    _load();
  }

  void _goUp() {
    if (_stack.length <= 1) return;
    _stack.removeLast();
    _load();
  }

  String? get _accountId =>
      _boundAccountId ?? context.read<AccountsService>().activeAccountId;

  Future<void> _onTapFile(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final downloads = context.read<DownloadQueueService>();
    final player = context.read<AudioPlayerService>();
    final audios = _items.where((e) => e.isAudio).toList();
    final playlist = audios
        .map(
          (e) => TrackInfo(
            accountId: accountId,
            remotePath: e.path,
            fileName: e.name,
          ),
        )
        .toList();
    final track = TrackInfo(
      accountId: accountId,
      remotePath: item.path,
      fileName: item.name,
    );

    final existing = downloads.taskForRemote(accountId, item.path);
    final app = context.read<AppState>();
    final cached =
        await app.cache.localPathIfCached(item.path, accountId: accountId);
    if (!mounted) return;
    if (cached == null &&
        (existing == null ||
            existing.status == DownloadStatus.failed ||
            existing.status == DownloadStatus.cancelled)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入下载队列：${item.name}')),
      );
    }
    await player.playTrack(track, playlist: playlist);
  }

  Future<void> _enqueueOnly(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final downloads = context.read<DownloadQueueService>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('排队下载：${item.name}')),
    );
    downloads.enqueue(accountId, item.path, fileName: item.name).ignore();
  }

  Future<void> _enqueueFolder(WebDavItem folder) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final downloads = context.read<DownloadQueueService>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在扫描文件夹：${folder.name}')),
    );
    try {
      final n = await downloads.enqueueFolder(accountId, folder.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入 $n 个音频文件到下载队列')),
      );
    } catch (e) {
      if (!mounted) return;
      await showWebDavErrorDialog(context, e);
    }
  }



  Future<void> _openCue(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    // Show loading while fetching/parsing — do NOT enqueue downloads yet.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('正在解析 CUE…')),
          ],
        ),
      ),
    );
    try {
      final webDav = context.read<WebDavService>();
      final bytes = await webDav.readAsBytes(item.path);
      final sheet = CueSheetParser.tryParse(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close loading
      if (sheet == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法解析的 CUE：需要标准 FILE + TRACK/INDEX')),
        );
        return;
      }
      await _showCuePreview(item, sheet);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取 CUE 失败：$e')),
      );
    }
  }

  Future<void> _showCuePreview(WebDavItem item, CueSheet sheet) async {
    final accountId = _accountId;
    if (accountId == null) return;
    // Group tracks by referenced audio FILE when multiple FILEs exist.
    final byFile = <String, List<CueTrack>>{};
    for (final t in sheet.tracks) {
      byFile.putIfAbsent(t.fileName, () => []).add(t);
    }
    final multiFile = byFile.length > 1;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    (sheet.title != null && sheet.title!.isNotEmpty)
                        ? sheet.title!
                        : item.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onDark,
                    ),
                  ),
                ),
                if (sheet.performer != null && sheet.performer!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      sheet.performer!,
                      style: const TextStyle(color: AppColors.mutedText),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'CUE · ${sheet.tracks.length} 曲'
                    '${multiFile ? ' · ${byFile.length} 个音频文件' : ''}',
                    style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in byFile.entries) ...[
                        if (multiFile)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.audio_file_outlined, size: 20),
                            title: Text(
                              entry.key,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        for (final t in entry.value)
                          ListTile(
                            dense: true,
                            title: Text(
                              '${t.number.toString().padLeft(2, '0')}-${t.title?.isNotEmpty == true ? t.title! : 'Track ${t.number}'}',
                            ),
                            subtitle: (t.performer != null && t.performer!.isNotEmpty)
                                ? Text(t.performer!)
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'close'),
                          child: const Text('关闭'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, 'download'),
                          icon: const Icon(Icons.download),
                          label: const Text('下载'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action != 'download' || !mounted) return;
    await _downloadCueGroup(item, sheet);
  }

  Future<void> _downloadCueGroup(WebDavItem item, CueSheet sheet) async {
    final accountId = _accountId;
    if (accountId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入 CUE 专辑「${sheet.title ?? item.name}」下载队列')),
    );
    try {
      await context.read<DownloadQueueService>().enqueueCueGroup(
        accountId: accountId,
        cueRemotePath: item.path,
        cueFileName: item.name,
        preParsed: sheet,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载任务已排队：完成后音乐库显示 ${sheet.tracks.length} 首虚拟曲目')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CUE 下载失败：$e')),
      );
    }
  }

  Future<void> _showItemMenu(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  item.isDirectory ? '文件夹' : '文件',
                  style: const TextStyle(color: AppColors.mutedText),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              if (item.isDirectory) ...[
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载整个文件夹'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _enqueueFolder(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameItem(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: const Text('删除'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteItem(item);
                  },
                ),
              ] else if (item.isAudio) ...[
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _enqueueOnly(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('播放（下载后播放）'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _onTapFile(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameItem(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: const Text('删除'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteItem(item);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameItem(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: const Text('删除'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteItem(item);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final parent = _path.endsWith('/') ? _path : '$_path/';
    final path = '$parent$name';
    await runWebDavAction(context, () async {
      await context.read<WebDavService>().createFolder(path);
      await _load();
    });
  }

  Future<void> _renameItem(WebDavItem item) async {
    final controller = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '新名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == item.name || !mounted) return;
    final parent = item.path.substring(0, item.path.lastIndexOf(item.name));
    var newPath = '$parent$name';
    if (item.isDirectory && !newPath.endsWith('/')) newPath = '$newPath/';
    await runWebDavAction(context, () async {
      await context.read<WebDavService>().renamePath(item.path, newPath);
      await _load();
    });
  }

  Future<void> _deleteItem(WebDavItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除「${item.name}」？此操作不可撤销。'),
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
    if (ok != true || !mounted) return;
    await runWebDavAction(context, () async {
      await context.read<WebDavService>().deletePath(item.path);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsService>();
    final downloads = context.watch<DownloadQueueService>();
    final player = context.watch<AudioPlayerService>();
    final active = accounts.activeAccount;

    // Reload when active account changes externally.
    if (active != null &&
        _boundAccountId != null &&
        active.id != _boundAccountId &&
        !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stack
          ..clear()
          ..add('/');
        _ensureAndLoad();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: _stack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goUp,
              )
            : const DrawerMenuButton(),
        title: Text(folderDisplayName(_path)),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: accounts.hasAccounts ? _createFolder : null,
          ),
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: '管理服务器',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              );
              if (mounted) await _ensureAndLoad();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (accounts.hasAccounts)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: active?.id,
                decoration: const InputDecoration(
                  labelText: '当前服务器',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: accounts.accounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _onAccountChanged,
              ),
            ),
          Expanded(child: _buildBody(downloads, player, active)),
        ],
      ),
    );
  }

  Widget _buildBody(
    DownloadQueueService downloads,
    AudioPlayerService player,
    WebDavAccount? active,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _ensureAndLoad, child: const Text('重试')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountsScreen()),
                  );
                  if (mounted) await _ensureAndLoad();
                },
                child: const Text('管理服务器'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('空目录'));
    }
    final accountId = active?.id ?? _accountId;
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        if (item.isDirectory) {
          return ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.accent),
            title: Text(item.name),
            subtitle: const Text('目录'),
            onTap: () => _enterDir(item),
            onLongPress: () => _showItemMenu(item),
          );
        }
        if (item.isCue) {
          return ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(item.name),
            subtitle: Text(item.size != null ? _fmtSize(item.size!) : 'CUE 文件'),
            onTap: () => _openCue(item),
            onLongPress: () => _showItemMenu(item),
          );
        }
        if (!item.isAudio) {
          return ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(item.name),
            subtitle: Text(item.size != null ? _fmtSize(item.size!) : '文件'),
            onLongPress: () => _showItemMenu(item),
          );
        }

        final task = accountId == null
            ? null
            : downloads.taskForRemote(accountId, item.path);
        final state = accountId == null
            ? TrackUiState.queued
            : downloads.uiStateFor(
                accountId,
                item.path,
                playingRemotePath: player.currentRemotePath,
                playingAccountId: player.currentAccountId,
              );
        return ListTile(
          leading: Icon(
            state == TrackUiState.playing ? Icons.equalizer : Icons.audiotrack,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(item.name),
          subtitle: Text(item.size != null ? _fmtSize(item.size!) : '音频'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrackStatusChip(
                state: state,
                progress: task?.status == DownloadStatus.active
                    ? task?.progress
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: '仅下载',
                onPressed: () => _enqueueOnly(item),
              ),
            ],
          ),
          onTap: () => _onTapFile(item),
          onLongPress: () => _showItemMenu(item),
        );
      },
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

extension on Future {
  void ignore() {}
}
