import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/player_screen.dart';
import '../services/audio_player_service.dart';

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
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    player.preparing
                        ? Icons.downloading
                        : Icons.music_note,
                    color: Theme.of(context).colorScheme.primary,
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          player.preparing
                              ? '下载中…'
                              : (player.error ?? track.displayArtist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      player.playing ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: () => player.playPause(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: () => player.skipNext(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
