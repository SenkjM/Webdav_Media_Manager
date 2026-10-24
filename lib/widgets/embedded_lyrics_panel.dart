import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../utils/stream_lyrics.dart';

/// Displays embedded plain text or LRC lyrics and follows [position].
///
/// The player currently does not expose its fetched embedded-lyrics payload;
/// this widget deliberately has no playback dependency so that the lyrics data
/// path can be added without reviving the obsolete stream-only player screen.
class EmbeddedLyricsPanel extends StatefulWidget {
  const EmbeddedLyricsPanel({
    super.key,
    required this.lyrics,
    required this.position,
  });

  final String lyrics;
  final Duration position;

  @override
  State<EmbeddedLyricsPanel> createState() => _EmbeddedLyricsPanelState();
}

class _EmbeddedLyricsPanelState extends State<EmbeddedLyricsPanel> {
  final _scroll = ScrollController();
  int _lastActive = -2;

  @override
  void didUpdateWidget(covariant EmbeddedLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position ||
        oldWidget.lyrics != widget.lyrics) {
      _scrollToActive();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToActive() {
    final lines = parseTimedLyrics(widget.lyrics);
    if (lines == null || !_scroll.hasClients) return;
    final active = lyricIndexAt(lines, widget.position);
    if (active == _lastActive) return;
    _lastActive = active;
    if (active < 0) return;
    final target = (active * 44.0 - 88.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = parseTimedLyrics(widget.lyrics);
    if (lines == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lyricsSourceEmbedded,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(widget.lyrics),
        ],
      );
    }
    final active = lyricIndexAt(lines, widget.position);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.lyricsSourceEmbedded,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.builder(
            controller: _scroll,
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final isActive = index == active;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  lines[index].text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
