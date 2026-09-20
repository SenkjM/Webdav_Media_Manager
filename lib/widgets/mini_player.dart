import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/player_screen.dart';
import '../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final track = player.current;
    if (track == null) return const SizedBox.shrink();

    final progress = (player.duration != null &&
            player.duration!.inMilliseconds > 0)
        ? player.position.inMilliseconds / player.duration!.inMilliseconds
        : 0.0;

    return Material(
      color: AppColors.elevated,
      elevation: 12,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 2.5,
                backgroundColor: AppColors.elevatedHigh,
                color: AppColors.accent,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    CoverArt(
                      path: track.coverPath,
                      size: 44,
                      borderRadius: 4,
                      icon: player.preparing
                          ? Icons.downloading
                          : Icons.music_note,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.onDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            player.preparing
                                ? '下载中…'
                                : (player.error ?? track.displayArtist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: player.error != null
                                  ? AppColors.error
                                  : AppColors.secondaryText,
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: AppColors.accent,
                      ),
                      iconSize: 30,
                      onPressed: () => player.playPause(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: AppColors.onDark,
                      ),
                      onPressed: () => player.skipNext(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
