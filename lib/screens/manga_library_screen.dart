// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/folder_view_mode.dart';
import '../models/manga.dart';
import '../models/manga_read_mode.dart';
import '../models/manga_series.dart';
import '../services/accounts_service.dart';
import '../services/cache_service.dart';
import '../services/manga_library_service.dart';
import '../services/manga_reader_prep.dart';
import '../services/settings_service.dart';
import '../services/task_queue_service.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import '../utils/selection_controller.dart';
import '../widgets/manga_cover_art.dart';
import '../widgets/selection_toolbar.dart';
import 'home_shell.dart';
import 'image_viewer_screen.dart';

/// Manga library: 系列 / 单本 / 作者 (99 §19).
class MangaLibraryScreen extends StatefulWidget {
  const MangaLibraryScreen({super.key});

  @override
  State<MangaLibraryScreen> createState() => _MangaLibraryScreenState();
}

class _MangaLibraryScreenState extends State<MangaLibraryScreen> {
  int _segment = 0; // default 系列
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  static const _tabKeys = ['series', 'manga', 'author'];

  String get _tabKey => _tabKeys[_segment.clamp(0, 2)];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mangaLib = context.watch<MangaLibraryService>();
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    final viewMode = settings.mangaViewModeFor(_tabKey);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: _searchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.searchPlaceholder,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(l10n.mangaLibrary),
        actions: [
          PopupMenuButton<FolderViewMode>(
            tooltip: l10n.mangaViewMode,
            icon: Icon(viewMode.isGrid ? Icons.grid_view : Icons.view_list),
            onSelected: (mode) => settings.setMangaViewMode(_tabKey, mode),
            itemBuilder: (context) => [
              for (final mode in FolderViewMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Row(
                    children: [
                      Icon(
                        viewMode == mode
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(mode.label(l10n)),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: _searchOpen ? l10n.closeSearch : l10n.searchAction,
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchCtrl.clear();
                  _query = '';
                }
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(l10n.mangaTabSeries)),
                ButtonSegment(value: 1, label: Text(l10n.mangaTabManga)),
                ButtonSegment(value: 2, label: Text(l10n.mangaTabAuthor)),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
        ),
      ),
      body: mangaLib.count == 0 && _query.trim().isEmpty
          ? _MangaEmpty()
          : switch (_segment) {
              0 => _SeriesList(query: _query, viewMode: viewMode),
              2 => _AuthorList(query: _query, viewMode: viewMode),
              _ => _MangaList(query: _query, viewMode: viewMode),
            },
    );
  }
}

class _MangaEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context)!.mangaLibraryEmptyGuide,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MangaList extends StatefulWidget {
  const _MangaList({required this.query, required this.viewMode});
  final String query;
  final FolderViewMode viewMode;

  @override
  State<_MangaList> createState() => _MangaListState();
}

class _MangaListState extends State<_MangaList> {
  SelectionController _selection = const SelectionController();

  List<Manga> _filtered(MangaLibraryService svc) => svc.search(widget.query);

  void _setSelection(SelectionController next) =>
      setState(() => _selection = next);

  Future<void> _batchSetSeries() async {
    final svc = context.read<MangaLibraryService>();
    final done = await _assignSeriesToMangas(context, _selectedMangas(svc));
    if (done && mounted) _setSelection(_selection.exit());
  }

  List<Manga> _selectedMangas(MangaLibraryService svc) => [
    for (final m in _filtered(svc))
      if (_selection.selected.contains(m.id)) m,
  ];

  Future<void> _batchClearCache() async {
    final svc = context.read<MangaLibraryService>();
    final targets = _selectedMangas(svc);
    if (targets.isEmpty) return;
    await _clearMangaCacheFor(context, targets);
    if (!mounted) return;
    _setSelection(_selection.exit());
  }

  Future<void> _batchDelete() async {
    final svc = context.read<MangaLibraryService>();
    final targets = _selectedMangas(svc);
    if (targets.isEmpty) return;
    final done = await _deleteMangasFor(context, targets);
    if (done && mounted) _setSelection(_selection.exit());
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
    final all = _filtered(svc);
    final unspecified = [
      for (final m in all)
        if (svc.isUnspecifiedSeries(m)) m,
    ];
    final withSeries = [
      for (final m in all)
        if (!svc.isUnspecifiedSeries(m)) m,
    ];
    final keys = [for (final m in all) m.id];
    _selection = _selection.sync(total: keys.length, validKeys: keys);

    if (all.isEmpty) {
      return Center(child: Text(l10n.libraryNoMatch));
    }

    return Column(
      children: [
        if (_selection.active)
          _mangaSelectionToolbar(
            context,
            selection: _selection,
            keys: keys,
            onChange: _setSelection,
            onAssignSeries: _batchSetSeries,
            onClearCache: _batchClearCache,
            onDelete: _batchDelete,
          ),
        Expanded(
          child: widget.viewMode.isGrid
              ? _MangaGridBody(
                  columns: widget.viewMode.crossAxisCount!,
                  unspecified: unspecified,
                  withSeries: withSeries,
                  selection: _selection,
                  onToggle: (id) => _setSelection(_selection.toggle(id)),
                  onEnter: (id) => _setSelection(
                    _selection
                        .enter(id, selectOnly: keys)
                        .sync(total: keys.length, validKeys: keys),
                  ),
                  onOpen: (m) => unawaited(openMangaReader(context, m)),
                  onMore: (m) => _mangaMore(context, m),
                )
              : ListView(
                  children: [
                    if (unspecified.isNotEmpty) ...[
                      _SectionHeader(l10n.mangaUnspecifiedSeries),
                      for (final manga in unspecified)
                        _MangaListTile(
                          manga: manga,
                          selection: _selection,
                          onToggle: () =>
                              _setSelection(_selection.toggle(manga.id)),
                          onEnter: () => _setSelection(
                            _selection
                                .enter(manga.id, selectOnly: keys)
                                .sync(total: keys.length, validKeys: keys),
                          ),
                          onOpen: () =>
                              unawaited(openMangaReader(context, manga)),
                          onMore: () => _mangaMore(context, manga),
                        ),
                    ],
                    if (withSeries.isNotEmpty) ...[
                      if (unspecified.isNotEmpty)
                        _SectionHeader(l10n.mangaTabSeries),
                      for (final manga in withSeries)
                        _MangaListTile(
                          manga: manga,
                          selection: _selection,
                          onToggle: () =>
                              _setSelection(_selection.toggle(manga.id)),
                          onEnter: () => _setSelection(
                            _selection
                                .enter(manga.id, selectOnly: keys)
                                .sync(total: keys.length, validKeys: keys),
                          ),
                          onOpen: () =>
                              unawaited(openMangaReader(context, manga)),
                          onMore: () => _mangaMore(context, manga),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MangaListTile extends StatelessWidget {
  const _MangaListTile({
    required this.manga,
    required this.selection,
    required this.onToggle,
    required this.onEnter,
    required this.onOpen,
    required this.onMore,
  });

  final Manga manga;
  final SelectionController selection;
  final VoidCallback onToggle;
  final VoidCallback onEnter;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final selected = selection.contains(manga.id);
    return ListTile(
      leading: selection.active
          ? Checkbox(value: selected, onChanged: (_) => onToggle())
          : MangaCoverArt(manga: manga, size: 48),
      title: Text(manga.title),
      subtitle: _mangaSubtitle(context, manga),
      selected: selected,
      trailing: selection.active
          ? null
          : IconButton(icon: const Icon(Icons.more_vert), onPressed: onMore),
      onTap: () {
        if (selection.active) {
          onToggle();
          return;
        }
        onOpen();
      },
      onLongPress: onEnter,
    );
  }
}

Widget? _mangaSubtitle(BuildContext context, Manga manga) {
  final l10n = AppLocalizations.of(context)!;
  final progress = context.watch<MangaLibraryService>().progressOf(manga.id);
  final meta = <String>[
    if (manga.displayAuthor.isNotEmpty) manga.displayAuthor,
    ?manga.series,
    if (manga.pageCount > 0)
      progress == null
          ? l10n.mangaPageCount(manga.pageCount)
          : l10n.mangaReadProgress(progress.pageIndex + 1, manga.pageCount),
    manga.format,
  ];
  if (meta.isEmpty) return null;
  return Text(
    meta.join(' · '),
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
    ),
  );
}

class _MangaGridBody extends StatelessWidget {
  const _MangaGridBody({
    required this.columns,
    required this.unspecified,
    required this.withSeries,
    required this.selection,
    required this.onToggle,
    required this.onEnter,
    required this.onOpen,
    required this.onMore,
    this.showSectionHeaders = true,
  });

  final int columns;
  final List<Manga> unspecified;
  final List<Manga> withSeries;
  final SelectionController selection;
  final void Function(String id) onToggle;
  final void Function(String id) onEnter;
  final void Function(Manga) onOpen;
  final void Function(Manga) onMore;

  /// Drill-down pages hold one flat list, so the group titles are dropped
  /// there: "未指定系列" above a series' own books is meaningless.
  final bool showSectionHeaders;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CustomScrollView(
      slivers: [
        if (unspecified.isNotEmpty) ...[
          if (showSectionHeaders)
            SliverToBoxAdapter(
              child: _SectionHeader(l10n.mangaUnspecifiedSeries),
            ),
          _mangaGridSliver(unspecified),
        ],
        if (withSeries.isNotEmpty) ...[
          if (showSectionHeaders && unspecified.isNotEmpty)
            SliverToBoxAdapter(child: _SectionHeader(l10n.mangaTabSeries)),
          _mangaGridSliver(withSeries),
        ],
      ],
    );
  }

  Widget _mangaGridSliver(List<Manga> list) {
    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          final manga = list[i];
          final selected = selection.contains(manga.id);
          return _MangaGridTile(
            manga: manga,
            selected: selection.active && selected,
            selecting: selection.active,
            onTap: () {
              if (selection.active) {
                onToggle(manga.id);
                return;
              }
              onOpen(manga);
            },
            onLongPress: () => onEnter(manga.id),
            onMore: () => onMore(manga),
          );
        }, childCount: list.length),
      ),
    );
  }
}

class _MangaGridTile extends StatelessWidget {
  const _MangaGridTile({
    required this.manga,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final Manga manga;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<MangaLibraryService>().progressOf(manga.id);
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.4)
          : Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: MangaCoverArt(
                      manga: manga,
                      size: 200,
                      borderRadius: 8,
                    ),
                  ),
                  if (!selecting)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: onMore,
                        icon: const Icon(Icons.more_vert),
                      ),
                    ),
                  if (progress != null && manga.pageCount > 0)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (progress.pageIndex / manga.pageCount).clamp(
                            0.0,
                            1.0,
                          ),
                          minHeight: 3,
                          backgroundColor: Colors.black26,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _mangaMore(BuildContext context, Manga manga) async {
  final l10n = AppLocalizations.of(context)!;
  final cache = context.read<CacheService>();
  // Loose-image mangas (class A) carry an explicit page list; they have no
  // whole-file cache and nothing to scrape. Only class B (containers) get
  // those two items.
  final isContainer = manga.format != MangaFormat.images;
  final cached =
      isContainer &&
      cache.hasLocalMangaFile(manga.remotePath, sourceName: manga.sourceName);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.mangaEditMetadata),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          if (isContainer) ...[
            ListTile(
              leading: const Icon(Icons.auto_fix_high_outlined),
              title: Text(l10n.mangaScrapeAction),
              onTap: () => Navigator.pop(ctx, 'scrape'),
            ),
            ListTile(
              leading: Icon(
                cached ? Icons.delete_outline : Icons.download_outlined,
              ),
              title: Text(
                cached ? l10n.mangaClearCache : l10n.mangaCacheAction,
              ),
              subtitle: cached ? Text(l10n.mangaCached) : null,
              onTap: () => Navigator.pop(ctx, cached ? 'clear_cache' : 'cache'),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppColors.error),
            title: Text(
              l10n.destroyAction,
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'edit':
      await _editMangaMetadata(context, manga);
    case 'scrape':
      await _enqueueMangaScrape(context, manga);
    case 'cache':
      await _enqueueMangaCache(context, manga);
    case 'clear_cache':
      await cache.deleteLocalMangaFile(
        sourceName: manga.sourceName,
        remotePath: manga.remotePath,
      );
      if (context.mounted) {
        AppSnack.show(context, l10n.mangaClearCache);
      }
    case 'delete':
      await _deleteManga(context, manga);
  }
}

/// Shared confirmation for the single-item and batch delete paths. Returns
/// false when the user backs out.
Future<bool> _confirmMangaDelete(BuildContext context, int count) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.mangaDeleteTitle),
      content: Text(l10n.mangaDeleteBody(count)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            l10n.destroyAction,
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Removes one manga from the library together with everything cached for it.
Future<void> _deleteManga(BuildContext context, Manga manga) async {
  final l10n = AppLocalizations.of(context)!;
  final svc = context.read<MangaLibraryService>();
  final cache = context.read<CacheService>();
  if (!await _confirmMangaDelete(context, 1)) return;
  await cache.clearMangaArtifacts(
    mangaId: manga.id,
    sourceName: manga.sourceName,
    remotePath: manga.remotePath,
  );
  await svc.deleteManga(manga.id);
  if (context.mounted) AppSnack.show(context, l10n.mangaBatchDeleteDone(1));
}

Future<void> _editMangaMetadata(BuildContext context, Manga manga) async {
  final l10n = AppLocalizations.of(context)!;
  final svc = context.read<MangaLibraryService>();
  final titleCtrl = TextEditingController(text: manga.title);
  final authorCtrl = TextEditingController(text: manga.author ?? '');
  final seriesCtrl = TextEditingController(text: manga.series ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.mangaEditMetadata),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleCtrl,
            decoration: InputDecoration(labelText: l10n.mangaFieldTitle),
          ),
          TextField(
            controller: authorCtrl,
            decoration: InputDecoration(labelText: l10n.mangaFieldAuthor),
          ),
          TextField(
            controller: seriesCtrl,
            decoration: InputDecoration(labelText: l10n.mangaFieldSeries),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.mangaConfirmSave),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await svc.updateMangaMetadata(
    manga.id,
    title: titleCtrl.text,
    author: authorCtrl.text,
    seriesTitle: seriesCtrl.text,
    updateSeries: true,
  );
}

Future<void> _enqueueMangaScrape(BuildContext context, Manga manga) async {
  final l10n = AppLocalizations.of(context)!;
  final accounts = context.read<AccountsService>();
  final accountId = accounts.idForSource(manga.sourceName);
  if (accountId == null || accountId.isEmpty) {
    AppSnack.show(context, l10n.mangaReaderUnboundSource);
    return;
  }
  final queue = context.read<TaskQueueService>();
  await queue.enqueueMangaScrape(
    accountId: accountId,
    sourceName: manga.sourceName,
    remotePath: manga.remotePath,
    displayName: manga.title,
    mangaId: manga.id,
  );
  if (context.mounted) {
    AppSnack.show(context, l10n.mangaScrapeQueued);
  }
}

/// Queue a whole-archive download; a large CBZ must not block the reader.
Future<void> _enqueueMangaCache(BuildContext context, Manga manga) async {
  final l10n = AppLocalizations.of(context)!;
  final accounts = context.read<AccountsService>();
  final accountId = accounts.idForSource(manga.sourceName);
  if (accountId == null || accountId.isEmpty) {
    AppSnack.show(context, l10n.mangaReaderUnboundSource);
    return;
  }
  final queue = context.read<TaskQueueService>();
  await queue.enqueueMangaCache(
    accountId: accountId,
    sourceName: manga.sourceName,
    remotePath: manga.remotePath,
    displayName: manga.title,
    mangaId: manga.id,
  );
  if (context.mounted) {
    AppSnack.show(context, l10n.mangaCacheQueued);
  }
}

/// Series-name prompt that owns its own [TextEditingController].
///
/// The controller must outlive the route: `showDialog` resolves as soon as
/// the route pops, while the dialog is still animating out. Disposing the
/// controller at that moment makes the [TextField] touch a disposed
/// [ChangeNotifier] during teardown, which aborts the element unmount
/// halfway and trips `InheritedElement`'s `_dependents.isEmpty` assertion.
class _SeriesNameDialog extends StatefulWidget {
  const _SeriesNameDialog({
    required this.title,
    required this.hint,
    required this.fieldLabel,
    required this.clearLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.pickLabel,
    required this.suggestions,
  });

  final String title;
  final String hint;
  final String fieldLabel;
  final String clearLabel;
  final String cancelLabel;
  final String confirmLabel;
  final String pickLabel;
  final List<String> suggestions;

  @override
  State<_SeriesNameDialog> createState() => _SeriesNameDialogState();
}

class _SeriesNameDialogState extends State<_SeriesNameDialog> {
  final TextEditingController _controller = TextEditingController();

  /// Mirrors the picker so the box keeps showing what was chosen.
  String? _selected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.fieldLabel),
          ),
          if (widget.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selected,
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.pickLabel),
              items: [
                for (final title in widget.suggestions)
                  DropdownMenuItem(
                    value: title,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (title) {
                if (title == null) return;
                setState(() {
                  _selected = title;
                  _controller.text = title;
                  _controller.selection = TextSelection.collapsed(
                    offset: title.length,
                  );
                });
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(widget.clearLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Ask for a series name and apply it to [targets].
///
/// Returns true once the assignment ran, so callers know whether to leave
/// selection mode.
Future<bool> _assignSeriesToMangas(
  BuildContext context,
  List<Manga> targets,
) async {
  final l10n = AppLocalizations.of(context)!;
  if (targets.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.mangaSelectNone)));
    return false;
  }
  final svc = context.read<MangaLibraryService>();
  final result = await showDialog<String?>(
    context: context,
    builder: (_) => _SeriesNameDialog(
      title: l10n.mangaBatchSetSeriesTitle,
      hint: l10n.mangaBatchSetSeriesHint,
      fieldLabel: l10n.mangaFieldSeries,
      clearLabel: l10n.mangaClearSeries,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.mangaConfirmSave,
      pickLabel: l10n.mangaPickSeries,
      suggestions: [for (final s in svc.series) s.title],
    ),
  );
  if (result == null || !context.mounted) return false;
  final n = await svc.assignSeriesToMangas(
    mangaIds: [for (final m in targets) m.id],
    seriesTitle: result,
  );
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(l10n.mangaBatchSetSeriesDone(n))));
  return true;
}

/// Drops the cached archive, cover and prefetched pages of [targets].
Future<void> _clearMangaCacheFor(
  BuildContext context,
  List<Manga> targets,
) async {
  final l10n = AppLocalizations.of(context)!;
  final cache = context.read<CacheService>();
  var removed = 0;
  for (final m in targets) {
    removed += await cache.clearMangaArtifacts(
      mangaId: m.id,
      sourceName: m.sourceName,
      remotePath: m.remotePath,
    );
  }
  if (!context.mounted) return;
  AppSnack.show(context, l10n.cacheClearedFiles(removed));
}

/// Confirms, then deletes [targets] along with their cached files.
Future<bool> _deleteMangasFor(BuildContext context, List<Manga> targets) async {
  final l10n = AppLocalizations.of(context)!;
  final svc = context.read<MangaLibraryService>();
  final cache = context.read<CacheService>();
  if (!await _confirmMangaDelete(context, targets.length)) return false;
  for (final m in targets) {
    await cache.clearMangaArtifacts(
      mangaId: m.id,
      sourceName: m.sourceName,
      remotePath: m.remotePath,
    );
    await svc.deleteManga(m.id);
  }
  if (!context.mounted) return false;
  AppSnack.show(context, l10n.mangaBatchDeleteDone(targets.length));
  return true;
}

/// Selection toolbar shared by the library list and the series / author
/// drill-downs, so every table offers the same batch actions.
Widget _mangaSelectionToolbar(
  BuildContext context, {
  required SelectionController selection,
  required List<String> keys,
  required ValueChanged<SelectionController> onChange,
  required VoidCallback onAssignSeries,
  required VoidCallback onClearCache,
  required VoidCallback onDelete,
}) {
  final l10n = AppLocalizations.of(context)!;
  return SelectionToolbar(
    children: [
      IconButton(
        tooltip: selection.showsDeselect
            ? l10n.cancelSelection
            : l10n.selectAll,
        onPressed: () => onChange(selection.toggleSelectAll(keys)),
        icon: Icon(selection.showsDeselect ? Icons.deselect : Icons.select_all),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          '${selection.count}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        tooltip: l10n.mangaBatchSetSeries,
        onPressed: onAssignSeries,
        icon: const Icon(Icons.collections_bookmark_outlined),
      ),
      IconButton(
        tooltip: l10n.mangaClearCache,
        onPressed: onClearCache,
        icon: const Icon(Icons.cleaning_services_outlined),
      ),
      IconButton(
        tooltip: l10n.destroyAction,
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline, color: AppColors.error),
      ),
      IconButton(
        tooltip: l10n.cancel,
        onPressed: () => onChange(selection.exit()),
        icon: const Icon(Icons.close),
      ),
    ],
  );
}

class _SeriesList extends StatelessWidget {
  const _SeriesList({required this.query, required this.viewMode});
  final String query;
  final FolderViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
    final q = query.trim().toLowerCase();
    final list = [
      for (final s in svc.series)
        if (q.isEmpty || s.title.toLowerCase().contains(q)) s,
    ];
    if (list.isEmpty) {
      return Center(child: Text(l10n.libraryNoMatch));
    }
    if (viewMode.isGrid) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: viewMode.crossAxisCount!,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.75,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final s = list[i];
          final mangas = svc.mangasForSeries(s.id);
          final cover = mangas.isEmpty ? null : mangas.first;
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _SeriesDetailScreen(series: s),
                  ),
                );
              },
              onLongPress: () => _editSeries(context, s),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: cover == null
                          ? Icon(
                              Icons.collections_bookmark_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 40,
                            )
                          : MangaCoverArt(manga: cover, size: 200),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i];
        final mangas = svc.mangasForSeries(s.id);
        final n = mangas.length;
        final cover = mangas.isEmpty ? null : mangas.first;
        return ListTile(
          leading: cover == null
              ? Icon(
                  Icons.collections_bookmark_outlined,
                  color: Theme.of(context).colorScheme.primary,
                )
              : MangaCoverArt(manga: cover, size: 48),
          title: Text(s.title),
          subtitle: Text(l10n.mangaSeriesCount(n)),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _editSeries(context, s),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _SeriesDetailScreen(series: s)),
            );
          },
        );
      },
    );
  }
}

/// Rename a series: it is the tag on its books, so this re-tags every member.
/// Renaming onto an existing title merges the two; clearing it unbinds them.
Future<void> _editSeries(BuildContext context, MangaSeries series) async {
  final l10n = AppLocalizations.of(context)!;
  final svc = context.read<MangaLibraryService>();
  final titleCtrl = TextEditingController(text: series.title);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.mangaEditSeries),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleCtrl,
            decoration: InputDecoration(labelText: l10n.mangaFieldSeries),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.mangaConfirmSave),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await svc.updateSeriesMetadata(series.id, title: titleCtrl.text);
}

class _AuthorList extends StatelessWidget {
  const _AuthorList({required this.query, required this.viewMode});
  final String query;
  final FolderViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
    final q = query.trim().toLowerCase();
    final list = [
      for (final a in svc.authors)
        if (q.isEmpty || a.toLowerCase().contains(q)) a,
    ];
    if (list.isEmpty) {
      return Center(child: Text(l10n.libraryNoMatch));
    }
    if (viewMode.isGrid) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: viewMode.crossAxisCount!,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final a = list[i];
          final mangas = svc.mangasForAuthor(a);
          final cover = mangas.isEmpty ? null : mangas.first;
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AuthorDetailScreen(author: a),
                  ),
                );
              },
              onLongPress: () => _renameAuthor(context, a),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: cover == null
                          ? Icon(
                              Icons.person_outline,
                              color: Theme.of(context).colorScheme.primary,
                              size: 40,
                            )
                          : MangaCoverArt(manga: cover, size: 200),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      a,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list[i];
        final mangas = svc.mangasForAuthor(a);
        final n = mangas.length;
        final cover = mangas.isEmpty ? null : mangas.first;
        return ListTile(
          leading: cover == null
              ? Icon(
                  Icons.person_outline,
                  color: Theme.of(context).colorScheme.primary,
                )
              : MangaCoverArt(manga: cover, size: 48),
          title: Text(a),
          subtitle: Text(l10n.mangaSeriesCount(n)),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _renameAuthor(context, a),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _AuthorDetailScreen(author: a)),
            );
          },
        );
      },
    );
  }
}

Future<void> _renameAuthor(BuildContext context, String author) async {
  final l10n = AppLocalizations.of(context)!;
  final svc = context.read<MangaLibraryService>();
  final ctrl = TextEditingController(text: author);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.mangaRenameAuthor),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.mangaRenameAuthorHint,
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.mangaFieldAuthor),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.mangaConfirmSave),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await svc.renameAuthor(from: author, to: ctrl.text);
}

/// Series / author drill-down: the library's own rows, multi-select and
/// view mode, scoped to one group.
/// A flat list of books with the library's grid/list toggle and selection bar.
///
/// Series and author drill-downs and the folder browser's series leaf all use
/// this, so a series looks the same wherever it is opened from. [onEdit] is
/// null where there is nothing to rename (a folder just references a series).
class MangaDetailScreen extends StatefulWidget {
  const MangaDetailScreen({
    super.key,
    required this.title,
    required this.viewKey,
    required this.list,
    this.editTooltip,
    this.onEdit,
  });

  final String title;

  /// Persisted view-mode slot, so each drill-down remembers its own choice.
  final String viewKey;
  final List<Manga> list;
  final String? editTooltip;
  final VoidCallback? onEdit;

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  SelectionController _selection = const SelectionController();

  void _setSelection(SelectionController next) =>
      setState(() => _selection = next);

  List<Manga> get _targets => [
    for (final m in widget.list)
      if (_selection.selected.contains(m.id)) m,
  ];

  Future<void> _assignSeries() async {
    final done = await _assignSeriesToMangas(context, _targets);
    if (done && mounted) _setSelection(_selection.exit());
  }

  Future<void> _clearCache() async {
    final targets = _targets;
    if (targets.isEmpty) return;
    await _clearMangaCacheFor(context, targets);
    if (!mounted) return;
    _setSelection(_selection.exit());
  }

  Future<void> _delete() async {
    final targets = _targets;
    if (targets.isEmpty) return;
    final done = await _deleteMangasFor(context, targets);
    if (done && mounted) _setSelection(_selection.exit());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final viewMode = settings.mangaViewModeFor(widget.viewKey);
    final list = widget.list;
    final keys = [for (final m in list) m.id];
    _selection = _selection.sync(total: keys.length, validKeys: keys);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<FolderViewMode>(
            tooltip: l10n.mangaViewMode,
            icon: Icon(viewMode.isGrid ? Icons.grid_view : Icons.view_list),
            onSelected: (mode) =>
                settings.setMangaViewMode(widget.viewKey, mode),
            itemBuilder: (context) => [
              for (final mode in FolderViewMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Row(
                    children: [
                      Icon(
                        viewMode == mode
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(mode.label(l10n)),
                    ],
                  ),
                ),
            ],
          ),
          if (widget.onEdit != null)
            IconButton(
              tooltip: widget.editTooltip,
              icon: const Icon(Icons.edit_outlined),
              onPressed: widget.onEdit,
            ),
        ],
      ),
      body: list.isEmpty
          ? Center(child: Text(l10n.libraryNoMatch))
          : Column(
              children: [
                if (_selection.active)
                  _mangaSelectionToolbar(
                    context,
                    selection: _selection,
                    keys: keys,
                    onChange: _setSelection,
                    onAssignSeries: _assignSeries,
                    onClearCache: _clearCache,
                    onDelete: _delete,
                  ),
                Expanded(
                  child: viewMode.isGrid
                      ? _MangaGridBody(
                          columns: viewMode.crossAxisCount!,
                          unspecified: list,
                          withSeries: const [],
                          showSectionHeaders: false,
                          selection: _selection,
                          onToggle: (id) =>
                              _setSelection(_selection.toggle(id)),
                          onEnter: (id) => _setSelection(
                            _selection
                                .enter(id, selectOnly: keys)
                                .sync(total: keys.length, validKeys: keys),
                          ),
                          onOpen: (m) => unawaited(openMangaReader(context, m)),
                          onMore: (m) => _mangaMore(context, m),
                        )
                      : ListView(
                          children: [
                            for (final manga in list)
                              _MangaListTile(
                                manga: manga,
                                selection: _selection,
                                onToggle: () =>
                                    _setSelection(_selection.toggle(manga.id)),
                                onEnter: () => _setSelection(
                                  _selection
                                      .enter(manga.id, selectOnly: keys)
                                      .sync(
                                        total: keys.length,
                                        validKeys: keys,
                                      ),
                                ),
                                onOpen: () =>
                                    unawaited(openMangaReader(context, manga)),
                                onMore: () => _mangaMore(context, manga),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class _SeriesDetailScreen extends StatelessWidget {
  const _SeriesDetailScreen({required this.series});
  final MangaSeries series;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
    return MangaDetailScreen(
      title: series.title,
      viewKey: 'seriesDetail',
      list: svc.mangasForSeries(series.id),
      editTooltip: l10n.mangaEditSeries,
      onEdit: () => _editSeries(context, series),
    );
  }
}

class _AuthorDetailScreen extends StatelessWidget {
  const _AuthorDetailScreen({required this.author});
  final String author;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
    return MangaDetailScreen(
      title: author,
      viewKey: 'authorDetail',
      list: svc.mangasForAuthor(author),
      editTooltip: l10n.mangaRenameAuthor,
      onEdit: () => _renameAuthor(context, author),
    );
  }
}

Future<void> openMangaReader(
  BuildContext context,
  Manga manga, {

  /// Overrides [SettingsService.mangaReadMode] for this one open.
  bool? forceFullCache,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final accounts = context.read<AccountsService>();
  final accountId = accounts.idForSource(manga.sourceName);
  if (accountId == null || accountId.isEmpty) {
    AppSnack.show(context, l10n.mangaReaderUnboundSource);
    return;
  }
  final mangaLib = context.read<MangaLibraryService>();
  final webDav = context.read<WebDavService>();
  final cache = context.read<CacheService>();
  final settings = context.read<SettingsService>();
  // Stream unless the user asked for the whole file up front. The Range
  // probe still runs first, so an unsupported driver is reported instead
  // of silently turning into a download.
  final cacheFirst =
      forceFullCache ?? (settings.mangaReadMode == MangaReadMode.cache);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.mangaReaderPreparing)),
          ],
        ),
      ),
    ),
  );

  try {
    final prepared = await MangaReaderPrep.prepare(
      manga: manga,
      accountId: accountId,
      webDav: webDav,
      mangaLib: mangaLib,
      cache: cache,
      forceFullCache: cacheFirst,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dialog
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen.pages(
          accountId: accountId,
          pages: prepared.pages,
          initialIndex: prepared.initialIndex,
          title: prepared.manga.title,
          mangaId: prepared.manga.id,
          onPageChanged: (i) {
            unawaited(mangaLib.setProgress(prepared.manga.id, i));
          },
        ),
      ),
    );
  } on MangaReaderPrepareException catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (e.kind == MangaReaderPrepareError.rangeUnsupported) {
      // Streaming failed: say so, and offer to make caching the default so
      // the next open does not stall on the same probe again.
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.mangaRangeUnsupportedTitle),
          content: Text(l10n.mangaRangeUnsupportedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.mangaRangeUnsupportedRemember),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.mangaRangeUnsupportedCache),
            ),
          ],
        ),
      );
      if (go == null) return;
      if (!go) await settings.setMangaReadMode(MangaReadMode.cache);
      if (context.mounted) {
        await openMangaReader(context, manga, forceFullCache: true);
      }
      return;
    }
    final msg = switch (e.kind) {
      MangaReaderPrepareError.unsupported => l10n.mangaReaderUnsupported,
      MangaReaderPrepareError.empty => l10n.mangaPagesNotReady,
      MangaReaderPrepareError.unbound => l10n.mangaReaderUnboundSource,
      MangaReaderPrepareError.failed => e.detail ?? l10n.mangaReaderUnsupported,
      MangaReaderPrepareError.rangeUnsupported =>
        l10n.mangaRangeUnsupportedTitle,
    };
    AppSnack.show(context, msg);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    AppSnack.error(context, e.toString());
  }
}
