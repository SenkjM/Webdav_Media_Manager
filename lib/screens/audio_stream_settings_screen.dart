import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('音频流式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '流式播放',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '音乐不下载到本地，直接从网盘边听边传。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.music_note_outlined),
            title: const Text('流式传输音乐'),
            subtitle: const Text('打开后音乐的文件动作里可以选「流式传输（音乐）」。关掉时该动作会被退回默认。'),
            value: settings.audioStreamingEnabled,
            onChanged: (v) => settings.setAudioStreamingEnabled(v),
          ),
          const Divider(height: 40),
          Text(
            '列表扫描',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '决定流式播放的「上一首 / 下一首」列表里都有什么。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            title: const Text('搜索子目录'),
            subtitle: const Text('打开：当前目录及其所有子目录里的音频都进列表。关闭：只列当前这一层。'),
            value: settings.audioScanSubdirs,
            onChanged: (v) => settings.setAudioScanSubdirs(v),
          ),
        ],
      ),
    );
  }
}
