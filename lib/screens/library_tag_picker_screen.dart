import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_tag_dimension.dart';
import '../models/library_track.dart';
import '../services/library_service.dart';
import '../utils/selection_controller.dart';
import '../widgets/meta_text.dart';
import '../widgets/selection_toolbar.dart';

/// Flat multi-select picker with search for album / artist / track (99 §18.2).
///
/// Tag-like kinds use [LibraryTagDimension]; [UserFolderRefKind.track] lists
/// tracks by `music_id`. Future dimensions plug the same shell.
class LibraryTagPickerScreen extends StatefulWidget {
  const LibraryTagPickerScreen({
    super.key,
    required this.refKind,
    required this.title,
  });

  final String refKind;
  final String title;

  @override
  State<LibraryTagPickerScreen> createState() => _LibraryTagPickerScreenState();
}

class _LibraryTagPickerScreenState extends State<LibraryTagPickerScreen> {
  final _searchCtrl = TextEditingController();
  SelectionController _selection = const SelectionController(active: true);
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final library = context.watch<LibraryService>();
    final entries = _entries(library, l10n);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? entries
        : [
            for (final e in entries)
              if (e.title.toLowerCase().contains(q) ||
                  (e.subtitle?.toLowerCase().contains(q) ?? false))
                e,
          ];
    final keys = [for (final e in filtered) e.key];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.searchPlaceholder,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _selection.selected.isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      _selection.selected.toList(growable: false),
                    ),
            child: Text(
              '${l10n.confirm}'
              '${_selection.selected.isEmpty ? '' : ' (${_selection.count})'}',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SelectionToolbar(
            children: [
              TextButton.icon(
                onPressed: keys.isEmpty
                    ? null
                    : () => setState(
                          () => _selection = _selection.toggleSelectAll(keys),
                        ),
                icon: Icon(
                  _selection.isAllSelected ? Icons.close : Icons.select_all,
                ),
                label: Text(
                  _selection.isAllSelected ? l10n.cancel : l10n.selectAll,
                ),
              ),
            ],
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(l10n.libraryEmpty))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      final selected = _selection.contains(e.key);
                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(e.title),
                        subtitle: e.subtitle == null
                            ? null
                            : MetaText(e.subtitle!),
                        onTap: () {
                          // Keep picker active even when selection empties.
                          final next = {..._selection.selected};
                          if (!next.remove(e.key)) next.add(e.key);
                          setState(() {
                            _selection = SelectionController(
                              active: true,
                              selected: next,
                              total: keys.length,
                            );
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_PickerEntry> _entries(LibraryService library, AppLocalizations l10n) {
    if (widget.refKind == UserFolderRefKind.track) {
      final list = [
        for (final t in library.tracks)
          _PickerEntry(
            key: t.musicId,
            title: t.displayTitle,
            subtitle:
                '${t.displayArtistFor(l10n)} · ${t.displayAlbumFor(l10n)}',
          ),
      ];
      list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      return list;
    }
    final dim = LibraryTagDimension.byId(widget.refKind);
    if (dim == null) return const [];
    final groups = <String, List<LibraryTrack>>{};
    for (final t in library.tracks) {
      groups.putIfAbsent(dim.groupKey(t), () => []).add(t);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final k in keys)
        _PickerEntry(
          key: k,
          title: dim.displayName(l10n, k),
          subtitle: l10n.playlistTrackCount(groups[k]!.length),
        ),
    ];
  }
}

class _PickerEntry {
  const _PickerEntry({
    required this.key,
    required this.title,
    this.subtitle,
  });
  final String key;
  final String title;
  final String? subtitle;
}
