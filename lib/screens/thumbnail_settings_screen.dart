import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/app_state.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/cover_image.dart';

/// 封面缩略图边长。自定义尺寸要手填，所以从设置主页收进二级页。
class ThumbnailSettingsScreen extends StatefulWidget {
  const ThumbnailSettingsScreen({super.key});

  @override
  State<ThumbnailSettingsScreen> createState() => _ThumbnailSettingsScreenState();
}

class _ThumbnailSettingsScreenState extends State<ThumbnailSettingsScreen> {
  late final TextEditingController _coverSizeController;
  String? _coverUiMode;

  @override
  void initState() {
    super.initState();
    _coverSizeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsService>();
      final edge = settings.coverThumbSizePx;
      if (edge != coverThumbSize && edge != coverThumbSizeLarge) {
        _coverSizeController.text = '$edge';
      }
    });
  }

  @override
  void dispose() {
    _coverSizeController.dispose();
    super.dispose();
  }

  String _coverPresetKey(int edge) {
    if (edge == coverThumbSize) return '100';
    if (edge == coverThumbSizeLarge) return '300';
    return 'custom';
  }

  String _coverMode(SettingsService settings) =>
      _coverUiMode ?? _coverPresetKey(settings.coverThumbSizePx);

  Future<void> _applyCustomCoverSize() async {
    final parsed = int.tryParse(_coverSizeController.text.trim());
    if (parsed == null) return;
    await context.read<AppState>().setCoverThumbSize(parsed);
    if (!mounted) return;
    setState(() => _coverUiMode = 'custom');
    final edge = context.read<SettingsService>().coverThumbSizePx;
    if (edge != coverThumbSize && edge != coverThumbSizeLarge) {
      _coverSizeController.text = '$edge';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(l10n.settingsThumbnails)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.coverThumbSize,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(l10n.coverThumbHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: '100', label: Text('100×100')),
              const ButtonSegment(value: '300', label: Text('300×300')),
              ButtonSegment(value: 'custom', label: Text(l10n.cacheCustom)),
            ],
            selected: {_coverMode(settings)},
            onSelectionChanged: (sel) async {
              final v = sel.first;
              if (v == '100') {
                setState(() => _coverUiMode = null);
                await context.read<AppState>().setCoverThumbSize(coverThumbSize);
              } else if (v == '300') {
                setState(() => _coverUiMode = null);
                await context.read<AppState>().setCoverThumbSize(coverThumbSizeLarge);
              } else {
                setState(() {
                  _coverUiMode = 'custom';
                  if (_coverSizeController.text.trim().isEmpty) {
                    _coverSizeController.text = '${settings.coverThumbSizePx}';
                  }
                });
              }
            },
          ),
          if (_coverMode(settings) == 'custom') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _coverSizeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.coverSize,
                      border: const OutlineInputBorder(),
                      helperText: '$minCoverThumbSize–$maxCoverThumbSize',
                    ),
                    onEditingComplete: _applyCustomCoverSize,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _applyCustomCoverSize,
                  child: Text(l10n.apply),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            l10n.coverThumbSizeCurrent('${settings.coverThumbSizePx}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
