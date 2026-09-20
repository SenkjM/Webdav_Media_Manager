import 'package:flutter/material.dart';

import '../models/webdav_item.dart';
import '../theme/app_theme.dart';

class TrackStatusChip extends StatelessWidget {
  const TrackStatusChip({super.key, required this.state, this.progress});

  final TrackUiState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    // Undownloaded / never queued: no badge (filename only).
    if (state == TrackUiState.remote) {
      return const SizedBox.shrink();
    }

    final (label, color, icon) = switch (state) {
      TrackUiState.remote => ('', AppColors.mutedText, Icons.circle_outlined),
      TrackUiState.queued => ('排队', AppColors.mutedText, Icons.schedule),
      TrackUiState.downloading => (
          '下载中',
          AppColors.accent,
          Icons.downloading,
        ),
      TrackUiState.ready => ('就绪', const Color(0xFF66BB6A), Icons.check_circle_outline),
      TrackUiState.playing => ('播放中', AppColors.accent, Icons.equalizer),
      TrackUiState.error => ('错误', AppColors.error, Icons.error_outline),
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
