import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_player_service.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final track = player.current;
    final duration = player.duration ?? Duration.zero;
    final position = player.position;
    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
    final posMs = position.inMilliseconds.clamp(0, maxMs);

    return Scaffold(
      appBar: AppBar(title: const Text('正在播放')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                player.preparing ? Icons.downloading : Icons.album,
                size: 96,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              track?.displayTitle ?? '未选择曲目',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              player.preparing
                  ? '正在下载到本地缓存…'
                  : (player.error ?? track?.displayArtist ?? ''),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: player.error != null
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
            ),
            if (track?.remotePath != null) ...[
              const SizedBox(height: 4),
              Text(
                track!.remotePath,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Spacer(),
            Slider(
              value: posMs.toDouble(),
              max: maxMs.toDouble(),
              onChanged: duration.inMilliseconds > 0
                  ? (v) => player.seek(Duration(milliseconds: v.round()))
                  : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(position)),
                Text(_fmt(duration)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  onPressed: () => player.skipPrevious(),
                  icon: const Icon(Icons.skip_previous),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                  ),
                  onPressed: track == null ? null : () => player.playPause(),
                  child: Icon(
                    player.playing ? Icons.pause : Icons.play_arrow,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  onPressed: () => player.skipNext(),
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
