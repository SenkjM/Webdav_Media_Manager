import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 音频流式设置：音乐要不要走流式传输，以及流式队列的扫描范围。
///
/// 与「视频播放设置」并列，因为两边各有一份**搜索子目录**开关：
/// 音频通常按专辑分目录、视频按剧集分目录，需要按各自的情况调。
class AudioStreamSettingsScreen extends StatelessWidget {
  const AudioStreamSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
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
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
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
          const Divider(height: 40),
          Text(
            l10n.scanList,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.scanListHint,
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
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
