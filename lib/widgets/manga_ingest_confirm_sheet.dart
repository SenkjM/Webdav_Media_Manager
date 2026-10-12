// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/manga_library_service.dart';

/// Confirm / edit metadata before writing a manga ingest draft.
Future<MangaIngestDraft?> showMangaIngestConfirmSheet(
  BuildContext context, {
  required MangaIngestDraft draft,
}) {
  return showDialog<MangaIngestDraft>(
    context: context,
    builder: (ctx) => _MangaIngestConfirmDialog(draft: draft),
  );
}

class _MangaIngestConfirmDialog extends StatefulWidget {
  const _MangaIngestConfirmDialog({required this.draft});
  final MangaIngestDraft draft;

  @override
  State<_MangaIngestConfirmDialog> createState() =>
      _MangaIngestConfirmDialogState();
}

class _MangaIngestConfirmDialogState extends State<_MangaIngestConfirmDialog> {
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _series;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title);
    _author = TextEditingController(text: widget.draft.author ?? '');
    _series = TextEditingController(text: widget.draft.seriesTitle ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _series.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pageHint = widget.draft.pageRelPaths.isEmpty
        ? null
        : l10n.mangaPageCount(widget.draft.pageRelPaths.length);
    return AlertDialog(
      title: Text(l10n.mangaConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: l10n.mangaFieldTitle),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _author,
              decoration: InputDecoration(labelText: l10n.mangaFieldAuthor),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _series,
              decoration: InputDecoration(labelText: l10n.mangaFieldSeries),
            ),
            if (pageHint != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pageHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () {
            widget.draft.title = _title.text.trim();
            widget.draft.author =
                _author.text.trim().isEmpty ? null : _author.text.trim();
            widget.draft.seriesTitle =
                _series.text.trim().isEmpty ? null : _series.text.trim();
            Navigator.pop(context, widget.draft);
          },
          child: Text(l10n.mangaConfirmSave),
        ),
      ],
    );
  }
}
