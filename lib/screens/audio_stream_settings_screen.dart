import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 音频流式设置：音乐要不要走流式传输、同目录封面，以及预载窗口。
///
/// 与「视频播放设置」并列，因为两边各有一份**搜索子目录**开关：
/// 音频通常按专辑分目录、视频按剧集分目录，需要按各自的情况调。
class AudioStreamSettingsScreen extends StatefulWidget {
  const AudioStreamSettingsScreen({super.key});

  @override
  State<AudioStreamSettingsScreen> createState() =>
      _AudioStreamSettingsScreenState();
}

class _AudioStreamSettingsScreenState extends State<AudioStreamSettingsScreen> {
  final TextEditingController _names = TextEditingController();
  var _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    _names.text = context.read<SettingsService>().audioStreamSidecarNames;
  }

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l10n.audioStreamingTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.streamPlayback,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.streamPlaybackHint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.music_note_outlined),
            title: Text(l10n.streamMusic),
            subtitle: Text(l10n.streamMusicHint),
            value: settings.audioStreamingEnabled,
            onChanged: (v) => settings.setAudioStreamingEnabled(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.image_outlined),
            title: Text(l10n.streamSidecarCover),
            subtitle: Text(l10n.streamSidecarCoverHint),
            value: settings.audioStreamSidecarCover,
            onChanged: (v) => settings.setAudioStreamSidecarCover(v),
          ),
          TextField(
            controller: _names,
            decoration: InputDecoration(
              labelText: l10n.streamSidecarNames,
              helperText: l10n.streamSidecarNamesHint,
              helperMaxLines: 4,
            ),
            onChanged: (value) => settings.setAudioStreamSidecarNames(value),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.streamPrefetchHint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.skip_previous),
            title: Text(l10n.streamPrefetchBackward),
            subtitle: Text('${settings.audioStreamPrefetchBackward}'),
          ),
          Slider(
            min: SettingsService.minStreamPrefetch.toDouble(),
            max: SettingsService.maxStreamPrefetch.toDouble(),
            divisions:
                SettingsService.maxStreamPrefetch -
                SettingsService.minStreamPrefetch,
            value: settings.audioStreamPrefetchBackward.toDouble(),
            label: '${settings.audioStreamPrefetchBackward}',
            onChanged: (v) =>
                settings.setAudioStreamPrefetchBackward(v.round()),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.skip_next),
            title: Text(l10n.streamPrefetchForward),
            subtitle: Text('${settings.audioStreamPrefetchForward}'),
          ),
          Slider(
            min: SettingsService.minStreamPrefetch.toDouble(),
            max: SettingsService.maxStreamPrefetch.toDouble(),
            divisions:
                SettingsService.maxStreamPrefetch -
                SettingsService.minStreamPrefetch,
            value: settings.audioStreamPrefetchForward.toDouble(),
            label: '${settings.audioStreamPrefetchForward}',
            onChanged: (v) => settings.setAudioStreamPrefetchForward(v.round()),
          ),
          const Divider(height: 40),
          Text(
            l10n.scanList,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.scanListHint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            title: Text(l10n.scanSubdirectories),
            subtitle: Text(l10n.scanSubdirectoriesHint),
            value: settings.audioScanSubdirs,
            onChanged: (v) => settings.setAudioScanSubdirs(v),
          ),
        ],
      ),
    );
  }
}
