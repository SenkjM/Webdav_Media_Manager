import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../models/file_actions.dart';
import '../models/webdav_stream.dart';
import '../models/file_type_config.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../providers/app_state.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/download_queue_service.dart';
import '../services/settings_service.dart';
import '../services/video_playback_service.dart';
import '../services/webdav_service.dart';
import '../utils/audio_extensions.dart';
import '../utils/back_handler_registry.dart';
import '../utils/selection_controller.dart';
import '../utils/cue_sheet.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/marquee_text.dart';
import '../widgets/track_status_chip.dart';
import '../utils/webdav_errors.dart';
import '../widgets/webdav_error_dialog.dart';
import 'accounts_screen.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import 'music_stream_screen.dart';
import 'video_player_screen.dart';
import 'webdav_folder_picker_screen.dart';

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

  /// 多选状态。选中数由 [SelectionController] 统一判定「是不是全选」，
  /// 全选按钮因此会在计数打满时变成叉号，而不必记住用户按过它。
  SelectionController _selection = const SelectionController();

  String get _path => _stack.last;

  String _itemKey(WebDavItem item) =>
      '${item.isDirectory ? 'd' : 'f'}\u0000${item.path}';

  List<WebDavItem> get _selectedItems =>
      _items.where((e) => _selection.contains(_itemKey(e))).toList();

  bool get _selecting => _selection.active;

  void _exitSelect() => setState(() => _selection = _selection.exit());

  /// 列表内容换了（进入目录 / 刷新）之后重新数一遍可选条目。
  void _syncSelectionTotal() {
    _selection = _selection.sync(
      total: _items.length,
      validKeys: _items.map(_itemKey),
    );
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
        _syncSelectionTotal();
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
    if (_selection.active) {
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

  /// 点按条目的统一入口：文件夹进目录，文件走**文件动作模型**。
  Future<void> _activateItem(WebDavItem item) async {
    if (item.isDirectory) {
      _enterDir(item);
      return;
    }
    await _runDefaultAction(item);
  }

  /// 这个条目在这份设置下的默认动作。
  FileAction _defaultActionFor(WebDavItem item) {
    final settings = context.read<SettingsService>();
    return settings.fileActions.forCategory(item.category);
  }

  /// 按设置的动作处理一个文件。
  ///
  /// 三个入口（整行点按、多选工具栏、更多菜单）都走这里，所以「点按音乐
  /// 会缓存」和「菜单里的缓存音乐」永远是同一段代码。动作与条目类型不匹配
  /// 时**直接说明原因**，不去猜用户想干什么——静默换成另一个动作会让设置
  /// 看起来没生效。
  Future<void> _runDefaultAction(WebDavItem item) async {
    final decision = judgeAction(
      action: _defaultActionFor(item),
      category: item.category,
      isDirectory: item.isDirectory,
    );
    if (!decision.allowed) {
      AppSnack.error(context, decision.reason ?? '该动作不适用于这个文件');
      return;
    }
    await _runAction(item, decision.action);
  }

  /// 在条目上执行一个**已判定合法**的动作。
  Future<void> _runAction(WebDavItem item, FileAction action) async {
    switch (action) {
      case FileAction.cacheMusic:
        await _cacheMusic(item);
      case FileAction.download:
        await _downloadItem(item);
      case FileAction.stream:
        await _openVideo(item);
      case FileAction.readCue:
        await _openCue(item);
      case FileAction.streamMusic:
        await _streamMusic(item);
    }
  }

  /// 视频 → 远端流式播放（复用视频播放页与它的后台/通知栈）。
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
    // 用户把后缀改掉（音频改成 .mp4 之类）时，源本身会按**内容无关**的后缀
    // 被当视频打开：那会白白起一个 VideoController 解码一个没有画面的流。
    // 音频只有一条流、没有视频轨，直接路由到音乐界面更省电，界面也更合适。
    if (source.kind == StreamKind.music) {
      await _openMusicStream(source, item);
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
  /// 音乐 → 应用音频缓存，完成后 ingest 进音乐库。
  ///
  /// 成功时**刻意不出提示**：`enqueue` 对未缓存的文件要等整段下载结束才
  /// 返回，这时弹「已加入下载」会出现在下载完成的那一刻。行上的状态标签
  /// 与下载队列已经在显示进度，只有失败才说话。
  Future<void> _cacheMusic(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    try {
      await downloads.ensureQueued(sourceName, item.path, fileName: item.name);
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, '加入下载失败：${downloads.lastError ?? e}');
    }
  }

  /// 任何文件 → 系统下载目录（不缓存、不进音乐库）。
  Future<void> _downloadItem(WebDavItem item) async {
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

  /// 音乐 → 远端流式播放（实验性，T6）。
  ///
  /// 当前分支只做到「能播就行」：复用视频那套远端源与媒体通知，封面与时长
  /// 不额外取（流式播放拿不到本地文件来解析标签）。完整取舍见 docs/99 的
  /// 《音乐流式传输可行性分析》。
  /// 实验性：把远端音频直接交给播放栈流式播放（不下载、不缓存、不入队）。
  ///
  /// 复用视频那套远端源与媒体通知（同一个 Player、同一个媒体会话），所以
  /// 后台播放与锁屏控制跟着工作。封面与时长不额外取：流式播放拿不到本地
  /// 文件来解析标签。完整取舍见 docs/99 的《音乐流式传输可行性分析》。
  Future<void> _streamMusic(WebDavItem item) async {
    if (!context.read<SettingsService>().fileActions.experimentalMusicStreaming) {
      AppSnack.error(context, '音乐流式传输是实验功能，请先在设置里打开');
      return;
    }
    final accountId = _accountId;
    if (accountId == null) return;
    final source = context.read<WebDavService>().buildStreamSource(
      remotePath: item.path,
      name: item.name,
      accountId: accountId,
      kind: StreamKind.music,
    );
    if (source == null) {
      AppSnack.error(context, '无法建立流式地址，请检查账户配置');
      return;
    }
    await _openMusicStream(source, item);
  }

  /// 打开音乐流式播放界面（音频与「被当成视频的音频」共用这一条路径）。
  Future<void> _openMusicStream(
    WebDavStreamSource source,
    WebDavItem item,
  ) async {
    final playback = context.read<VideoPlaybackService>();
    // 先建好源再进界面：起播不用等界面第一帧。
    try {
      await playback.prepare(source, bufferSizeMb: 48);
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, '流式播放失败：$e');
      return;
    }
    if (!mounted) return;
    final seed = VideoQueueSeed(
      accountId: source.accountId,
      folderPath: _path,
      current: item,
      siblings: _items.where((e) => e.category == FileCategory.music).toList(),
    );
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => MusicStreamScreen(source: source, seed: seed),
      ),
    );
  }

  /// 多选「下载」：**逐项按类型分发**，而不是把所有东西都当成音频。
  ///
  /// 只有音乐进音频缓存；视频与普通文件都落到系统下载目录。这里刻意不再
  /// 把视频塞进系统相册——「下载」在动作模型里就是 `DownloadTarget.downloads`，
  /// 想存相册可以在更多菜单里单独选。
  Future<void> _downloadMany(List<WebDavItem> items) async {
    final accountId = _accountId;
    if (accountId == null || items.isEmpty) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    var queued = 0;
    var failed = 0;
    for (final item in items) {
      if (item.isDirectory) continue; // 文件夹由「下载整个文件夹」处理
      try {
        final ok = item.category == FileCategory.music
            ? await downloads.ensureQueued(
                sourceName,
                item.path,
                fileName: item.name,
              )
            : await downloads.enqueueToDownloads(
                sourceName,
                item.path,
                fileName: item.name,
              );
        if (ok) queued++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    final parts = <String>[];
    if (queued > 0) parts.add('已加入 $queued 项');
    if (failed > 0) parts.add('失败 $failed 项');
    final text = parts.isEmpty ? '所选条目均已在队列或已下载' : parts.join('，');
    if (failed > 0) {
      AppSnack.error(context, text);
    } else {
      AppSnack.show(context, text);
    }
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
        AppSnack.show(context, '无法解析的 CUE：需要标准 FILE + TRACK/INDEX');
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
                    '将整张专辑按分片导入音乐库。',
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

  /// 单文件右侧「更多」菜单。
  ///
  /// 与 T1 的动作模型对齐：主行动那一条**就是**设置里选的默认动作（文案随之
  /// 变化），其余是该类别允许的其它动作，最后才是重命名 / 复制 / 移动 /
  /// 删除这些与类型无关的条目。上一版三处各写一套判定（音乐写「播放（仅
  /// 本地缓存）」、视频只有播放、普通文件只有下载），已经开始互相打架。
  Future<void> _showItemMenu(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final settings = context.read<SettingsService>();
    final defaultAction = settings.fileActions.forCategory(item.category);
    final otherActions = FileActionCatalog.forCategory(item.category)
        .where((a) => a != defaultAction)
        .where((a) =>
            a != FileAction.streamMusic ||
            settings.fileActions.experimentalMusicStreaming)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated,
      isScrollControlled: true,
      shape: AppBottomSheet.shape,
      builder: (ctx) {
        return AppBottomSheet(
          padding: const EdgeInsets.only(bottom: 8),
          child: SingleChildScrollView(
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
                    item.isDirectory
                        ? '文件夹'
                        : '${categoryLabelZh(item.category)} · 点按＝${defaultAction.labelZh}',
                    style: const TextStyle(color: AppColors.mutedText),
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                if (item.isDirectory)
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('下载整个文件夹'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _enqueueFolder(item);
                    },
                  )
                else ...[
                  ListTile(
                    leading: Icon(_actionIcon(defaultAction)),
                    title: Text(defaultAction.labelZh),
                    subtitle: const Text('设置里的默认动作'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _runDefaultAction(item);
                    },
                  ),
                  for (final action in otherActions)
                    ListTile(
                      leading: Icon(_actionIcon(action)),
                      title: Text(action.labelZh),
                      subtitle: action == FileAction.streamMusic
                          ? const Text('实验性：不下载、不进音乐库')
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _runAction(item, action);
                      },
                    ),
                  // 相册与下载目录是两条不同的落盘路径，视频两个都保留。
                  if (item.isVideo)
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('下载到系统相册'),
                      subtitle: const Text('保存到 Movies/WebdavMediaManager'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _downloadToGallery(item);
                      },
                    ),
                ],
                const Divider(height: 1, color: AppColors.divider),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameItem(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('复制到…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyOrMove([item], move: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('移动到…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyOrMove([item], move: true);
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
            ),
          ),
        );
      },
    );
  }

  IconData _actionIcon(FileAction action) => switch (action) {
        FileAction.cacheMusic => Icons.download_for_offline_outlined,
        FileAction.download => Icons.download,
        FileAction.stream => Icons.play_circle_outline,
        FileAction.readCue => Icons.queue_music_outlined,
        FileAction.streamMusic => Icons.stream,
      };

  /// 复制 / 移动选中的条目到另一个远端文件夹。
  Future<void> _copyOrMove(List<WebDavItem> items, {required bool move}) async {
    final accountId = _accountId;
    if (accountId == null || items.isEmpty) return;
    await copyOrMoveItems(
      context,
      items: items,
      move: move,
      accountId: accountId,
      currentPath: _path,
      onDone: _load,
    );
  }

  /// 视频 → 系统相册（与「下载」分开的一条落盘路径）。
  Future<void> _downloadToGallery(WebDavItem item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    try {
      final queued = await downloads.enqueueGallery(
        sourceName,
        item.path,
        fileName: item.name,
      );
      if (!mounted) return;
      if (!queued) AppSnack.show(context, '该文件已在队列或已保存');
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, '加入下载失败：${downloads.lastError ?? e}');
    }
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
                  onTap: () => _onEntryTap(item),
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
                  onTap: () => _onEntryTap(item),
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
                  onTap: () => _onEntryTap(item),
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
                  onTap: () => _onEntryTap(item),
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
                onTap: () => _onEntryTap(item),
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
    final selected = _selection.contains(_itemKey(item));
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

  /// 点按一行：多选中就切换勾选，否则执行这个条目的默认动作。
  void _onEntryTap(WebDavItem item) {
    if (_selecting) {
      setState(() => _selection = _selection.toggle(_itemKey(item)));
      return;
    }
    _activateItem(item);
  }

  /// 长按一行进入多选，并把这一行选上。
  void _enterSelect(WebDavItem item) {
    setState(() {
      _selection = _selection.enter(
        _itemKey(item),
        selectOnly: _items.map(_itemKey),
      );
    });
  }

  /// 工具栏那个按钮：不是全选就全选，已经是全选就只取消全选（留在多选里）。
  void _toggleSelectAll() {
    setState(() => _selection = _selection.toggleSelectAll(_items.map(_itemKey)));
  }

  /// 多选工具栏。
  ///
  /// 交互约定（本分支修正）：**左边的按钮就是那个按钮**。
  /// - 一进入多选不显示任何叉号：用户好不容易选了几项，旁边杵一个「关闭」
  ///   只会让人误触。
  /// - 选定数打满（计数器对比，不看按钮按过没有）时，它变成叉号，作用是
  ///   **取消全选**，不是退出多选——退出多选交给系统返回键。
  /// - 任何一次手动取消都会把计数打回去，按钮随即变回「全选」。
  ///
  /// 动作按类型分发：下载走 [_downloadMany]，播放只对单个视频开放，复制 /
  /// 移动对任意条目都可选。
  Widget _buildSelectionBar() {
    final items = _selectedItems;
    final folders = items.where((e) => e.isDirectory).toList();
    final files = items.where((e) => !e.isDirectory).toList();
    final onlyFolder = folders.length == 1 && files.isEmpty;
    final allSelected = _selection.isAllSelected;
    final bulkAction = bulkDownloadAction(files.map((e) => e.category));
    // 背景必须在滚动层**外面**：之前滚动层直接当 SafeArea 的孩子，内容一
    // 比屏幕宽，灰色条就只画到内容末端，右边露出一截空白（真机截图里能看
    // 到）。现在滚动只负责按钮，底色由外层铺满整宽。
    return Material(
      color: AppColors.elevated,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: double.infinity),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                // 只在「计数打满」时出现的叉号：它是取消全选，不是关闭界面。
                if (allSelected)
                  IconButton(
                    tooltip: '取消全选',
                    onPressed: _toggleSelectAll,
                    icon: const Icon(Icons.deselect),
                  )
                else
                  IconButton(
                    tooltip: '全选',
                    onPressed: _items.isEmpty ? null : _toggleSelectAll,
                    icon: const Icon(Icons.select_all),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '已选 ${items.length} 项',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                  // 文件夹只有一个来源，按钮跟着选中内容变，不摆一排禁用按钮。
                  if (onlyFolder) ...[
                    IconButton(
                      tooltip: '缓存文件夹中的音频',
                      onPressed: () => _cacheFolderAudio(folders.first),
                      icon: const Icon(Icons.library_music_outlined),
                    ),
                    IconButton(
                      tooltip: '下载整个文件夹',
                      onPressed: () => _downloadFolder(folders.first),
                      icon: const Icon(Icons.folder_zip_outlined),
                    ),
                  ] else ...[
                    // 音频与普通文件分开：音频进缓存（随后进音乐库），其它落
                    // 系统下载目录。混选时两个按钮都可用，按各自的类型分发。
                    IconButton(
                      tooltip: '缓存音乐',
                      onPressed: files.any((e) => e.category == FileCategory.music)
                          ? () => _downloadMany(
                                files
                                    .where(
                                        (e) => e.category == FileCategory.music)
                                    .toList(),
                              )
                          : null,
                      icon: const Icon(Icons.library_music_outlined),
                    ),
                    IconButton(
                      tooltip: '下载',
                      onPressed: files.isNotEmpty
                          ? () => _downloadMany(
                                files
                                    .where(
                                        (e) => e.category != FileCategory.music)
                                    .toList(),
                              )
                          : null,
                      icon: Icon(_actionIcon(bulkAction)),
                    ),
                  ],
                  IconButton(
                    tooltip: '复制到…',
                    onPressed: items.isEmpty
                        ? null
                        : () => _copyOrMove(items, move: false),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                  IconButton(
                    tooltip: '移动到…',
                    onPressed: items.isEmpty
                        ? null
                        : () => _copyOrMove(items, move: true),
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 缓存文件夹内的音频（递归），随缓存管线进音乐库。
  Future<void> _cacheFolderAudio(WebDavItem folder) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    AppSnack.show(context, '正在扫描文件夹中的音频：${folder.name}');
    try {
      final n = await downloads.enqueueFolder(sourceName, folder.path);
      if (!mounted) return;
      AppSnack.show(
        context,
        n == 0 ? '这个文件夹里没有音频' : '已加入 $n 个音频到缓存队列',
      );
    } catch (e) {
      if (!mounted) return;
      await showWebDavErrorDialog(context, e);
    }
  }

  /// 把整个文件夹（递归，含非音频）下载到系统下载目录。
  Future<void> _downloadFolder(WebDavItem folder) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final sourceName = _nameFor(accountId);
    final downloads = context.read<DownloadQueueService>();
    AppSnack.show(context, '正在扫描文件夹：${folder.name}');
    try {
      final n = await downloads.enqueueFolderToDownloads(
        sourceName,
        folder.path,
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        n == 0 ? '这个文件夹里没有可下载的文件' : '已加入 $n 个文件到下载队列',
      );
    } catch (e) {
      if (!mounted) return;
      await showWebDavErrorDialog(context, e);
    }
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
