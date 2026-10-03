import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';
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
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: scheme.surface,
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
                Divider(height: 1, color: Theme.of(ctx).colorScheme.outline),
                for (final row in rows)
                  ListTile(
                    leading: Icon(
                      selectedKey == row.keyId
                          ? Icons.check_circle
                          : Icons.subtitles_outlined,
                      color: selectedKey == row.keyId
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      row.title.isEmpty
                          ? l10n.videoSubtitleExternal
                          : row.title,
                    ),
                    trailing: row.formatTag == null
                        ? null
                        : _FormatTag(row.formatTag!),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await onSelect(row.keyId);
                    },
                  ),
                Divider(height: 1, color: Theme.of(ctx).colorScheme.outline),
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
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
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
                const _SubtitleSizeControls(),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Same presets and range as video settings. Writes the shared setting so the
/// settings screen and this sheet stay in sync.
class _SubtitleSizeControls extends StatelessWidget {
  const _SubtitleSizeControls();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final size = settings.videoSubtitleFontSize;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.videoSubtitleSize),
          const SizedBox(height: 4),
          Text(
            l10n.videoSubtitleSizeCurrent(
              SettingsService.maxVideoSubtitleFontSize.toStringAsFixed(0),
              SettingsService.minVideoSubtitleFontSize.toStringAsFixed(0),
              size.toStringAsFixed(0),
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in SettingsService.videoSubtitleFontSizePresets)
                ChoiceChip(
                  label: Text(preset.toStringAsFixed(0)),
                  selected: (size - preset).abs() < 0.001,
                  onSelected: (_) => settings.setVideoSubtitleFontSize(preset),
                ),
            ],
          ),
          Slider(
            value: size.clamp(
              SettingsService.minVideoSubtitleFontSize,
              SettingsService.maxVideoSubtitleFontSize,
            ),
            min: SettingsService.minVideoSubtitleFontSize,
            max: SettingsService.maxVideoSubtitleFontSize,
            divisions: 30,
            label: '${size.toStringAsFixed(0)} sp',
            onChanged: (v) => settings.setVideoSubtitleFontSize(v),
          ),
        ],
      ),
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outline),
      ),
      child: Text(
        format.toLowerCase(),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
