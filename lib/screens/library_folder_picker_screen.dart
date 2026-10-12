import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/user_folder.dart';
import '../services/user_folder_service.dart';

/// Destination picker for user folders. Defaults to virtual root 「我的文件夹」.
///
/// Returns the selected folder id, or `''` for the virtual root (callers that
/// need a real folder should create under root first). Cancel → null.
class LibraryFolderPickerScreen extends StatefulWidget {
  const LibraryFolderPickerScreen({
    super.key,
    required this.purpose,
    this.initialFolderId,
    this.excludedFolderId,
  });

  final String purpose;
  final String? initialFolderId;
  final String? excludedFolderId;

  @override
  State<LibraryFolderPickerScreen> createState() =>
      _LibraryFolderPickerScreenState();
}

class _LibraryFolderPickerScreenState extends State<LibraryFolderPickerScreen> {
  /// Stack of folder ids; null sentinel at bottom = virtual root.
  final List<String?> _stack = [null];

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  String? get _currentId => _stack.last;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Move the breadcrumb stack to [folderId] so the picker lands on it.
  void _jumpTo(String folderId) {
    final folders = context.read<UserFolderService>();
    final chain = <String>[];
    var id = folderId;
    final guard = <String>{};
    while (id.isNotEmpty && guard.add(id)) {
      final f = folders.folderById(id);
      if (f == null) break;
      chain.add(f.id);
      id = f.parentId ?? '';
    }
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _stack
        ..clear()
        ..add(null)
        ..addAll(chain.reversed);
    });
  }

  @override
  void initState() {
    super.initState();
    final start = widget.initialFolderId;
    if (start != null && start.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final folders = context.read<UserFolderService>();
        final chain = <String>[];
        var id = start;
        final guard = <String>{};
        while (id.isNotEmpty && guard.add(id)) {
          final f = folders.folderById(id);
          if (f == null) break;
          chain.add(f.id);
          id = f.parentId ?? '';
        }
        setState(() {
          _stack
            ..clear()
            ..add(null)
            ..addAll(chain.reversed);
        });
      });
    }
  }

  bool _isExcluded(String? id) {
    final ex = widget.excludedFolderId;
    if (ex == null || id == null) return false;
    if (id == ex) return true;
    final folders = context.read<UserFolderService>();
    var cur = folders.folderById(id);
    final guard = <String>{};
    while (cur != null && guard.add(cur.id)) {
      if (cur.id == ex) return true;
      cur = cur.parentId == null ? null : folders.folderById(cur.parentId!);
    }
    return false;
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: l10n.newFolderDefaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.newFolderDefaultName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final folder = await context.read<UserFolderService>().createFolder(
          parentId: _currentId,
          name: name.isEmpty ? l10n.newFolderDefaultName : name,
        );
    setState(() => _stack.add(folder.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final folders = context.watch<UserFolderService>();
    final children = folders.childrenOf(_currentId);
    final path = folders.pathDisplay(_currentId);
    final q = _query.trim().toLowerCase();
    final matches = <UserFolder>[];
    if (q.isNotEmpty) {
      for (final f in folders.folders) {
        if (f.name.toLowerCase().contains(q)) matches.add(f);
      }
      matches.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    final excludedHere = _isExcluded(_currentId);
    // Virtual root cannot hold items — confirm only when inside a real folder,
    // or allow confirming root and let caller create. Product: leaf holds items;
    // picker may confirm any real folder (including empty).
    final canConfirm = _currentId != null && !excludedHere;

    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_stack.length > 1) {
          setState(() => _stack.removeLast());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.cancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(widget.purpose),
          actions: [
            IconButton(
              tooltip: l10n.parentFolder,
              icon: const Icon(Icons.arrow_upward),
              onPressed: _stack.length <= 1
                  ? null
                  : () => setState(() => _stack.removeLast()),
            ),
            IconButton(
              tooltip: l10n.newFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createFolder,
            ),
            TextButton(
              onPressed: canConfirm
                  ? () => Navigator.of(context).pop(_currentId)
                  : null,
              child: Text(l10n.confirm),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                          ),
                      child: Text(path),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: l10n.folderSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.cancel,
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: q.isNotEmpty
                  ? (matches.isEmpty
                        ? Center(child: Text(l10n.libraryEmpty))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, i) {
                              final f = matches[i];
                              final blocked = _isExcluded(f.id);
                              return ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(f.name),
                                subtitle: Text(folders.pathDisplay(f.id)),
                                trailing: const Icon(Icons.chevron_right),
                                enabled: !blocked,
                                onTap: blocked
                                    ? null
                                    : () => _jumpTo(f.id),
                              );
                            },
                          ))
                  : children.isEmpty
                  ? Center(
                      child: Text(
                        excludedHere
                            ? l10n.folderPickerExcluded
                            : l10n.folderEmptyHint,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: children.length,
                      itemBuilder: (context, i) {
                        final f = children[i];
                        final blocked = _isExcluded(f.id);
                        return ListTile(
                          leading: Icon(
                            Icons.folder_outlined,
                            color: blocked
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.38)
                                : null,
                          ),
                          title: Text(f.name),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: !blocked,
                          onTap: blocked
                              ? null
                              : () => setState(() => _stack.add(f.id)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
