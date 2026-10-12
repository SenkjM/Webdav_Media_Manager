import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/webdav_item.dart';
import '../theme/app_theme.dart';
import 'track_status_dot.dart';

class TrackStatusChip extends StatelessWidget {
  const TrackStatusChip({super.key, required this.state, this.progress});

  final TrackUiState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    // Network-browser "never touched": no badge.
    // ready / streamable: status dots on the row; no text chip.
    if (state == TrackUiState.remote ||
        state == TrackUiState.streamable ||
        state == TrackUiState.ready) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (state) {
      TrackUiState.remote => ('', scheme.outline, Icons.circle_outlined),
      TrackUiState.streamable => ('', scheme.primary, Icons.stream),
      TrackUiState.ready => ('', cachedStatusDotColor(context), Icons.check_circle_outline),
      TrackUiState.remoteMissing => (
        l10n.trackStateRemoteMissing,
        AppColors.error,
        Icons.error_outline,
      ),
      TrackUiState.queued => (
        l10n.trackStateQueued,
        scheme.secondary,
        Icons.schedule,
      ),
      TrackUiState.downloading => (
        l10n.trackStateDownloading,
        scheme.primary,
        Icons.downloading,
      ),
      TrackUiState.playing => (
        '', // icon-only
        scheme.primary,
        Icons.equalizer,
      ),
      TrackUiState.error => (
        l10n.trackStateError,
        AppColors.error,
        Icons.error_outline,
      ),
    };

    // Playing: compact icon chip, no text.
    if (state == TrackUiState.playing) {
      return Chip(
        label: Icon(icon, size: 16, color: color),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: color.withValues(alpha: 0.14),
        side: BorderSide.none,
      );
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        state == TrackUiState.downloading && progress != null
            ? '$label ${(progress! * 100).toStringAsFixed(0)}%'
            : label,
        style: TextStyle(fontSize: 12, color: color),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: color.withValues(alpha: 0.14),
      side: BorderSide.none,
    );
  }
}
