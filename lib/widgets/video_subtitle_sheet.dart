import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/subtitle_encoding.dart';
import '../widgets/app_bottom_sheet.dart';

class VideoSubtitleSheetRow {
  const VideoSubtitleSheetRow({
    required this.keyId,
    required this.title,
    this.formatTag,
  });

  final String keyId;
  final String title;
  final String? formatTag;
}

Future<void> showVideoSubtitleSheet({
  required BuildContext context,
  required List<VideoSubtitleSheetRow> rows,
  required String? selectedKey,
  required SubtitleEncodingChoice encoding,
  required Future<void> Function(String keyId) onSelect,
  required Future<void> Function(SubtitleEncodingChoice encoding) onEncoding,
  required Future<void> Function() onImportRemote,
  required Future<void> Function() onImportLocal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: AppBottomSheet.shape,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AppBottomSheet(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text(l10n.videoSubtitlePick),
                  subtitle: Text(l10n.videoSubtitleEncodingHint),
                ),
                const Divider(height: 1, color: AppColors.divider),
                for (final row in rows)
                  ListTile(
                    leading: Icon(
                      selectedKey == row.keyId
                          ? Icons.check_circle
                          : Icons.subtitles_outlined,
                      color: selectedKey == row.keyId
                          ? AppColors.accent
                          : null,
                    ),
                    title: Text(
                      row.title.isEmpty ? l10n.videoSubtitleExternal : row.title,
                    ),
                    trailing: row.formatTag == null
                        ? null
                        : _FormatTag(row.formatTag!),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await onSelect(row.keyId);
                    },
                  ),
                const Divider(height: 1, color: AppColors.divider),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(l10n.videoSubtitleImportRemote),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await onImportRemote();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(l10n.videoSubtitleImportLocal),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await onImportLocal();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    l10n.videoSubtitleEncoding,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in SubtitleEncodingChoice.values)
                        ChoiceChip(
                          label: Text(_encodingLabel(l10n, choice)),
                          selected: encoding == choice,
                          onSelected: (_) async {
                            setLocal(() {});
                            Navigator.pop(ctx);
                            await onEncoding(choice);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _encodingLabel(AppLocalizations l10n, SubtitleEncodingChoice choice) {
  return switch (choice) {
    SubtitleEncodingChoice.auto => l10n.videoSubtitleEncodingAuto,
    SubtitleEncodingChoice.utf8 => 'UTF-8',
    SubtitleEncodingChoice.utf16le => 'UTF-16 LE',
    SubtitleEncodingChoice.utf16be => 'UTF-16 BE',
    SubtitleEncodingChoice.gbk => 'GBK',
    SubtitleEncodingChoice.gb18030 => 'GB18030',
    SubtitleEncodingChoice.big5 => 'Big5',
  };
}

class _FormatTag extends StatelessWidget {
  const _FormatTag(this.format);

  final String format;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        format.toLowerCase(),
        style: const TextStyle(fontSize: 10, color: AppColors.secondaryText),
      ),
    );
  }
}
