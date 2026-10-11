import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/webdav_item.dart';
import '../theme/app_theme.dart';

class TrackStatusChip extends StatelessWidget {
  const TrackStatusChip({super.key, required this.state, this.progress});

  final TrackUiState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    // Network-browser "never touched": no badge.
    if (state == TrackUiState.remote) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Cached / streamable / downloading use theme normal colors — not grey / warning red.
    final (label, color, icon) = switch (state) {
      TrackUiState.remote => ('', scheme.outline, Icons.circle_outlined),
      TrackUiState.streamable => (
        l10n.trackStateStreamable,
        scheme.primary,
        Icons.stream,
      ),
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
      TrackUiState.ready => (
        l10n.trackStateReady,
        scheme.tertiary,
        Icons.check_circle_outline,
      ),
      TrackUiState.playing => (
        l10n.trackStatePlaying,
        scheme.primary,
        Icons.equalizer,
      ),
      TrackUiState.error => (
        l10n.trackStateError,
        AppColors.error,
        Icons.error_outline,
      ),
    };

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
