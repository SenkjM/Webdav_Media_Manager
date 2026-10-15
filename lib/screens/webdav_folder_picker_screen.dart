import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_capabilities.dart';
import '../models/file_type_config.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../widgets/marquee_text.dart';
import '../widgets/meta_text.dart';
import '../utils/app_snack.dart';
import '../utils/audio_extensions.dart';
import '../utils/remote_path.dart';
import '../utils/webdav_errors.dart';
import '../widgets/webdav_error_dialog.dart';
import '../l10n/generated/app_localizations.dart';

/// 远端目录选择器：挑一个目标文件夹，供复制 / 移动使用。
///
/// 返回选中的**目录路径**（不是条目），用户取消时返回 null。浏览、进入、
/// 返回上一层与新建文件夹都在这里处理；调用方只管把结果拿去发 COPY / MOVE。
class WebDavFolderPickerScreen extends StatefulWidget {
  const WebDavFolderPickerScreen({
    super.key,
    required this.accountId,
    required this.purpose,
    this.initialPath = '/',
    this.excludedPath,
    this.accountChoices = const [],
    this.onAccountChanged,
  });

  final String accountId;

  /// 动作名，用于标题与按钮文案（「复制到」/「移动到」）。
  final String purpose;

  final String initialPath;

  /// 不允许选中的路径（移动文件夹时不能把它移进自己里面）。
  final String? excludedPath;

  /// 可切换的上传账号。空列表表示钉死在 [accountId]（复制 / 移动 / 重扫）。
  final List<WebDavAccount> accountChoices;

  /// 用户改了账号时回调。路由仍只返回目录路径，新账号 id 由调用方从这里拿。
  final ValueChanged<String>? onAccountChanged;

  @override
  State<WebDavFolderPickerScreen> createState() =>
      _WebDavFolderPickerScreenState();
}

class _WebDavFolderPickerScreenState extends State<WebDavFolderPickerScreen> {
  /// 目录栈。栈底永远是 `/`，**每一层目录一格**——所以「上一级」和返回键
  /// 都是一格一格退，而不是一步回根目录。
  final List<String> _stack = ['/'];
  List<WebDavItem> _items = const [];
  bool _loading = false;
  String? _error;
  late String _accountId;

  String get _path => _stack.last;

  bool get _canSwitchAccount {
    if (widget.accountChoices.length < 2) return false;
    return widget.accountChoices.any((a) => a.id == _accountId);
  }

  @override
  void initState() {
    super.initState();
    _accountId = widget.accountId;
    _stack.addAll(remoteAncestors(widget.initialPath));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 换账号后原路径作废：散页目录在另一个后端上不存在。
  void _switchAccount(String? id) {
    if (id == null || id == _accountId) return;
    setState(() {
      _accountId = id;
      _stack
        ..clear()
        ..add('/');
      _items = const [];
      _error = null;
    });
    widget.onAccountChanged?.call(id);
    _load();
  }

  /// 当前位置是否就是被排除的那个目录（移动文件夹时不能选它）。
  bool get _isExcluded {
    final ex = widget.excludedPath;
    if (ex == null) return false;
    final here = _path.endsWith('/') ? _path : '$_path/';
    final target = ex.endsWith('/') ? ex : '$ex/';
    return here == target;
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<WebDavService>().listDirectory(
        _accountId,
        _path,
      );
      if (!mounted) return;
      setState(() {
        _items = items.where((e) => e.isDirectory).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = webDavErrorMessage(e, AppLocalizations.of(context)!);
        _loading = false;
        _items = const [];
      });
    }
  }

  void _enter(WebDavItem dir) {
    _stack.add(dir.path);
    _load();
  }

  /// 返回上一层；已经在根目录时返回 false，让调用方去关界面。
  bool _goUp() {
    if (_stack.length <= 1) return false;
    _stack.removeLast();
    _load();
    return true;
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.newFolder),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.nameLabel,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final parent = _path.endsWith('/') ? _path : '$_path/';
    await runWebDavAction(context, () async {
      await context.read<WebDavService>().createFolder(
        _accountId,
        '$parent$name',
      );
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_goUp()) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            // 左上角是「关闭选择器」，不是「上一级」——上一级在右上角，两者
            // 混用会让人以为退出了、其实只是上了一层目录。
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l10n.folderPickerTitle(
              widget.purpose,
              folderDisplayName(_path, rootLabel: l10n.rootFolder),
            ),
          ),
          actions: [
            IconButton(
              key: const Key('picker-up'),
              icon: const Icon(Icons.arrow_upward),
              tooltip: l10n.parentFolder,
              onPressed: _stack.length > 1
                  ? () => setState(() => _goUp())
                  : null,
            ),
            // 新建文件夹按「创建文件夹」能力遮罩（99 §7.2.6）：无能力直接隐藏。
            if (context.read<WebDavService>().can(
              _accountId,
              AccountCaps.mkdir,
            ))
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: AppLocalizations.of(context)!.newFolder,
                onPressed: _createFolder,
              ),
          ],
        ),
        body: Column(
          children: [
            if (_canSwitchAccount)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  // ignore: deprecated_member_use
                  value: _accountId,
                  decoration: InputDecoration(
                    labelText: l10n.currentServer,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final a in widget.accountChoices)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          webDavAccountLabel(a, l10n),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _switchAccount,
                ),
              ),
            // 路径是次要信息：只留末级，颜色跟当前方案的 onSurfaceVariant。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MetaText(
                  folderDisplayName(_path, rootLabel: l10n.rootFolder),
                ),
              ),
            ),
            Expanded(child: _buildList()),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(AppLocalizations.of(context)!.close),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isExcluded
                            ? null
                            : () => Navigator.of(context).pop(_path),
                        child: Text(
                          AppLocalizations.of(context)!.pickThisFolder,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
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
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(AppLocalizations.of(context)!.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.noSubfolders));
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final dir = _items[i];
        return ListTile(
          leading: const Icon(Icons.folder_rounded, color: AppColors.accent),
          title: Text(dir.name),
          onTap: () => _enter(dir),
        );
      },
    );
  }
}

/// 复制 / 移动一个或多个条目到用户选定的远端文件夹。
///
/// 行为约定：
/// - 目标文件夹由 [WebDavFolderPickerScreen] 选出，可以就是当前目录。
/// - **同名冲突自动改名**（`name (1).ext`），绝不静默覆盖：WebDAV 的
///   `Overwrite: T` 会把目标端旧文件直接抹掉，那是不可逆的，不该藏在
///   一个「复制」按钮后面。
/// - 移动文件夹时不允许把它移进自己或自己的子目录（选择器禁用当前位置）。
Future<void> copyOrMoveItems(
  BuildContext context, {
  required List<WebDavItem> items,
  required bool move,
  required String accountId,
  required String currentPath,
  required Future<void> Function() onDone,
}) async {
  if (items.isEmpty) return;
  final purpose = move
      ? AppLocalizations.of(context)!.moveTo
      : AppLocalizations.of(context)!.copyTo;
  final onlyDir = items.length == 1 && items.first.isDirectory;

  final target = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => WebDavFolderPickerScreen(
        accountId: accountId,
        purpose: purpose,
        initialPath: currentPath,
        excludedPath: onlyDir ? items.first.path : null,
      ),
    ),
  );
  if (target == null || !context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  final webDav = context.read<WebDavService>();
  final done = <String>[];
  final failed = <String>[];
  for (final item in items) {
    try {
      final dest = await resolveAvailableRemotePath(
        webDav: webDav,
        accountId: accountId,
        folderPath: target,
        name: item.name,
        isDirectory: item.isDirectory,
      );
      if (move) {
        await webDav.movePath(accountId, item.path, dest);
      } else {
        await webDav.copyPath(accountId, item.path, dest);
      }
      done.add(item.name);
    } catch (e) {
      failed.add(l10n.itemWithMessage(item.name, webDavErrorMessage(e, l10n)));
    }
  }
  if (!context.mounted) return;

  if (failed.isEmpty) {
    AppSnack.show(
      context,
      move ? l10n.movedItems(done.length) : l10n.copiedItems(done.length),
    );
  } else if (done.isEmpty) {
    AppSnack.error(context, l10n.failedWith(failed.first));
  } else {
    AppSnack.error(
      context,
      l10n.movePartialResult(done.length, failed.length, failed.first),
    );
  }
  await onDone();
}

/// 在 [folderPath] 里给 [name] 找一个不冲突的名字。
///
/// 只在目标目录里已经存在同名条目时才加 ` (n)` 后缀；列目录失败时不猜，
/// 直接沿用原名（让服务端决定，通常报 412 / 409，用户能看到原因）。
Future<String> resolveAvailableRemotePath({
  required WebDavService webDav,
  required String accountId,
  required String folderPath,
  required String name,
  required bool isDirectory,
}) async {
  final parent = folderPath.endsWith('/') ? folderPath : '$folderPath/';
  List<WebDavItem> existing;
  try {
    existing = await webDav.listDirectory(accountId, folderPath);
  } catch (_) {
    return '$parent$name';
  }
  final taken = existing.map((e) => e.name).toSet();
  if (!taken.contains(name)) return '$parent$name';

  final dot = name.lastIndexOf('.');
  final hasExt = !isDirectory && dot > 0;
  final base = hasExt ? name.substring(0, dot) : name;
  final ext = hasExt ? name.substring(dot) : '';
  for (var i = 1; i < 1000; i++) {
    final candidate = '$base ($i)$ext';
    if (!taken.contains(candidate)) return '$parent$candidate';
  }
  return '$parent$name';
}


/// Pick a single music file for library redirect.
Future<WebDavItem?> pickWebDavFile(
  BuildContext context, {
  required String accountId,
  bool musicOnly = true,
  String initialPath = '/',
}) {
  return Navigator.of(context).push<WebDavItem>(
    MaterialPageRoute(
      builder: (_) => _WebDavFilePickerScreen(
        accountId: accountId,
        musicOnly: musicOnly,
        initialPath: initialPath,
      ),
    ),
  );
}

class _WebDavFilePickerScreen extends StatefulWidget {
  const _WebDavFilePickerScreen({
    required this.accountId,
    required this.musicOnly,
    required this.initialPath,
  });

  final String accountId;
  final bool musicOnly;
  final String initialPath;

  @override
  State<_WebDavFilePickerScreen> createState() =>
      _WebDavFilePickerScreenState();
}

class _WebDavFilePickerScreenState extends State<_WebDavFilePickerScreen> {
  final List<String> _stack = ['/'];
  List<WebDavItem> _items = const [];
  bool _loading = false;
  String? _error;

  String get _path => _stack.last;

  @override
  void initState() {
    super.initState();
    _stack.addAll(remoteAncestors(widget.initialPath));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<WebDavService>().listDirectory(
        widget.accountId,
        _path,
      );
      if (!mounted) return;
      setState(() {
        _items = items
            .where(
              (e) =>
                  e.isDirectory ||
                  !widget.musicOnly ||
                  e.category == FileCategory.music,
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = webDavErrorMessage(e, AppLocalizations.of(context)!);
        _loading = false;
        _items = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remoteMissingRedirect),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _items.length + (_stack.length > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_stack.length > 1 && i == 0) {
                      return ListTile(
                        leading: const Icon(Icons.arrow_upward),
                        title: Text(l10n.parentFolder),
                        onTap: () {
                          _stack.removeLast();
                          _load();
                        },
                      );
                    }
                    final item = _items[i - (_stack.length > 1 ? 1 : 0)];
                    if (item.isDirectory) {
                      return ListTile(
                        leading: const Icon(
                          Icons.folder_rounded,
                          color: AppColors.accent,
                        ),
                        title: Text(item.name),
                        onTap: () {
                          _stack.add(item.path);
                          _load();
                        },
                      );
                    }
                    return ListTile(
                      leading: const Icon(Icons.audiotrack),
                      title: Text(item.name),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
    );
  }
}


/// 通用「选账号 + 选远端目录」入口（单屏）。
///
/// 在同一个 [WebDavFolderPickerScreen] 页面内完成账号切换与目录浏览。
/// [accounts] 应已按能力过滤好（调用方用 [WebDavService.can] 筛选）。
///
/// 返回选定的账号 id 与目录路径；任一步取消返回 null。
Future<({String accountId, String path})?> pickRemoteDestination(
  BuildContext context, {
  required List<WebDavAccount> accounts,
  required String purpose,
  String? initialAccountId,
  String? initialPath,
}) async {
  if (accounts.isEmpty) return null;
  final startId = initialAccountId ?? accounts.first.id;
  String resolvedAccountId = startId;
  final path = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => WebDavFolderPickerScreen(
        accountId: startId,
        purpose: purpose,
        initialPath: initialPath ?? '/',
        accountChoices: accounts,
        onAccountChanged: (id) => resolvedAccountId = id,
      ),
    ),
  );
  if (path == null) return null;
  return (accountId: resolvedAccountId, path: path);
}
