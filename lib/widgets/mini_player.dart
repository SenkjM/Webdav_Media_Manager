import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

import 'package:provider/provider.dart';

import '../screens/player_screen.dart';
import '../screens/now_playing_queue_screen.dart';
import '../services/audio_player_service.dart';
import 'cover_art.dart';

/// Global mini play bar. Only shown when a local track is current —
/// never displays download / preparing progress.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final track = player.current;
    if (track == null) return const SizedBox.shrink();

    final playProgress =
        (player.duration != null && player.duration!.inMilliseconds > 0)
        ? player.position.inMilliseconds / player.duration!.inMilliseconds
        : 0.0;

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 12,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () {
            Navigator.of(
              context,
              rootNavigator: true,
            ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniProgressBar(
                progress: playProgress,
                enabled:
                    player.duration != null &&
                    player.duration!.inMilliseconds > 0,
                onSeek: (fraction) {
                  final total = player.duration;
                  if (total == null || total.inMilliseconds <= 0) return;
                  player.seek(
                    Duration(
                      milliseconds: (total.inMilliseconds * fraction)
                          .round()
                          .clamp(0, total.inMilliseconds),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    CoverArt(
                      // Mini bar may use thumb; full player never does.
                      path: track.coverPath,
                      size: 44,
                      borderRadius: 4,
                      icon: Icons.music_note,
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.2,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            player.error ??
                                track.displayArtistFor(
                                  AppLocalizations.of(context)!,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: player.error != null
                                      ? scheme.error
                                      : scheme.onSurfaceVariant,
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
                        color: scheme.primary,
                      ),
                      iconSize: 30,
                      onPressed: () => player.playPause(),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.playQueueTitle,
                      icon: Icon(
                        Icons.queue_music,
                        color: scheme.onSurface,
                      ),
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const NowPlayingQueueScreen(),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: scheme.onSurface,
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

/// The mini bar's progress line — **drag it to seek**.
///
/// Drag-only on purpose: a plain tap is left to the surrounding [InkWell],
/// which opens the full player, and nothing in the bar's thin look changes.
/// Only the touch strip grows ([_hitHeight]) so a finger has something to
/// grab; [onSeek] fires once, on release.
class _MiniProgressBar extends StatefulWidget {
  const _MiniProgressBar({
    required this.progress,
    required this.enabled,
    required this.onSeek,
  });

  /// 0..1, from the player's position / duration.
  final double progress;

  /// False while the duration is unknown — dragging then does nothing.
  final bool enabled;

  /// Called on release with the fraction the finger landed on.
  final ValueChanged<double> onSeek;

  static const double _hitHeight = 14;
  static const double _lineHeight = 2.5;
  static const double _thumbSize = 14;

  @override
  State<_MiniProgressBar> createState() => _MiniProgressBarState();
}

class _MiniProgressBarState extends State<_MiniProgressBar> {
  /// While set, the bar shows this instead of [widget.progress]. It tracks the
  /// finger during the drag, and is held after the release until the player
  /// reports a position near it (or [_settleTimeout] elapses) — otherwise the
  /// thumb snaps back to the old position while the seek is still in flight.
  double? _override;
  Timer? _settle;

  static const _settleTimeout = Duration(milliseconds: 900);
  static const _settleTolerance = 0.02;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MiniProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final held = _override;
    if (held != null && (widget.progress - held).abs() <= _settleTolerance) {
      // Already rebuilding — no setState needed.
      _settle?.cancel();
      _override = null;
    }
  }

  void _dragTo(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    setState(() => _override = (dx / width).clamp(0.0, 1.0));
  }

  void _release() {
    final value = _override;
    if (value == null) return;
    widget.onSeek(value);
    _settle?.cancel();
    _settle = Timer(_settleTimeout, () {
      if (!mounted) return;
      setState(() => _override = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = (_override ?? widget.progress).clamp(0.0, 1.0);
    final dragging = _override != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inset =
            (_MiniProgressBar._hitHeight - _MiniProgressBar._lineHeight) / 2;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _dragTo(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _dragTo(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: _release,
          child: SizedBox(
            height: _MiniProgressBar._hitHeight,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: inset,
                  bottom: inset,
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: _MiniProgressBar._lineHeight,
                    backgroundColor: Theme.of(context).colorScheme.outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (dragging)
                  Positioned(
                    left: (width * value) - _MiniProgressBar._thumbSize / 2,
                    top: 0,
                    child: Container(
                      width: _MiniProgressBar._thumbSize,
                      height: _MiniProgressBar._thumbSize,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
