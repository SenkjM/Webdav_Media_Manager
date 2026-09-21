
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../models/video_settings.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/download_queue_service.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';
import '../utils/audio_extensions.dart';
import '../utils/cue_sheet.dart';
import '../widgets/track_status_chip.dart';
import '../utils/webdav_errors.dart';
import '../widgets/webdav_error_dialog.dart';
import 'accounts_screen.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import 'video_player_screen.dart';

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

  /// Multi-select mode (entered by long-pressing a file entry).
  bool _selecting = false;
  final Set<String> _selected = {};

  String get _path => _stack.last;

  String _itemKey(WebDavItem item) => '${item.isDirectory ? 'd' : 'f'}\u0000${item.path}';

  List<WebDavItem> get _selectedItems =>
      _items.where((e) => _selected.contains(_itemKey(e))).toList();

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    if (settings.networkRememberLastPath &&
        settings.networkLastPath != '/' &&
        settings.networkLastPath.isNotEmpty) {
      _stack.add(settings.networkLastPath);
    }
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
      final fileTypes = context.read<SettingsService>().fileTypes;
      final items = await webDav.listDirectory(_path, fileTypes: fileTypes);
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
    _persistPath();
    await _load();
  }

  void _enterDir(WebDavItem item) {
    _stack.add(item.path);
    _persistPath();
    _load();
  }

  void _goUp() {
    if (_stack.length <= 1) return;
    _stack.removeLast();
    _persistPath();
    _load();
  }

  void _persistPath() {
    final settings = context.read<SettingsService>();
    if (settings.networkRememberLastPath) {
      settings.setNetworkLastPath(_path);
    }
  }

  String? get _accountId =>
      _boundAccountId ?? context.read<AccountsService>().activeAccountId;

  Future<void> _onTapFile(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    if (item.isVideo) {
      final settings = context.read<SettingsService>();
      if (settings.videoTapAction == VideoTapAction.download) {
        await _enqueueOnly(item);
      } else {
        await _openVideo(item);
      }
      return;
    }
    if (item.isAudio) {
      final settings = context.read<SettingsService>();
      if (settings.musicTapAction == MusicTapAction.download) {
        await _enqueueOnly(item);
        return;
      }
    }
    final cache = context.read<CacheService>();
    final local = await cache.localPathIfCached(item.path, accountId: accountId);
    if (local == null) {
      // Non-local: download link only — never enter the play / preparing flow.
      await _enqueueOnly(item);
      return;
    }
    final player = context.read<AudioPlayerService>();
    final audios = _items.where((e) => e.isAudio).toList();
    final playlist = <TrackInfo>[];
    for (final e in audios) {
      final path = await cache.localPathIfCached(e.path, accountId: accountId);
      if (path == null) continue;
      playlist.add(
        TrackInfo(
          accountId: accountId,
          remotePath: e.path,
          fileName: e.name,
          localPath: path,
        ),
      );
    }
    final track = TrackInfo(
      accountId: accountId,
      remotePath: item.path,
      fileName: item.name,
      localPath: local,
    );
    if (playlist.isEmpty) playlist.add(track);
    await player.playTrack(track, playlist: playlist);
  }

  Future<void> _openVideo(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final source = context.read<WebDavService>().buildStreamSource(
          remotePath: item.path,
          name: item.name,
          accountId: accountId,
        );
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 未连接，无法流式播放')),
      );
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => VideoPlayerScreen(source: source)),
    );
  }

  /// Enqueue one file for download. Videos go to the **system gallery**;
  /// music goes to the app-internal audio cache (playback reads only there).
  Future<void> _enqueueOnly(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final downloads = context.read<DownloadQueueService>();
    if (item.isVideo) {
      final queued = await downloads.enqueueGallery(
        accountId,
        item.path,
        fileName: item.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued ? '已加入下载（保存到系统相册）' : '该视频已在下载队列或已保存到系统相册',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入下载')),
    );
    downloads.enqueue(accountId, item.path, fileName: item.name).ignore();
  }

  /// Download many entries at once (multi-select). Videos → system gallery.
  Future<void> _enqueueMany(List<WebDavItem> items) async {
    final accountId = _accountId;
    if (accountId == null || items.isEmpty) return;
    final downloads = context.read<DownloadQueueService>();
    final videos = items.where((e) => e.isVideo).toList();
    final others = items.where((e) => !e.isVideo).toList();
    var queued = 0;
    if (videos.isNotEmpty) {
      queued += await downloads.enqueueGalleryMany(
        videos.map(
          (v) => (
            accountId: accountId,
            remotePath: v.path,
            fileName: v.name,
          ),
        ),
      );
    }
    for (final item in others) {
      // Video-adjacent and unknown files are neither audio nor cacheable.
      if (!item.isAudio) continue;
      if (await downloads.ensureQueued(
        accountId,
        item.path,
        fileName: item.name,
      )) {
        queued++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queued == 0
              ? '所选条目均已在队列或已下载'
              : '已加入 $queued 个下载任务'
                  '${videos.isEmpty ? '' : '（视频保存到系统相册）'}',
        ),
      ),
    );
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
        decodeCueText(bytes),
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    '多歌曲合并分片 · CUE · ${sheet.tracks.length} 曲'
                    '${multiFile ? ' · ${byFile.length} 个音频文件' : ''}',
                    style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '此 CUE 将整张专辑按分片导入音乐库，不是独立单曲文件。',
                    style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
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
                  title: const Text('播放（仅本地缓存）'),
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
              ] else if (item.isVideo) ...[
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('打开视频（流式播放）'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openVideo(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载到系统相册'),
                  subtitle: const Text('保存到系统相册（Movies），不是应用内部目录'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _enqueueOnly(item);
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
    return Column(
      children: [
        if (_selecting) _buildSelectionBar(),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final item = _items[i];
              if (item.isDirectory) {
                return ListTile(
                  leading: _selectionLeading(
                    item,
                    const Icon(Icons.folder_rounded, color: AppColors.accent),
                  ),
                  title: Text(item.name),
                  subtitle: const Text('目录'),
                  trailing: _itemMenuButton(item),
                  onTap: () => _onEntryTap(item, () => _enterDir(item)),
                  onLongPress: () => _enterSelect(item),
                );
              }
              if (item.isCue) {
                return ListTile(
                  leading: _selectionLeading(
                    item,
                    const Icon(Icons.insert_drive_file_outlined),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    item.size != null ? _fmtSize(item.size!) : 'CUE 文件',
                  ),
                  trailing: _itemMenuButton(item),
                  onTap: () => _onEntryTap(item, () => _openCue(item)),
                  onLongPress: () => _enterSelect(item),
                );
              }
              if (item.isVideo) {
                final task = accountId == null
                    ? null
                    : downloads.taskFor(accountId, item.path);
                final saved = task != null &&
                    task.isGallery &&
                    task.status == DownloadStatus.completed;
                return ListTile(
                  leading: _selectionLeading(
                    item,
                    const Icon(Icons.videocam_outlined, color: AppColors.accent),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    [
                      item.size != null ? _fmtSize(item.size!) : '视频',
                      if (saved) '系统相册',
                    ].join(' · '),
                  ),
                  // Videos expose only 播放 here; 下载 appears on long-press
                  // (item menu) or in multi-select mode.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline),
                        tooltip: '播放视频',
                        onPressed: () => _openVideo(item),
                      ),
                      _itemMenuButton(item),
                    ],
                  ),
                  onTap: () => _onEntryTap(item, () => _onTapFile(item)),
                  onLongPress: () => _enterSelect(item),
                );
              }
              if (!item.isAudio) {
                return ListTile(
                  leading: _selectionLeading(
                    item,
                    const Icon(Icons.insert_drive_file_outlined),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    item.size != null ? _fmtSize(item.size!) : '文件',
                  ),
                  trailing: _itemMenuButton(item),
                  onTap: () => _onEntryTap(item, () {}),
                  onLongPress: () => _enterSelect(item),
                );
              }

              final task = accountId == null
                  ? null
                  : downloads.taskForRemote(accountId, item.path);
              // Undownloaded + never enqueued → TrackUiState.remote (no chip).
              final state = accountId == null
                  ? TrackUiState.remote
                  : downloads.uiStateFor(
                      accountId,
                      item.path,
                      playingRemotePath: player.currentRemotePath,
                      playingAccountId: player.currentAccountId,
                    );
              return ListTile(
                leading: _selectionLeading(
                  item,
                  Icon(
                    state == TrackUiState.playing
                        ? Icons.equalizer
                        : Icons.audiotrack,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(item.name),
                subtitle: Text(
                  item.size != null ? _fmtSize(item.size!) : '音频',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Only show after user-initiated queue / download / ready / play.
                    if (state != TrackUiState.remote)
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
                    _itemMenuButton(item),
                  ],
                ),
                onTap: () => _onEntryTap(item, () => _onTapFile(item)),
                onLongPress: () => _enterSelect(item),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Checkbox shown in multi-select mode, otherwise the entry's own icon.
  Widget _selectionLeading(WebDavItem item, Widget icon) {
    if (!_selecting) return icon;
    final selected = _selected.contains(_itemKey(item));
    return Icon(
      selected ? Icons.check_circle : Icons.circle_outlined,
      color: selected ? AppColors.accent : AppColors.mutedText,
    );
  }

  /// Overflow button opening the per-item menu (rename / delete / download).
  /// Long-press now enters multi-select, so the menu lives on this button.
  Widget _itemMenuButton(WebDavItem item) {
    if (_selecting) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.more_vert),
      tooltip: '更多操作',
      onPressed: () => _showItemMenu(item),
    );
  }

  /// Tap handling that respects multi-select mode.
  void _onEntryTap(WebDavItem item, VoidCallback action) {
    if (!_selecting) {
      action();
      return;
    }
    setState(() {
      final key = _itemKey(item);
      if (!_selected.remove(key)) _selected.add(key);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _enterSelect(WebDavItem item) {
    setState(() {
      _selecting = true;
      _selected.add(_itemKey(item));
    });
  }

  Widget _buildSelectionBar() {
    final items = _selectedItems;
    final videos = items.where((e) => e.isVideo).length;
    return Material(
      color: AppColors.elevated,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '取消',
                onPressed: _exitSelect,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  '已选 ${items.length} 项'
                  '${videos > 0 ? '（$videos 个视频 → 系统相册）' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: '下载',
                onPressed: items.isEmpty ? null : () => _enqueueMany(items),
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
              IconButton(
                tooltip: '下载整个文件夹',
                onPressed: items.length != 1 || !items.first.isDirectory
                    ? null
                    : () => _enqueueFolder(items.first),
                icon: const Icon(Icons.folder_zip_outlined),
              ),
            ],
          ),
        ),
      ),
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
