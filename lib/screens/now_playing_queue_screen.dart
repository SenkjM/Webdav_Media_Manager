import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/webdav_item.dart';
import '../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';

/// Ephemeral now-playing queue viewer. Does NOT auto-sync to saved playlists.
class NowPlayingQueueScreen extends StatelessWidget {
  const NowPlayingQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final queue = player.queue;
    final currentIndex = player.index;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(queue.isEmpty ? '当前播放列表' : '当前播放列表（${queue.length}）'),
      ),
      body: queue.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '当前没有播放队列。\n从音乐库或网络库开始播放后会出现在此。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              ),
            )
          : ListView.builder(
              itemCount: queue.length,
              itemBuilder: (context, i) {
                final TrackInfo t = queue[i];
                final playing = i == currentIndex;
                return ListTile(
                  selected: playing,
                  selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
                  leading: CoverArt(
                    path: t.coverPath,
                    size: 44,
                    borderRadius: 4,
                    icon: playing ? Icons.equalizer : Icons.music_note,
                  ),
                  title: Text(
                    t.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
                      color: playing ? AppColors.accent : AppColors.primaryText,
                    ),
                  ),
                  subtitle: Text(
                    [
                      t.displayArtist,
                      if (t.displayAlbum.isNotEmpty) t.displayAlbum,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                  trailing: playing
                      ? const Icon(Icons.graphic_eq, color: AppColors.accent)
                      : Text(
                          '${i + 1}',
                          style: const TextStyle(color: AppColors.mutedText),
                        ),
                  onTap: () async {
                    await player.playTrack(t, playlist: queue);
                  },
                );
              },
            ),
    );
  }
}
