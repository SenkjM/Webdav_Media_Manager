import '../l10n/generated/app_localizations.dart';
import '../utils/app_snack.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_settings.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Video playback settings (WebDAV streaming parameters, gestures, background
/// playback & picture-in-picture). Reachable from the main Settings list.
class VideoSettingsScreen extends StatefulWidget {
  const VideoSettingsScreen({super.key});

  @override
  State<VideoSettingsScreen> createState() => _VideoSettingsScreenState();
}

class _VideoSettingsScreenState extends State<VideoSettingsScreen> {
  late final TextEditingController _bufferController;

  @override
  void initState() {
    super.initState();
    _bufferController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bufferController.text =
          '${context.read<SettingsService>().videoBufferSizeMb}';
    });
  }

  @override
  void dispose() {
    _bufferController.dispose();
    super.dispose();
  }

  Future<void> _applyBuffer() async {
    final mb = int.tryParse(_bufferController.text.trim());
    if (mb == null) return;
    await context.read<SettingsService>().setVideoBufferSizeMb(mb);
    if (!mounted) return;
    _bufferController.text =
        '${context.read<SettingsService>().videoBufferSizeMb}';
    AppSnack.show(context, AppLocalizations.of(context)!.videoBufferSaved);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.videoPlayback)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppLocalizations.of(context)!.streamPlayback,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.videoStreamingHint,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.memory_outlined),
            title: Text(AppLocalizations.of(context)!.videoHardwareDecoding),
            subtitle: Text(
              AppLocalizations.of(context)!.videoHardwareDecodingHint,
            ),
            value: settings.videoHardwareDecoding,
            onChanged: (v) => settings.setVideoHardwareDecoding(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            title: Text(AppLocalizations.of(context)!.scanSubdirectories),
            subtitle: Text(AppLocalizations.of(context)!.videoScanSubdirsHint),
            value: settings.videoScanSubdirs,
            onChanged: (v) => settings.setVideoScanSubdirs(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: Text(AppLocalizations.of(context)!.videoBufferSize),
            subtitle: Text(
              AppLocalizations.of(context)!.videoBufferCurrent(
                settings.videoBufferSizeMb,
                SettingsService.minVideoBufferMb,
                SettingsService.maxVideoBufferMb,
              ),
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _bufferController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: AppLocalizations.of(context)!.videoBufferInput,
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _applyBuffer,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _applyBuffer,
                child: Text(AppLocalizations.of(context)!.apply),
              ),
            ],
          ),
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.videoGestures,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          _gestureTile(
            label: AppLocalizations.of(context)!.videoGestureLeftDoubleTap,
            value: settings.videoLeftDoubleTap,
            onChanged: (v) => settings.setVideoLeftDoubleTap(v),
          ),
          _gestureTile(
            label: AppLocalizations.of(context)!.videoGestureRightDoubleTap,
            value: settings.videoRightDoubleTap,
            onChanged: (v) => settings.setVideoRightDoubleTap(v),
          ),
          _gestureTile(
            label: AppLocalizations.of(context)!.videoGestureLongPress,
            value: settings.videoLongPress,
            onChanged: (v) => settings.setVideoLongPress(v),
          ),
          if (settings.videoLongPress == VideoGestureAction.toggleRate2x) ...[
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.speed),
              title: Text(AppLocalizations.of(context)!.videoLongPressRate),
              subtitle: Text(
                AppLocalizations.of(context)!.videoLongPressCurrent(
                  settings.videoLongPressRate.toStringAsFixed(2),
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in SettingsService.videoLongPressRatePresets)
                  ChoiceChip(
                    label: Text('${preset.toStringAsFixed(2)}×'),
                    selected:
                        (settings.videoLongPressRate - preset).abs() < 0.001,
                    onSelected: (_) => settings.setVideoLongPressRate(preset),
                  ),
              ],
            ),
            Slider(
              value: settings.videoLongPressRate.clamp(
                SettingsService.minVideoRate,
                SettingsService.maxVideoRate,
              ),
              min: SettingsService.minVideoRate,
              max: SettingsService.maxVideoRate,
              divisions: SettingsService.videoRateDivisions,
              label: '${settings.videoLongPressRate.toStringAsFixed(2)}×',
              onChanged: (v) => settings.setVideoLongPressRate(v),
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.slow_motion_video),
            title: Text(AppLocalizations.of(context)!.videoDefaultRate),
            subtitle: Text(
              AppLocalizations.of(context)!.videoDefaultRateCurrent(
                settings.videoLastRate.toStringAsFixed(2),
                SettingsService.minVideoRate.toStringAsFixed(1),
                SettingsService.maxVideoRate.toStringAsFixed(1),
              ),
            ),
          ),
          Slider(
            value: settings.videoLastRate.clamp(
              SettingsService.minVideoRate,
              SettingsService.maxVideoRate,
            ),
            min: SettingsService.minVideoRate,
            max: SettingsService.maxVideoRate,
            divisions: SettingsService.videoRateDivisions,
            label: '${settings.videoLastRate.toStringAsFixed(2)}×',
            onChanged: (v) => settings.setVideoLastRate(v),
          ),
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.videoSubtitles,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.videoSubtitleHint,
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SegmentedButton<VideoSubtitlePosition>(
            showSelectedIcon: false,
            segments: [
              for (final p in VideoSubtitlePosition.values)
                ButtonSegment(value: p, label: Text(p.label(AppLocalizations.of(context)!))),
            ],
            selected: {settings.videoSubtitlePosition},
            onSelectionChanged: (sel) =>
                settings.setVideoSubtitlePosition(sel.first),
          ),
          if (settings.videoSubtitlePosition ==
              VideoSubtitlePosition.visible) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.format_size),
              title: Text(AppLocalizations.of(context)!.videoSubtitleSize),
              subtitle: Text(
                AppLocalizations.of(context)!.videoSubtitleSizeCurrent(
                  settings.videoSubtitleFontSize.toStringAsFixed(0),
                  SettingsService.minVideoSubtitleFontSize.toStringAsFixed(0),
                  SettingsService.maxVideoSubtitleFontSize.toStringAsFixed(0),
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final preset
                    in SettingsService.videoSubtitleFontSizePresets)
                  ChoiceChip(
                    label: Text(preset.toStringAsFixed(0)),
                    selected:
                        (settings.videoSubtitleFontSize - preset).abs() < 0.001,
                    onSelected: (_) =>
                        settings.setVideoSubtitleFontSize(preset),
                  ),
              ],
            ),
            Slider(
              value: settings.videoSubtitleFontSize.clamp(
                SettingsService.minVideoSubtitleFontSize,
                SettingsService.maxVideoSubtitleFontSize,
              ),
              min: SettingsService.minVideoSubtitleFontSize,
              max: SettingsService.maxVideoSubtitleFontSize,
              divisions: 30,
              label: '${settings.videoSubtitleFontSize.toStringAsFixed(0)} sp',
              onChanged: (v) => settings.setVideoSubtitleFontSize(v),
            ),
          ],
          const Divider(height: 40),
          Text(
            AppLocalizations.of(context)!.videoPlaybackBehavior,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.headset_outlined),
            title: Text(AppLocalizations.of(context)!.videoBackgroundPlayback),
            subtitle: Text(
              AppLocalizations.of(context)!.videoBackgroundPlaybackHint,
            ),
            value: settings.videoBackgroundPlayback,
            onChanged: (v) => settings.setVideoBackgroundPlayback(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: Text(AppLocalizations.of(context)!.videoPip),
            subtitle: Text(AppLocalizations.of(context)!.videoPipHint),
            value: settings.videoPipEnabled,
            onChanged: (v) => settings.setVideoPipEnabled(v),
          ),
        ],
      ),
    );
  }

  Widget _gestureTile({
    required String label,
    required VideoGestureAction value,
    required ValueChanged<VideoGestureAction> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.touch_app_outlined),
      title: Text(label),
      trailing: DropdownButton<VideoGestureAction>(
        value: value,
        items: [
          for (final a in VideoGestureAction.values)
            DropdownMenuItem(value: a, child: Text(a.label(AppLocalizations.of(context)!))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
