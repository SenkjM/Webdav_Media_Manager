import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';

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
    final cover = track?.coverPath;
    final artSize = MediaQuery.sizeOf(context).width * 0.72;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: CoverBackdrop(
        path: cover,
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: const Text('正在播放'),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      CoverArt(
                        path: cover,
                        size: artSize.clamp(200.0, 320.0),
                        borderRadius: 8,
                        icon: player.preparing
                            ? Icons.downloading
                            : Icons.album,
                      ),
                      const SizedBox(height: 36),
                      Text(
                        track?.displayTitle ?? '未选择曲目',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.onDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: 0.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        player.preparing
                            ? '正在下载到本地缓存…'
                            : (player.error ?? track?.displayArtist ?? ''),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: player.error != null
                              ? AppColors.error
                              : AppColors.secondaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Builder(builder: (context) {
                        final album = track?.album?.trim();
                        if (album == null || album.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            album,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }),
                      const Spacer(flex: 3),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 9,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 18,
                          ),
                        ),
                        child: Slider(
                          value: posMs.toDouble(),
                          max: maxMs.toDouble(),
                          onChanged: duration.inMilliseconds > 0
                              ? (v) => player.seek(
                                    Duration(milliseconds: v.round()),
                                  )
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(position),
                              style: const TextStyle(
                                color: AppColors.mutedText,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              _fmt(duration),
                              style: const TextStyle(
                                color: AppColors.mutedText,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 42,
                            color: AppColors.onDark,
                            onPressed: () => player.skipPrevious(),
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          const SizedBox(width: 20),
                          Material(
                            color: AppColors.accent,
                            shape: const CircleBorder(),
                            elevation: 4,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: track == null
                                  ? null
                                  : () => player.playPause(),
                              child: SizedBox(
                                width: 72,
                                height: 72,
                                child: Icon(
                                  player.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 42,
                                  color: AppColors.onAccent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            iconSize: 42,
                            color: AppColors.onDark,
                            onPressed: () => player.skipNext(),
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
