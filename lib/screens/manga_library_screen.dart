// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import '../models/manga_series.dart';
import '../services/manga_library_service.dart';
import '../utils/selection_controller.dart';
import '../widgets/selection_toolbar.dart';
import 'home_shell.dart';

/// Manga library: 系列 / 单本 / 作者 (99 §19).
class MangaLibraryScreen extends StatefulWidget {
  const MangaLibraryScreen({super.key});

  @override
  State<MangaLibraryScreen> createState() => _MangaLibraryScreenState();
}

class _MangaLibraryScreenState extends State<MangaLibraryScreen> {
  int _segment = 1; // default 单本
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mangaLib = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
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
              0 => _SeriesList(query: _query),
              2 => _AuthorList(query: _query),
              _ => _MangaList(query: _query),
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
  const _MangaList({required this.query});
  final String query;

  @override
  State<_MangaList> createState() => _MangaListState();
}

class _MangaListState extends State<_MangaList> {
  SelectionController _selection = const SelectionController();

  List<Manga> _filtered(MangaLibraryService svc) => svc.search(widget.query);

  void _setSelection(SelectionController next) =>
      setState(() => _selection = next);

  Future<void> _batchSetSeries() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selection.count == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mangaSelectNone)));
      return;
    }
    final svc = context.read<MangaLibraryService>();
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mangaBatchSetSeriesTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mangaBatchSetSeriesHint,
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.mangaFieldSeries),
            ),
            if (svc.series.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in svc.series)
                    ActionChip(
                      label: Text(s.title),
                      onPressed: () => Navigator.pop(ctx, s.title),
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(l10n.mangaClearSeries),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.mangaConfirmSave),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final n = await svc.assignSeriesToMangas(
      mangaIds: _selection.selected.toList(),
      seriesTitle: result,
    );
    if (!mounted) return;
    _setSelection(_selection.exit());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.mangaBatchSetSeriesDone(n))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final l10n = AppLocalizations.of(context)!;
    final list = _filtered(svc);
    final keys = [for (final m in list) m.id];
    _selection = _selection.sync(total: keys.length, validKeys: keys);

    if (list.isEmpty) {
      return Center(child: Text(l10n.libraryNoMatch));
    }

    return Column(
      children: [
        if (_selection.active)
          SelectionToolbar(
            children: [
              if (_selection.showsDeselect)
                IconButton(
                  tooltip: l10n.cancelSelection,
                  onPressed: () =>
                      _setSelection(_selection.toggleSelectAll(keys)),
                  icon: const Icon(Icons.deselect),
                )
              else
                IconButton(
                  tooltip: l10n.selectAll,
                  onPressed: () =>
                      _setSelection(_selection.toggleSelectAll(keys)),
                  icon: const Icon(Icons.select_all),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${_selection.count}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: l10n.mangaBatchSetSeries,
                onPressed: _batchSetSeries,
                icon: const Icon(Icons.collections_bookmark_outlined),
              ),
              IconButton(
                tooltip: l10n.cancel,
                onPressed: () => _setSelection(_selection.exit()),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final manga = list[i];
              final selected = _selection.contains(manga.id);
              return ListTile(
                leading: _selection.active
                    ? Checkbox(
                        value: selected,
                        onChanged: (_) =>
                            _setSelection(_selection.toggle(manga.id)),
                      )
                    : Icon(
                        Icons.menu_book_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                title: Text(manga.title),
                subtitle: _mangaSubtitle(context, manga),
                selected: selected,
                onTap: () {
                  if (_selection.active) {
                    _setSelection(_selection.toggle(manga.id));
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MangaReaderStubScreen(manga: manga),
                    ),
                  );
                },
                onLongPress: () {
                  _setSelection(
                    _selection
                        .enter(manga.id, selectOnly: keys)
                        .sync(total: keys.length, validKeys: keys),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget? _mangaSubtitle(BuildContext context, Manga manga) {
    final l10n = AppLocalizations.of(context)!;
    final meta = <String>[
      if (manga.displayAuthor.isNotEmpty) manga.displayAuthor,
      if (manga.pageCount > 0) l10n.mangaPageCount(manga.pageCount),
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
}

class _SeriesList extends StatelessWidget {
  const _SeriesList({required this.query});
  final String query;

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
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i];
        final n = svc.mangasForSeries(s.id).length;
        return ListTile(
          leading: Icon(
            Icons.collections_bookmark_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(s.title),
          subtitle: Text(l10n.mangaSeriesCount(n)),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _SeriesDetailScreen(series: s),
              ),
            );
          },
        );
      },
    );
  }
}

class _AuthorList extends StatelessWidget {
  const _AuthorList({required this.query});
  final String query;

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
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list[i];
        final n = svc.mangasForAuthor(a).length;
        return ListTile(
          leading: Icon(
            Icons.person_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(a),
          subtitle: Text(l10n.mangaSeriesCount(n)),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _AuthorDetailScreen(author: a),
              ),
            );
          },
        );
      },
    );
  }
}

class _SeriesDetailScreen extends StatelessWidget {
  const _SeriesDetailScreen({required this.series});
  final MangaSeries series;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final list = svc.mangasForSeries(series.id);
    return Scaffold(
      appBar: AppBar(title: Text(series.title)),
      body: list.isEmpty
          ? Center(child: Text(AppLocalizations.of(context)!.libraryNoMatch))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final manga = list[i];
                return ListTile(
                  leading: Icon(
                    Icons.menu_book_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(manga.title),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MangaReaderStubScreen(manga: manga),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _AuthorDetailScreen extends StatelessWidget {
  const _AuthorDetailScreen({required this.author});
  final String author;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MangaLibraryService>();
    final list = svc.mangasForAuthor(author);
    return Scaffold(
      appBar: AppBar(title: Text(author)),
      body: list.isEmpty
          ? Center(child: Text(AppLocalizations.of(context)!.libraryNoMatch))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final manga = list[i];
                return ListTile(
                  leading: Icon(
                    Icons.menu_book_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(manga.title),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MangaReaderStubScreen(manga: manga),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/// Page-list + progress stub; full chrome deferred.
class MangaReaderStubScreen extends StatefulWidget {
  const MangaReaderStubScreen({super.key, required this.manga});
  final Manga manga;

  @override
  State<MangaReaderStubScreen> createState() => _MangaReaderStubScreenState();
}

class _MangaReaderStubScreenState extends State<MangaReaderStubScreen> {
  List<MangaPage> _pages = const [];
  int _progress = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = context.read<MangaLibraryService>();
    final pages = await svc.pagesFor(widget.manga.id);
    final prog = await svc.progressFor(widget.manga.id);
    if (!mounted) return;
    setState(() {
      _pages = pages;
      _progress = prog?.pageIndex ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.manga.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.mangaPagesNotReady,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    final current = i == _progress;
                    return ListTile(
                      leading: Text(
                        '${page.pageIndex + 1}',
                        style: TextStyle(
                          color: current
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              current ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      title: Text(
                        page.relPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: current,
                      onTap: () async {
                        await context
                            .read<MangaLibraryService>()
                            .setProgress(widget.manga.id, page.pageIndex);
                        if (!mounted) return;
                        setState(() => _progress = page.pageIndex);
                      },
                    );
                  },
                ),
    );
  }
}
