import '../utils/app_snack.dart';

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
import '../utils/back_handler_registry.dart';
import '../utils/cue_sheet.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/marquee_text.dart';
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

  /// Multi-select mode (entered by long-pressing a file entry).
  bool _selecting = false;
  final Set<String> _selected = {};

  String get _path => _stack.last;

  String _itemKey(WebDavItem item) =>
      '${item.isDirectory ? 'd' : 'f'}\u0000${item.path}';

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
    // Take the system back key for directory navigation / multi-select.
    BackHandlerRegistry.register(_handleSystemBack);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAndLoad());
  }

  @override
  void dispose() {
    BackHandlerRegistry.unregister(_handleSystemBack);
    super.dispose();
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
    // Make sure every account has a client before the first request. Without
    // this the very first listing could go out with no credentials and fail as
    // 401/403 for every configured account — which popped one permission dialog
    // per account on every app start.
    await app.registerAllAccounts();
    // Bring the browsing pointer in line with the selected account. Previously
    // this was only done when the ids differed, and the reload loop below could
    // fire again before the first load finished — producing duplicate dialogs.
    _browsedAccountId = accounts.activeAccountId;
    await _load();
  }

  Future<void> _load() async {
    if (_loading) return; // never run two listings at once
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
    if (!webDav.hasAccount(accounts.activeAccountId ?? '')) {
      await context.read<AppState>().registerAllAccounts();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fileTypes = context.read<SettingsService>().fileTypes;
      // Resolve the account once for both the request and the bookkeeping, so the
      // listing and [_browsedAccountId] can never disagree.
      final accountId = _accountId;
      if (accountId == null) {
        setState(() => _loading = false);
        return;
      }
      final items = await webDav.listDirectory(
        accountId,
        _path,
        fileTypes: fileTypes,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _browsedAccountId = accountId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _items = [];
      });
      // Show the permission dialog at most once per account per session: it used
      // to reappear on every reload (the reload guard could fire repeatedly
      // before the first listing finished), which on startup looked like "a
      // permission error every time, one per configured account".
      final accountId = _accountId;
      if (isWebDavPermissionError(e) &&
          accountId != null &&
          _permissionWarned.add(accountId)) {
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

  /// Handles the system back key for this tab.
  ///
  /// Returns true when the gesture was consumed here: leave multi-select, or walk
  /// up one directory. Returns false at the root so the shell keeps its usual
  /// root-back behaviour (return to the home tab / send the task to the
  /// background).
  bool _handleSystemBack() {
    if (!mounted) return false;
    if (_selecting) {
      _exitSelect();
      return true;
    }
    if (_stack.length > 1) {
      _goUp();
      return true;
    }
    return false;
  }

  void _persistPath() {
    final settings = context.read<SettingsService>();
    if (settings.networkRememberLastPath) {
      settings.setNetworkLastPath(_path);
    }
  }

  /// Account the network library is browsing — always the *current* active
  /// account, never a cached one.
  ///
  /// This used to be `_boundAccountId ?? active`, and `_boundAccountId` was only
  /// updated *after* a load finished. Switching accounts therefore listed the
  /// previous account's directory ("落后一次") because the directory request still
  /// used the stale cached id.
  String? get _accountId => context.read<AccountsService>().activeAccountId;

  /// Library binding name for a local WebDAV account id.
  String _nameFor(String accountId) =>
      context.read<AccountsService>().nameForAccount(accountId) ?? '';



  /// The account whose directory the current [_items] belong to. Only used to
  /// detect an external account switch for reloading.
  String? _browsedAccountId;

  /// Accounts already warned about a permission failure this session, so a
  /// retry loop cannot stack dialogs.
  final Set<String> _permissionWarned = {};

  Future<void> _onTapFile(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    if (item.isVideo) {
      final settings = context.read<SettingsService>();
      if (settings.videoTapAction == VideoTapAction.download) {
        await _enqueueOnly(item);
      } else {
        await _openVideo(item);
      }
      return;
    }
    // Music: tap = download. There is deliberately no separate download button
    // on the row — the row itself is the download action (and plays once the
    // file is cached).
    final settings = context.read<SettingsService>();
    if (!item.isAudio) {
      await _enqueueOnly(item);
      return;
    }
    final cache = context.read<CacheService>();
    final local = await cache.localPathIfCached(
      item.path,
      sourceName: sourceName,
    );
    final wantsPlay = settings.musicTapAction == MusicTapAction.play;
    if (local == null || !wantsPlay) {
      // Not cached → download. Already cached but the tap action is 下载 → also a
      // plain download request (keeps the setting meaningful without a button).
      await _enqueueOnly(item);
      return;
    }
    final player = context.read<AudioPlayerService>();
    final audios = _items.where((e) => e.isAudio).toList();
    final playlist = <TrackInfo>[];
    for (final e in audios) {
      final path = await cache.localPathIfCached(e.path, sourceName: sourceName);
      if (path == null) continue;
      playlist.add(
        TrackInfo(
          sourceName: sourceName,
          accountId: accountId,
          remotePath: e.path,
          fileName: e.name,
          localPath: path,
        ),
      );
    }
    final track = TrackInfo(
      sourceName: sourceName,
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
      AppSnack.show(context, 'WebDAV 未连接，无法流式播放');
      return;
    }
    // Build a play queue from this folder: the already-listed videos seed it so
    // playback starts immediately, and the player keeps scanning in the
    // background to extend 上一个 / 下一个.
    final seed = VideoQueueSeed(
      accountId: accountId,
      folderPath: _path,
      current: item,
      siblings: _items.where((e) => e.isVideo).toList(),
    );
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(source: source, seed: seed),
      ),
    );
  }

  /// Download a file whose extension is in none of the configured lists.
  ///
  /// Such files have no playback path, so they go to the public Downloads folder
  /// (MediaStore `Download/…`) and are never indexed into the music library.
  Future<void> _enqueueUnknown(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    try {
      final queued = await downloads.enqueueToDownloads(
        sourceName,
        item.path,
        fileName: item.name,
      );
      if (!mounted) return;
      if (!queued) AppSnack.show(context, '该文件已在下载队列或已下载');
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, '加入下载失败：${downloads.lastError ?? e}');
    }
  }

  /// Enqueue one file for download. Videos go to the **system gallery**;
  /// music goes to the app-internal audio cache (playback reads only there).
  ///
  /// Deliberately **silent on success**: `enqueue` resolves when the task is
  /// persisted for a cached file, but for a new file it waits for the whole
  /// download — so a success message used to appear at *download completion*
  /// while saying "已加入下载". The row's status chip and the download queue
  /// already show progress; only failures speak up.
  Future<void> _enqueueOnly(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    try {
      if (item.isVideo) {
        await downloads.enqueueGallery(
          sourceName,
          item.path,
          fileName: item.name,
        );
        return;
      }
      await downloads.enqueue(sourceName, item.path, fileName: item.name);
    } catch (e) {
      if (!mounted) return;
      final hint = downloads.lastError ?? '$e';
      AppSnack.error(context, '加入下载失败：$hint');
    }
  }

  /// Download many entries at once (multi-select). Videos → system gallery.
  Future<void> _enqueueMany(List<WebDavItem> items) async {
    final accountId = _accountId;
    if (accountId == null || items.isEmpty) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    final videos = items.where((e) => e.isVideo).toList();
    final others = items.where((e) => !e.isVideo).toList();
    var queued = 0;
    if (videos.isNotEmpty) {
      queued += await downloads.enqueueGalleryMany(
        videos.map(
          (v) => (sourceName: sourceName, remotePath: v.path, fileName: v.name),
        ),
      );
    }
    for (final item in others) {
      // Video-adjacent and unknown files are neither audio nor cacheable.
      if (!item.isAudio) continue;
      if (await downloads.ensureQueued(
        sourceName,
        item.path,
        fileName: item.name,
      )) {
        queued++;
      }
    }
    if (!mounted) return;
    AppSnack.show(
      context,
      queued == 0
          ? '所选条目均已在队列或已下载'
          : '已加入 $queued 个下载任务'
                '${videos.isEmpty ? '' : '（视频保存到系统相册）'}',
    );
  }

  Future<void> _enqueueFolder(WebDavItem folder) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    AppSnack.show(context, '正在扫描文件夹：${folder.name}');
    try {
      final n = await downloads.enqueueFolder(sourceName, folder.path);
      if (!mounted) return;
      AppSnack.show(context, '已加入 $n 个音频文件到下载队列');
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
      final bytes = await webDav.readAsBytes(_accountId!, item.path);
      final sheet = CueSheetParser.tryParse(decodeCueText(bytes));
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
      AppSnack.show(context, '读取 CUE 失败：$e');
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
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '此 CUE 将整张专辑按分片导入音乐库，不是独立单曲文件。',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
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
                            leading: const Icon(
                              Icons.audio_file_outlined,
                              size: 20,
                            ),
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
                            subtitle:
                                (t.performer != null && t.performer!.isNotEmpty)
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
    final sourceName = _nameFor(accountId);
    try {
      await context.read<DownloadQueueService>().enqueueCueGroup(
        sourceName: sourceName,
        cueRemotePath: item.path,
        cueFileName: item.name,
        preParsed: sheet,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'CUE 下载失败：$e');
    }
  }

  Future<void> _showItemMenu(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated,
      isScrollControlled: true,
      shape: AppBottomSheet.shape,
      builder: (ctx) {
        return AppBottomSheet(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  title: const Text('删除'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteItem(item);
                  },
                ),
              ] else if (item.isAudio) ...[
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载到本地缓存'),
                  subtitle: const Text('点按整行即为下载，此处为备用入口'),
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
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
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
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  title: const Text('删除'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteItem(item);
                  },
                ),
              ] else ...[
                // Not in the configured music/video/CUE extension lists: still
                // downloadable, just with no playback path — it lands in the
                // public Downloads folder instead of the audio cache.
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载到系统下载目录'),
                  subtitle: const Text('该后缀不在音乐/视频列表中，不会进入音乐库'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _enqueueUnknown(item);
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
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
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
      await context.read<WebDavService>().createFolder(_accountId!, path);
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
      await context.read<WebDavService>().renamePath(
        _accountId!,
        item.path,
        newPath,
      );
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
      await context.read<WebDavService>().deletePath(_accountId!, item.path);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsService>();
    final downloads = context.watch<DownloadQueueService>();
    final player = context.watch<AudioPlayerService>();
    final active = accounts.activeAccount;

    // Reload when the active account changed from the one these items came from
    // (e.g. switched in the accounts screen, or from the drawer).
    if (active != null && _browsedAccountId != active.id && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _stack
          ..clear()
          ..add('/');
        _ensureAndLoad();
      });
    }

    // The system back key is handled through [BackHandlerRegistry] (registered in
    // initState), which the app shell consults before its own fallbacks. Doing it
    // with PopScope here did not work: this screen sits in a nested Navigator
    // inside the shell's own PopScope, and the event never reached our handler.
    return _buildScaffold(accounts, downloads, player, active);
  }

  Widget _buildScaffold(
    AccountsService accounts,
    DownloadQueueService downloads,
    AudioPlayerService player,
    WebDavAccount? active,
  ) {
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        // Always the drawer button: directory navigation is done by the system
        // back key (see BackHandlerRegistry), so the top-left is reserved for the
        // side menu like every other tab.
        leading: const DrawerMenuButton(),
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
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
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
                        // 名称（用户名）so two mounts on the same host are
                        // distinguishable at a glance.
                        child: Text(
                          webDavAccountLabel(a),
                          overflow: TextOverflow.ellipsis,
                        ),
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
              Icon(
                Icons.cloud_off,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
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
    final sourceName =
        context.read<AccountsService>().nameForAccount(active?.id ?? '') ?? '';
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
                final task = sourceName.isEmpty
                    ? null
                    : downloads.taskFor(sourceName, item.path);
                final saved =
                    task != null &&
                    task.isGallery &&
                    task.status == DownloadStatus.completed;
                return ListTile(
                  leading: _selectionLeading(
                    item,
                    const Icon(
                      Icons.videocam_outlined,
                      color: AppColors.accent,
                    ),
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

              final task = sourceName.isEmpty
                  ? null
                  : downloads.taskForRemote(sourceName, item.path);
              // Undownloaded + never enqueued → TrackUiState.remote (no chip).
              final state = sourceName.isEmpty
                  ? TrackUiState.remote
                  : downloads.uiStateFor(
                      sourceName,
                      item.path,
                      playingRemotePath: player.currentRemotePath,
                      playingSourceName: player.currentSourceName,
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
                  [
                    item.size != null ? _fmtSize(item.size!) : '音频',
                    // 没有下载按钮：整行就是下载动作。
                    if (state == TrackUiState.remote) '点按下载',
                  ].join(' · '),
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
    final allSelected = _items.isNotEmpty && _selected.length >= _items.length;
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
              IconButton(
                tooltip: allSelected ? '取消全选' : '全选',
                onPressed: _items.isEmpty
                    ? null
                    : () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                          _selecting = false;
                        } else {
                          _selected
                            ..clear()
                            ..addAll(_items.map(_itemKey));
                        }
                      }),
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
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
